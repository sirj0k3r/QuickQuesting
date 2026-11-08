local ADDON_NAME = ...;

local LIST_HEIGHT = 102;
local ROW_HEIGHT = 24;

local category = nil;
local exceptionsPanel = nil;
local exceptionList = nil;
local emptyLabel = nil;

---------------------------------------------------------------------------
-- Exceptions list
---------------------------------------------------------------------------

local function InitExceptionRow(row, data)
    if (row.label == nil) then
        row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
        row.label:SetPoint("LEFT", row, "LEFT", 8, 0);
        row.label:SetPoint("RIGHT", row, "RIGHT", -90, 0);
        row.label:SetJustifyH("LEFT");
        row.label:SetWordWrap(false);

        row.removeButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate");
        row.removeButton:SetSize(76, 20);
        row.removeButton:SetPoint("RIGHT", row, "RIGHT", -4, 0);
        row.removeButton:SetText("Remove");
        row.removeButton:SetScript("OnClick", function(self)
            QQ_RemoveException(self:GetParent().questID);
        end);
    end

    row.questID = data.questID;
    row.label:SetText(data.title .. " (" .. data.questID .. ")");
end

local function CompareExceptions(a, b)
    local titleA, titleB = a.title:lower(), b.title:lower();
    if (titleA ~= titleB) then
        return titleA < titleB;
    end
    return a.questID < b.questID;
end

function QQ_RefreshOptions()
    if (exceptionsPanel == nil) then
        return;
    end

    local dataProvider = CreateDataProvider();
    dataProvider:SetSortComparator(CompareExceptions, true);
    local count = 0;
    for questID in pairs(QuickQuestingDB.exceptions) do
        dataProvider:Insert({ questID = questID, title = QQ_GetExceptionTitle(questID) });
        count = count + 1;
    end
    dataProvider:Sort();
    exceptionList:SetDataProvider(dataProvider, ScrollBoxConstants.RetainScrollPosition);
    emptyLabel:SetShown(count == 0);
end

local function ParseQuestID(text)
    local questID = text:match("|Hquest:(%d+)") or text:match("^%s*(%d+)%s*$");
    return questID and tonumber(questID) or nil;
end

local function ShowQuestLogMenu(owner)
    MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
        rootDescription:SetScrollMode(320);
        rootDescription:CreateTitle("Add from quest log");

        local added = 0;
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i);
            if (info and not info.isHeader and not info.isHidden and not QQ_IsException(info.questID)) then
                local questID, title = info.questID, info.title;
                rootDescription:CreateButton(title, function()
                    QQ_AddException(questID, title);
                end);
                added = added + 1;
            end
        end

        if (added == 0) then
            rootDescription:CreateTitle("No quests to add");
        end
    end);
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local function AddCheckbox(category, key, label, tooltip)
    local setting = Settings.RegisterAddOnSetting(category, "QuickQuesting_" .. key, key, QuickQuestingDB, Settings.VarType.Boolean, label, QQ_DEFAULTS[key]);
    local initializer = Settings.CreateCheckbox(category, setting, tooltip);
    return setting, initializer;
end

local function AddDropdown(category, key, label, options, tooltip)
    local setting = Settings.RegisterAddOnSetting(category, "QuickQuesting_" .. key, key, QuickQuestingDB, Settings.VarType.String, label, QQ_DEFAULTS[key]);
    local function GetOptions()
        local container = Settings.CreateControlTextContainer();
        for _, option in ipairs(options) do
            if (not option.disabled) then
                container:Add(option.key, option.label);
            end
        end
        return container:GetData();
    end
    local initializer = Settings.CreateDropdown(category, setting, GetOptions, tooltip);
    return setting, initializer;
end

