--[[
    Test suite for Template.lua
    Run: lua tests/test_template.lua
]]

if not table.getn then
    table.getn = function(t) return #t end
end

dofile("lua/Template.lua")

local Compile = DiscordPresence_Template.Compile
local Render = DiscordPresence_Template.Render

local tests_run = 0
local tests_passed = 0
local tests_failed = 0

local function test(name, template, vars, expected)
    tests_run = tests_run + 1
    local nodes, err = Compile(template)
    local result = Render(nodes or template, vars)
    if result == expected then
        tests_passed = tests_passed + 1
    else
        tests_failed = tests_failed + 1
        print("FAIL: " .. name)
        print("  expected: " .. tostring(expected))
        print("  got:      " .. tostring(result))
        if err then print("  compile:  " .. err) end
    end
end

local function test_compile_err(name, template)
    tests_run = tests_run + 1
    local _, err = Compile(template)
    if err then
        tests_passed = tests_passed + 1
    else
        tests_failed = tests_failed + 1
        print("FAIL: " .. name .. " (expected compile error, got none)")
    end
end

-- variables: simple, multiple, missing, nil, plain text
test("variables",
    "{{a}} - {{b}} - {{missing}} - hello",
    { a = "X", b = "Y" },
    "X - Y -  - hello")
test("nil template", nil, nil, "")

-- pipe functions: all six + chaining + single quotes
test("pipe functions",
    '{{a | lower}} {{b | upper}} {{c | title}} {{d | default "fb"}}',
    { a = "War", b = "hi", c = "elwynn forest", d = "" },
    "war HI Elwynn Forest fb")

-- conditionals: if/elif/else, nested, pipes inside
test("conditionals",
    "{{#if a}}A{{#elif b}}{{b | upper}}{{#else}}C{{/if}}-{{#if d}}D{{#else}}{{#if e}}E{{/if}}{{/if}}",
    { a = "", b = "hi", d = "", e = "1" },
    "HI-E")

-- truthiness: non-empty=true, empty=false, "0"=false, nil=false
test("truthiness",
    "{{#if a}}1{{/if}}{{#if b}}2{{/if}}{{#if c}}3{{/if}}{{#if d}}4{{/if}}",
    { a = "yes", b = "", c = "0" },
    "1")

-- whitespace: preserved by default, edges trimmed, newlines kept
test("whitespace preservation",
    "  {{a}}  {{b}}  \n{{c}}  ",
    { a = "X", b = "Y", c = "Z" },
    "X  Y  \nZ")

-- ~ whitespace control: left, right, both, newlines, on all tag types
test("~ strip on variables",
    "hello  {{~a~}}  world\nline1\n{{~b}}\n{{c~}}\nline2",
    { a = "X", b = "Y", c = "Z" },
    "helloXworld\nline1Y\nZline2")

test("~ strip on control tags",
    "A{{~#if x~}} X {{~#else~}} Y {{~/if~}}B {{~! gone ~}} C{{~#if z~}} {{z}}{{~/if~}}D",
    { x = "", z = "!" },
    "AYBC!D")

-- escaping: values with template syntax, pipes, quotes, braces
test("escaping",
    "{{a}} {{b}} {{c}} {{d}} test { and }",
    { a = "{{evil}}", b = "a|b", c = 'say "hi"', d = "{{#if x}}inject{{/if}}" },
    '{{evil}} a|b say "hi" {{#if x}}inject{{/if}} test { and }')

-- # prefix disambiguation: vars named "if" and "else"
test("keyword vars",
    "{{if}}-{{else}}", { ["if"] = "a", ["else"] = "b" }, "a-b")

-- comments
test("comments",
    "before{{! ignored }}middle{{! also gone }}after", {}, "beforemiddleafter")

-- compile errors
test_compile_err("unclosed if", "{{#if x}}text")
test_compile_err("unknown function", "{{x | nonexistent}}")

-- realistic preset patterns
test("preset details",
    "{{n}} - Level {{l~}}\n{{~#if d}} (Dead){{/if}}",
    { n = "Test", l = "42", d = "1" },
    "Test - Level 42 (Dead)")

test("preset state",
    "{{z~}}\n{{~#if s~}}, {{s~}}{{~/if~}}\n{{~#if r}} | Raid ({{rs}}){{~/if~}}\n{{~#if p}} | Party ({{ps}}){{~/if}}",
    { z = "Elwynn", s = "Gold", r = "", p = "1", ps = "5" },
    "Elwynn, Gold | Party (5)")

-- Results
print(string.format("\n%d/%d passed, %d failed",
    tests_passed, tests_run, tests_failed))
os.exit(tests_failed > 0 and 1 or 0)
