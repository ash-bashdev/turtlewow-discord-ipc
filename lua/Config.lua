--[[
    Config.lua - Configuration GUI and profile management for Discord Presence

    On first run, built-in presets (minimal/default/detailed) are seeded into
    the user's profile list. After that they're regular editable profiles.
    The three built-in names can't be deleted, but can be edited and reset.
]]

DiscordPresence_Config = {}

local FRAME_WIDTH = 540
local FRAME_HEIGHT = 620
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

-- names that can't be deleted (but can be edited and reset)
local PROTECTED_NAMES = { minimal = true, default = true, detailed = true }

local function CopyTemplates(src)
    local copy = {}
    for k, v in pairs(src or {}) do
        copy[k] = v
    end
    return copy
end

-- Init: seed built-in presets into profiles if they don't exist
function DiscordPresence_Config.InitDefaults()
    if not DiscordPresence_DB then DiscordPresence_DB = {} end
    if not DiscordPresence_DB.profiles then DiscordPresence_DB.profiles = {} end
    if not DiscordPresence_DB.active then DiscordPresence_DB.active = "default" end

    -- seed built-ins into profiles on first run
    local presets = DiscordPresence_Presets.list
    for i = 1, table.getn(presets) do
        local p = presets[i]
        if not DiscordPresence_DB.profiles[p.name] then
            DiscordPresence_DB.profiles[p.name] = CopyTemplates(p.templates)
        end
    end

    -- load active profile into templates
    local active = DiscordPresence_DB.active
    if DiscordPresence_DB.profiles[active] then
        DiscordPresence_DB.templates = CopyTemplates(DiscordPresence_DB.profiles[active])
    else
        DiscordPresence_DB.active = "default"
        DiscordPresence_DB.templates = CopyTemplates(DiscordPresence_DB.profiles["default"])
    end
end

function DiscordPresence_Config.GetTemplates()
    return DiscordPresence_DB.templates
end

-- Load a profile (by name)
function DiscordPresence_Config.LoadProfile(name)
    if not DiscordPresence_DB.profiles then return false end
    if not DiscordPresence_DB.profiles[name] then return false end
    DiscordPresence_DB.active = name
    DiscordPresence_DB.templates = CopyTemplates(DiscordPresence_DB.profiles[name])
    DiscordPresence_Config.RefreshEditors()
    if DiscordPresence_CompileTemplates then
        DiscordPresence_CompileTemplates()
    end
    return true
end

-- Save current templates to the active profile
function DiscordPresence_Config.SaveActive()
    local active = DiscordPresence_DB.active or ""
    if active == "" then return false end
    if not DiscordPresence_DB.profiles then DiscordPresence_DB.profiles = {} end
    DiscordPresence_DB.profiles[active] = CopyTemplates(DiscordPresence_DB.templates)
    return true
end

-- Save current templates as a new named profile
function DiscordPresence_Config.SaveProfileAs(name)
    if not name or name == "" then return false end
    if not DiscordPresence_DB.profiles then DiscordPresence_DB.profiles = {} end
    DiscordPresence_DB.profiles[name] = CopyTemplates(DiscordPresence_DB.templates)
    DiscordPresence_DB.active = name
    DiscordPresence_Config.RefreshLabel()
    return true
end

-- Clone current templates to a new profile
function DiscordPresence_Config.CloneProfile(name)
    if not name or name == "" then return false end
    return DiscordPresence_Config.SaveProfileAs(name)
end

