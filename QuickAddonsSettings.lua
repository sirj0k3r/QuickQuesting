-- Shared by all Quick addons. This file must stay byte-identical in every addon.
-- Bump VERSION on any change; newer copies must keep the data fields
-- (version, members, parentCategory, landingFrame) compatible with older ones.
local VERSION = 1;
local PARENT_NAME = "Quick AddOns";

local QuickAddons = _G.QuickAddons;
if (type(QuickAddons) ~= "table") then
    QuickAddons = { version = 0, members = {} };
    _G.QuickAddons = QuickAddons;
end
if (QuickAddons.version >= VERSION) then
    return;
end
QuickAddons.version = VERSION;

---------------------------------------------------------------------------
-- Parent category
---------------------------------------------------------------------------

function QuickAddons:GetParentCategory()
    if (self.parentCategory == nil) then
        local frame = CreateFrame("Frame");
        frame.OnCommit = function() end;
        frame.OnDefault = function() end;
        frame.OnRefresh = function() end;
        frame:SetScript("OnShow", function(shownFrame)
            QuickAddons:RenderLanding(shownFrame);
        end);

        local category = Settings.RegisterCanvasLayoutCategory(frame, PARENT_NAME);
        category:SetShouldSortAlphabetically(true);
        Settings.RegisterAddOnCategory(category);

        self.landingFrame = frame;
        self.parentCategory = category;
    end
    return self.parentCategory;
end

function QuickAddons:RegisterVerticalSubcategory(shortName)
    return Settings.RegisterVerticalLayoutSubcategory(self:GetParentCategory(), shortName);
end

function QuickAddons:RegisterMember(addonName, shortName, description, category)
    self:GetParentCategory();
    self.members[addonName] = {
        addonName = addonName,
        shortName = shortName,
        title = C_AddOns.GetAddOnMetadata(addonName, "Title") or shortName,
        version = C_AddOns.GetAddOnMetadata(addonName, "Version"),
        description = description,
        category = category,
    };
    if (self.landingFrame:IsVisible()) then
        self:RenderLanding(self.landingFrame);
    end
end

---------------------------------------------------------------------------
-- Landing page
---------------------------------------------------------------------------

local function CreateRow(frame, index)
    local row = CreateFrame("Frame", nil, frame);
    row:SetHeight(48);
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -80 - (index - 1) * 56);
    row:SetPoint("RIGHT", frame, "RIGHT", -16, 0);

    row.title = row:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge");
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0);

    row.version = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall");
    row.version:SetPoint("LEFT", row.title, "RIGHT", 8, 0);

    row.openButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate");
    row.openButton:SetSize(100, 22);
    row.openButton:SetPoint("RIGHT", row, "RIGHT", 0, 0);
    row.openButton:SetText("Open");
    row.openButton:SetScript("OnClick", function(self)
        local member = self:GetParent().member;
        if (member and member.category) then
            Settings.OpenToCategory(member.category:GetID());
        end
    end);

    row.description = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
    row.description:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -6);
    row.description:SetPoint("RIGHT", row.openButton, "LEFT", -12, 0);
    row.description:SetJustifyH("LEFT");

    return row;
end

function QuickAddons:RenderLanding(frame)
    if (frame.quickAddonsRenderVersion ~= VERSION) then
        for _, widget in ipairs(frame.quickAddonsWidgets or {}) do
            widget:Hide();
        end
        frame.quickAddonsWidgets = {};

        local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge");
        title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16);
        title:SetText(PARENT_NAME);

        local subtitle = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
        subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8);
        subtitle:SetText("Installed Quick addons:");

        table.insert(frame.quickAddonsWidgets, title);
        table.insert(frame.quickAddonsWidgets, subtitle);
        frame.quickAddonsRows = {};
        frame.quickAddonsRenderVersion = VERSION;
    end

    local sorted = {};
    for _, member in pairs(self.members) do
        table.insert(sorted, member);
    end
    table.sort(sorted, function(a, b)
        return a.shortName:lower() < b.shortName:lower();
    end);

    local rows = frame.quickAddonsRows;
    for i, member in ipairs(sorted) do
        local row = rows[i];
        if (row == nil) then
            row = CreateRow(frame, i);
            rows[i] = row;
            table.insert(frame.quickAddonsWidgets, row);
        end
        row.member = member;
        row.title:SetText(member.title);
        row.version:SetText(member.version and ("v" .. member.version) or "");
        row.description:SetText(member.description or "");
        row.openButton:SetShown(member.category ~= nil);
        row:Show();
    end
    for i = #sorted + 1, #rows do
        rows[i]:Hide();
    end
end
