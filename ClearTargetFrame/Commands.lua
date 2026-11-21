-- ClearTargetFrame: slash commands (/ctf and /cleartargetframe).

local _, ns = ...

local HELP = {
    "/ctf : open the settings",
    "/ctf unlock | lock : drag the frames / fix them in place",
    "/ctf reset : put the frames back in their default places",
    "/ctf errors : caught errors (/ctf errors clear empties the list)",
}

SLASH_CLEARTARGETFRAME1 = "/ctf"
SLASH_CLEARTARGETFRAME2 = "/cleartargetframe"
SlashCmdList.CLEARTARGETFRAME = ns.Safe("slash command", function(msg)
    local cmd, rest = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "" then
        ns.Options:Open()
    elseif cmd == "unlock" then
        if ns.Frames:SetLocked(false) then ns.Print("frames unlocked: drag them. Type /ctf lock when done.") end
    elseif cmd == "lock" then
        if ns.Frames:SetLocked(true) then ns.Print("frames locked.") end
    elseif cmd == "reset" then
        ns.Frames:ResetPositions()
    elseif cmd == "errors" then
        if rest == "clear" then
            ns.ClearErrors()
            ns.Print("error log cleared.")
        else
            ns.ShowCopy("ClearTargetFrame errors (Ctrl+A, Ctrl+C to copy)", ns.ErrorReport())
        end
    else
        for _, line in ipairs(HELP) do ns.Print(line) end
    end
end)
