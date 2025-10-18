--[[
	WhatHappenedToMe.lua
	Core addon logic and event handling
]]--

WHTM = {}
WHTM.buffer = nil
WHTM.inCombat = false
WHTM.lastCombatTime = 0
WHTM.playerName = nil
WHTM.damageStats = {}

-- Error handler
function WHTM:HandleError(funcName, err)
	DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[WHTM Error]|r " .. funcName .. ": " .. tostring(err))
end

-- Default settings
WHTM.defaults = {
	bufferSize = 200,
	showOnDeath = true,
	trackHealing = true,
	trackBuffs = true,
	trackMisses = true,
	autoShowDelay = 1.0,
	showDamageNumbers = true,
	relativeToLastEvent = false
}

-- Initialize addon
function WHTM:InitializeInternal()
	-- Load saved variables or use defaults
	if not WhatHappenedToMeDB then
		WhatHappenedToMeDB = {}
	end
	
	for key, value in pairs(self.defaults) do
		if WhatHappenedToMeDB[key] == nil then
			WhatHappenedToMeDB[key] = value
		end
	end
	
	-- Create circular buffer
	self.buffer = CircularBuffer:New(WhatHappenedToMeDB.bufferSize)
	
	-- Cache player name for filtering
	self.playerName = UnitName("player")
	
	-- Register events
	self:RegisterEvents()
	
	-- Register slash commands
	self:RegisterSlashCommands()
	
	DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00What Happened To Me|r loaded. Type |cFFFFFF00/whtm|r to show window.")
end

function WHTM:Initialize()
	local success, err = pcall(function() WHTM:InitializeInternal() end)
	if not success then
		DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[WHTM Error]|r Failed to initialize: " .. tostring(err))
	end
end

function WHTM:RegisterEvents()
	local frame = WhatHappenedToMeFrame
	frame:RegisterEvent("PLAYER_DEAD")
	frame:RegisterEvent("PLAYER_ALIVE")
	frame:RegisterEvent("PLAYER_UNGHOST")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:RegisterEvent("PLAYER_REGEN_DISABLED")
	frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	
	-- Damage events
	frame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")
	frame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES")
	frame:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS")
	frame:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES")
	frame:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE")
	frame:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE")
	frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE")
	frame:RegisterEvent("CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF")
	
	-- Environmental damage (falling, drowning, fire)
	frame:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
	
	-- Healing and buff events
	if WhatHappenedToMeDB.trackHealing then
		frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS")
		frame:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
	end
	
	-- Buff/Debuff changes
	if WhatHappenedToMeDB.trackBuffs then
		frame:RegisterEvent("CHAT_MSG_SPELL_AURA_GONE_SELF")
		frame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE")
	end
	
	-- Health tracking
	frame:RegisterEvent("UNIT_HEALTH")
end

function WHTM:IsMessageAboutPlayer(message)
	if not message then
		return false
	end
	
	-- Check if message contains "you" or "your" (case-insensitive)
	local lowerMsg = string.lower(message)
	if string.find(lowerMsg, "you") or string.find(lowerMsg, "your") then
		return true
	end
	
	-- Check if message contains player name (using cached name)
	if self.playerName and string.find(message, self.playerName) then
		return true
	end
	
	return false
end

function WHTM:ParseDamageAmount(message)
	-- Try to extract damage number from message
	-- Using string.gsub for Lua 5.0 compatibility
	local damage = 0
	
	-- Try pattern: "X damage"
	local _, _, amount = string.find(message, "(%d+) damage")
	if amount then
		return tonumber(amount)
	end
	
	-- Try pattern: "for X"
	_, _, amount = string.find(message, "for (%d+)")
	if amount then
		return tonumber(amount)
	end
	
	-- Try pattern: "hits ... for X"
	_, _, amount = string.find(message, "hits .* for (%d+)")
	if amount then
		return tonumber(amount)
	end
	
	-- Try pattern: "crits ... for X"
	_, _, amount = string.find(message, "crits .* for (%d+)")
	if amount then
		return tonumber(amount)
	end
	
	return damage
end

function WHTM:ParseSource(message)
	-- Try to extract the source/attacker name
	-- Using string.find for Lua 5.0 compatibility
	local source = "Unknown"
	
	-- Check for possessive form "Name's"
	local _, _, possessive = string.find(message, "([%w%s]+)'s ")
	if possessive then
		return possessive
	end
	
	-- Check for direct action "Name hits"
	_, _, possessive = string.find(message, "^([%w%s]+) hits")
	if possessive then
		return possessive
	end
	
	-- Check for "Name crits"
	_, _, possessive = string.find(message, "^([%w%s]+) crits")
	if possessive then
		return possessive
	end
	
	return source
end

