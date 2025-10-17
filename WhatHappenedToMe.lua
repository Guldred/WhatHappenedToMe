--[[
	WhatHappenedToMe.lua
	Core addon logic and event handling
]]--

WHTM = {}
WHTM.buffer = nil
WHTM.inCombat = false
WHTM.lastCombatTime = 0

-- Default settings
WHTM.defaults = {
	bufferSize = 50,
	showOnDeath = true,
	trackHealing = true,
	trackBuffs = true,
	autoShowDelay = 1.0  -- Delay in seconds before showing window on death
}

-- Initialize addon
function WHTM:Initialize()
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
	
	-- Register events
	self:RegisterEvents()
	
	-- Register slash commands
	self:RegisterSlashCommands()
	
	DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00What Happened To Me|r v1.0.0 loaded. Type |cFFFFFF00/whtm|r for commands.")
end

function WHTM:RegisterEvents()
	this:RegisterEvent("PLAYER_DEAD")
	this:RegisterEvent("PLAYER_ALIVE")
	this:RegisterEvent("PLAYER_UNGHOST")
	this:RegisterEvent("PLAYER_ENTERING_WORLD")
	this:RegisterEvent("PLAYER_REGEN_DISABLED")
	this:RegisterEvent("PLAYER_REGEN_ENABLED")
	
	-- Damage events
	this:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")
	this:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES")
	this:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS")
	this:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES")
	this:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE")
	this:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE")
	this:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE")
	this:RegisterEvent("CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF")
	
	-- Healing and buff events
	if WhatHappenedToMeDB.trackHealing then
		this:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS")
		this:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
	end
	
	-- Buff/Debuff changes
	if WhatHappenedToMeDB.trackBuffs then
		this:RegisterEvent("CHAT_MSG_SPELL_AURA_GONE_SELF")
		this:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE")
	end
	
	-- Health tracking
	this:RegisterEvent("UNIT_HEALTH")
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

function WHTM:OnEvent()
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
		self.buffer:Add(self:CreateEntry(arg1, "damage"))
		
	elseif event == "CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES" then
		self.buffer:Add(self:CreateEntry(arg1, "miss"))
		
	elseif event == "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE" then
		self.buffer:Add(self:CreateEntry(arg1, "spell"))
		
	elseif event == "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE" then
		self.buffer:Add(self:CreateEntry(arg1, "spell"))
		
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

function WHTM:OnUpdate(elapsed)
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

function WHTM:UpdateDisplay()
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
		
		for i, entry in ipairs(entries) do
			local timeAgo = currentTime - entry.timestamp
			local timeStr = ""
			
			if timeAgo < 1 then
				timeStr = "now"
			elseif timeAgo < 60 then
				timeStr = string.format("%ds ago", math.floor(timeAgo))
			else
				timeStr = string.format("%dm %ds ago", math.floor(timeAgo / 60), math.floor(timeAgo % 60))
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
	
	WhatHappenedToMeFrameScrollFrameText:SetText(text)
end

function WHTM:RegisterSlashCommands()
	SLASH_WHTM1 = "/whtm"
	SLASH_WHTM2 = "/whathappened"
	
	SlashCmdList["WHTM"] = function(msg)
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
	end
end
