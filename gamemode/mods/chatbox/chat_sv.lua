-- chatbox_sv.lua (Server-side with Anti-Spam)

util.AddNetworkString("gRust.SendChat")

-- ============================================
-- CONFIGURATION - Customize these values
-- ============================================
local Config = {
    -- Rate Limiting
    MinMessageDelay = 0.75,          -- Minimum seconds between messages
    MaxMessagesPerWindow = 5,        -- Max messages allowed in time window
    TimeWindow = 10,                 -- Time window in seconds

    -- Spam Detection
    MaxDuplicateMessages = 2,        -- Max identical messages before warning
    DuplicateResetTime = 30,         -- Seconds before duplicate count resets

    -- Punishments
    WarningsBeforeMute = 3,          -- Warnings before temporary mute
    MuteDuration = 60,               -- Mute duration in seconds
    WarningDecayTime = 120,          -- Seconds before warnings reset

    -- Message Limits
    MaxMessageLength = 126,          -- Maximum characters per message

    -- Caps Lock Detection
    MaxCapsPercentage = 0.7,         -- Max % of caps in message (0.7 = 70%)
    MinLengthForCapsCheck = 8,       -- Minimum message length to check caps
}

-- ============================================
-- RANK SYSTEM - Add SteamID64s here for custom ranks
-- ============================================

-- Default ranks based on usergroup (from ULX, FAdmin, etc.)
local UsergroupRanks = {
    ["superadmin"] = { name = "Owner", color = Color(255, 0, 0) },        -- Red for Owner
    ["admin"] = { name = "Admin", color = Color(255, 100, 100) },         -- Light Red for Admin
    ["moderator"] = { name = "Mod", color = Color(0, 150, 255) },         -- Blue for Moderator
    ["vip"] = { name = "VIP", color = Color(255, 215, 0) },               -- Gold for VIP
}

-- Custom ranks by SteamID64 - Add your staff members here!
-- These override usergroup ranks
local SteamIDRanks = {
    -- OWNERS (Red)
    ["76561199222590247"] = { name = "Owner", color = Color(255, 0, 0) },
    ["76561198135631170"] = { name = "superadmin sugar daddy", color = Color(255, 0, 0) },

    -- ADMINS (Light Red)
    ["76561198000000003"] = { name = "Admin", color = Color(255, 100, 100) },
    ["76561198000000004"] = { name = "Admin", color = Color(255, 100, 100) },

    -- MODERATORS (Blue)
    ["0"] = { name = "Mod", color = Color(0, 150, 255) },
    ["76561198000000006"] = { name = "Mod", color = Color(0, 150, 255) },

    -- VIP (Gold)
    ["76561198000000007"] = { name = "VIP", color = Color(255, 215, 0) },
}

-- Helper function to add ranks via console (persists until server restart)
-- Usage in server console: lua_run AddChatRank("76561198xxxxxxxxx", "Admin", 255, 100, 100)
function AddChatRank(steamid64, rankName, r, g, b)
    SteamIDRanks[steamid64] = { name = rankName, color = Color(r, g, b) }
    print("[gRust Chat] Added rank '" .. rankName .. "' for SteamID: " .. steamid64)
end

function RemoveChatRank(steamid64)
    SteamIDRanks[steamid64] = nil
    print("[gRust Chat] Removed rank for SteamID: " .. steamid64)
end

-- ============================================
-- PLAYER DATA STORAGE
-- ============================================
local PlayerChatData = {}

local function GetPlayerData(ply)
    local sid = ply:SteamID64()
    if not PlayerChatData[sid] then
        PlayerChatData[sid] = {
            lastMessageTime = 0,
            messageHistory = {},       -- Recent messages with timestamps
            lastMessage = "",
            duplicateCount = 0,
            lastDuplicateTime = 0,
            warnings = 0,
            lastWarningTime = 0,
            mutedUntil = 0,
        }
    end
    return PlayerChatData[sid]
end

-- Clean up on disconnect
hook.Add("PlayerDisconnected", "gRust.ChatCleanup", function(ply)
    PlayerChatData[ply:SteamID64()] = nil
end)

