-- DisenchantInfo: slash commands (/dei and /disenchantinfo).
-- (/di is used by the Disenchant Forever addon.)

local _, ns = ...

local HELP = {
    "/dei : open the settings",
    "/dei salvager : Arcane Salvager auto / on / off (or: /dei salvager auto | on | off)",
    "/dei stats : what you have logged, without vs with the Salvager",
    "/dei buffs : your buffs now (to find a Salvager buff)",
    "/dei errors : caught errors (/dei errors clear empties the list)",
}

SLASH_DISENCHANTINFO1 = "/dei"
SLASH_DISENCHANTINFO2 = "/disenchantinfo"
SlashCmdList.DISENCHANTINFO = ns.Safe("slash command", function(msg)
    local cmd, rest = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "" then
        ns.Options:Open()
    elseif cmd == "salvager" or cmd == "salv" then
        if rest == "auto" or rest == "on" or rest == "off" then
            ns.Logger:SetSalvager(rest)
        else
            ns.Logger:CycleSalvager()
        end
    elseif cmd == "stats" then
        ns.ShowCopy("DisenchantInfo stats (Ctrl+A, Ctrl+C to copy)", ns.Logger:StatsReport())
    elseif cmd == "buffs" then
        ns.ShowCopy("DisenchantInfo: your buffs (Ctrl+A, Ctrl+C to copy)", ns.Logger:BuffReport())
    elseif cmd == "errors" then
        if rest == "clear" then
            ns.ClearErrors()
            ns.Print("error log cleared.")
        else
            ns.ShowCopy("DisenchantInfo errors (Ctrl+A, Ctrl+C to copy)", ns.ErrorReport())
        end
    else
        for _, line in ipairs(HELP) do ns.Print(line) end
    end
end)
