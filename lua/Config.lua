--[[
    Config.lua - Configuration GUI and profile management for Discord Presence

    Built-in presets (minimal/default/detailed) are read-only.
    Editing a preset auto-clones it as a user profile.
    User profiles are stored in DiscordPresence_DB.profiles.
]]

DiscordPresence_Config = {}

local FRAME_WIDTH = 540
local FRAME_HEIGHT = 540
local FIELD_HEIGHT = 24
local MULTI_HEIGHT = 60
local LABEL_WIDTH = 80
local PADDING = 12

local configFrame = nil

local TEMPLATE_FIELDS = {
    { key = "details",     label = "Details",     multi = true },
    { key = "state",       label = "State",       multi = true },
    { key = "large_image", label = "Large Icon",  multi = false },
    { key = "large_text",  label = "Large Text",  multi = false },
    { key = "small_image", label = "Small Icon",  multi = false },
    { key = "small_text",  label = "Small Text",  multi = false },
}

local editors = {}

-- =========================================================================
-- Helpers
-- =========================================================================

local function CopyTemplates(src)
    local copy = {}
    for k, v in pairs(src or {}) do
        copy[k] = v
    end
    return copy
end

local function IsBuiltIn(name)
    return DiscordPresence_Presets.Get(name) ~= nil
end

-- =========================================================================
-- Init
-- =========================================================================

function DiscordPresence_Config.InitDefaults()
    if not DiscordPresence_DB then DiscordPresence_DB = {} end
    if not DiscordPresence_DB.profiles then DiscordPresence_DB.profiles = {} end
    if not DiscordPresence_DB.active then DiscordPresence_DB.active = "default" end
    if not DiscordPresence_DB.templates then
        local default = DiscordPresence_Presets.GetDefault()
        DiscordPresence_DB.templates = CopyTemplates(default.templates)
    end
end

function DiscordPresence_Config.GetTemplates()
    return DiscordPresence_DB.templates
end

-- =========================================================================
-- Profile management
-- =========================================================================

-- Load a built-in preset (read-only, editing will auto-clone)
function DiscordPresence_Config.ApplyPreset(name)
    local preset = DiscordPresence_Presets.Get(name)
    if not preset then return false end
    DiscordPresence_DB.active = name
    DiscordPresence_DB.templates = CopyTemplates(preset.templates)
    DiscordPresence_Config.RefreshEditors()
    if DiscordPresence_CompileTemplates then
        DiscordPresence_CompileTemplates()
    end
    return true
end

-- Save current templates as a user profile
function DiscordPresence_Config.SaveProfile(name)
    if not name or name == "" then return false end
    if IsBuiltIn(name) then return false end
    if not DiscordPresence_DB.profiles then DiscordPresence_DB.profiles = {} end
    DiscordPresence_DB.profiles[name] = CopyTemplates(DiscordPresence_DB.templates)
    DiscordPresence_DB.active = name
    DiscordPresence_Config.RefreshLabel()
    return true
end

-- Load a user profile
function DiscordPresence_Config.LoadProfile(name)
    -- try user profile first, then built-in preset
    if DiscordPresence_DB.profiles and DiscordPresence_DB.profiles[name] then
        DiscordPresence_DB.active = name
        DiscordPresence_DB.templates = CopyTemplates(DiscordPresence_DB.profiles[name])
        DiscordPresence_Config.RefreshEditors()
        if DiscordPresence_CompileTemplates then
            DiscordPresence_CompileTemplates()
        end
        return true
    end
    return DiscordPresence_Config.ApplyPreset(name)
end

-- Clone current templates into a new profile
function DiscordPresence_Config.CloneProfile(name)
    if not name or name == "" then return false end
    if IsBuiltIn(name) then return false end
    if not DiscordPresence_DB.profiles then DiscordPresence_DB.profiles = {} end
    DiscordPresence_DB.profiles[name] = CopyTemplates(DiscordPresence_DB.templates)
    DiscordPresence_DB.active = name
    DiscordPresence_Config.RefreshLabel()
    return true
end