local function CreateExceptionsPanel()
    exceptionsPanel = CreateFrame("Frame");
    local panel = exceptionsPanel;

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge");
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16);
    title:SetText("Exceptions");

    local editBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate");
    editBox:SetSize(180, 22);
    editBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 30, -60);
    editBox:SetAutoFocus(false);
    editBox:SetMaxLetters(255);

    local function SubmitQuestID()
        local questID = ParseQuestID(editBox:GetText());
        if (questID and QQ_AddException(questID)) then
            editBox:SetText("");
            editBox:ClearFocus();
        end
    end
    editBox:SetScript("OnEnterPressed", SubmitQuestID);
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus();
    end);

    local addButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate");
    addButton:SetSize(60, 22);
    addButton:SetPoint("LEFT", editBox, "RIGHT", 8, 0);
    addButton:SetText("Add");
    addButton:SetScript("OnClick", SubmitQuestID);

    local logButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate");
    logButton:SetSize(150, 22);
    logButton:SetPoint("LEFT", addButton, "RIGHT", 12, 0);
    logButton:SetText("Add from quest log");
    logButton:SetScript("OnClick", function(self)
        ShowQuestLogMenu(self);
    end);

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
    hint:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", -6, -4);
    hint:SetText("Type a quest ID, or add one from your quest log.");

    local listBackground = panel:CreateTexture(nil, "BACKGROUND");
    listBackground:SetColorTexture(0, 0, 0, 0.3);

    exceptionList = CreateFrame("Frame", nil, panel, "WowScrollBoxList");
    exceptionList:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8);
    exceptionList:SetSize(500, LIST_HEIGHT);
    listBackground:SetAllPoints(exceptionList);

    local scrollBar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar");
    scrollBar:SetPoint("TOPLEFT", exceptionList, "TOPRIGHT", 6, 0);
    scrollBar:SetPoint("BOTTOMLEFT", exceptionList, "BOTTOMRIGHT", 6, 0);

    local view = CreateScrollBoxListLinearView();
    view:SetElementExtent(ROW_HEIGHT);
    view:SetElementInitializer("Button", InitExceptionRow);
    ScrollUtil.InitScrollBoxListWithScrollBar(exceptionList, scrollBar, view);

    emptyLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontDisable");
    emptyLabel:SetPoint("CENTER", exceptionList, "CENTER");
    emptyLabel:SetText("No exceptions");

    panel.OnRefresh = QQ_RefreshOptions;
    panel.OnCommit = function() end;
    panel.OnDefault = function() end;
    panel:SetScript("OnShow", QQ_RefreshOptions);

    return panel;
end

local function CreateSettings()
    local layout;
    category, layout = QuickAddons:RegisterVerticalSubcategory("Questing");

    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Automation"));
    AddDropdown(category, "rewardMode", "Reward Choice", QQ_RewardOptions, "Reward to pick when a quest offers a choice.");
    AddDropdown(category, "questScope", "Quests to Handle", QQ_ScopeOptions, nil);
    AddDropdown(category, "modifier", "Skip Key", QQ_ModifierOptions, "Hold this key to skip automation");

    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Sharing"));
    local autoShareSetting, autoShareInitializer = AddCheckbox(category, "autoShare", "Share quests with your party");
    local _, zoneOnlyInitializer = AddCheckbox(category, "shareZoneOnly", "Only share with players in your zone");
    zoneOnlyInitializer:SetParentInitializer(autoShareInitializer, function()
        return autoShareSetting:GetValue();
    end);
    local autoAcceptSetting = AddCheckbox(category, "autoAcceptShared", "Accept quests shared with you");
    autoShareSetting:SetValueChangedCallback(function(_, value)
        if (value) then
            autoAcceptSetting:SetValue(true);
        else
            QQ_ClearShareQueue();
        end
    end);

    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Abandon"));
    local abandonEnabledSetting, abandonEnabledInitializer = AddCheckbox(category, "abandonEnabled", "Abandon quests with a modifier click");
    local _, abandonKeyInitializer = AddDropdown(category, "abandonModifier", "Abandon Key", QQ_ModifierOptions, "Hold this key while clicking a quest");
    abandonKeyInitializer:SetParentInitializer(abandonEnabledInitializer, function()
        return abandonEnabledSetting:GetValue();
    end);

    Settings.RegisterCanvasLayoutSubcategory(category, CreateExceptionsPanel(), "Exceptions");

    QuickAddons:RegisterMember(ADDON_NAME, "Questing", "Automatically accepts and turns in quests.", category);
end

local loader = CreateFrame("Frame");
loader:RegisterEvent("ADDON_LOADED");
loader:SetScript("OnEvent", function(self, _, addonName)
    if (addonName ~= ADDON_NAME) then
        return;
    end
    self:UnregisterEvent("ADDON_LOADED");

    if (QuickQuestingDB == nil or QuickQuestingDB.exceptions == nil) then
        QQ_InitDB();
    end
    CreateSettings();
    QQ_RefreshOptions();
end)

SLASH_QUICKQUESTING1 = "/quickquesting";
SLASH_QUICKQUESTING2 = "/qquest";
SlashCmdList["QUICKQUESTING"] = function()
    if (category ~= nil) then
        Settings.OpenToCategory(category:GetID());
    end
end
