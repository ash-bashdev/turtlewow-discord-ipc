--[[
    Template.lua - Go/Handlebars-style template engine

    Syntax:
      {{variable}}                                          - variable
      {{variable | func}}                                   - pipe
      {{variable | func1 | func2 "arg"}}                    - chain
      {{#if var}}...{{#elif var}}...{{#else}}...{{/if}}     - conditionals
      {{! comment }}                                        - comment (stripped)
      {{~ and ~}}                                           - whitespace control

    Whitespace control (tilde):
      {{~expr}}    - strip whitespace/newlines BEFORE this tag
      {{expr~}}    - strip whitespace/newlines AFTER this tag
      {{~expr~}}   - strip both sides
      Works on all tags: variables, #if, #else, #elif, /if, comments

    Pipe functions:
      lower  upper  title  default "str"
]]

DiscordPresence_Template = {}

local OPEN = "{{"
local CLOSE = "}}"
local OPEN_LEN = 2
local CLOSE_LEN = 2

-- Safety limits
local MAX_TEMPLATE_LEN = 4096   -- max input template string length
local MAX_NESTING_DEPTH = 16    -- max nested {{#if}} depth

local function IsTruthy(val)
    if not val then return false end
    if val == "" then return false end
    if val == "0" then return false end
    return true
end

local function Trim(s)
    if not s then return "" end
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    return s
end

local function StripTrailingWS(s)
    return string.gsub(s, "%s+$", "")
end

local function StripLeadingWS(s)
    return string.gsub(s, "^%s+", "")
end

-- =========================================================================
-- Pipe functions
-- =========================================================================

local FUNCTIONS = {}
FUNCTIONS["lower"] = function(val) return string.lower(val) end
FUNCTIONS["upper"] = function(val) return string.upper(val) end
FUNCTIONS["title"] = function(val)
    return string.gsub(string.lower(val), "(%a)([%w_']*)", function(first, rest)
        return string.upper(first) .. rest
    end)
end

FUNCTIONS["default"] = function(val, arg)
    if val == "" then return arg or "" end
    return val
end

-- =========================================================================
-- Parse pipe expression
-- =========================================================================

local function ParsePipe(expr)
    local parts = {}
    local current = ""
    local in_quotes = false
    local quote_char = nil
    for i = 1, string.len(expr) do
        local c = string.sub(expr, i, i)
        if (c == '"' or c == "'") and not in_quotes then
            in_quotes = true
            quote_char = c
            current = current .. c
        elseif c == quote_char and in_quotes then
            in_quotes = false
            quote_char = nil
            current = current .. c
        elseif c == "|" and not in_quotes then
            table.insert(parts, current)
            current = ""
        else
            current = current .. c
        end
    end
    if current ~= "" then table.insert(parts, current) end
    if table.getn(parts) == 0 then return nil, "empty expression" end

    local var_name = Trim(parts[1])
    local steps = {}
    for i = 2, table.getn(parts) do
        local segment = Trim(parts[i])
        local fname, arg = nil, nil
        local _, _, f1, a1 = string.find(segment, '^([%w_]+)%s+"([^"]*)"')
        if f1 then
            fname, arg = f1, a1
        else
            local _, _, f2, a2 = string.find(segment, "^([%w_]+)%s+'([^']*)'")
            if f2 then
                fname, arg = f2, a2
            else
                local _, _, f3 = string.find(segment, "^([%w_]+)$")
                if f3 then fname = f3 end
            end
        end
        if not fname then
            -- skip
        elseif not FUNCTIONS[fname] then
            return nil, "unknown function: " .. fname
        else
            table.insert(steps, { fname, arg })
        end
    end
    return { var = var_name, steps = steps }, nil
end

-- =========================================================================
-- Find closing }} and check for ~ before it
-- Quote-aware: skips }} inside "..." or '...' strings
-- Returns: close_pos, strip_right
-- =========================================================================

local function FindClose(template, from)
    local len = string.len(template)
    local i = from
    local in_quotes = false
    local quote_char = nil

    while i <= len - 1 do
        local c = string.sub(template, i, i)

        if (c == '"' or c == "'") and not in_quotes then
            in_quotes = true
            quote_char = c
        elseif c == quote_char and in_quotes then
            in_quotes = false
            quote_char = nil
        elseif not in_quotes and string.sub(template, i, i + 1) == CLOSE then
            local strip_right = false
            if i > 1 and string.sub(template, i - 1, i - 1) == "~" then
                strip_right = true
            end
            return i, strip_right
        end

        i = i + 1
    end

    return nil, false
