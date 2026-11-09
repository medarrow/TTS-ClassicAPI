--[[
	TTS-ClassicAPI - Options window
	Left: every source (checkbox = on/off, click = select). Right: settings for the
	selected source, or the General page. Built lazily on first open.
]]

local _, ns = ...
ns = ns or TTSClassicAPI

local f                     -- main frame
local selected = "GENERAL"
local rows = {}
local general, presetsPanel, sourcePanel  -- right-hand panels

local nameCounter = 0
local function uname(kind)
	nameCounter = nameCounter + 1
	return "TTSCAPIOpt" .. kind .. nameCounter
end

local function setColor(tex, r, g, b, a)
	if tex.SetColorTexture then tex:SetColorTexture(r, g, b, a) else tex:SetTexture(r, g, b, a) end
end

local function voiceLabel(i)
	local v = i and ns.voices[i]
	return v and ns.ShortVoiceName(v.name) or "(no voices)"
end

local function defaultVoiceIndex()
	return ns.VoiceIndexByID(C_TTSSettings.GetSpeechVoiceID()) or 1
end

---------------------------------------------------------------------------
-- Widget helpers (classic 1.12 templates)
---------------------------------------------------------------------------
local function Label(parent, text, font)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
	fs:SetText(text or "")
	fs:SetJustifyH("LEFT")
	return fs
end

local function Checkbox(parent, label, tip, onClick)
	local name = uname("Check")
	local cb = CreateFrame("CheckButton", name, parent, "OptionsCheckButtonTemplate")
	cb:SetWidth(24)
	cb:SetHeight(24)
	cb.label = getglobal(name .. "Text")
	cb.label:SetText(label)
	cb.tooltipText = tip
	cb:SetScript("OnClick", function()
		onClick(cb:GetChecked() and true or false)
	end)
	return cb
end

local function Button(parent, text, width, onClick)
	local b = CreateFrame("Button", uname("Button"), parent, "UIPanelButtonTemplate")
	b:SetWidth(width or 90)
	b:SetHeight(22)
	b:SetText(text)
	b:SetScript("OnClick", function() onClick(b) end)
	return b
end

local function Slider(parent, label, minV, maxV, step, fmt, onChange)
	local name = uname("Slider")
	local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
	s:SetWidth(180)
	s:SetHeight(16)
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	getglobal(name .. "Low"):SetText(fmt and fmt(minV) or minV)
	getglobal(name .. "High"):SetText(fmt and fmt(maxV) or maxV)
	local text = getglobal(name .. "Text")
	local function display(v)
		text:SetText(label .. ": " .. (fmt and fmt(v) or v))
	end
	s:SetScript("OnValueChanged", function()
		local v = math.floor(s:GetValue() / step + 0.5) * step
		display(v)
		if not s.silent then onChange(v) end
	end)
	function s:SetSilently(v)
		self.silent = true
		self:SetValue(v)
		display(v)
		self.silent = nil
	end
	function s:SetActive(on)
		self:SetAlpha(on and 1 or 0.4)
		self:EnableMouse(on)
	end
	return s
end

local function EditBox(parent, width, onCommit)
	local eb = CreateFrame("EditBox", uname("Edit"), parent, "InputBoxTemplate")
	eb:SetAutoFocus(false)
	eb:SetWidth(width)
	eb:SetHeight(20)
	eb:SetMaxLetters(255)
	eb:SetScript("OnEnterPressed", function()
		onCommit(eb:GetText())
		eb:ClearFocus()
	end)
	eb:SetScript("OnEscapePressed", function()
		if eb.revert then eb:SetText(eb.revert) end
		eb:ClearFocus()
	end)
	eb:SetScript("OnEditFocusLost", function()
		onCommit(eb:GetText())
	end)
	return eb
end

