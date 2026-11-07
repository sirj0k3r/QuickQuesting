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
