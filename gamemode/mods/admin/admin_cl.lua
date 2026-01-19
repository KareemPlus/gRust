

if not CLIENT then return end

-- =========================
-- DEBUG CAMERA SYSTEM
-- =========================
local DebugCamera = {
    Enabled = false,
    Lerp = 0.1,
    Speed = 1000,
    Pos = Vector(0, 0, 0),
    Ang = Angle(0, 0, 0),
    TargetPos = Vector(0, 0, 0),
    TargetAng = Angle(0, 0, 0),
}

-- =========================
-- ESP SYSTEM
-- =========================
local ESPEnabled = false

-- Bone connections for skeleton ESP
local BONE_CONNECTIONS = {
    ["ValveBiped.Bip01_Head1"] = {"ValveBiped.Bip01_Neck1"},
    ["ValveBiped.Bip01_Neck1"] = {"ValveBiped.Bip01_Spine4"},
    ["ValveBiped.Bip01_Spine4"] = {"ValveBiped.Bip01_Spine2"},
    ["ValveBiped.Bip01_Spine2"] = {"ValveBiped.Bip01_Spine1"},
    ["ValveBiped.Bip01_Spine1"] = {"ValveBiped.Bip01_Spine"},
    ["ValveBiped.Bip01_Pelvis"] = {"ValveBiped.Bip01_R_Thigh", "ValveBiped.Bip01_L_Thigh", "ValveBiped.Bip01_Spine"},
    ["ValveBiped.Bip01_R_Thigh"] = {"ValveBiped.Bip01_R_Calf"},
    ["ValveBiped.Bip01_R_Calf"] = {"ValveBiped.Bip01_R_Foot"},
    ["ValveBiped.Bip01_R_Foot"] = {"ValveBiped.Bip01_R_Toe0"},
    ["ValveBiped.Bip01_L_Thigh"] = {"ValveBiped.Bip01_L_Calf"},
    ["ValveBiped.Bip01_L_Calf"] = {"ValveBiped.Bip01_L_Foot"},
    ["ValveBiped.Bip01_L_Foot"] = {"ValveBiped.Bip01_L_Toe0"},
    ["ValveBiped.Bip01_Spine"] = {"ValveBiped.Bip01_R_UpperArm", "ValveBiped.Bip01_L_UpperArm"},
    ["ValveBiped.Bip01_R_UpperArm"] = {"ValveBiped.Bip01_R_Forearm"},
    ["ValveBiped.Bip01_R_Forearm"] = {"ValveBiped.Bip01_R_Hand"},
    ["ValveBiped.Bip01_L_UpperArm"] = {"ValveBiped.Bip01_L_Forearm"},
    ["ValveBiped.Bip01_L_Forearm"] = {"ValveBiped.Bip01_L_Hand"},
}

-- =========================
-- FONTS
-- =========================
surface.CreateFont("ADM_Title", {
    font = "Courier New",
    size = 24,
    weight = 800,
    antialias = true,
    outline = true,
})

surface.CreateFont("ADM_Font", {
    font = "Courier New",
    size = 16,
    weight = 500,
    antialias = true,
    outline = true,
})

surface.CreateFont("ADM_ESP", {
    font = "Tahoma",
    size = 14,
    weight = 700,
    antialias = true,
    outline = true,
})

surface.CreateFont("ADM_Notify", {
    font = "Roboto",
    size = 18,
    weight = 500,
    antialias = true,
})

-- =========================
-- NOTIFICATION SYSTEM
-- =========================
local Notifications = {}

local function AddNotification(text, color)
    table.insert(Notifications, {
        text = text,
        color = color or Color(255, 255, 255),
        time = CurTime(),
        alpha = 255
    })
end

hook.Add("HUDPaint", "ADM_NotifyHUD", function()
    local y = ScrH() - 200
    local toRemove = {}

    for i, notif in ipairs(Notifications) do
        local age = CurTime() - notif.time
        if age > 5 then
            notif.alpha = notif.alpha - FrameTime() * 200
            if notif.alpha <= 0 then
                table.insert(toRemove, i)
            end
        end

        if notif.alpha > 0 then
            local col = Color(notif.color.r, notif.color.g, notif.color.b, notif.alpha)
            draw.SimpleTextOutlined(notif.text, "ADM_Notify", 20, y, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, notif.alpha))
            y = y - 25
        end
    end

    -- Remove expired notifications
    for i = #toRemove, 1, -1 do
        table.remove(Notifications, toRemove[i])
    end
end)