function WHTM:CreateEntry(message, eventType)
	local currentHealth = UnitHealth("player")
	local maxHealth = UnitHealthMax("player")
	local healthPercent = 0
	local prevHealthPercent = 0
	
	if maxHealth > 0 then
		healthPercent = math.floor((currentHealth / maxHealth) * 100)
	end
	
	local damage = 0
	local source = nil
	
	-- Parse damage amount and source for damage events
	if eventType == "damage" or eventType == "spell" or eventType == "dot" then
		damage = self:ParseDamageAmount(message)
		source = self:ParseSource(message)
		
		-- Track damage stats
		if damage > 0 and source then
			if not self.damageStats[source] then
				self.damageStats[source] = {total = 0, count = 0, max = 0}
			end
			self.damageStats[source].total = self.damageStats[source].total + damage
			self.damageStats[source].count = self.damageStats[source].count + 1
			if damage > self.damageStats[source].max then
				self.damageStats[source].max = damage
			end
		end
		
		-- currentHealth is BEFORE damage in WoW 1.12 (event fires before health update)
		-- Calculate health AFTER damage
		prevHealthPercent = healthPercent  -- Before damage
		if damage > 0 and maxHealth > 0 then
			local afterHealth = currentHealth - damage
			if afterHealth < 0 then afterHealth = 0 end
			healthPercent = math.floor((afterHealth / maxHealth) * 100)
		end
		
	elseif eventType == "heal" then
		-- Parse heal amount
		damage = self:ParseDamageAmount(message)
		
		-- currentHealth is BEFORE heal
		-- Calculate health AFTER heal
		prevHealthPercent = healthPercent  -- Before heal
		if damage > 0 and maxHealth > 0 then
			local afterHealth = currentHealth + damage
			if afterHealth > maxHealth then afterHealth = maxHealth end
			healthPercent = math.floor((afterHealth / maxHealth) * 100)
		end
		
	else
		-- For non-damage/heal events, no health change
		prevHealthPercent = healthPercent
	end
	
	return {
		timestamp = GetTime(),
		message = message,
		type = eventType,
		health = currentHealth,
		maxHealth = maxHealth,
		healthPercent = healthPercent,
		prevHealthPercent = prevHealthPercent,
		damage = damage,
		source = source
	}
end

local function UpdateDisplayIfVisible()
	if WhatHappenedToMeFrame:IsVisible() then
		WHTM:UpdateDisplay()
	end
end

function WHTM:OnEventInternal()
	if event == "PLAYER_ENTERING_WORLD" then
		self:Initialize()
		
	elseif event == "PLAYER_DEAD" then
		-- Record death event
		self.buffer:Add(self:CreateEntry("You have died.", "death"))

        UpdateDisplayIfVisible()
		
		if WhatHappenedToMeDB.showOnDeath then
			-- Schedule window to show after a short delay
			self.deathTime = GetTime()
			self.showScheduled = true
		end
		
	elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
		-- Player was resurrected
		
	elseif event == "PLAYER_REGEN_DISABLED" then
		self.inCombat = true
		self.lastCombatTime = GetTime()
		
	elseif event == "PLAYER_REGEN_ENABLED" then
		self.inCombat = false
		
	elseif event == "UNIT_HEALTH" and arg1 == "player" then
		-- Health changed, but we'll track this with combat events
		
	-- Damage events
	elseif event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS" then
		self.buffer:Add(self:CreateEntry(arg1, "damage"))
        UpdateDisplayIfVisible()
		
	elseif event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES" then
		self.buffer:Add(self:CreateEntry(arg1, "miss"))
        UpdateDisplayIfVisible()
		
	elseif event == "CHAT_MSG_COMBAT_SELF_HITS" then
		-- Environmental damage (falling, drowning, fire, etc.)
		-- Filter: Only track self-damage, not damage TO targets
		-- Self-damage patterns: "You fall", "You drown", "You are afflicted", "You suffer"
		-- Outgoing damage patterns: "You hit", "You crit" (followed by target name)
		local isSelfDamage = string.find(arg1, "You fall") or 
		                     string.find(arg1, "You drown") or 
		                     string.find(arg1, "You are afflicted") or
		                     string.find(arg1, "You suffer") or
		                     string.find(arg1, "You lose") or
		                     string.find(arg1, "You take")
		
		if isSelfDamage then
			self.buffer:Add(self:CreateEntry(arg1, "damage"))
            UpdateDisplayIfVisible()
		end
		
	elseif event == "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS" then
		if self:IsMessageAboutPlayer(arg1) then
			self.buffer:Add(self:CreateEntry(arg1, "damage"))
            UpdateDisplayIfVisible()
		end
		
	elseif event == "CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES" then
		if self:IsMessageAboutPlayer(arg1) then
			self.buffer:Add(self:CreateEntry(arg1, "miss"))
            UpdateDisplayIfVisible()
		end
		
	elseif event == "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE" then
		self.buffer:Add(self:CreateEntry(arg1, "spell"))
        UpdateDisplayIfVisible()
		
	elseif event == "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE" then
		if self:IsMessageAboutPlayer(arg1) then
			self.buffer:Add(self:CreateEntry(arg1, "spell"))
            UpdateDisplayIfVisible()
		end
		
	elseif event == "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE" then
		-- DoTs and debuffs
		self.buffer:Add(self:CreateEntry(arg1, "dot"))
        UpdateDisplayIfVisible()
		
	elseif event == "CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF" then
		self.buffer:Add(self:CreateEntry(arg1, "reflect"))
        UpdateDisplayIfVisible()
		
	-- Healing events
	elseif event == "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS" then
		if WhatHappenedToMeDB.trackHealing then
			self.buffer:Add(self:CreateEntry(arg1, "heal"))
            UpdateDisplayIfVisible()
		end
		
	elseif event == "CHAT_MSG_SPELL_SELF_BUFF" then
		if WhatHappenedToMeDB.trackHealing then
			self.buffer:Add(self:CreateEntry(arg1, "heal"))
            UpdateDisplayIfVisible()
		end
		
	-- Buff/Debuff changes
	elseif event == "CHAT_MSG_SPELL_AURA_GONE_SELF" then
		if WhatHappenedToMeDB.trackBuffs then
			self.buffer:Add(self:CreateEntry(arg1, "aura"))
            UpdateDisplayIfVisible()
		end
	end
