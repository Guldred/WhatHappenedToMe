WHTM = {
	buffer = nil,
	inCombat = false,
	lastCombatTime = 0,
	playerName = nil,
	damageStats = {}
}

local defaults =
{
	bufferSize = 200,
	showOnDeath = true,
	trackHealing = true,
	trackBuffs = true,
	trackMisses = true,
	autoShowDelay = 1.0,
	showDamageNumbers = true,
	relativeToLastEvent = false
}

function WHTM:Initialize()
	if not WhatHappenedToMeDB then WhatHappenedToMeDB = {} end
	
	for k, v in pairs(defaults) do
		if WhatHappenedToMeDB[k] == nil then
			WhatHappenedToMeDB[k] = v
		end
	end
	
	self.buffer = CircularBuffer:New(WhatHappenedToMeDB.bufferSize)
	self.playerName = UnitName("player")
	self:RegisterEvents()
	self:RegisterSlashCommands()
	
	DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00What Happened To Me|r loaded. Type |cFFFFFF00/whtm|r to show window.")
end

function WHTM:RegisterEvents()
	local f = WhatHappenedToMeFrame
	local events = {
		"PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_ENTERING_WORLD",
		"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
		"CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS", "CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES",
		"CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS", "CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES",
		"CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE", "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE",
		"CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE", "CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF",
		"CHAT_MSG_COMBAT_SELF_HITS", "UNIT_HEALTH"
	}
	
	for _, e in ipairs(events) do
		f:RegisterEvent(e)
	end
	
	if WhatHappenedToMeDB.trackHealing then
		f:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS")
		f:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
	end
	
	if WhatHappenedToMeDB.trackBuffs then
		f:RegisterEvent("CHAT_MSG_SPELL_AURA_GONE_SELF")
	end
end

function WHTM:IsMessageAboutPlayer(msg)
	if not msg then return false end
	local lower = string.lower(msg)
	return string.find(lower, "you") or string.find(msg, self.playerName or "")
end

function WHTM:ParseDamageAmount(msg)
	local patterns = {"(%d+) damage", "for (%d+)", "hits .* for (%d+)", "crits .* for (%d+)"}
	for _, pattern in ipairs(patterns) do
		local _, _, amt = string.find(msg, pattern)
		if amt then return tonumber(amt) end
	end
	return 0
end

function WHTM:ParseSource(msg)
	local patterns = {"([%w%s]+)'s ", "^([%w%s]+) hits", "^([%w%s]+) crits"}
	for _, pattern in ipairs(patterns) do
		local _, _, name = string.find(msg, pattern)
		if name then return name end
	end
	return "Unknown"
end

function WHTM:CreateEntry(msg, evType)
	local hp = UnitHealth("player")
    local maxHp = UnitHealthMax("player")
	local pct = maxHp > 0 and math.floor((hp / maxHp) * 100) or 0
	local prevPct = pct
	local dmg, src = 0, nil
	
	if evType == "damage" or evType == "spell" or evType == "dot" then
		dmg = self:ParseDamageAmount(msg)
		src = self:ParseSource(msg)
		
		if dmg > 0 and src then
			if not self.damageStats[src] then
				self.damageStats[src] = {total = 0, count = 0, max = 0}
			end
			local s = self.damageStats[src]
			s.total = s.total + dmg
			s.count = s.count + 1
			if dmg > s.max then s.max = dmg end
		end
		
		-- Vanilla fires events before health update, calculate projected HP
		if dmg > 0 and maxHp > 0 then
			local after = hp - dmg
			if after < 0 then after = 0 end
			pct = math.floor((after / maxHp) * 100)
		end
		
	elseif evType == "heal" then
		dmg = self:ParseDamageAmount(msg)
		if dmg > 0 and maxHp > 0 then
			local after = hp + dmg
			if after > maxHp then after = maxHp
            end
			pct = math.floor((after / maxHp) * 100)
		end
	end
	
	return {
		timestamp = GetTime(),
		wallTime = time(),
		message = msg,
		type = evType,
		health = hp,
		maxHealth = maxHp,
		healthPercent = pct,
		prevHealthPercent = prevPct,
		damage = dmg,
		source = src
	}