-- =========================
-- NET RECEIVERS
-- =========================
net.Receive("ADM_Notify", function()
    local text = net.ReadString()
    local color = net.ReadColor()
    AddNotification(text, color)
    chat.AddText(color, text)
end)

net.Receive("ADM_ToggleESP", function()
    ESPEnabled = net.ReadBool()
end)

net.Receive("ADM_ToggleDebugCamera", function()
    local enabled = net.ReadBool()
    DebugCamera.Enabled = enabled
    if enabled then
        local pl = LocalPlayer()
        DebugCamera.Pos = pl:EyePos()
        DebugCamera.Ang = pl:EyeAngles()
        DebugCamera.TargetPos = pl:EyePos()
        DebugCamera.TargetAng = pl:EyeAngles()
    end
end)

net.Receive("ADM_InspectResult", function()
    local entClass = net.ReadString()
    local entName = net.ReadString()
    local ownerID = net.ReadString()
    local entModel = net.ReadString()
    local entHealth = net.ReadString()

    chat.AddText(Color(0, 255, 255), "[Inspect] ", Color(255, 255, 255), "Class: ", Color(255, 200, 0), entClass)
    if entName ~= "N/A" then
        chat.AddText(Color(0, 255, 255), "[Inspect] ", Color(255, 255, 255), "Name: ", Color(0, 255, 0), entName)
    end
    chat.AddText(Color(0, 255, 255), "[Inspect] ", Color(255, 255, 255), "Owner: ", Color(255, 0, 0), ownerID)
    chat.AddText(Color(0, 255, 255), "[Inspect] ", Color(255, 255, 255), "Model: ", Color(200, 200, 200), entModel)
    chat.AddText(Color(0, 255, 255), "[Inspect] ", Color(255, 255, 255), "Health: ", Color(100, 255, 100), entHealth)
end)

-- =========================
-- CHAT PREFIX: RANK BEFORE NAME
-- =========================
local function RankColor(rank)
    if rank == "Owner" then return Color(255, 0, 0) end
    if rank == "Staff Manger" then return Color(0, 153, 255) end
    if rank == "Admin" then return Color(128, 0, 128) end
    if rank == "Moderator" then return Color(0, 0, 255) end
    if rank == "Trial Moderator" then return Color(0, 255, 0) end
    if rank == "VIP" then return Color(255, 215, 0) end
    return Color(200, 200, 200)
end

hook.Add("OnPlayerChat", "ADM_RankPrefixChat", function(ply, text, teamChat, isDead)
    if not IsValid(ply) then return end

    -- Don't double-print slash commands locally; server already suppresses
    if string.sub(text or "", 1, 1) == "/" then return end

    local rank = ply:GetNWString("ADM_Rank", "")
    local rankCol = RankColor(rank)
    local nameCol = teamChat and Color(102, 178, 255) or Color(255, 255, 255)
    local deadCol = Color(150, 150, 150)

    local parts = {}
    if isDead then
        table.insert(parts, deadCol)
        table.insert(parts, "*DEAD* ")
    end
    if teamChat then
        table.insert(parts, Color(102, 178, 255))
        table.insert(parts, "(TEAM) ")
    end
    if rank ~= nil and rank ~= "" then
        table.insert(parts, rankCol)
        table.insert(parts, "[" .. rank .. "] ")
    end
    table.insert(parts, nameCol)
    table.insert(parts, ply:Nick())
    table.insert(parts, Color(255, 255, 255))
    table.insert(parts, ": ")
    table.insert(parts, Color(230, 230, 230))
    table.insert(parts, text)

    chat.AddText(unpack(parts))
    return true -- suppress default chat line
end)

-- =========================
-- SCREENGRAB HANDLER
-- =========================
net.Receive("ADM_Screengrab", function()
    local requestId = net.ReadInt(32)

    -- Capture on next frame using PostRender hook for better timing
    hook.Add("PostRender", "ADM_CaptureScreen_" .. requestId, function()
        hook.Remove("PostRender", "ADM_CaptureScreen_" .. requestId)
        
        -- Small delay after PostRender to ensure everything is drawn
        timer.Simple(0.1, function()
            local data = render.Capture({
                format = "png",
                quality = 100,
                x = 0,
                y = 0,
                w = ScrW(),
                h = ScrH()
            })

            if data then
                -- Encode to base64
                local base64 = util.Base64Encode(data)

                net.Start("ADM_ScreengrabResult")
                net.WriteString(base64)
                net.WriteInt(requestId, 32)
                net.SendToServer()
            else
                net.Start("ADM_ScreengrabResult")
                net.WriteString("")
                net.WriteInt(requestId, 32)
                net.SendToServer()
            end
        end)
    end)
end)

