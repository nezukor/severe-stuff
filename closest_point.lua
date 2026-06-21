local cpa = {}

local FOV      = 180
local enabled  = false
local viz_on   = false
local conn     = nil
local registry = {}

local viz_dot, viz_ring, viz_label = nil, nil, nil

-- visualizer setup
local function viz_create()
	if viz_dot then return end

	viz_dot = Drawing.new("Circle")
	viz_dot.Filled   = true
	viz_dot.Color    = Color3.fromRGB(255, 50, 50)
	viz_dot.Opacity  = 1
	viz_dot.Radius   = 5
	viz_dot.NumSides = 32
	viz_dot.ZIndex   = 10
	viz_dot.Visible  = false

	viz_ring = Drawing.new("Circle")
	viz_ring.Filled    = false
	viz_ring.Color     = Color3.fromRGB(255, 255, 255)
	viz_ring.Opacity   = 0.85
	viz_ring.Radius    = 8
	viz_ring.Thickness = 1
	viz_ring.NumSides  = 32
	viz_ring.ZIndex    = 9
	viz_ring.Visible   = false

	viz_label = Drawing.new("Text")
	viz_label.Color        = Color3.fromRGB(255, 220, 220)
	viz_label.Outline      = true
	viz_label.OutlineColor = Vector3.new(0, 0, 0)
	viz_label.Size         = 13
	viz_label.Center       = true
	viz_label.ZIndex       = 11
	viz_label.Visible      = false
end

local function viz_destroy()
	if viz_dot   then viz_dot:Remove();   viz_dot   = nil end
	if viz_ring  then viz_ring:Remove();  viz_ring  = nil end
	if viz_label then viz_label:Remove(); viz_label = nil end
end

local function viz_update(world_pos, part_name)
	if not viz_dot then return end
	if not world_pos then
		viz_dot.Visible = false; viz_ring.Visible = false; viz_label.Visible = false
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then return end
	local screen, visible = camera:WorldToScreenPoint(world_pos)
	if not visible then
		viz_dot.Visible = false; viz_ring.Visible = false; viz_label.Visible = false
		return
	end
	local p = Vector2.new(screen.X, screen.Y)
	viz_dot.Position   = p; viz_dot.Visible   = true
	viz_ring.Position  = p; viz_ring.Visible  = true
	viz_label.Position = Vector2.new(p.X, p.Y - 23)
	viz_label.Text     = part_name or "?"
	viz_label.Visible  = true
end

-- math
local function closest_on_aabb(center, half, point)
	return Vector3.new(
		math.clamp(point.X, center.X - half.X, center.X + half.X),
		math.clamp(point.Y, center.Y - half.Y, center.Y + half.Y),
		math.clamp(point.Z, center.Z - half.Z, center.Z + half.Z)
	)
end

local function closest_on_ray(origin, dir, point)
	local t = math.max(0, (point - origin):Dot(dir))
	return origin + dir * t
end

local function angle_deg(a, b)
	return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
end

-- per frame
local function on_frame()
	if not enabled then return end
	local cam = workspace.CurrentCamera
	if not cam then return end

	local origin = cam.Position
	local look   = cam.CFrame.LookVector

	local best_angle = math.huge
	local best_point = nil
	local best_name  = nil

	for key, data in registry do
		local entry_best_angle = math.huge
		local entry_best_part  = nil
		local entry_best_point = nil
		local entry_best_name  = nil

		for _, part in data.parts do
			local ok1, cf   = pcall(function() return part.CFrame end)
			local ok2, size = pcall(function() return part.Size   end)
			if not ok1 or not ok2 then continue end

			local center = cf.Position
			local half   = size * 0.5
			local ray_pt = closest_on_ray(origin, look, center)
			local aabb   = closest_on_aabb(center, half, ray_pt)
			local dir    = aabb - origin

			if dir.Magnitude < 0.001 then continue end

			local ang = angle_deg(look, dir)
			if ang > FOV then continue end

			if ang < entry_best_angle then
				entry_best_angle = ang
				entry_best_part  = part
				entry_best_point = aabb
				entry_best_name  = part.Name
			end
		end

		if entry_best_part then
			pcall(edit_model_data, { Aimbot_Part = entry_best_part }, key)
			if entry_best_angle < best_angle then
				best_angle = entry_best_angle
				best_point = entry_best_point
				best_name  = entry_best_name
			end
		end
	end

	if viz_on then
		viz_update(best_point, best_name)
	end
end

local function restore_all()
	for key, data in registry do
		pcall(edit_model_data, { Aimbot_Part = data.default_part }, key)
	end
end

-- public api
function cpa.register(key, config)
	assert(type(key) == "string" and #key > 0)
	assert(type(config) == "table" and config.head ~= nil)

	local parts = {}
	for _, f in { "head", "torso", "left_arm", "right_arm", "left_leg", "right_leg" } do
		if config[f] then parts[#parts + 1] = config[f] end
	end

	registry[key] = { parts = parts, default_part = config.default_part or config.head }
end

function cpa.unregister(key)
	local data = registry[key]
	if data then
		pcall(edit_model_data, { Aimbot_Part = data.default_part }, key)
		registry[key] = nil
	end
end

function cpa.set_enabled(state)
	if state == enabled then return end
	enabled = state
	if enabled then
		conn = game:GetService("RunService").Heartbeat:Connect(on_frame)
		send_notification("Closest Point Aim: ON")
	else
		restore_all()
		viz_update(nil, nil)
		if conn then pcall(function() conn:Disconnect() end); conn = nil end
		send_notification("Closest Point Aim: OFF")
	end
end

function cpa.toggle()
	cpa.set_enabled(not enabled)
end

function cpa.is_enabled()
	return enabled
end

function cpa.set_fov(deg)
	assert(type(deg) == "number" and deg > 0 and deg <= 180)
	FOV = deg
end

function cpa.get_fov()
	return FOV
end

function cpa.set_visualizer(state)
	if state == viz_on then return end
	viz_on = state
	if viz_on then
		viz_create()
		send_notification("CPA Visualizer: ON")
	else
		viz_update(nil, nil)
		viz_destroy()
		send_notification("CPA Visualizer: OFF")
	end
end

function cpa.toggle_visualizer()
	cpa.set_visualizer(not viz_on)
end

function cpa.is_visualizer_enabled()
	return viz_on
end

return cpa