-- Rename a user profile
function DiscordPresence_Config.RenameProfile(old_name, new_name)
    if not old_name or not new_name or old_name == "" or new_name == "" then return false end
    if IsBuiltIn(old_name) or IsBuiltIn(new_name) then return false end
    if not DiscordPresence_DB.profiles then return false end
    if not DiscordPresence_DB.profiles[old_name] then return false end
    if DiscordPresence_DB.profiles[new_name] then return false end -- don't overwrite
    DiscordPresence_DB.profiles[new_name] = DiscordPresence_DB.profiles[old_name]
    DiscordPresence_DB.profiles[old_name] = nil
    if DiscordPresence_DB.active == old_name then
        DiscordPresence_DB.active = new_name
    end
    DiscordPresence_Config.RefreshLabel()
    return true
end

-- Delete a user profile
function DiscordPresence_Config.DeleteProfile(name)
    if IsBuiltIn(name) then return false end
    if not DiscordPresence_DB.profiles then return false end
    if not DiscordPresence_DB.profiles[name] then return false end
    DiscordPresence_DB.profiles[name] = nil
    -- if we deleted the active profile, fall back to default
    if DiscordPresence_DB.active == name then
        DiscordPresence_Config.ApplyPreset("default")
    end
    return true
end

-- Get list of user profile names
function DiscordPresence_Config.GetProfileNames()
    local names = {}
    if DiscordPresence_DB.profiles then
        for k, _ in pairs(DiscordPresence_DB.profiles) do
            table.insert(names, k)
        end
    end
    table.sort(names)
    return names
end

-- =========================================================================
-- Save editors (auto-clones if editing a built-in preset)
-- =========================================================================

local function SaveEditors()
    if not DiscordPresence_DB then return end
    if not DiscordPresence_DB.templates then DiscordPresence_DB.templates = {} end
    for i = 1, table.getn(TEMPLATE_FIELDS) do
        local key = TEMPLATE_FIELDS[i].key
        if editors[key] then
            DiscordPresence_DB.templates[key] = editors[key]:GetText()
        end
    end

    -- auto-clone: if editing a built-in preset, save as "presetname (custom)"
    local active = DiscordPresence_DB.active or ""
    if IsBuiltIn(active) then
        local clone_name = active .. " (custom)"
        if not DiscordPresence_DB.profiles then DiscordPresence_DB.profiles = {} end
        DiscordPresence_DB.profiles[clone_name] = CopyTemplates(DiscordPresence_DB.templates)
        DiscordPresence_DB.active = clone_name
    else
        -- save back to existing user profile
        if DiscordPresence_DB.profiles and DiscordPresence_DB.profiles[active] then
            DiscordPresence_DB.profiles[active] = CopyTemplates(DiscordPresence_DB.templates)
        end
    end

    if DiscordPresence_CompileTemplates then
        DiscordPresence_CompileTemplates()
    end
    DiscordPresence_Config.RefreshLabel()
end

function DiscordPresence_Config.RefreshEditors()
    if not DiscordPresence_DB or not DiscordPresence_DB.templates then return end
    for key, eb in pairs(editors) do
        eb:SetText(DiscordPresence_DB.templates[key] or "")
    end
    DiscordPresence_Config.RefreshLabel()
end

function DiscordPresence_Config.RefreshLabel()
    if configFrame and configFrame.activeLabel then
        local active = DiscordPresence_DB.active or "none"
        local label = "Active: " .. active
        if IsBuiltIn(active) then
            label = label .. " (read-only)"
        end
        configFrame.activeLabel:SetText(label)
    end
end

-- =========================================================================
-- GUI helpers
-- =========================================================================

local function MakeEditBox(parent, name, width, height)
    local eb = CreateFrame("EditBox", name, parent)
    eb:SetWidth(width)
    eb:SetHeight(height)
    eb:SetFontObject(ChatFontNormal)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(512)
    eb:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    eb:SetBackdropColor(0, 0, 0, 0.7)
    eb:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    eb:SetTextInsets(4, 4, 2, 2)
    eb:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function()
        this:ClearFocus()
        SaveEditors()
    end)
    eb:SetScript("OnEditFocusLost", function() SaveEditors() end)
    return eb
