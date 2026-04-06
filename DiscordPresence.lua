--[[
    DiscordPresence.lua - Main addon logic
    
    Requires the discord_rpc.dll to be loaded via VanillaFixes / dlls.txt.
    Collects game state, builds template variables, renders templates,
    and calls DiscordSetPresence().
]]

DiscordPresence_DB = DiscordPresence_DB or {}

local DP = CreateFrame("Frame", "DiscordPresenceFrame", UIParent)

-- =========================================================================
-- Locals
-- =========================================================================

local L = {
    UPDATE_INTERVAL = 15,
    QUICK_UPDATE = 0.25,
    DEBUG = false,
    MAX_LEN = 128,
    PREFIX = "|cff7289DA[DiscordPresence]|r ",
}

function L.Debug(msg)
    if not L.DEBUG then return end
    DEFAULT_CHAT_FRAME:AddMessage(L.PREFIX .. tostring(msg))
end

function L.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(L.PREFIX .. tostring(msg))
end

function L.Truncate(s, limit)
    if not s then return "" end
    if string.len(s) > limit then
        return string.sub(s, 1, limit - 3) .. "..."
    end
    return s
end

-- =========================================================================
-- Build template variables from current game state
-- =========================================================================

function L.BuildVariables()
    local playerName = UnitName("player")
    if not playerName then return nil end

    local localizedClass = UnitClass("player")
    local localizedRace = UnitRace("player")
    local playerLevel = UnitLevel("player")
    local zoneName = GetRealZoneText()
    local subZone = GetMinimapZoneText()

    if not zoneName or zoneName == "" then zoneName = "Unknown" end
    if subZone == zoneName then subZone = "" end

    local numRaid = GetNumRaidMembers and GetNumRaidMembers() or 0
    local numParty = GetNumPartyMembers and GetNumPartyMembers() or 0
    local isDead = UnitIsDeadOrGhost("player")

    local xp = UnitXP and UnitXP("player") or 0
    local xpMax = UnitXPMax and UnitXPMax("player") or 0

    local vars = {
        player_name = playerName or "",
        player_level = playerLevel and tostring(playerLevel) or "",
        player_class = localizedClass or "",
        player_race = localizedRace or "",
        zone = zoneName or "",
        subzone = subZone or "",
        is_dead = isDead and "1" or "",
        in_party = (numParty > 0 and numRaid == 0) and "1" or "",
        in_raid = (numRaid > 0) and "1" or "",
        party_size = (numParty > 0 and numRaid == 0) and tostring(numParty + 1) or "",
        raid_size = (numRaid > 0) and tostring(numRaid) or "",
        xp = tostring(xp),
        xp_max = tostring(xpMax),
        xp_remaining = tostring(xpMax - xp),
        is_max_level = (xpMax == 0) and "1" or "",
    }

    -- leader
    local isLeader = IsPartyLeader and IsPartyLeader() or false
    vars.is_leader = isLeader and "1" or ""
    if numRaid > 0 or numParty > 0 then
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

    -- party members (party1 through party4)
    for i = 1, 4 do
        local unit = "party" .. i
        local name = UnitName(unit)
        local p = "party" .. i .. "_"
        if name then
            vars[p .. "name"] = name
            vars[p .. "level"] = tostring(UnitLevel(unit) or "")
            vars[p .. "class"] = UnitClass(unit) or ""
            vars[p .. "race"] = UnitRace(unit) or ""
        else
            vars[p .. "name"] = ""
            vars[p .. "level"] = ""
            vars[p .. "class"] = ""
            vars[p .. "race"] = ""
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
            L.Print("Template error in " .. key .. ": " .. err)
            had_error = true
        end
        compiled[key] = nodes
    end
    if had_error then L.Print("Using templates with errors - some fields may be empty") end
    compiledTemplates = compiled
    L.Debug("Templates compiled")
end

-- =========================================================================
-- Render all fields from compiled templates + vars
-- =========================================================================