-- ============================================
-- ANTI-SPAM FUNCTIONS
-- ============================================

-- Check if player is muted
local function IsMuted(ply)
    local data = GetPlayerData(ply)
    if data.mutedUntil > CurTime() then
        return true, math.ceil(data.mutedUntil - CurTime())
    end
    return false, 0
end

-- Mute a player
local function MutePlayer(ply, duration)
    local data = GetPlayerData(ply)
    data.mutedUntil = CurTime() + duration
    data.warnings = 0
end

-- Add a warning
local function AddWarning(ply, reason)
    local data = GetPlayerData(ply)

    -- Decay old warnings
    if CurTime() - data.lastWarningTime > Config.WarningDecayTime then
        data.warnings = 0
    end

    data.warnings = data.warnings + 1
    data.lastWarningTime = CurTime()

    if data.warnings >= Config.WarningsBeforeMute then
        MutePlayer(ply, Config.MuteDuration)
        ply:ChatPrint("[CHAT] You have been muted for " .. Config.MuteDuration .. " seconds (spam)")
        return false
    else
        local remaining = Config.WarningsBeforeMute - data.warnings
        ply:ChatPrint("[CHAT] Warning: " .. reason .. " (" .. remaining .. " warnings left)")
        return true
    end
end

-- Check message rate
local function CheckRateLimit(ply)
    local data = GetPlayerData(ply)
    local now = CurTime()

    -- Check minimum delay between messages
    if now - data.lastMessageTime < Config.MinMessageDelay then
        return false, "Sending messages too fast"
    end

    -- Clean old messages from history
    local recentMessages = {}
    for _, msgData in ipairs(data.messageHistory) do
        if now - msgData.time < Config.TimeWindow then
            table.insert(recentMessages, msgData)
        end
    end
    data.messageHistory = recentMessages

    -- Check flood limit
    if #data.messageHistory >= Config.MaxMessagesPerWindow then
        return false, "Too many messages, slow down"
    end

    return true
end

-- Check for duplicate messages
local function CheckDuplicate(ply, message)
    local data = GetPlayerData(ply)
    local now = CurTime()

    -- Reset duplicate count if enough time passed
    if now - data.lastDuplicateTime > Config.DuplicateResetTime then
        data.duplicateCount = 0
        data.lastMessage = ""
    end

    -- Check if message is duplicate
    if string.lower(message) == string.lower(data.lastMessage) then
        data.duplicateCount = data.duplicateCount + 1
        data.lastDuplicateTime = now

        if data.duplicateCount >= Config.MaxDuplicateMessages then
            return false, "Stop sending duplicate messages"
        end
    else
        data.duplicateCount = 0
    end

    data.lastMessage = message
    return true
end

-- Check for excessive caps
local function CheckCapsLock(message)
    if #message < Config.MinLengthForCapsCheck then
        return true
    end

    local letters = string.gsub(message, "[^%a]", "")
    if #letters == 0 then return true end

    local caps = string.gsub(letters, "[^A-Z]", "")
    local capsRatio = #caps / #letters

    return capsRatio <= Config.MaxCapsPercentage
end

-- Sanitize message
local function SanitizeMessage(message)
    -- Trim whitespace
    message = string.Trim(message)

    -- Limit length
    message = string.sub(message, 1, Config.MaxMessageLength)

    -- Remove excessive spaces
    message = string.gsub(message, "%s+", " ")

    return message
end

-- ============================================
-- GET PLAYER RANK (checks SteamID first, then usergroup)
-- ============================================
local function GetPlayerRank(ply)
    local steamid64 = ply:SteamID64()

    -- First check SteamID-based ranks (highest priority)
    if SteamIDRanks[steamid64] then
        return SteamIDRanks[steamid64]
    end

    -- Then check usergroup-based ranks
    local usergroup = ply:GetUserGroup()
    if UsergroupRanks[usergroup] then
        return UsergroupRanks[usergroup]
    end

    return nil
end

