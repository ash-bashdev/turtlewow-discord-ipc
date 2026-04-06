# turtlewow-discord-ipc

this is a plugin+addon i made for turtlewow to stream discord presence updates from the game.

the plugin is a dll that registers lua functions that can be used to send rich presence updates.

the addon uses said lua functions, grabs data from the game, and sends it.

## install

installation requires some sort of dll loader (vanillafixes, turtlewow launcher, superwow, etc)

1. add the addon via the git however you do it: `https://github.com/ash-bashdev/turtlewow-discord-ipc`

2. add the plugin, either download [`discord_rpc.dll`](https://github.com/ash-bashdev/turtlewow-discord-ipc/raw/master/dist/discord_rpc.dll)/grab it from the addon (i build it and put it in `dist/discord_rpc.dll`) and copy it to your turtle wow game folder (next to `WoW.exe`)

3. if your launcher doesn't for you, open `dlls.txt` in the game folder and add the new line:
   ```
   discord_rpc.dll
   ```
4. log in and type `/dp status` to verify it's working. if not then maybe try to debug with whatever it says

## commands

| command | description |
|---------|-------------|
| `/dp status` | check discord connection |
| `/dp update` | force a presence update |
| `/dp clear` | clear presence |
| `/dp config` | open the config gui |
| `/dp preset <name>` | apply a preset (minimal / default / detailed) |
| `/dp debug` | toggle debug output |

## linux / wine

the dll writes to the windows named pipe `\\.\pipe\discord-ipc-0`. under wine/proton you need a bridge to forward this to the linux discord socket.

i use: [rpc-bridge](https://github.com/EnderIce2/rpc-bridge) -- but any of them should work.

## custom templates

the presence text is fully customizable. edit templates in the config gui (`/dp config`) or directly in your savedvariables file. the engine uses a go/handlebars-style syntax.

### variables

these are pulled from the wow api every update tick (default 15 seconds) and on zone/group/death events:

| variable | source | example |
|----------|--------|---------|
| `{{player_name}}` | `UnitName("player")` | `Beltmagnet` |
| `{{player_level}}` | `UnitLevel("player")` | `60` |
| `{{player_class}}` | `UnitClass("player")` (english) | `Priest` |
| `{{player_race}}` | `UnitRace("player")` | `Undead` |
| `{{zone}}` | `GetRealZoneText()` | `Elwynn Forest` |
| `{{subzone}}` | `GetMinimapZoneText()` (only if different from zone) | `Goldshire` |

### party member variables

each party slot (1-4) has its own set of variables. empty if the slot is unoccupied.

| variable | source | example |
|----------|--------|---------|
| `{{party1_name}}` | `UnitName("party1")` | `Jonboat` |
| `{{party1_level}}` | `UnitLevel("party1")` | `38` |
| `{{party1_class}}` | `UnitClass("party1")` (english) | `Priest` |
| `{{party1_race}}` | `UnitRace("party1")` | `Human` |
| ... | same for `party2_`, `party3_`, `party4_` | |

### group variables

| variable | condition |
|----------|-----------|
| `{{is_dead}}` | `UnitIsDeadOrGhost("player")` returns true |
| `{{in_party}}` | `GetNumPartyMembers() > 0` and not in a raid |
| `{{in_raid}}` | `GetNumRaidMembers() > 0` |
| `{{is_leader}}` | you are the party/raid leader |
| `{{leader_name}}` | name of the current party/raid leader |
| `{{party_size}}` | party member count + 1 (includes you), only set when in a party |
| `{{raid_size}}` | raid member count, only set when in a raid |

### pipe functions

chain functions with `|` to transform values left to right:

```
{{player_class | lower}}                         --> priest
{{player_class | upper}}                         --> PRIEST
{{player_class | title}}                         --> Priest
class_icons-{{player_class | lower}}             --> class_icons-priest
{{player_name}} the Great                        --> Beltmagnet the Great
{{zone | default "Unknown"}}                     --> Unknown (if zone is empty)
```

available functions: `lower`, `upper`, `title`, `default "str"`

### conditionals

use `{{#if}}`, `{{#elif}}`, `{{#else}}`, `{{/if}}` for conditional blocks:

```
{{#if is_dead}} (Dead){{/if}}

{{#if in_raid}} | Raid ({{raid_size}})
{{#elif in_party}} | Party ({{party_size}})
{{#else}} | Solo
{{/if}}
```

conditionals can be nested:

```
{{#if in_raid}}raiding{{#else}}{{#if in_party}}grouped{{#else}}solo{{/if}}{{/if}}
```

### whitespace control

by default, whitespace and newlines in templates are preserved. use `~` next to the braces to strip whitespace on that side:

- `{{~expr}}` -- strip whitespace/newlines **before** this tag
- `{{expr~}}` -- strip whitespace/newlines **after** this tag
- `{{~expr~}}` -- strip both sides

this lets you write templates across multiple lines for readability while rendering as a single line:

```
{{player_name}} - Level {{player_level~}}
{{~#if is_dead}} (Dead){{/if}}
```

renders as: `Beltmagnet - Level 60` or `Beltmagnet - Level 60 (Dead)`

### comments

```
{{! this text is ignored and won't appear in the output }}
```

### example: default preset

```
details:
  {{player_name}} - Level {{player_level~}}
  {{~#if is_dead}} (Dead){{/if}}

state:
  {{zone~}}
  {{~#if subzone~}}, {{subzone~}}{{~/if~}}
  {{~#if in_raid}} | Raid ({{raid_size}}){{~/if~}}
  {{~#if in_party}} | Party ({{party_size}}){{~/if}}

small_image:
  class_icons-{{player_class | lower}}

small_text:
  {{player_race}} {{player_class}}
```

for a level 38 undead priest named Beltmagnet in goldshire with a 3-person party, this renders:

- **details:** `Beltmagnet - Level 38`
- **state:** `Elwynn Forest, Goldshire | Party (3)`
- **small icon:** `class_icons-priest`
- **small text:** `Undead Priest`

## license

[unlicense](https://unlicense.org/) -- public domain


