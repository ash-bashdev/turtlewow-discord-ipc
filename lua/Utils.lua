DiscordPresence_Utils = {
    DEBUG = false,
    PREFIX = "|cff7289DA[DiscordPresence]|r ",
}

function DiscordPresence_Utils.Print(msg)
    msg = tostring(msg)
    for line in string.gfind(msg, "[^\n]+") do
        DEFAULT_CHAT_FRAME:AddMessage(DiscordPresence_Utils.PREFIX .. line)
    end
end

function DiscordPresence_Utils.Debug(msg)
    if not DiscordPresence_Utils.DEBUG then return end
    DiscordPresence_Utils.Print(msg)
end

function DiscordPresence_Utils.Truncate(s, limit)
    if not s then return "" end
    if string.len(s) > limit then
        return string.sub(s, 1, limit - 3) .. "..."
    end
    return s
end
