local ADDON_NAME, QQ = ...;

local LOOP_GUARD_SECONDS = 2;

-- Frequencies that count as repeatable: daily, weekly and scheduler-reset quests.
local REPEATABLE_FREQUENCIES = {
    [Enum.QuestFrequency.Daily] = true,
    [Enum.QuestFrequency.Weekly] = true,
    [Enum.QuestFrequency.ResetByScheduler] = true,
};

-- Frequencies of repeatable quests whose hand-in items are safe to give automatically.
local RESET_FREQUENCIES = {
    [Enum.QuestFrequency.Daily] = true,
    [Enum.QuestFrequency.Weekly] = true,
};

local questFrequency = {};
local questRepeatable = {};
local recentlySelected = {};
-- Quests refused after being opened (gold cost, PvP...). Not auto-selected from lists again this
-- session, so they don't hide the NPC's other options on every visit.
local leftForPlayer = {};
local pendingReward = nil;
local shareFromPlayer = QQ.shareFromPlayer;

---------------------------------------------------------------------------
-- Quest frequency
---------------------------------------------------------------------------

-- Returns the quest frequency (Enum.QuestFrequency) or nil if unknown.
local function QQ_GetFrequency(questID, frequency)
    if (frequency ~= nil) then
        return frequency;
    end

    local logIndex = C_QuestLog.GetLogIndexForQuestID(questID);
    if (logIndex) then
        local info = C_QuestLog.GetInfo(logIndex);
        if (info and info.frequency ~= nil) then
            return info.frequency;
        end
    end

    return questFrequency[questID];
end

-- A quest counts as repeatable when its frequency is daily, weekly or scheduler-reset, or when
-- the game flags it as repeatable.
function QQ_IsRepeatable(questID, frequency)
    local resolved = QQ_GetFrequency(questID, frequency);
    if (resolved ~= nil and REPEATABLE_FREQUENCIES[resolved] == true) then
        return true;
    end
    if (questRepeatable[questID]) then
        return true;
    end
    if (C_QuestLog.IsRepeatableQuest(questID)) then
        return true;
    end

    -- QuestIsDaily and QuestIsWeekly are undocumented globals that only describe the quest open
    -- in the quest window, so they are only asked about that quest. Guarded so a client
    -- without them simply falls through to "not repeatable".
    if (questID == GetQuestID()) then
        if (QuestIsDaily and QuestIsDaily()) then
            return true;
        end
        if (QuestIsWeekly and QuestIsWeekly()) then
            return true;
        end
    end

    return false;
end

---------------------------------------------------------------------------
-- Decision helpers
---------------------------------------------------------------------------

function QQ_ShouldHandle(questID, frequency)
    if (questID == nil or questID == 0) then
        return false;
    end
    if (QuickQuestingDB.exceptions[questID] ~= nil) then
        return false;
    end
    if (QuickQuestingDB.questScope == "repeatable" and QQ_IsRepeatable(questID, frequency) ~= true) then
        return false;
    end
    return true;
end

local function CacheQuestInfo(questID, frequency, repeatable)
    if (questID and questID ~= 0) then
        if (frequency ~= nil) then
            questFrequency[questID] = frequency;
        end
        if (repeatable) then
            questRepeatable[questID] = true;
        end
    end
end

local function CanSelectFromList(questID, frequency)
    if (not QQ_ShouldHandle(questID, frequency) or leftForPlayer[questID]) then
        return false;
    end
    local last = recentlySelected[questID];
    if (last and GetTime() - last < LOOP_GUARD_SECONDS) then
        return false;
    end
    return true;
end

---------------------------------------------------------------------------
-- Event handlers
---------------------------------------------------------------------------

local function OnGossipShow()
    local active = C_GossipInfo.GetActiveQuests();
    for _, quest in ipairs(active) do
        CacheQuestInfo(quest.questID, quest.frequency, quest.repeatable);
    end
    local available = C_GossipInfo.GetAvailableQuests();
    for _, quest in ipairs(available) do
        CacheQuestInfo(quest.questID, quest.frequency, quest.repeatable);
    end

    for _, quest in ipairs(active) do
        local questID = quest.questID;
        if (quest.isComplete and CanSelectFromList(questID, quest.frequency)) then
            recentlySelected[questID] = GetTime();
            C_GossipInfo.SelectActiveQuest(questID);
            return;
        end
    end

    for _, quest in ipairs(available) do
        local questID = quest.questID;
        if (not quest.isIgnored and CanSelectFromList(questID, quest.frequency)) then
            recentlySelected[questID] = GetTime();
            C_GossipInfo.SelectAvailableQuest(questID);
            return;
        end
    end
end

local function OnQuestGreeting()
    for i = 1, GetNumActiveQuests() do
        local _, isComplete = GetActiveTitle(i);
        local questID = GetActiveQuestID(i);
        if (isComplete and CanSelectFromList(questID)) then
            recentlySelected[questID] = GetTime();
            SelectActiveQuest(i);
            return;
        end
    end

    for i = 1, GetNumAvailableQuests() do
        local _, frequency, isRepeatable, _, questID = GetAvailableQuestInfo(i);
        CacheQuestInfo(questID, frequency, isRepeatable);
        if (CanSelectFromList(questID, frequency)) then
            recentlySelected[questID] = GetTime();
            SelectAvailableQuest(i);
            return;
        end
    end
end

local function IsQuestFromPlayer()
    return UnitIsPlayer("questnpc") or UnitIsPlayer("npc");
end

