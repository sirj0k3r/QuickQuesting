local _, QQ = ...;

local IsSecret = QQ.IsSecret;
local StripGrammar = QQ.StripGrammar;
local BuildSharePatterns = QQ.BuildSharePatterns;
local RefreshShareRoster = QQ.RefreshShareRoster;
local ResolveShareName = QQ.ResolveShareName;
local shareRoster = QQ.shareRoster;
local shareRosterUnit = QQ.shareRosterUnit;
local sharePatterns = QQ.sharePatterns;
local shareNameless = QQ.shareNameless;

---------------------------------------------------------------------------
-- Auto share
---------------------------------------------------------------------------

-- A later quest is pushed while a member still has an earlier popup open: the server answers
-- "busy" and leaves that popup alone.
local SHARE_ACK_SECONDS = 3;
local SHARE_REPLY_SECONDS = 60;
-- How long after a popup times out its answer still counts.
local SHARE_LATE_SECONDS = 300;
-- A player who let the popup time out gets one more share this long after, to give them time to
-- come back. An answer before then settles it. Must stay under SHARE_LATE_SECONDS.
local SHARE_SILENT_RETRY_SECONDS = 180;
-- How often a player who couldn't take the quest (too far, dead, log full) is looked at again.
local SHARE_UNABLE_RETRY_SECONDS = 30;
local SHARE_MAX_PUSHES = 5;
-- An accept arrives a server round trip after the quest window closes, in either order.
local SHARE_FROM_PLAYER_SECONDS = 10;

local SHARE_OPEN = 1;
local SHARE_BUSY = 2;
local SHARE_DONE = 3;
local SHARE_RETRY = 4; -- timed out once, one more share due at retryAt
local SHARE_UNABLE = 5; -- too far, dead or log full; shared again once they look able
local SHARE_AWAY = 6; -- out of your zone when last looked at: not waited on, asked again only by a share going out anyway

