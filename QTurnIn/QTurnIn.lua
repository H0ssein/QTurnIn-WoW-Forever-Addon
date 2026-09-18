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
        
        local tex = markFrame:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints()
        markFrame.tex = tex
        
        local text = markFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("TOP", markFrame, "BOTTOM", 0, -2)
        markFrame.text = text
    end
    markFrame:SetParent(parent)
    markFrame:ClearAllPoints()
    markFrame:Show()
    return markFrame
end

local function RecycleMark(unit)
    local marks = activeMarks[unit]
    if marks then
        for _, markFrame in ipairs(marks) do
            markFrame:Hide()
            markFrame:ClearAllPoints()
            markFrame:SetParent(UIParent)
            table.insert(markPool, markFrame)
        end
        activeMarks[unit] = nil
        
        local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
        if nameplate and nameplate.UnitFrame then
            nameplate.UnitFrame:SetScale(1.0)
        end
    end
end

local UpdateUnitMarks

local function InitDB()
    if type(QTurnInDB) ~= "table" then
        QTurnInDB = {
            autoQuest = true,
            nameplateMarks = true,
            partyMarks = true,
        }
    end
    -- Migration for existing DBs
    if QTurnInDB.partyMarks == nil then QTurnInDB.partyMarks = true end

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
            else
                if C_NamePlate then
                    for _, nameplate in ipairs(C_NamePlate.GetNamePlates()) do
                        local u = nameplate.namePlateUnitToken
                        if u then UpdateUnitMarks(u) end
                    end
                end
            end
        elseif cmd == "party" then
            QTurnInDB.partyMarks = not QTurnInDB.partyMarks
            print("|cff00ff00QTurnIn:|r Party Marks are now " .. (QTurnInDB.partyMarks and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
            -- Refresh nameplates to reflect changes
            if C_NamePlate then
                for _, nameplate in ipairs(C_NamePlate.GetNamePlates()) do
                    local u = nameplate.namePlateUnitToken
                    if u then UpdateUnitMarks(u) end
                end
            end
        else
            print("|cff00ff00QTurnIn Commands:|r")
            print("  /qt auto - Toggle Auto Quest Accept/Turn-in")
            print("  /qt mark - Toggle Nameplate Objective Marks")
            print("  /qt party - Toggle Party Member Objectives")
        end
    end
end

local function GetPartyNames()
    local names = {}
    if IsInGroup() then
        for i = 1, GetNumGroupMembers() do
            local unit = IsInRaid() and ("raid"..i) or ("party"..i)
            local name, realm = UnitName(unit)
            if name then
                names[name] = true
                if realm and realm ~= "" then
                    names[name.."-"..realm] = true
                end
            end
        end
    end
    return names
end

local function GetQuestObjectives(unit)
    local tooltipData = C_TooltipInfo.GetUnit(unit)
    if not tooltipData or not tooltipData.lines then return nil end

    local objectives = {}
    local partyNames = GetPartyNames()
    local isPartySection = false
    local seenObjectives = {}

    for _, line in ipairs(tooltipData.lines) do
        local text = line.leftText or ""
        local plainText = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        
        -- Reset party section if it's a Quest Title (type 17 usually)
        if line.type == 17 then
            isPartySection = false
        end
        
        -- Check if text is a party member's name
        if plainText ~= "" and partyNames[plainText] then
            isPartySection = true
        end
        
        if line.type == 8 or line.type == Enum.TooltipDataLineType.QuestObjective or string.match(text, "%d+/%d+") or string.match(text, "[Ss]lain") then
            
            -- If party marks are disabled, skip if we are in a party section
            if isPartySection and not QTurnInDB.partyMarks then
                -- Skip this line entirely
            else
                local isCompleted = line.completed
                local current, max = string.match(text, "(%d+)/(%d+)")
                if current and max then
                    if tonumber(current) >= tonumber(max) then
                        isCompleted = true
                    end
                end
                
                if not isCompleted then
                    local baseObjStr = string.match(text, "%d+/%d+[%s%-]*(.*)")
                    if not baseObjStr then
                        baseObjStr = string.match(plainText, ".*[Ss]lain") or plainText
                    end
                    
                    if baseObjStr then
                        baseObjStr = baseObjStr:gsub("^[%s%-]+", ""):gsub("[%s%-]+$", "")
                    end
                    
                    -- If we haven't seen this objective yet (prevents duplicates between player and party)
                    if not baseObjStr or not seenObjectives[baseObjStr] then
                        if baseObjStr then
                            seenObjectives[baseObjStr] = true
                        end
                        
                        local obj = { isKill = false, progress = nil, icon = nil }
                        
                        if string.match(text, "[Ss]lain") then
                            obj.isKill = true
                        end
                        
                        if current and max then
                            obj.progress = current .. "/" .. max
                            
                            if not obj.isKill then
                                local itemName = baseObjStr
                                if itemName and itemName ~= "" then
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
                                        obj.icon = icon
                                    end
                                end
                            end
                        end
                        
                        table.insert(objectives, obj)
                    end
                end
            end
        end
    end
    
    if #objectives > 0 then return objectives end
    return nil
end

UpdateUnitMarks = function(unit)
    RecycleMark(unit)
    
    if not QTurnInDB or not QTurnInDB.nameplateMarks then return end

    local objectives = GetQuestObjectives(unit)
    if not objectives then return end
    
    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    if not nameplate then return end
    
    activeMarks[unit] = {}
    
    local size = 22
    if #objectives == 2 then size = 18
    elseif #objectives >= 3 then size = 15 end

    local spacing = 4
    local totalWidth = (#objectives * size) + ((#objectives - 1) * spacing)
    local startX = -(totalWidth / 2) + (size / 2)
    
    for i, obj in ipairs(objectives) do
        local markFrame = GetMarkTexture(nameplate)
        markFrame:SetSize(size, size)
        
        local offsetX = startX + ((i - 1) * (size + spacing))
        markFrame:SetPoint("BOTTOM", nameplate, "TOP", offsetX, 8)
        
        if obj.isKill then
            markFrame.tex:SetTexture(ICON_SKULL)
        elseif obj.icon then
            markFrame.tex:SetTexture(obj.icon)
        else
            markFrame.tex:SetTexture(ICON_ITEM)
        end
        
        if obj.progress then
            markFrame.text:SetText(obj.progress)
        else
            markFrame.text:SetText("")
        end
        
        table.insert(activeMarks[unit], markFrame)
    end
    
    if nameplate.UnitFrame then
        nameplate.UnitFrame:SetScale(1.25)
    end
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
        UpdateUnitMarks(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        RecycleMark(unit)
    elseif event == "PLAYER_ENTERING_WORLD" then
        for activeUnit, _ in pairs(activeMarks) do
            RecycleMark(activeUnit)
        end
    elseif event == "QUEST_LOG_UPDATE" then
        if not QTurnInDB or not QTurnInDB.nameplateMarks then return end
        if C_NamePlate then
            for _, nameplate in ipairs(C_NamePlate.GetNamePlates()) do
                local u = nameplate.namePlateUnitToken
                if u then UpdateUnitMarks(u) end
            end
        end
    else
        DoAutoQuest(event)
    end
end)
