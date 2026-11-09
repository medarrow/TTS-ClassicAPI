--[[
	TTS-ClassicAPI - Quest log read button
	A small, semi-transparent icon in the top-right of the quest log's detail
	pane. Left-click reads the selected quest (click again to stop), right-click
	stops all speech. Its voice/rate/volume/template come from the
	"Quest log read button" source; that source's checkbox shows/hides the icon.
]]

local _, ns = ...
ns = ns or TTSClassicAPI

local ICON = "Interface\\Icons\\INV_Misc_Note_01"
local IDLE_ALPHA = 0.55

local def = {
	key = "QUEST_LOG", label = "Quest log read button", category = "Quests & Dialog", default = true,
	events = {},   -- manual: triggered by the button, not by events
	handler = function() return nil end,
	template = "{title}. {msg} Objectives: {objectives} {progress}",
	tokens = "{title} {level} {msg} {objectives} {progress} {complete}",
	sample = { title = "The Collector", level = 12, msg = "Bring me ten gold dust.", objectives = "Collect 10 Gold Dust.", progress = "Gold Dust: 3/10" },
}
ns.RegisterSource(def)

local function readSelectedQuest()
	-- Second click on the button stops the quest currently being read.
	if ns.CurrentSource() == "QUEST_LOG" then
		ns.Skip()
		return
	end
	local index = GetQuestLogSelection()
	if not index or index == 0 then return end
	local title, level, tag, isHeader, isCollapsed, isComplete = GetQuestLogTitle(index)
	if not title or isHeader then return end
	local desc, objectives = GetQuestLogQuestText()

	local progress = {}
	for i = 1, (GetNumQuestLeaderBoards(index) or 0) do
		local text = GetQuestLogLeaderBoard(i, index)
		if text and text ~= "" then progress[#progress + 1] = text end
	end

	local tokens = {
		title = title,
		level = level,
		msg = desc,
		objectives = objectives,
		progress = table.concat(progress, ". "),
		complete = (isComplete == 1 or isComplete == true) and "Complete." or nil,
	}
	local s = ns.db.sources.QUEST_LOG
	ns.Enqueue(ns.Format(s.template, tokens), def, { force = true })
end

local button

local function createButton()
	local anchor = QuestLogDetailScrollFrame or QuestLogFrame
	if not anchor then return end
	button = CreateFrame("Button", "TTSClassicAPIQuestLogButton", anchor)
	button:SetWidth(18)
	button:SetHeight(18)
	button:SetFrameLevel(anchor:GetFrameLevel() + 5)
	if anchor == QuestLogDetailScrollFrame then
		button:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -2, -2)
	else
		button:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -60, -40)
	end
	button:SetNormalTexture(ICON)
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button:SetAlpha(IDLE_ALPHA)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetScript("OnClick", function(self, mouseButton)
		mouseButton = mouseButton or arg1
		if mouseButton == "RightButton" then
			ns.Stop()
		else
			readSelectedQuest()
		end
	end)
	button:SetScript("OnEnter", function()
		button:SetAlpha(1)
		GameTooltip:SetOwner(button, "ANCHOR_LEFT")
		GameTooltip:SetText("Read quest aloud")
		GameTooltip:AddLine("Left-click: read / stop reading", 1, 1, 1)
		GameTooltip:AddLine("Right-click: stop all speech", 1, 1, 1)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		button:SetAlpha(IDLE_ALPHA)
		GameTooltip:Hide()
	end)
end

-- Called by Core whenever source settings change (and once at login).
local previous = ns.OnSourcesChanged
function ns.OnSourcesChanged()
	if previous then previous() end
	if not ns.db then return end
	local show = ns.db.global.enabled and ns.db.sources.QUEST_LOG.enabled
	if show and not button then createButton() end
	if button then
		if show then button:Show() else button:Hide() end
	end
end
