--[[
    DiscordPresence.lua - Main addon entrypoint

    Orchestrates all modules:
      Template.lua   - template engine
      Presets.lua    - built-in presets
      Variables.lua  - game state collection
      Config.lua     - GUI + profile management

    Handles: events, timer, compiled template cache, slash commands.
]]

DiscordPresence_DB = DiscordPresence_DB or {}

local DP = CreateFrame("Frame", "DiscordPresenceFrame", UIParent)

local UPDATE_INTERVAL = 15
local QUICK_UPDATE = 0.25

local Print = DiscordPresence_Utils.Print
local Debug = DiscordPresence_Utils.Debug

-- compiled template cache
local compiledTemplates = nil

function DiscordPresence_CompileTemplates()
    local t = DiscordPresence_DB.templates
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

local function UpdatePresence()
    if not DiscordSetPresence then
        Debug("DLL not loaded")
        return
    end
    local vars = DiscordPresence_Vars.Build()
    if not vars then return end
    if not compiledTemplates then DiscordPresence_CompileTemplates() end

    local f = DiscordPresence_Vars.RenderFields(compiledTemplates, vars)
    if not f then return end

    local partySize = 0
    local partyMax = 0
    if DiscordPresence_DB.show_party then
        local numRaid = GetNumRaidMembers and GetNumRaidMembers() or 0
        local numParty = GetNumPartyMembers and GetNumPartyMembers() or 0
        if numRaid > 0 then
            partySize = numRaid
            partyMax = 40
        elseif numParty > 0 then
            partySize = numParty + 1
            partyMax = 5
        end
    end

    DiscordSetPresence(f.details, f.state, f.largeImage, f.largeText, f.smallImage, f.smallText, partySize, partyMax)
    Debug("Updated: " .. f.details .. " | " .. f.state)
end

-- timer
DP:SetScript("OnUpdate", function()
    if (this.tick or 1) > GetTime() then return end
    this.tick = GetTime() + UPDATE_INTERVAL
    if not UnitName("player") then return end
    UpdatePresence()
end)

-- events (dispatch table)
local function QuickUpdate()
    DP.tick = GetTime() + QUICK_UPDATE
end

local EVENT_HANDLERS = {
    VARIABLES_LOADED = function()
        DiscordPresence_Config.InitDefaults()
        DiscordPresence_CompileTemplates()
        Debug("Config loaded, templates compiled")
    end,
    PLAYER_LOGIN = function()
        Debug("Player logged in")
        QuickUpdate()
    end,
    PLAYER_LOGOUT = function()
        if DiscordClearPresence then DiscordClearPresence() end
    end,
}

local QUICK_EVENTS = {
    "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
    "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE",
    "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
    "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE",
}

for _, evt in ipairs(QUICK_EVENTS) do
    EVENT_HANDLERS[evt] = QuickUpdate
end

for evt, _ in pairs(EVENT_HANDLERS) do
    DP:RegisterEvent(evt)
end

DP:SetScript("OnEvent", function()
    local handler = EVENT_HANDLERS[event]
    if handler then handler() end
end)

-- slash commands (dispatch table)
local COMMANDS = {}

COMMANDS["status"] = function()
    if DiscordIsConnected and DiscordIsConnected() then
        Print("Connected to Discord")
    else
        Print("Not connected to Discord")
    end
    Print("Active: " .. (DiscordPresence_DB.active or "none"))
    local vars = DiscordPresence_Vars.Build()
    if vars and compiledTemplates then
        local f = DiscordPresence_Vars.RenderFields(compiledTemplates, vars)
        if f then
            Print("  details:     " .. f.details)
            Print("  state:       " .. f.state)
            Print("  large_image: " .. f.largeImage)
            Print("  large_text:  " .. f.largeText)
            Print("  small_image: " .. f.smallImage)
            Print("  small_text:  " .. f.smallText)
        end
    end
end

COMMANDS["update"] = function()
    UpdatePresence()
    Print("Forced presence update")
end

COMMANDS["clear"] = function()
    if DiscordClearPresence then
        DiscordClearPresence()
        Print("Presence cleared")
    end
end

COMMANDS["config"] = function()
    DiscordPresence_Config.Toggle()
end

COMMANDS["debug"] = function()
    DEBUG = not DEBUG
    Print("Debug mode: " .. (DEBUG and "ON" or "OFF"))
end

COMMANDS["preset"] = function(args)
    local sub = args or ""
    local _, _, cmd, rest = string.find(sub, "^(%S+)%s*(.*)")
    if not cmd then cmd = "" end

    if cmd == "list" then
        Print("Profiles: " .. table.concat(DiscordPresence_Config.GetProfileNames(), ", "))
    elseif cmd == "save" and rest ~= "" then
        if DiscordPresence_Config.SaveProfileAs(rest) then
            Print("Saved as: " .. rest)
        else
            Print("Can't save")
        end
    elseif cmd == "clone" and rest ~= "" then
        if DiscordPresence_Config.CloneProfile(rest) then
            Print("Cloned to: " .. rest)
        else
            Print("Can't clone (name empty or exists)")
        end
    elseif cmd == "rename" then
        local _, _, old, new = string.find(rest, "^(%S+)%s+(%S+)")
        if old and new then
            if DiscordPresence_Config.RenameProfile(old, new) then
                Print("Renamed: " .. old .. " -> " .. new)
            else
                Print("Can't rename (not found, protected, or target exists)")
            end
        else
            Print("Usage: /dp preset rename <old> <new>")
        end
    elseif cmd == "delete" and rest ~= "" then
        if DiscordPresence_Config.DeleteProfile(rest) then
            Print("Deleted: " .. rest)
        else
            Print("Can't delete (not found or built-in)")
        end
    elseif cmd == "reset" and rest ~= "" then
        if DiscordPresence_Config.ResetProfile(rest) then
            Print("Reset: " .. rest)
        else
            Print("Can only reset built-in profiles (minimal/default/detailed)")
        end
    else
        if cmd ~= "" then
            if DiscordPresence_Config.LoadProfile(cmd) then
                Print("Loaded: " .. cmd)
            else
                Print("Not found: " .. cmd)
            end
        else
            Print([[
Preset commands:
  /dp preset <name>              - load a profile
  /dp preset list                - list all profiles
  /dp preset save <name>         - save current as new profile
  /dp preset clone <name>        - clone current to new profile
  /dp preset rename <old> <new>  - rename a profile
  /dp preset delete <name>       - delete a profile (not built-in)
  /dp preset reset <name>        - reset built-in to defaults]])
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
        Print([[
Commands:
  /dp status     - connection + template preview
  /dp update     - force presence update
  /dp clear      - clear presence
  /dp config     - open config gui
  /dp preset     - preset/profile management
  /dp debug      - toggle debug messages]])
    end
end