-- [<] Voice name [>] cycler; get() returns an index into ns.voices, set(i) stores it.
local function VoicePicker(parent, get, set)
	local p = CreateFrame("Frame", nil, parent)
	p:SetWidth(200)
	p:SetHeight(22)
	local prev = CreateFrame("Button", uname("Button"), p, "UIPanelButtonTemplate")
	prev:SetWidth(24) prev:SetHeight(22) prev:SetText("<")
	prev:SetPoint("LEFT", p, "LEFT", 0, 0)
	local nxt = CreateFrame("Button", uname("Button"), p, "UIPanelButtonTemplate")
	nxt:SetWidth(24) nxt:SetHeight(22) nxt:SetText(">")
	nxt:SetPoint("RIGHT", p, "RIGHT", 0, 0)
	local text = Label(p, "", "GameFontHighlight")
	text:SetPoint("LEFT", prev, "RIGHT", 4, 0)
	text:SetPoint("RIGHT", nxt, "LEFT", -4, 0)
	text:SetJustifyH("CENTER")

	function p:Update()
		text:SetText(voiceLabel(get()))
	end
	local function step(d)
		local n = #ns.voices
		if n == 0 then return end
		local i = (get() or 1) + d
		if i < 1 then i = n elseif i > n then i = 1 end
		set(i)
		p:Update()
	end
	prev:SetScript("OnClick", function() step(-1) end)
	nxt:SetScript("OnClick", function() step(1) end)
	function p:SetActive(on)
		self:SetAlpha(on and 1 or 0.4)
		if on then prev:Enable() nxt:Enable() else prev:Disable() nxt:Disable() end
	end
	return p
end

---------------------------------------------------------------------------
-- Source list
---------------------------------------------------------------------------
local ROW_H = 20

local function refreshRows()
	local db = ns.db
	for _, row in ipairs(rows) do
		if row.key then
			if row.key == selected then row.sel:Show() else row.sel:Hide() end
			if row.check then
				local on = db.sources[row.key].enabled
				row.check:SetChecked(on)
				if on then row.text:SetTextColor(1, 1, 1) else row.text:SetTextColor(0.55, 0.55, 0.55) end
			end
		end
	end
end

local function buildList(child)
	local y = 0
	local function addRow(key, text, isSource)
		local row = CreateFrame("Button", nil, child)
		row:SetWidth(196)
		row:SetHeight(ROW_H)
		row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
		row.key = key
		row.sel = row:CreateTexture(nil, "BACKGROUND")
		row.sel:SetAllPoints(row)
		setColor(row.sel, 0.25, 0.45, 0.9, 0.35)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		local textX = 6
		if isSource then
			local cb = CreateFrame("CheckButton", uname("RowCheck"), row, "UICheckButtonTemplate")
			cb:SetWidth(20) cb:SetHeight(20)
			cb:SetPoint("LEFT", row, "LEFT", 2, 0)
			cb:SetScript("OnClick", function()
				ns.db.sources[key].enabled = cb:GetChecked() and true or false
				ns.UpdateEventRegistrations()
				ns.RefreshOptions()
			end)
			row.check = cb
			textX = 24
		end
		row.text = Label(row, text, isSource and "GameFontHighlightSmall" or "GameFontNormal")
		row.text:SetPoint("LEFT", row, "LEFT", textX, 0)
		row:SetScript("OnClick", function()
			selected = key
			ns.RefreshOptions()
		end)
		rows[#rows + 1] = row
		y = y + ROW_H
	end
	local function addHeader(text)
		y = y + 6
		local fs = Label(child, text, "GameFontNormalSmall")
		fs:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -y)
		fs:SetTextColor(1, 0.82, 0)
		y = y + 14
	end

	addRow("GENERAL", "General settings", false)
	addRow("PRESETS", "Presets", false)
	for _, cat in ipairs(ns.categories) do
		addHeader(cat)
		for _, def in ipairs(ns.sources) do
			if def.category == cat then addRow(def.key, def.label, true) end
		end
	end
	child:SetHeight(y + 4)
