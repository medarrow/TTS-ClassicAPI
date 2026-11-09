--[[
	TTS-ClassicAPI - Sources
	Every readable thing is a "source": a set of events, a handler that turns
	the event payload into tokens, and a default template ("{name} says: {msg}").
	Handlers return a token table to speak, or nil to stay quiet.
]]

local _, ns = ...
ns = ns or TTSClassicAPI

local strlower, strgsub, strfind = string.lower, string.gsub, string.find
local Register = ns.RegisterSource

local CHAT_TOKENS = "{msg} {name} {channel} {language} {target}"
local CHAT_SAMPLE = { msg = "Hello there, this is a test.", name = "Arthas", channel = "World", language = "Common" }

---------------------------------------------------------------------------
-- Shared handlers
---------------------------------------------------------------------------

-- CHAT_MSG_*: msg, author, language, channelString, target, flags,
-- zoneChannelID, channelNumber, channelName, _, lineID (arg11), guid (arg12)
local function chat(def, event, msg, author, language, channelString, target, flags, zoneID, channelNumber, channelName, unused, lineID, guid)
	if type(msg) ~= "string" or msg == "" then return nil end
	return {
		msg = msg, name = author, language = language, target = target,
		channel = channelName, guid = guid, event = event,
	}
end

-- NPC chat: emotes contain "%s" for the speaker's name.
local function monster(def, event, msg, author, ...)
	if type(msg) ~= "string" or msg == "" then return nil end
	author = author or ""
	msg = strgsub(msg, "%%s", function() return author end)
	return { msg = msg, name = author }
end

-- Single-string events, tolerating both vanilla (msg) and modern (type, msg) payloads.
local function firstString(def, event, a1, a2)
	local msg = type(a1) == "string" and a1 or (type(a2) == "string" and a2) or nil
	if not msg or msg == "" then return nil end
	return { msg = msg }
end

---------------------------------------------------------------------------
-- Unit descriptions (target, mouseover, focus, soft target)
---------------------------------------------------------------------------
local CLASSIFICATION = {
	elite = "elite", rareelite = "rare elite", rare = "rare", worldboss = "boss",
}

function ns.DescribeUnit(unit)
	if not UnitExists(unit) then return nil end
	local name = UnitName(unit)
	if not name or name == "" then return nil end
	local level = UnitLevel(unit)
	if not level or level < 0 then level = "skull" end
	local class
	if UnitIsPlayer(unit) then
		class = UnitClass(unit)
	else
		class = UnitCreatureType(unit)
		if class == "Not specified" then class = nil end
	end
	local reaction
	if UnitIsEnemy("player", unit) then reaction = "hostile"
	elseif UnitIsFriend("player", unit) then reaction = "friendly"
	else reaction = "neutral" end
	local hp, hpMax = UnitHealth(unit), UnitHealthMax(unit)
	local health = (hpMax and hpMax > 0) and (math.floor(hp / hpMax * 100 + 0.5) .. " percent") or nil
	local guild = UnitIsPlayer(unit) and GetGuildInfo(unit) or nil
	return {
		name = name,
		level = level,
		class = class,
		race = UnitIsPlayer(unit) and UnitRace(unit) or nil,
		classification = CLASSIFICATION[UnitClassification(unit) or ""],
		reaction = reaction,
		health = health,
		guild = guild,
		dead = UnitIsDead(unit) and "dead" or nil,
		guid = UnitGUID and UnitGUID(unit) or nil,
	}
end

local UNIT_TOKENS = "{name} {level} {class} {race} {classification} {reaction} {health} {guild} {dead}"
local UNIT_SAMPLE = { name = "Hogger", level = 11, class = "Humanoid", classification = "elite", reaction = "hostile", health = "100 percent" }

-- Speak a unit on demand (key binding / slash command), using the Target source's template.
function ns.ReadUnit(unit)
	local tokens = ns.DescribeUnit(unit)
	if not tokens then
		ns.Say("No target")
		return
	end
	local s = ns.db.sources.TARGET
	ns.Enqueue(ns.Format(s and s.template or "{name}", tokens), ns.sourceByKey.TARGET, { force = true })
end

