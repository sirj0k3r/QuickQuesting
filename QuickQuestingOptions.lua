local ADDON_NAME = ...;

local PANEL_NAME = "Quick Questing";
local RADIO_SPACING = 22;
local LIST_HEIGHT = 130;
local ROW_HEIGHT = 24;

local category = nil;
local panel = nil;
local radioGroups = {};
local exceptionList = nil;
local emptyLabel = nil;

---------------------------------------------------------------------------
-- Radio groups
---------------------------------------------------------------------------

local function RefreshRadioGroup(group)
    local current = QuickQuestingDB[group.dbKey];
    for _, radio in ipairs(group.buttons) do
        radio:SetChecked(radio.optionKey == current);
    end
end

local function CreateRadioGroup(parent, dbKey, options, anchorY)
    local group = { dbKey = dbKey, buttons = {} };

    for i, option in ipairs(options) do
        local radio = CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate");
        radio:SetPoint("TOPLEFT", parent, "TOPLEFT", 28, anchorY - (i - 1) * RADIO_SPACING);
        radio.optionKey = option.key;
        radio.text:SetText(option.label);
        radio:SetHitRectInsets(0, -(radio.text:GetStringWidth() + 10), 0, 0);

        if (option.disabled) then
            radio:Disable();
            radio.text:SetTextColor(GRAY_FONT_COLOR:GetRGB());
        else
            radio.text:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB());
            radio:SetScript("OnClick", function(self)
                QuickQuestingDB[dbKey] = self.optionKey;
                RefreshRadioGroup(group);
            end);
        end

        group.buttons[#group.buttons + 1] = radio;
    end

    radioGroups[#radioGroups + 1] = group;
    return anchorY - #options * RADIO_SPACING;
end

local function CreateHeader(parent, text, y)
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge");
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y);
    header:SetText(text);
    return header;
end

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
    if (panel == nil) then
        return;
    end

    for _, group in ipairs(radioGroups) do
        RefreshRadioGroup(group);
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
-- Panel
---------------------------------------------------------------------------

local function CreatePanel()
    panel = CreateFrame("Frame");
    panel.name = PANEL_NAME;

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge");
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16);
    title:SetText(PANEL_NAME);

    local y = -52;
    CreateHeader(panel, "When a turn-in offers a reward choice", y);
    y = CreateRadioGroup(panel, "rewardMode", QQ_RewardOptions, y - 26);
    local note = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
    note:SetPoint("TOPLEFT", panel, "TOPLEFT", 28, y - 2);
    note:SetText("\"Nothing\" leaves the reward window open for you.");

    y = y - 30;
    CreateHeader(panel, "Which quests to handle", y);
    y = CreateRadioGroup(panel, "questScope", QQ_ScopeOptions, y - 26);

    y = y - 12;
    CreateHeader(panel, "Hold this key to skip automation", y);
    y = CreateRadioGroup(panel, "modifier", QQ_ModifierOptions, y - 26);

    y = y - 12;
    CreateHeader(panel, "Exceptions (never handled automatically)", y);
    y = y - 30;

    local editBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate");
    editBox:SetSize(180, 22);
    editBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 30, y);
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
    panel.OnDefault = function()
        QuickQuestingDB.rewardMode = QQ_DEFAULTS.rewardMode;
        QuickQuestingDB.questScope = QQ_DEFAULTS.questScope;
        QuickQuestingDB.modifier = QQ_DEFAULTS.modifier;
        QQ_RefreshOptions();
    end;

    category = Settings.RegisterCanvasLayoutCategory(panel, PANEL_NAME);
    Settings.RegisterAddOnCategory(category);
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
    CreatePanel();
    QQ_RefreshOptions();
end)

SLASH_QUICKQUESTING1 = "/quickquesting";
SLASH_QUICKQUESTING2 = "/qquest";
SlashCmdList["QUICKQUESTING"] = function()
    if (category ~= nil) then
        Settings.OpenToCategory(category:GetID());
    end
end
