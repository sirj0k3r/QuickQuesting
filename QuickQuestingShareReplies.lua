local _, QQ = ...;

---------------------------------------------------------------------------
-- Share replies: patterns built from the game's strings, the party roster, name matching
---------------------------------------------------------------------------

local SHARE_INFLECT_BYTES = 4;

local SHARE_REPLY_KINDS = {
    { kind = "sent", suffixes = { "SUCCESS" } },
    { kind = "busy", suffixes = { "BUSY" } },
    { kind = "accepted", suffixes = { "ACCEPTED" } },
    { kind = "declined", suffixes = { "DECLINED" } },
    -- Can't take it right now; looked at again later.
    { kind = "unable", suffixes = { "DEAD", "LOG_FULL", "TOO_FAR" } },
    { kind = "final", suffixes = {
        "ALREADY_DONE", "CLASS", "DIFFERENT_SERVER_DAILY", "EXPANSION", "HIGH_FACTION",
        "HIGH_LEVEL", "INVALID", "LOW_FACTION", "LOW_LEVEL", "NEW_PLAYER_EXPERIENCE",
        "NOT_GARRISON_OWNER", "ONQUEST", "PREREQUISITE", "RACE", "WRONG_COVENANT",
        "WRONG_FACTION",
    } },
};

-- Replies that name no player, matched by exact text.
local SHARE_NAMELESS_KINDS = {
    { kind = "questBlocked", keys = { "ERR_QUEST_PUSH_NOT_ALLOWED_S", "ERR_QUEST_PUSH_NOT_DAILY_S" } },
    { kind = "groupBlocked", keys = { "ERR_QUEST_PUSH_NOT_IN_PARTY_S", "ERR_QUEST_PUSH_CROSS_FACTION_RESTRICTED_S" } },
};

local shareRoster = {};
local shareRosterBase = {};
local shareRosterUnit = {};
local sharePatterns = {};
local shareNameless = {};

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
    if (next(sharePatterns) ~= nil) then
        return;
    end

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
                    sharePatterns[#sharePatterns + 1] = { pattern = "^" .. pattern .. "$", kind = group.kind, suffix = suffix, fuzzy = fuzzy };
                end
            end
        end
    end

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
    wipe(shareRosterUnit);

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
                shareRosterUnit[key] = unit;
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

QQ.IsSecret = IsSecret;
QQ.StripGrammar = StripGrammar;
QQ.BuildSharePatterns = BuildSharePatterns;
QQ.RefreshShareRoster = RefreshShareRoster;
QQ.ResolveShareName = ResolveShareName;
QQ.shareRoster = shareRoster;
QQ.shareRosterUnit = shareRosterUnit;
QQ.sharePatterns = sharePatterns;
QQ.shareNameless = shareNameless;
