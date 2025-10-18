CircularBuffer = {}

function CircularBuffer:New(size)
	local buf = {entries = {}, maxSize = size or 50, idx = 1, count = 0}
	setmetatable(buf, self)
	self.__index = self
	return buf
end

function CircularBuffer:Add(entry)
	self.entries[self.idx] = entry
	self.idx = self.idx + 1
	if self.idx > self.maxSize then self.idx = 1 end
	if self.count < self.maxSize then self.count = self.count + 1 end
end

function CircularBuffer:GetAll()
	if self.count == 0 then return {} end
	
	local result = {}
	if self.count < self.maxSize then
		for i = 1, self.count do
			table.insert(result, self.entries[i])
		end
	else
		for i = 0, self.maxSize - 1 do
			local idx = self.idx + i
			if idx > self.maxSize then idx = idx - self.maxSize end
			table.insert(result, self.entries[idx])
		end
	end
	return result
end

function CircularBuffer:GetRecent(n)
	local all = self:GetAll()
	local result = {}
	for i = math.max(1, table.getn(all) - n + 1), table.getn(all) do
		table.insert(result, all[i])
	end
	return result
end

function CircularBuffer:Clear()
	self.entries, self.idx, self.count = {}, 1, 0
end

function CircularBuffer:GetCount()
	return self.count
end