end

---------------------------------------------------------------------------
-- General panel
---------------------------------------------------------------------------
local function buildGeneral(parent)
	local p = CreateFrame("Frame", nil, parent)
	p:SetAllPoints(parent)
	local g = function() return ns.db.global end

	local title = Label(p, "General settings", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
	local sub = Label(p, "Defaults are ClassicAPI's shared TTS settings (C_TTSSettings) and apply to every source without its own override.", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	sub:SetWidth(400)

	local vl = Label(p, "Default voice", "GameFontNormalSmall")
	vl:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -52)
	p.voice = VoicePicker(p, defaultVoiceIndex, function(i)
		C_TTSSettings.SetVoiceOption(ns.voices[i].voiceID)
	end)
	p.voice:SetPoint("TOPLEFT", vl, "BOTTOMLEFT", 0, -4)

	p.rate = Slider(p, "Default rate", -10, 10, 1, nil, function(v) C_TTSSettings.SetSpeechRate(v) end)
	p.rate:SetPoint("TOPLEFT", p, "TOPLEFT", 4, -115)
	p.volume = Slider(p, "Default volume", 0, 100, 5, nil, function(v) C_TTSSettings.SetSpeechVolume(v) end)
	p.volume:SetPoint("TOPLEFT", p, "TOPLEFT", 4, -160)
	p.queue = Slider(p, "Max queued lines", 1, 30, 1, nil, function(v) g().maxQueue = v end)
	p.queue:SetPoint("TOPLEFT", p, "TOPLEFT", 4, -205)
	p.dedupe = Slider(p, "Skip repeats within", 0, 60, 1, function(v) return v .. "s" end, function(v) g().dedupeSeconds = v end)
	p.dedupe:SetPoint("TOPLEFT", p, "TOPLEFT", 4, -250)
	p.maxlen = Slider(p, "Max line length", 50, 2000, 50, nil, function(v) g().maxLength = v end)
	p.maxlen:SetPoint("TOPLEFT", p, "TOPLEFT", 4, -295)

	local checks = {
		{ "readOwn", "Read my own messages", "Speak chat lines you sent yourself." },
		{ "skipUnknownLanguage", "Skip unknown languages", "Don't read chat in languages your character can't understand (it's gibberish anyway)." },
		{ "expandAbbrev", "Expand chat abbreviations", "lfm -> looking for more, wts -> want to sell, brd -> Blackrock Depths..." },
		{ "stopOnClose", "Stop when window closes", "Stop reading quest, gossip and book text when that window is closed." },
		{ "muteInCombat", "Silence in combat", "While in combat, only sources marked 'Interrupt' are spoken." },
		{ "debug", "Debug output", "Print what is spoken and any errors to chat." },
	}
	p.checks = {}
	for i, c in ipairs(checks) do
		local key = c[1]
		local cb = Checkbox(p, c[2], c[3], function(on) g()[key] = on end)
		cb:SetPoint("TOPLEFT", p, "TOPLEFT", 215, -48 - (i - 1) * 28)
		cb.key = key
		p.checks[#p.checks + 1] = cb
	end

	local refresh = Button(p, "Refresh voices", 120, function()
		if C_TTSSettings.RefreshVoices then C_TTSSettings.RefreshVoices() end
		ns.RefreshVoiceList()
		ns.Print(#ns.voices .. " voice(s) found")
	end)
	refresh:SetPoint("TOPLEFT", p, "TOPLEFT", 219, -224)
	local reset = Button(p, "Reset TTS defaults", 120, function()
		C_TTSSettings.SetDefaultSettings()
		ns.RefreshOptions()
	end)
	reset:SetPoint("TOPLEFT", refresh, "BOTTOMLEFT", 0, -6)

	local sl = Label(p, "Speak text:", "GameFontNormalSmall")
	sl:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -340)
	local eb
	eb = EditBox(p, 300, function() end)
	eb:SetPoint("TOPLEFT", sl, "BOTTOMLEFT", 6, -4)
	eb:SetText("The quick brown fox jumps over the lazy dog.")
	eb:SetScript("OnEnterPressed", function() ns.Say(eb:GetText()) eb:ClearFocus() end)
	local speak = Button(p, "Speak", 80, function() ns.Say(eb:GetText()) end)
	speak:SetPoint("LEFT", eb, "RIGHT", 6, 0)

	function p:Refresh()
		self.voice:Update()
		self.rate:SetSilently(C_TTSSettings.GetSpeechRate())
		self.volume:SetSilently(C_TTSSettings.GetSpeechVolume())
		self.queue:SetSilently(g().maxQueue)
		self.dedupe:SetSilently(g().dedupeSeconds)
		self.maxlen:SetSilently(g().maxLength)
		for _, cb in ipairs(self.checks) do cb:SetChecked(g()[cb.key]) end
	end
	return p
end

---------------------------------------------------------------------------
-- Presets panel
---------------------------------------------------------------------------
local PRESET_ROWS = 7
local pendingDelete

StaticPopupDialogs["TTSCAPI_DELETE_PRESET"] = {
	text = "Delete TTS preset \"%s\"?",
	button1 = YES or "Yes",
	button2 = NO or "No",
	OnAccept = function()
		if pendingDelete then ns.DeletePreset(pendingDelete) end
		pendingDelete = nil
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

local function buildPresets(parent)
	local p = CreateFrame("Frame", nil, parent)
	p:SetAllPoints(parent)
	p.page = 1

	local title = Label(p, "Presets", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)

	local bl = Label(p, "Built-in presets only change which sources are on. Your voices, templates and cooldowns are kept.", "GameFontHighlightSmall")
	bl:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	bl:SetWidth(400)

	local prevBtn
	for i, preset in ipairs(ns.BUILTIN_PRESETS) do
		local b = Button(p, preset.name, 64, function() ns.ApplyBuiltinPreset(preset) end)
		if i == 1 then
			b:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -58)
		else
			b:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
		end
		b:SetScript("OnEnter", function()
			GameTooltip:SetOwner(b, "ANCHOR_TOP")
			GameTooltip:SetText(preset.name)
			GameTooltip:AddLine(preset.desc, 1, 1, 1, 1)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		prevBtn = b
	end

	local yl = Label(p, "Your presets", "GameFontNormal")
	yl:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -100)
	local yd = Label(p, "Saved presets store every source's full settings: on/off, voice, rate, volume, template, cooldown...", "GameFontHighlightSmall")
	yd:SetPoint("TOPLEFT", yl, "BOTTOMLEFT", 0, -4)
	yd:SetWidth(400)

	local nameBox = EditBox(p, 250, function() end)
	nameBox:SetPoint("TOPLEFT", p, "TOPLEFT", 6, -140)
	local function save()
		if ns.SavePreset(nameBox:GetText()) then
			nameBox:SetText("")
			nameBox:ClearFocus()
		end
	end
	nameBox:SetScript("OnEnterPressed", save)
	nameBox:SetScript("OnEditFocusLost", nil)
	local saveBtn = Button(p, "Save current", 110, save)
	saveBtn:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)

	p.rows = {}
	for i = 1, PRESET_ROWS do
		local row = CreateFrame("Frame", nil, p)
		row:SetWidth(400)
		row:SetHeight(24)
		row:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -168 - (i - 1) * 26)
		local bg = row:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(row)
		setColor(bg, 1, 1, 1, (i % 2 == 0) and 0.04 or 0.08)
		row.text = Label(row, "", "GameFontHighlight")
		row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
		row.text:SetWidth(190)
		row.del = Button(row, "Delete", 64, function()
			pendingDelete = row.name
			StaticPopup_Show("TTSCAPI_DELETE_PRESET", row.name)
		end)
		row.del:SetPoint("RIGHT", row, "RIGHT", 0, 0)
		row.load = Button(row, "Load", 64, function() ns.LoadPreset(row.name) end)
		row.load:SetPoint("RIGHT", row.del, "LEFT", -4, 0)
		row.overwrite = Button(row, "Update", 64, function() ns.SavePreset(row.name) end)
		row.overwrite:SetPoint("RIGHT", row.load, "LEFT", -4, 0)
		p.rows[i] = row
	end

	p.empty = Label(p, "No saved presets yet. Type a name above and press Save current.", "GameFontDisableSmall")
	p.empty:SetPoint("TOPLEFT", p, "TOPLEFT", 6, -174)

	p.prev = Button(p, "<", 28, function() p.page = p.page - 1 p:Refresh() end)
	p.prev:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -168 - PRESET_ROWS * 26 - 4)
	p.next = Button(p, ">", 28, function() p.page = p.page + 1 p:Refresh() end)
	p.next:SetPoint("LEFT", p.prev, "RIGHT", 4, 0)
	p.pageText = Label(p, "", "GameFontHighlightSmall")
	p.pageText:SetPoint("LEFT", p.next, "RIGHT", 8, 0)

	function p:Refresh()
		local names = ns.GetSavedPresets()
		local pages = math.max(1, math.ceil(#names / PRESET_ROWS))
		if self.page > pages then self.page = pages end
		if self.page < 1 then self.page = 1 end
		local offset = (self.page - 1) * PRESET_ROWS
		for i, row in ipairs(self.rows) do
			local name = names[offset + i]
			row.name = name
			if name then
				row.text:SetText(name)
				row:Show()
			else
				row:Hide()
			end
		end
		if #names == 0 then self.empty:Show() else self.empty:Hide() end
		local paged = pages > 1
		if paged then
			self.prev:Show() self.next:Show() self.pageText:Show()
			self.pageText:SetText("Page " .. self.page .. " / " .. pages)
			if self.page > 1 then self.prev:Enable() else self.prev:Disable() end
			if self.page < pages then self.next:Enable() else self.next:Disable() end
		else
			self.prev:Hide() self.next:Hide() self.pageText:Hide()
		end
	end
	return p
end

---------------------------------------------------------------------------
-- Per-source panel
---------------------------------------------------------------------------
local function buildSourcePanel(parent)
	local p = CreateFrame("Frame", nil, parent)
	p:SetAllPoints(parent)
	local function S() return ns.db.sources[selected] end
	local function D() return ns.sourceByKey[selected] end

	p.title = Label(p, "", "GameFontNormalLarge")
	p.title:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
	p.events = Label(p, "", "GameFontDisableSmall")
	p.events:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -4)
	p.events:SetWidth(400)

	p.enabled = Checkbox(p, "Enabled", "Read this source aloud.", function(on)
		S().enabled = on
		ns.UpdateEventRegistrations()
		ns.RefreshOptions()
	end)
	p.enabled:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -44)
	p.interrupt = Checkbox(p, "Interrupt", "Stop whatever is being read and speak this immediately. Also bypasses 'Silence in combat'.", function(on)
		S().interrupt = on
	end)
	p.interrupt:SetPoint("TOPLEFT", p, "TOPLEFT", 130, -44)
	p.noCombat = Checkbox(p, "Not in combat", "Don't read this source while you are in combat.", function(on)
		S().noCombat = on
	end)
	p.noCombat:SetPoint("TOPLEFT", p, "TOPLEFT", 260, -44)

	-- Voice override
	p.useVoice = Checkbox(p, "Own voice", "Use a different voice for this source.", function(on)
		local v = ns.voices[defaultVoiceIndex()]
		S().voice = (on and v) and v.name or nil
		p:Refresh()
	end)
	p.useVoice:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -90)
	p.voice = VoicePicker(p, function()
		return ns.VoiceIndexByName(S().voice) or defaultVoiceIndex()
	end, function(i)
		S().voice = ns.voices[i].name
	end)
	p.voice:SetPoint("TOPLEFT", p, "TOPLEFT", 140, -91)

	-- Rate override
	p.useRate = Checkbox(p, "Own rate", "Use a different speech rate for this source.", function(on)
		S().rate = on and C_TTSSettings.GetSpeechRate() or nil
		p:Refresh()
	end)
	p.useRate:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -130)
	p.rate = Slider(p, "Rate", -10, 10, 1, nil, function(v) S().rate = v end)
	p.rate:SetPoint("TOPLEFT", p, "TOPLEFT", 150, -135)

	-- Volume override
	p.useVolume = Checkbox(p, "Own volume", "Use a different volume for this source.", function(on)
		S().volume = on and C_TTSSettings.GetSpeechVolume() or nil
		p:Refresh()
	end)
	p.useVolume:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -175)
	p.volume = Slider(p, "Volume", 0, 100, 5, nil, function(v) S().volume = v end)
	p.volume:SetPoint("TOPLEFT", p, "TOPLEFT", 150, -180)

	-- Template
	local tl = Label(p, "What to say (template):", "GameFontNormalSmall")
	tl:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -222)
	p.template = EditBox(p, 395, function(text)
		text = strtrim(text or "")
		if text == "" then text = D().template end
		S().template = text
		p.template.revert = text
	end)
	p.template:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 6, -4)
	p.tokens = Label(p, "", "GameFontHighlightSmall")
	p.tokens:SetPoint("TOPLEFT", p.template, "BOTTOMLEFT", -6, -6)
	p.tokens:SetWidth(400)

	-- Cooldown
	p.cooldown = Slider(p, "Cooldown", 0, 120, 1, function(v)
		return (v == 0) and "off" or (v .. "s")
	end, function(v) S().cooldown = v end)
	p.cooldown:SetPoint("TOPLEFT", p, "TOPLEFT", 4, -318)
	local cdHelp = Label(p, "Minimum time between lines from this source.\nLines arriving sooner are dropped.", "GameFontHighlightSmall")
	cdHelp:SetPoint("LEFT", p.cooldown, "RIGHT", 16, -2)
	cdHelp:SetWidth(200)

	local test = Button(p, "Test", 80, function()
		local def = D()
		ns.Enqueue(ns.Format(S().template, def.sample or { msg = "Test" }), def, { force = true })
	end)
	test:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -360)
	local reset = Button(p, "Reset source", 110, function()
		ns.ResetSource(selected)
		ns.RefreshOptions()
	end)
	reset:SetPoint("LEFT", test, "RIGHT", 6, 0)

	function p:Refresh()
		local s, def = S(), D()
		if not s or not def then return end
		self.title:SetText(def.label)
		self.events:SetText(def.category .. "  -  " .. table.concat(def.events, ", "))
		self.enabled:SetChecked(s.enabled)
		self.interrupt:SetChecked(s.interrupt)
		self.noCombat:SetChecked(s.noCombat)

		self.useVoice:SetChecked(s.voice ~= nil)
		self.voice:Update()
		self.voice:SetActive(s.voice ~= nil)

		self.useRate:SetChecked(s.rate ~= nil)
		self.rate:SetSilently(s.rate or C_TTSSettings.GetSpeechRate())
		self.rate:SetActive(s.rate ~= nil)

		self.useVolume:SetChecked(s.volume ~= nil)
		self.volume:SetSilently(s.volume or C_TTSSettings.GetSpeechVolume())
		self.volume:SetActive(s.volume ~= nil)

		self.cooldown:SetSilently(s.cooldown or 0)

		self.template:SetText(s.template or "")
		self.template.revert = s.template
		self.template:ClearFocus()
		self.tokens:SetText("Tokens: " .. (def.tokens or "{msg}") .. "\nDefault: " .. (def.template or ""))
	end
	return p