end

-- Extract the inner content between {{ and }}, stripping ~ from both ends
-- Returns: content, strip_left, strip_right, end_pos
local function ExtractTag(template, tag_start)
    local inner_start = tag_start + OPEN_LEN
    local close_pos, strip_right = FindClose(template, inner_start)
    if not close_pos then return nil, false, false, nil end

    local content_end = close_pos - 1
    if strip_right then content_end = content_end - 1 end

    local strip_left = false
    local content_start = inner_start
    if string.sub(template, content_start, content_start) == "~" then
        strip_left = true
        content_start = content_start + 1
    end

    local content = string.sub(template, content_start, content_end)
    return content, strip_left, strip_right, close_pos + CLOSE_LEN
end

-- Apply strip_left to the last text node in a list
local function ApplyStripLeft(nodes)
    local n = table.getn(nodes)
    if n > 0 and nodes[n].type == "text" then
        nodes[n].value = StripTrailingWS(nodes[n].value)
    end
end

-- =========================================================================
-- Compile
-- =========================================================================

local CompileIf

function DiscordPresence_Template.Compile(template)
    if not template then return {}, nil end
    if string.len(template) > MAX_TEMPLATE_LEN then
        return {}, "template too long (" .. string.len(template) .. " chars, max " .. MAX_TEMPLATE_LEN .. ")"
    end
    local nodes = {}
    local errors = {}
    local pos = 1
    local len = string.len(template)
    local pending_strip_right = false

    while pos <= len do
        local tag_start = string.find(template, OPEN, pos, true)
        if not tag_start then
            local text = string.sub(template, pos)
            if pending_strip_right then
                text = StripLeadingWS(text)
                pending_strip_right = false
            end
            if text ~= "" then table.insert(nodes, { type = "text", value = text }) end
            break
        end

        -- Text before tag
        local text = string.sub(template, pos, tag_start - 1)
        if pending_strip_right then
            text = StripLeadingWS(text)
            pending_strip_right = false
        end
        if text ~= "" then table.insert(nodes, { type = "text", value = text }) end

        local content, strip_left, strip_right, end_pos = ExtractTag(template, tag_start)
        if not content then
            table.insert(nodes, { type = "text", value = string.sub(template, tag_start) })
            pos = len + 1
            break
        end

        if strip_left then ApplyStripLeft(nodes) end
        pending_strip_right = strip_right

        content = Trim(content)
        local first_char = string.sub(content, 1, 1)

        if first_char == "!" then
            -- Comment: skip entirely
            pos = end_pos

        elseif first_char == "#" then
            local keyword = string.sub(content, 2)
            local _, _, kw = string.find(keyword, "^(%w+)")
            if kw == "if" then
                local if_node, new_pos, err = CompileIf(template, tag_start, 1)
                if err then
                    table.insert(errors, err)
                    table.insert(nodes, { type = "text", value = "" })
                    pos = len + 1
                else
                    table.insert(nodes, if_node)
                    pos = new_pos
                end
            else
                -- Unknown # tag
                pos = end_pos
            end

        elseif first_char == "/" then
            -- Stray close tag, skip
            pos = end_pos

        else
            -- Variable/pipe
            local pipe, err = ParsePipe(content)
            if err then
                table.insert(errors, err .. " in: {{" .. content .. "}}")
                table.insert(nodes, { type = "text", value = "" })
            else
                table.insert(nodes, { type = "pipe", var = pipe.var, steps = pipe.steps })
            end
            pos = end_pos
        end
    end

    local err_str = nil
    if table.getn(errors) > 0 then err_str = table.concat(errors, "; ") end
    return nodes, err_str
end

