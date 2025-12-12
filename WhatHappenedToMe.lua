WHTM = {
	buffer = nil,
	inCombat = false,
	lastCombatTime = 0,
	playerName = nil,
	damageStats = {},
	initialized = false,
	viewingDeathIndex = nil,
	deathHistory = {}
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
	if self.initialized then return end
	
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
	self.initialized = true
	
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
		self.deathTime = GetTime()
		self.snapshotScheduled = true
		if WhatHappenedToMeDB.showOnDeath then
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

local SNAPSHOT_DELAY = 1.0

function WHTM:OnUpdate(elapsed)
	if self.deathTime then
		local timeSinceDeath = GetTime() - self.deathTime
		
		if self.snapshotScheduled and timeSinceDeath >= SNAPSHOT_DELAY then
			self.snapshotScheduled = false
			self:SaveDeathSnapshot()
		end
		
		if self.showScheduled and timeSinceDeath >= WhatHappenedToMeDB.autoShowDelay then
			self.showScheduled = false
			self.deathTime = nil
			WhatHappenedToMeFrame:Show()
			self:UpdateDisplay()
		end
	end
end

function WHTM:SaveDeathSnapshot()
	local entries = self.buffer:GetAll()
	if not entries or table.getn(entries) == 0 then
		return
	end
	
	local snapshot = {
		timestamp = time(),
		entries = {}
	}
	
	for i = 1, table.getn(entries) do
		local e = entries[i]
		if e then
			table.insert(snapshot.entries, {
				timestamp = e.timestamp,
				wallTime = e.wallTime,
				message = e.message,
				type = e.type,
				health = e.health,
				maxHealth = e.maxHealth,
				healthPercent = e.healthPercent,
				prevHealthPercent = e.prevHealthPercent,
				damage = e.damage,
				source = e.source
			})
		end
	end
	
	if table.getn(snapshot.entries) > 0 then
		table.insert(self.deathHistory, snapshot)
		DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00WHTM:|r Death #" .. table.getn(self.deathHistory) .. " recorded.")
	end
end

function WHTM:GetDeathHistory()
	return self.deathHistory
end

function WHTM:ViewDeath(index)
	local history = self:GetDeathHistory()
	if index < 1 or index > table.getn(history) then
		DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000WHTM:|r Invalid death index.")
		return
	end
	
	self.viewingDeathIndex = index
	WhatHappenedToMeFrame:Show()
	self:UpdateDisplay()
end

function WHTM:ViewLiveCombat()
	self.viewingDeathIndex = nil
	self:UpdateDisplay()
end

function WHTM:InitDeathDropdown()
	local dropdown = WhatHappenedToMeFrameToolbarDeathDropDown
	if not dropdown then return end
	
	UIDropDownMenu_Initialize(dropdown, function()
		local info = {}
		
		info.text = "Live"
		info.value = "live"
		info.func = function()
			WHTM.viewingDeathIndex = nil
			UIDropDownMenu_SetSelectedValue(dropdown, "live")
			WHTM:UpdateDisplay()
		end
		info.checked = (WHTM.viewingDeathIndex == nil)
		UIDropDownMenu_AddButton(info)
		
		local history = WHTM:GetDeathHistory()
		for i = 1, table.getn(history) do
			local death = history[i]
			local timeStr = date("%H:%M", death.timestamp)
			local deathIndex = i
			
			info = {}
			info.text = "Death " .. timeStr
			info.value = deathIndex
			info.func = function()
				WHTM.viewingDeathIndex = deathIndex
				UIDropDownMenu_SetSelectedValue(dropdown, deathIndex)
				WHTM:UpdateDisplay()
			end
			info.checked = (WHTM.viewingDeathIndex == deathIndex)
			UIDropDownMenu_AddButton(info)
		end
	end)
	
	UIDropDownMenu_SetWidth(120, dropdown)
	
	if self.viewingDeathIndex then
		UIDropDownMenu_SetSelectedValue(dropdown, self.viewingDeathIndex)
		local history = self:GetDeathHistory()
		local death = history[self.viewingDeathIndex]
		if death then
			UIDropDownMenu_SetText("Death " .. date("%H:%M", death.timestamp), dropdown)
		end
	else
		UIDropDownMenu_SetSelectedValue(dropdown, "live")
		UIDropDownMenu_SetText("Live", dropdown)
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
	
	self:InitDeathDropdown()
	
	local entries
	local headerText
	
	if self.viewingDeathIndex then
		local history = self:GetDeathHistory()
		local death = history[self.viewingDeathIndex]
		if death then
			entries = death.entries
			local timeStr = date("%H:%M:%S", death.timestamp)
			headerText = string.format("|cFFFF4444=== Death #%d (%s) ===|r\n\n", 
				self.viewingDeathIndex, timeStr)
		else
			entries = {}
		end
	else
		entries = self.buffer:GetAll()
		headerText = "|cFF00FF00=== Live Combat Log ===|r\n\n"
	end
	
	if table.getn(entries) == 0 then
		WhatHappenedToMeFrameScrollFrameScrollChildFrameText:SetText("|cFFFFFF00No combat events recorded.|r\n")
		return
	end
	
	local text = headerText
	
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

WHTM.exportChannel = "SAY"

function WHTM:ShowExportDialog()
	local dialog = WhatHappenedToMeExportDialog
	
	UIDropDownMenu_Initialize(WhatHappenedToMeExportDialogChannelDropDown, function()
		local info = {}
		local channels = {
			{text = "Say", value = "SAY"},
			{text = "Party", value = "PARTY"},
			{text = "Raid", value = "RAID"},
			{text = "Guild", value = "GUILD"},
			{text = "Whisper", value = "WHISPER"}
		}
		
		for _, channel in ipairs(channels) do
			local channelValue = channel.value
			info.text = channel.text
			info.value = channelValue
			info.func = function()
				WHTM.exportChannel = channelValue
				UIDropDownMenu_SetSelectedValue(WhatHappenedToMeExportDialogChannelDropDown, channelValue)
				
				local targetInput = WhatHappenedToMeExportDialogTargetInput
				local targetLabel = WhatHappenedToMeExportDialogTargetLabel
				if channelValue == "WHISPER" then
					targetInput:Show()
					targetLabel:Show()
				else
					targetInput:Hide()
					targetLabel:Hide()
				end
			end
			info.checked = (WHTM.exportChannel == channelValue)
			UIDropDownMenu_AddButton(info)
		end
	end)
	
	UIDropDownMenu_SetSelectedValue(WhatHappenedToMeExportDialogChannelDropDown, WHTM.exportChannel)
	UIDropDownMenu_SetWidth(150, WhatHappenedToMeExportDialogChannelDropDown)
	
	dialog:Show()
end

function WHTM:ExportToChat()
	local countInput = WhatHappenedToMeExportDialogCountInput
	local targetInput = WhatHappenedToMeExportDialogTargetInput
	
	local count = tonumber(countInput:GetText()) or 5
	if count < 1 then count = 1 end
	if count > 100 then count = 100 end
	
	local channel = self.exportChannel
	local target = nil
	
	if channel == "WHISPER" then
		target = targetInput:GetText()
		if not target or target == "" then
			DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000WHTM:|r Please enter a whisper target.")
			return
		end
	end
	
	local allEntries
	local sourceLabel
	
	if self.viewingDeathIndex then
		local history = self:GetDeathHistory()
		local death = history[self.viewingDeathIndex]
		if death then
			allEntries = death.entries
			sourceLabel = "Death " .. date("%H:%M", death.timestamp)
		else
			allEntries = {}
		end
	else
		allEntries = self.buffer:GetAll()
		sourceLabel = "Live"
	end
	
	local entries = {}
	for i = math.max(1, table.getn(allEntries) - count + 1), table.getn(allEntries) do
		table.insert(entries, allEntries[i])
	end
	
	if table.getn(entries) == 0 then
		DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000WHTM:|r No events to export.")
		return
	end
	
	for i = 1, table.getn(entries) do
		local e = entries[i]
		local timeStr
		if WhatHappenedToMeDB.relativeToLastEvent then
			local lastTime = entries[table.getn(entries)].timestamp
			timeStr = FormatRelativeTime(lastTime - e.timestamp)
		else
			timeStr = FormatTimestamp(e.wallTime or time())
		end
		
		local dmgStr = (e.damage and e.damage > 0) and string.format(" [-%d]", e.damage) or ""
		local hpStr = (e.prevHealthPercent and e.prevHealthPercent ~= e.healthPercent) and
		              string.format("(HP: %d%%->%d%%)", e.prevHealthPercent, e.healthPercent) or
		              string.format("(HP: %d%%)", e.healthPercent)
		
		local msg = string.format("[%s] %s%s %s", timeStr, e.message, dmgStr, hpStr)
		
		if channel == "WHISPER" then
			SendChatMessage(msg, channel, nil, target)
		else
			SendChatMessage(msg, channel)
		end
	end
	
	WhatHappenedToMeExportDialog:Hide()
	DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00WHTM:|r Exported " .. table.getn(entries) .. " events (" .. sourceLabel .. ") to " .. channel .. ".")
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
		elseif cmd == "deaths" then
			local history = WHTM:GetDeathHistory()
			local count = table.getn(history)
			if count == 0 then
				DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00WHTM:|r No deaths recorded this session.")
			else
				DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00WHTM Death History (this session):|r")
				for i = 1, count do
					local d = history[i]
					local timeStr = date("%H:%M:%S", d.timestamp)
					DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cFFFFFF00%d.|r %s - %d events", 
						i, timeStr, table.getn(d.entries)))
				end
				DEFAULT_CHAT_FRAME:AddMessage("Use |cFFFFFF00/whtm death <n>|r or the dropdown to view.")
			end
		elseif string.find(cmd, "^death%s+%d+") then
			local _, _, idx = string.find(cmd, "^death%s+(%d+)")
			if idx then
				WHTM:ViewDeath(tonumber(idx))
			end
		elseif cmd == "live" then
			WHTM:ViewLiveCombat()
			frame:Show()
		elseif cmd == "help" then
			local help = {
				"|cFF00FF00WHTM Commands:|r",
				"|cFFFFFF00/whtm [show]|r - Show window",
				"|cFFFFFF00/whtm hide|r - Hide window",
				"|cFFFFFF00/whtm toggle|r - Toggle window",
				"|cFFFFFF00/whtm relative|r - Toggle relative time",
				"|cFFFFFF00/whtm buffersize [n]|r - Set buffer size (10-1000)",
				"|cFFFFFF00/whtm clear|r - Clear live log",
				"|cFFFFFF00/whtm deaths|r - List deaths (this session)",
				"|cFFFFFF00/whtm death <n>|r - View death #n",
				"|cFFFFFF00/whtm live|r - Return to live combat view"
			}
			for _, line in ipairs(help) do
				DEFAULT_CHAT_FRAME:AddMessage(line)
			end
		else
			DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000Unknown command.|r Type |cFFFFFF00/whtm help|r")
		end
	end
end
