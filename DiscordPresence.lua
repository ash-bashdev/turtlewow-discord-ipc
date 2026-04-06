--[[
    DiscordPresence.lua - Main addon logic
    
    Requires the discord_rpc.dll to be loaded via VanillaFixes / dlls.txt.
    Collects game state, builds template variables, renders templates,
    and calls DiscordSetPresence().
]]

DiscordPresence_DB = DiscordPresence_DB or {}

local DP = CreateFrame("Frame", "DiscordPresenceFrame", UIParent)

local UPDATE_INTERVAL = 15
local DEBUG_ENABLED = false

local UnitName = UnitName
local UnitLevel = UnitLevel
local UnitClass = UnitClass
local UnitRace = UnitRace
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local GetRealZoneText = GetRealZoneText
local GetMinimapZoneText = GetMinimapZoneText
local GetNumPartyMembers = GetNumPartyMembers
local GetNumRaidMembers = GetNumRaidMembers
local GetTime = GetTime

local function Debug(msg)
    if not DEBUG_ENABLED then return end
    DEFAULT_CHAT_FRAME:AddMessage("|cff7289DA[DiscordPresence]|r " .. tostring(msg))
end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff7289DA[DiscordPresence]|r " .. tostring(msg))
end

-- =========================================================================
-- Build template variables from current game state
-- =========================================================================

local function BuildVariables()
    local playerName = UnitName("player")
    if not playerName then return nil end

    local localizedClass = UnitClass("player")
    local _, englishClass = UnitClass("player")
    local localizedRace = UnitRace("player")
    local playerLevel = UnitLevel("player")
    local zoneName = GetRealZoneText()
    local subZone = GetMinimapZoneText()

    if not zoneName or zoneName == "" then zoneName = "Unknown" end
    if subZone == zoneName then subZone = "" end

    local numRaid = GetNumRaidMembers and GetNumRaidMembers() or 0
    local numParty = GetNumPartyMembers and GetNumPartyMembers() or 0
    local isDead = UnitIsDeadOrGhost("player")

    local vars = {
        player_name = playerName or "",
        player_level = playerLevel and tostring(playerLevel) or "",
        player_class = englishClass or "",
        player_race = localizedRace or "",
        zone = zoneName or "",
        subzone = subZone or "",
        is_dead = isDead and "1" or "",
        in_party = (numParty > 0 and numRaid == 0) and "1" or "",
        in_raid = (numRaid > 0) and "1" or "",
        party_size = (numParty > 0 and numRaid == 0) and tostring(numParty + 1) or "",
        raid_size = (numRaid > 0) and tostring(numRaid) or "",
    }

    -- leader
    local isLeader = IsPartyLeader and IsPartyLeader() or false
    vars.is_leader = isLeader and "1" or ""
    if numRaid > 0 or numParty > 0 then
        -- find the leader name
        if UnitIsPartyLeader and UnitIsPartyLeader("player") then
            vars.leader_name = playerName
        else
            for i = 1, 4 do
                local unit = "party" .. i
                if UnitIsPartyLeader and UnitIsPartyLeader(unit) then
                    vars.leader_name = UnitName(unit) or ""
                    break
                end
            end
        end
    end
    if not vars.leader_name then vars.leader_name = "" end

    -- party member variables (party1 through party4)
    for i = 1, 4 do
        local unit = "party" .. i
        local name = UnitName(unit)
        local prefix = "party" .. i .. "_"
        if name then
            local _, cls = UnitClass(unit)
            vars[prefix .. "name"] = name
            vars[prefix .. "level"] = tostring(UnitLevel(unit) or "")
            vars[prefix .. "class"] = cls or ""
            vars[prefix .. "race"] = UnitRace(unit) or ""
        else
            vars[prefix .. "name"] = ""
            vars[prefix .. "level"] = ""
            vars[prefix .. "class"] = ""
            vars[prefix .. "race"] = ""
        end
    end

    return vars
end

-- =========================================================================
-- Compiled template cache
-- =========================================================================