end

local function UpdateDisplayIfVisible()
	if WhatHappenedToMeFrame:IsVisible() then WHTM:UpdateDisplay() end
end

local function AddEntry(msg, evType)
	WHTM.buffer:Add(WHTM:CreateEntry(msg, evType))
	UpdateDisplayIfVisible()
end

function WHTM:OnEvent()
	if event == "PLAYER_ENTERING_WORLD" then
		self:Initialize()
	elseif event == "PLAYER_DEAD" then
		AddEntry("You have died.", "death")
		if WhatHappenedToMeDB.showOnDeath then
			self.deathTime = GetTime()
			self.showScheduled = true
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		self.inCombat = true
		self.lastCombatTime = GetTime()
	elseif event == "PLAYER_REGEN_ENABLED" then
		self.inCombat = false
	elseif event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS" then
		AddEntry(arg1, "damage")
	elseif event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES" then
		AddEntry(arg1, "miss")
	elseif event == "CHAT_MSG_COMBAT_SELF_HITS" then
		if string.find(arg1, "You fall") or string.find(arg1, "You drown") or
		   string.find(arg1, "You suffer") or string.find(arg1, "You take") then
			AddEntry(arg1, "damage")
		end
	elseif event == "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS" then
		if self:IsMessageAboutPlayer(arg1) then AddEntry(arg1, "damage") end
	elseif event == "CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES" then
		if self:IsMessageAboutPlayer(arg1) then AddEntry(arg1, "miss") end
	elseif event == "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE" then
		AddEntry(arg1, "spell")
	elseif event == "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE" then
		if self:IsMessageAboutPlayer(arg1) then AddEntry(arg1, "spell") end
	elseif event == "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE" then
		AddEntry(arg1, "dot")
	elseif event == "CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF" then
		AddEntry(arg1, "reflect")
	elseif event == "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS" and WhatHappenedToMeDB.trackHealing then
		AddEntry(arg1, "heal")
	elseif event == "CHAT_MSG_SPELL_SELF_BUFF" and WhatHappenedToMeDB.trackHealing then
		AddEntry(arg1, "heal")
	elseif event == "CHAT_MSG_SPELL_AURA_GONE_SELF" and WhatHappenedToMeDB.trackBuffs then
		AddEntry(arg1, "aura")
	end
end

function WHTM:OnUpdate(elapsed)
	if self.showScheduled and self.deathTime and
	   GetTime() - self.deathTime >= WhatHappenedToMeDB.autoShowDelay then
		self.showScheduled = false
		self.deathTime = nil
		WhatHappenedToMeFrame:Show()
		self:UpdateDisplay()
	end
end


local eventColors = {
	damage = "|cFFFF4444", spell = "|cFFFF4444", dot = "|cFFFF4444",
	heal = "|cFF44FF44", miss = "|cFFAAAAFF", aura = "|cFFFFAA44",
	death = "|cFFFF0000"
}

local function FormatTimestamp(wallTime)
	return date("%H:%M:%S", wallTime)
end

local function FormatRelativeTime(diff)
	if diff < 1 then return string.format("-%.1fs", diff) end
	if diff < 60 then return string.format("-%.1fs", diff) end
	local m, s = math.floor(diff / 60), math.floor(math.mod(diff, 60))
	return string.format("-%dm %ds", m, s)
end

