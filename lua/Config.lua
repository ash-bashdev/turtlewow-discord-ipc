--[[
    Config.lua - Configuration GUI for Discord Presence

    Opens with /dp config. Shows preset buttons, editable template fields
    (multiline for details/state), and syntax help.
]]

DiscordPresence_Config = {}

local FRAME_WIDTH = 540
local FRAME_HEIGHT = 500
local FIELD_HEIGHT = 24
local MULTI_HEIGHT = 60
local LABEL_WIDTH = 80
local PADDING = 12

local configFrame = nil

-- Template fields: multiline = true gets a scrollable multiline editor
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
-- Init / Getters
-- =========================================================================

function DiscordPresence_Config.InitDefaults()
    if not DiscordPresence_DB then DiscordPresence_DB = {} end
    if not DiscordPresence_DB.preset then DiscordPresence_DB.preset = "default" end
    if not DiscordPresence_DB.templates then
        local default = DiscordPresence_Presets.GetDefault()
        DiscordPresence_DB.templates = {}
        for k, v in pairs(default.templates) do
            DiscordPresence_DB.templates[k] = v
        end
    end
end

function DiscordPresence_Config.GetTemplates()
    return DiscordPresence_DB.templates
end

function DiscordPresence_Config.ApplyPreset(name)
    local preset = DiscordPresence_Presets.Get(name)
    if not preset then return end
    DiscordPresence_DB.preset = name
    DiscordPresence_DB.templates = {}
    for k, v in pairs(preset.templates) do
        DiscordPresence_DB.templates[k] = v
    end
    DiscordPresence_Config.RefreshEditors()
    if DiscordPresence_CompileTemplates then
        DiscordPresence_CompileTemplates()
    end
end

-- =========================================================================
-- Save / Refresh
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
    DiscordPresence_DB.preset = "custom"
    if DiscordPresence_CompileTemplates then
        DiscordPresence_CompileTemplates()
    end
    if configFrame and configFrame.presetLabel then
        configFrame.presetLabel:SetText("Current: custom")
    end
end

function DiscordPresence_Config.RefreshEditors()
    if not DiscordPresence_DB or not DiscordPresence_DB.templates then return end
    for key, eb in pairs(editors) do
        eb:SetText(DiscordPresence_DB.templates[key] or "")
    end
    if configFrame and configFrame.presetLabel then
        configFrame.presetLabel:SetText("Current: " .. (DiscordPresence_DB.preset or "custom"))
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
    -- Scroll frame container
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

    -- Edit box inside scroll frame
    local eb = CreateFrame("EditBox", name, sf)
    eb:SetWidth(width - 10)
    eb:SetFontObject(ChatFontNormal)
    eb:SetAutoFocus(false)
    eb:SetMultiLine(true)
    eb:SetMaxLetters(1024)
    eb:SetTextInsets(4, 4, 4, 4)

    sf:SetScrollChild(eb)

    -- Mouse wheel scrolling
    sf:SetScript("OnMouseWheel", function()
        local cur = sf:GetVerticalScroll()
        local max = eb:GetHeight() - sf:GetHeight()
        if max < 0 then max = 0 end
        local new = cur - (arg1 * 20)
        if new < 0 then new = 0 end
        if new > max then new = max end
        sf:SetVerticalScroll(new)
    end)

    -- Keep scroll in view when typing
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

    -- Click on scroll frame focuses the edit box
    sf:SetScript("OnMouseDown", function() eb:SetFocus() end)

    -- Return the edit box but keep reference to scroll frame
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

    -- Draggable
    local drag = CreateFrame("Frame", nil, f)
    drag:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -12)
    drag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -32, -12)
    drag:SetHeight(20)
    drag:EnableMouse(true)
    drag:SetScript("OnMouseDown", function() f:StartMoving() end)
    drag:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING + 4, -PADDING - 2)
    title:SetText("|cff7289DADiscord|cffffffffPresence")

    -- Close
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

    local yOff = -40

    -- =====================================================================
    -- Presets
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

    local curLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    curLabel:SetPoint("TOPLEFT", f, "TOPLEFT", btnX + 10, yOff)
    curLabel:SetTextColor(0.4, 0.8, 0.4)
    f.presetLabel = curLabel

    yOff = yOff - 30

    -- =====================================================================
    -- Editors
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