local compiledTemplates = nil

function DiscordPresence_CompileTemplates()
    local t = DiscordPresence_Config.GetTemplates()
    if not t then
        compiledTemplates = nil
        return
    end
    local fields = { "details", "state", "large_image", "large_text", "small_image", "small_text" }
    local compiled = {}
    local had_error = false
    for i = 1, table.getn(fields) do
        local key = fields[i]
        local nodes, err = DiscordPresence_Template.Compile(t[key] or "")
        if err then
            Print("Template error in " .. key .. ": " .. err)
            had_error = true
        end
        compiled[key] = nodes
    end
    if had_error then Print("Using templates with errors - some fields may be empty") end
    compiledTemplates = compiled
    Debug("Templates compiled")
end

-- =========================================================================
-- Core: Render and send presence
-- =========================================================================

local DISCORD_MAX_LEN = 128

local function Truncate(s, limit)
    if not s then return "" end
    if string.len(s) > limit then
        return string.sub(s, 1, limit - 3) .. "..."
    end
    return s
end

local function UpdatePresence()
    if not DiscordSetPresence then
        Debug("DLL not loaded")
        return
    end
    local vars = BuildVariables()
    if not vars then return end
    if not compiledTemplates then DiscordPresence_CompileTemplates() end
    if not compiledTemplates then return end

    local details     = Truncate(DiscordPresence_Template.Render(compiledTemplates.details, vars), DISCORD_MAX_LEN)
    local state       = Truncate(DiscordPresence_Template.Render(compiledTemplates.state, vars), DISCORD_MAX_LEN)
    local largeImage  = DiscordPresence_Template.Render(compiledTemplates.large_image, vars)
    local largeText   = Truncate(DiscordPresence_Template.Render(compiledTemplates.large_text, vars), DISCORD_MAX_LEN)
    local smallImage  = DiscordPresence_Template.Render(compiledTemplates.small_image, vars)
    local smallText   = Truncate(DiscordPresence_Template.Render(compiledTemplates.small_text, vars), DISCORD_MAX_LEN)

    DiscordSetPresence(details, state, largeImage, largeText, smallImage, smallText)
    Debug("Updated: " .. details .. " | " .. state)
end

-- =========================================================================
-- OnUpdate timer
-- =========================================================================

DP:SetScript("OnUpdate", function()
    if (this.tick or 1) > GetTime() then return end
    this.tick = GetTime() + UPDATE_INTERVAL
    if not UnitName("player") then return end
    UpdatePresence()
end)

-- =========================================================================
-- Events
-- =========================================================================

DP:RegisterEvent("VARIABLES_LOADED")
DP:RegisterEvent("PLAYER_LOGIN")
DP:RegisterEvent("PLAYER_LOGOUT")
DP:RegisterEvent("ZONE_CHANGED_NEW_AREA")
DP:RegisterEvent("ZONE_CHANGED")
DP:RegisterEvent("ZONE_CHANGED_INDOORS")
DP:RegisterEvent("PARTY_MEMBERS_CHANGED")
DP:RegisterEvent("RAID_ROSTER_UPDATE")
DP:RegisterEvent("PLAYER_DEAD")
DP:RegisterEvent("PLAYER_ALIVE")
DP:RegisterEvent("PLAYER_UNGHOST")

DP:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        DiscordPresence_Config.InitDefaults()
        DiscordPresence_CompileTemplates()
        Debug("Config loaded, templates compiled")
    elseif event == "PLAYER_LOGIN" then
        Debug("Player logged in")
        this.tick = GetTime() + 3
    elseif event == "PLAYER_LOGOUT" then
        if DiscordClearPresence then DiscordClearPresence() end
    elseif event == "ZONE_CHANGED_NEW_AREA"
        or event == "ZONE_CHANGED"
        or event == "ZONE_CHANGED_INDOORS"
        or event == "PARTY_MEMBERS_CHANGED"
        or event == "RAID_ROSTER_UPDATE"
        or event == "PLAYER_DEAD"
        or event == "PLAYER_ALIVE"
        or event == "PLAYER_UNGHOST" then
        this.tick = GetTime() + 2
    end
