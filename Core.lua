--[[
	TTS-ClassicAPI - Core
	Speech queue, text cleanup, saved variables, event dispatch and slash commands.
	Requires the ClassicAPI DLL (C_VoiceChat / C_TTSSettings / C_Timer, Lua 5.1 syntax, modern script args).
]]

local addonName, ns = ...
addonName = addonName or "TTS-ClassicAPI"
ns = ns or {}
TTSClassicAPI = ns

ns.name = addonName
ns.version = "1.0.0"

local LOCAL_PLAYBACK = 1

local tinsert, tremove = table.insert, table.remove
local strlower, strgsub, strsub, strfind = string.lower, string.gsub, string.sub, string.find

---------------------------------------------------------------------------
-- Output helpers
---------------------------------------------------------------------------
function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffTTS|r: " .. tostring(msg))
end

function ns.Debug(msg)
	if ns.db and ns.db.global.debug then
		DEFAULT_CHAT_FRAME:AddMessage("|cff888888TTS debug:|r " .. tostring(msg))
	end
end

function ns.HasTTS()
	return C_VoiceChat ~= nil and C_VoiceChat.SpeakText ~= nil and C_TTSSettings ~= nil
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
ns.GLOBAL_DEFAULTS = {
	enabled = true,
	maxQueue = 8,          -- drop oldest queued lines beyond this
	dedupeSeconds = 6,     -- ignore identical text spoken within N seconds
	maxLength = 500,       -- truncate very long lines (characters)
	readOwn = false,       -- read your own chat messages
	skipUnknownLanguage = true, -- skip chat in languages the character doesn't speak
	expandAbbrev = true,   -- "lfm" -> "looking for more"
	stopOnClose = true,    -- stop quest/gossip/book reading when the window closes
	muteInCombat = false,  -- silence everything except "interrupt" sources in combat
	debug = false,
	muted = {},            -- [lowercase name] = true
}

-- Registry filled by Sources.lua: ordered list + key lookup.
ns.sources = {}
ns.sourceByKey = {}
ns.categories = {}

function ns.RegisterSource(def)
	assert(def.key and def.events and def.handler, "bad source definition")
	tinsert(ns.sources, def)
	ns.sourceByKey[def.key] = def
	local found
	for _, c in ipairs(ns.categories) do
		if c == def.category then found = true break end
	end
	if not found then tinsert(ns.categories, def.category) end
end