end

---------------------------------------------------------------------------
-- Main frame
---------------------------------------------------------------------------
local function build()
	f = CreateFrame("Frame", "TTSClassicAPIOptions", UIParent)
	f:SetWidth(700)
	f:SetHeight(500)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function() f:StartMoving() end)
	f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
	f:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	f:Hide()
	tinsert(UISpecialFrames, "TTSClassicAPIOptions")

	local header = f:CreateTexture(nil, "ARTWORK")
	header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	header:SetWidth(320)
	header:SetHeight(64)
	header:SetPoint("TOP", f, "TOP", 0, 12)
	local title = Label(f, "TTS-ClassicAPI", "GameFontNormal")
	title:SetPoint("TOP", f, "TOP", 0, -2)

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)

	-- Top bar
	f.master = Checkbox(f, "Speech enabled", "Master switch. Key-bindable under Key Bindings > TTS-ClassicAPI.", function(on)
		ns.SetEnabled(on)
	end)
	f.master:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -26)
	f.status = Label(f, "", "GameFontHighlightSmall")
	f.status:SetPoint("LEFT", f.master.label, "RIGHT", 16, 0)

	local stop = Button(f, "Stop", 70, function() ns.Stop() end)
	stop:SetPoint("TOPRIGHT", f, "TOPRIGHT", -40, -28)
	local skip = Button(f, "Skip", 70, function() ns.Skip() end)
	skip:SetPoint("RIGHT", stop, "LEFT", -4, 0)
	local rep = Button(f, "Repeat", 70, function() ns.Repeat() end)
	rep:SetPoint("RIGHT", skip, "LEFT", -4, 0)

	-- Source list
	local listBg = CreateFrame("Frame", nil, f)
	listBg:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -58)
	listBg:SetWidth(232)
	listBg:SetHeight(424)
	listBg:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	listBg:SetBackdropColor(0, 0, 0, 0.5)

	local scroll = CreateFrame("ScrollFrame", "TTSClassicAPIOptionsScroll", listBg, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", listBg, "TOPLEFT", 6, -8)
	scroll:SetPoint("BOTTOMRIGHT", listBg, "BOTTOMRIGHT", -28, 8)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetWidth(196)
	child:SetHeight(10)
	scroll:SetScrollChild(child)
	buildList(child)

	-- Right side
	local right = CreateFrame("Frame", nil, f)
	right:SetPoint("TOPLEFT", f, "TOPLEFT", 266, -64)
	right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 20)
	general = buildGeneral(right)
	presetsPanel = buildPresets(right)
	sourcePanel = buildSourcePanel(right)

	f:SetScript("OnShow", function() ns.RefreshOptions() end)
end

local function updateStatus()
	if not f then return end
	if not ns.HasTTS() then
		f.status:SetText("|cffff4444ClassicAPI TTS not available|r")
	else
		f.status:SetText(string.format("%d voice(s)  -  %s", #ns.voices,
			ns.IsSpeaking() and "|cff00ff00speaking|r" or "idle"))
	end
end

function ns.RefreshOptions()
	if not f or not f:IsShown() or not ns.db then return end
	f.master:SetChecked(ns.db.global.enabled)
	updateStatus()
	refreshRows()
	if selected ~= "PRESETS" and not ns.sourceByKey[selected] then
		selected = "GENERAL"
	end
	local panel = (selected == "GENERAL" and general)
		or (selected == "PRESETS" and presetsPanel)
		or sourcePanel
	for _, other in ipairs({ general, presetsPanel, sourcePanel }) do
		if other ~= panel then other:Hide() end
	end
	panel:Show()
	panel:Refresh()
end

ns.OnVoicesUpdated = ns.RefreshOptions
ns.UpdateStatus = function()
	if f and f:IsShown() then updateStatus() end
end

function ns.ToggleOptions()
	if not ns.db then return end
	if not f then build() end
	if f:IsShown() then f:Hide() else f:Show() end
end
