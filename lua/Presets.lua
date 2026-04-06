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
            state = "{{zone}}",
            large_image = "turtle-weblogo",
            large_text = "Turtle WoW",
            small_image = "",
            small_text = "",
        },
    },
    {
        name = "default",
        templates = {
            details = [[{{player_name}} - Level {{player_level~}}
{{~#if is_dead}} (Dead){{/if}}]],
            state = [[{{zone~}}
{{~#if subzone~}}, {{subzone~}}{{~/if~}}
{{~#if in_raid}} | Raid ({{raid_size}}){{~/if~}}
{{~#if in_party}} | Party ({{party_size}}){{~/if}}]],
            large_image = "turtle-weblogo",
            large_text = "Turtle WoW",
            small_image = [[{{player_class | lower | prefix "class_icons-"}}]],
            small_text = "{{player_race}} {{player_class}}",
        },
    },
    {
        name = "detailed",
        templates = {
            details = [[{{player_name}} - {{player_race}} {{player_class~}}
 - Level {{player_level~}}
{{~#if is_dead}} (Dead){{/if}}]],
            state = [[{{zone~}}
{{~#if subzone~}}, {{subzone~}}{{~/if~}}
{{~#if in_raid~}}
 | Raid ({{raid_size}})
{{~#elif in_party~}}
 | Party ({{party_size}})
{{~#else~}}
 | Solo
{{~/if}}]],
            large_image = "turtle-weblogo",
            large_text = "Turtle WoW - Mysteries of Azeroth",
            small_image = [[{{player_class | lower | prefix "class_icons-"}}]],
            small_text = "Level {{player_level}} {{player_race}} {{player_class}}",
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

function DiscordPresence_Presets.GetDefault()
    return DiscordPresence_Presets.Get("default")
end

function DiscordPresence_Presets.GetNames()
    local names = {}
    for i = 1, table.getn(DiscordPresence_Presets.list) do
        table.insert(names, DiscordPresence_Presets.list[i].name)
    end
    return names
end
