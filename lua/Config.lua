DiscordPresence_Config = {}

local FRAME_WIDTH = 540
local FRAME_HEIGHT = 580
local FIELD_HEIGHT = 24
local MULTI_HEIGHT = 60
local LABEL_WIDTH = 80
local PADDING = 12

local configFrame = nil
local editors = {}
local isDirty = false

local TEMPLATE_FIELDS = {
    { key = "details",     label = "Details",     multi = true },
    { key = "state",       label = "State",       multi = true },
    { key = "large_image", label = "Large Icon",  multi = false },
    { key = "large_text",  label = "Large Text",  multi = false },
    { key = "small_image", label = "Small Icon",  multi = false },
    { key = "small_text",  label = "Small Text",  multi = false },
}

local PROTECTED_NAMES = { minimal = true, default = true, detailed = true }

local function CopyTemplates(src)
    local copy = {}
    for k, v in pairs(src or {}) do
        copy[k] = v
    end
    return copy
end

function DiscordPresence_Config.InitDefaults()
    if not DiscordPresence_DB then DiscordPresence_DB = {} end
    if not DiscordPresence_DB.profiles then DiscordPresence_DB.profiles = {} end
    if not DiscordPresence_DB.active then DiscordPresence_DB.active = "default" end
    if DiscordPresence_DB.show_party == nil then DiscordPresence_DB.show_party = true end

    local presets = DiscordPresence_Presets.list
    for i = 1, table.getn(presets) do
        local p = presets[i]
        if not DiscordPresence_DB.profiles[p.name] then
            DiscordPresence_DB.profiles[p.name] = CopyTemplates(p.templates)
        end
    end

    local active = DiscordPresence_DB.active
    if DiscordPresence_DB.profiles[active] then
        DiscordPresence_DB.templates = CopyTemplates(DiscordPresence_DB.profiles[active])
    else
        DiscordPresence_DB.active = "default"
        DiscordPresence_DB.templates = CopyTemplates(DiscordPresence_DB.profiles["default"])
    end
end

function DiscordPresence_Config.LoadProfile(name)
    if not DiscordPresence_DB.profiles then return false end
    if not DiscordPresence_DB.profiles[name] then return false end
    DiscordPresence_DB.active = name
    DiscordPresence_DB.templates = CopyTemplates(DiscordPresence_DB.profiles[name])
    isDirty = false
    DiscordPresence_Config.RefreshEditors()
    if DiscordPresence_CompileTemplates then DiscordPresence_CompileTemplates() end
    return true
end

function DiscordPresence_Config.SaveActive()
    local active = DiscordPresence_DB.active or ""
    if active == "" then return false end
    if not DiscordPresence_DB.profiles then DiscordPresence_DB.profiles = {} end
    for i = 1, table.getn(TEMPLATE_FIELDS) do
        local key = TEMPLATE_FIELDS[i].key
        if editors[key] then
            DiscordPresence_DB.templates[key] = editors[key]:GetText()
        end
    end
    DiscordPresence_DB.profiles[active] = CopyTemplates(DiscordPresence_DB.templates)
    if DiscordPresence_CompileTemplates then DiscordPresence_CompileTemplates() end
    isDirty = false
    DiscordPresence_Config.RefreshLabel()
    return true
end

function DiscordPresence_Config.SaveProfileAs(name)
    if not name or name == "" then return false end
    if not DiscordPresence_DB.profiles then DiscordPresence_DB.profiles = {} end
    for i = 1, table.getn(TEMPLATE_FIELDS) do
        local key = TEMPLATE_FIELDS[i].key
        if editors[key] then
            DiscordPresence_DB.templates[key] = editors[key]:GetText()
        end
    end
    DiscordPresence_DB.profiles[name] = CopyTemplates(DiscordPresence_DB.templates)
    DiscordPresence_DB.active = name
    isDirty = false
    DiscordPresence_Config.RefreshLabel()
    return true
end

function DiscordPresence_Config.CloneProfile(name)
    if not name or name == "" then return false end
    return DiscordPresence_Config.SaveProfileAs(name)
end

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