local function fillDefaults(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			fillDefaults(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

function ns.SourceDefaults(def)
	return {
		enabled = def.default and true or false,
		template = def.template,
		interrupt = def.interrupt and true or false,
		noCombat = false,
		cooldown = def.cooldown or 0,   -- seconds between lines from this source; 0 = off
		voice = nil,   -- voice display name; nil = global default
		rate = nil,    -- nil = global default
		volume = nil,  -- nil = global default
	}
end

function ns.ResetSource(key)
	local def = ns.sourceByKey[key]
	if def then
		ns.db.sources[key] = ns.SourceDefaults(def)
		ns.UpdateEventRegistrations()
	end
end

local function initDB()
	TTSClassicAPIDB = TTSClassicAPIDB or {}
	local db = TTSClassicAPIDB
	db.global = db.global or {}
	fillDefaults(db.global, ns.GLOBAL_DEFAULTS)
	db.presets = db.presets or {}   -- [name] = snapshot of db.sources
	db.sources = db.sources or {}
	for _, def in ipairs(ns.sources) do
		local s = db.sources[def.key]
		if type(s) ~= "table" then
			db.sources[def.key] = ns.SourceDefaults(def)
		else
			local d = ns.SourceDefaults(def)
			for _, k in ipairs({ "enabled", "template", "interrupt", "noCombat", "cooldown" }) do
				if s[k] == nil then s[k] = d[k] end
			end
		end
	end
	ns.db = db
end

---------------------------------------------------------------------------
-- Voices
---------------------------------------------------------------------------
ns.voices = {}

function ns.RefreshVoiceList()
	if not ns.HasTTS() or ns.refreshingVoices then return end
	ns.refreshingVoices = true
	wipe(ns.voices)
	local ok, list = pcall(C_VoiceChat.GetTtsVoices)
	if ok and type(list) == "table" then
		for _, v in ipairs(list) do
			tinsert(ns.voices, { voiceID = v.voiceID, name = v.name })
		end
		table.sort(ns.voices, function(a, b) return a.voiceID < b.voiceID end)
	end
	ns.refreshingVoices = nil
	if ns.OnVoicesUpdated then ns.OnVoicesUpdated() end
end

-- "Microsoft Zira Desktop - English (United States)" -> "Zira"
function ns.ShortVoiceName(name)
	if not name or name == "" then return "?" end
	local s = name
	s = (strgsub(s, " %- .*$", ""))
	s = (strgsub(s, "^Microsoft ", ""))
	s = (strgsub(s, " Desktop$", ""))
	return s
end

function ns.VoiceIndexByName(name)
	if not name then return nil end
	for i, v in ipairs(ns.voices) do
		if v.name == name then return i end
	end
	return nil
end

function ns.VoiceIndexByID(id)
	for i, v in ipairs(ns.voices) do
		if v.voiceID == id then return i end
	end
	return nil
end

-- Per-source voices are stored by name so they survive voice installs/reorders.
function ns.ResolveVoiceID(name)
	local i = ns.VoiceIndexByName(name)
	if i then return ns.voices[i].voiceID end
	return C_TTSSettings.GetSpeechVoiceID() or 0
end

---------------------------------------------------------------------------
-- Text cleanup
---------------------------------------------------------------------------
ns.ABBREVIATIONS = {
	lf = "looking for", lfg = "looking for group", lfm = "looking for more",
	lf1m = "looking for one more", lf2m = "looking for two more", lf3m = "looking for three more",
	wts = "want to sell", wtb = "want to buy", wtt = "want to trade",
	brb = "be right back", afk = "away", bbl = "be back later", omw = "on my way",
	ty = "thank you", thx = "thanks", tyvm = "thank you very much", np = "no problem",
	pls = "please", plz = "please", ppl = "people", gz = "grats", gratz = "grats",
	idk = "I don't know", imo = "in my opinion", btw = "by the way", atm = "at the moment",
	gl = "good luck", hf = "have fun", gg = "good game", rdy = "ready",
	mt = "main tank", ot = "off tank", dps = "D P S", aoe = "A O E", cc = "crowd control",
	inv = "invite", pst = "please send tell", whs = "whisper", ofc = "of course",
	sry = "sorry", u = "you", ur = "your", r = "are", k = "okay", kk = "okay",
	ud = "Undercity", sw = "Stormwind", og = "Orgrimmar", tb = "Thunder Bluff",
	sm = "Scarlet Monastery", rfc = "Ragefire Chasm", wc = "Wailing Caverns", sfk = "Shadowfang Keep",
	bfd = "Blackfathom Deeps", rfk = "Razorfen Kraul", rfd = "Razorfen Downs", zf = "Zul'Farrak",
	st = "Sunken Temple", brd = "Blackrock Depths", lbrs = "Lower Blackrock Spire",
	ubrs = "Upper Blackrock Spire", strat = "Stratholme", scholo = "Scholomance", dm = "Dire Maul",
	mc = "Molten Core", bwl = "Blackwing Lair", ony = "Onyxia", zg = "Zul'Gurub", aq = "Ahn'Qiraj",
	naxx = "Naxxramas", kara = "Karazhan", hc = "hardcore",
}

local RAID_ICON_WORDS = {
	"star", "circle", "diamond", "triangle", "moon", "square", "cross", "x", "skull",
}

-- Must return the original word when there's no match: on the 1.12 Lua 5.0 VM
-- a nil from a gsub callback replaces the match with "" instead of keeping it.
local function expandWord(w)
	return ns.ABBREVIATIONS[strlower(w)] or w
end

function ns.CleanText(text)
	if type(text) ~= "string" then return "" end
	local s = text
	s = strgsub(s, "|c%x%x%x%x%x%x%x%x", "")
	s = strgsub(s, "|r", "")
	s = strgsub(s, "|H.-|h%[?(.-)%]?|h", "%1")   -- [Item Link] -> Item Link
	s = strgsub(s, "|T.-|t", "")
	s = strgsub(s, "|A.-|a", "")
	s = strgsub(s, "|n", ". ")
	-- Don't spell out URLs character by character.
	s = strgsub(s, "https?://%S+", "link")
	s = strgsub(s, "www%.%S+", "link")
	-- SAPI reads "3/10" as a date ("March tenth"); quest progress wants "3 of 10".
	s = strgsub(s, "(%d+)/(%d+)", "%1 of %2")
	s = strgsub(s, "{[Rr][Tt]%d}", "")
	for _, w in ipairs(RAID_ICON_WORDS) do
		s = strgsub(s, "{" .. w .. "}", "")
	end
	-- SAPI may parse XML-ish markup; keep it plain.
	s = strgsub(s, "[<>]", " ")
	s = strgsub(s, "\r?\n+", ". ")
	-- Collapse character spam: "!!!!!!" -> "!", "hahahahahaha" left alone.
	s = strgsub(s, "([%p])%1%1+", "%1")
	s = strgsub(s, "%s+", " ")
	s = strgsub(s, "^[%s%.,:;]+", "")
	s = strgsub(s, "[%s,:;]+$", "")
	s = strgsub(s, "%s+([%.,!%?])", "%1")
	s = strgsub(s, "%.%s*%.", ".")
	return s
end

function ns.ExpandAbbreviations(s)
	return (strgsub(s, "([%w']+)", expandWord))
end

-- "{name} says: {msg}" + tokens -> text. Unknown/empty tokens vanish.
function ns.Format(template, tokens)
	if not template or template == "" then template = "{msg}" end
	local out = strgsub(template, "{(%w+)}", function(k)
		local v = tokens[k]
		if v == nil then return "" end
		return tostring(v)
	end)
	return out
end

---------------------------------------------------------------------------
-- Speech queue
---------------------------------------------------------------------------
local queue = {}
local current          -- item being spoken
local pendingStart     -- waiting for VOICE_CHAT_TTS_PLAYBACK_STARTED of `current`
local currentUtt       -- utteranceID of `current`
local staleUtt = {}    -- utterance IDs we abandoned (stop/skip/watchdog)
local watchdog
local lastSpoken = {}  -- [text] = GetTime()
local lastPrune = 0

ns.queue = queue

local function itemSettings(item)
	local s = item.source and ns.db.sources[item.source]
	local voiceName = item.voice or (s and s.voice)
	local rate = item.rate or (s and s.rate) or C_TTSSettings.GetSpeechRate() or 0
	local volume = item.volume or (s and s.volume) or C_TTSSettings.GetSpeechVolume() or 100
	return ns.ResolveVoiceID(voiceName), rate, volume
end

-- Rough upper bound on speech duration, used only if SAPI never reports back.
local function estimateSeconds(text, rate)
	local cps = 15 * math.pow(3, (rate or 0) / 10)    -- SAPI: +10 is ~3x speed
	return (string.len(text) / cps) * 2 + 5
end

local function cancelWatchdog()
	if watchdog then watchdog:Cancel() watchdog = nil end
end

local function markStale()
	if currentUtt then staleUtt[currentUtt] = true end
end

local function clearCurrent()
	cancelWatchdog()
	current, pendingStart, currentUtt = nil, nil, nil
	if ns.UpdateStatus then ns.UpdateStatus() end
end

function ns.Next()
	if current then return end
	local item = tremove(queue, 1)
	if not item then return end
	current, pendingStart, currentUtt = item, true, nil
	if ns.UpdateStatus then ns.UpdateStatus() end
	local voiceID, rate, volume = itemSettings(item)
	ns.Debug(string.format("speak [%s] v=%s r=%s vol=%s: %s", tostring(item.source), tostring(voiceID), tostring(rate), tostring(volume), item.text))
	local ok, err = pcall(C_VoiceChat.SpeakText, voiceID, item.text, LOCAL_PLAYBACK, rate, volume)
	if not ok then
		ns.Debug("SpeakText error: " .. tostring(err))
		clearCurrent()
		C_Timer.After(0, ns.Next)
		return
	end
	watchdog = C_Timer.NewTimer(estimateSeconds(item.text, rate), function()
		watchdog = nil
		if current == item then
			ns.Debug("watchdog advanced queue")
			markStale()
			clearCurrent()
			ns.Next()
		end
	end)
end

local function onPlaybackStarted(utteranceID)
	if current and pendingStart and not staleUtt[utteranceID] then
		pendingStart, currentUtt = nil, utteranceID
	end
end

local function onPlaybackDone(utteranceID)
	if utteranceID and staleUtt[utteranceID] then
		staleUtt[utteranceID] = nil
		return
	end
	if not current then return end
	if currentUtt and utteranceID and utteranceID ~= currentUtt then return end
	clearCurrent()
	ns.Next()
end

function ns.Enqueue(text, src, opts)
	if not ns.HasTTS() or not ns.db.global.enabled then return end
	local g = ns.db.global
	text = ns.CleanText(text)
	if g.expandAbbrev and src and src.chat then
		text = ns.ExpandAbbreviations(text)
	end
	if text == "" or not strfind(text, "[%w]") then return end
	if g.maxLength and string.len(text) > g.maxLength then
		local cut = strsub(text, 1, g.maxLength)
		cut = (strgsub(cut, "%s+%S*$", ""))
		text = cut .. "..."
	end

	local now = GetTime()
	if not (opts and opts.force) and g.dedupeSeconds > 0 then
		local t = lastSpoken[text]
		if t and now - t < g.dedupeSeconds then return end
	end
	lastSpoken[text] = now
	if now - lastPrune > 60 then
		lastPrune = now
		for k, t in pairs(lastSpoken) do
			if now - t > 120 then lastSpoken[k] = nil end
		end
	end

	local item = {
		text = text,
		source = src and src.key,
		dialog = src and src.dialog,
		voice = opts and opts.voice,
		rate = opts and opts.rate,
		volume = opts and opts.volume,
	}
	ns.lastItem = item

	local s = src and ns.db.sources[src.key]
	if (s and s.interrupt) or (opts and opts.interrupt) then
		ns.Stop()
		tinsert(queue, item)
	else
		tinsert(queue, item)
		while #queue > g.maxQueue do tremove(queue, 1) end
	end
	if not current then ns.Next() end
end

-- Speak arbitrary text with the global defaults (or explicit overrides).
function ns.Say(text, opts)
	opts = opts or {}
	opts.force = true
	ns.Enqueue(text, nil, opts)
end

function ns.Stop()
	wipe(queue)
	markStale()
	clearCurrent()
	if ns.HasTTS() then C_VoiceChat.StopSpeakingText() end
end

function ns.Skip()
	-- StopSpeakingText purges SAPI's queue too, which is fine: ours is separate.
	markStale()
	clearCurrent()
	if ns.HasTTS() then C_VoiceChat.StopSpeakingText() end
	ns.Next()
end

function ns.Repeat()
	local item = ns.lastItem
	if not item then return end
	local copy = {}
	for k, v in pairs(item) do copy[k] = v end
	tinsert(queue, 1, copy)
	if not current then ns.Next() end
end

-- Drop quest/gossip/book text when its window closes.
function ns.StopDialog()
	for i = #queue, 1, -1 do
		if queue[i].dialog then tremove(queue, i) end
	end
	if current and current.dialog then ns.Skip() end
end

function ns.IsSpeaking()
	return current ~= nil
end

function ns.SetEnabled(on)
	ns.db.global.enabled = on and true or false
	if not on then ns.Stop() end
	ns.UpdateEventRegistrations()
	ns.Print(on and "speech |cff00ff00enabled|r" or "speech |cffff4444disabled|r")
	if ns.RefreshOptions then ns.RefreshOptions() end
end

---------------------------------------------------------------------------
-- Source emission (called by the event dispatcher)
---------------------------------------------------------------------------
local playerName, playerGUID
local lastEmit = {}   -- [source key] = GetTime() of the last line it spoke

-- Languages this character speaks (Common, Darnassian, ...). Built lazily.
local knownLanguages
function ns.KnowsLanguage(language)
	if not language or language == "" then return true end
	if not knownLanguages then
		if not (GetNumLanguages and GetLanguageByIndex) then return true end
		knownLanguages = {}
		for i = 1, GetNumLanguages() do
			local lang = GetLanguageByIndex(i)
			if lang then knownLanguages[lang] = true end
		end
		if not next(knownLanguages) then knownLanguages = nil return true end
	end
	return knownLanguages[language] and true or false
end

function ns.Emit(def, tokens)
	local s = ns.db.sources[def.key]
	if not s or not s.enabled then return end
	local now = GetTime()
	if s.cooldown and s.cooldown > 0 and lastEmit[def.key] and now - lastEmit[def.key] < s.cooldown then
		return
	end
	if UnitAffectingCombat("player") then
		if s.noCombat then return end
		if ns.db.global.muteInCombat and not s.interrupt then return end
	end
	if def.chat then
		if ns.db.global.skipUnknownLanguage and not ns.KnowsLanguage(tokens.language) then return end
		local name = tokens.name
		if name and name ~= "" then
			if ns.db.global.muted[strlower(name)] then return end
			if not def.allowOwn and not ns.db.global.readOwn then
				if name == playerName or (tokens.guid and tokens.guid == playerGUID) then return end
			end
		end
	end
	lastEmit[def.key] = now
	local text = ns.Format(s.template, tokens)
	ns.Enqueue(text, def)
end

function ns.CurrentSource()
	return current and current.source
end

---------------------------------------------------------------------------
-- Event dispatch: only events needed by enabled sources are registered.
---------------------------------------------------------------------------
local frame = CreateFrame("Frame", "TTSClassicAPIEventFrame")
ns.frame = frame

local internal = {}     -- [event] = function(...) — always registered
local eventMap = {}     -- [event] = { def, ... } — sources currently listening

local function isEventValid(ev)
	if C_EventUtils and C_EventUtils.IsEventValid then
		local ok, valid = pcall(C_EventUtils.IsEventValid, ev)
		if ok then return valid end
	end
	return true
end

function ns.UpdateEventRegistrations()
	for ev in pairs(eventMap) do
		if not internal[ev] then frame:UnregisterEvent(ev) end
	end
	wipe(eventMap)
	if ns.OnSourcesChanged then ns.OnSourcesChanged() end
	if not ns.db or not ns.db.global.enabled then return end
	for _, def in ipairs(ns.sources) do
		local s = ns.db.sources[def.key]
		if s and s.enabled then
			for _, ev in ipairs(def.events) do
				if not eventMap[ev] then
					eventMap[ev] = {}
					if isEventValid(ev) then pcall(frame.RegisterEvent, frame, ev) end
				end
				tinsert(eventMap[ev], def)
			end
		end
	end
end

frame:SetScript("OnEvent", function(self, event, ...)
	local fn = internal[event]
	if fn then fn(...) end
	local list = eventMap[event]
	if list then
		for i = 1, #list do
			local def = list[i]
			local ok, tokens = pcall(def.handler, def, event, ...)
			if not ok then
				ns.Debug(def.key .. " handler error: " .. tostring(tokens))
			elseif tokens then
				ns.Emit(def, tokens)
			end
		end
	end
end)

local function registerInternal(ev, fn)
	internal[ev] = fn
	frame:RegisterEvent(ev)
end

registerInternal("ADDON_LOADED", function(name)
	if name ~= addonName then return end
	initDB()
end)

registerInternal("PLAYER_LOGIN", function()
	if not ns.db then initDB() end
	playerName = UnitName("player")
	playerGUID = UnitGUID and UnitGUID("player")
	if not ns.HasTTS() then
		ns.Print("|cffff4444ClassicAPI text-to-speech not found.|r This addon needs the ClassicAPI (or VanillaTTS) DLL loaded via VanillaFixes.")
		return
	end
	ns.RefreshVoiceList()
	ns.UpdateEventRegistrations()
	if #ns.voices == 0 then
		ns.Print("No SAPI voices found. Install voices in Windows Settings > Time & Language > Speech, then type /tts voices.")
	end
	ns.Print("loaded. Type |cffffff00/tts|r for options.")
end)

registerInternal("VOICE_CHAT_TTS_PLAYBACK_STARTED", function(numConsumers, utteranceID)
	onPlaybackStarted(utteranceID)
end)
registerInternal("VOICE_CHAT_TTS_PLAYBACK_FINISHED", function(numConsumers, utteranceID)
	onPlaybackDone(utteranceID)
end)
registerInternal("VOICE_CHAT_TTS_PLAYBACK_FAILED", function(status, utteranceID)
	ns.Debug("playback failed: " .. tostring(status))
	onPlaybackDone(utteranceID)
end)
registerInternal("VOICE_CHAT_TTS_VOICES_UPDATE", function()
	ns.RefreshVoiceList()
end)

-- Dialog windows: stop reading when they close (deferred so a frame that
-- re-opens immediately, e.g. greeting -> quest detail, isn't cut off).
local function dialogClosed()
	if not ns.db or not ns.db.global.stopOnClose then return end
	C_Timer.After(0.2, function()
		local open = (QuestFrame and QuestFrame:IsVisible())
			or (GossipFrame and GossipFrame:IsVisible())
			or (ItemTextFrame and ItemTextFrame:IsVisible())
		if not open then ns.StopDialog() end
	end)
end
registerInternal("QUEST_FINISHED", dialogClosed)
registerInternal("GOSSIP_CLOSED", dialogClosed)
registerInternal("ITEM_TEXT_CLOSED", dialogClosed)

---------------------------------------------------------------------------
-- Key bindings & slash commands
---------------------------------------------------------------------------
BINDING_HEADER_TTSCAPI = "TTS-ClassicAPI"
BINDING_NAME_TTSCAPI_TOGGLE = "Toggle speech on/off"
BINDING_NAME_TTSCAPI_STOP = "Stop speaking (clear queue)"
BINDING_NAME_TTSCAPI_SKIP = "Skip current line"
BINDING_NAME_TTSCAPI_REPEAT = "Repeat last line"
BINDING_NAME_TTSCAPI_READTARGET = "Read target"
BINDING_NAME_TTSCAPI_OPTIONS = "Open options"

function TTSClassicAPI_Toggle() ns.SetEnabled(not ns.db.global.enabled) end
function TTSClassicAPI_Stop() ns.Stop() end
function TTSClassicAPI_Skip() ns.Skip() end
function TTSClassicAPI_Repeat() ns.Repeat() end
function TTSClassicAPI_ReadTarget()
	if ns.ReadUnit then ns.ReadUnit("target") end
end
function TTSClassicAPI_ToggleOptions()
	if ns.ToggleOptions then ns.ToggleOptions() end
end

local HELP = {
	"|cffffff00/tts|r - open options",
	"|cffffff00/tts on|off|toggle|r - enable/disable speech",
	"|cffffff00/tts stop|r, |cffffff00skip|r, |cffffff00repeat|r - control playback",
	"|cffffff00/tts say <text>|r - speak text",
	"|cffffff00/tts target|r - read your target",
	"|cffffff00/tts voices|r - list installed voices",
	"|cffffff00/tts mute <name>|r / |cffffff00unmute <name>|r / |cffffff00muted|r - per-player mute",
	"|cffffff00/tts preset <name>|r / |cffffff00savepreset <name>|r / |cffffff00presets|r - load, save, list presets",
	"|cffffff00/tts debug|r - toggle debug output",
}

SLASH_TTSCLASSICAPI1 = "/tts"
SLASH_TTSCLASSICAPI2 = "/ttsc"
SlashCmdList["TTSCLASSICAPI"] = function(msg)
	msg = strtrim(msg or "")
	local cmd, rest = string.match(msg, "^(%S*)%s*(.-)$")
	cmd = strlower(cmd or "")
	if cmd == "" or cmd == "options" or cmd == "config" then
		TTSClassicAPI_ToggleOptions()
	elseif cmd == "on" then ns.SetEnabled(true)
	elseif cmd == "off" then ns.SetEnabled(false)
	elseif cmd == "toggle" then TTSClassicAPI_Toggle()
	elseif cmd == "stop" then ns.Stop()
	elseif cmd == "skip" then ns.Skip()
	elseif cmd == "repeat" then ns.Repeat()
	elseif cmd == "target" then TTSClassicAPI_ReadTarget()
	elseif cmd == "say" then ns.Say(rest)
	elseif cmd == "voices" then
		if C_TTSSettings and C_TTSSettings.RefreshVoices then C_TTSSettings.RefreshVoices() end
		ns.RefreshVoiceList()
		if #ns.voices == 0 then ns.Print("no voices installed") end
		local cur = C_TTSSettings and C_TTSSettings.GetSpeechVoiceID()
		for _, v in ipairs(ns.voices) do
			ns.Print(string.format("%s%d: %s", v.voiceID == cur and "* " or "  ", v.voiceID, v.name))
		end
	elseif cmd == "mute" and rest ~= "" then
		ns.db.global.muted[strlower(rest)] = true
		ns.Print("muted " .. rest)
	elseif cmd == "unmute" and rest ~= "" then
		ns.db.global.muted[strlower(rest)] = nil
		ns.Print("unmuted " .. rest)
	elseif cmd == "muted" then
		local n = 0
		for name in pairs(ns.db.global.muted) do ns.Print("  " .. name) n = n + 1 end
		if n == 0 then ns.Print("nobody is muted") end
	elseif cmd == "preset" and rest ~= "" then
		ns.LoadPreset(rest)
	elseif cmd == "presets" or cmd == "preset" then
		ns.ListPresets()
	elseif cmd == "savepreset" and rest ~= "" then
		ns.SavePreset(rest)
	elseif cmd == "debug" then
		ns.db.global.debug = not ns.db.global.debug
		ns.Print("debug " .. (ns.db.global.debug and "on" or "off"))
	else
		for _, line in ipairs(HELP) do ns.Print(line) end
	end
end