-- The replies only need listening to while something is being shared.
local SHARE_ACTIVE_EVENTS = {
    "CHAT_MSG_SYSTEM",
    "QUEST_REMOVED",
    "QUEST_TURNED_IN",
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
local shareZones = {};
local shareLoading = false;
local shareTimer = nil;
local shareActive = false;
-- Quests last offered by another player. Accepting one doesn't push it again: the party already got
-- that offer, and a second push would prompt anyone who declined it again. true while that offer is
-- the one shown; the time it stopped being shown afterwards; "join" for a quest another player
-- started (escort prompt), which is never shared whenever it is accepted.
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
    -- A retry already due waits for the next pump (end of combat, a reply...), not for the timer,
    -- so it is skipped here. The timer itself handles unable deadlines, even late ones.
    local now = GetTime();
    for _, entry in ipairs(shareQueue) do
        for name, state in pairs(entry.members) do
            local at = nil;
            if (state == SHARE_RETRY) then
                if (entry.retryAt[name] > now) then
                    at = entry.retryAt[name];
                end
            elseif (state == SHARE_UNABLE) then
                local unable = entry.unable[name];
                at = unable.due and unable.giveUpAt or math.min(unable.nextAt, unable.giveUpAt);
            end
            if (at and (earliest == nil or at < earliest)) then
                earliest = at;
            end
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
        if (entry.pushes > 0 and not (shareFlight and entry == shareEntry)) then
            if (entry.pushes >= SHARE_MAX_PUSHES) then
                for name, state in pairs(entry.members) do
                    if (state == SHARE_BUSY or state == SHARE_RETRY or state == SHARE_UNABLE) then
                        entry.members[name] = SHARE_DONE;
                    end
                end
            end
            local waiting = false;
            for _, state in pairs(entry.members) do
                if (state ~= SHARE_DONE and state ~= SHARE_AWAY) then
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

local function IsShareWanted(entry, zones)
    if (entry.pushes >= SHARE_MAX_PUSHES) then
        return false;
    end
    local now = GetTime();
    for name in pairs(shareRoster) do
        local open = shareOpen[name];
        local state = entry.members[name];
        -- Out-of-zone members never make a quest wanted.
        if (zones == nil or zones[name]) then
            if (entry.pushes == 0) then
                -- A member whose popup timed out does not hold back a new quest.
                if (state == nil and (open == nil or open.expired)) then
                    return true;
                end
            elseif (state == SHARE_BUSY and open == nil) then
                return true;
            elseif (state == SHARE_RETRY and now >= entry.retryAt[name]) then
                return true;
            elseif (state == SHARE_UNABLE and entry.unable[name].due and open == nil) then
                return true;
            end
        end
    end
    return false;
end

-- Whether a player who couldn't take the quest looks able to now. A full log can't be seen.
local function LooksAbleNow(name, reason)
    local unit = shareRosterUnit[name];
    if (unit == nil) then
        return false;
    end
    if (reason == "DEAD") then
        local dead = UnitIsDeadOrGhost(unit);
        return IsSecret(dead) or not dead;
    elseif (reason == "TOO_FAR") then
        local inRange, checked = UnitInRange(unit);
        if (IsSecret(inRange) or IsSecret(checked)) then
            return true;
        end
        return inRange or not checked;
    end
    return true;
end

-- The zone a unit is in, so caves, sub-zones and dungeon floors count as their zone. A map with
-- no zone above it (some instances, orphan maps) stands for itself or for its group of floors.
-- nil when the map can't be read.
local function GetZoneKey(unit)
    local mapID = C_Map.GetBestMapForUnit(unit);
    if (mapID == nil or IsSecret(mapID)) then
        return nil;
    end
    local key = nil;
    local info = C_Map.GetMapInfo(mapID);
    -- Bounded in case of a parent loop.
    for _ = 1, 20 do
        if (info == nil) then
            break;
        end
        local mapType = info.mapType;
        if (mapType == Enum.UIMapType.Zone) then
            return info.mapID;
        elseif (mapType == Enum.UIMapType.Continent or mapType == Enum.UIMapType.World or mapType == Enum.UIMapType.Cosmic) then
            break;
        end
        key = info.mapID;
        if (not info.parentMapID or info.parentMapID == 0) then
            break;
        end
        info = C_Map.GetMapInfo(info.parentMapID);
    end
    if (key) then
        local group = C_Map.GetMapGroupID(key);
        if (group and group ~= 0) then
            return "group" .. group;
        end
    end
    return key;
end

-- Whether each member is in your zone, or nil when sharing isn't limited by zone: the option is
-- off or your own zone is unknown. In an instance or a raid, where members' maps may not be
-- readable, a party whose maps all can't be read isn't limited either. Otherwise a member whose
-- zone is unknown counts as out of it.
local function GetShareZones()
    if (not (QuickQuestingDB and QuickQuestingDB.shareZoneOnly)) then
        return nil;
    end
    local own = GetZoneKey("player");
    if (own == nil) then
        return nil;
    end
    wipe(shareZones);
    local known = false;
    for name in pairs(shareRoster) do
        local unit = shareRosterUnit[name];
        local key = unit and GetZoneKey(unit);
        if (key ~= nil) then
            known = true;
        end
        shareZones[name] = (key ~= nil and key == own);
    end
    if (not known and (IsInInstance() or IsInRaid())) then
        return nil;
    end
    return shareZones;
end

local function HasZoneMember(zones)
    for _, inZone in pairs(zones) do
        if (inZone) then
            return true;
        end
    end
    return false;
end

-- A member who left your zone is no longer waited on. A popup they still have open keeps being
-- tracked, and its answer is read as usual.
local function SweepShareZones(zones)
    for _, entry in ipairs(shareQueue) do
        if (entry.pushes > 0) then
            for name, state in pairs(entry.members) do
                if (not zones[name] and (state == SHARE_BUSY or state == SHARE_RETRY or state == SHARE_UNABLE)) then
                    entry.members[name] = SHARE_AWAY;
                end
            end
        end
    end
end

PumpShareQueue = function()
    local zones = GetShareZones();
    if (zones) then
        SweepShareZones(zones);
    end
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
        -- Nobody else is in your zone: quests not shared yet are dropped rather than kept waiting.
        if (zones and not HasZoneMember(zones)) then
            for i = #shareQueue, 1, -1 do
                if (shareQueue[i].pushes == 0) then
                    table.remove(shareQueue, i);
                end
            end
            if (StopShareIfIdle()) then
                return;
            end
        end
        local i = 1;
        while (shareQueue[i]) do
            local entry = shareQueue[i];
            if (IsShareWanted(entry, zones)) then
                -- The log index is passed so the quest selected in the log is never touched.
                local index = C_QuestLog.GetLogIndexForQuestID(entry.questID);
                if (index and C_QuestLog.IsPushableQuest(entry.questID) and pcall(QuestLogPushQuest, index)) then
                    entry.pushes = entry.pushes + 1;
                    -- Back in your zone, or no longer limited by zone: this share asks them afresh.
                    for name in pairs(shareRoster) do
                        if (entry.members[name] == SHARE_AWAY and (zones == nil or zones[name])) then
                            entry.members[name] = nil;
                            entry.retried[name] = nil;
                            entry.retryAt[name] = nil;
                            entry.unable[name] = nil;
                        end
                    end
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
        if (shareEntry.members[name] == SHARE_RETRY) then
            -- Their one retry went unanswered.
            shareEntry.members[name] = SHARE_DONE;
        elseif (shareRoster[name] and shareOpen[name] == nil and shareEntry.members[name] ~= SHARE_DONE) then
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
                -- No answer will be read for them any more, so nothing of theirs waits on one.
                shareOpen[name] = nil;
                for _, entry in ipairs(shareQueue) do
                    local state = entry.members[name];
                    if (state == SHARE_BUSY or state == SHARE_RETRY or state == SHARE_OPEN) then
                        entry.members[name] = SHARE_DONE;
                    end
                end
            end
        elseif (now >= open.deadline) then
            open.expired = true;
            open.forgetAt = now + SHARE_LATE_SECONDS;
            local entry = open.entry;
            if (entry.members[name] == SHARE_OPEN) then
                if (entry.retried[name]) then
                    entry.members[name] = SHARE_DONE;
                else
                    entry.retried[name] = true;
                    entry.retryAt[name] = now + SHARE_SILENT_RETRY_SECONDS;
                    entry.members[name] = SHARE_RETRY;
                end
            end
        end
    end

    for _, entry in ipairs(shareQueue) do
        for name, state in pairs(entry.members) do
            if (state == SHARE_UNABLE) then
                local unable = entry.unable[name];
                if (now >= unable.giveUpAt) then
                    entry.members[name] = SHARE_DONE;
                elseif (not unable.due and now >= unable.nextAt) then
                    if (LooksAbleNow(name, unable.reason)) then
                        unable.due = true;
                    else
                        unable.nextAt = now + SHARE_UNABLE_RETRY_SECONDS;
                    end
                end
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
        -- Their popup for this very quest is still up: that was their retry, the answer still counts.
        if (entry.members[name] == SHARE_RETRY) then
            entry.members[name] = SHARE_OPEN;
        end
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

local function OnShareUnable(name, reason)
    local entry = shareEntry;
    if (entry.members[name] == SHARE_DONE) then
        return;
    end
    local now = GetTime();
    local unable = entry.unable[name];
    if (unable == nil or entry.members[name] ~= SHARE_UNABLE) then
        unable = { giveUpAt = now + SHARE_LATE_SECONDS };
        entry.unable[name] = unable;
    end
    unable.reason = reason;
    unable.nextAt = now + SHARE_UNABLE_RETRY_SECONDS;
    unable.due = false;
    entry.members[name] = SHARE_UNABLE;
end

-- Answers name a player and not a quest, so they belong to whichever popup that member has open.
-- Accepting and declining are both final for that player only.
local function OnShareAnswer(name)
    local open = shareOpen[name];
    if (open == nil) then
        return;
    end
    open.entry.members[name] = SHARE_DONE;
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
                OnShareAnswer(name);
            else
                if (shareEntry == nil) then
                    return;
                end
                if (p.kind == "sent") then
                    OnShareSent(name);
                elseif (p.kind == "busy") then
                    OnShareBusy(name);
                elseif (p.kind == "unable") then
                    OnShareUnable(name, p.suffix);
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
    if (fromPlayer == true or fromPlayer == "join"
        or (type(fromPlayer) == "number" and GetTime() - fromPlayer < SHARE_FROM_PLAYER_SECONDS)) then
        return;
    end
    if (not (QuickQuestingDB and QuickQuestingDB.autoShare)) then
        return;
    end
    if (not IsInGroup()) then
        return;
    end
    if (FindShareEntry(questID)) then
        return;
    end
    if (not (C_QuestLog.GetLogIndexForQuestID(questID) and C_QuestLog.IsPushableQuest(questID))) then
        return;
    end

    StartShareEvents();
    shareQueue[#shareQueue + 1] = { questID = questID, pushes = 0, members = {}, retried = {}, retryAt = {}, unable = {} };
    PumpShareQueue();
end

-- A separate frame so the skip key never affects sharing.
shareFrame = CreateFrame("Frame");
shareFrame:RegisterEvent("QUEST_ACCEPTED");
shareFrame:RegisterEvent("PLAYER_LEAVING_WORLD");
shareFrame:RegisterEvent("PLAYER_ENTERING_WORLD");

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
