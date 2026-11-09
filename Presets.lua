--[[
	TTS-ClassicAPI - Presets
	Built-in presets only switch sources on/off (your voices, templates,
	cooldowns etc. are kept). Saved presets are full snapshots of every
	source's settings and restore all of them.
]]

local _, ns = ...
ns = ns or TTSClassicAPI

local strlower = string.lower

local function set(...)
	local t = {}
	for i = 1, select("#", ...) do t[select(i, ...)] = true end
	return t
end

local LOCAL = set("SAY", "YELL", "EMOTE")
local SOCIAL = set("SAY", "YELL", "EMOTE", "WHISPER", "PARTY", "RAID", "RAID_WARNING", "GUILD")
local NPCS = set("NPC_SAY", "NPC_YELL", "NPC_WHISPER", "NPC_EMOTE", "BOSS_EMOTE")

ns.BUILTIN_PRESETS = {
	{ name = "Default", desc = "The sources that are on when the addon is first installed. Also turns 'Stop when window closes' back on.",
	  enabled = function(def) return def.default and true or false end,
	  apply = function(g) g.stopOnClose = true end },
	{ name = "None", desc = "Turn every source off.",
	  enabled = function() return false end },
	{ name = "Local", desc = "Say, yell and emotes from players around you.",
	  enabled = function(def) return LOCAL[def.key] or false end },
	{ name = "Social", desc = "Local chat plus party, raid, raid warnings, guild and incoming whispers.",
	  enabled = function(def) return SOCIAL[def.key] or false end },
	{ name = "NPCs", desc = "NPC say, yell, whispers and emotes, including boss emotes.",
	  enabled = function(def) return NPCS[def.key] or false end },
	{ name = "Quests", desc = "Quest text, gossip, books and the quest log button. Turns off 'Stop when window closes' so you can close the window and keep listening.",
	  enabled = function(def) return def.category == "Quests & Dialog" end,
	  apply = function(g) g.stopOnClose = false end },
}

local function copy(t)
	local out = {}
	for k, v in pairs(t) do
		out[k] = type(v) == "table" and copy(v) or v
	end
	return out
end

local function findBuiltin(name)
	local n = strlower(name or "")
	for _, p in ipairs(ns.BUILTIN_PRESETS) do
		if strlower(p.name) == n then return p end
	end
end

-- Case-insensitive lookup of a saved preset; returns its stored name.
local function findSaved(name)
	local n = strlower(name or "")
	for k in pairs(ns.db.presets) do
		if strlower(k) == n then return k end
	end
end

-- Saved preset names, sorted.
function ns.GetSavedPresets()
	local names = {}
	for k in pairs(ns.db.presets) do names[#names + 1] = k end
	table.sort(names, function(a, b) return strlower(a) < strlower(b) end)
	return names
end

local function applied(name)
	ns.UpdateEventRegistrations()
	if ns.RefreshOptions then ns.RefreshOptions() end
	ns.Print("loaded preset |cffffff00" .. name .. "|r")
end

function ns.ApplyBuiltinPreset(p)
	for _, def in ipairs(ns.sources) do
		ns.db.sources[def.key].enabled = p.enabled(def) and true or false
	end
	if p.apply then p.apply(ns.db.global) end
	applied(p.name)
end

-- Load a preset by name: saved presets win over built-ins of the same name.
function ns.LoadPreset(name)
	local saved = findSaved(name)
	if saved then
		local snap = ns.db.presets[saved]
		for _, def in ipairs(ns.sources) do
			ns.db.sources[def.key] = snap[def.key] and copy(snap[def.key]) or ns.SourceDefaults(def)
		end
		applied(saved)
		return true
	end
	local b = findBuiltin(name)
	if b then
		ns.ApplyBuiltinPreset(b)
		return true
	end
	ns.Print("no preset named '" .. tostring(name) .. "'")
	return false
end

function ns.SavePreset(name)
	name = strtrim(name or "")
	if name == "" then
		ns.Print("give the preset a name first")
		return false
	end
	local existing = findSaved(name)
	if existing then name = existing end
	ns.db.presets[name] = copy(ns.db.sources)
	ns.Print((existing and "updated" or "saved") .. " preset |cffffff00" .. name .. "|r")
	if ns.RefreshOptions then ns.RefreshOptions() end
	return true
end

function ns.DeletePreset(name)
	local saved = findSaved(name)
	if not saved then return false end
	ns.db.presets[saved] = nil
	ns.Print("deleted preset |cffffff00" .. saved .. "|r")
	if ns.RefreshOptions then ns.RefreshOptions() end
	return true
end

function ns.ListPresets()
	local b = {}
	for _, p in ipairs(ns.BUILTIN_PRESETS) do b[#b + 1] = p.name end
	ns.Print("built-in: " .. table.concat(b, ", "))
	local saved = ns.GetSavedPresets()
	ns.Print("saved: " .. (#saved > 0 and table.concat(saved, ", ") or "(none)"))
end
