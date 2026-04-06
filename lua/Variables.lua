DiscordPresence_Vars = {}

DiscordPresence_Vars.MAX_LEN = 128

function DiscordPresence_Vars.Build()
    local playerName = UnitName("player")
    if not playerName then return nil end

    local localizedClass = UnitClass("player")
    local localizedRace = UnitRace("player")
    local playerLevel = UnitLevel("player")
    local zoneName = GetRealZoneText()
    local subZone = GetMinimapZoneText()

    if not zoneName or zoneName == "" then zoneName = "Unknown" end
    if subZone == zoneName then subZone = "" end

    local numRaid = GetNumRaidMembers and GetNumRaidMembers() or 0
    local numParty = GetNumPartyMembers and GetNumPartyMembers() or 0
    local isDead = UnitIsDeadOrGhost("player")

    local xp = UnitXP and UnitXP("player") or 0
    local xpMax = UnitXPMax and UnitXPMax("player") or 0

    local vars = {
        player_name = playerName or "",
        player_level = playerLevel and tostring(playerLevel) or "",
        player_class = localizedClass or "",
        player_race = localizedRace or "",
        zone = zoneName or "",
        subzone = subZone or "",
        is_dead = isDead and "1" or "",
        in_party = (numParty > 0 and numRaid == 0) and "1" or "",
        in_raid = (numRaid > 0) and "1" or "",
        party_size = (numParty > 0 and numRaid == 0) and tostring(numParty + 1) or "",
        raid_size = (numRaid > 0) and tostring(numRaid) or "",
        xp = tostring(xp),
        xp_max = tostring(xpMax),
        xp_remaining = tostring(xpMax - xp),
        is_max_level = (xpMax == 0) and "1" or "",
    }

    -- leader
    local isLeader = IsPartyLeader and IsPartyLeader() or false
    vars.is_leader = isLeader and "1" or ""
    if numRaid > 0 or numParty > 0 then
        if UnitIsPartyLeader and UnitIsPartyLeader("player") then
            vars.leader_name = playerName
        else
            for i = 1, 4 do
                local unit = "party" .. i
                if UnitIsPartyLeader and UnitIsPartyLeader(unit) then
                    vars.leader_name = UnitName(unit) or ""
                    break
                end
            end
        end
    end
    if not vars.leader_name then vars.leader_name = "" end

    -- party members (party1 through party4)
    for i = 1, 4 do
        local unit = "party" .. i
        local name = UnitName(unit)
        local p = "party" .. i .. "_"
        if name then
            vars[p .. "name"] = name
            vars[p .. "level"] = tostring(UnitLevel(unit) or "")
            vars[p .. "class"] = UnitClass(unit) or ""
            vars[p .. "race"] = UnitRace(unit) or ""
        else
            vars[p .. "name"] = ""
            vars[p .. "level"] = ""
            vars[p .. "class"] = ""
            vars[p .. "race"] = ""
        end
    end

    return vars
end

-- Render all 6 fields from compiled templates + vars
function DiscordPresence_Vars.RenderFields(compiledTemplates, vars)
    if not compiledTemplates or not vars then return nil end
    local T = DiscordPresence_Template
    local MAX = DiscordPresence_Vars.MAX_LEN
    local trunc = DiscordPresence_Utils.Truncate
    return {
        details    = trunc(T.Render(compiledTemplates.details, vars), MAX),
        state      = trunc(T.Render(compiledTemplates.state, vars), MAX),
        largeImage = T.Render(compiledTemplates.large_image, vars),
        largeText  = trunc(T.Render(compiledTemplates.large_text, vars), MAX),
        smallImage = T.Render(compiledTemplates.small_image, vars),
        smallText  = trunc(T.Render(compiledTemplates.small_text, vars), MAX),
    }
end


