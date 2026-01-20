util.AddNetworkString("RustHitmarker")

hook.Add("EntityTakeDamage", "RustHitmarker_Detect", function(target, dmg)
    local attacker = dmg:GetAttacker()
    
    -- Check if attacker is a valid player
    if not IsValid(attacker) or not attacker:IsPlayer() then return end
    
    -- Check if target is a valid player
    if not IsValid(target) or not target:IsPlayer() then return end
    
    -- Don't show hitmarker for self-damage
    if attacker == target then return end
    
    -- Send hitmarker notification to the attacker
    net.Start("RustHitmarker")
    net.Send(attacker)
end)
