local addonName, addonTable = ...

local frame = CreateFrame("Frame")

local markPool = {}
local activeMarks = {}

local ICON_SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
local ICON_ITEM = "Interface\\Icons\\INV_Misc_Bag_10"

local function GetMarkTexture(parent)
    local markFrame = table.remove(markPool)
    if not markFrame then
        markFrame = CreateFrame("Frame", nil, parent)
        markFrame:SetSize(22, 22)
        
        local tex = markFrame:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints()
        markFrame.tex = tex
        
        local text = markFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("TOP", markFrame, "BOTTOM", 0, -2)
        markFrame.text = text
    end
    markFrame:SetParent(parent)
    markFrame:ClearAllPoints()
    markFrame:SetPoint("BOTTOM", parent, "TOP", 0, 8)
    markFrame:Show()
    return markFrame
end

local function RecycleMark(unit)
    local markFrame = activeMarks[unit]
    if markFrame then
        markFrame:Hide()
        markFrame:ClearAllPoints()
        markFrame:SetParent(UIParent)
        table.insert(markPool, markFrame)
        activeMarks[unit] = nil
        
        local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
        if nameplate and nameplate.UnitFrame then
            nameplate.UnitFrame:SetScale(1.0)
        end
    end
end

local function InitDB()
    if type(QTurnInDB) ~= "table" then
        QTurnInDB = {
            autoQuest = true,
            nameplateMarks = true,
        }
    end

    SLASH_QTURNIN1 = "/qt"
    SLASH_QTURNIN2 = "/qturnin"
    SlashCmdList["QTURNIN"] = function(msg)
        local cmd = msg:lower():match("^(%S*)")
        if cmd == "auto" then
            QTurnInDB.autoQuest = not QTurnInDB.autoQuest
            print("|cff00ff00QTurnIn:|r Auto Quest is now " .. (QTurnInDB.autoQuest and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
        elseif cmd == "mark" or cmd == "marks" then
            QTurnInDB.nameplateMarks = not QTurnInDB.nameplateMarks
            print("|cff00ff00QTurnIn:|r Nameplate Marks are now " .. (QTurnInDB.nameplateMarks and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
            if not QTurnInDB.nameplateMarks then
                for activeUnit, _ in pairs(activeMarks) do
                    RecycleMark(activeUnit)
                end
            end
        else
            print("|cff00ff00QTurnIn Commands:|r")
            print("  /qt auto - Toggle Auto Quest Accept/Turn-in")
            print("  /qt mark - Toggle Nameplate Objective Marks")
        end
    end
end

local function IsQuestObjective(unit)
    local tooltipData = C_TooltipInfo.GetUnit(unit)
    if not tooltipData or not tooltipData.lines then return false, nil, nil, nil end

    local isQuest = false
    local isKill = false
    local progress = nil
    local itemIcon = nil

    for _, line in ipairs(tooltipData.lines) do
        local text = line.leftText or ""
        
        if line.type == 8 or line.type == Enum.TooltipDataLineType.QuestObjective or string.match(text, "%d+/%d+") or string.match(text, "Slain") then
            
            local isCompleted = line.completed
            local current, max = string.match(text, "(%d+)/(%d+)")
            if current and max then
                if tonumber(current) >= tonumber(max) then
                    isCompleted = true
                end
            end
            
            if not isCompleted then
                isQuest = true
                
                if string.match(text, "Slain") then
                    isKill = true
                end
                
                if current and max then
                    progress = current .. "/" .. max
                    
                    if not isKill then
                        local itemName = string.match(text, "%d+/%d+[%s%-]*(.*)")
                        if itemName then
                            itemName = itemName:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^[%s%-]+", ""):gsub("[%s%-]+$", "")
                            if itemName ~= "" then
                                local icon = nil
                                if C_Item and C_Item.GetItemInfoInstant then
                                    local _, _, _, _, i = C_Item.GetItemInfoInstant(itemName)
                                    icon = i
                                elseif C_Item and C_Item.GetItemIconByID then
                                    icon = C_Item.GetItemIconByID(itemName)
                                elseif GetItemInfoInstant then
                                    local _, _, _, _, i = GetItemInfoInstant(itemName)
                                    icon = i
                                end
                                
                                if icon then
                                    itemIcon = icon
                                end
                            end
                        end
                    end
                end
                
                break
            end
        end
    end
    
    return isQuest, isKill, progress, itemIcon
end


local function DoAutoQuest(event)
    if not QTurnInDB or not QTurnInDB.autoQuest then return end
    if IsShiftKeyDown() then return end
    
    if event == "GOSSIP_SHOW" then
        if C_GossipInfo then
            local activeQuests = C_GossipInfo.GetActiveQuests()
            if activeQuests then
                for _, q in ipairs(activeQuests) do
                    if q.isComplete then
                        C_GossipInfo.SelectActiveQuest(q.questID)
                        return
                    end
                end
            end
            
            local availableQuests = C_GossipInfo.GetAvailableQuests()
            if availableQuests then
                for _, q in ipairs(availableQuests) do
                    C_GossipInfo.SelectAvailableQuest(q.questID)
                    return
                end
            end
        end
    elseif event == "QUEST_GREETING" then
        if GetNumActiveQuests then
            for i=1, GetNumActiveQuests() do
                local _, isComplete = GetActiveTitle(i)
                if isComplete then
                    SelectActiveQuest(i)
                    return
                end
            end
        end
        if GetNumAvailableQuests then
            for i=1, GetNumAvailableQuests() do
                SelectAvailableQuest(i)
                return
            end
        end
    elseif event == "QUEST_DETAIL" then
        if AcceptQuest then AcceptQuest() end
    elseif event == "QUEST_ACCEPT_CONFIRM" then
        if ConfirmAcceptQuest then ConfirmAcceptQuest() end
    elseif event == "QUEST_PROGRESS" then
        if IsQuestCompletable and CompleteQuest then
            if IsQuestCompletable() then
                CompleteQuest()
            end
        end
    elseif event == "QUEST_COMPLETE" then
        if GetNumQuestChoices and GetQuestReward then
            if GetNumQuestChoices() <= 1 then
                GetQuestReward(1)
            end
        end
    end
end

frame:RegisterEvent("ADDON_LOADED")

frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("QUEST_LOG_UPDATE")

frame:RegisterEvent("GOSSIP_SHOW")
frame:RegisterEvent("QUEST_GREETING")
frame:RegisterEvent("QUEST_DETAIL")
frame:RegisterEvent("QUEST_ACCEPT_CONFIRM")
frame:RegisterEvent("QUEST_PROGRESS")
frame:RegisterEvent("QUEST_COMPLETE")

frame:SetScript("OnEvent", function(self, event, unit, ...)
    if event == "ADDON_LOADED" and unit == addonName then
        InitDB()
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if not QTurnInDB or not QTurnInDB.nameplateMarks then return end
        local isQuest, isKill, progress, itemIcon = IsQuestObjective(unit)
        if isQuest then
            local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
            if nameplate then
                local markFrame = GetMarkTexture(nameplate)
                
                if isKill then
                    markFrame.tex:SetTexture(ICON_SKULL)
                elseif itemIcon then
                    markFrame.tex:SetTexture(itemIcon)
                else
                    markFrame.tex:SetTexture(ICON_ITEM)
                end
                
                if progress then
                    markFrame.text:SetText(progress)
                else
                    markFrame.text:SetText("")
                end
                
                if nameplate.UnitFrame then
                    nameplate.UnitFrame:SetScale(1.25)
                end
                
                activeMarks[unit] = markFrame
                

            end
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        RecycleMark(unit)
    elseif event == "PLAYER_ENTERING_WORLD" then
        for activeUnit, _ in pairs(activeMarks) do
            RecycleMark(activeUnit)
        end
    elseif event == "QUEST_LOG_UPDATE" then
        if not QTurnInDB or not QTurnInDB.nameplateMarks then return end
        for activeUnit, markFrame in pairs(activeMarks) do
            local isQuest, isKill, progress, itemIcon = IsQuestObjective(activeUnit)
            if isQuest then
                if isKill then
                    markFrame.tex:SetTexture(ICON_SKULL)
                elseif itemIcon then
                    markFrame.tex:SetTexture(itemIcon)
                else
                    markFrame.tex:SetTexture(ICON_ITEM)
                end
                
                if progress then
                    markFrame.text:SetText(progress)
                else
                    markFrame.text:SetText("")
                end
            else
                RecycleMark(activeUnit)
            end
        end
    else
        DoAutoQuest(event)
    end
end)