-- =========================
-- DEBUG CAMERA FUNCTIONS
-- =========================
local function GoToPlayer()
    DebugCamera.TargetPos = LocalPlayer():EyePos()
    DebugCamera.TargetAng = LocalPlayer():EyeAngles()
end

hook.Add("CalcView", "ADM_DebugCam", function()
    if not DebugCamera.Enabled then return end
    DebugCamera.Pos = LerpVector(DebugCamera.Lerp, DebugCamera.Pos, DebugCamera.TargetPos)
    DebugCamera.Ang = LerpAngle(DebugCamera.Lerp, DebugCamera.Ang, DebugCamera.TargetAng)
    DebugCamera.Ang.z = 0
    return { origin = DebugCamera.Pos, angles = DebugCamera.Ang }
end)

hook.Add("ShouldDrawLocalPlayer", "ADM_DebugCam", function()
    if DebugCamera.Enabled then return true end
end)

hook.Add("StartCommand", "ADM_DebugCam", function(pl, cmd)
    if not DebugCamera.Enabled then return end

    DebugCamera.TargetAng.y = DebugCamera.TargetAng.y - cmd:GetMouseX() * FrameTime() * 2
    DebugCamera.TargetAng.p = math.Clamp(DebugCamera.TargetAng.p + cmd:GetMouseY() * FrameTime() * 2, -89, 89)

    local speed = DebugCamera.Speed
    if input.IsKeyDown(KEY_LSHIFT) then speed = speed * 2 end
    if input.IsKeyDown(KEY_LCONTROL) then speed = speed * 0.2 end
    if input.IsKeyDown(KEY_SPACE) then speed = speed * 0.1 end

    local forward = DebugCamera.TargetAng:Forward()
    local right = DebugCamera.TargetAng:Right()
    local up = DebugCamera.TargetAng:Up()

    if cmd:KeyDown(IN_FORWARD) then DebugCamera.TargetPos = DebugCamera.TargetPos + forward * speed * FrameTime() end
    if cmd:KeyDown(IN_BACK) then DebugCamera.TargetPos = DebugCamera.TargetPos - forward * speed * FrameTime() end
    if cmd:KeyDown(IN_MOVELEFT) then DebugCamera.TargetPos = DebugCamera.TargetPos - right * speed * FrameTime() end
    if cmd:KeyDown(IN_MOVERIGHT) then DebugCamera.TargetPos = DebugCamera.TargetPos + right * speed * FrameTime() end
    if input.IsKeyDown(KEY_Q) then DebugCamera.TargetPos = DebugCamera.TargetPos - up * speed * FrameTime() end
    if input.IsKeyDown(KEY_E) then DebugCamera.TargetPos = DebugCamera.TargetPos + up * speed * FrameTime() end
    if input.IsKeyDown(KEY_G) then GoToPlayer() end

    cmd:ClearMovement()
    cmd:ClearButtons()
    cmd:SetMouseX(0)
    cmd:SetMouseY(0)
end)

hook.Add("Think", "ADM_DebugCam", function()
    if not DebugCamera.Enabled then return end
    net.Start("ADM_DebugCameraPos")
    net.WriteVector(DebugCamera.TargetPos)
    net.WriteAngle(DebugCamera.TargetAng)
    net.SendToServer()
end)

-- =========================
-- DEBUG CAMERA HUD
-- =========================
local DebugCamInfo = {
    "WASD - Move",
    "Mouse - Look",
    "Shift - Speed x2",
    "Ctrl - Slow x0.2",
    "Space - Very Slow x0.1",
    "Q - Down",
    "E - Up",
    "G - Go to player",
}

