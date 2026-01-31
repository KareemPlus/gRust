util.AddNetworkString( "wis_giveitem" )

-- not used anywhere
local function ItemAutoComplete(cmd, argStr, args)
    if (#args > 1) then return {} end
    local searchItem = string.lower(args[1] or "")

    local items = {}
    for k, v in ipairs(gRust.GetItems()) do
        local itemId = string.lower(v)
        if (string.StartWith(itemId, searchItem)) then
            local completion = string.format("%s %s", cmd, v)
            table.insert(items, completion)
        end
    end

    table.sort(items, function(a, b)
        return string.len(a) < string.len(b)
    end)

    return items
end

local function give_item(ply, id, amount)
    local itemID = id
    local amount = tonumber(amount) or 1
    
    ply:AddItem(gRust.CreateItem(itemID, amount), ITEM_PICKUP)
    gRust.Log(string.format("%s gave themselves %s x%d", ply:Name(), itemID, amount))

end


net.Receive("wis_giveitem", function(len, ply)
    local rank = ply:GetNWString("ADM_Rank", "user")
    if rank ~= "Admin" and rank ~= "Owner" and rank ~= "superadmin" then
        ply:ChatMessage("You are not allowed to use this command.")
        return
    end

    local id = net.ReadString()
    local amount = net.ReadInt(16)

    give_item(ply, id, amount)
end)
