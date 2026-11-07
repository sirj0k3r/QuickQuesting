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
    autoShare = false,
    autoAcceptShared = false,
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
    if (type(QuickQuestingDB.autoAcceptShared) ~= "boolean") then
        QuickQuestingDB.autoAcceptShared = QuickQuestingDB.autoShare;
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
-- Auto share
---------------------------------------------------------------------------

-- A later quest is pushed while a member still has an earlier popup open: the server answers
-- "busy" and leaves that popup alone.
local SHARE_ACK_SECONDS = 3;
local SHARE_REPLY_SECONDS = 60;
local SHARE_LATE_SECONDS = 300;
local SHARE_MAX_PUSHES = 5;
local SHARE_INFLECT_BYTES = 4;

local SHARE_OPEN = 1;
local SHARE_BUSY = 2;
local SHARE_DONE = 3;

-- The replies only need listening to while something is being shared.
local SHARE_ACTIVE_EVENTS = {
    "CHAT_MSG_SYSTEM",
    "QUEST_REMOVED",
    "GROUP_ROSTER_UPDATE",
    "PLAYER_REGEN_ENABLED",
    "ADDON_RESTRICTION_STATE_CHANGED",
};

local SHARE_REPLY_KINDS = {
    { kind = "sent", suffixes = { "SUCCESS" } },
    { kind = "busy", suffixes = { "BUSY" } },
    { kind = "accepted", suffixes = { "ACCEPTED" } },
    { kind = "declined", suffixes = { "DECLINED" } },
    { kind = "final", suffixes = {
        "ALREADY_DONE", "CLASS", "DEAD", "DIFFERENT_SERVER_DAILY", "EXPANSION", "HIGH_FACTION",
        "HIGH_LEVEL", "INVALID", "LOG_FULL", "LOW_FACTION", "LOW_LEVEL", "NEW_PLAYER_EXPERIENCE",
        "NOT_GARRISON_OWNER", "ONQUEST", "PREREQUISITE", "RACE", "TOO_FAR", "WRONG_COVENANT",
        "WRONG_FACTION",
    } },
};

-- Replies that name no player, matched by exact text.
local SHARE_NAMELESS_KINDS = {
    { kind = "questBlocked", keys = { "ERR_QUEST_PUSH_NOT_ALLOWED_S", "ERR_QUEST_PUSH_NOT_DAILY_S" } },
    { kind = "groupBlocked", keys = { "ERR_QUEST_PUSH_NOT_IN_PARTY_S", "ERR_QUEST_PUSH_CROSS_FACTION_RESTRICTED_S" } },
};

local shareFrame = nil;
local shareQueue = {};
local shareOpen = {};
local shareEntry = nil;
local shareFlight = false;
local shareFlightDeadline = nil;
local shareExpected = {};
local shareRoster = {};
local shareRosterBase = {};
local shareLoading = false;
local shareTimer = nil;
local sharePatterns = nil;
local shareNameless = nil;
local shareActive = false;
-- Quests someone declined. A push can't exclude a player, so these are not pushed again while we
-- stay in this group, even if that means a slower member misses them. Cleared when the group ends,
-- and per quest when it is turned in.
local shareDeclined = {};
-- Quests last offered by another player. Accepting one doesn't push it again: the party already got
-- that offer, and a second push would prompt anyone who declined it again.
local shareFromPlayer = {};

local OnShareTimer;
local PumpShareQueue;

local function IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value);
end

local function StripGrammar(text)
    text = text:gsub("|3%-%d+%((.-)%)", "%1");
    text = text:gsub("|2 ?", "");
    text = text:gsub("|1[^;]*;[^;]*;", "");
    return text;
end