function L.RenderFields(vars)
    if not compiledTemplates then return nil end
    return {
        details    = L.Truncate(DiscordPresence_Template.Render(compiledTemplates.details, vars), L.MAX_LEN),
        state      = L.Truncate(DiscordPresence_Template.Render(compiledTemplates.state, vars), L.MAX_LEN),
        largeImage = DiscordPresence_Template.Render(compiledTemplates.large_image, vars),
        largeText  = L.Truncate(DiscordPresence_Template.Render(compiledTemplates.large_text, vars), L.MAX_LEN),
        smallImage = DiscordPresence_Template.Render(compiledTemplates.small_image, vars),
        smallText  = L.Truncate(DiscordPresence_Template.Render(compiledTemplates.small_text, vars), L.MAX_LEN),
    }
end

-- =========================================================================
-- Send presence update
-- =========================================================================

local function UpdatePresence()
    if not DiscordSetPresence then
        L.Debug("DLL not loaded")
        return
    end
    local vars = L.BuildVariables()
    if not vars then return end
    if not compiledTemplates then DiscordPresence_CompileTemplates() end

    local f = L.RenderFields(vars)
    if not f then return end

    DiscordSetPresence(f.details, f.state, f.largeImage, f.largeText, f.smallImage, f.smallText)
    L.Debug("Updated: " .. f.details .. " | " .. f.state)
end

-- =========================================================================
-- OnUpdate timer
-- =========================================================================

DP:SetScript("OnUpdate", function()
    if (this.tick or 1) > GetTime() then return end
    this.tick = GetTime() + L.UPDATE_INTERVAL
    if not UnitName("player") then return end
    UpdatePresence()
end)

-- =========================================================================
-- Events (dispatch table)
-- =========================================================================

local function QuickUpdate()
    DP.tick = GetTime() + L.QUICK_UPDATE
end

local EVENT_HANDLERS = {
    VARIABLES_LOADED = function()
        DiscordPresence_Config.InitDefaults()
        DiscordPresence_CompileTemplates()
        L.Debug("Config loaded, templates compiled")
    end,
    PLAYER_LOGIN = function()
        L.Debug("Player logged in")
        QuickUpdate()
    end,
    PLAYER_LOGOUT = function()
        if DiscordClearPresence then DiscordClearPresence() end
    end,
}

local QUICK_UPDATE_EVENTS = {
    "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
    "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE",
    "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
    "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE",
}

for _, evt in ipairs(QUICK_UPDATE_EVENTS) do
    EVENT_HANDLERS[evt] = QuickUpdate
end

for evt, _ in pairs(EVENT_HANDLERS) do
    DP:RegisterEvent(evt)
end

DP:SetScript("OnEvent", function()
    local handler = EVENT_HANDLERS[event]
    if handler then handler() end
end)

-- =========================================================================
-- Slash commands (dispatch table)
-- =========================================================================

local COMMANDS = {}

COMMANDS["status"] = function()
    if DiscordIsConnected and DiscordIsConnected() then
        L.Print("Connected to Discord")
    else
        L.Print("Not connected to Discord")
    end
    L.Print("Active: " .. (DiscordPresence_DB.active or "none"))
    -- preview rendered fields
    local vars = L.BuildVariables()
    if vars and compiledTemplates then
        local f = L.RenderFields(vars)
        if f then
            L.Print("  details:     " .. f.details)
            L.Print("  state:       " .. f.state)
            L.Print("  large_image: " .. f.largeImage)
            L.Print("  large_text:  " .. f.largeText)
            L.Print("  small_image: " .. f.smallImage)
            L.Print("  small_text:  " .. f.smallText)
        end
    end
end

COMMANDS["update"] = function()
    UpdatePresence()
    L.Print("Forced presence update")
end

COMMANDS["clear"] = function()
    if DiscordClearPresence then
        DiscordClearPresence()
        L.Print("Presence cleared")
    end