---------------------------------------------------------------------------
-- Chat
---------------------------------------------------------------------------
Register({
	key = "SAY", label = "Say", category = "Chat", default = true, chat = true,
	events = { "CHAT_MSG_SAY" }, handler = chat,
	template = "{name} says: {msg}", tokens = CHAT_TOKENS, sample = CHAT_SAMPLE,
})
Register({
	key = "YELL", label = "Yell", category = "Chat", default = true, chat = true,
	events = { "CHAT_MSG_YELL" }, handler = chat,
	template = "{name} yells: {msg}", tokens = CHAT_TOKENS, sample = CHAT_SAMPLE,
})
Register({
	key = "EMOTE", label = "Emotes", category = "Chat", default = false, chat = true,
	events = { "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE" },
	handler = function(def, event, msg, author, ...)
		local t = chat(def, event, msg, author, ...)
		-- Custom /e text lacks the name; standard emotes already include it.
		if t and event == "CHAT_MSG_EMOTE" then t.msg = (author or "") .. " " .. msg end
		return t
	end,
	template = "{msg}", tokens = CHAT_TOKENS, sample = { msg = "Arthas waves at you." },
})
Register({
	key = "WHISPER", label = "Whispers (incoming)", category = "Chat", default = true, chat = true,
	events = { "CHAT_MSG_WHISPER" }, handler = chat,
	template = "{name} whispers: {msg}", tokens = CHAT_TOKENS, sample = CHAT_SAMPLE,
})
Register({
	key = "WHISPER_INFORM", label = "Whispers (outgoing)", category = "Chat", default = false, chat = true, allowOwn = true,
	events = { "CHAT_MSG_WHISPER_INFORM" },
	handler = function(def, event, msg, target, ...)
		local t = chat(def, event, msg, target, ...)
		if t then t.target, t.name = target, nil end
		return t
	end,
	template = "To {target}: {msg}", tokens = "{msg} {target}", sample = { msg = "On my way.", target = "Jaina" },
})
Register({
	key = "AFK", label = "AFK / DND replies", category = "Chat", default = false, chat = true,
	events = { "CHAT_MSG_AFK", "CHAT_MSG_DND" }, handler = chat,
	template = "{name} is away: {msg}", tokens = CHAT_TOKENS, sample = CHAT_SAMPLE,
})
Register({
	key = "PARTY", label = "Party", category = "Chat", default = true, chat = true,
	events = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER" }, handler = chat,
	template = "Party, {name}: {msg}", tokens = CHAT_TOKENS, sample = CHAT_SAMPLE,
})
Register({
	key = "RAID", label = "Raid", category = "Chat", default = true, chat = true,
	events = { "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER" }, handler = chat,
	template = "Raid, {name}: {msg}", tokens = CHAT_TOKENS, sample = CHAT_SAMPLE,
})
Register({
	key = "RAID_WARNING", label = "Raid Warning", category = "Chat", default = true, chat = true, interrupt = true, allowOwn = true,
	events = { "CHAT_MSG_RAID_WARNING" }, handler = chat,
	template = "Raid warning: {msg}", tokens = CHAT_TOKENS, sample = { msg = "Spread out!", name = "Arthas" },
})
Register({
	key = "BATTLEGROUND", label = "Battleground", category = "Chat", default = false, chat = true,
	events = { "CHAT_MSG_BATTLEGROUND", "CHAT_MSG_BATTLEGROUND_LEADER" }, handler = chat,
	template = "{name}: {msg}", tokens = CHAT_TOKENS, sample = CHAT_SAMPLE,
})
Register({
	key = "GUILD", label = "Guild", category = "Chat", default = true, chat = true,
	events = { "CHAT_MSG_GUILD" }, handler = chat,
	template = "Guild, {name}: {msg}", tokens = CHAT_TOKENS, sample = CHAT_SAMPLE,
})
Register({
	key = "OFFICER", label = "Officer", category = "Chat", default = false, chat = true,
	events = { "CHAT_MSG_OFFICER" }, handler = chat,
	template = "Officer, {name}: {msg}", tokens = CHAT_TOKENS, sample = CHAT_SAMPLE,
})

---------------------------------------------------------------------------
-- Channels (all share CHAT_MSG_CHANNEL; each source claims its own channel)
---------------------------------------------------------------------------
local CHANNEL_KEYS = {
	world = "CH_WORLD",
	general = "CH_GENERAL",
	trade = "CH_TRADE",
	lookingforgroup = "CH_LFG", lfg = "CH_LFG",
	localdefense = "CH_DEFENSE", worlddefense = "CH_DEFENSE",
}

