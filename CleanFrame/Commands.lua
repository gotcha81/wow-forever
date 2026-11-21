-- CleanFrame: slash commands (/cfr and /cleanframe).

local _, ns = ...

local HELP = {
    "/cfr : open the settings",
    "/cfr unlock | lock : drag the frames / fix them in place",
    "/cfr test : test mode on / off (every frame with sample data)",
    "/cfr reset : put the frames back in their default places",
    "/cfr minimap on | off : show or hide the minimap button",
    "/cfr errors : caught errors (/cfr errors clear empties the list)",
}

SLASH_CLEANFRAME1 = "/cfr"
SLASH_CLEANFRAME2 = "/cleanframe"
SlashCmdList.CLEANFRAME = ns.Safe("slash command", function(msg)
    local cmd, rest = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "" then
        ns.Options:Open()
    elseif cmd == "unlock" then
        if ns.Frames:SetLocked(false) then ns.Print("frames unlocked: drag them. Type /cfr lock when done.") end
    elseif cmd == "lock" then
        if ns.Frames:SetLocked(true) then ns.Print("frames locked.") end
    elseif cmd == "test" then
        ns.Frames:SetTestMode(not ns.Frames.testMode)
    elseif cmd == "reset" then
        ns.Frames:ResetPositions()
    elseif cmd == "minimap" and (rest == "on" or rest == "off") then
        ns.MinimapButton:SetShown(rest == "on")
        ns.Print("minimap button " .. (rest == "on" and "shown." or "hidden."))
    elseif cmd == "errors" then
        if rest == "clear" then
            ns.ClearErrors()
            ns.Print("error log cleared.")
        else
            ns.ShowCopy("CleanFrame errors (Ctrl+A, Ctrl+C to copy)", ns.ErrorReport())
        end
    else
        for _, line in ipairs(HELP) do ns.Print(line) end
    end
end)