end

function WHTM:OnEvent()
	local success, err = pcall(function() WHTM:OnEventInternal() end)
	if not success then
		self:HandleError("OnEvent", err)
	end
end

function WHTM:OnUpdateInternal(elapsed)
	-- Check if we need to show the window after death
	if self.showScheduled and self.deathTime then
		if GetTime() - self.deathTime >= WhatHappenedToMeDB.autoShowDelay then
			self.showScheduled = false
			self.deathTime = nil
			WhatHappenedToMeFrame:Show()
			self:UpdateDisplay()
		end
	end
end

function WHTM:OnUpdate(elapsed)
	local success, err = pcall(function() WHTM:OnUpdateInternal(elapsed) end)
	if not success then
		self:HandleError("OnUpdate", err)
	end
end


function WHTM:UpdateDisplayInternal()
	if not WhatHappenedToMeFrame:IsVisible() then
		return
	end
	
	local text = ""
	local entries = self.buffer:GetAll()
	local referenceTime = GetTime()
	
	-- Use last event time if relative mode is enabled
	if WhatHappenedToMeDB.relativeToLastEvent and table.getn(entries) > 0 then
		referenceTime = entries[table.getn(entries)].timestamp
	end
	
	if table.getn(entries) == 0 then
		text = "|cFFFFFF00No combat events recorded.|r\n"
	else
		text = "|cFF00FF00=== Combat Log ===|r\n\n"
		
		for i = 1, table.getn(entries) do
			local entry = entries[i]
			local timeDiff = referenceTime - entry.timestamp
			local timeStr = ""
			
			if WhatHappenedToMeDB.relativeToLastEvent then
				-- Show time before last event
				if timeDiff < 1 then
					timeStr = "0s"
				elseif timeDiff < 60 then
					timeStr = string.format("-%ds", math.floor(timeDiff))
				else
					timeStr = string.format("-%dm %ds", math.floor(timeDiff / 60), math.floor(math.mod(timeDiff, 60)))
				end
			else
				-- Show time ago from now
				if timeDiff < 1 then
					timeStr = "now"
				elseif timeDiff < 60 then
					timeStr = string.format("%ds ago", math.floor(timeDiff))
				else
					timeStr = string.format("%dm %ds ago", math.floor(timeDiff / 60), math.floor(math.mod(timeDiff, 60)))
				end
			end
			
			-- Color code by type
			local color = "|cFFFFFFFF"
			if entry.type == "damage" or entry.type == "spell" or entry.type == "dot" then
				color = "|cFFFF4444"  -- Red for damage
			elseif entry.type == "heal" then
				color = "|cFF44FF44"  -- Green for healing
			elseif entry.type == "miss" then
				color = "|cFFAAAAFF"  -- Light blue for misses
			elseif entry.type == "aura" then
				color = "|cFFFFAA44"  -- Orange for auras
			elseif entry.type == "death" then
				color = "|cFFFF0000"  -- Bright red for death
			end
			
			local damageStr = ""
			if entry.damage and entry.damage > 0 and WhatHappenedToMeDB.showDamageNumbers then
				damageStr = string.format(" |cFFFF6666[-%d]|r", entry.damage)
			end
			
			-- Health display - show transition only if percentages are different
			local healthStr = ""
			if entry.prevHealthPercent and entry.prevHealthPercent ~= entry.healthPercent then
				healthStr = string.format("(HP: %d%% -> %d%%)", entry.prevHealthPercent, entry.healthPercent)
			else
				healthStr = string.format("(HP: %d%%)", entry.healthPercent)
			end
			
			local line = string.format("[%s] %s%s|r%s %s\n", 
				timeStr, 
				color, 
				entry.message,
				damageStr,
				healthStr
			)
			
			text = text .. line
		end
	end
	
	local textFrame = WhatHappenedToMeFrameScrollFrameScrollChildFrameText
	textFrame:SetText(text)
	
	-- Set the height of the text frame to enable scrolling
	local textHeight = textFrame:GetHeight()
	local scrollChildFrame = WhatHappenedToMeFrameScrollFrameScrollChildFrame
	scrollChildFrame:SetHeight(textHeight)
	
	-- Update the scroll frame
	local scrollFrame = WhatHappenedToMeFrameScrollFrame
	scrollFrame:UpdateScrollChildRect()
	
	-- Auto-scroll to the bottom
	local maxScroll = scrollFrame:GetVerticalScrollRange()
	scrollFrame:SetVerticalScroll(maxScroll)