-- Hidden addon-to-addon channels: never read, whatever the settings.
local IGNORED_CHANNELS = {
	lft = true,
}

local function channelBase(channelString, channelName)
	local n = channelName
	if not n or n == "" then
		n = channelString and (strgsub(channelString, "^%d+%.%s*", "")) or ""
	end
	return (strgsub(n, "%s+%-.*$", ""))
end

local function channel(def, event, msg, author, language, channelString, target, flags, zoneID, channelNumber, channelName, unused, lineID, guid)
	if type(msg) ~= "string" or msg == "" then return nil end
	local base = channelBase(channelString, channelName)
	local lower = strlower(base)
	if IGNORED_CHANNELS[lower] then return nil end
	local key = CHANNEL_KEYS[lower] or "CH_OTHER"
	if key ~= def.key then return nil end
	return { msg = msg, name = author, language = language, channel = base, guid = guid }
end

local function channelSource(key, label, default, template)
	Register({
		key = key, label = label, category = "Channels", default = default, chat = true,
		events = { "CHAT_MSG_CHANNEL" }, handler = channel,
		template = template, tokens = CHAT_TOKENS, sample = CHAT_SAMPLE,
	})
end
channelSource("CH_WORLD", "World", false, "World, {name}: {msg}")
channelSource("CH_GENERAL", "General", false, "General, {name}: {msg}")
channelSource("CH_TRADE", "Trade", false, "Trade, {name}: {msg}")
channelSource("CH_LFG", "Looking For Group", false, "L F G, {name}: {msg}")
channelSource("CH_DEFENSE", "Local / World Defense", false, "Defense: {msg}")
channelSource("CH_OTHER", "Other / custom channels", false, "{channel}, {name}: {msg}")

---------------------------------------------------------------------------
-- NPCs
---------------------------------------------------------------------------
local NPC_SAMPLE = { msg = "You no take candle!", name = "Kobold Miner" }
Register({
	key = "NPC_SAY", label = "NPC say", category = "NPCs", default = true,
	events = { "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_PARTY" }, handler = monster,
	template = "{name} says: {msg}", tokens = "{msg} {name}", sample = NPC_SAMPLE,
})
Register({
	key = "NPC_YELL", label = "NPC yell", category = "NPCs", default = true,
	events = { "CHAT_MSG_MONSTER_YELL" }, handler = monster,
	template = "{name} yells: {msg}", tokens = "{msg} {name}", sample = NPC_SAMPLE,
})
Register({
	key = "NPC_WHISPER", label = "NPC whisper", category = "NPCs", default = true,
	events = { "CHAT_MSG_MONSTER_WHISPER", "CHAT_MSG_RAID_BOSS_WHISPER" }, handler = monster,
	template = "{name} whispers: {msg}", tokens = "{msg} {name}", sample = NPC_SAMPLE,
})
Register({
	key = "NPC_EMOTE", label = "NPC emotes", category = "NPCs", default = false,
	events = { "CHAT_MSG_MONSTER_EMOTE" }, handler = monster,
	template = "{msg}", tokens = "{msg} {name}", sample = { msg = "Kobold Miner attempts to run away in fear!" },
})
Register({
	key = "BOSS_EMOTE", label = "Boss emotes", category = "NPCs", default = true, interrupt = false,
	events = { "CHAT_MSG_RAID_BOSS_EMOTE" }, handler = monster,
	template = "{msg}", tokens = "{msg} {name}", sample = { msg = "Onyxia takes in a deep breath..." },
})

---------------------------------------------------------------------------
-- Quests, gossip & books (dialog = stops when the window closes)
---------------------------------------------------------------------------
local lastQuestTitle

