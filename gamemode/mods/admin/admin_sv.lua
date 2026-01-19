

if not SERVER then return end

-- =========================
-- CONFIGURATION 
-- =========================
local CONFIG = {

    API_URL = "",

    
    API_KEY = "",

 
    IMGUR_CLIENT_ID = "YOUR_IMGUR_CLIENT_ID",

    -- Multi-Server Sync Settings
    SERVER_ID = "Kareem Servers",  -- Unique ID for this server (change for each server!)
    SERVER_NAME = "Kareem Servers",  -- Display name for Discord notifications

    -- How often to check for pending screengrabs (seconds)
    SCREENGRAB_CHECK_INTERVAL = 5,

    -- How often to send heartbeat to API (seconds)
    HEARTBEAT_INTERVAL = 30,

    -- How often to sync data with API (seconds)
    SYNC_INTERVAL = 60,
}

-- =========================
-- LOCAL STORAGE
-- =========================
local AdminCache = {} -- Cached admin data from API
local ReturnPositions = {} -- Saved positions for /return command
local AdminMode = {} -- Full admin mode status
local SessionTimes = {} -- Track session times

-- =========================
-- NETWORK STRINGS
-- =========================
util.AddNetworkString("ADM_ToggleESP")
util.AddNetworkString("ADM_ToggleDebugCamera")
util.AddNetworkString("ADM_DebugCameraPos")
util.AddNetworkString("ADM_InspectResult")
util.AddNetworkString("ADM_Notify")
util.AddNetworkString("ADM_Screengrab")
util.AddNetworkString("ADM_ScreengrabResult")

-- =========================
-- HTTP HELPER
-- =========================
local function APIRequest(endpoint, method, data, callback)
    local url = CONFIG.API_URL .. endpoint
    local headers = {
        ["Content-Type"] = "application/json",
        ["X-API-Key"] = CONFIG.API_KEY
    }

    local body = data and util.TableToJSON(data) or nil

    -- Use HTTP function for all requests (GET, POST, etc)
    HTTP({
        url = url,
        method = method or "GET",
        headers = headers,
        body = body,
        success = function(code, responseBody, responseHeaders)
            if code >= 200 and code < 300 then
                -- Success response
                if callback then
                    local success, result = pcall(util.JSONToTable, responseBody)
                    if success then
                        callback(result, code)
                    else
                        print("[ADMIN] JSON Parse Error on " .. method .. " " .. endpoint .. ": " .. tostring(result))
                        callback(nil, code)
                    end
                end
            else
                -- Error response
                print("[ADMIN] HTTP Error on " .. method .. " " .. endpoint .. " (Code: " .. code .. "): " .. tostring(responseBody))
                if callback then callback(nil, code) end
            end
        end,
        failed = function(err)
            print("[ADMIN] HTTP Connection Error on " .. method .. " " .. endpoint .. ": " .. tostring(err))
            if callback then callback(nil, 0) end
        end
    })
end

-- =========================
-- BAN SYSTEM HELPER FUNCTIONS
-- =========================
local function GetBanFilePath()
    -- Support multiple servers with per-server ban files
    local serverID = CONFIG.SERVER_ID or "server_1"
    return "banned_users_" .. serverID .. ".json"
end

local function LoadBannedUsersFromFile()
    -- Try to read from banned_users.json file
    local filePath = GetBanFilePath()
    local file = file.Open(filePath, "r", "DATA")
    if file then
        local content = file:Read(file:Size())
        file:Close()
        
        local success, data = pcall(util.JSONToTable, content)
        if success and data and data.banned_users then
            return data.banned_users
        end
    end
    return {}
end

local function SteamID64ToSteamID(steamid64)
    -- Convert SteamID64 to SteamID format (STEAM_0:X:XXXXX)
    local base = 76561197960265728
    local id64 = tonumber(steamid64)
    if not id64 then return nil end
    
    local accountID = id64 - base
    local y = accountID % 2
    local z = math.floor(accountID / 2)
    
    return "STEAM_0:" .. y .. ":" .. z
end

local function AddToBannedUserCfg(steamid64, reason, duration)
    -- Add to GMod's native banned_user.cfg
    local steamid = SteamID64ToSteamID(steamid64)
    if not steamid then
        print("[ADMIN] Failed to convert SteamID64 to SteamID: " .. tostring(steamid64))
        return
    end
    
    local minutes = tonumber(duration) or 0
    
    if minutes < 0 or minutes == 0 then
        -- Permanent ban
        game.ConsoleCommand('banid 0 ' .. steamid .. '\n')
    else
        -- Temporary ban (convert minutes to GMod format)
        game.ConsoleCommand('banid ' .. minutes .. ' ' .. steamid .. '\n')
    end
    
    game.ConsoleCommand('writeid\n') -- Save to banned_user.cfg
    print("[ADMIN] Added " .. steamid .. " (" .. steamid64 .. ") to banned_user.cfg")
end

local function RemoveFromBannedUserCfg(steamid64)
    -- Remove from GMod's native banned_user.cfg
    local steamid = SteamID64ToSteamID(steamid64)
    if not steamid then
        print("[ADMIN] Failed to convert SteamID64 to SteamID: " .. tostring(steamid64))
        return
    end
    
    game.ConsoleCommand('removeid ' .. steamid .. '\n')
    game.ConsoleCommand('writeid\n') -- Save changes
    print("[ADMIN] Removed " .. steamid .. " (" .. steamid64 .. ") from banned_user.cfg")
end

