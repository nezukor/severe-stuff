local npc_library = {}

-- NPC detection and management library for Severe
-- Provides functions to find, filter, and manage NPCs in games

-- Cache for NPC models to avoid repeated scanning
local npc_cache = {}
local cache_expiry = 0
local cache_duration = 5 -- Cache expires after 5 seconds

-- Common NPC indicators
local npc_indicators = {
    -- Common NPC model names
    "NPC", "Bot", "Enemy", "Monster", "Mob", "Creature",
    -- Common humanoid properties that indicate NPCs
    "AutoJumpEnabled", "PlatformStand",
}

-- Check if a model is likely an NPC
local function is_likely_npc(model)
    if not model or not model:IsA("Model") then return false end
    
    local humanoid = model:FindFirstChild("Humanoid")
    if not humanoid then return false end
    
    -- Check for NPC-specific properties
    for _, indicator in pairs(npc_indicators) do
        if model.Name:find(indicator) or humanoid:FindFirstChild(indicator) then
            return true
        end
    end
    
    -- Check if it's not a player character
    local players_service = game:GetService("Players")
    for _, player in pairs(players_service:GetPlayers()) do
        if player.Character == model then
            return false -- It's a player character
        end
    end
    
    -- Check for common NPC patterns
    local root_part = model:FindFirstChild("HumanoidRootPart")
    if not root_part then return false end
    
    -- NPCs often have specific configurations
    if humanoid.AutoJumpEnabled == false or humanoid.PlatformStand == true then
        return true
    end
    
    -- Check if the model has no player associated with it
    -- and has a humanoid with health
    if humanoid.Health > 0 and humanoid.MaxHealth > 0 then
        -- It's likely an NPC if it's not a player character
        return true
    end
    
    return false
end

-- Refresh the NPC cache
local function refresh_cache()
    npc_cache = {}
    cache_expiry = tick() + cache_duration
    
    for _, model in pairs(workspace:GetDescendants()) do
        if is_likely_npc(model) then
            local humanoid = model:FindFirstChild("Humanoid")
            local root_part = model:FindFirstChild("HumanoidRootPart")
            
            if humanoid and root_part and humanoid.Health > 0 then
                table.insert(npc_cache, {
                    model = model,
                    character = model,
                    humanoid = humanoid,
                    root_part = root_part,
                    name = model.Name,
                    health = humanoid.Health,
                    max_health = humanoid.MaxHealth,
                    position = root_part.Position
                })
            end
        end
    end
end

-- Get all NPCs in the game
function npc_library.get_npcs()
    -- Refresh cache if expired
    if tick() > cache_expiry then
        refresh_cache()
    end
    
    -- Filter out dead NPCs
    local valid_npcs = {}
    for _, npc in pairs(npc_cache) do
        if npc.humanoid and npc.humanoid.Health > 0 and npc.model and npc.model.Parent then
            table.insert(valid_npcs, npc)
        end
    end
    
    return valid_npcs
end

-- Get NPCs within range of a position
function npc_library.get_npcs_in_range(position, range)
    local npcs = npc_library.get_npcs()
    local nearby_npcs = {}
    
    for _, npc in pairs(npcs) do
        local distance = (npc.position - position).Magnitude
        if distance <= range then
            npc.distance = distance
            table.insert(nearby_npcs, npc)
        end
    end
    
    -- Sort by distance
    table.sort(nearby_npcs, function(a, b) return a.distance < b.distance end)
    
    return nearby_npcs
end

-- Get NPCs within range and angle (for targeting)
function npc_library.get_npcs_in_range_and_angle(origin, look_vector, range, max_angle)
    local npcs = npc_library.get_npcs()
    local valid_npcs = {}
    
    local normalized_look = look_vector.Unit
    
    for _, npc in pairs(npcs) do
        local delta = npc.position - origin
        local distance = delta.Magnitude
        
        -- Range check
        if distance > range then continue end
        
        -- Angle check
        local normalized_delta = delta.Unit
        local angle = math.deg(math.acos(math.clamp(normalized_look:Dot(normalized_delta), -1, 1)))
        
        if angle <= max_angle then
            npc.distance = distance
            npc.angle = angle
            table.insert(valid_npcs, npc)
        end
    end
    
    -- Sort by distance
    table.sort(valid_npcs, function(a, b) return a.distance < b.distance end)
    
    return valid_npcs
end

-- Check if a model is an NPC
function npc_library.is_npc(model)
    return is_likely_npc(model)
end

-- Get NPC data in entity_support format (for compatibility)
function npc_library.get_as_entities(options)
    options = options or {}
    
    local range = options.Range or 28
    local wallcheck_enabled = options.Wallcheck
    local part_name = options.Part or "RootPart"
    local limit = options.Limit or math.huge
    local sort_method = options.Sort or "Distance"
    
    local local_player = game:GetService("Players").LocalPlayer
    local local_character = local_player.Character
    if not local_character or not local_character:FindFirstChild("HumanoidRootPart") then
        return {}
    end
    
    local self_pos = local_character.HumanoidRootPart.Position
    local self_facing = local_character.HumanoidRootPart.CFrame.LookVector * Vector3.new(1, 0, 1)
    local entities = {}
    
    local npcs = npc_library.get_npcs()
    
    for _, npc in pairs(npcs) do
        local target_part = npc.model:FindFirstChild(part_name)
        if not target_part then continue end
        
        local distance = (target_part.Position - self_pos).Magnitude
        if distance > range then continue end
        
        local delta = target_part.Position - self_pos
        local angle = math.deg(math.acos(math.clamp(
            self_facing:Dot((delta * Vector3.new(1, 0, 1)).Unit), -1, 1
        )))
        
        -- Wall check
        if wallcheck_enabled then
            local ignore_list = {local_character, npc.model}
            local ray = Ray.new(self_pos, delta.Unit * distance)
            local hit_part = workspace:FindPartOnRayWithIgnoreList(ray, ignore_list, false, true)
            if hit_part then
                continue
            end
        end
        
        table.insert(entities, {
            player = nil, -- NPCs don't have players
            character = npc.model,
            RootPart = target_part,
            Humanoid = npc.humanoid,
            distance = distance,
            angle = angle,
            is_npc = true
        })
    end
    
    -- Sort entities
    if sort_method == "Distance" then
        table.sort(entities, function(a, b) return a.distance < b.distance end)
    elseif sort_method == "Damage" then
        table.sort(entities, function(a, b) 
            local a_health = a.Humanoid and a.Humanoid.Health or 0
            local b_health = b.Humanoid and b.Humanoid.Health or 0
            return a_health < b_health
        end)
    elseif sort_method == "Angle" then
        table.sort(entities, function(a, b) return a.angle < b.angle end)
    end
    
    -- Limit results
    if limit < #entities then
        local result = {}
        for i = 1, limit do
            result[i] = entities[i]
        end
        return result
    end
    
    return entities
end

-- Clear the cache manually
function npc_library.clear_cache()
    npc_cache = {}
    cache_expiry = 0
end

-- Set cache duration
function npc_library.set_cache_duration(seconds)
    cache_duration = seconds
end

-- Get cache status
function npc_library.get_cache_status()
    return {
        cached_count = #npc_cache,
        expiry_time = cache_expiry,
        is_expired = tick() > cache_expiry
    }
end

return npc_library
