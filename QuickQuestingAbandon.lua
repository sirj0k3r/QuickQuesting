local OLD_ADDON_NAME = "QuickAbandon";

---------------------------------------------------------------------------
-- Abandon
---------------------------------------------------------------------------

local function AbandonQuest(questID)
    if (not QuickQuestingDB or not QuickQuestingDB.abandonEnabled) then
        return;
    end
    if (not questID or not QQ_IsModifierDown(QuickQuestingDB.abandonModifier)) then
        return;
    end
    if (not (C_QuestLog.CanAbandonQuest(questID) and C_QuestLog.IsOnQuest(questID))) then
        return;
    end

    C_QuestLog.SetSelectedQuest(questID);
    C_QuestLog.SetAbandonQuest();
    C_QuestLog.AbandonQuest();

    if (WorldMapFrame and WorldMapFrame:IsShown()) then
        WorldMapFrameCloseButton:Click();
    end

    SendSystemMessage("Quest abandoned: " .. GetQuestLink(questID));
end

local function InstallHooks()
    hooksecurefunc("QuestMapLogTitleButton_OnClick", function(self)
        AbandonQuest(self.questID);
    end);

    hooksecurefunc(CampaignQuestObjectiveTracker, "OnBlockHeaderClick", function(_, block)
        AbandonQuest(block.id);
    end);

    hooksecurefunc(QuestObjectiveTracker, "OnBlockHeaderClick", function(_, block)
        AbandonQuest(block.id);
    end);
end

---------------------------------------------------------------------------
-- Old Quick Abandon addon
---------------------------------------------------------------------------

-- Quick Abandon 1.1.0 and later is a stub that does nothing when Quick Questing
-- is loaded, so only older versions would double-hook.
local function IsOldAbandonHooking()
    local version = C_AddOns.GetAddOnMetadata(OLD_ADDON_NAME, "Version");
    local major, minor = tostring(version):match("^(%d+)%.(%d+)");
    major, minor = tonumber(major), tonumber(minor);
    if (major == nil or minor == nil) then
        return true;
    end
    return major < 1 or (major == 1 and minor < 1);
end

local frame = CreateFrame("Frame");
frame:RegisterEvent("PLAYER_LOGIN");
frame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN");

    -- All addons are loaded by now, so this works whichever loaded first.
    if (C_AddOns.IsAddOnLoaded(OLD_ADDON_NAME)) then
        print("Quick Questing: Quick Abandon is now built in; you can uninstall it.");
        if (IsOldAbandonHooking()) then
            return;
        end
    end

    InstallHooks();
end);