end

local function MakeMultiEditBox(parent, name, width, height)
    local sf = CreateFrame("ScrollFrame", name .. "_Scroll", parent)
    sf:SetWidth(width)
    sf:SetHeight(height)
    sf:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    sf:SetBackdropColor(0, 0, 0, 0.7)
    sf:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    sf:EnableMouseWheel(true)

    local eb = CreateFrame("EditBox", name, sf)
    eb:SetWidth(width - 10)
    eb:SetFontObject(ChatFontNormal)
    eb:SetAutoFocus(false)
    eb:SetMultiLine(true)
    eb:SetMaxLetters(1024)
    eb:SetTextInsets(4, 4, 4, 4)
    sf:SetScrollChild(eb)

    sf:SetScript("OnMouseWheel", function()
        local cur = sf:GetVerticalScroll()
        local max = eb:GetHeight() - sf:GetHeight()
        if max < 0 then max = 0 end
        local new = cur - (arg1 * 20)
        if new < 0 then new = 0 end
        if new > max then new = max end
        sf:SetVerticalScroll(new)
    end)
    eb:SetScript("OnCursorChanged", function()
        local _, y = 0, -arg2
        local offset = sf:GetVerticalScroll()
        local h = sf:GetHeight()
        if y < offset then
            sf:SetVerticalScroll(y)
        elseif y + arg4 > offset + h then
            sf:SetVerticalScroll(y + arg4 - h)
        end
    end)
    eb:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    eb:SetScript("OnEditFocusLost", function() SaveEditors() end)
    sf:SetScript("OnMouseDown", function() eb:SetFocus() end)

    eb.scrollFrame = sf
    return eb, sf
end

-- =========================================================================
-- Build frame
-- =========================================================================