local function SyncToBannedUserCfg(bannedList)
    -- Sync entire ban list to banned_user.cfg
    -- First, clear all bans (we'll re-add active ones)
    local allPlayers = player.GetAll()
    
    -- Get all currently banned IDs from our list
    local bannedIDs = {}
    for _, ban in ipairs(bannedList) do
        bannedIDs[ban.steamid64] = true
        
        -- Calculate duration
        local duration = -1 -- Permanent by default
        if ban.expires_at and ban.expires_at ~= "" then
            -- Try to calculate remaining time if expires_at is provided
            -- Format: "YYYY-MM-DD HH:MM:SS"
            local year, month, day, hour, min, sec = ban.expires_at:match("(%d+)%-(%d+)%-(%d+) (%d+):(%d+):(%d+)")
            if year then
                local expireTime = os.time({
                    year = tonumber(year),
                    month = tonumber(month),
                    day = tonumber(day),
                    hour = tonumber(hour),
                    min = tonumber(min),
                    sec = tonumber(sec)
                })
                local remainingSeconds = expireTime - os.time()
                if remainingSeconds > 0 then
                    duration = math.ceil(remainingSeconds / 60) -- Convert to minutes
                end
            end
        end
        
        -- Add to banned_user.cfg
        AddToBannedUserCfg(ban.steamid64, ban.reason, duration)
    end
    
    print("[ADMIN] Synced " .. #bannedList .. " bans to banned_user.cfg")
end

local function SaveBannedUsersToFile(bannedList)
    -- Save banned users to local file for offline enforcement
    local filePath = GetBanFilePath()
    local jsonStr = util.TableToJSON({ banned_users = bannedList })
    
    local file = file.Open(filePath, "w", "DATA")
    if file then
        file:Write(jsonStr)
        file:Close()
        print("[ADMIN] Saved " .. (#bannedList) .. " banned users to " .. filePath)
        
        -- Sync to GMod's banned_user.cfg
        SyncToBannedUserCfg(bannedList)
        return true
    else
        print("[ADMIN] Failed to save " .. filePath)
        return false
    end
end

local function FindBannedUser(steamid64, bannedUsers)
    for _, ban in ipairs(bannedUsers) do
        if ban.steamid64 == steamid64 then
            return ban
        end
    end
    return nil
end

-- =========================
-- MULTI-SERVER SYNC
-- =========================

-- Register this server with the API on startup
hook.Add("Initialize", "ADM_ServerRegister", function()
    timer.Simple(5, function()  -- Wait for server to fully initialize
        print("[ADMIN] Attempting to register with API at " .. CONFIG.API_URL .. "/server/register")
        APIRequest("/server/register", "POST", {
            server_id = CONFIG.SERVER_ID,
            server_name = CONFIG.SERVER_NAME,
            callback_url = CONFIG.CALLBACK_URL or ""
        }, function(result, code)
            if result and result.success then
                print("[ADMIN] ✓ Server registered with API. Connected servers: " .. (result.data.connected_servers or 1))
            else
                print("[ADMIN] ✗ Warning: Failed to register with API")
                print("[ADMIN]   Response Code: " .. tostring(code))
                print("[ADMIN]   Result: " .. tostring(result))
                print("[ADMIN] Check that:")
                print("[ADMIN]   1. API is running on " .. CONFIG.API_URL)
                print("[ADMIN]   2. API_KEY in CONFIG matches API_SECRET_KEY in .env")
                print("[ADMIN]   3. Firewall allows connection to port 3000")
            end
        end)
        
        -- Sync bans from API on server start
        print("[ADMIN] Syncing ban list from API...")
        APIRequest("/bans/list", "GET", nil, function(result, code)
            if result and result.success and result.data.banned_users then
                SaveBannedUsersToFile(result.data.banned_users)
                print("[ADMIN] ✓ Ban list synced: " .. #result.data.banned_users .. " active bans")
            else
                print("[ADMIN] ⚠ Could not sync bans from API (offline mode will use local file)")
            end
        end)
    end)
end)

-- Send heartbeat to API with exponential backoff on failure
local LastHeartbeatAttempt = 0
local HeartbeatFailCount = 0
local HeartbeatBackoffTime = CONFIG.HEARTBEAT_INTERVAL

timer.Create("ADM_ServerHeartbeat", CONFIG.HEARTBEAT_INTERVAL, 0, function()
    if CurTime() - LastHeartbeatAttempt < HeartbeatBackoffTime then
        return
    end
    
    LastHeartbeatAttempt = CurTime()
    
    APIRequest("/server/heartbeat", "POST", {
        server_id = CONFIG.SERVER_ID,
        player_count = #player.GetAll()
    }, function(result, code)
        if result and result.success then
            HeartbeatFailCount = 0
            HeartbeatBackoffTime = CONFIG.HEARTBEAT_INTERVAL
        else
            HeartbeatFailCount = HeartbeatFailCount + 1
            HeartbeatBackoffTime = math.min(CONFIG.HEARTBEAT_INTERVAL * math.pow(2, HeartbeatFailCount), 300)
        end
    end)
end)

-- Helper to check if a timestamp string is within the last N seconds
local function IsRecentTimestamp(ts, windowSeconds)
    if not ts then return false end
    local year, month, day, hour, min, sec = ts:match("(%d+)%-(%d+)%-(%d+) (%d+):(%d+):(%d+)")
    if not year then return false end
    local t = os.time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(min),
        sec = tonumber(sec)
    })
    if not t then return false end
    return os.time() - t <= (windowSeconds or 30)
end

-- Check for new bans and kick players who got banned while online
local LastBanCheck = {}
local BanCheckFailCount = {}

timer.Create("ADM_CheckBans", 30, 0, function()
    for _, ply in ipairs(player.GetAll()) do
        local steamid = ply:SteamID64()
        LastBanCheck[steamid] = LastBanCheck[steamid] or 0
        BanCheckFailCount[steamid] = BanCheckFailCount[steamid] or 0
        
        -- Exponential backoff per player: 30s -> 60s -> 120s (max)
        local backoffTime = math.min(30 * math.pow(2, BanCheckFailCount[steamid]), 120)
        
        if CurTime() - LastBanCheck[steamid] >= backoffTime then
            LastBanCheck[steamid] = CurTime()
            
            -- Check for new bans
            APIRequest("/ban/" .. steamid, "GET", nil, function(result, code)
                if result and result.success then
                    BanCheckFailCount[steamid] = 0
                    
                    if result.data.is_banned and result.data.ban then
                        local ban = result.data.ban
                        local durationText = "Permanent"
                        if not ban.is_permanent and ban.duration_minutes then
                            local mins = ban.duration_minutes
                            if mins < 60 then
                                durationText = mins .. "m"
                            elseif mins < 1440 then
                                durationText = math.floor(mins / 60) .. "h"
                            else
                                durationText = math.floor(mins / 1440) .. "d"
                            end
                        end
                        
                        local banMsg = "═══════════════════════\n"
                        banMsg = banMsg .. "You have been BANNED\n"
                        banMsg = banMsg .. "═══════════════════════\n\n"
                        banMsg = banMsg .. "Reason: " .. (ban.reason or "No reason provided") .. "\n"
                        banMsg = banMsg .. "Duration: " .. durationText .. "\n"
                        
                        -- Show admin SteamID64 if linked, otherwise show banned_by
                        local adminInfo = ban.admin_steamid64 or ban.banned_by or "Server"
                        banMsg = banMsg .. "Banned By: " .. adminInfo .. "\n\n"
                        banMsg = banMsg .. "Appeal at: https://discord.gg/W5a89nzmSa"
                        
                        if IsValid(ply) then
                            ply:Kick(banMsg)
                            print("[ADMIN] Player " .. ply:Nick() .. " kicked due to new ban")
                        end
                    end
                else
                    BanCheckFailCount[steamid] = (BanCheckFailCount[steamid] or 0) + 1
                end
            end)
            
            -- Check for new warns (only notify very recent warns)
            APIRequest("/warns/" .. steamid, "GET", nil, function(result, code)
                if result and result.success and result.data.warns then
                    local warns = result.data.warns
                    for _, warn in ipairs(warns) do
                        if warn.is_active and IsRecentTimestamp(warn.created_at, 30) then
                            if not ply.ADM_NotifiedWarns then
                                ply.ADM_NotifiedWarns = {}
                            end

                            if not ply.ADM_NotifiedWarns[warn.id] then
                                ply.ADM_NotifiedWarns[warn.id] = true
                                ply:ChatPrint("\x07FF0000[ADMIN] You have been warned for " .. warn.reason)
                            end
                        end
                    end
                end
            end)
        end
    end
end)

-- Unregister on server shutdown
hook.Add("ShutDown", "ADM_ServerUnregister", function()
    -- Note: This may not complete before shutdown
    APIRequest("/server/unregister", "POST", {
        server_id = CONFIG.SERVER_ID
    })
end)

-- Handle incoming sync events from other servers
-- These are events broadcasted when bans/kicks happen on other servers
local SyncEventHandlers = {
    -- Handle ban from another server - kick the player if online
    ban = function(data)
        local steamid = data.steamid64
        for _, ply in ipairs(player.GetAll()) do
            if ply:SteamID64() == steamid then
                -- Format duration nicely
                local durationText = "Permanent"
                if not data.is_permanent and data.duration_minutes then
                    local mins = data.duration_minutes
                    if mins < 60 then
                        durationText = mins .. "m"
                    elseif mins < 1440 then
                        durationText = math.floor(mins / 60) .. "h"
                    else
                        durationText = math.floor(mins / 1440) .. "d"
                    end
                end
                
                local banMsg = "═══════════════════════\n"
                banMsg = banMsg .. "You have been BANNED\n"
                banMsg = banMsg .. "═══════════════════════\n\n"
                banMsg = banMsg .. "Reason: " .. (data.reason or "No reason provided") .. "\n"
                banMsg = banMsg .. "Duration: " .. durationText .. "\n"
                banMsg = banMsg .. "Banned By: " .. (data.banned_by or "Server") .. "\n\n"
                banMsg = banMsg .. "Appeal at: https://discord.gg/W5a89nzmSa"
                
                ply:Kick(banMsg)
                print("[ADMIN] Player " .. ply:Nick() .. " kicked due to ban from another server")
                break
            end
        end
    end,

    -- Handle unban (just log it)
    unban = function(data)
        print("[ADMIN] Player " .. data.steamid64 .. " was unbanned on the network")
    end,

    -- Handle kick from another server
    kick = function(data)
        local steamid = data.steamid64
        for _, ply in ipairs(player.GetAll()) do
            if ply:SteamID64() == steamid then
                ply:Kick("[KICKED] " .. (data.reason or "Kicked from network"))
                print("[ADMIN] Player " .. ply:Nick() .. " kicked from network")
                break
            end
        end
    end,

    -- Handle rank change
    rank_change = function(data)
        local steamid = data.steamid64
        for _, ply in ipairs(player.GetAll()) do
            if ply:SteamID64() == steamid then
                ply:SetNWString("ADM_Rank", data.rank)
                RefreshAdminStatus(ply)
                print("[ADMIN] Player " .. ply:Nick() .. " rank changed to " .. data.rank)
                break
            end
        end
    end,

    -- Handle warn (notify the player if online)
    warn = function(data)
        local steamid = data.steamid64
        for _, ply in ipairs(player.GetAll()) do
            if ply:SteamID64() == steamid then
                -- Notify player of warn from another server
                ply:ChatPrint("[ADMIN] You have been warned for " .. data.reason)
                break
            end
        end
    end,
}

-- HTTP endpoint for receiving sync events (if callback URL is configured)
-- Note: Requires a separate HTTP server addon like gm_express or similar
-- For now, we poll for ban status on player join

-- =========================
-- ADMIN CHECK (FROM API)
-- =========================
local function IsAdmin(ply)
    if not IsValid(ply) then return false end
    local steamid = ply:SteamID64()
    local cached = AdminCache[steamid]
    if cached and cached.is_admin then
        return true
    end
    return false
end

local function GetRank(ply)
    if not IsValid(ply) then return "user" end
    local cached = AdminCache[ply:SteamID64()]
    return cached and cached.rank or "user"
end

local function HasPermission(ply, permission)
    if not IsValid(ply) then return false end
    local cached = AdminCache[ply:SteamID64()]
    if not cached or not cached.permissions then return false end

    -- Owner has all permissions
    if table.HasValue(cached.permissions, "*") then return true end

    return table.HasValue(cached.permissions, permission)
end

local function RefreshAdminStatus(ply)
    if not IsValid(ply) then return end
    local steamid = ply:SteamID64()

    local function RankDisplayName(rank)
        if rank == "superadmin" then return "Staff Manger" end
        if rank == "trial_mod" then return "Trial Moderator" end
        if rank == "vip" then return "VIP" end
        if rank == "owner" then return "Owner" end
        if rank == "admin" then return "Admin" end
        if rank == "moderator" then return "Moderator" end
        return "User"
    end

    APIRequest("/admin/" .. steamid, "GET", nil, function(result, code)
        if result and result.success then
            AdminCache[steamid] = result.data
            if IsValid(ply) and result.data.rank then
                ply:SetNWString("ADM_Rank", RankDisplayName(result.data.rank))
            end
        end
    end)
end

-- Periodically refresh admin status and rank for all players so Discord changes apply in-game
-- Added exponential backoff to prevent API spam when server is down
local LastAdminRefreshAttempt = {}
local AdminRefreshFailCount = {}

timer.Create("ADM_PeriodicAdminRefresh", 10, 0, function()
    for _, p in ipairs(player.GetAll()) do
        local sid = p:SteamID64()
        LastAdminRefreshAttempt[sid] = LastAdminRefreshAttempt[sid] or 0
        AdminRefreshFailCount[sid] = AdminRefreshFailCount[sid] or 0
        
        -- Exponential backoff per player: 10s -> 20s -> 40s -> 80s (max)
        local backoffTime = math.min(10 * math.pow(2, AdminRefreshFailCount[sid]), 80)
        
        if CurTime() - LastAdminRefreshAttempt[sid] >= backoffTime then
            LastAdminRefreshAttempt[sid] = CurTime()
            
            -- Call API with success/fail tracking
            APIRequest("/admin/" .. sid, "GET", nil, function(result, code)
                if result and result.success then
                    AdminCache[sid] = result.data
                    AdminRefreshFailCount[sid] = 0 -- Reset on success
                    if IsValid(p) and result.data.rank then
                        local function RankDisplayName(rank)
                            if rank == "superadmin" then return "Staff Manger" end
                            if rank == "trial_mod" then return "Trial Moderator" end
                            if rank == "vip" then return "VIP" end
                            if rank == "owner" then return "Owner" end
                            if rank == "admin" then return "Admin" end
                            if rank == "moderator" then return "Moderator" end
                            return "User"
                        end
                        p:SetNWString("ADM_Rank", RankDisplayName(result.data.rank))
                    end
                else
                    AdminRefreshFailCount[sid] = (AdminRefreshFailCount[sid] or 0) + 1
                end
            end)
        end
    end
end)

-- =========================
-- PLAYER CONNECTION & BAN CHECKS
-- =========================

-- Check bans on connection with custom message
hook.Add("CheckPassword", "ADM_BanCheckPassword", function(steamid64, ipaddress, svpassword, clpassword, name)
    -- Check if player is banned
    local bannedUsers = LoadBannedUsersFromFile()
    local ban = FindBannedUser(steamid64, bannedUsers)
    
    if ban then
        -- Build custom ban message
        local durationText = "Permanent"
        if ban.expires_at and ban.expires_at ~= "" then
            durationText = "Until " .. ban.expires_at
        elseif ban.duration_minutes and ban.duration_minutes > 0 then
            local mins = ban.duration_minutes
            if mins < 60 then
                durationText = mins .. " minutes"
            elseif mins < 1440 then
                durationText = math.floor(mins / 60) .. " hours"
            else
                durationText = math.floor(mins / 1440) .. " days"
            end
        end
        
        local banMsg = "═══════════════════════════════════\n"
        banMsg = banMsg .. "     YOU ARE BANNED FROM THIS SERVER\n"
        banMsg = banMsg .. "═══════════════════════════════════\n\n"
        banMsg = banMsg .. "Reason: " .. (ban.reason or "No reason provided") .. "\n"
        banMsg = banMsg .. "Duration: " .. durationText .. "\n"
        banMsg = banMsg .. "Banned By: " .. (ban.banned_by or "Admin") .. "\n\n"
        banMsg = banMsg .. "Appeal at: https://discord.gg/W5a89nzmSa\n"
        banMsg = banMsg .. "═══════════════════════════════════"
        
        print("[ADMIN] Blocked banned player " .. name .. " (" .. steamid64 .. ")")
        return false, banMsg  -- Deny connection with custom message
    end
    
    return true  -- Allow connection
end)

-- Check bans BEFORE player can receive files/spawn (backup check)
hook.Add("PlayerCanReceiveFile", "ADM_BanCheckPreSpawn", function(ply, filename)
    -- Quick pre-spawn ban check
    local steamid = ply:SteamID64()
    local bannedUsers = LoadBannedUsersFromFile()
    local ban = FindBannedUser(steamid, bannedUsers)
    
    if ban then
        print("[ADMIN] [PRE-SPAWN] Denying " .. ply:Nick() .. " - banned locally")
        return false  -- Deny file transfer, will cause disconnect
    end
    return true  -- Allow
end)

-- Sync bans from API with proper interval (respects SYNC_INTERVAL from config)
-- Changed from 1 second to prevent spam when API is down
local LastBanSyncAttempt = 0
local BanSyncFailCount = 0
local BanSyncBackoffTime = CONFIG.SYNC_INTERVAL

timer.Create("ADM_SyncBansFromAPI", CONFIG.SYNC_INTERVAL, 0, function()
    -- Implement exponential backoff when API is failing
    if CurTime() - LastBanSyncAttempt < BanSyncBackoffTime then
        return
    end
    
    LastBanSyncAttempt = CurTime()
    print("[ADMIN] Syncing bans from API...")
    
    APIRequest("/bans/list", "GET", nil, function(result, code)
        if result and result.success and result.data and result.data.banned_users then
            SaveBannedUsersToFile(result.data.banned_users)
            print("[ADMIN] ✓ Ban list synced: " .. #result.data.banned_users .. " active bans")
            -- Reset backoff on success
            BanSyncFailCount = 0
            BanSyncBackoffTime = CONFIG.SYNC_INTERVAL
        else
            -- Increase backoff time on failure (up to 5 minutes max)
            BanSyncFailCount = BanSyncFailCount + 1
            BanSyncBackoffTime = math.min(CONFIG.SYNC_INTERVAL * math.pow(2, BanSyncFailCount), 300)
            print("[ADMIN] ⚠ Could not sync bans from API (code: " .. tostring(code) .. "). Retry in " .. math.floor(BanSyncBackoffTime) .. "s")
        end
    end)
end)

hook.Add("PlayerInitialSpawn", "ADM_PlayerConnect", function(ply)
    timer.Create("ADM_CheckBannedPlayers", 10, 0, function()
        local players = player.GetAll()
        if #players == 0 then return end
    
        -- Try API first, fall back to file
        local bannedUsers = nil
    
        -- Check at least one player via API to see if it's online
        for _, ply in ipairs(players) do
            APIRequest("/player/connect", "POST", {
                steamid64 = ply:SteamID64(),
                username = ply:Nick(),
                ip = ply:IPAddress()
            }, function(result, code)
                if result and result.success and not result.data.allowed then
                    -- Player is banned! Kick them
                    if IsValid(ply) then
                        local ban = result.data.ban
                        local durationText = ban.is_permanent and "Permanent" or ban.expires_at or "Unknown"
                        local banMsg = "═══════════════════════\n"
                        banMsg = banMsg .. "You have been BANNED\n"
                        banMsg = banMsg .. "═══════════════════════\n\n"
                        banMsg = banMsg .. "Reason: " .. ban.reason .. "\n"
                        banMsg = banMsg .. "Duration: " .. durationText .. "\n"
                        banMsg = banMsg .. "Banned By: " .. (ban.banned_by or "Server") .. "\n\n"
                        banMsg = banMsg .. "Appeal at: https://discord.gg/W5a89nzmSa"
                        ply:Kick(banMsg)
                    end
                end
            end)
            break  -- Only check one player per cycle to avoid spamming API
        end
    end)

    local steamid = ply:SteamID64()
    SessionTimes[steamid] = os.time()

    -- Check with API first (primary source of truth)
    APIRequest("/player/connect", "POST", {
        steamid64 = steamid,
        username = ply:Nick(),
        ip = ply:IPAddress()
    }, function(result, code)
        if not IsValid(ply) then return end

        if result and result.success then
            -- API is online - trust this result
            if not result.data.allowed then
                -- Player is banned
                local ban = result.data.ban
                
                -- Format duration
                local durationText = "Permanent"
                if not ban.is_permanent and ban.duration_minutes then
                    local mins = ban.duration_minutes
                    if mins < 60 then
                        durationText = mins .. "m"
                    elseif mins < 1440 then
                        durationText = math.floor(mins / 60) .. "h"
                    else
                        durationText = math.floor(mins / 1440) .. "d"
                    end
                end
                
                local adminInfo = ban.admin_steamid64 or ban.banned_by or "Server"
                
                local banMsg = "═══════════════════════\n"
                banMsg = banMsg .. "You have been BANNED\n"
                banMsg = banMsg .. "═══════════════════════\n\n"
                banMsg = banMsg .. "Reason: " .. ban.reason .. "\n"
                banMsg = banMsg .. "Duration: " .. durationText .. "\n"
                banMsg = banMsg .. "Banned By: " .. adminInfo .. "\n\n"
                banMsg = banMsg .. "Appeal at: https://discord.gg/W5a89nzmSa"
                
                ply:Kick(banMsg)
                return
            end

            -- Store player data
            local function RankDisplayName(rank)
                if rank == "superadmin" then return "Staff Manger" end
                if rank == "trial_mod" then return "Trial Moderator" end
                if rank == "vip" then return "VIP" end
                if rank == "owner" then return "Owner" end
                if rank == "admin" then return "Admin" end
                if rank == "moderator" then return "Moderator" end
                return "User"
            end
            ply:SetNWString("ADM_Rank", RankDisplayName(result.data.user.rank))
            ply:SetNWInt("ADM_Scrapcoins", result.data.user.scrapcoins)

            -- Refresh admin status
            RefreshAdminStatus(ply)
        else
            -- API offline - read from banned_users.json file as fallback
            print("[ADMIN] API offline for " .. ply:Nick() .. " - reading from banned_users.json")
            local bannedUsers = LoadBannedUsersFromFile()
            local ban = FindBannedUser(steamid, bannedUsers)
            
            if ban then
                local banMsg = "═══════════════════════\n"
                banMsg = banMsg .. "You have been BANNED\n"
                banMsg = banMsg .. "═══════════════════════\n\n"
                banMsg = banMsg .. "Reason: " .. ban.reason .. "\n"
                banMsg = banMsg .. "Duration: " .. (ban.is_permanent and "Permanent" or ban.expires_at) .. "\n"
                banMsg = banMsg .. "Banned By: " .. ban.banned_by .. "\n\n"
                banMsg = banMsg .. "Appeal at: https://discord.gg/W5a89nzmSa"
                ply:Kick(banMsg)
                print("[ADMIN] Player " .. ply:Nick() .. " kicked (file-based ban - API offline)")
            else
                print("[ADMIN] Player " .. ply:Nick() .. " allowed (API offline, not in file)")
            end
        end
    end)
end)

hook.Add("PlayerDisconnected", "ADM_PlayerDisconnect", function(ply)
    local steamid = ply:SteamID64()
    local sessionStart = SessionTimes[steamid]

    if sessionStart then
        local sessionMinutes = math.floor((os.time() - sessionStart) / 60)

        APIRequest("/player/disconnect", "POST", {
            steamid64 = steamid,
            session_minutes = sessionMinutes
        })

        SessionTimes[steamid] = nil
    end

    -- Cleanup
    AdminCache[steamid] = nil
    ReturnPositions[steamid] = nil
    AdminMode[steamid] = nil
end)

-- =========================
-- UTILITY FUNCTIONS
-- =========================
local function Notify(ply, msg, color)
    if not IsValid(ply) then return end
    net.Start("ADM_Notify")
    net.WriteString(msg)
    net.WriteColor(color or Color(255, 255, 255))
    net.Send(ply)
end

local function NoPerm(ply)
    Notify(ply, "[ADMIN] You do not have permission to use this command.", Color(255, 0, 0))
end

local function FindPlayer(arg)
    if not arg then return end
    arg = tostring(arg)
    for _, v in ipairs(player.GetAll()) do
        if v:SteamID64() == arg then return v end
        if string.find(string.lower(v:Nick()), string.lower(arg), 1, true) then
            return v
        end
    end
end

local function SaveReturn(ply)
    if IsValid(ply) then
        ReturnPositions[ply:SteamID64()] = ply:GetPos()
    end
end

-- =========================
-- CORE COMMANDS
-- =========================
local function Freeze(admin, target)
    if not HasPermission(admin, "freeze") then return NoPerm(admin) end
    if not IsValid(target) then
        Notify(admin, "[Freeze] Target not found!", Color(255, 100, 100))
        return
    end
    SaveReturn(target)
    target:AddFlags(FL_FROZEN)
    target:SetMoveType(MOVETYPE_NONE)
    Notify(admin, "[Freeze] You froze " .. target:Nick(), Color(0, 255, 255))
end

local function Unfreeze(admin, target)
    if not HasPermission(admin, "freeze") then return NoPerm(admin) end
    if not IsValid(target) then
        Notify(admin, "[Unfreeze] Target not found!", Color(255, 100, 100))
        return
    end
    target:RemoveFlags(FL_FROZEN)
    target:SetMoveType(MOVETYPE_WALK)
    Notify(admin, "[Unfreeze] You unfroze " .. target:Nick(), Color(0, 255, 255))
end

local function Goto(admin, target)
    if not HasPermission(admin, "goto") then return NoPerm(admin) end
    if not IsValid(target) then
        Notify(admin, "[Goto] Target not found!", Color(255, 100, 100))
        return
    end
    SaveReturn(admin)
    admin:SetPos(target:GetPos() - target:GetForward() * 60)
    admin:SetEyeAngles((target:GetPos() - admin:GetPos()):Angle())
    Notify(admin, "[Goto] Teleported to " .. target:Nick(), Color(0, 255, 255))
end

local function Bring(admin, target)
    if not HasPermission(admin, "bring") then return NoPerm(admin) end
    if not IsValid(target) then
        Notify(admin, "[Bring] Target not found!", Color(255, 100, 100))
        return
    end
    SaveReturn(target)
    target:SetPos(admin:GetPos() + admin:GetForward() * 80)
    target:SetEyeAngles((admin:GetPos() - target:GetPos()):Angle())
    Notify(admin, "[Bring] Brought " .. target:Nick(), Color(0, 255, 255))
end

local function Send(admin, fromPlayer, toPlayer)
    if not HasPermission(admin, "bring") then return NoPerm(admin) end
    if not IsValid(fromPlayer) or not IsValid(toPlayer) then
        Notify(admin, "[Send] Target(s) not found!", Color(255, 100, 100))
        return
    end
    SaveReturn(fromPlayer)
    fromPlayer:SetPos(toPlayer:GetPos() - toPlayer:GetForward() * 60)
    Notify(admin, "[Send] Sent " .. fromPlayer:Nick() .. " to " .. toPlayer:Nick(), Color(0, 255, 255))
end

local function Return(admin, target)
    if not IsAdmin(admin) then return NoPerm(admin) end
    target = target or admin
    local pos = ReturnPositions[target:SteamID64()]
    if not pos then
        Notify(admin, "[Return] No saved position for " .. target:Nick(), Color(255, 100, 100))
        return
    end
    target:SetPos(pos)
    ReturnPositions[target:SteamID64()] = nil
    Notify(admin, "[Return] Returned " .. target:Nick() .. " to previous position", Color(0, 255, 255))
end

-- =========================
-- UTILITY COMMANDS
-- =========================
local function ToggleNoclip(ply)
    if not HasPermission(ply, "noclip") then return NoPerm(ply) end
    SaveReturn(ply)
    if ply:GetMoveType() == MOVETYPE_NOCLIP then
        ply:SetMoveType(MOVETYPE_WALK)
        Notify(ply, "[Noclip] Disabled", Color(255, 100, 100))
    else
        ply:SetMoveType(MOVETYPE_NOCLIP)
        Notify(ply, "[Noclip] Enabled", Color(0, 255, 0))
    end
end

local function ToggleGod(ply)
    if not HasPermission(ply, "god") then return NoPerm(ply) end
    local god = not ply:GetNWBool("ADM_GOD", false)
    ply:SetNWBool("ADM_GOD", god)
    Notify(ply, "[God] " .. (god and "Enabled" or "Disabled"), god and Color(0, 255, 0) or Color(255, 100, 100))
end

hook.Add("EntityTakeDamage", "ADM_GodProtection", function(target, dmg)
    if IsValid(target) and target:IsPlayer() and target:GetNWBool("ADM_GOD", false) then
        return true
    end
end)

local function ToggleCloak(ply)
    if not HasPermission(ply, "cloak") then return NoPerm(ply) end
    local cloak = not ply:GetNWBool("ADM_CLOAK", false)
    ply:SetNWBool("ADM_CLOAK", cloak)
    ply:SetNoDraw(cloak)
    ply:DrawShadow(not cloak)
    Notify(ply, "[Cloak] " .. (cloak and "Enabled" or "Disabled"), cloak and Color(0, 255, 0) or Color(255, 100, 100))
end

local function ToggleESP(ply)
    if not IsAdmin(ply) then return NoPerm(ply) end
    local esp = not ply:GetNWBool("ADM_ESP", false)
    ply:SetNWBool("ADM_ESP", esp)
    net.Start("ADM_ToggleESP")
    net.WriteBool(esp)
    net.Send(ply)
    Notify(ply, "[ESP] " .. (esp and "Enabled" or "Disabled"), esp and Color(0, 255, 0) or Color(255, 100, 100))
end

local function ToggleDebugCamera(ply)
    if not IsAdmin(ply) then return NoPerm(ply) end
    local cam = not ply:GetNWBool("ADM_DEBUGCAM", false)
    ply:SetNWBool("ADM_DEBUGCAM", cam)
    net.Start("ADM_ToggleDebugCamera")
    net.WriteBool(cam)
    net.Send(ply)
    Notify(ply, "[DebugCamera] " .. (cam and "Enabled" or "Disabled"), cam and Color(0, 255, 0) or Color(255, 100, 100))
end

net.Receive("ADM_DebugCameraPos", function(len, ply)
    if not IsAdmin(ply) then return end
    local pos = net.ReadVector()
    local ang = net.ReadAngle()
    ply:SetNWVector("ADM_CamPos", pos)
    ply:SetNWAngle("ADM_CamAng", ang)
end)

-- =========================
-- ADMINISTRATE MODE
-- =========================
local function Administrate(ply)
    if not IsAdmin(ply) then return NoPerm(ply) end
    AdminMode[ply:SteamID64()] = not AdminMode[ply:SteamID64()]
    local mode = AdminMode[ply:SteamID64()]

    if mode then
        ply:SetMoveType(MOVETYPE_NOCLIP)
        ply:SetNWBool("ADM_GOD", true)
        ply:SetNoDraw(true)
        ply:DrawShadow(false)
        ply:SetNWBool("ADM_CLOAK", true)
        Notify(ply, "[Administrate] All admin powers ENABLED", Color(0, 255, 0))
    else
        ply:SetMoveType(MOVETYPE_WALK)
        ply:SetNWBool("ADM_GOD", false)
        ply:SetNoDraw(false)
        ply:DrawShadow(true)
        ply:SetNWBool("ADM_CLOAK", false)
        Notify(ply, "[Administrate] All admin powers DISABLED", Color(255, 100, 100))
    end
end

hook.Add("PlayerSpawn", "ADM_ReapplyAdminMode", function(ply)
    if AdminMode[ply:SteamID64()] then
        timer.Simple(0, function()
            if not IsValid(ply) then return end
            ply:SetMoveType(MOVETYPE_NOCLIP)
            ply:SetNWBool("ADM_GOD", true)
            ply:SetNoDraw(true)
            ply:DrawShadow(false)
            ply:SetNWBool("ADM_CLOAK", true)
        end)
    end
end)

-- =========================
-- INSPECT ENTITY
-- =========================
local function InspectEntity(ply)
    if not IsAdmin(ply) then return NoPerm(ply) end
    local ent = ply:GetEyeTrace().Entity

    local ownerID = "N/A"
    local entClass = "N/A"
    local entModel = "N/A"
    local entHealth = "N/A"
    local entName = "N/A"

    if IsValid(ent) then
        entClass = ent:GetClass()
        entModel = ent:GetModel() or "N/A"

        if ent:IsPlayer() then
            ownerID = ent:SteamID64()
            entName = ent:Nick()
            entHealth = ent:Health() .. "/" .. ent:GetMaxHealth()
        else
            -- Try multiple methods to get owner
            local owner = nil
            local foundOwner = false
            
            -- Try CPPI (Common Prop Protection Interface)
            if ent.CPPIGetOwner then
                owner = ent:CPPIGetOwner()
                if IsValid(owner) and owner:IsPlayer() then
                    ownerID = owner:SteamID64() .. " (" .. owner:Nick() .. ")"
                    foundOwner = true
                end
            end
            
            -- Try standard GetOwner
            if not foundOwner and ent.GetOwner then
                owner = ent:GetOwner()
                if IsValid(owner) and owner:IsPlayer() then
                    ownerID = owner:SteamID64() .. " (" .. owner:Nick() .. ")"
                    foundOwner = true
                end
            end
            
            -- Try NWString (custom implementation)
            if not foundOwner then
                local ownerStr = ent:GetNWString("OWNER", "")
                if ownerStr ~= "" then
                    ownerID = ownerStr
                    foundOwner = true
                end
            end
            
            -- Fallback if no owner found
            if not foundOwner then
                ownerID = "World/Unknown"
            end
            
            -- Get entity health
            if ent.Health and ent:Health() > 0 then
                if ent.GetMaxHealth then
                    entHealth = ent:Health() .. "/" .. ent:GetMaxHealth()
                else
                    entHealth = tostring(ent:Health())
                end
            else
                entHealth = "N/A"
            end
        end
    else
        Notify(ply, "[Inspect] No entity found!", Color(255, 100, 100))
        return
    end

    net.Start("ADM_InspectResult")
    net.WriteString(entClass)
    net.WriteString(entName)
    net.WriteString(ownerID)
    net.WriteString(entModel)
    net.WriteString(entHealth)
    net.Send(ply)
end

-- =========================
-- API-INTEGRATED COMMANDS
-- =========================
local function FormatBanDuration(durationMins)
    if not durationMins or durationMins < 0 then return "Permanent" end
    if durationMins < 60 then return durationMins .. "m" end
    if durationMins < 1440 then return math.floor(durationMins / 60) .. "h" end
    return math.floor(durationMins / 1440) .. "d"
end

local function BuildBanKickMessage(reason, durationText, adminSteamid)
    local banMsg = "═══════════════════════\n"
    banMsg = banMsg .. "You have been BANNED\n"
    banMsg = banMsg .. "═══════════════════════\n\n"
    banMsg = banMsg .. "Reason: " .. reason .. "\n"
    banMsg = banMsg .. "Duration: " .. durationText .. "\n"
    banMsg = banMsg .. "Banned By: " .. (adminSteamid or "Server") .. "\n\n"
    banMsg = banMsg .. "Appeal at: https://discord.gg/W5a89nzmSa"
    return banMsg
end

local function BroadcastBanAnnouncement(targetName, reason, durationText)
    for _, v in ipairs(player.GetAll()) do
        v:ChatPrint("[BAN] " .. targetName .. " was banned for " .. reason .. " (" .. durationText .. ")")
    end
end

local function FindPlayerBySteamIDOrName(identifier)
    -- Try to find player by SteamID64 first
    if string.match(identifier, "^7656%d+$") then
        for _, ply in ipairs(player.GetAll()) do
            if ply:SteamID64() == identifier then
                return ply
            end
        end
        return nil  -- SteamID64 but player not online
    end
    
    -- Otherwise try to find by name
    return FindPlayer(identifier)
end

local function Kick(admin, target, reason)
    if not HasPermission(admin, "kick") then return NoPerm(admin) end
    if not IsValid(target) then
        Notify(admin, "[Kick] Target not found!", Color(255, 100, 100))
        return
    end
    local kickReason = reason or "Kicked by admin"
    local targetName = target:Nick()
    local targetSteamid = target:SteamID64()

    -- Notify API for Discord webhook and multi-server kick
    APIRequest("/kick", "POST", {
        steamid64 = targetSteamid,
        reason = kickReason,
        kicked_by_steamid64 = admin:SteamID64(),
        server_id = CONFIG.SERVER_ID,
        server_name = CONFIG.SERVER_NAME,
        player_name = targetName
    })

    target:Kick(kickReason)
    Notify(admin, "[Kick] Kicked " .. targetName .. " (from all servers)", Color(0, 255, 255))
end

local function Ban(admin, targetIdentifier, duration, reason)
    if not HasPermission(admin, "ban") then return NoPerm(admin) end
    
    local durationMins = tonumber(duration)
    if durationMins == nil then
        durationMins = -1
    end
    local durationText = FormatBanDuration(durationMins)
    local banReason = (reason and reason ~= "" and reason) or "Banned by admin"
    
    -- Check if target is a SteamID64 (offline ban) or player name
    local targetSteamid, targetName, target
    
    if string.match(targetIdentifier, "^7656%d+$") then
        -- It's a SteamID64 - check if player is online
        targetSteamid = targetIdentifier
        target = nil
        
        for _, ply in ipairs(player.GetAll()) do
            if ply:SteamID64() == targetSteamid then
                target = ply
                targetName = ply:Nick()
                break
            end
        end
        
        -- If offline, try to get name from previous bans
        if not target then
            local bannedUsers = LoadBannedUsersFromFile()
            for _, ban in ipairs(bannedUsers) do
                if ban.steamid64 == targetSteamid and ban.player_name then
                    targetName = ban.player_name
                    break
                end
            end
            targetName = targetName or targetSteamid
        end
    else
        -- Try to find player by name
        target = FindPlayer(targetIdentifier)
        if not IsValid(target) then
            Notify(admin, "[Ban] Player not found! Use SteamID64 for offline bans.", Color(255, 100, 100))
            return
        end
        targetSteamid = target:SteamID64()
        targetName = target:Nick()
    end
    
    local adminSteamid = admin:SteamID64()

    -- Add to local ban list and save IMMEDIATELY (before API call)
    local currentBans = LoadBannedUsersFromFile()
    table.insert(currentBans, {
        steamid64 = targetSteamid,
        reason = banReason,
        expires_at = nil,
        is_permanent = (durationMins < 0) and 1 or 0,
        banned_by = adminSteamid,
        duration_minutes = durationMins,
        player_name = targetName
    })
    SaveBannedUsersToFile(currentBans)
    
    -- Add to GMod's native banned_user.cfg
    AddToBannedUserCfg(targetSteamid, banReason, durationMins)

    -- Send to API (includes server info for webhook notifications)
    APIRequest("/ban", "POST", {
        steamid64 = targetSteamid,
        reason = banReason,
        duration_minutes = durationMins,
        banned_by_steamid64 = adminSteamid,
        -- Server info for Discord webhook
        server_id = CONFIG.SERVER_ID,
        server_name = CONFIG.SERVER_NAME,
        player_name = targetName
    }, function(result, code)
        if result and result.success then
            Notify(admin, "[Ban] Banned " .. targetName .. " (synced to all servers)", Color(255, 0, 0))
            BroadcastBanAnnouncement(targetName, banReason, durationText)
            if IsValid(target) then
                target:Kick(BuildBanKickMessage(banReason, durationText, adminSteamid))
            end
        else
            Notify(admin, "[Ban] Saved locally (Discord bot/API offline - ban will persist)", Color(255, 165, 0))
            if IsValid(target) then
                target:Kick(BuildBanKickMessage(banReason, durationText, adminSteamid))
            end
        end
    end)
end

local function Unban(admin, steamid)
    if not HasPermission(admin, "unban") then return NoPerm(admin) end

    -- Try to resolve a player name for Discord activity (may be offline)
    local targetPlayer = FindPlayer(steamid)
    local targetName = IsValid(targetPlayer) and targetPlayer:Nick() or steamid

    -- Remove from local ban list IMMEDIATELY (before API call)
    local currentBans = LoadBannedUsersFromFile()
    for i = #currentBans, 1, -1 do
        if currentBans[i].steamid64 == steamid then
            table.remove(currentBans, i)
            break
        end
    end
    SaveBannedUsersToFile(currentBans)
    
    -- Remove from GMod's native banned_user.cfg
    RemoveFromBannedUserCfg(steamid)

    APIRequest("/unban", "POST", {
        steamid64 = steamid,
        reason = "Unbanned by " .. admin:Nick(),
        unbanned_by_steamid64 = admin:SteamID64(),
        -- Server info for Discord webhook
        server_id = CONFIG.SERVER_ID,
        server_name = CONFIG.SERVER_NAME,
        player_name = targetName
    }, function(result, code)
        if result and result.success then
            Notify(admin, "[Unban] Successfully unbanned " .. steamid .. " (synced to all servers)", Color(0, 255, 0))
        else
            Notify(admin, "[Unban] Removed locally (Discord bot/API offline - unban will persist)", Color(255, 165, 0))
        end
    end)
end

local function Warn(admin, target, reason)
    if not HasPermission(admin, "warn") then return NoPerm(admin) end
    if not IsValid(target) then
        Notify(admin, "[Warn] Target not found!", Color(255, 100, 100))
        return
    end

    local warnReason = reason or "Warned by admin"
    local targetName = target:Nick()

    APIRequest("/warn", "POST", {
        steamid64 = target:SteamID64(),
        reason = warnReason,
        warned_by_steamid64 = admin:SteamID64(),
        -- Server info for Discord webhook
        server_id = CONFIG.SERVER_ID,
        server_name = CONFIG.SERVER_NAME,
        player_name = targetName
    }, function(result, code)
        if result and result.success then
            Notify(admin, "[Warn] Warned " .. targetName .. " (Total: " .. result.data.total_warns .. ")", Color(255, 200, 0))
            if IsValid(target) then
                Notify(target, "[ADMIN] You have been warned for " .. warnReason, Color(255, 100, 100))
            end
        else
            Notify(admin, "[Warn] Failed to record warning", Color(255, 100, 100))
        end
    end)
end

local function Respawn(admin, target)
    if not IsAdmin(admin) then return NoPerm(admin) end
    target = target or admin
    if not IsValid(target) then
        Notify(admin, "[Respawn] Target not found!", Color(255, 100, 100))
        return
    end
    SaveReturn(target)
    target:KillSilent()
    timer.Simple(0, function()
        if IsValid(target) then
            target:Spawn()
            Notify(admin, " Respawned " .. target:Nick(), Color(0, 255, 255))
        end
    end)
end

local function SetHealth(admin, target, hp)
    if not IsAdmin(admin) then return NoPerm(admin) end
    if not IsValid(target) then
        Notify(admin, "[SetHealth] Target not found!", Color(255, 100, 100))
        return
    end
    
    local newHP = tonumber(hp)
    if not newHP or newHP <= 0 then
        Notify(admin, "[SetHealth] Invalid HP value!", Color(255, 100, 100))
        return
    end
    
    -- Check if admin is owner
    local adminRank = admin:GetUserGroup()
    local isOwner = (adminRank == "owner" or adminRank == "superadmin")
    
    -- Limit non-owners to max 100 HP
    if not isOwner and newHP > 100 then
        Notify(admin, "[SetHealth] Non-owners can only set HP up to 100!", Color(255, 100, 100))
        return
    end
    
    -- Set max health first if needed
    if newHP > target:GetMaxHealth() then
        target:SetMaxHealth(newHP)
    end
    
    target:SetHealth(newHP)
    Notify(admin, "[SetHealth] Set " .. target:Nick() .. "'s health to " .. target:Health(), Color(0, 255, 255))
end

local function SetRank(admin, target, rank)
    if not HasPermission(admin, "setrank") then return NoPerm(admin) end
    if not IsValid(target) then
        Notify(admin, "SetRank Target not found!", Color(255, 100, 100))
        return
    end

    local validRanks = { user = true, vip = true, moderator = true, admin = true, superadmin = true, owner = true }
    if not validRanks[rank] then
        Notify(admin, "[SetRank] Invalid rank. Valid: user, vip, moderator, admin, superadmin, owner", Color(255, 100, 100))
        return
    end

    -- Update via API - This would need an endpoint
    target:SetNWString("ADM_Rank", rank)
    RefreshAdminStatus(target)
    Notify(admin, "[SetRank] Set " .. target:Nick() .. "'s rank to " .. rank, Color(0, 255, 255))
end

-- =========================
-- SCREENGRAB SYSTEM
-- =========================
-- Store who requested each screengrab
local screengrabRequests = {}

net.Receive("ADM_ScreengrabResult", function(len, ply)
    local imageData = net.ReadString()
    local requestId = net.ReadInt(32)

    if not imageData or imageData == "" then
        APIRequest("/screengrab/complete", "POST", {
            request_id = requestId,
            success = false
        })
        return
    end

    -- Send base64 image directly to API (no Imgur required)
    APIRequest("/screengrab/complete", "POST", {
        request_id = requestId,
        success = true,
        image_data = imageData  -- Send base64 encoded image
    }, function(result, code)
        if result and result.success and result.image_url then
            -- Notify the player who requested it
            local requestor = screengrabRequests[requestId]
            if IsValid(requestor) then
                Notify(requestor, "[Screengrab] Screenshot captured! Link: " .. result.image_url, Color(0, 255, 0))
                screengrabRequests[requestId] = nil
            end
        end
    end)
end)

-- Check for pending screengrabs
local LastScreengrabCheck = {}
local ScreengrabFailCount = {}

timer.Create("ADM_CheckScreengrabs", CONFIG.SCREENGRAB_CHECK_INTERVAL, 0, function()
    for _, ply in ipairs(player.GetAll()) do
        local sid = ply:SteamID64()
        LastScreengrabCheck[sid] = LastScreengrabCheck[sid] or 0
        ScreengrabFailCount[sid] = ScreengrabFailCount[sid] or 0
        
        -- Exponential backoff per player: 5s -> 10s -> 20s -> 40s (max)
        local backoffTime = math.min(CONFIG.SCREENGRAB_CHECK_INTERVAL * math.pow(2, ScreengrabFailCount[sid]), 40)
        
        if CurTime() - LastScreengrabCheck[sid] >= backoffTime then
            LastScreengrabCheck[sid] = CurTime()
            
            APIRequest("/screengrab/pending/" .. sid, "GET", nil, function(result, code)
                if result and result.success then
                    ScreengrabFailCount[sid] = 0 -- Reset on success
                    if result.data.has_pending then
                        net.Start("ADM_Screengrab")
                        net.WriteInt(result.data.request_id, 32)
                        net.Send(ply)
                    end
                else
                    ScreengrabFailCount[sid] = (ScreengrabFailCount[sid] or 0) + 1
                end
            end)
        end
    end
end)

-- =========================
-- HELP COMMAND
-- =========================
local function ShowHelp(ply)
    ply:ChatPrint("========== ADMIN COMMANDS ==========")
    ply:ChatPrint("/freeze, /fz <player> - Freeze player")
    ply:ChatPrint("/unfreeze, /ufz <player> - Unfreeze player")
    ply:ChatPrint("/goto, /go, /gt <player> - Teleport to player")
    ply:ChatPrint("/bring, /tp <player> - Bring player to you")
    ply:ChatPrint("/send <p1> <p2> - Send p1 to p2")
    ply:ChatPrint("/return, /ret [player] - Return to saved pos")
    ply:ChatPrint("/noclip, /fly, /nc - Toggle noclip")
    ply:ChatPrint("/god - Toggle godmode")
    ply:ChatPrint("/cloak, /invis, /cl - Toggle invisibility")
    ply:ChatPrint("/inspect, /info, /id - Inspect entity")
    ply:ChatPrint("/hp <player> <amount> - Set health")
    ply:ChatPrint("/admin, /a - Toggle full admin mode")
    ply:ChatPrint("/esp - Toggle ESP wallhack")
    ply:ChatPrint("/debugcam, /dcam, /fc - Debug Camera")
    ply:ChatPrint("/respawn [player] - Respawn")
    ply:ChatPrint("/kick <player> [reason] - Kick")
    ply:ChatPrint("/ban <player/steamid64> <mins> [reason] - Ban (-1 = permanent)")
    ply:ChatPrint("/unban <steamid64> - Unban")
    ply:ChatPrint("/warn <player> <reason> - Warn player")
    ply:ChatPrint("/help - Show this help")
    ply:ChatPrint("/auth <code> - Link Discord (get code from Discord)")
    ply:ChatPrint("====================================")
end

-- =========================
-- CHAT COMMANDS
-- =========================
hook.Add("PlayerSay", "ADM_ChatCommands", function(ply, text)
    if not IsValid(ply) then return end
    if string.sub(text, 1, 1) ~= "/" then return end

    local args = string.Explode(" ", text)
    local cmd = string.lower(args[1]):gsub("/", "")

    -- Check if admin for most commands
    if not IsAdmin(ply) then
        local publicCommands = { help = true, commands = true, cmds = true, auth = true }
        if not publicCommands[cmd] then
            return "" -- Suppress chat for non-admin commands
        end
    end

    local t1 = args[2] and FindPlayer(args[2])
    local t2 = args[3] and FindPlayer(args[3])

    if cmd == "auth" then
        local code = args[2]
        if not code or code == "" then
            ply:ChatPrint(" Usage: /auth <code>")
            ply:ChatPrint(" Get your code from Discord by clicking the Authenticate button")
            return ""
        end
        
        local steamid = ply:SteamID64()
        ply:ChatPrint("[AUTH] Verifying code " .. string.upper(code) .. "...")
        print(" Auth attempt - SteamID: " .. steamid .. " Code: " .. string.upper(code))
        print(" Auth URL: " .. CONFIG.API_URL .. "/auth/use-code")
        
        APIRequest("/auth/use-code", "POST", { code = string.upper(code), steamid64 = steamid }, function(resp, httpCode)
            print(" Auth response - HTTP Code: " .. tostring(httpCode) .. " Response: " .. tostring(resp and util.TableToJSON(resp) or "nil"))
            
            if not resp then
                ply:ChatPrint(" Connection error (HTTP " .. tostring(httpCode) .. ")")
                ply:ChatPrint(" Check if the API server is running")
                return
            end
            
            if resp.success then
                ply:ChatPrint("====================================")
                ply:ChatPrint(" Account linked successfully!")
                ply:ChatPrint(" Your Discord and Steam accounts are now connected.")
                ply:ChatPrint("====================================")
            else
                local errMsg = resp.error or "Unknown error"
                ply:ChatPrint("  Error: " .. errMsg)
                if errMsg == "Invalid or expired code" then
                    ply:ChatPrint("The code may have expired (10 min limit) or already been used")
                    ply:ChatPrint("Get a new code from Discord")
                else
                    ply:ChatPrint("Make sure you're using the correct code from Discord")
                end
            end
        end)
        return ""
    end

    if cmd == "freeze" or cmd == "fz" then Freeze(ply, t1) return "" end
    if cmd == "unfreeze" or cmd == "ufz" then Unfreeze(ply, t1) return "" end
    if cmd == "goto" or cmd == "go" or cmd == "to" or cmd == "gt" then Goto(ply, t1) return "" end
    if cmd == "bring" or cmd == "tp" or cmd == "summon" then Bring(ply, t1) return "" end
    if cmd == "send" then Send(ply, t1, t2) return "" end
    if cmd == "return" or cmd == "ret" then Return(ply, t1) return "" end
    if cmd == "noclip" or cmd == "fly" or cmd == "nc" then ToggleNoclip(ply) return "" end
    if cmd == "god" then ToggleGod(ply) return "" end
    if cmd == "cloak" or cmd == "invis" or cmd == "ghost" or cmd == "cl" then ToggleCloak(ply) return "" end
    if cmd == "inspect" or cmd == "info" or cmd == "ownerid" or cmd == "id" then InspectEntity(ply) return "" end
    if cmd == "sethealth" or cmd == "hp" or cmd == "sethp" then SetHealth(ply, t1, args[3]) return "" end
    if cmd == "administrate" or cmd == "admin" or cmd == "a" then Administrate(ply) return "" end
    if cmd == "esp" then ToggleESP(ply) return "" end
    if cmd == "debugcam" or cmd == "dcam" or cmd == "freecam" or cmd == "fc" then ToggleDebugCamera(ply) return "" end
    if cmd == "respawn" then Respawn(ply, t1) return "" end
    if cmd == "kick" then Kick(ply, t1, table.concat(args, " ", 3)) return "" end
    --[[
    if cmd == "ban" then
        local targetIdentifier = args[2]  -- Can be player name or SteamID64
        local durationArg = args[3]
        local durationMins = tonumber(durationArg)
        local reasonText

        if durationMins == nil then
            -- User supplied no duration; treat arg3+ as reason, make ban permanent (-1)
            durationMins = -1
            reasonText = table.concat(args, " ", 3)
        else
            -- Duration provided; reason is everything after arg3
            reasonText = table.concat(args, " ", 4)
        end

        Ban(ply, targetIdentifier, durationMins, reasonText)
        return ""
    end
    if cmd == "unban" then Unban(ply, args[2]) return "" end
    if cmd == "warn" then Warn(ply, t1, table.concat(args, " ", 3)) return "" end
    --]]
    if cmd == "screengrab" or cmd == "sg" then
        if not HasPermission(ply, "screengrab") then return NoPerm(ply) end
        local target = FindPlayer(args[2])
        if not IsValid(target) then
            Notify(ply, "[Screengrab] Target not found!", Color(255, 100, 100))
            return ""
        end
        -- Request screenshot from target player via API
        APIRequest("/screengrab/create", "POST", {
            steamid64 = target:SteamID64(),
            requested_by_discord_id = "in-game:" .. ply:SteamID64(),
            server_id = CONFIG.SERVER_ID
        }, function(result, code)
            if result and result.success and result.request_id then
                -- Store who requested this screengrab
                screengrabRequests[result.request_id] = ply
                
                -- Send network message to target to capture screenshot
                net.Start("ADM_Screengrab")
                net.WriteInt(result.request_id, 32)
                net.Send(target)
                
                Notify(ply, "[Screengrab] Request sent to " .. target:Nick(), Color(0, 255, 255))
            else
                Notify(ply, "[Screengrab] Failed to send request (HTTP " .. tostring(code) .. ")", Color(255, 100, 100))
            end
        end)
        return ""
    end
    -- removed in-game setrank command; ranks are managed via Discord
    if cmd == "help" or cmd == "commands" or cmd == "cmds" then ShowHelp(ply) return "" end
    
    -- Unknown command
    ply:ChatPrint("Unknown command: /" .. cmd)
    return ""
end)

-- =========================
-- ADMIN ABUSE DETECTION
-- =========================
-- Detect when admins kill players and report to Discord
hook.Add("PlayerDeath", "ADM_AbsuseDetection", function(victim, inflictor, attacker)
    -- Only log if attacker is a player
    if not IsValid(attacker) or not attacker:IsPlayer() then return end
    if not IsValid(victim) or not victim:IsPlayer() then return end
    
    -- Don't log self-kills
    if attacker == victim then return end
    
    -- Only log if attacker is an admin
    if not IsAdmin(attacker) then return end
    
    -- Don't log admin-on-admin (could be legitimate testing)
    if IsAdmin(victim) then return end
    
    -- Get weapon info
    local weapon = "Unknown"
    if IsValid(attacker:GetActiveWeapon()) then
        weapon = attacker:GetActiveWeapon():GetClass()
    end
    
    -- Send abuse report to API
    local data = {
        server_id = CONFIG.SERVER_ID,
        server_name = CONFIG.SERVER_NAME,
        admin_steamid64 = attacker:SteamID64(),
        admin_name = attacker:Nick(),
        victim_steamid64 = victim:SteamID64(),
        victim_name = victim:Nick(),
        weapon = weapon,
        admin_rank = attacker:GetUserGroup()
    }
    
    HTTP({
        failed = function(err)
            print("[ADMIN ABUSE] Failed to report abuse: " .. err)
        end,
        success = function(code, body, headers)
            if code ~= 200 then
                print("[ADMIN ABUSE] API returned error code: " .. code)
            end
        end,
        method = "POST",
        url = CONFIG.API_URL .. "/abuse/report",
        parameters = data,
        headers = {
            ["X-API-Key"] = CONFIG.API_KEY
        }
    })
end)

print("[ADMIN] Server-side loaded - Connected to Discord API")
print("[ADMIN] Admin abuse detection enabled")