function WHTM:UpdateDisplay()
	if not WhatHappenedToMeFrame:IsVisible() then return end
	
	local entries = self.buffer:GetAll()
	if table.getn(entries) == 0 then
		WhatHappenedToMeFrameScrollFrameScrollChildFrameText:SetText("|cFFFFFF00No combat events recorded.|r\n")
		return
	end
	
	local text = "|cFF00FF00=== Combat Log ===|r\n\n"
	
	for i = 1, table.getn(entries) do
		local e = entries[i]
		local timeStr
		if WhatHappenedToMeDB.relativeToLastEvent then
			local lastTime = entries[table.getn(entries)].timestamp
			timeStr = FormatRelativeTime(lastTime - e.timestamp)
		else
			timeStr = FormatTimestamp(e.wallTime or time())
		end
		local color = eventColors[e.type] or "|cFFFFFFFF"
		local dmgStr = (e.damage and e.damage > 0 and WhatHappenedToMeDB.showDamageNumbers) and 
		               string.format(" |cFFFF6666[-%d]|r", e.damage) or ""
		local hpStr = (e.prevHealthPercent and e.prevHealthPercent ~= e.healthPercent) and
		              string.format("(HP: %d%% -> %d%%)", e.prevHealthPercent, e.healthPercent) or
		              string.format("(HP: %d%%)", e.healthPercent)
		
		text = text .. string.format("[%s] %s%s|r%s %s\n", timeStr, color, e.message, dmgStr, hpStr)
	end
	
	local tf = WhatHappenedToMeFrameScrollFrameScrollChildFrameText
	tf:SetText(text)
	WhatHappenedToMeFrameScrollFrameScrollChildFrame:SetHeight(tf:GetHeight())
	
	local sf = WhatHappenedToMeFrameScrollFrame
	sf:UpdateScrollChildRect()
	sf:SetVerticalScroll(sf:GetVerticalScrollRange())
end


function WHTM:RegisterSlashCommands()
	SLASH_WHTM1 = "/whtm"
	SLASH_WHTM2 = "/whathappened"
	
	SlashCmdList["WHTM"] = function(msg)
		local cmd = string.lower(msg)
		local frame = WhatHappenedToMeFrame
		
		if cmd == "show" or cmd == "" then
			frame:Show()
			WHTM:UpdateDisplay()
		elseif cmd == "hide" or cmd == "close" then
			frame:Hide()
		elseif cmd == "toggle" then
			if frame:IsVisible() then frame:Hide() else frame:Show(); WHTM:UpdateDisplay() end
		elseif cmd == "clear" then
			WHTM.buffer:Clear()
			WHTM.damageStats = {}
			DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00WHTM:|r Log cleared.")
			WHTM:UpdateDisplay()
		elseif cmd == "relative" then
			WhatHappenedToMeDB.relativeToLastEvent = not WhatHappenedToMeDB.relativeToLastEvent
			DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00WHTM:|r Relative time " .. 
				(WhatHappenedToMeDB.relativeToLastEvent and "enabled" or "disabled") .. ".")
			WHTM:UpdateDisplay()
		elseif string.find(cmd, "^buffer") then
			local _, _, size = string.find(cmd, "^buffer%s*size?%s+(%d+)")
			if size then
				size = tonumber(size)
				if size >= 10 and size <= 1000 then
					local old = WHTM.buffer:GetAll()
					WhatHappenedToMeDB.bufferSize = size
					WHTM.buffer = CircularBuffer:New(size)
					for i = math.max(1, table.getn(old) - size + 1), table.getn(old) do
						WHTM.buffer:Add(old[i])
					end
					DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00WHTM:|r Buffer size set to " .. size .. ".")
					WHTM:UpdateDisplay()
				else
					DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000Buffer size must be 10-1000.|r")
				end
			else
				DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00Buffer size:|r " .. WhatHappenedToMeDB.bufferSize)
			end
		elseif cmd == "help" then
			local help = {
				"|cFF00FF00WHTM Commands:|r",
				"|cFFFFFF00/whtm [show]|r - Show window",
				"|cFFFFFF00/whtm hide|r - Hide window",
				"|cFFFFFF00/whtm toggle|r - Toggle window",
				"|cFFFFFF00/whtm relative|r - Toggle relative time",
				"|cFFFFFF00/whtm buffersize [n]|r - Set buffer size (10-1000)",
				"|cFFFFFF00/whtm clear|r - Clear log"
			}
			for _, line in ipairs(help) do
				DEFAULT_CHAT_FRAME:AddMessage(line)
			end
		else
			DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000Unknown command.|r Type |cFFFFFF00/whtm help|r")
		end
	end
end
