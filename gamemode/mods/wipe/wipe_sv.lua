-- wipesync_sv.lua
-- Auto wipe + hostname updater for gRust
-- Timer persists across restarts

if not SERVER then return end

--------------------------------------------------
-- CONFIG
--------------------------------------------------

local BASE_HOSTNAME = ""
local WIPE_INTERVAL = 1 * 24 * 60 * 60 
local DATA_FILE = "grust_last_wipe.txt"

--------------------------------------------------
-- WIPE TIME STORAGE
--------------------------------------------------

local function GetLastWipeTime()
    if file.Exists(DATA_FILE, "DATA") then
        local t = tonumber(file.Read(DATA_FILE, "DATA"))
        if t then return t end
    end
    return os.time() -- If file missing, start timer from now
end

local function SetLastWipeTime(time)
    file.Write(DATA_FILE, tostring(time or os.time()))
end

--------------------------------------------------
-- HOSTNAME UPDATE
--------------------------------------------------

local function UpdateHostname()
    local lastWipe = GetLastWipeTime()
    local elapsed = os.time() - lastWipe
    local text

    if elapsed < 60 then
        text = elapsed .. "s ago"
    elseif elapsed < 3600 then
        text = math.floor(elapsed / 60) .. "m ago"
    elseif elapsed < 86400 then
        text = math.floor(elapsed / 3600) .. "h ago"
    else
        text = math.floor(elapsed / 86400) .. "d ago"
    end

    local hostText = BASE_HOSTNAME .. " | wiped " .. text .. " | wipes every 1d"

    if game.IsDedicated() then
        RunConsoleCommand("hostname", hostText)
    end
end

--------------------------------------------------
-- WIPE HANDLER
--------------------------------------------------

local function DoWipe()
    print("[GRUST] Auto wipe triggered")
    RunConsoleCommand("grust_wipe", "1") -- Actual wipe command
    SetLastWipeTime() -- reset timer to now
    UpdateHostname()
end

--------------------------------------------------
-- AUTO WIPE TIMER
--------------------------------------------------

timer.Create("GRust_Auto_Wipe_Check", 1, 0, function() -- every second for accurate timer
    local lastWipe = GetLastWipeTime()
    local elapsed = os.time() - lastWipe

    if elapsed >= WIPE_INTERVAL then
        DoWipe()
    else
        UpdateHostname()
    end
end)

--------------------------------------------------
-- MANUAL WIPE DETECTION
--------------------------------------------------

local function OnWipeTriggered()
    SetLastWipeTime() -- manual wipe resets timer
    UpdateHostname()
end

hook.Add("PlayerRunConsoleCommand", "GRust_Wipe_Player_Detect", function(ply, cmd, args)
    if string.lower(cmd) ~= "grust_wipe" then return end
    if not args or args[1] ~= "1" then return end
    OnWipeTriggered()
end)

hook.Add("ConsoleCommand", "GRust_Wipe_Console_Detect", function(cmd, args)
    if string.lower(cmd) ~= "grust_wipe" then return end
    if not args or args[1] ~= "1" then return end
    OnWipeTriggered()
end)

--------------------------------------------------
-- SERVER STARTUP
--------------------------------------------------

hook.Add("InitPostEntity", "GRust_Set_Hostname_On_Restart", function()
    -- Ensure last wipe timestamp exists
    if not file.Exists(DATA_FILE, "DATA") then
        SetLastWipeTime(os.time()) -- first server start, start timer from now
    end
    UpdateHostname() -- immediately set hostname
end)