end

function WHTM:UpdateDisplay()
	local success, err = pcall(function() WHTM:UpdateDisplayInternal() end)
	if not success then
		self:HandleError("UpdateDisplay", err)
	end
end


function WHTM:RegisterSlashCommands()
	SLASH_WHTM1 = "/whtm"
	SLASH_WHTM2 = "/whathappened"
	
	SlashCmdList["WHTM"] = function(msg)
		local success, err = pcall(function()
			local command = string.lower(msg)
			
			if command == "show" or command == "" then
				WhatHappenedToMeFrame:Show()
				WHTM:UpdateDisplay()
				
			elseif command == "hide" or command == "close" then
				WhatHappenedToMeFrame:Hide()
				
			elseif command == "clear" then
				WHTM.buffer:Clear()
				WHTM.damageStats = {}
				DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00What Happened To Me:|r Combat log and stats cleared.")
				WHTM:UpdateDisplay()
				
			elseif command == "toggle" then
				if WhatHappenedToMeFrame:IsVisible() then
					WhatHappenedToMeFrame:Hide()
				else
					WhatHappenedToMeFrame:Show()
					WHTM:UpdateDisplay()
				end
				
			elseif command == "relative" then
				WhatHappenedToMeDB.relativeToLastEvent = not WhatHappenedToMeDB.relativeToLastEvent
				local status = WhatHappenedToMeDB.relativeToLastEvent and "enabled" or "disabled"
				DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00What Happened To Me:|r Relative time to last event " .. status .. ".")
				WHTM:UpdateDisplay()
				
			elseif string.find(command, "^buffersize") or string.find(command, "^buffer") then
				local _, _, sizeStr = string.find(command, "^buffer%s*size?%s+(%d+)")
				if sizeStr then
					local newSize = tonumber(sizeStr)
					if newSize and newSize >= 10 and newSize <= 1000 then
						-- Save old entries
						local oldEntries = WHTM.buffer:GetAll()
						
						-- Update buffer size
						WhatHappenedToMeDB.bufferSize = newSize
						WHTM.buffer = CircularBuffer:New(newSize)
						
						-- Restore entries (up to new size)
						local startIndex = math.max(1, table.getn(oldEntries) - newSize + 1)
						for i = startIndex, table.getn(oldEntries) do
							WHTM.buffer:Add(oldEntries[i])
						end
						
						DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00What Happened To Me:|r Buffer size set to " .. newSize .. ".")
						WHTM:UpdateDisplay()
					else
						DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000Buffer size must be between 10 and 1000.|r")
					end
				else
					DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00Current buffer size:|r " .. WhatHappenedToMeDB.bufferSize)
				end
				
			elseif command == "help" then
				DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00What Happened To Me Commands:|r")
				DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00/whtm show|r - Show the window")
				DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00/whtm hide|r - Hide the window")
				DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00/whtm toggle|r - Toggle the window")
				DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00/whtm relative|r - Toggle relative time mode")
				DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00/whtm buffersize [number]|r - Set/view buffer size (10-1000)")
				DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00/whtm clear|r - Clear all recorded events")
				
			else
				DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000Unknown command. Type|r |cFFFFFF00/whtm help|r |cFFFF0000for available commands.|r")
			end
		end)
		
		if not success then
			WHTM:HandleError("SlashCommand", err)
		end
	end
end