local function BuildSharePatterns()
    if (sharePatterns ~= nil) then
        return;
    end

    sharePatterns = {};
    for _, group in ipairs(SHARE_REPLY_KINDS) do
        for _, suffix in ipairs(group.suffixes) do
            local format = _G["ERR_QUEST_PUSH_" .. suffix .. "_S"];
            if (type(format) == "string") then
                local stripped = StripGrammar(format);
                local fuzzy = stripped ~= format;
                local pattern = stripped:gsub("%%%d*%$?s", "\001");
                if (pattern:find("\001", 1, true)) then
                    pattern = pattern:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0");
                    pattern = pattern:gsub("\001", "(.+)");
                    sharePatterns[#sharePatterns + 1] = { pattern = "^" .. pattern .. "$", kind = group.kind, fuzzy = fuzzy };
                end
            end
        end
    end

    shareNameless = {};
    for _, group in ipairs(SHARE_NAMELESS_KINDS) do
        for _, key in ipairs(group.keys) do
            local text = _G[key];
            if (type(text) == "string") then
                shareNameless[text] = group.kind;
            end
        end
    end
end

local function RefreshShareRoster()
    wipe(shareRoster);
    wipe(shareRosterBase);

    local prefix = IsInRaid() and "raid" or "party";
    for i = 1, GetNumGroupMembers() do
        local unit = prefix .. i;
        if (UnitExists(unit) and not UnitIsUnit(unit, "player") and UnitIsConnected(unit)) then
            local name, realm = UnitName(unit);
            if (name ~= nil and not IsSecret(name) and not IsSecret(realm) and name ~= UNKNOWNOBJECT) then
                local key = name;
                if (realm ~= nil and realm ~= "") then
                    key = name .. "-" .. (realm:gsub(" ", ""));
                end
                shareRoster[key] = true;
                if (shareRosterBase[name] == nil) then
                    shareRosterBase[name] = key;
                else
                    shareRosterBase[name] = false;
                end
            end
        end
    end
end

-- Returns the roster key for a name, and whether the name matched several members.
local function LookupRosterKey(key)
    if (shareRoster[key]) then
        return key, false;
    end
    local base = key:match("^([^-]+)");
    local owner = base and shareRosterBase[base];
    if (owner) then
        return owner, false;
    end
    return nil, owner == false;
end

-- Some clients (ruRU, koKR, frFR) put the name through grammar tokens, so it can arrive
-- inflected or prefixed. A name that still does not match just falls to the timeout.
local function ResolveShareName(captured, fuzzy)
    captured = captured:match("^%[(.+)%]$") or captured;

    local found, ambiguous = LookupRosterKey((captured:gsub("%s", "")));
    if (found) then
        return found;
    end
    if (ambiguous or not fuzzy) then
        return nil;
    end

    captured = captured:gsub("^de%s+", "");
    captured = captured:gsub("^d'", "");
    captured = captured:gsub("^d\226\128\153", "");
    local cleaned = captured:gsub("%s", "");
    found, ambiguous = LookupRosterKey(cleaned);
    if (found) then
        return found;
    end
    if (ambiguous) then
        return nil;
    end

    local match = nil;
    local matches = 0;
    for baseName, owner in pairs(shareRosterBase) do
        if (owner) then
            local common = 0;
            local limit = math.min(#baseName, #cleaned);
            while (common < limit and baseName:byte(common + 1) == cleaned:byte(common + 1)) do
                common = common + 1;
            end
            if (common >= math.max(2, #baseName - SHARE_INFLECT_BYTES)) then
                match = owner;
                matches = matches + 1;
            end
        end
    end
    if (matches == 1) then
        return match;
    end
    return nil;
end

local function FindShareEntry(questID)
    for _, entry in ipairs(shareQueue) do
        if (entry.questID == questID) then
            return entry;
        end
    end
    return nil;
end

local function RemoveShareEntry(target)
    for i, entry in ipairs(shareQueue) do
        if (entry == target) then
            table.remove(shareQueue, i);
            return;
        end
    end
end

local function ArmShareTimer()
    if (shareTimer) then
        shareTimer:Cancel();
        shareTimer = nil;
    end

    local earliest = nil;
    if (shareFlight) then
        earliest = shareFlightDeadline;
    end
    for _, open in pairs(shareOpen) do
        local at = open.expired and open.forgetAt or open.deadline;
        if (earliest == nil or at < earliest) then
            earliest = at;
        end
    end
    if (earliest == nil) then
        return;
    end

    shareTimer = C_Timer.NewTimer(math.max(earliest - GetTime(), 0.1), OnShareTimer);
end

local function StopShareIfIdle()
    if (#shareQueue == 0 and next(shareOpen) == nil and not shareFlight) then
        for _, event in ipairs(SHARE_ACTIVE_EVENTS) do
            shareFrame:UnregisterEvent(event);
        end
        if (shareTimer) then
            shareTimer:Cancel();
            shareTimer = nil;
        end
        shareEntry = nil;
        wipe(shareExpected);
        shareActive = false;
        return true;
    end
    return false;
end

local function StartShareEvents()
    if (shareActive) then
        return;
    end
    BuildSharePatterns();
    RefreshShareRoster();
    for _, event in ipairs(SHARE_ACTIVE_EVENTS) do
        shareFrame:RegisterEvent(event);
    end
    shareActive = true;
end

function QQ_ClearShareQueue()
    if (not shareActive) then
        return;
    end
    wipe(shareQueue);
    wipe(shareOpen);
    wipe(shareExpected);
    shareFlight = false;
    shareFlightDeadline = nil;
    StopShareIfIdle();
end

local function PruneShareQueue()
    for i = #shareQueue, 1, -1 do
        local entry = shareQueue[i];
        local declined = shareDeclined[entry.questID];
        if ((entry.pushes > 0 or declined) and not (shareFlight and entry == shareEntry)) then
            if (declined or entry.pushes >= SHARE_MAX_PUSHES) then
                for name, state in pairs(entry.members) do
                    if (state == SHARE_BUSY) then
                        entry.members[name] = SHARE_DONE;
                    end
                end
            end
            local waiting = false;
            for _, state in pairs(entry.members) do
                if (state == SHARE_OPEN or state == SHARE_BUSY) then
                    waiting = true;
                    break;
                end
            end
            if (not waiting) then
                table.remove(shareQueue, i);
            end
        end
    end
end

local function IsShareWanted(entry)
    if (shareDeclined[entry.questID] or entry.pushes >= SHARE_MAX_PUSHES) then
        return false;
    end
    for name in pairs(shareRoster) do
        local open = shareOpen[name];
        local state = entry.members[name];
        if (entry.pushes == 0) then
            -- A member whose popup timed out does not hold back a new quest.
            if (state == nil and (open == nil or open.expired)) then
                return true;
            end
        elseif (state == SHARE_BUSY and open == nil) then
            return true;
        end
    end
    return false;
end

PumpShareQueue = function()
    PruneShareQueue();
    if (StopShareIfIdle()) then
        return;
    end
    if (not IsInGroup()) then
        QQ_ClearShareQueue();
        return;
    end
    if (C_PartyInfo.IsCrossFactionParty and C_PartyInfo.IsCrossFactionParty()) then
        QQ_ClearShareQueue();
        return;
    end
    if (next(shareRoster) == nil) then
        QQ_ClearShareQueue();
        return;
    end

    local paused = shareLoading or InCombatLockdown()
        or (C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown());
    if (not shareFlight and not paused) then
        local i = 1;
        while (shareQueue[i]) do
            local entry = shareQueue[i];
            if (IsShareWanted(entry)) then
                -- The log index is passed so the quest selected in the log is never touched.
                local index = C_QuestLog.GetLogIndexForQuestID(entry.questID);
                if (index and C_QuestLog.IsPushableQuest(entry.questID) and pcall(QuestLogPushQuest, index)) then
                    entry.pushes = entry.pushes + 1;
                    shareEntry = entry;
                    shareFlight = true;
                    shareFlightDeadline = GetTime() + SHARE_ACK_SECONDS;
                    wipe(shareExpected);
                    for name in pairs(shareRoster) do
                        shareExpected[name] = true;
                    end
                    break;
                end
                table.remove(shareQueue, i);
            else
                i = i + 1;
            end
        end
    end

    ArmShareTimer();
end

-- Anything not answered may have received the popup, and the timeout covers it. The caller
-- pumps the queue afterwards.
local function EndShareFlight()
    if (not shareFlight) then
        return;
    end
    shareFlight = false;
    shareFlightDeadline = nil;

    for name in pairs(shareExpected) do
        if (shareRoster[name] and shareOpen[name] == nil and shareEntry.members[name] ~= SHARE_DONE) then
            shareEntry.members[name] = SHARE_OPEN;
            shareOpen[name] = { entry = shareEntry, deadline = GetTime() + SHARE_REPLY_SECONDS, expired = false, assumed = true };
        end
    end
    wipe(shareExpected);
end

OnShareTimer = function()
    shareTimer = nil;
    local now = GetTime();

    if (shareFlight and now >= shareFlightDeadline) then
        EndShareFlight();
    end

    for name, open in pairs(shareOpen) do
        if (open.expired) then
            if (now >= open.forgetAt) then
                shareOpen[name] = nil;
                for _, entry in ipairs(shareQueue) do
                    if (entry.members[name] == SHARE_BUSY) then
                        entry.members[name] = SHARE_DONE;
                    end
                end
            end
        elseif (now >= open.deadline) then
            open.expired = true;
            open.forgetAt = now + SHARE_LATE_SECONDS;
            -- Timed out: final for this quest, never a reason to push it again.
            if (open.entry.members[name] == SHARE_OPEN) then
                open.entry.members[name] = SHARE_DONE;
            end
        end
    end

    PumpShareQueue();
end

local function OnShareSent(name)
    local entry = shareEntry;
    local open = shareOpen[name];
    if (open and open.entry ~= entry and open.entry.members[name] == SHARE_OPEN) then
        -- A new popup means the earlier one closed without a reply, so none will come for it.
        open.entry.members[name] = SHARE_DONE;
    end
    shareOpen[name] = { entry = entry, deadline = GetTime() + SHARE_REPLY_SECONDS, expired = false };
    if (entry.members[name] ~= SHARE_DONE) then
        entry.members[name] = SHARE_OPEN;
    end
end

local function OnShareBusy(name)
    local entry = shareEntry;
    local open = shareOpen[name];
    if (open and open.entry == entry) then
        return;
    end
    if (entry.members[name] == SHARE_DONE) then
        return;
    end
    if (open) then
        entry.members[name] = (entry.pushes >= SHARE_MAX_PUSHES) and SHARE_DONE or SHARE_BUSY;
    else
        -- Cause unknown and no answer will ever arrive to trigger a retry.
        entry.members[name] = SHARE_DONE;
    end
end

-- Does not touch shareOpen: an earlier popup may still be open.
local function OnShareFinal(name)
    shareEntry.members[name] = SHARE_DONE;
end

-- Answers name a player and not a quest, so they belong to whichever popup that member has open.
local function OnShareAnswer(name, declined)
    local open = shareOpen[name];
    if (open == nil) then
        return;
    end
    open.entry.members[name] = SHARE_DONE;
    if (declined) then
        shareDeclined[open.entry.questID] = true;
    end
    shareOpen[name] = nil;
end

local function OnShareMessage(text)
    if (IsSecret(text) or type(text) ~= "string") then
        return;
    end
    text = StripGrammar(text);

    local nameless = shareNameless[text];
    if (nameless == "groupBlocked") then
        QQ_ClearShareQueue();
        return;
    elseif (nameless == "questBlocked") then
        if (shareFlight and shareEntry) then
            wipe(shareExpected);
            EndShareFlight();
            RemoveShareEntry(shareEntry);
            PumpShareQueue();
        end
        return;
    end

    for _, p in ipairs(sharePatterns) do
        local captured = text:match(p.pattern);
        if (captured) then
            local name = ResolveShareName(captured, p.fuzzy);
            if (not name) then
                return;
            end
            if (p.kind == "accepted" or p.kind == "declined") then
                OnShareAnswer(name, p.kind == "declined");
            else
                if (shareEntry == nil) then
                    return;
                end
                if (p.kind == "sent") then
                    OnShareSent(name);
                elseif (p.kind == "busy") then
                    OnShareBusy(name);
                else
                    OnShareFinal(name);
                end
                shareExpected[name] = nil;
                if (shareFlight and next(shareExpected) == nil) then
                    EndShareFlight();
                end
            end
            PumpShareQueue();
            return;
        end
    end
end

local function OnShareAccepted(questID)
    -- Cleared before the other checks so the mark never outlives this accept.
    local fromPlayer = shareFromPlayer[questID];
    shareFromPlayer[questID] = nil;
    if (fromPlayer) then
        return;
    end
    if (not (QuickQuestingDB and QuickQuestingDB.autoShare)) then
        return;
    end
    if (not IsInGroup()) then
        return;
    end
    if (FindShareEntry(questID) or shareDeclined[questID]) then
        return;
    end
    if (not (C_QuestLog.GetLogIndexForQuestID(questID) and C_QuestLog.IsPushableQuest(questID))) then
        return;
    end

    StartShareEvents();
    shareQueue[#shareQueue + 1] = { questID = questID, pushes = 0, members = {} };
    PumpShareQueue();
end

-- A separate frame so the skip key never affects sharing.
shareFrame = CreateFrame("Frame");
shareFrame:RegisterEvent("QUEST_ACCEPTED");
shareFrame:RegisterEvent("PLAYER_LEAVING_WORLD");
shareFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
-- Always registered: the decline marks must be cleared even while nothing is being shared.
shareFrame:RegisterEvent("QUEST_TURNED_IN");
shareFrame:RegisterEvent("GROUP_LEFT");

shareFrame:SetScript("OnEvent", function(_, event, arg1)
    if (event == "QUEST_ACCEPTED") then
        OnShareAccepted(arg1);
        return;
    elseif (event == "PLAYER_LEAVING_WORLD") then
        shareLoading = true;
        return;
    elseif (event == "PLAYER_ENTERING_WORLD") then
        shareLoading = false;
        if (shareActive) then
            PumpShareQueue();
        end
        return;
    elseif (event == "GROUP_LEFT") then
        -- A new group never saw the earlier offers. Leaving an instance group while still in the
        -- home party keeps them.
        if (not IsInGroup()) then
            wipe(shareDeclined);
        end
        return;
    elseif (event == "QUEST_TURNED_IN") then
        -- A repeatable quest accepted again can be shared again.
        shareDeclined[arg1] = nil;
    end

    if (not shareActive) then
        return;
    end

    if (event == "CHAT_MSG_SYSTEM") then
        OnShareMessage(arg1);
    elseif (event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN") then
        local entry = FindShareEntry(arg1);
        if (entry) then
            RemoveShareEntry(entry);
            PumpShareQueue();
        end
    elseif (event == "GROUP_ROSTER_UPDATE") then
        RefreshShareRoster();
        for name in pairs(shareOpen) do
            if (not shareRoster[name]) then
                shareOpen[name] = nil;
            end
        end
        for name in pairs(shareExpected) do
            if (not shareRoster[name]) then
                shareExpected[name] = nil;
            end
        end
        for _, entry in ipairs(shareQueue) do
            for name in pairs(entry.members) do
                if (not shareRoster[name]) then
                    entry.members[name] = nil;
                end
            end
        end
        if (shareFlight and next(shareExpected) == nil) then
            EndShareFlight();
        end
        PumpShareQueue();
    elseif (event == "PLAYER_REGEN_ENABLED" or event == "ADDON_RESTRICTION_STATE_CHANGED") then
        PumpShareQueue();
    end
end)

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
    end

    if (event == "QUEST_DETAIL") then
        -- Set or cleared on every offer, so a share that was declined and then taken from an NPC can
        -- still be shared. Not cleared on QUEST_FINISHED, which can fire before QUEST_ACCEPTED.
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