-- A player's offer stops being the one shown when the quest window closes or shows another offer.
-- Accepts can still arrive just after (some without a QUEST_DETAIL, such as an escort confirm), so
-- the time is kept rather than the mark dropped.
local function CloseShareMarks()
    local now = GetTime();
    for questID, mark in pairs(shareFromPlayer) do
        if (mark == true) then
            shareFromPlayer[questID] = now;
        end
    end
end

local function OnQuestDetail(questStartItemID)
    -- Blizzard shows a confirmation popup (or the quest is not from an NPC) in these cases.
    if (questStartItemID ~= nil and questStartItemID ~= 0) then
        return;
    end
    if (QuestIsFromAdventureMap()) then
        return;
    end
    if (QuestGetAutoAccept() and QuestIsFromAreaTrigger()) then
        return;
    end
    if (QuestFlagsPVP()) then
        leftForPlayer[GetQuestID()] = true;
        return;
    end
    if (IsQuestFromPlayer() and not QuickQuestingDB.autoAcceptShared) then
        return;
    end

    if (QQ_ShouldHandle(GetQuestID())) then
        if (QuestGetAutoAccept()) then
            AcknowledgeAutoAcceptQuest();
        else
            AcceptQuest();
        end
    end
end

local function OnQuestProgress()
    local questID = GetQuestID();
    if (not QQ_ShouldHandle(questID)) then
        return;
    end
    if (not IsQuestCompletable()) then
        return;
    end
    if (GetQuestMoneyToGet() > 0 or GetNumQuestCurrencies() > 0) then
        leftForPlayer[questID] = true;
        return;
    end
    if (GetNumQuestItems() > 0 and (questRepeatable[questID] or C_QuestLog.IsRepeatableQuest(questID))) then
        local frequency = QQ_GetFrequency(questID);
        if (frequency == nil or RESET_FREQUENCIES[frequency] ~= true) then
            leftForPlayer[questID] = true;
            return;
        end
    end
    CompleteQuest();
end

local function OnQuestComplete()
    local questID = GetQuestID();
    if (not QQ_ShouldHandle(questID)) then
        return;
    end
    if (GetQuestMoneyToGet() > 0) then
        leftForPlayer[questID] = true;
        return;
    end

    local numChoices = GetNumQuestChoices();
    if (numChoices <= 1) then
        pendingReward = nil;
        GetQuestReward(numChoices);
        return;
    end

    local strategy = QQ_RewardStrategies[QuickQuestingDB.rewardMode];
    if (strategy == nil) then
        return;
    end
    local choice, pending = strategy(numChoices);
    if (choice) then
        pendingReward = nil;
        GetQuestReward(choice);
    elseif (pending) then
        pendingReward = questID;
    else
        pendingReward = nil;
    end
end

local function OnRewardDataUpdate()
    if (pendingReward and pendingReward == GetQuestID()) then
        OnQuestComplete();
    end
end

local frame = CreateFrame("Frame");
frame:RegisterEvent("ADDON_LOADED");
frame:RegisterEvent("GOSSIP_SHOW");
frame:RegisterEvent("QUEST_GREETING");
frame:RegisterEvent("QUEST_DETAIL");
frame:RegisterEvent("QUEST_PROGRESS");
frame:RegisterEvent("QUEST_COMPLETE");
frame:RegisterEvent("QUEST_ITEM_UPDATE");
frame:RegisterEvent("ITEM_DATA_LOAD_RESULT");
frame:RegisterEvent("QUEST_FINISHED");
frame:RegisterEvent("QUEST_DATA_LOAD_RESULT");

frame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if (event == "ADDON_LOADED") then
        if (arg1 == ADDON_NAME) then
            QQ_InitDB();
        end
        return;
    end

    if (QuickQuestingDB == nil) then
        return;
    end

    -- Bookkeeping that never touches the quest window runs even while the skip key is down.
    if (event == "QUEST_DATA_LOAD_RESULT") then
        if (arg2 and QuickQuestingDB.exceptions[arg1] == "") then
            local title = C_QuestLog.GetTitleForQuestID(arg1);
            if (title and title ~= "") then
                QuickQuestingDB.exceptions[arg1] = title;
                QQ_OnExceptionsChanged();
            end
        end
        return;
    end

    if (event == "QUEST_FINISHED") then
        pendingReward = nil;
        -- Only timestamped, not cleared: QUEST_FINISHED can fire before QUEST_ACCEPTED.
        CloseShareMarks();
    end

    if (event == "QUEST_DETAIL") then
        -- Set or cleared on every offer, so a share that was declined and then taken from an NPC can
        -- still be shared.
        CloseShareMarks();
        local questID = GetQuestID();
        if (questID and questID ~= 0) then
            shareFromPlayer[questID] = IsQuestFromPlayer() or nil;
        end
    end

    if (QQ_IsSkipKeyDown()) then
        return;
    end

    if (event == "GOSSIP_SHOW") then
        OnGossipShow();
    elseif (event == "QUEST_GREETING") then
        OnQuestGreeting();
    elseif (event == "QUEST_DETAIL") then
        OnQuestDetail(arg1);
    elseif (event == "QUEST_PROGRESS") then
        OnQuestProgress();
    elseif (event == "QUEST_COMPLETE") then
        OnQuestComplete();
    elseif (event == "ITEM_DATA_LOAD_RESULT" and arg2 == false) then
        -- An item failed to load: stop retrying and leave the reward window for the player.
        pendingReward = nil;
    elseif (event == "QUEST_ITEM_UPDATE" or event == "ITEM_DATA_LOAD_RESULT") then
        OnRewardDataUpdate();
    end
end)