-- =========================================================================
-- Compile {{#if}}...{{/if}}
-- =========================================================================

CompileIf = function(template, tag_start, depth)
    if depth > MAX_NESTING_DEPTH then
        return nil, nil, "nesting too deep (max " .. MAX_NESTING_DEPTH .. ")"
    end
    local len = string.len(template)

    -- Parse the opening {{#if var}} tag
    local content, strip_left, strip_right, end_pos = ExtractTag(template, tag_start)
    if not content then return nil, nil, "unclosed {{#if}} tag" end

    content = Trim(content)
    -- content is "#if varname"
    local first_var = Trim(string.sub(content, 5))
    local branches = {}
    local current_nodes = {}
    local current_var = first_var
    local pos = end_pos
    local pending_strip = strip_right

    while pos <= len do
        local next_tag = string.find(template, OPEN, pos, true)
        if not next_tag then return nil, nil, "unclosed {{#if " .. first_var .. "}}" end

        -- Text between tags
        local text = string.sub(template, pos, next_tag - 1)
        if pending_strip then
            text = StripLeadingWS(text)
            pending_strip = false
        end
        if text ~= "" then table.insert(current_nodes, { type = "text", value = text }) end

        local tag_content, sl, sr, tag_end = ExtractTag(template, next_tag)
        if not tag_content then return nil, nil, "unclosed tag inside {{#if}}" end

        if sl then ApplyStripLeft(current_nodes) end
        pending_strip = sr

        tag_content = Trim(tag_content)
        local fc = string.sub(tag_content, 1, 1)

        if fc == "/" then
            local keyword = Trim(string.sub(tag_content, 2))
            if keyword == "if" then
                table.insert(branches, { var = current_var, nodes = current_nodes })
                return { type = "if", branches = branches }, tag_end, nil
            else
                table.insert(current_nodes, { type = "text", value = "" })
                pos = tag_end
            end

        elseif fc == "#" then
            local kw_content = string.sub(tag_content, 2)
            local _, _, kw = string.find(kw_content, "^(%w+)")

            if kw == "elif" then
                table.insert(branches, { var = current_var, nodes = current_nodes })
                current_var = Trim(string.sub(kw_content, 6))
                current_nodes = {}
                pos = tag_end

            elseif kw == "else" then
                table.insert(branches, { var = current_var, nodes = current_nodes })
                current_var = nil
                current_nodes = {}
                pos = tag_end

            elseif kw == "if" then
                -- Nested if
                local nested, new_pos, err = CompileIf(template, next_tag, depth + 1)
                if err then return nil, nil, err end
                table.insert(current_nodes, nested)
                pos = new_pos

            else
                pos = tag_end
            end

        elseif fc == "!" then
            -- Comment inside block
            pos = tag_end

        else
            -- Variable/pipe inside block
            local pipe, err = ParsePipe(tag_content)
            if pipe then
                table.insert(current_nodes, { type = "pipe", var = pipe.var, steps = pipe.steps })
            else
                table.insert(current_nodes, { type = "text", value = "" })
            end
            pos = tag_end
        end
    end
    return nil, nil, "unclosed {{#if " .. first_var .. "}}"
end

-- =========================================================================
-- Evaluate
-- =========================================================================

local function EvalPipe(node, vars)
    local val = vars[node.var] or ""
    for i = 1, table.getn(node.steps) do
        local step = node.steps[i]
        local fn = FUNCTIONS[step[1]]
        if fn then val = fn(val, step[2]) end
    end
    return val
end

local function EvalNodes(nodes, vars)
    local parts = {}
    for i = 1, table.getn(nodes) do
        local node = nodes[i]
        if node.type == "text" then
            table.insert(parts, node.value)
        elseif node.type == "pipe" then
            table.insert(parts, EvalPipe(node, vars))
        elseif node.type == "if" then
            for j = 1, table.getn(node.branches) do
                local branch = node.branches[j]
                if branch.var == nil or IsTruthy(vars[branch.var]) then
                    table.insert(parts, EvalNodes(branch.nodes, vars))
                    break
                end
            end
        end
    end
    return table.concat(parts, "")
end

-- =========================================================================
-- Render
-- =========================================================================

function DiscordPresence_Template.Render(compiled, vars)
    if not compiled then return "" end
    if not vars then vars = {} end
    local nodes
    if type(compiled) == "string" then
        nodes = DiscordPresence_Template.Compile(compiled)
    else
        nodes = compiled
    end
    if not nodes or table.getn(nodes) == 0 then return "" end
    local result = EvalNodes(nodes, vars)
    result = string.gsub(result, "^%s+", "")
    result = string.gsub(result, "%s+$", "")
    return result
end
