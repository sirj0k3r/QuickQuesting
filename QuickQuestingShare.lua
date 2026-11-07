local _, QQ = ...;

local IsSecret = QQ.IsSecret;
local StripGrammar = QQ.StripGrammar;
local BuildSharePatterns = QQ.BuildSharePatterns;
local RefreshShareRoster = QQ.RefreshShareRoster;
local ResolveShareName = QQ.ResolveShareName;
local shareRoster = QQ.shareRoster;
local sharePatterns = QQ.sharePatterns;
local shareNameless = QQ.shareNameless;

---------------------------------------------------------------------------
-- Auto share
---------------------------------------------------------------------------

-- A later quest is pushed while a member still has an earlier popup open: the server answers
-- "busy" and leaves that popup alone.
local SHARE_ACK_SECONDS = 3;
local SHARE_REPLY_SECONDS = 60;
local SHARE_LATE_SECONDS = 300;
local SHARE_MAX_PUSHES = 5;

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

local shareFrame = nil;
local shareQueue = {};
local shareOpen = {};
local shareEntry = nil;
local shareFlight = false;
local shareFlightDeadline = nil;
local shareExpected = {};
local shareLoading = false;
local shareTimer = nil;
local shareActive = false;
-- Quests someone declined. A push can't exclude a player, so these are not pushed again while we
-- stay in this group, even if that means a slower member misses them. Cleared when the group ends,
-- and per quest when it is turned in.
local shareDeclined = {};
-- Quests last offered by another player. Accepting one doesn't push it again: the party already got
-- that offer, and a second push would prompt anyone who declined it again.
local shareFromPlayer = {};
QQ.shareFromPlayer = shareFromPlayer;

local OnShareTimer;
local PumpShareQueue;

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