end)

-- =========================================================================
-- Slash commands
-- =========================================================================

SLASH_DISCORDPRESENCE1 = "/discordpresence"
SLASH_DISCORDPRESENCE2 = "/dp"
SlashCmdList["DISCORDPRESENCE"] = function(msg)
    if msg == "status" then
        if DiscordIsConnected and DiscordIsConnected() then
            Print("Connected to Discord")
        else
            Print("Not connected to Discord")
        end
        Print("Active: " .. (DiscordPresence_DB.active or "none"))
    elseif msg == "update" then
        UpdatePresence()
        Print("Forced presence update")
    elseif msg == "clear" then
        if DiscordClearPresence then
            DiscordClearPresence()
            Print("Presence cleared")
        end
    elseif msg == "config" then
        DiscordPresence_Config.Toggle()
    elseif msg == "debug" then
        DEBUG_ENABLED = not DEBUG_ENABLED
        Print("Debug mode: " .. (DEBUG_ENABLED and "ON" or "OFF"))
    elseif string.sub(msg, 1, 7) == "preset " then
        local name = string.sub(msg, 8)
        if DiscordPresence_Config.ApplyPreset(name) then
            Print("Applied preset: " .. name)
        else
            Print("Unknown preset: " .. name)
        end
    elseif string.sub(msg, 1, 5) == "save " then
        local name = string.sub(msg, 6)
        if DiscordPresence_Config.SaveProfile(name) then
            Print("Saved profile: " .. name)
        else
            Print("Can't save (empty name or built-in preset name)")
        end
    elseif string.sub(msg, 1, 5) == "load " then
        local name = string.sub(msg, 6)
        if DiscordPresence_Config.LoadProfile(name) then
            Print("Loaded profile: " .. name)
        else
            Print("Profile not found: " .. name)
        end
    elseif string.sub(msg, 1, 6) == "clone " then
        local name = string.sub(msg, 7)
        if DiscordPresence_Config.CloneProfile(name) then
            Print("Cloned to: " .. name)
        else
            Print("Can't clone (empty or built-in name)")
        end
    elseif string.sub(msg, 1, 7) == "rename " then
        local args = string.sub(msg, 8)
        local _, _, old, new = string.find(args, "^(%S+)%s+(%S+)")
        if old and new then
            if DiscordPresence_Config.RenameProfile(old, new) then
                Print("Renamed: " .. old .. " -> " .. new)
            else
                Print("Can't rename (not found, built-in, or target exists)")
            end
        else
            Print("Usage: /dp rename <old> <new>")
        end
    elseif string.sub(msg, 1, 7) == "delete " then
        local name = string.sub(msg, 8)
        if DiscordPresence_Config.DeleteProfile(name) then
            Print("Deleted profile: " .. name)
        else
            Print("Can't delete (not found or built-in)")
        end
    elseif msg == "profiles" then
        local names = DiscordPresence_Config.GetProfileNames()
        if table.getn(names) == 0 then
            Print("No saved profiles. Use /dp save <name> to save one.")
        else
            Print("Saved profiles: " .. table.concat(names, ", "))
        end
    else
        Print("Commands:")
        Print("  /dp status   - connection status and active profile")
        Print("  /dp update   - force presence update")
        Print("  /dp clear    - clear presence")
        Print("  /dp config   - open config gui")
        Print("  /dp preset <name>    - load built-in (minimal/default/detailed)")
        Print("  /dp save <name>      - save current templates as profile")
        Print("  /dp load <name>      - load a saved profile")
        Print("  /dp clone <name>     - clone current templates to new profile")
        Print("  /dp rename <old> <new> - rename a profile")
        Print("  /dp delete <name>    - delete a saved profile")
        Print("  /dp profiles         - list saved profiles")
        Print("  /dp debug    - toggle debug messages")
    end
end