end

COMMANDS["config"] = function()
    DiscordPresence_Config.Toggle()
end

COMMANDS["debug"] = function()
    L.DEBUG = not L.DEBUG
    L.Print("Debug mode: " .. (L.DEBUG and "ON" or "OFF"))
end

-- /dp preset <subcommand>
COMMANDS["preset"] = function(args)
    local sub = args or ""
    local _, _, cmd, rest = string.find(sub, "^(%S+)%s*(.*)")
    if not cmd then cmd = "" end

    if cmd == "list" then
        L.Print("Built-in: " .. table.concat(DiscordPresence_Presets.GetNames(), ", "))
        local profiles = DiscordPresence_Config.GetProfileNames()
        if table.getn(profiles) > 0 then
            L.Print("Profiles: " .. table.concat(profiles, ", "))
        end
    elseif cmd == "load" and rest ~= "" then
        if DiscordPresence_Config.LoadProfile(rest) then
            L.Print("Loaded: " .. rest)
        elseif DiscordPresence_Config.ApplyPreset(rest) then
            L.Print("Applied preset: " .. rest)
        else
            L.Print("Not found: " .. rest)
        end
    elseif cmd == "save" and rest ~= "" then
        if DiscordPresence_Config.SaveProfile(rest) then
            L.Print("Saved profile: " .. rest)
        else
            L.Print("Can't save (empty or built-in name)")
        end
    elseif cmd == "clone" and rest ~= "" then
        if DiscordPresence_Config.CloneProfile(rest) then
            L.Print("Cloned to: " .. rest)
        else
            L.Print("Can't clone (empty or built-in name)")
        end
    elseif cmd == "rename" then
        local _, _, old, new = string.find(rest, "^(%S+)%s+(%S+)")
        if old and new then
            if DiscordPresence_Config.RenameProfile(old, new) then
                L.Print("Renamed: " .. old .. " -> " .. new)
            else
                L.Print("Can't rename (not found, built-in, or target exists)")
            end
        else
            L.Print("Usage: /dp preset rename <old> <new>")
        end
    elseif cmd == "delete" and rest ~= "" then
        if DiscordPresence_Config.DeleteProfile(rest) then
            L.Print("Deleted: " .. rest)
        else
            L.Print("Can't delete (not found or built-in)")
        end
    else
        -- bare "/dp preset <name>" loads directly
        if cmd ~= "" then
            if DiscordPresence_Config.LoadProfile(cmd) then
                L.Print("Loaded: " .. cmd)
            elseif DiscordPresence_Config.ApplyPreset(cmd) then
                L.Print("Applied preset: " .. cmd)
            else
                L.Print("Not found: " .. cmd)
            end
        else
            L.Print("Preset commands:")
            L.Print("  /dp preset <name>              - load preset or profile")
            L.Print("  /dp preset list                - list all presets and profiles")
            L.Print("  /dp preset save <name>         - save current as profile")
            L.Print("  /dp preset clone <name>        - clone current to new profile")
            L.Print("  /dp preset rename <old> <new>  - rename a profile")
            L.Print("  /dp preset delete <name>       - delete a profile")
        end
    end
end

SLASH_DISCORDPRESENCE1 = "/discordpresence"
SLASH_DISCORDPRESENCE2 = "/dp"
SlashCmdList["DISCORDPRESENCE"] = function(msg)
    local _, _, cmd, rest = string.find(msg or "", "^(%S+)%s*(.*)")
    if not cmd then cmd = "" end

    local handler = COMMANDS[cmd]
    if handler then
        handler(rest)
    else
        L.Print("Commands:")
        L.Print("  /dp status     - connection + template preview")
        L.Print("  /dp update     - force presence update")
        L.Print("  /dp clear      - clear presence")
        L.Print("  /dp config     - open config gui")
        L.Print("  /dp preset     - preset/profile management")
        L.Print("  /dp debug      - toggle debug messages")
    end
end