local function BuildFrame()
    local f = CreateFrame("Frame", "DiscordPresenceConfigFrame", UIParent)
    f:SetWidth(FRAME_WIDTH)
    f:SetHeight(FRAME_HEIGHT)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    local drag = CreateFrame("Frame", nil, f)
    drag:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -12)
    drag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -32, -12)
    drag:SetHeight(20)
    drag:EnableMouse(true)
    drag:SetScript("OnMouseDown", function() f:StartMoving() end)
    drag:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING + 4, -PADDING - 2)
    title:SetText("|cff7289DADiscord|cffffffffPresence")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

    local yOff = -40

    -- =====================================================================
    -- Built-in presets row
    -- =====================================================================

    local pl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pl:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING, yOff)
    pl:SetText("Presets:")
    pl:SetTextColor(0.8, 0.8, 0.8)

    local names = DiscordPresence_Presets.GetNames()
    local btnX = PADDING + 55
    for i = 1, table.getn(names) do
        local pname = names[i]
        local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", btnX, yOff + 2)
        btn:SetWidth(70)
        btn:SetHeight(20)
        btn:SetText(pname)
        btn:SetScript("OnClick", function()
            DiscordPresence_Config.ApplyPreset(pname)
        end)
        btnX = btnX + 75
    end

    yOff = yOff - 26

    -- =====================================================================
    -- Profile row: name input + save/load/clone/rename/delete
    -- =====================================================================

    local profileLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    profileLabel:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING, yOff)
    profileLabel:SetText("Profile:")
    profileLabel:SetTextColor(0.8, 0.8, 0.8)

    local profileInput = MakeEditBox(f, "DP_ProfileName", 120, 20)
    profileInput:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING + 55, yOff + 2)
    profileInput:SetScript("OnEditFocusLost", function() end) -- don't auto-save

    local function MakeSmallBtn(text, x, onClick)
        local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", x, yOff + 2)
        btn:SetWidth(50)
        btn:SetHeight(20)
        btn:SetText(text)
        btn:SetScript("OnClick", onClick)
        return btn
    end

    local bx = PADDING + 180
    MakeSmallBtn("Save", bx, function()
        local name = profileInput:GetText()
        if DiscordPresence_Config.SaveProfile(name) then
            DEFAULT_CHAT_FRAME:AddMessage("|cff7289DA[DP]|r Saved profile: " .. name)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[DP]|r Can't save (empty or built-in name)")
        end
    end)
    bx = bx + 54

    MakeSmallBtn("Load", bx, function()
        local name = profileInput:GetText()
        if DiscordPresence_Config.LoadProfile(name) then
            DEFAULT_CHAT_FRAME:AddMessage("|cff7289DA[DP]|r Loaded: " .. name)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[DP]|r Not found: " .. name)
        end
    end)
    bx = bx + 54

    MakeSmallBtn("Clone", bx, function()
        local name = profileInput:GetText()
        if DiscordPresence_Config.CloneProfile(name) then
            DEFAULT_CHAT_FRAME:AddMessage("|cff7289DA[DP]|r Cloned to: " .. name)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[DP]|r Can't clone (empty or built-in name)")
        end
    end)
    bx = bx + 54

    MakeSmallBtn("Delete", bx, function()
        local name = profileInput:GetText()
        if DiscordPresence_Config.DeleteProfile(name) then
            DEFAULT_CHAT_FRAME:AddMessage("|cff7289DA[DP]|r Deleted: " .. name)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[DP]|r Can't delete (not found or built-in)")
        end
    end)

    yOff = yOff - 26

    -- Active label
    local activeLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    activeLabel:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING, yOff)
    activeLabel:SetTextColor(0.4, 0.8, 0.4)
    f.activeLabel = activeLabel

    yOff = yOff - 20

    -- =====================================================================
    -- Template editors
    -- =====================================================================

    local editWidth = FRAME_WIDTH - PADDING * 2 - LABEL_WIDTH - 24

    for i = 1, table.getn(TEMPLATE_FIELDS) do
        local field = TEMPLATE_FIELDS[i]

        local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING, yOff - 4)
        label:SetWidth(LABEL_WIDTH)
        label:SetJustifyH("RIGHT")
        label:SetText(field.label)
        label:SetTextColor(0.9, 0.9, 0.9)

        if field.multi then
            local eb, sf = MakeMultiEditBox(f, "DP_Edit_" .. field.key, editWidth, MULTI_HEIGHT)
            sf:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING + LABEL_WIDTH + 8, yOff)
            editors[field.key] = eb
            yOff = yOff - (MULTI_HEIGHT + 6)
        else
            local eb = MakeEditBox(f, "DP_Edit_" .. field.key, editWidth, FIELD_HEIGHT)
            eb:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING + LABEL_WIDTH + 8, yOff)
            editors[field.key] = eb
            yOff = yOff - (FIELD_HEIGHT + 6)
        end
    end

    yOff = yOff - 4

    -- =====================================================================
    -- Help text
    -- =====================================================================

    local help = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    help:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING, yOff)
    help:SetWidth(FRAME_WIDTH - PADDING * 2)
    help:SetJustifyH("LEFT")
    help:SetTextColor(0.6, 0.6, 0.6)
    help:SetText(
        "|cff7289DAVariables:|r  player_name  player_level  player_class  player_race  zone  subzone\n" ..
        "|cff7289DABooleans:|r  is_dead  in_party  in_raid  party_size  raid_size\n" ..
        "|cff7289DAFunctions:|r  lower  upper  title  default \"str\"\n" ..
        "|cff7289DASyntax:|r  {{var}}  {{var | func}}  {{#if var}}...{{#else}}...{{/if}}\n" ..
        "|cff7289DAWhitespace:|r  {{~expr}} strip before  {{expr~}} strip after  {{~expr~}} both"
    )

    table.insert(UISpecialFrames, "DiscordPresenceConfigFrame")
    configFrame = f
    return f
end

-- =========================================================================
-- Toggle
-- =========================================================================

function DiscordPresence_Config.Toggle()
    if configFrame and configFrame:IsShown() then
        configFrame:Hide()
        return
    end
    if not configFrame then
        BuildFrame()
    end
    DiscordPresence_Config.RefreshEditors()
    configFrame:Show()
end