Register({
	key = "QUEST_GREETING", label = "Quest giver greeting", category = "Quests & Dialog", default = true, dialog = true,
	events = { "QUEST_GREETING" },
	handler = function() return { msg = GetGreetingText(), npc = UnitName("npc") } end,
	template = "{msg}", tokens = "{msg} {npc}", sample = { msg = "Greetings, traveler." },
})
Register({
	key = "QUEST_DETAIL", label = "Quest description", category = "Quests & Dialog", default = true, dialog = true,
	events = { "QUEST_DETAIL" },
	handler = function()
		lastQuestTitle = GetTitleText()
		return { title = lastQuestTitle, msg = GetQuestText(), objectives = GetObjectiveText(), npc = UnitName("npc") }
	end,
	template = "{title}. {msg} Objectives: {objectives}", tokens = "{title} {msg} {objectives} {npc}",
	sample = { title = "The Collector", msg = "Bring me ten gold dust.", objectives = "Collect 10 Gold Dust." },
})
Register({
	key = "QUEST_PROGRESS", label = "Quest progress (turn-in)", category = "Quests & Dialog", default = true, dialog = true,
	events = { "QUEST_PROGRESS" },
	handler = function()
		lastQuestTitle = GetTitleText()
		return { title = lastQuestTitle, msg = GetProgressText(), npc = UnitName("npc") }
	end,
	template = "{title}. {msg}", tokens = "{title} {msg} {npc}",
	sample = { title = "The Collector", msg = "Do you have the gold dust?" },
})
Register({
	key = "QUEST_COMPLETE", label = "Quest completion text", category = "Quests & Dialog", default = true, dialog = true,
	events = { "QUEST_COMPLETE" },
	handler = function()
		lastQuestTitle = GetTitleText()
		return { title = lastQuestTitle, msg = GetRewardText(), npc = UnitName("npc") }
	end,
	template = "{msg}", tokens = "{title} {msg} {npc}", sample = { title = "The Collector", msg = "Excellent work!" },
})
Register({
	key = "GOSSIP", label = "NPC gossip", category = "Quests & Dialog", default = true, dialog = true,
	events = { "GOSSIP_SHOW" },
	handler = function()
		local text, options, quests
		if C_GossipInfo and C_GossipInfo.GetText then
			text = C_GossipInfo.GetText()
			local names = {}
			for _, o in ipairs(C_GossipInfo.GetOptions() or {}) do
				if o.name then names[#names + 1] = o.name end
			end
			options = table.concat(names, ". ")
			names = {}
			for _, q in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
				if q.title then names[#names + 1] = q.title end
			end
			for _, q in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
				if q.title then names[#names + 1] = q.title end
			end
			quests = table.concat(names, ". ")
		else
			text = GetGossipText()
		end
		return { msg = text, npc = UnitName("npc"), options = options, quests = quests }
	end,
	template = "{msg}", tokens = "{msg} {npc} {options} {quests}", sample = { msg = "Welcome to the Lion's Pride Inn." },
})
Register({
	key = "BOOK", label = "Books, letters & plaques", category = "Quests & Dialog", default = true, dialog = true,
	events = { "ITEM_TEXT_READY" },
	handler = function()
		local page = ItemTextGetPage and ItemTextGetPage() or 1
		return {
			title = (page == 1) and ItemTextGetItem() or nil,
			msg = ItemTextGetText(),
			page = page,
		}
	end,
	template = "{title}. {msg}", tokens = "{title} {msg} {page}", sample = { title = "A Dusty Tome", msg = "Once upon a time..." },
})
Register({
	key = "QUEST_ACCEPTED", label = "Quest accepted", category = "Quests & Dialog", default = false,
	events = { "QUEST_ACCEPTED" },
	handler = function(def, event, a1, a2)
		-- Payload is (questLogIndex, questID) on Classic-style clients, (questID) on retail-style.
		local title
		local byID = C_QuestLog and C_QuestLog.GetTitleForQuestID
		if a2 then
			title = byID and byID(a2) or nil
			if not title and type(a1) == "number" then title = GetQuestLogTitle(a1) end
		elseif a1 and byID then
			title = byID(a1)
		end
		return { title = title or lastQuestTitle }
	end,
	template = "Quest accepted: {title}", tokens = "{title}", sample = { title = "The Collector" },
})
Register({
	key = "QUEST_TURNED_IN", label = "Quest turned in", category = "Quests & Dialog", default = false,
	events = { "QUEST_TURNED_IN" },
	handler = function(def, event, questID, xp, money)
		local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and questID and C_QuestLog.GetTitleForQuestID(questID)
		return { title = title or lastQuestTitle, xp = xp }
	end,
	template = "Quest complete: {title}", tokens = "{title} {xp}", sample = { title = "The Collector", xp = 450 },
})
Register({
	key = "INFO", label = "Objective progress / info", category = "Quests & Dialog", default = false,
	events = { "UI_INFO_MESSAGE" }, handler = firstString,
	template = "{msg}", tokens = "{msg}", sample = { msg = "Gold Dust: 3/10" },
})

---------------------------------------------------------------------------
-- Targeting
---------------------------------------------------------------------------
local TARGET_SETTLE = 0.15
local targetSeq, lastTargetID = 0, nil
Register({
	key = "TARGET", label = "Target", category = "Targeting", default = true,
	events = { "PLAYER_TARGET_CHANGED" },
	-- Some nameplate/unit-scan addons briefly target units and then restore your
	-- target, firing PLAYER_TARGET_CHANGED in bursts. Wait for the target to
	-- settle, and only speak if it actually differs from the last one read.
	handler = function(def)
		targetSeq = targetSeq + 1
		local seq = targetSeq
		C_Timer.After(TARGET_SETTLE, function()
			if seq ~= targetSeq then return end
			local t = ns.DescribeUnit("target")
			local id = t and (t.guid or t.name) or nil
			if id == lastTargetID then return end
			lastTargetID = id
			if t then ns.Emit(def, t) end
		end)
		return nil
	end,
	template = "{name}, level {level} {classification} {class}", tokens = UNIT_TOKENS, sample = UNIT_SAMPLE,
})

local seenPlates, seenPlateCount = {}, 0
Register({
	key = "NAMEPLATE", label = "Nameplates appearing", category = "Targeting", default = false,
	events = { "NAME_PLATE_UNIT_ADDED" },
	handler = function(def, event, unit)
		local t = unit and ns.DescribeUnit(unit)
		if not t then return nil end
		local id = t.guid or t.name
		local now = GetTime()
		if seenPlates[id] and now - seenPlates[id] < 30 then return nil end
		if not seenPlates[id] then
			seenPlateCount = seenPlateCount + 1
			if seenPlateCount > 300 then wipe(seenPlates) seenPlateCount = 1 end
		end
		seenPlates[id] = now
		return t
	end,
	template = "{name}", tokens = UNIT_TOKENS, sample = UNIT_SAMPLE,
})

local lastMouseover, lastMouseoverTime = nil, 0
Register({
	key = "MOUSEOVER", label = "Mouseover unit", category = "Targeting", default = false,
	events = { "UPDATE_MOUSEOVER_UNIT" },
	handler = function()
		local t = ns.DescribeUnit("mouseover")
		if not t then return nil end
		local id = t.guid or t.name
		local now = GetTime()
		if id == lastMouseover and now - lastMouseoverTime < 5 then return nil end
		lastMouseover, lastMouseoverTime = id, now
		return t
	end,
	template = "{name}", tokens = UNIT_TOKENS, sample = UNIT_SAMPLE,
})
Register({
	key = "FOCUS", label = "Focus", category = "Targeting", default = false,
	events = { "PLAYER_FOCUS_CHANGED" },
	handler = function() return ns.DescribeUnit("focus") end,
	template = "Focus: {name}", tokens = UNIT_TOKENS, sample = UNIT_SAMPLE,
})
local SOFT_UNIT = {
	PLAYER_SOFT_INTERACT_CHANGED = "softinteract",
	PLAYER_SOFT_ENEMY_CHANGED = "softenemy",
	PLAYER_SOFT_FRIEND_CHANGED = "softfriend",
}
Register({
	key = "SOFT_TARGET", label = "Soft target / interact", category = "Targeting", default = false,
	events = { "PLAYER_SOFT_INTERACT_CHANGED", "PLAYER_SOFT_ENEMY_CHANGED", "PLAYER_SOFT_FRIEND_CHANGED" },
	handler = function(def, event)
		local unit = SOFT_UNIT[event]
		local t = ns.DescribeUnit(unit)
		if t then return t end
		local name = UnitName(unit)   -- game objects have a name but no unit info
		return name and { name = name } or nil
	end,
	template = "{name}", tokens = UNIT_TOKENS, sample = UNIT_SAMPLE,
})

---------------------------------------------------------------------------
-- Group & requests
---------------------------------------------------------------------------
local REQUEST_TEXT = {
	PARTY_INVITE_REQUEST = "%s invites you to a group",
	DUEL_REQUESTED = "%s challenges you to a duel",
	RESURRECT_REQUEST = "%s wants to resurrect you",
	GUILD_INVITE_REQUEST = "%s invites you to a guild",
	READY_CHECK = "Ready check from %s",
}
Register({
	key = "REQUESTS", label = "Invites, duels, ready checks", category = "Group & System", default = true, interrupt = false,
	events = { "PARTY_INVITE_REQUEST", "DUEL_REQUESTED", "RESURRECT_REQUEST", "GUILD_INVITE_REQUEST", "READY_CHECK" },
	handler = function(def, event, name)
		local fmt = REQUEST_TEXT[event]
		if not fmt then return nil end
		return { msg = string.format(fmt, tostring(name or "Someone")), name = name }
	end,
	template = "{msg}", tokens = "{msg} {name}", sample = { msg = "Arthas invites you to a group" },
})
Register({
	key = "BG_SYSTEM", label = "Battleground announcements", category = "Group & System", default = true,
	events = { "CHAT_MSG_BG_SYSTEM_NEUTRAL", "CHAT_MSG_BG_SYSTEM_ALLIANCE", "CHAT_MSG_BG_SYSTEM_HORDE" }, handler = firstString,
	template = "{msg}", tokens = "{msg}", sample = { msg = "The Horde flag was picked up!" },
})
Register({
	key = "SYSTEM", label = "System messages", category = "Group & System", default = false,
	events = { "CHAT_MSG_SYSTEM" }, handler = firstString,
	template = "{msg}", tokens = "{msg}", sample = { msg = "Arthas has come online." },
})
Register({
	key = "ERRORS", label = "Error messages (red text)", category = "Group & System", default = false,
	events = { "UI_ERROR_MESSAGE" }, handler = firstString,
	template = "{msg}", tokens = "{msg}", sample = { msg = "Not enough mana" },
})
Register({
	key = "LOOT", label = "Loot", category = "Group & System", default = false,
	events = { "CHAT_MSG_LOOT" }, handler = firstString,
	template = "{msg}", tokens = "{msg}", sample = { msg = "You receive loot: Linen Cloth." },
})
Register({
	key = "MONEY", label = "Money looted", category = "Group & System", default = false,
	events = { "CHAT_MSG_MONEY" }, handler = firstString,
	template = "{msg}", tokens = "{msg}", sample = { msg = "You loot 12 Copper" },
})
Register({
	key = "XP", label = "Experience gains", category = "Group & System", default = false,
	events = { "CHAT_MSG_COMBAT_XP_GAIN" }, handler = firstString,
	template = "{msg}", tokens = "{msg}", sample = { msg = "Kobold Vermin dies, you gain 45 experience." },
})
Register({
	key = "REPUTATION", label = "Reputation changes", category = "Group & System", default = false,
	events = { "CHAT_MSG_COMBAT_FACTION_CHANGE" }, handler = firstString,
	template = "{msg}", tokens = "{msg}", sample = { msg = "Reputation with Stormwind increased by 25." },
})
Register({
	key = "SKILL", label = "Skill ups", category = "Group & System", default = false,
	events = { "CHAT_MSG_SKILL" }, handler = firstString,
	template = "{msg}", tokens = "{msg}", sample = { msg = "Your skill in Mining has increased to 75." },
})
Register({
	key = "LEVELUP", label = "Level up", category = "Group & System", default = true,
	events = { "PLAYER_LEVEL_UP" },
	handler = function(def, event, level) return { level = level } end,
	template = "Congratulations, you reached level {level}!", tokens = "{level}", sample = { level = 60 },
})
Register({
	key = "ZONE", label = "Zone changes", category = "Group & System", default = false,
	events = { "ZONE_CHANGED_NEW_AREA" },
	handler = function() return { zone = GetZoneText(), subzone = GetSubZoneText() } end,
	template = "Entering {zone}", tokens = "{zone} {subzone}", sample = { zone = "Elwynn Forest" },
})
local lastSubzone
Register({
	key = "SUBZONE", label = "Subzone changes", category = "Group & System", default = false,
	events = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" },
	handler = function()
		local sub = GetSubZoneText()
		if not sub or sub == "" or sub == lastSubzone then return nil end
		lastSubzone = sub
		return { zone = GetZoneText(), subzone = sub }
	end,
	template = "{subzone}", tokens = "{zone} {subzone}", sample = { subzone = "Goldshire" },
})
