local gc_support = {}

local _registered = {}

local function walk(t, targets, results, visited)
	if visited[t] then return end
	visited[t] = true
	for k, v in pairs(t) do
		if targets[tostring(k)] then
			results[#results + 1] = { key = tostring(k), value = v, type = typeof(v), addr = 0 }
		end
		if type(v) == "table" then
			walk(v, targets, results, visited)
		end
	end
end

local function scan(names)
	local targets, results, visited = {}, {}, {}
	for _, n in names do targets[n] = true end

	pcall(walk, _G, targets, results, visited)

	pcall(function()
		for _, inst in game:GetDescendants() do
			if type(inst.Data) == "table" then
				walk(inst.Data, targets, results, visited)
			end
			for attr, val in pairs(inst:GetAttributes()) do
				if targets[attr] then
					results[#results + 1] = { key = attr, value = val, type = typeof(val), addr = 0 }
				end
			end
		end
	end)

	for _, t in _registered do
		pcall(walk, t, targets, results, visited)
	end

	return results
end

local function apply(pairs_to_set)
	local count, visited = 0, {}

	local function apply_table(t, k, v)
		if visited[t] then return end
		visited[t] = true
		for tk, tv in pairs(t) do
			if tostring(tk) == k and typeof(tv) == typeof(v) then
				t[tk] = v
				count += 1
			end
			if type(tv) == "table" then apply_table(tv, k, v) end
		end
	end

	for k, v in pairs(pairs_to_set) do
		visited = {}
		apply_table(_G, k, v)
		for _, t in _registered do apply_table(t, k, v) end
	end

	pcall(function()
		for _, inst in game:GetDescendants() do
			for attr in pairs(inst:GetAttributes()) do
				if pairs_to_set[attr] ~= nil then
					inst:SetAttribute(attr, pairs_to_set[attr])
					count += 1
				end
			end
		end
	end)

	return count
end

function gc_support.getgc(name)
	return scan(type(name) == "string" and { name } or name)
end

function gc_support.setgc(key, value)
	local p = type(key) == "string" and { [key] = value } or key
	return apply(p)
end

function gc_support.applygc(cache, key, value)
	local p = type(key) == "string" and { [key] = value } or key
	for _, entry in cache do
		if p[entry.key] ~= nil and typeof(p[entry.key]) == entry.type then
			entry.value = p[entry.key]
		end
	end
	return apply(p)
end

function gc_support.register(t)
	assert(type(t) == "table", "register() expects a table")
	_registered[#_registered + 1] = t
end

function gc_support.unregister(t)
	for i, v in _registered do
		if v == t then table.remove(_registered, i) return end
	end
end

return gc_support
