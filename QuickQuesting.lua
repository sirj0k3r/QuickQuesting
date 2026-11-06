local ADDON_NAME = ...;

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

QQ_DEFAULTS = {
    rewardMode = "nothing",
    questScope = "all",
    modifier = "shift",
};

QQ_RewardOptions = {
    { key = "nothing", label = "Nothing" },
    { key = "sellPrice", label = "Highest sell price" },
    { key = "spec", label = "More useful for spec (coming soon)", disabled = true },
};

QQ_ScopeOptions = {
    { key = "all", label = "All quests" },
    { key = "repeatable", label = "Repeatable quests only" },
};

QQ_ModifierOptions = {
    { key = "shift", label = "Shift" },
    { key = "ctrl", label = "Ctrl" },
    { key = "alt", label = "Option / Alt" },
};

QQ_RewardStrategies = {};

local function IsValidOption(options, key)
    for _, option in ipairs(options) do
        if (option.key == key) then
            return true;
        end
    end
    return false;
end

function QQ_InitDB()
    if (type(QuickQuestingDB) ~= "table") then
        QuickQuestingDB = {};
    end

    if (QQ_RewardStrategies[QuickQuestingDB.rewardMode] == nil) then
        QuickQuestingDB.rewardMode = QQ_DEFAULTS.rewardMode;
    end
    if (not IsValidOption(QQ_ScopeOptions, QuickQuestingDB.questScope)) then
        QuickQuestingDB.questScope = QQ_DEFAULTS.questScope;
    end
    if (not IsValidOption(QQ_ModifierOptions, QuickQuestingDB.modifier)) then
        QuickQuestingDB.modifier = QQ_DEFAULTS.modifier;
    end

    if (type(QuickQuestingDB.exceptions) ~= "table") then
        QuickQuestingDB.exceptions = {};
    end
    local exceptions = QuickQuestingDB.exceptions;
    for questID, title in pairs(exceptions) do
        if (type(questID) ~= "number" or type(title) ~= "string") then
            exceptions[questID] = nil;
        end
    end
end

---------------------------------------------------------------------------
-- Skip key
---------------------------------------------------------------------------

function QQ_IsSkipKeyDown()
    local modifier = QuickQuestingDB.modifier;
    if (modifier == "ctrl") then
        return IsControlKeyDown();
    elseif (modifier == "alt") then
        return IsAltKeyDown();
    end
    return IsShiftKeyDown();
end

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
-- Exceptions
---------------------------------------------------------------------------

function QQ_OnExceptionsChanged()
    if (QQ_RefreshOptions) then
        QQ_RefreshOptions();
    end
end

function QQ_IsException(questID)
    return questID ~= nil and QuickQuestingDB.exceptions[questID] ~= nil;
end

function QQ_AddException(questID, knownTitle)
    if (type(questID) ~= "number" or questID < 1 or questID ~= math.floor(questID)) then
        return false;
    end

    local title = knownTitle;
    if (title == nil or title == "") then
        title = C_QuestLog.GetTitleForQuestID(questID);
    end
    if (title == nil or title == "") then
        title = "";
        C_QuestLog.RequestLoadQuestByID(questID);
    end

    QuickQuestingDB.exceptions[questID] = title;
    QQ_OnExceptionsChanged();
    return true;
end

function QQ_RemoveException(questID)
    if (questID ~= nil and QuickQuestingDB.exceptions[questID] ~= nil) then
        QuickQuestingDB.exceptions[questID] = nil;
        QQ_OnExceptionsChanged();
    end
end

function QQ_GetExceptionTitle(questID)
    local title = QuickQuestingDB.exceptions[questID];
    if (title == nil or title == "") then
        return "Quest " .. tostring(questID);
    end
    return title;
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
-- Reward strategies: fn(numChoices) returns choiceIndex or nil, pending
---------------------------------------------------------------------------

QQ_RewardStrategies.nothing = function()
    return nil;
end

QQ_RewardStrategies.sellPrice = function(numChoices)
    local pending = false;
    local bestIndex, bestValue = nil, -1;

    for i = 1, numChoices do
        if (GetQuestItemInfoLootType("choice", i) ~= 0) then
            -- Currency: no vendor price, leave the choice to the player.
            return nil;
        end

        local _, _, numItems, _, _, itemID = GetQuestItemInfo("choice", i);
        if (itemID == nil or itemID == 0) then
            return nil, true;
        end

        local sellPrice = select(11, C_Item.GetItemInfo(itemID));
        if (sellPrice == nil) then
            C_Item.RequestLoadItemDataByID(itemID);
            pending = true;
        else
            local value = sellPrice * math.max(numItems or 1, 1);
            if (value > bestValue) then
                bestIndex, bestValue = i, value;
            end
        end
    end

    if (pending) then
        return nil, true;
    end
    return bestIndex;
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
    if (UnitIsPlayer("questnpc") or UnitIsPlayer("npc")) then
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