hook.Add("HUDPaint", "ADM_DebugCamHUD", function()
    if not DebugCamera.Enabled then return end

    local margin = 32
    local y = margin

    draw.SimpleText("DEBUG CAMERA", "ADM_Title", margin, y, Color(0, 255, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    y = y + 30

    for _, text in ipairs(DebugCamInfo) do
        draw.SimpleText(text, "ADM_Font", margin, y, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        y = y + 18
    end

    y = y + 10
    draw.SimpleText("Pos: " .. tostring(DebugCamera.Pos), "ADM_Font", margin, y, Color(200, 200, 200), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    y = y + 18
    draw.SimpleText("Ang: " .. tostring(DebugCamera.Ang), "ADM_Font", margin, y, Color(200, 200, 200), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
end)

-- =========================
-- ESP 3D RENDERING
-- =========================
local ANGLE_ORIGIN = Angle(0, 0, 0)

hook.Add("PostDrawOpaqueRenderables", "ADM_ESP3D", function()
    if not ESPEnabled then return end

    for _, pl in player.Iterator() do
        if pl == LocalPlayer() and not DebugCamera.Enabled then continue end

        render.SetColorMaterial()

        -- Draw skeleton
        for bone, connections in pairs(BONE_CONNECTIONS) do
            local boneID = pl:LookupBone(bone)
            if not boneID then continue end
            local pos = pl:GetBonePosition(boneID)
            if not pos then continue end

            for _, connBone in ipairs(connections) do
                local connBoneID = pl:LookupBone(connBone)
                if not connBoneID then continue end
                local pos2 = pl:GetBonePosition(connBoneID)
                if not pos2 then continue end
                render.DrawLine(pos, pos2, Color(0, 255, 0))
            end
        end

        -- Draw bounding box
        local mins, maxs = pl:OBBMins(), pl:OBBMaxs()
        render.DrawWireframeBox(pl:GetPos(), ANGLE_ORIGIN, mins, maxs, Color(255, 255, 0))

        -- Draw eye trace lines
        local tr = pl:GetEyeTraceNoCursor()
        local tr2 = pl:GetEyeTrace()
        render.DrawBeam(pl:EyePos(), tr2.HitPos, 1, 0, 1, Color(255, 0, 0))
        render.DrawBeam(pl:EyePos(), tr.HitPos, 1, 0, 1, Color(255, 255, 255))
    end
end)

-- =========================
-- ESP 2D HUD
-- =========================
hook.Add("HUDPaint", "ADM_ESP2D", function()
    if not ESPEnabled then return end

    local viewPos = DebugCamera.Enabled and DebugCamera.TargetPos or LocalPlayer():EyePos()

    for _, pl in player.Iterator() do
        if pl == LocalPlayer() and not DebugCamera.Enabled then continue end

        -- Visibility check
        local tr = util.TraceLine({
            start = viewPos,
            endpos = pl:EyePos(),
            filter = { pl, LocalPlayer() },
            mask = MASK_SHOT
        })

        local visible = not tr.Hit
        local nameColor = visible and Color(0, 255, 0) or Color(255, 100, 100)

        -- Screen position
        local headPos = pl:GetPos() + Vector(0, 0, 80)
        local screen = headPos:ToScreen()

        if not screen.visible then continue end

        -- Player rank
        local rank = pl:GetNWString("ADM_Rank", "user")
        local rankColor = Color(150, 150, 150)
        if rank == "owner" then rankColor = Color(255, 0, 0)
        elseif rank == "superadmin" then rankColor = Color(255, 100, 0)
        elseif rank == "admin" then rankColor = Color(0, 200, 255)
        elseif rank == "moderator" then rankColor = Color(0, 255, 100)
        elseif rank == "vip" then rankColor = Color(255, 200, 0)
        end

        -- Draw rank
        draw.SimpleTextOutlined("[" .. string.upper(rank) .. "]", "ADM_ESP", screen.x, screen.y - 16, rankColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)

        -- Player name
        draw.SimpleTextOutlined(pl:Nick(), "ADM_ESP", screen.x, screen.y, nameColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)

        -- SteamID64
        draw.SimpleTextOutlined(pl:SteamID64(), "ADM_ESP", screen.x, screen.y + 16, Color(200, 200, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)

        -- Health bar
        local health = pl:Health()
        local maxHealth = pl:GetMaxHealth()
        local healthPercent = math.Clamp(health / maxHealth, 0, 1)
        local barWidth, barHeight = 60, 4
        local barX, barY = screen.x - barWidth / 2, screen.y + 32

        draw.RoundedBox(2, barX - 1, barY - 1, barWidth + 2, barHeight + 2, Color(0, 0, 0, 200))
        draw.RoundedBox(2, barX, barY, barWidth * healthPercent, barHeight, Color(255 * (1 - healthPercent), 255 * healthPercent, 0))

        -- Distance
        local dist = math.Round(viewPos:Distance(pl:GetPos()))
        draw.SimpleTextOutlined(dist .. "m", "ADM_ESP", screen.x, screen.y + 42, Color(150, 150, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)

        -- Weapon
        local wep = pl:GetActiveWeapon()
        local weaponName = "Nothing"
        if IsValid(wep) then
            weaponName = wep:GetClass():gsub("^weapon_", "")
            draw.SimpleTextOutlined(weaponName, "ADM_ESP", screen.x, screen.y + 56, Color(255, 200, 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
        end
    end
end)

print("[ADMIN] Client-side ESP & Debug Camera loaded")



        
