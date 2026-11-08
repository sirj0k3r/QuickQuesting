QQ_DEFAULTS = {
    rewardMode = "nothing",
    questScope = "all",
    modifier = "shift",
    autoShare = false,
    shareZoneOnly = true,
    autoAcceptShared = false,
    abandonEnabled = true,
    abandonModifier = "alt",
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
    if (type(QuickQuestingDB.autoShare) ~= "boolean") then
        QuickQuestingDB.autoShare = QQ_DEFAULTS.autoShare;
    end
    if (type(QuickQuestingDB.shareZoneOnly) ~= "boolean") then
        QuickQuestingDB.shareZoneOnly = QQ_DEFAULTS.shareZoneOnly;
    end
    if (type(QuickQuestingDB.autoAcceptShared) ~= "boolean") then
        QuickQuestingDB.autoAcceptShared = QuickQuestingDB.autoShare;
    end
    if (type(QuickQuestingDB.abandonEnabled) ~= "boolean") then
        QuickQuestingDB.abandonEnabled = QQ_DEFAULTS.abandonEnabled;
    end
    if (not IsValidOption(QQ_ModifierOptions, QuickQuestingDB.abandonModifier)) then
        QuickQuestingDB.abandonModifier = QQ_DEFAULTS.abandonModifier;
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
-- Modifier keys
---------------------------------------------------------------------------

function QQ_IsModifierDown(modifier)
    if (modifier == "ctrl") then
        return IsControlKeyDown();
    elseif (modifier == "alt") then
        return IsAltKeyDown();
    end
    return IsShiftKeyDown();
end

function QQ_IsSkipKeyDown()
    return QQ_IsModifierDown(QuickQuestingDB.modifier);
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
