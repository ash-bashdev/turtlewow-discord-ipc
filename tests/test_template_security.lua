--[[
    Security tests for Template.lua
    Run: lua tests/test_template_security.lua

    Tests for vulnerabilities relevant to our engine, informed by
    Handlebars.js CVEs adapted to our Lua implementation.
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

-- pipe argument injection (our CVE fix)
-- }} inside a quoted pipe argument must not close the tag early
test("pipe arg with }} inside quotes",
    '{{a | default "}} {{evil}}"}}',
    { a = "", evil = "HACKED" },
    "}} {{evil}}")

-- value injection: template syntax in variable values must not be re-parsed
test("template syntax in values",
    "{{a}}",
    { a = "{{#if x}}injected{{/if}}" },
    "{{#if x}}injected{{/if}}")

-- DoS: nesting depth limit (CVE-2019-20922)
-- 16 deep should work, 20 should error
local deep_ok = ""
for i = 1, 16 do deep_ok = "{{#if a}}" .. deep_ok .. "{{/if}}" end
test("16-deep nesting ok", deep_ok, { a = "1" }, "")

local deep_bad = ""
for i = 1, 20 do deep_bad = "{{#if a}}" .. deep_bad .. "{{/if}}" end
local nodes, err = Compile(deep_bad)
tests_run = tests_run + 1
if err and string.find(err, "nesting too deep", 1, true) then
    tests_passed = tests_passed + 1
else
    tests_failed = tests_failed + 1
    print("FAIL: 20-deep nesting should error")
end

-- DoS: template length limit
local long = string.rep("a", 5000)
nodes, err = Compile(long)
tests_run = tests_run + 1
if err and string.find(err, "too long", 1, true) then
    tests_passed = tests_passed + 1
else
    tests_failed = tests_failed + 1
    print("FAIL: 5000-char template should error")
end

-- DoS: malformed input terminates (CVE-2026-33939)
test("garbage input doesn't hang",
    "{{{{{{###}}}}}} {{/if}} {{/if}} {{#if}}{{#if",
    {},
    "}}}}")

-- Results
print(string.format("\n%d/%d passed, %d failed",
    tests_passed, tests_run, tests_failed))
os.exit(tests_failed > 0 and 1 or 0)