function DiscordPresence_Config.ResetProfile(name)
    local preset = DiscordPresence_Presets.Get(name)
    if not preset then return false end
    if not DiscordPresence_DB.profiles then DiscordPresence_DB.profiles = {} end
    DiscordPresence_DB.profiles[name] = CopyTemplates(preset.templates)
    if DiscordPresence_DB.active == name then
        DiscordPresence_DB.templates = CopyTemplates(preset.templates)
        isDirty = false
        DiscordPresence_Config.RefreshEditors()
        if DiscordPresence_CompileTemplates then DiscordPresence_CompileTemplates() end
    end
    return true
end

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

function DiscordPresence_Config.RefreshEditors()
    if not DiscordPresence_DB or not DiscordPresence_DB.templates then return end
    for key, eb in pairs(editors) do
        eb:SetText(DiscordPresence_DB.templates[key] or "")
    end
    DiscordPresence_Config.RefreshLabel()
    DiscordPresence_Config.UpdatePreview()
end

function DiscordPresence_Config.UpdatePreview()
    if not configFrame or not configFrame.preview then return end
    local vars = DiscordPresence_Vars.Build()
    if not vars then
        configFrame.preview:SetText("|cff888888Not logged in - no preview available|r")
        return
    end

    local fields = { "details", "state", "large_image", "large_text", "small_image", "small_text" }
    local lines = {}
    for i = 1, table.getn(fields) do
        local key = fields[i]
        local text = editors[key] and editors[key]:GetText() or ""
        local nodes, err = DiscordPresence_Template.Compile(text)
        if err then
            table.insert(lines, "|cffff4444" .. key .. ": " .. err .. "|r")
        else
            local rendered = DiscordPresence_Template.Render(nodes, vars)
            table.insert(lines, "|cffaaaaaa" .. key .. ":|r " .. rendered)
        end
    end
    configFrame.preview:SetText(table.concat(lines, "\n"))
end

function DiscordPresence_Config.RefreshLabel()
    if not configFrame then return end
    if configFrame.activeLabel then
        local active = DiscordPresence_DB.active or "none"
        local label = "Active: " .. active
        if PROTECTED_NAMES[active] then label = label .. " (built-in)" end
        if isDirty then label = label .. " |cffff8800*unsaved*|r" end
        configFrame.activeLabel:SetText(label)
    end
    if configFrame.saveBtn then
        if isDirty then
            configFrame.saveBtn:Enable()
        else
            configFrame.saveBtn:Disable()
        end
    end
end

local function MarkDirty()
    isDirty = true
    DiscordPresence_Config.RefreshLabel()
    DiscordPresence_Config.UpdatePreview()
end

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
    eb:SetScript("OnTextChanged", function() MarkDirty() end)
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
        if y < offset then sf:SetVerticalScroll(y)
        elseif y + arg4 > offset + h then sf:SetVerticalScroll(y + arg4 - h) end
    end)
    eb:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    eb:SetScript("OnTextChanged", function() MarkDirty() end)
    sf:SetScript("OnMouseDown", function() eb:SetFocus() end)

    eb.scrollFrame = sf
    return eb, sf
end

local function SetTab(tabName)
    if not configFrame then return end
    if configFrame.tabTemplates then
        if tabName == "templates" then
            configFrame.tabTemplates:Show()
            configFrame.tabTemplatesBtn.bg:SetTexture(0.2, 0.3, 0.5, 0.8)
        else
            configFrame.tabTemplates:Hide()
            configFrame.tabTemplatesBtn.bg:SetTexture(0.15, 0.15, 0.15, 0.8)
        end
    end
    if configFrame.tabReference then
        if tabName == "reference" then
            configFrame.tabReference:Show()
            configFrame.tabReferenceBtn.bg:SetTexture(0.2, 0.3, 0.5, 0.8)
        else
            configFrame.tabReference:Hide()
            configFrame.tabReferenceBtn.bg:SetTexture(0.15, 0.15, 0.15, 0.8)
        end
    end
end

local function MakeTabBtn(parent, text, x, y, tabName)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    btn:SetWidth(80)
    btn:SetHeight(22)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(btn)
    btn.bg = bg
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
    fs:SetText(text)
    btn:SetScript("OnClick", function() SetTab(tabName) end)
    return btn
