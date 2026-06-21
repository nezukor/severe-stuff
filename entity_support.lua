local entity_support = {}

-- Entity library equivalent for Severe
-- Provides target finding and filtering functions similar to CatV6's entitylib

local function is_alive(character)
    if not character then return false end
    
    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid then return false end
    
    return humanoid.Health > 0
end

local function get_distance(pos1, pos2)
    return (pos1 - pos2).Magnitude
end

local function get_angle(look_vector, target_direction)
    local normalized_look = look_vector.Unit
    local normalized_target = target_direction.Unit
    return math.deg(math.acos(math.clamp(normalized_look:Dot(normalized_target), -1, 1)))
end

local function wallcheck(origin, target_pos, ignore_list)
    local ray = Ray.new(origin, (target_pos - origin).Unit * get_distance(origin, target_pos))
    local hit_part, hit_pos, hit_normal = workspace:FindPartOnRayWithIgnoreList(ray, ignore_list or {}, false, true)
    
    -- If we hit something, check if it's the target
    if hit_part then
        return true -- Wall detected
    end
    
    return false -- No wall
end

-- Find all entities within range with filtering options
function entity_support.get_entities(options)
    options = options or {}
    
    local range = options.Range or 28
    local wallcheck_enabled = options.Wallcheck
    local part_name = options.Part or "RootPart"
    local players_enabled = options.Players ~= false
    local npcs_enabled = options.NPCs or false
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
    
    -- Get players
    if players_enabled then
        for _, player in pairs(game:GetService("Players"):GetPlayers()) do
            if player == local_player then continue end
            
            local character = player.Character
            if not is_alive(character) then continue end
            
            local target_part = character:FindFirstChild(part_name)
            if not target_part then continue end
            
            local distance = get_distance(self_pos, target_part.Position)
            if distance > range then continue end
            
            local delta = target_part.Position - self_pos
            local angle = get_angle(self_facing, delta * Vector3.new(1, 0, 1))
            
            -- Wall check
            if wallcheck_enabled then
                local ignore_list = {local_character, character}
                if wallcheck(self_pos, target_part.Position, ignore_list) then
                    continue
                end
            end
            
            local humanoid = character:FindFirstChild("Humanoid")
            
            table.insert(entities, {
                player = player,
                character = character,
                RootPart = target_part,
                Humanoid = humanoid,
                distance = distance,
                angle = angle
            })
        end
    end
    
    -- Get NPCs (if enabled)
    if npcs_enabled then
        for _, model in pairs(workspace:GetDescendants()) do
            if model:IsA("Model") and model ~= local_character then
                local humanoid = model:FindFirstChild("Humanoid")
                if humanoid and humanoid.Health > 0 then
                    local target_part = model:FindFirstChild(part_name)
                    if not target_part then continue end
                    
                    local distance = get_distance(self_pos, target_part.Position)
                    if distance > range then continue end
                    
                    local delta = target_part.Position - self_pos
                    local angle = get_angle(self_facing, delta * Vector3.new(1, 0, 1))
                    
                    -- Wall check
                    if wallcheck_enabled then
                        local ignore_list = {local_character, model}
                        if wallcheck(self_pos, target_part.Position, ignore_list) then
                            continue
                        end
                    end
                    
                    table.insert(entities, {
                        player = nil, -- NPCs don't have players
                        character = model,
                        RootPart = target_part,
                        Humanoid = humanoid,
                        distance = distance,
                        angle = angle,
                        is_npc = true
                    })
                end
            end
        end
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

-- Check if local player is alive
function entity_support.is_local_alive()
    local local_player = game:GetService("Players").LocalPlayer
    local character = local_player.Character
    return is_alive(character)
end

-- Get local player character
function entity_support.get_local_character()
    local local_player = game:GetService("Players").LocalPlayer
    return local_player.Character
end

-- Get local player data
function entity_support.get_local_data()
    local local_player = game:GetService("Players").LocalPlayer
    local character = local_player.Character
    
    if not character then
        return {
            is_alive = false,
            character = nil,
            root_part = nil,
            humanoid = nil
        }
    end
    
    local humanoid = character:FindFirstChild("Humanoid")
    local root_part = character:FindFirstChild("HumanoidRootPart")
    
    return {
        is_alive = is_alive(character),
        character = character,
        root_part = root_part,
        humanoid = humanoid,
        health = humanoid and humanoid.Health or 0,
        max_health = humanoid and humanoid.MaxHealth or 0,
        position = root_part and root_part.Position or Vector3.zero
    }
end

-- Check if entity is valid and alive
function entity_support.is_valid_entity(entity)
    if not entity then return false end
    if not entity.character then return false end
    return is_alive(entity.character)
end

-- Filter entities by custom predicate
function entity_support.filter_entities(entities, predicate)
    local result = {}
    for _, entity in pairs(entities) do
        if predicate(entity) then
            table.insert(result, entity)
        end
    end
    return result
end

-- Get entity by player
function entity_support.get_entity_by_player(player)
    local local_player = game:GetService("Players").LocalPlayer
    if player == local_player then return nil end
    
    local character = player.Character
    if not is_alive(character) then return nil end
    
    local humanoid = character:FindFirstChild("Humanoid")
    local root_part = character:FindFirstChild("HumanoidRootPart")
    
    return {
        player = player,
        character = character,
        RootPart = root_part,
        Humanoid = humanoid
    }
end

return entity_support
