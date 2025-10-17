--[[
	CircularBuffer.lua
	Circular buffer implementation for storing combat events efficiently
]]--

CircularBuffer = {}

function CircularBuffer:New(maxSize)
	local buffer = {
		entries = {},
		maxSize = maxSize or 50,
		currentIndex = 1,
		count = 0
	}
	setmetatable(buffer, self)
	self.__index = self
	return buffer
end

function CircularBuffer:Add(entry)
	self.entries[self.currentIndex] = entry
	self.currentIndex = self.currentIndex + 1
	
	if self.currentIndex > self.maxSize then
		self.currentIndex = 1
	end
	
	if self.count < self.maxSize then
		self.count = self.count + 1
	end
end

function CircularBuffer:GetAll()
	local result = {}
	
	if self.count == 0 then
		return result
	end
	
	-- If buffer is not full yet, just return entries in order
	if self.count < self.maxSize then
		for i = 1, self.count do
			table.insert(result, self.entries[i])
		end
		return result
	end
	
	-- Buffer is full, return in chronological order
	-- Start from currentIndex (oldest) to currentIndex-1 (newest)
	for i = 0, self.maxSize - 1 do
		local index = self.currentIndex + i
		if index > self.maxSize then
			index = index - self.maxSize
		end
		table.insert(result, self.entries[index])
	end
	
	return result
end

function CircularBuffer:GetRecent(count)
	local all = self:GetAll()
	local result = {}
	local startIndex = math.max(1, table.getn(all) - count + 1)
	
	for i = startIndex, table.getn(all) do
		table.insert(result, all[i])
	end
	
	return result
end

function CircularBuffer:Clear()
	self.entries = {}
	self.currentIndex = 1
	self.count = 0
end

function CircularBuffer:GetCount()
	return self.count
end
