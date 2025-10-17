--[[
	WhatHappenedToMe.lua
	Core addon logic and event handling
]]--

WHTM = {}
WHTM.buffer = nil
WHTM.inCombat = false
WHTM.lastCombatTime = 0
WHTM.playerName = nil

-- Error handler
function WHTM:HandleError(funcName, err)
	DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[WHTM Error]|r " .. funcName .. ": " .. tostring(err))
end

-- Default settings
WHTM.defaults = {
	bufferSize = 50,
	showOnDeath = true,
	trackHealing = true,
	trackBuffs = true,
	autoShowDelay = 1.0  -- Delay in seconds before showing window on death
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
	
	DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00What Happened To Me|r v1.0.0 loaded. Type |cFFFFFF00/whtm|r for commands.")
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

function WHTM:CreateEntry(message, eventType)
	local currentHealth = UnitHealth("player")
	local maxHealth = UnitHealthMax("player")
	local healthPercent = 0
	
	if maxHealth > 0 then
		healthPercent = math.floor((currentHealth / maxHealth) * 100)
	end
	
	return {
		timestamp = GetTime(),
		message = message,
		type = eventType,
		health = currentHealth,
		maxHealth = maxHealth,
		healthPercent = healthPercent
	}
end

function WHTM:OnEventInternal()
	if event == "PLAYER_ENTERING_WORLD" then
		self:Initialize()
		
	elseif event == "PLAYER_DEAD" then
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
		
	elseif event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES" then
		self.buffer:Add(self:CreateEntry(arg1, "miss"))
		
	elseif event == "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS" then
		if self:IsMessageAboutPlayer(arg1) then
			self.buffer:Add(self:CreateEntry(arg1, "damage"))
		end
		
	elseif event == "CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES" then
		if self:IsMessageAboutPlayer(arg1) then
			self.buffer:Add(self:CreateEntry(arg1, "miss"))
		end
		
	elseif event == "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE" then
		self.buffer:Add(self:CreateEntry(arg1, "spell"))
		
	elseif event == "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE" then
		if self:IsMessageAboutPlayer(arg1) then
			self.buffer:Add(self:CreateEntry(arg1, "spell"))
		end
		
	elseif event == "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE" then
		-- DoTs and debuffs
		self.buffer:Add(self:CreateEntry(arg1, "dot"))
		
	elseif event == "CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF" then
		self.buffer:Add(self:CreateEntry(arg1, "reflect"))
		
	-- Healing events
	elseif event == "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS" then
		if WhatHappenedToMeDB.trackHealing then
			self.buffer:Add(self:CreateEntry(arg1, "heal"))
		end
		
	elseif event == "CHAT_MSG_SPELL_SELF_BUFF" then
		if WhatHappenedToMeDB.trackHealing then
			self.buffer:Add(self:CreateEntry(arg1, "heal"))
		end
		
	-- Buff/Debuff changes
	elseif event == "CHAT_MSG_SPELL_AURA_GONE_SELF" then
		if WhatHappenedToMeDB.trackBuffs then
			self.buffer:Add(self:CreateEntry(arg1, "aura"))
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
	
	local entries = self.buffer:GetAll()
	local text = ""
	local currentTime = GetTime()
	
	if table.getn(entries) == 0 then
		text = "|cFFFFFF00No combat events recorded.|r\n"
	else
		text = "|cFF00FF00=== What Happened To Me ===|r\n\n"
		
		for i = 1, table.getn(entries) do
			local entry = entries[i]
			local timeAgo = currentTime - entry.timestamp
			local timeStr = ""
			
			if timeAgo < 1 then
				timeStr = "now"
			elseif timeAgo < 60 then
				timeStr = string.format("%ds ago", math.floor(timeAgo))
			else
				timeStr = string.format("%dm %ds ago", math.floor(timeAgo / 60), math.floor(math.mod(timeAgo, 60)))
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
			end
			
			local line = string.format("[%s] %s%s|r (HP: %d%%)\n", 
				timeStr, 
				color, 
				entry.message, 
				entry.healthPercent
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
	WhatHappenedToMeFrameScrollFrame:UpdateScrollChildRect()
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
				DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00What Happened To Me:|r Combat log cleared.")
				WHTM:UpdateDisplay()
				
			elseif command == "toggle" then
				if WhatHappenedToMeFrame:IsVisible() then
					WhatHappenedToMeFrame:Hide()
				else
					WhatHappenedToMeFrame:Show()
					WHTM:UpdateDisplay()
				end
				
			elseif command == "help" then
				DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00What Happened To Me Commands:|r")
				DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00/whtm show|r - Show the combat log window")
				DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00/whtm hide|r - Hide the combat log window")
				DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00/whtm toggle|r - Toggle the combat log window")
				DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00/whtm clear|r - Clear all recorded events")
				DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00/whtm help|r - Show this help message")
				
			else
				DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000Unknown command. Type|r |cFFFFFF00/whtm help|r |cFFFF0000for available commands.|r")
			end
		end)
		
		if not success then
			WHTM:HandleError("SlashCommand", err)
		end
	end
end
