local remote_support = {}

local REMOTE_CLASSES = {
	RemoteEvent      = true,
	RemoteFunction   = true,
	BindableEvent    = true,
	BindableFunction = true,
}

local function collect_all()
	local found = {}
	pcall(function()
		for _, inst in game:GetDescendants() do
			if REMOTE_CLASSES[inst.ClassName] then
				found[#found + 1] = { instance = inst, path = inst:GetFullName(), class = inst.ClassName }
			end
		end
	end)
	return found
end

local function find_instances(name, class_filter)
	local results, lower = {}, name:lower()
	for _, entry in collect_all() do
		local match = entry.instance.Name:lower()
		if (not class_filter or entry.class == class_filter)
			and (match == lower or match:find(lower, 1, true)) then
			results[#results + 1] = entry
		end
	end
	return results
end

local function resolve(name_or_instance, class_name)
	if type(name_or_instance) ~= "string" then return name_or_instance end
	local found = find_instances(name_or_instance, class_name)
	if #found == 0 then
		warn("[remote_support] not found: " .. name_or_instance)
		return nil
	end
	return found[1].instance
end

function remote_support.fire_remote(name_or_instance, ...)
	local remote = resolve(name_or_instance, "RemoteEvent")
	if remote then pcall(function(...) (remote :: any):FireServer(...) end, ...) end
end

function remote_support.fire_remote_at(instance, ...)
	pcall(function(...) (instance :: any):FireServer(...) end, ...)
end

function remote_support.invoke_remote(name_or_instance, ...)
	local remote = resolve(name_or_instance, "RemoteFunction")
	if not remote then return nil end
	local ok, result = pcall(function(...) return (remote :: any):InvokeServer(...) end, ...)
	return ok and result or nil
end

function remote_support.fire_bindable(name_or_instance, ...)
	local b = resolve(name_or_instance, "BindableEvent")
	if b then pcall(function(...) (b :: any):Fire(...) end, ...) end
end

function remote_support.invoke_bindable(name_or_instance, ...)
	local b = resolve(name_or_instance, "BindableFunction")
	if not b then return nil end
	local ok, result = pcall(function(...) return (b :: any):Invoke(...) end, ...)
	return ok and result or nil
end

function remote_support.find(name, class_filter)
	return find_instances(name, class_filter)
end

function remote_support.list(class_filter)
	if not class_filter then return collect_all() end
	local results = {}
	for _, entry in collect_all() do
		if entry.class == class_filter then results[#results + 1] = entry end
	end
	return results
end

function remote_support.spy(name, callback)
	local connections = {}

	for _, entry in find_instances(name, "RemoteEvent") do
		local ok, conn = pcall(function()
			return (entry.instance :: any).OnClientEvent:Connect(function(...)
				callback(entry.instance, ...)
			end)
		end)
		if ok and conn then connections[#connections + 1] = conn end
	end

	for _, entry in find_instances(name, "BindableEvent") do
		local ok, conn = pcall(function()
			return (entry.instance :: any).Event:Connect(function(...)
				callback(entry.instance, ...)
			end)
		end)
		if ok and conn then connections[#connections + 1] = conn end
	end

	return function()
		for _, conn in connections do pcall(function() conn:Disconnect() end) end
		connections = {}
	end
end

function remote_support.spy_all(callback)
	local connections = {}
	for _, entry in collect_all() do
		local inst = entry.instance
		local ok, conn

		if entry.class == "RemoteEvent" then
			ok, conn = pcall(function()
				return (inst :: any).OnClientEvent:Connect(function(...)
					callback(inst, ...)
				end)
			end)
		elseif entry.class == "BindableEvent" then
			ok, conn = pcall(function()
				return (inst :: any).Event:Connect(function(...)
					callback(inst, ...)
				end)
			end)
		end

		if ok and conn then connections[#connections + 1] = conn end
	end

	return function()
		for _, conn in connections do pcall(function() conn:Disconnect() end) end
		connections = {}
	end
end

function remote_support.spy_invoke(name, callback)
	local restores = {}
	for _, entry in find_instances(name, "RemoteFunction") do
		local remote = entry.instance
		local ok, original = pcall(function() return (remote :: any).OnClientInvoke end)
		pcall(function()
			(remote :: any).OnClientInvoke = function(...)
				return callback(remote, ...)
			end
		end)
		restores[#restores + 1] = function()
			pcall(function()
				(remote :: any).OnClientInvoke = ok and original or nil
			end)
		end
	end

	return function()
		for _, r in restores do r() end
		restores = {}
	end
end

return remote_support
