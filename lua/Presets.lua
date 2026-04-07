-- Presets.lua - Template presets for Discord Presence
--
-- Templates are stored as multiline strings using [[ ]] literals.
-- What you see here is exactly what appears in the editor.
-- Use ~ for whitespace control so multiline reads well but renders clean.

DiscordPresence_Presets = {}

DiscordPresence_Presets.list = {
    {
        name = "minimal",
        templates = {
            details = "{{player_name}}",
            state   = "{{zone}}",
            large_image = "turtle-weblogo",
            large_text  = "Turtle WoW",
            small_image = "",
            small_text  = "",
        },
    },
    {
        name = "default",
        templates = {
            details = [[
{{~player_name}} - Level {{player_level~}}
{{~#if is_dead~}}
 (Dead)
{{~/if~}}
]],
            state = [[
{{~zone~}}
{{~#if subzone~}}, {{subzone~}}{{~/if~}}
]],
            large_image = "turtle-weblogo",
            large_text  = "Turtle WoW - {{realm}}",
            small_image = "class_icons-{{player_class | lower}}",
            small_text  = "{{player_race}} {{player_class}}",
        },
    },
    {
        name = "detailed",
        templates = {
            details = [[
{{~player_name}} - {{player_race}} {{player_class~}}
{{~#if is_dead}} (Dead){{/if~}}
]],
            state = [[
{{~zone~}}
{{~#if subzone~}}, {{subzone~}}{{~/if~}}
{{~#if in_raid}} ({{raid_size}}/40)
{{~#elif in_party~}}
{{~#if party2_name}} ({{party_size}}/5)
{{~#else}} with {{party1_name~}}
{{~/if~}}
{{~#else}} Solo
{{~/if~}}
]],
            large_image = "turtle-weblogo",
            large_text  = "Turtle WoW - {{realm}}",
            small_image = "class_icons-{{player_class | lower}}",
            small_text  = [[
{{~#if is_max_level~}}
{{~player_race}} {{player_class}} ({{player_level}})
{{~#else~}}
{{~xp}}/{{xp_max}} XP ({{player_level}})
{{~/if~}}
]],
        },
    },
}

function DiscordPresence_Presets.Get(name)
    for i = 1, table.getn(DiscordPresence_Presets.list) do
        if DiscordPresence_Presets.list[i].name == name then
            return DiscordPresence_Presets.list[i]
        end
    end
    return nil
end


