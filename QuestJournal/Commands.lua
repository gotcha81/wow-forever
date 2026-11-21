-- Slash command /qj

local _, ns = ...

local HELP = {
    "/qj - open or close the journal",
    "/qj clear - remove the map pins",
    "/qj minimap on|off - show or hide the minimap button",
    "/qj status - what data QuestJournal found",
    "/qj errors - show caught errors (/qj errors clear empties the list)",
}

local function Status()
    local D, C = ns.Data, ns.Chains
    local lines = {
        "QuestJournal " .. ns.Version(),
        "Questie data: " .. (D.questie and "yes" or "no (only the game's own data)"),
        "Questie zone module: " .. (D.zoneDB and "yes" or "no (no map pins)"),
        "Ready: " .. (ns.ready and "yes" or "no, still reading"),
        "Chains: " .. (C.count or 0),
    }
    local keys = 0
    for _, line in ipairs(C.lines or {}) do if line.hasKey then keys = keys + 1 end end
    lines[#lines + 1] = "Chains that reward a key: " .. keys
    lines[#lines + 1] = "Game questline API (C_QuestLine): " .. (C_QuestLine and C_QuestLine.GetQuestLineQuests and "yes" or "no")
    lines[#lines + 1] = "Completed-quests list (GetAllCompletedQuestIDs): " ..
        (C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs and "yes" or "no")
    for _, l in ipairs(lines) do ns.Print(l) end
end

SLASH_QUESTJOURNAL1 = "/qj"
SLASH_QUESTJOURNAL2 = "/questjournal"
SlashCmdList.QUESTJOURNAL = ns.Safe("slash", function(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "" then
        ns.Window:Toggle()
    elseif cmd == "clear" then
        ns.MapPins:Clear()
    elseif cmd == "minimap" then
        ns.MinimapButton:SetShown(arg ~= "off")
    elseif cmd == "status" then
        Status()
    elseif cmd == "errors" then
        if arg == "clear" then
            ns.ClearErrors()
            ns.Print("error list emptied.")
        else
            ns.ShowCopy("QuestJournal errors", ns.ErrorReport())
        end
    else
        for _, l in ipairs(HELP) do ns.Print(l) end
    end
end)