-- Check if player is staff (for permissions)
local function IsStaff(ply)
    if not IsValid(ply) then return true end -- Console is always staff

    local steamid64 = ply:SteamID64()

    -- Check SteamID ranks
    if SteamIDRanks[steamid64] then
        local rankName = string.lower(SteamIDRanks[steamid64].name)
        if rankName == "owner" or rankName == "admin" or rankName == "mod" then
            return true
        end
    end

    -- Check usergroup
    local usergroup = ply:GetUserGroup()
    if usergroup == "superadmin" or usergroup == "admin" or usergroup == "moderator" then
        return true
    end

    return ply:IsAdmin()
end

-- ============================================
-- MAIN CHAT HANDLER
-- ============================================
net.Receive("gRust.SendChat", function(len, ply)
    if not IsValid(ply) then return end

    local message = net.ReadString()
    local teamchat = net.ReadBool()

    -- Basic validation
    if not message then return end
    message = SanitizeMessage(message)
    if message == "" then return end

    -- Check if muted
    local muted, remaining = IsMuted(ply)
    if muted then
        ply:ChatPrint("[CHAT] You are muted for " .. remaining .. " more seconds")
        return
    end

    -- Rate limit check
    local rateOk, rateReason = CheckRateLimit(ply)
    if not rateOk then
        if not AddWarning(ply, rateReason) then return end
        return -- Still block this message
    end

    -- Duplicate check
    local dupOk, dupReason = CheckDuplicate(ply, message)
    if not dupOk then
        if not AddWarning(ply, dupReason) then return end
        return
    end

    -- Caps lock check
    if not CheckCapsLock(message) then
        ply:ChatPrint("[CHAT] Please don't use excessive caps")
        -- Convert to lowercase instead of blocking
        message = string.lower(message)
    end

    -- Update player data
    local data = GetPlayerData(ply)
    data.lastMessageTime = CurTime()
    table.insert(data.messageHistory, { time = CurTime(), msg = message })

    -- Run hook for other addons
    local hookResult = hook.Run("PlayerSay", ply, message, teamchat)
    if hookResult == "" then return end
    if type(hookResult) == "string" then message = hookResult end

    -- Get rank info
    local rankInfo = GetPlayerRank(ply)

    -- Determine recipients
    local recipients = {}
    if teamchat then
        -- Use the new team system - check TeamID
        local plyTeamID = ply.TeamID
        if plyTeamID then
            for _, v in player.Iterator() do
                if v.TeamID == plyTeamID then
                    table.insert(recipients, v)
                end
            end
        else
            -- No team, just send to self
            table.insert(recipients, ply)
        end
    else
        recipients = player.GetAll()
    end

    -- Broadcast message
    net.Start("gRust.SendChat")
        net.WritePlayer(ply)
        net.WriteString(message)
        net.WriteBool(teamchat)

        if rankInfo then
            net.WriteBool(true)
            net.WriteString(rankInfo.name)
            net.WriteColor(rankInfo.color)
        else
            net.WriteBool(false)
        end
    net.Send(recipients)
end)

-- ============================================
-- ADMIN COMMANDS
-- ============================================

-- Unmute command
concommand.Add("chat_unmute", function(ply, cmd, args)
    if not IsStaff(ply) then
        if IsValid(ply) then
            ply:ChatPrint("[CHAT] You don't have permission to use this command")
        end
        return
    end

    local target = args[1]
    if not target then
        if IsValid(ply) then
            ply:ChatPrint("Usage: chat_unmute <name or steamid64>")
        else
            print("Usage: chat_unmute <name or steamid64>")
        end
        return
    end

    for _, p in player.Iterator() do
        if string.find(string.lower(p:Name()), string.lower(target)) or p:SteamID64() == target then
            local data = GetPlayerData(p)
            data.mutedUntil = 0
            data.warnings = 0
            p:ChatPrint("[CHAT] You have been unmuted")
            if IsValid(ply) then
                ply:ChatPrint("[CHAT] Unmuted " .. p:Name())
            else
                print("[CHAT] Unmuted " .. p:Name())
            end
            return
        end
    end

    if IsValid(ply) then
        ply:ChatPrint("[CHAT] Player not found")
    else
        print("[CHAT] Player not found")
    end
end)