end

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

    -- profile dropdown + buttons
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
            end
            info.value = names[i]
            if names[i] == DiscordPresence_DB.active then info.checked = true end
            UIDropDownMenu_AddButton(info)
        end
    end
    UIDropDownMenu_Initialize(dropdown, DropdownInit)
    UIDropDownMenu_SetSelectedName(dropdown, DiscordPresence_DB.active or "default")
    f.dropdown = dropdown

    local function SmallBtn(text, x, w, onClick)
        local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", x, yOff + 2)
        btn:SetWidth(w)
        btn:SetHeight(20)
        btn:SetText(text)
        btn:SetScript("OnClick", onClick)
        return btn
    end

    local bx = PADDING + 210

    local saveBtn = SmallBtn("Save", bx, 45, function()
        DiscordPresence_Config.SaveActive()
    end)
    saveBtn:Disable()
    f.saveBtn = saveBtn
    bx = bx + 49

    SmallBtn("Clone", bx, 50, function()
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
            timeout = 0, whileDead = true, hideOnEscape = true,
        }
        StaticPopup_Show("DP_CLONE")
    end)
    bx = bx + 54

    SmallBtn("Reset", bx, 50, function()
        local active = DiscordPresence_DB.active or ""
        if PROTECTED_NAMES[active] then
            DiscordPresence_Config.ResetProfile(active)
        end
    end)
    bx = bx + 54

    SmallBtn("Delete", bx, 50, function()
        local active = DiscordPresence_DB.active or ""
        if DiscordPresence_Config.DeleteProfile(active) then
            UIDropDownMenu_Initialize(dropdown, DropdownInit)
            UIDropDownMenu_SetSelectedName(dropdown, DiscordPresence_DB.active or "default")
        end
    end)

    yOff = yOff - 28

    -- active label
    local activeLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    activeLabel:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING, yOff)
    activeLabel:SetTextColor(0.4, 0.8, 0.4)
    f.activeLabel = activeLabel

    yOff = yOff - 16

    -- show party checkbox
    local partyCheck = CreateFrame("CheckButton", "DP_ShowParty", f, "UICheckButtonTemplate")
    partyCheck:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING - 2, yOff)
    partyCheck:SetWidth(24)
    partyCheck:SetHeight(24)
    partyCheck:SetChecked(DiscordPresence_DB.show_party)
    partyCheck:SetScript("OnClick", function()
        DiscordPresence_DB.show_party = (this:GetChecked() == 1)
    end)
    local partyLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    partyLabel:SetPoint("LEFT", partyCheck, "RIGHT", 2, 0)
    partyLabel:SetText("Enable rich party presence")
    partyLabel:SetTextColor(0.9, 0.9, 0.9)

    yOff = yOff - 26

    -- tab buttons
    f.tabTemplatesBtn = MakeTabBtn(f, "Templates", PADDING, yOff, "templates")
    f.tabReferenceBtn = MakeTabBtn(f, "Reference", PADDING + 84, yOff, "reference")

    yOff = yOff - 26

    -- content area start
    local contentTop = yOff

    -- templates tab
    local templatesTab = CreateFrame("Frame", nil, f)
    templatesTab:SetPoint("TOPLEFT", f, "TOPLEFT", 0, contentTop)
    templatesTab:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    f.tabTemplates = templatesTab

    local ty = -4
    local editWidth = FRAME_WIDTH - PADDING * 2 - LABEL_WIDTH - 24

    for i = 1, table.getn(TEMPLATE_FIELDS) do
        local field = TEMPLATE_FIELDS[i]
        local label = templatesTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", templatesTab, "TOPLEFT", PADDING, ty - 4)
        label:SetWidth(LABEL_WIDTH)
        label:SetJustifyH("RIGHT")
        label:SetText(field.label)
        label:SetTextColor(0.9, 0.9, 0.9)

        if field.multi then
            local eb, sf = MakeMultiEditBox(templatesTab, "DP_Edit_" .. field.key, editWidth, MULTI_HEIGHT)
            sf:SetPoint("TOPLEFT", templatesTab, "TOPLEFT", PADDING + LABEL_WIDTH + 8, ty)
            editors[field.key] = eb
            ty = ty - (MULTI_HEIGHT + 6)
        else
            local eb = MakeEditBox(templatesTab, "DP_Edit_" .. field.key, editWidth, FIELD_HEIGHT)
            eb:SetPoint("TOPLEFT", templatesTab, "TOPLEFT", PADDING + LABEL_WIDTH + 8, ty)
            editors[field.key] = eb
            ty = ty - (FIELD_HEIGHT + 6)
        end
    end

    ty = ty - 6

    local previewLabel = templatesTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    previewLabel:SetPoint("TOPLEFT", templatesTab, "TOPLEFT", PADDING, ty)
    previewLabel:SetText("Preview:")
    previewLabel:SetTextColor(0.8, 0.8, 0.8)
    ty = ty - 14

    local preview = templatesTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    preview:SetPoint("TOPLEFT", templatesTab, "TOPLEFT", PADDING, ty)
    preview:SetWidth(FRAME_WIDTH - PADDING * 2)
    preview:SetJustifyH("LEFT")
    preview:SetTextColor(0.7, 0.9, 0.7)
    f.preview = preview

    -- reference tab
    local referenceTab = CreateFrame("Frame", nil, f)
    referenceTab:SetPoint("TOPLEFT", f, "TOPLEFT", 0, contentTop)
    referenceTab:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    f.tabReference = referenceTab

    local ref = referenceTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ref:SetPoint("TOPLEFT", referenceTab, "TOPLEFT", PADDING, -4)
    ref:SetWidth(FRAME_WIDTH - PADDING * 2)
    ref:SetJustifyH("LEFT")
    ref:SetTextColor(0.7, 0.7, 0.7)
    ref:SetText(
        "|cff7289DAPlayer:|r\n" ..
        "  {{player_name}}  {{player_level}}  {{player_class}}  {{player_race}}\n" ..
        "  {{realm}}\n\n" ..
        "|cff7289DALocation:|r\n" ..
        "  {{zone}}  {{subzone}}\n\n" ..
        "|cff7289DAGroup:|r\n" ..
        "  {{is_dead}}  {{in_party}}  {{in_raid}}  {{is_leader}}\n" ..
        "  {{party_size}}  {{raid_size}}  {{leader_name}}\n\n" ..
        "|cff7289DAParty Members:|r\n" ..
        "  {{party1_name}}  {{party1_level}}  {{party1_class}}  {{party1_race}}\n" ..
        "  {{party2_name}}  {{party2_level}}  ...up to party4\n\n" ..
        "|cff7289DAXP:|r\n" ..
        "  {{xp}}  {{xp_max}}  {{xp_remaining}}  {{is_max_level}}\n\n" ..
        "|cff7289DAFunctions:|r\n" ..
        "  {{var | lower}}  {{var | upper}}  {{var | title}}\n" ..
        "  {{var | default \"fallback\"}}\n\n" ..
        "|cff7289DAConditionals:|r\n" ..
        "  {{#if var}}shown if true{{/if}}\n" ..
        "  {{#if var}}true{{#elif var2}}alt{{#else}}false{{/if}}\n\n" ..
        "|cff7289DAWhitespace:|r\n" ..
        "  {{~expr}} strip before  {{expr~}} strip after\n" ..
        "  {{~expr~}} strip both sides\n\n" ..
        "|cff7289DAComments:|r  {{! this is ignored }}"
    )

    -- confirm save on close
    f:SetScript("OnHide", function()
        if isDirty then
            StaticPopupDialogs["DP_UNSAVED"] = {
                text = "You have unsaved template changes. Save?",
                button1 = "Save",
                button2 = "Discard",
                OnAccept = function()
                    DiscordPresence_Config.SaveActive()
                end,
                OnCancel = function()
                    isDirty = false
                    DiscordPresence_Config.LoadProfile(DiscordPresence_DB.active)
                end,
                timeout = 0, whileDead = true, hideOnEscape = true,
            }
            StaticPopup_Show("DP_UNSAVED")
        end
    end)

    table.insert(UISpecialFrames, "DiscordPresenceConfigFrame")
    configFrame = f
    return f
end

function DiscordPresence_Config.Toggle()
    if configFrame and configFrame:IsShown() then
        configFrame:Hide()
        return
    end
    if not configFrame then
        BuildFrame()
    end
    isDirty = false
    DiscordPresence_Config.RefreshEditors()
    SetTab("templates")
    configFrame:Show()
end
