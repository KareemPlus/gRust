
local ALLOWED_STEAMID64 = {
    ["76561198135631170"] = true,
    ["76561199222590247"] = true, 
}


local function ItemAutoComplete(cmd, argStr, args)
    if (#args > 1) then return {} end
    local searchItem = string.lower(args[1] or "")

    local items = {}
    for _, v in ipairs(gRust.GetItems()) do
        if string.StartWith(string.lower(v), searchItem) then
            table.insert(items, cmd .. " " .. v)
        end
    end

    table.sort(items, function(a, b)
        return #a < #b
    end)

    return items
end


concommand.Add("grust_giveitem", function(pl, cmd, args)
    if not IsValid(pl) then return end

   
    if not ALLOWED_STEAMID64[pl:SteamID64()] then
        pl:ChatPrint("You are not allowed to use this command.")
        return
    end

    local itemID = args[1]
    local amount = tonumber(args[2]) or 1

    if not itemID then
        pl:ChatPrint("Usage: grust_giveitem <item> [amount]")
        return
    end

    pl:AddItem(gRust.CreateItem(itemID, amount), ITEM_PICKUP)

    gRust.Log(string.format(
        "%s gave themselves %s x%d",
        pl:Name(),
        itemID,
        amount
    ))
end, ItemAutoComplete, "Give yourself an item")