-- Mute command
concommand.Add("chat_mute", function(ply, cmd, args)
    if not IsStaff(ply) then
        if IsValid(ply) then
            ply:ChatPrint("[CHAT] You don't have permission to use this command")
        end
        return
    end

    local target = args[1]
    local duration = tonumber(args[2]) or 300

    if not target then
        if IsValid(ply) then
            ply:ChatPrint("Usage: chat_mute <name or steamid64> [duration in seconds]")
        else
            print("Usage: chat_mute <name or steamid64> [duration in seconds]")
        end
        return
    end

    for _, p in player.Iterator() do
        if string.find(string.lower(p:Name()), string.lower(target)) or p:SteamID64() == target then
            MutePlayer(p, duration)
            p:ChatPrint("[CHAT] You have been muted for " .. duration .. " seconds")
            if IsValid(ply) then
                ply:ChatPrint("[CHAT] Muted " .. p:Name() .. " for " .. duration .. " seconds")
            else
                print("[CHAT] Muted " .. p:Name() .. " for " .. duration .. " seconds")
            end
            return
        end
    end

    if IsValid(ply) then
        ply:ChatPrint("[CHAT] Player not found")
    else
        print("[CHAT] Player not found")
    end
end)

-- Add rank command (console only or superadmin)
concommand.Add("chat_addrank", function(ply, cmd, args)
    if IsValid(ply) and ply:GetUserGroup() ~= "superadmin" then
        ply:ChatPrint("[CHAT] Only superadmins can add ranks")
        return
    end

    if #args < 5 then
        local msg = "Usage: chat_addrank <steamid64> <rankname> <r> <g> <b>"
        if IsValid(ply) then
            ply:ChatPrint(msg)
        else
            print(msg)
        end
        return
    end

    local steamid64 = args[1]
    local rankName = args[2]
    local r = tonumber(args[3]) or 255
    local g = tonumber(args[4]) or 255
    local b = tonumber(args[5]) or 255

    AddChatRank(steamid64, rankName, r, g, b)

    local msg = "[CHAT] Added rank '" .. rankName .. "' for " .. steamid64
    if IsValid(ply) then
        ply:ChatPrint(msg)
    else
        print(msg)
    end
end)

-- Remove rank command
concommand.Add("chat_removerank", function(ply, cmd, args)
    if IsValid(ply) and ply:GetUserGroup() ~= "superadmin" then
        ply:ChatPrint("[CHAT] Only superadmins can remove ranks")
        return
    end

    if #args < 1 then
        local msg = "Usage: chat_removerank <steamid64>"
        if IsValid(ply) then
            ply:ChatPrint(msg)
        else
            print(msg)
        end
        return
    end

    RemoveChatRank(args[1])

    local msg = "[CHAT] Removed rank for " .. args[1]
    if IsValid(ply) then
        ply:ChatPrint(msg)
    else
        print(msg)
    end
end)

-- List all custom ranks
concommand.Add("chat_listranks", function(ply, cmd, args)
    if not IsStaff(ply) then
        if IsValid(ply) then
            ply:ChatPrint("[CHAT] You don't have permission to use this command")
        end
        return
    end

    local function output(msg)
        if IsValid(ply) then
            ply:ChatPrint(msg)
        else
            print(msg)
        end
    end

    output("=== Custom SteamID Ranks ===")
    for steamid, rank in pairs(SteamIDRanks) do
        output(steamid .. " - " .. rank.name .. " (R:" .. rank.color.r .. " G:" .. rank.color.g .. " B:" .. rank.color.b .. ")")
    end
    output("=== Usergroup Ranks ===")
    for usergroup, rank in pairs(UsergroupRanks) do
        output(usergroup .. " - " .. rank.name .. " (R:" .. rank.color.r .. " G:" .. rank.color.g .. " B:" .. rank.color.b .. ")")
    end
end)

-- ============================================
-- INITIALIZATION
-- ============================================
if SERVER then
    AddCSLuaFile("chatbox_cl.lua")
end

print("[gRust Chat] Loaded with " .. table.Count(SteamIDRanks) .. " custom ranks")