-- Rename a profile (can't rename protected names)
function DiscordPresence_Config.RenameProfile(old_name, new_name)
    if not old_name or not new_name or old_name == "" or new_name == "" then return false end
    if PROTECTED_NAMES[old_name] or PROTECTED_NAMES[new_name] then return false end
    if not DiscordPresence_DB.profiles then return false end
    if not DiscordPresence_DB.profiles[old_name] then return false end
    if DiscordPresence_DB.profiles[new_name] then return false end
    DiscordPresence_DB.profiles[new_name] = DiscordPresence_DB.profiles[old_name]
    DiscordPresence_DB.profiles[old_name] = nil
    if DiscordPresence_DB.active == old_name then
        DiscordPresence_DB.active = new_name
    end
    DiscordPresence_Config.RefreshLabel()
    return true
end

-- Delete a profile (can't delete protected names)
function DiscordPresence_Config.DeleteProfile(name)
    if PROTECTED_NAMES[name] then return false end
    if not DiscordPresence_DB.profiles then return false end
    if not DiscordPresence_DB.profiles[name] then return false end
    DiscordPresence_DB.profiles[name] = nil
    if DiscordPresence_DB.active == name then
        DiscordPresence_Config.LoadProfile("default")
    end
    return true
end

-- Reset a protected profile back to its built-in preset
function DiscordPresence_Config.ResetProfile(name)
    local preset = DiscordPresence_Presets.Get(name)
    if not preset then return false end
    if not DiscordPresence_DB.profiles then DiscordPresence_DB.profiles = {} end
    DiscordPresence_DB.profiles[name] = CopyTemplates(preset.templates)
    if DiscordPresence_DB.active == name then
        DiscordPresence_DB.templates = CopyTemplates(preset.templates)
        DiscordPresence_Config.RefreshEditors()
        if DiscordPresence_CompileTemplates then
            DiscordPresence_CompileTemplates()
        end
    end
    return true
end

-- For backwards compat with /dp preset <name>
function DiscordPresence_Config.ApplyPreset(name)
    return DiscordPresence_Config.LoadProfile(name)
end

-- Get all profile names
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

-- Save editors back to active profile
local function SaveEditors()
    if not DiscordPresence_DB then return end
    if not DiscordPresence_DB.templates then DiscordPresence_DB.templates = {} end
    for i = 1, table.getn(TEMPLATE_FIELDS) do
        local key = TEMPLATE_FIELDS[i].key
        if editors[key] then
            DiscordPresence_DB.templates[key] = editors[key]:GetText()
        end
    end
    DiscordPresence_Config.SaveActive()
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

function DiscordPresence_Config.UpdatePreview()
    if not configFrame or not configFrame.preview then return end
    -- try to compile from current editor text and render a preview
    local vars = nil
    vars = DiscordPresence_Vars.Build()
    if not vars then
        if configFrame and configFrame.preview then
            configFrame.preview:SetText("|cff888888Not logged in - no preview available|r")
        end
        return
    end

    local fields = { "details", "state", "large_image", "large_text", "small_image", "small_text" }
    local lines = {}
    local has_error = false
    for i = 1, table.getn(fields) do
        local key = fields[i]
        local text = ""
        if editors[key] then
            text = editors[key]:GetText() or ""
        end
        local nodes, err = DiscordPresence_Template.Compile(text)
        if err then
            table.insert(lines, "|cffff4444" .. key .. ": " .. err .. "|r")
            has_error = true
        else
            local rendered = DiscordPresence_Template.Render(nodes, vars)
            table.insert(lines, "|cffaaaaaa" .. key .. ":|r " .. rendered)
        end
    end
    configFrame.preview:SetText(table.concat(lines, "\n"))
end

function DiscordPresence_Config.RefreshLabel()
    if configFrame and configFrame.activeLabel then
        local active = DiscordPresence_DB.active or "none"
        local label = "Active: " .. active
        if PROTECTED_NAMES[active] then
            label = label .. " (built-in, can reset)"
        end
        configFrame.activeLabel:SetText(label)
    end
end

-- GUI helpers

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
    eb:SetScript("OnTextChanged", function() DiscordPresence_Config.UpdatePreview() end)
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
    eb:SetScript("OnTextChanged", function() DiscordPresence_Config.UpdatePreview() end)
    sf:SetScript("OnMouseDown", function() eb:SetFocus() end)

    eb.scrollFrame = sf
    return eb, sf
end

-- Build frame

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

    -- Profile dropdown + buttons

    local profileLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    profileLabel:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING, yOff)
    profileLabel:SetText("Profile:")
    profileLabel:SetTextColor(0.8, 0.8, 0.8)

    local dropdown = CreateFrame("Frame", "DP_ProfileDropdown", f, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING + 40, yOff + 6)
    UIDropDownMenu_SetWidth(130, dropdown)

    local function DropdownInit()
        local names = DiscordPresence_Config.GetProfileNames()
        for i = 1, table.getn(names) do
            local info = {}
            info.text = names[i]
            info.func = function()
                UIDropDownMenu_SetSelectedName(dropdown, this.value)
                DiscordPresence_Config.LoadProfile(this.value)
                DiscordPresence_Config.UpdatePreview()
            end
            info.value = names[i]
            if names[i] == DiscordPresence_DB.active then
                info.checked = true
            end
            UIDropDownMenu_AddButton(info)
        end
    end
    UIDropDownMenu_Initialize(dropdown, DropdownInit)
    UIDropDownMenu_SetSelectedName(dropdown, DiscordPresence_DB.active or "default")
    f.dropdown = dropdown

    local function MakeSmallBtn(text, x, w, onClick)
        local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", x, yOff + 2)
        btn:SetWidth(w)
        btn:SetHeight(20)
        btn:SetText(text)
        btn:SetScript("OnClick", onClick)
        return btn
    end

    local bx = PADDING + 210
    MakeSmallBtn("Clone", bx, 50, function()
        -- prompt for name via simple dialog
        StaticPopupDialogs["DP_CLONE"] = {
            text = "Clone profile as:",
            hasEditBox = true,
            button1 = "OK",
            button2 = "Cancel",
            OnAccept = function()
                local name = getglobal(this:GetParent():GetName().."EditBox"):GetText()
                if name and name ~= "" then
                    DiscordPresence_Config.CloneProfile(name)
                    UIDropDownMenu_Initialize(dropdown, DropdownInit)
                    UIDropDownMenu_SetSelectedName(dropdown, name)
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("DP_CLONE")
    end)
    bx = bx + 54

    MakeSmallBtn("Reset", bx, 50, function()
        local active = DiscordPresence_DB.active or ""
        if PROTECTED_NAMES[active] then
            DiscordPresence_Config.ResetProfile(active)
            DiscordPresence_Config.UpdatePreview()
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[DP]|r Only built-in profiles can be reset")
        end
    end)
    bx = bx + 54

    MakeSmallBtn("Delete", bx, 50, function()
        local active = DiscordPresence_DB.active or ""
        if DiscordPresence_Config.DeleteProfile(active) then
            UIDropDownMenu_Initialize(dropdown, DropdownInit)
            UIDropDownMenu_SetSelectedName(dropdown, DiscordPresence_DB.active or "default")
            DiscordPresence_Config.UpdatePreview()
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[DP]|r Can't delete (built-in)")
        end
    end)

    yOff = yOff - 30

    -- Active label
    local activeLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    activeLabel:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING, yOff)
    activeLabel:SetTextColor(0.4, 0.8, 0.4)
    f.activeLabel = activeLabel

    yOff = yOff - 16

    -- Template editors

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

    yOff = yOff - 6

    -- Live preview

    local previewLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    previewLabel:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING, yOff)
    previewLabel:SetText("Preview:")
    previewLabel:SetTextColor(0.8, 0.8, 0.8)
    yOff = yOff - 14

    local preview = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    preview:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING, yOff)
    preview:SetWidth(FRAME_WIDTH - PADDING * 2)
    preview:SetJustifyH("LEFT")
    preview:SetTextColor(0.7, 0.9, 0.7)
    f.preview = preview

    yOff = yOff - 50

    -- Help text

    local help = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    help:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING, yOff)
    help:SetWidth(FRAME_WIDTH - PADDING * 2)
    help:SetJustifyH("LEFT")
    help:SetTextColor(0.6, 0.6, 0.6)
    help:SetText(
        "|cff7289DAVariables:|r  player_name  player_level  player_class  player_race  zone  subzone\n" ..
        "|cff7289DABooleans:|r  is_dead  in_party  in_raid  party_size  raid_size  is_max_level\n" ..
        "|cff7289DAXP:|r  xp  xp_max  xp_remaining\n" ..
        "|cff7289DAFunctions:|r  lower  upper  title  default \"str\"\n" ..
        "|cff7289DASyntax:|r  {{var}}  {{var | func}}  {{#if var}}...{{#else}}...{{/if}}\n" ..
        "|cff7289DAWhitespace:|r  {{~expr}} strip before  {{expr~}} strip after  {{~expr~}} both"
    )

    table.insert(UISpecialFrames, "DiscordPresenceConfigFrame")
    configFrame = f
    return f
end

-- Toggle

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
