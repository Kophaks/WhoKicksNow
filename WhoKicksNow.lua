local _G = getfenv(0)
local tinsert = table.insert
local getn = table.getn
local strupper = string.upper
local ceil = math.ceil
local floor = math.floor
local strfind = string.find
local gmatch = string.gfind
local format = string.format
local GetTime = GetTime
local GetNumRaidMembers = GetNumRaidMembers
local GetNumPartyMembers = GetNumPartyMembers
local UnitName = UnitName
local UnitClass = UnitClass
local RAID_CLASS_COLORS = RAID_CLASS_COLORS

local MAINBAR_WIDTH = 150
local MAINBAR_HEIGHT = 30
local BAR_WIDTH = 110
local BAR_WIDTH_LOCKED = 150
local BAR_HEIGHT = 20
local BAR_HEIGHT_MAIN = 30
local COOLDOWN_WIDTH = 200
local COOLDOWN_HEIGHT = 20
local ICONF_WIDTH = 40
local ICONF_HEIGHT = 20
local ICON_WIDTH = 20
local ICON_HEIGHT = 20

local debug_level = 0
local NETWORK = true
local PREFIX = 'WhoKicksNow'
local PAUSE = false
local __WKN,__WKN_D1,__WKN_D2
local addon = CreateFrame('Frame')
local CTL = ChatThrottleLib

local party, raid = {},{}
do
	for i=1,MAX_RAID_MEMBERS do
		raid[i] = format("raid%d",i)
	end
	for i=1,MAX_PARTY_MEMBERS do
		party[i] = format("party%d",i)
	end
end
local me = UnitName('player')

addon:SetScript('OnEvent', function()
	this[event](this)
end)

addon.Network = {
	Cooldown = 'C',
	Version = 'VERSION',
	VersionCheck = 'VER_REQ',
	VersionCheckReply = 'VER_INF',
}

local SKILLS = {
	{name='Kick', cooldown=10, texture=[[Interface\Icons\Ability_Kick]]},
	{name='Cheap Shot', useHook=true, cooldown=1, texture=[[Interface\Icons\Ability_CheapShot]]},
	{name='Kidney Shot', cooldown=20, texture=[[Interface\Icons\Ability_Rogue_KidneyShot]]},
	{name='Gouge', cooldown=10, texture=[[Interface\Icons\Ability_Gouge]]},
	{name='Pummel', cooldown=10, texture=[[Interface\Icons\INV_Gauntlets_04]]},
	{name='Shield Bash', cooldown=12, texture=[[Interface\Icons\Ability_Warrior_ShieldBash]]},
}

local CLASSES = {
	ROGUE = true,
	WARRIOR = true,
}
local SPELLBOOK = {}

addon:RegisterEvent('VARIABLES_LOADED')
addon:RegisterEvent('PLAYER_ENTERING_WORLD')
addon:RegisterEvent('PLAYER_LEAVING_WORLD')

StaticPopupDialogs["WKN_UPDATEPOPUP"] = {
	text = 'Copy link to the clipboard',
	button1 = TEXT(ACCEPT),
	button2 = TEXT(CANCEL),
	hasEditBox = 1,
	maxLetters = 256,
	hasWideEditBox = 1,
	OnAccept = function()
	end,
	OnShow = function()
		this.editBox = getglobal(this:GetName().."WideEditBox")
	end,
	OnHide = function()
		if ( ChatFrameEditBox:IsVisible() ) then
			ChatFrameEditBox:SetFocus()
		end
	end,
	EditBoxOnEnterPressed = function()
		this:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function()
		this:GetParent():Hide()
	end,
	timeout = 0,
	exclusive = 1,
	whileDead = 1,
	hideOnEscape = 1
}

function addon:RegisterCombatEvents()
	addon:RegisterEvent('CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS')
	addon:RegisterEvent('CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF')
	addon:RegisterEvent('CHAT_MSG_SPELL_SELF_DAMAGE')
	addon:RegisterEvent('CHAT_MSG_SPELL_PARTY_DAMAGE')
	addon:RegisterEvent('CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE')
	addon:RegisterEvent('SPELL_UPDATE_COOLDOWN')
	if NETWORK then
		addon:RegisterEvent('CHAT_MSG_ADDON')
	end
	self.SpellWatcher:RegisterEvent('SPELLCAST_STOP')
end

function addon:UnregisterCombatEvents()
	addon:UnregisterEvent('CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS')
	addon:UnregisterEvent('CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF')
	addon:UnregisterEvent('CHAT_MSG_SPELL_SELF_DAMAGE')
	addon:UnregisterEvent('CHAT_MSG_SPELL_PARTY_DAMAGE')
	addon:UnregisterEvent('CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE')
	addon:UnregisterEvent('SPELL_UPDATE_COOLDOWN')
	if NETWORK then
		addon:UnregisterEvent('CHAT_MSG_ADDON')
	end
	self.SpellWatcher:UnregisterEvent('SPELLCAST_STOP')
end

function addon:GetSkillInfo(skill, rank)
	if not skill then
		return
	end
	if not rank then
		skill = gsub(skill, '%(.+%)', '')
	end
	for i=1, getn(SKILLS) do
		if SKILLS[i].name == skill then
			return SKILLS[i]
		end
	end
end

function addon:GetAnchorPoint()
	local UI_Width, UI_Height, width, height, top, right, bottom, left, UI_scale, frame_scale
	UI_scale = UIParent:GetEffectiveScale()
	frame_scale = self.main_frame:GetEffectiveScale()
	
	UI_Width = floor(UIParent:GetWidth()+0.5) -- UI_ROOT
	UI_Height = floor(UIParent:GetHeight()+0.5) -- UI_ROOT
	width = floor(self.main_frame:GetWidth()+0.5) -- UI_ROOT
	height = floor(self.main_frame:GetHeight()+0.5) -- UI_ROOT
	-- multiply by effective scale to translate to UI_ROOT values, so comparisons have meaning
	top = floor((self.main_frame:GetTop()*frame_scale)+0.5) -- Effective Scaled 
	right = floor((self.main_frame:GetRight()*frame_scale)+0.5) -- Effective Scaled
	bottom = floor((self.main_frame:GetBottom()*frame_scale)+0.5) -- Effective Scaled
	left = floor((self.main_frame:GetLeft()*frame_scale)+0.5) -- Effective Scaled
	
	if (debug_level > 0) then self:print(format('UI: %f x %f', UI_Width, UI_Height ), 1) end
	if (debug_level > 0) then self:print(format('bottom: %f, left: %f, right: %f, top: %f', bottom, left, right, top ), 1) end
	
	local is_top, is_right, is_bottom, is_left
	
	if left + width/2 < UI_Width/2 then
		is_left = true
	end
	if right + width/2 > UI_Width/2 then
		right =  -(UI_Width-right)
		is_right = true
	end
	if top + height/2 > UI_Height/2 then
		top = -(UI_Height-top)
		is_top = true
	end
	if bottom + height/2 < UI_Height/2 then
		is_bottom = true
	end
	-- for use with SetPoint() we must convert back to EffectiveScaled
	if is_top and is_left then
		if (debug_level > 0) then self:print(format('Region is TOPLEFT %f, %f', left, top), 1) end
		return 'TOPLEFT', left/frame_scale, top/frame_scale
	elseif is_top and is_right then
		if (debug_level > 0) then self:print(format('Region is TOPRIGHT %f, %f', right, top), 1) end
		return 'TOPRIGHT', right/frame_scale, top/frame_scale
	elseif is_bottom and is_left then
		if (debug_level > 0) then self:print(format('Region is BOTTOMLEFT %f, %f', left, bottom), 1) end
		return 'BOTTOMLEFT', left/frame_scale, bottom/frame_scale
	elseif is_bottom and is_right then
		if (debug_level > 0) then self:print(format('Region is BOTTOMRIGHT %f, %f', right, bottom), 1) end
		return 'BOTTOMRIGHT', right/frame_scale, bottom/frame_scale
	else
		if (debug_level > 0) then self:print('Unable to assume region', 1) end
		return 'CENTER', 0, 0
	end
end

function addon:IsInGroup(name)
	if not name then return end
	for i=1, getn(self.groupMembers) do
		if self.groupMembers[i].name == name then
			return self.groupMembers[i].class
		end
	end
end

function addon:print(message, level, headless)
	if not message or message == '' then return end
	local chatframe
  if (SELECTED_CHAT_FRAME) then
    chatframe = SELECTED_CHAT_FRAME
  else
    if not DEFAULT_CHAT_FRAME:IsVisible() then
      FCF_SelectDockFrame(DEFAULT_CHAT_FRAME)
    end
    chatframe = DEFAULT_CHAT_FRAME
  end
  if (chatframe) then
		if level then
			if level <= debug_level then
				if headless then
					chatframe:AddMessage(message, 0.53, 0.69, 0.19)
				else
					chatframe:AddMessage('[WKN]: ' .. message, 0.53, 0.69, 0.19)
				end
			end
		else
			if headless then
				chatframe:AddMessage(message)
			else
				chatframe:AddMessage('[WKN]: ' .. message, 1.0, 0.61, 0)
			end
		end
  end 
end

do
	local ignoreUpdate
	function addon:CHAT_MSG_ADDON()
		if arg1 ~= PREFIX then
			return
		end
		
		if (debug_level > 0) then self:print(format('--RAW [%s] --\n%s\n--ENDRAW--', arg4, arg2), 2) end
		
		local msg = {}
		local len = 0
		for w in gmatch(arg2, '[^;]+') do
			len = len + 1
			if (debug_level > 0) then self:print(format('[%d] WORD "%s"', len, w), 3) end
			tinsert(msg, w)
		end
		
		if len == 3 and msg[3] == self.Network.VersionCheck --[[and arg4 ~= me]] then
			-- received version check message
			local netversion = tonumber(msg[2])
			if (debug_level > 0) then self:print('[NET:CHECK] '..arg4..' v'..netversion, 2) end
			self:NetworkSendUpdate(self.Network.VersionCheckReply, nil, "BULK")
		end
		
		if len == 3 and msg[3] == self.Network.VersionCheckReply and self.netPing --[[and arg4 ~= me]] then
			-- received version check reply message
			local netversion = tonumber(msg[2])
			if (debug_level > 0) then self:print('[NET:REPLY] '..arg4..' v'..netversion, 2) end
			self:NetworkPingReply(arg4, netversion)
		end
		
		if len == 4 and msg[3] == self.Network.Version and arg4 ~= me then
			-- received version message
			local netversion = tonumber(msg[2])
			local url = string.gsub(msg[4], '\124', '\124\124') -- paranoia from the webdev days
			if (debug_level > 0) then self:print('[NET] '..arg4..' v'..netversion, 2) end
			if netversion > tonumber(self.version) and string.find(url, '^.-://') and not ignoreUpdate then -- ensure "PROTOCOL://DATA" format
				self.networkUpdateURL = url
				ignoreUpdate = true
				self:print(arg4..' has newer version than yours. Updating is highly recommended.')
				self:print('Update URL: '..url)
				self:print('Type "/wk update" to copy download link.')
			end
		end
		
		if len == 4 and msg[3] == self.Network.Cooldown and arg4 ~= me then
			-- received cooldown message
			local skillInfo = self:GetSkillInfo(msg[4])
			if not skillInfo then
				return
			end
			
			self:ApplyCooldown(arg4, skillInfo, false)
			if (debug_level > 0) then self:print('[NET] Showing cooldowns for '..arg4..' due to '..skillInfo.name, 1) end
		end
		
		if len == 5 and msg[3] == self.Network.Cooldown and arg4 ~= me then
			-- received cooldown message (miss)
			local skillInfo = self:GetSkillInfo(msg[4])
			if not skillInfo then
				return
			end
			
			self:ApplyCooldown(arg4, skillInfo, true)
			if (debug_level > 0) then self:print('[NET] Showing cooldowns for '..arg4..' due to '..skillInfo.name..' (miss)', 1) end
		end
	end
end

local messageCache = setmetatable({},{__index = function(t,k)
	local v = format("%s;%s;%s;",PREFIX,addon.version,k)
	rawset(t,k,v)
	return v
end})
function addon:NetworkSendUpdate(message, guild, prio)
	if not NETWORK then return end
	
	local msg = messageCache[message]
	if not (prio) then prio = "NORMAL" end
	
	if GetNumRaidMembers() > 0 then
		if (debug_level > 0) then self:print('[NET] OUT RAID', 3) end
		CTL:SendAddonMessage(prio, PREFIX, msg, 'RAID')
	elseif GetNumPartyMembers() > 0 then
		if (debug_level > 0) then self:print('[NET] OUT PARTY', 3) end
		CTL:SendAddonMessage(prio, PREFIX, msg, 'PARTY')
	end
	
	if guild and IsInGuild() then
		if (debug_level > 0) then self:print('[NET] OUT GUILD', 3) end
		CTL:SendAddonMessage(prio, PREFIX, msg, 'GUILD')
	end
end

function addon:NetworkPing(ready)
	if (debug_level > 0) then self:print('[NetworkPing] '..tostring(ready), 1) end
	if ready then
		if (debug_level > 0) then self:print('[NetworkPing] version check ready', 3) end
		for k,frame in pairs(self.main_frame.trackers) do
			frame.net:Hide()
			frame.net.status:SetVertexColor(1, 1, 1)
			frame.net.status:Hide()
		end
	else
		if (debug_level > 0) then self:print('[NetworkPing] requesting version check', 3) end
		for k,frame in pairs(self.main_frame.trackers) do
			frame.net.status:SetVertexColor(1, 1, 1)
			frame.net.status:Hide()
			frame.net:Show()
		end
		self.netPing = true
		self.main_frame.netPingFrame:Show()
		self:NetworkSendUpdate(self.Network.VersionCheck, nil, "BULK")
	end
end

function addon:NetworkPingReply(name, version)
	for k,frame in pairs(self.main_frame.trackers) do
		if frame.text:GetText() == name then
			frame.net:Show()
			if version > tonumber(self.version) then
				frame.net.status:SetVertexColor(0.6, 1, 0.6)
			elseif version < tonumber(self.version) then
				frame.net.status:SetVertexColor(1, 0.6, 0.6)
			end
			frame.net.status:Show()
		end
	end
end

function addon:PopulateSpells(reset)
	if reset then
		SPELLBOOK = {}
	end
	
	local MAX_TABS = GetNumSpellTabs()
	
	for tab=1, MAX_TABS do
		local name, texture, offset, numSpells = GetSpellTabInfo(tab)
		
		for spell=1, numSpells do
			local currentPage = ceil(spell/SPELLS_PER_PAGE)
			local SpellID = spell + offset + ( SPELLS_PER_PAGE * (currentPage - 1))
			local spellName, spellRank = GetSpellName(SpellID, "spell")
			local skillInfo = self:GetSkillInfo(spellName)
			if skillInfo then
				tinsert(SPELLBOOK, {name=skillInfo.name, id=SpellID})
			end
		end
	end
	
	if (debug_level > 0) then self:print('PopulateSpells: '..getn(SPELLBOOK)..' spells ready', 2) end
	
end

function addon:ResetCooldowns(name)
	if not name then
		-- reset cooldowns for all players
		for tname, tracker in pairs(self.main_frame.trackers) do
			for k, v in pairs(tracker.cooldowns.icons) do
				v.text:SetText()
				v:Hide()
			end
			tracker.cooldowns.t = {}
			tracker.cooldowns:SetWidth(0)
		end
	else
		-- reset cooldowns for specific player
		if not self.main_frame.trackers[name] then
			return
		end
		for k, v in pairs(self.main_frame.trackers[name].cooldowns.icons) do
			v.text:SetText()
			v:Hide()
		end
		self.main_frame.trackers[name].cooldowns.t = {}
		self.main_frame.trackers[name].cooldowns:SetWidth(0)
	end	
end

function addon:ApplyCooldown(name, skillInfo, miss)
	if
		not name
		or not skillInfo
		or not skillInfo.name
		or not skillInfo.cooldown
		or not skillInfo.texture
		or not self.main_frame.trackers[name]
	then 
		return
	end

	local obj = {
		name = skillInfo.name,
		remaining = skillInfo.cooldown,
		miss = miss,
		cooldown = skillInfo.cooldown,
		texture = skillInfo.texture
	}
	
	local found
	for i=1, getn(self.main_frame.trackers[name].cooldowns.t) do
		if self.main_frame.trackers[name].cooldowns.t[i].name == skillInfo.name then
			found = i
			break
		end
	end
	
	if found then
		self.main_frame.trackers[name].cooldowns.t[found] = obj
	else
		table.insert(self.main_frame.trackers[name].cooldowns.t, obj)
	end

	self.main_frame.trackers[name].cooldowns:Show()
end

-- important combat events
function addon:CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS() -- can occur OUTSIDE PARTY TOO
	-- "Roguea's Kick was dodged by Earthborer"
	local _,_, name, skill = strfind(arg1, '^(%a-)\'s (.-) %l.- .+')
	local skillInfo = self:GetSkillInfo(skill)
	if not name or not skillInfo or not self:IsInGroup(name) then
		return
	end

	self:ApplyCooldown(name, skillInfo, true)
	if (debug_level > 0) then self:print('[DAMAGESHIELDS_ON_OTHERS] Showing cooldowns for '..name..' due to missed '..skillInfo.name, 1) end
end

function addon:CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF()
	-- "Your Kick was dodged by Earthborer"
	-- "Your Gouge failed. Magistrate Barthilas is immune."
	-- "Your Cheap Shot failed. Magistrate Barthilas is immune."
	local _,_, skill = strfind(arg1, '^Your (.-) %l.- .+')
	local skillInfo = self:GetSkillInfo(skill)
	if not skillInfo then
		return
	end

	self:ApplyCooldown(me, skillInfo, true)
	for skill, spellData in pairs(self.SpellWatcher.spells) do
		self.SpellWatcher.spells[skill].fail = true
	end
	self:NetworkSendUpdate(format('%s;%s;%s', self.Network.Cooldown, skillInfo.name, 1), nil, "ALERT")
	if (debug_level > 0) then self:print('[DAMAGESHIELDS_ON_SELF] Showing cooldowns for you due to missed '..skill, 1) end
end

function addon:CHAT_MSG_SPELL_SELF_DAMAGE()
	if (debug_level > 0) then self:print('CHAT_MSG_SPELL_SELF_DAMAGE', 1) end
	-- "Your Kick hits Earthborer for 8."
	local _,_, skill = strfind(arg1, '^Your (.-) .- .+')
	local skillInfo = self:GetSkillInfo(skill)
	if not skillInfo then
		return
	end

	self:ApplyCooldown(me, skillInfo, false)
	if (debug_level > 0) then self:print('[SELF_DAMAGE] Showing cooldowns for you due to '..skill, 1) end
end

function addon:CHAT_MSG_SPELL_PARTY_DAMAGE()
	if (debug_level > 0) then self:print('CHAT_MSG_SPELL_PARTY_DAMAGE', 1) end
	-- "Roguea's Kick hits Earthborer for 4. (7 blocked)"
	local _,_, name, skill = strfind(arg1, '^(.-)\'s (.-) .- .+')
	local skillInfo = self:GetSkillInfo(skill)
	if not skillInfo then
		return
	end
	
	self:ApplyCooldown(name, skillInfo, false)
	if (debug_level > 0) then self:print('[PARTY_DAMAGE] Showing cooldowns for '..name..' due to '..skillInfo.name, 1) end
end

function addon:CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE() -- fucking raid groups, can occur OUTSIDE PARTY/RAID TOO
	local _,_, name, skill = strfind(arg1, '^(%a-)\'s (.-) %l.- .+')
	local skillInfo = self:GetSkillInfo(skill)
	if not name or not skillInfo or not self:IsInGroup(name) then
		return
	end
	
	self:ApplyCooldown(name, skillInfo, false)
	if (debug_level > 0) then self:print('[FRIENDLYPLAYER_DAMAGE] Showing cooldowns for '..name..' due to '..skillInfo.name, 1) end
end

do
	local oncd = {}
	function addon:SPELL_UPDATE_COOLDOWN() -- lag-independed way to detect kidney shot, hopefully
<<<<<<< HEAD
		self:print('SPELL_UPDATE_COOLDOWN', 2)
		for i=1, getn(SPELLBOOK) do
			local t, cd = GetSpellCooldown(SPELLBOOK[i].id, "spell")
			self:print(SPELLBOOK[i].name..' cd '..cd, 2)
=======
		if (debug_level > 0) then self:print('SPELL_UPDATE_COOLDOWN', 1) end
		for i=1, getn(SPELLBOOK) do
			local t, cd = GetSpellCooldown(SPELLBOOK[i].id, "spell")
			if (debug_level > 0) then self:print(SPELLBOOK[i].name..' cd '..cd, 2) end
>>>>>>> 8c019268fafd36dff8d627783758794a9e3a5830
			if cd > 1.5 then
				if not oncd[SPELLBOOK[i].id] or oncd[SPELLBOOK[i].id] < t then
				
					oncd[SPELLBOOK[i].id] = t
					local skillInfo = self:GetSkillInfo(SPELLBOOK[i].name)
					
					self:ApplyCooldown(me, skillInfo, false)
					self:NetworkSendUpdate(format('%s;%s', self.Network.Cooldown, skillInfo.name), nil, "NORMAL")
					if (debug_level > 0) then self:print('[SPELL_UPDATE_COOLDOWN] Showing cooldowns for you due to '..skillInfo.name, 1) end
				end
			end
		end
	end
end
-- end of important combat events

function addon:ResetConfig()
	WhoKicksNowOptions = {}
	WhoKicksNowOptions.point = 'CENTER'
	WhoKicksNowOptions.x = 0
	WhoKicksNowOptions.y = 0
	WhoKicksNowOptions.enabled = true
	WhoKicksNowOptions.locked = false
end

function addon:SetHooks()
	-- hooks
	self.CastSpellByName = CastSpellByName
	self.CastSpell = CastSpell
	self.UseAction = UseAction
	self.RunMacro = RunMacro
	
	function RunMacro(arg)
		if (debug_level > 0) then self:print('[SpellWatcher|Macro] '..arg, 2) end
		self.RunMacro(arg)
	end
	
	function CastSpellByName(msg)
		local skillInfo = self:GetSkillInfo(msg)
		if (debug_level > 0) then self:print('[SpellWatcher|ByName] '..msg, 2) end
		if skillInfo and skillInfo.useHook then
			if (debug_level > 0) then self:print('[SpellWatcher|ByName] updating '..msg, 1) end
			self.SpellWatcher.spells[msg] = { t = GetTime() }
		end
		self.CastSpellByName(msg)
	end
	
	function CastSpell(id, bookType)
		if (debug_level > 0) then self:print('[SpellWatcher|id] '..id..', bookType: '..bookType, 1) end
		self.CastSpell(id, bookType)
	end
	
	self.UseActionTooltip = CreateFrame('GameTooltip', 'WKNTooltip', UIParent, 'GameTooltipTemplate')
	self.UseActionTooltip:SetOwner(UIParent, 'ANCHOR_NONE')
	self.UseActionTooltipText = WKNTooltipTextLeft1
	
	function UseAction(slot, flags, onSelf)
		if IsUsableAction(slot) and GetActionCooldown(slot) == 0 then
			self.UseActionTooltip:ClearLines()
			self.UseActionTooltip:SetAction(slot)
			local spellName = self.UseActionTooltipText:GetText()
			local skillInfo = self:GetSkillInfo(spellName)
<<<<<<< HEAD
			self:print('[UseAction]  '..tostring(spellName), 2)
=======
			if (debug_level > 0) then self:print('[UseAction]  '..tostring(spellName), 1) end
>>>>>>> 8c019268fafd36dff8d627783758794a9e3a5830
			if skillInfo and skillInfo.useHook then
				if (debug_level > 0) then self:print('[SpellWatcher|Slot] updating '..spellName, 1) end
				self.SpellWatcher.spells[spellName] = { t = GetTime() }
			end
		end
		self.UseAction(slot, flags, onSelf)
	end
	-- hooks end
end

-- update trackers frame: is player alive? is player connected? is player near us?
function addon:UpdateWorldStatus()
	local name, _, class, unitid
	
	local numRaidMembers = GetNumRaidMembers()
	local numPartyMembers = GetNumPartyMembers()
	if numRaidMembers > 0 then
		for i=1, numRaidMembers do
			unitid = raid[i]
			_, class = UnitClass(unitid)
			name = UnitName(unitid)
			if name and class and self:IsInGroup(name) and self.main_frame.trackers[name] then
				-- check distance
				if CheckInteractDistance(unitid, 3) then
					self.main_frame.trackers[name]:SetAlpha(1)
				else
					self.main_frame.trackers[name]:SetAlpha(0.5)
				end
				
				-- check if is alive and connected
				if UnitIsConnected(unitid) then
					if UnitIsDeadOrGhost(unitid) then
						self.main_frame.trackers[name].text:SetTextColor(RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b)
					else
						self.main_frame.trackers[name].text:SetTextColor(RAID_CLASS_COLORS[class].r, RAID_CLASS_COLORS[class].g, RAID_CLASS_COLORS[class].b)
					end
				else
					self.main_frame.trackers[name].text:SetTextColor(0.5, 0.5, 0.5)
				end
			end
		end
	elseif numPartyMembers > 0 then
		for i=1, numPartyMembers do
			unitid = party[i]
			_, class = UnitClass(unitid)
			name = UnitName(unitid)
			if name and class and self:IsInGroup(name) and self.main_frame.trackers[name] then
				-- check distance
				if CheckInteractDistance(unitid, 3) then
					self.main_frame.trackers[name]:SetAlpha(1)
				else
					self.main_frame.trackers[name]:SetAlpha(0.5)
				end
				
				-- check if is alive and connected
				if UnitIsConnected(unitid) then
					if UnitIsDeadOrGhost(unitid) then
						self.main_frame.trackers[name].text:SetTextColor(RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b)
					else
						self.main_frame.trackers[name].text:SetTextColor(RAID_CLASS_COLORS[class].r, RAID_CLASS_COLORS[class].g, RAID_CLASS_COLORS[class].b)
					end
				else
					self.main_frame.trackers[name].text:SetTextColor(0.5, 0.5, 0.5)
				end
			end
		end
	end
end

function addon:CreateGUI()
	local main_frame = CreateFrame('Frame', nil, UIParent)
	self.main_frame = main_frame
	if (debug_level > 0) then self:print(format('loading frame position [%s] %f, %f', WhoKicksNowOptions.point, WhoKicksNowOptions.x, WhoKicksNowOptions.y), 1) end
	main_frame:SetPoint(WhoKicksNowOptions.point, WhoKicksNowOptions.x, WhoKicksNowOptions.y)
	main_frame:SetWidth(MAINBAR_WIDTH)
	main_frame:SetHeight(MAINBAR_HEIGHT)
	main_frame:SetBackdrop({
		bgFile=[[Interface\Minimap\TooltipBackdrop-Background]],
		edgeFile=[[Interface\Minimap\TooltipBackdrop]],
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 }
	})
  main_frame:SetBackdropColor(0, 0, 0, .6)
	main_frame:SetMovable(true)
	main_frame:SetClampedToScreen(true)
	main_frame:SetToplevel(true)
	main_frame:EnableMouse(true)
	main_frame:RegisterForDrag('LeftButton')
	main_frame:SetScript('OnDragStart', function()
		if self.locked then return end
		this:StartMoving()
	end)
	main_frame:SetScript('OnDragStop', function()
		this:StopMovingOrSizing()
		--local point, x, y = self:GetAnchorPoint()
		local point, _, _, x, y = this:GetPoint() -- pre 2.0 the anchor is always TOPLEFT
		WhoKicksNowOptions.point = point
		WhoKicksNowOptions.x = x
		WhoKicksNowOptions.y = y
		if (debug_level > 0) then self:print(format('saving frame position [%s] %f, %f', point, x, y), 1) end
	end)
	main_frame:SetScript('OnUpdate', function()
		self:UpdateWorldStatus()
	end)
	main_frame.trackers = {}
	main_frame.trackersCount = 0
	
	local text = main_frame:CreateFontString()
	main_frame.text = text
	text:SetFontObject(GameFontNormal)
	text:SetPoint('RIGHT', -15, 0)
	text:SetText('Who Kicks Now?')
	
	local button_lock = CreateFrame('Button', nil, main_frame)
	main_frame.button_lock = button_lock
	button_lock:SetPoint('LEFT', main_frame, 'LEFT', 10, 0)
	button_lock:SetWidth(ICON_WIDTH)
	button_lock:SetHeight(ICON_HEIGHT)
	
	button_lock:SetNormalTexture([[Interface\AddOns\WhoKicksNow\textures\padlock-open]])
	button_lock:SetHighlightTexture([[Interface\AddOns\WhoKicksNow\textures\padlock-highlight]], 'ADD')
	button_lock:SetDisabledTexture([[Interface\AddOns\WhoKicksNow\textures\padlock-disabled]])
	button_lock:SetPushedTexture([[Interface\AddOns\WhoKicksNow\textures\padlock-locked]])
	
	button_lock:SetScript('OnClick', function()
		self.locked = not self.locked
		WhoKicksNowOptions.locked = self.locked
		if this.locked then
			this:SetNormalTexture([[Interface\AddOns\WhoKicksNow\textures\padlock-locked]])
			this:SetHighlightTexture([[Interface\AddOns\WhoKicksNow\textures\padlock-locked-highlight]], 'ADD')
			this:SetDisabledTexture([[Interface\AddOns\WhoKicksNow\textures\padlock-locked-disabled]])
			this:SetPushedTexture([[Interface\AddOns\WhoKicksNow\textures\padlock-pushed]])
			PlaySound("KeyRingOpen")
		else
			this:SetNormalTexture([[Interface\AddOns\WhoKicksNow\textures\padlock-open]])
			this:SetHighlightTexture([[Interface\AddOns\WhoKicksNow\textures\padlock-highlight]], 'ADD')
			this:SetDisabledTexture([[Interface\AddOns\WhoKicksNow\textures\padlock-disabled]])
			this:SetPushedTexture([[Interface\AddOns\WhoKicksNow\textures\padlock-locked-pushed]])
			PlaySound("KeyRingClose")
		end
		self:LockGUI(self.locked)
	end)
	
	local netPingFrame = CreateFrame('Frame')
	main_frame.netPingFrame = netPingFrame
	netPingFrame.elapsed = 0
	netPingFrame:SetScript('OnShow', function()
		this.elapsed = 0
	end)
	netPingFrame:SetScript('OnUpdate', function()
		if not self.netPing then
			this:Hide()
		end
		this.elapsed = this.elapsed + arg1
		if this.elapsed > 5 then
			self.netPing = false
			this:Hide()
			if (debug_level > 0) then self:print('[netPingFrame] finished in '..this.elapsed, 3) end
			self:NetworkPing(true)
		end
	end)
	netPingFrame:Hide()
	
	local button_query = CreateFrame('Button', nil, main_frame)
	main_frame.button_query = button_query
	button_query:SetPoint('LEFT', main_frame, 'RIGHT', 0, 0)
	button_query:SetWidth(ICON_WIDTH)
	button_query:SetHeight(ICON_HEIGHT)
	
	button_query:SetNormalTexture([[Interface\GossipFrame\GossipGossipIcon]])
	button_query:SetHighlightTexture([[Interface\GossipFrame\PetitionGossipIcon]], 'BLEND')
	button_query:SetPushedTexture([[Interface\GossipFrame\PetitionGossipIcon]])
	
	button_query:SetScript('OnClick', function()
		if (debug_level > 0) then self:print('Clicked query button', 1) end
		self:NetworkPing()
	end)
	
	if (debug_level > 0) then self:print('BUTTON_PING:LOCKED? '..tostring(self.locked), 1) end
	if self.locked then
		button_query:Hide()
	end
	self:LockGUI(self.locked)
end

function addon:VARIABLES_LOADED()
	--[[if arg1 ~= 'WhoKicksNow' then
		return
	end]]
	if not WhoKicksNowOptions then
		self:ResetConfig()
		self:print('config created')
	end
	self:print('loaded')
	
	self.groupMembers = {}
	self.locked = WhoKicksNowOptions.locked
	self.enabled = WhoKicksNowOptions.enabled
	self.inGroup = false
	self.version = GetAddOnMetadata('WhoKicksNow', 'Version')
	self.updateURL = GetAddOnMetadata('WhoKicksNow', 'X-Website')
	self.networkUpdateURL = nil
	
	--[[addon:RegisterAllEvents()
	addon:SetScript('OnEvent', function()
		local s = ""
		if arg1 then s = s..' arg1: '..arg1 end
		if arg2 then s = s..' arg2: '..arg2 end
		if arg3 then s = s..' arg3: '..arg3 end
		if arg4 then s = s..' arg4: '..arg4 end
		if arg5 then s = s..' arg5: '..arg5 end
		if arg6 then s = s..' arg6: '..arg6 end
		if arg7 then s = s..' arg7: '..arg7 end
		if arg8 then s = s..' arg8: '..arg8 end
		if arg9 then s = s..' arg9: '..arg9 end
		if ( strsub(event, 1, 8) == "CHAT_MSG" ) then
			if (debug_level > 0) then self:print(event, 0) end
			self:print(s, 0, true)
		else
			if (debug_level > 0) then self:print(event, 1) end
			self:print(s, 1, true)
		end
	end)]]
	
	-- relay on timing 
	local SPELL_FAIL_TIME = 0.3
	self.SpellWatcher = CreateFrame('Frame')
	
	self.SpellWatcher:SetScript('OnUpdate', function()
		local now = GetTime()
		for skill, spellData in pairs(self.SpellWatcher.spells) do
			if spellData.t+SPELL_FAIL_TIME < now then
				if spellData.fail or not spellData.cast then
					-- cast failed
					self.SpellWatcher.spells[skill] = nil
					if (debug_level > 0) then self:print('[SpellWatcher] '..skill..' failed ('..spellData.t..', now: '..now..')', 1) end
					break
				end
				-- cast was successful
				local skillInfo = self:GetSkillInfo(skill)
				if not skillInfo or not skillInfo.useHook then
					return
				end
				
				self:ApplyCooldown(me, skillInfo, false)
				self:NetworkSendUpdate(format('%s;%s', self.Network.Cooldown, skillInfo.name), nil, "NORMAL")
				if (debug_level > 0) then self:print('[SpellWatcher] Showing cooldowns for you due to '..skill..' ('..spellData.t+SPELL_FAIL_TIME..' < '..now..')', 1) end
				self.SpellWatcher.spells[skill] = nil
			end
		end
		
	end)
	self.SpellWatcher:SetScript('OnEvent', function()
		local now = GetTime()
		if event == 'SPELLCAST_STOP' then
			for skill, spellData in pairs(self.SpellWatcher.spells) do
				self.SpellWatcher.spells[skill].cast = true
			end
		end
	end)
	self.SpellWatcher.spells = {}
	
	local help = {
		'/whokicks pause (pause timers)',
		'/whokicks unlock (unlock trackers)',
		'/whokicks reset (reset configuration)',
		'/whokicks or /wk (enable or disable)'
	}
	SLASH_WHOKICKSNOW1, SLASH_WHOKICKSNOW2, SLASH_WHOKICKSNOW3 = '/whokicksnow', '/whokicks', '/wk'
	function SlashCmdList.WHOKICKSNOW(arg)
		if arg == 'debug' then
			debug_level = debug_level + 1
			if debug_level > 3 then debug_level = 0 end
			self:print('Debug level is now set to ' .. debug_level)
		elseif arg == 'pause' then
			if PAUSE then
				PAUSE = false
				__WKN = nil
				__WKN_D1 = nil
				__WKN_D2 = nil
				self:print('Resuming timers')
			else
				PAUSE = true
				__WKN = self
				__WKN_D1 = self.SpellWatcher.spells
				__WKN_D2 = self.main_frame.trackers[me].cooldowns.t
				self:print('Pausing timers')
			end
		elseif arg == 'indexes' then
			for k,frame in pairs(self.main_frame.trackers) do
				if frame:IsVisible() then
					local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint()
					self:print(format('[%d] %s offset %d', frame.sortIndex, frame.text:GetText(), yOfs))
				end
			end
		elseif arg == 'getpoints' then
			self:GetAnchorPoint()
		elseif arg == 'reset' then
			self:ResetConfig()
			self:print('Configuration has been reseted')
		elseif arg == 'update' then
			self:print('Showing update url')
			local dialog = StaticPopup_Show('WKN_UPDATEPOPUP')
			if dialog then
				dialog:SetWidth(420)
				dialog.editBox:SetText(self.networkUpdateURL or self.updateURL)
			end
		elseif arg == 'unlock' then
			self.locked = not self.locked
			self:LockGUI(self.locked)
			if not (self.locked) then
				local show = self.main_frame:IsVisible() and HideUIPanel(self.main_frame) or ShowUIPanel(self.main_frame)
			end
		elseif arg == '' then
			self.enabled = not self.enabled
			WhoKicksNowOptions.enabled = self.enabled
			
			if self.enabled then
				self:PopulateSpells(true)
				self:RegisterEvent('PARTY_MEMBERS_CHANGED')
				self:RegisterEvent('RAID_ROSTER_UPDATE')
				self:RegisterCombatEvents()
				self:HandlePlayerChange()
				self.main_frame:Show()
				self:print('Enabling AddOn')
			else
				self:HandlePlayerChange()
				self:UnregisterCombatEvents()
				self:ResetCooldowns()
				self.main_frame:Hide()
				self:UnregisterEvent('PARTY_MEMBERS_CHANGED')
				self:UnregisterEvent('RAID_ROSTER_UPDATE')
				self:print('Disabling AddOn')
			end
		else
			for _,line in ipairs(help) do
				self:print(line)
			end
		end
	end
	
	self:SetHooks()
	self:CreateGUI()
	
	if self.enabled then
		self:PopulateSpells()
		self:RegisterEvent('PARTY_MEMBERS_CHANGED')
		self:RegisterEvent('RAID_ROSTER_UPDATE')
		self:HandlePlayerChange()
		self:NetworkSendUpdate(self.Network.Version..';'..self.updateURL, true, "BULK")
	else
		self.main_frame:Hide()
	end
end

function addon:PLAYER_ENTERING_WORLD()
	if self.enabled then
		self:RegisterCombatEvents()
		self:RegisterEvent('PARTY_MEMBERS_CHANGED')
		self:RegisterEvent('RAID_ROSTER_UPDATE')
		self:PopulateSpells(true)
	end
end

function addon:PLAYER_LEAVING_WORLD()
	-- ignore events when zoning in/out
	self:UnregisterCombatEvents()
	self:UnregisterEvent('PARTY_MEMBERS_CHANGED')
	self:UnregisterEvent('RAID_ROSTER_UPDATE')
end

function addon:RAID_ROSTER_UPDATE()
	if (debug_level > 0) then self:print('RAID_ROSTER_UPDATE', 1) end
	self:HandlePlayerChange()
end

function addon:PARTY_MEMBERS_CHANGED()
	if (debug_level > 0) then self:print('PARTY_MEMBERS_CHANGED', 1) end
	self:HandlePlayerChange()
end

function addon:LockGUI(locked)
	if (debug_level > 0) then self:print('LockGUI: '..tostring(locked), 1) end
	if locked then
		self.main_frame.button_lock:SetNormalTexture([[Interface\AddOns\WhoKicksNow\textures\padlock-locked]])
		self.main_frame.button_lock:SetHighlightTexture([[Interface\AddOns\WhoKicksNow\textures\padlock-locked-highlight]], 'ADD')
		self.main_frame.button_lock:SetDisabledTexture([[Interface\AddOns\WhoKicksNow\textures\padlock-locked-disabled]])
		self.main_frame.button_lock:SetPushedTexture([[Interface\AddOns\WhoKicksNow\textures\padlock-pushed]])
		
		for name, tracker in pairs(self.main_frame.trackers) do
			if (debug_level > 0) then self:print('[tracker] (locked)', 1) end
			tracker:SetWidth(BAR_WIDTH_LOCKED)
			tracker.button_up:Hide()
			tracker.button_down:Hide()
			tracker:EnableMouse(false)
		end
		
		self.main_frame:EnableMouse(false)
		self.main_frame.button_query:Hide()
	else
		self.main_frame.button_lock:SetNormalTexture([[Interface\AddOns\WhoKicksNow\textures\padlock-open]])
		self.main_frame.button_lock:SetHighlightTexture([[Interface\AddOns\WhoKicksNow\textures\padlock-highlight]], 'ADD')
		self.main_frame.button_lock:SetDisabledTexture([[Interface\AddOns\WhoKicksNow\textures\padlock-disabled]])
		self.main_frame.button_lock:SetPushedTexture([[Interface\AddOns\WhoKicksNow\textures\padlock-locked-pushed]])
		
		for name, tracker in pairs(self.main_frame.trackers) do
			if (debug_level > 0) then self:print('[tracker] (unlocked)', 1) end
			tracker:SetWidth(BAR_WIDTH)
			tracker.button_up:Show()
			tracker.button_down:Show()
			tracker:EnableMouse(true)
		end
		
		self.main_frame:EnableMouse(true)
		self.main_frame.button_query:Show()
	end
end

do
	local frameid = 1
	local t = {
		{name='Kidney Shot', remaining=20, cooldown=20, texture=[[Interface\Icons\Ability_Rogue_KidneyShot]]},
		{name='Kick', remaining=10, miss=true, cooldown=10, texture=[[Interface\Icons\Ability_Kick]]},
		{name='Pummel', remaining=10, miss=true, cooldown=10, texture=[[Interface\Icons\INV_Gauntlets_04]]},
		{name='Shield Bash', remaining=12, miss=true, cooldown=12, texture=[[Interface\Icons\Ability_Warrior_ShieldBash]]},
	}
	function addon:CreateTracker(name, class)
		if (debug_level > 0) then self:print('creating frame for '..name..', '..class, 1) end

		if self.main_frame.trackers[name] then
			return self.main_frame.trackers[name]
		end
		
		local track_frame = CreateFrame('Frame', nil, self.main_frame)
		self.main_frame.trackers[name] = track_frame
		track_frame.id = frameid
		frameid = frameid + 1
		track_frame:SetPoint('TOPRIGHT', self.main_frame, 'BOTTOMRIGHT', 0, 0)
		track_frame:SetWidth(BAR_WIDTH)
		track_frame:SetHeight(BAR_HEIGHT)
		track_frame:SetBackdrop({
			bgFile=[[Interface\Tooltips\ChatBubble-Background]],
			edgeFile=[[Interface\Tooltips\UI-Tooltip-Border]],
			tile = true,
			tileSize = 16,
			edgeSize = 12,
			insets = { left = 2, right = 2, top = 2, bottom = 2 }
		})
		track_frame:EnableMouse(true)
		track_frame:SetScript('OnMouseDown', function()
			if arg1 == 'LeftButton' then
				TargetByName(this.text:GetText(), 1)
			elseif arg1 == 'RightButton' then
				this.cooldowns.t = t
				this.cooldowns:Show()
				self:print('Test mode for '..this.text:GetText())
			end
		end)
		
		local text = track_frame:CreateFontString()
		track_frame.text = text
		text:SetFontObject(GameFontNormal)
		text:SetTextColor(RAID_CLASS_COLORS[class].r, RAID_CLASS_COLORS[class].g, RAID_CLASS_COLORS[class].b)
		text:SetAllPoints()
		text:SetText(name)
		
		local button_up = CreateFrame('Button', nil, track_frame)
		track_frame.button_up = button_up
		button_up:SetPoint('RIGHT', self.main_frame.trackers[name], 'LEFT', 0, 0)
		button_up:SetWidth(ICON_WIDTH)
		button_up:SetHeight(ICON_HEIGHT)
		
		button_up:SetNormalTexture([[Interface\Buttons\UI-ScrollBar-ScrollUpButton-Up]])
		button_up:SetHighlightTexture([[Interface\Buttons\UI-ScrollBar-ScrollUpButton-Highlight]])
		button_up:SetDisabledTexture([[Interface\Buttons\UI-ScrollBar-ScrollUpButton-Disabled]])
		button_up:SetPushedTexture([[Interface\Buttons\UI-ScrollBar-ScrollUpButton-Down]])
		
		button_up:SetScript('OnClick', function()
			local id = this:GetParent().sortIndex
			local id_previous = id-1
			local id_next = id+1
			
			local tracker_current, tracker_previous, tracker_next
			
			if (debug_level > 0) then self:print('[Up] '..id..' => '..id_previous, 1) end
			
			for name, tracker in pairs(self.main_frame.trackers) do
				if tracker.sortIndex == id_next then
					tracker_next = tracker
				end
				if tracker.sortIndex == id_previous then
					tracker_previous = tracker
				end
				if tracker.sortIndex == id then
					tracker_current = tracker
				end
			end
			
			if tracker_previous and tracker_current then
				tracker_previous.sortIndex = id
				tracker_current.sortIndex = id_previous
				
				tracker_previous.button_up:Enable()
				tracker_previous.button_down:Enable()
				tracker_current.button_up:Enable()
				tracker_current.button_down:Enable()
				
				if tracker_current.sortIndex == 1 then
					tracker_current.button_up:Disable()
				end
				
				if tracker_previous.sortIndex == self.main_frame.trackersCount then
					tracker_previous.button_down:Disable()
				end
				
				local point, relativeTo, relativePoint, xOfs, yOfs = tracker_current:GetPoint()
				tracker_current:SetPoint(point, relativeTo, relativePoint, xOfs, -(tracker_current.sortIndex-1)*BAR_HEIGHT )
				point = tracker_previous:GetPoint()
				tracker_previous:SetPoint(point, relativeTo, relativePoint, xOfs, -(tracker_previous.sortIndex-1)*BAR_HEIGHT )
			end
			
		end)
		
		local button_down = CreateFrame('Button', nil, track_frame)
		track_frame.button_down = button_down
		button_down:SetPoint('RIGHT', self.main_frame.trackers[name], 'LEFT', -ICON_WIDTH, 0)
		button_down:SetWidth(ICON_WIDTH)
		button_down:SetHeight(ICON_HEIGHT)
		
		button_down:SetNormalTexture([[Interface\Buttons\UI-ScrollBar-ScrollDownButton-Up]])
		button_down:SetHighlightTexture([[Interface\Buttons\UI-ScrollBar-ScrollDownButton-Highlight]])
		button_down:SetDisabledTexture([[Interface\Buttons\UI-ScrollBar-ScrollDownButton-Disabled]])
		button_down:SetPushedTexture([[Interface\Buttons\UI-ScrollBar-ScrollDownButton-Down]])
		
		button_down:SetScript('OnClick', function()
			local id = this:GetParent().sortIndex
			local id_previous = id-1
			local id_next = id+1
			
			local tracker_current, tracker_previous, tracker_next
			
			if (debug_level > 0) then self:print('[Down] '..id..' => '..id_next, 1) end
			
			for name, tracker in pairs(self.main_frame.trackers) do
				if tracker.sortIndex == id_next then
					tracker_next = tracker
				end
				if tracker.sortIndex == id_previous then
					tracker_previous = tracker
				end
				if tracker.sortIndex == id then
					tracker_current = tracker
				end
			end
			
			if tracker_next and tracker_current then
				tracker_next.sortIndex = id
				tracker_current.sortIndex = id_next
				
				tracker_next.button_up:Enable()
				tracker_next.button_down:Enable()
				tracker_current.button_up:Enable()
				tracker_current.button_down:Enable()
				
				if tracker_current.sortIndex == self.main_frame.trackersCount then
					tracker_current.button_down:Disable()
				end
				
				if tracker_next.sortIndex == 1 then
					tracker_next.button_up:Disable()
				end
				
				local point, relativeTo, relativePoint, xOfs, yOfs = tracker_next:GetPoint()
				tracker_next:SetPoint(point, relativeTo, relativePoint, xOfs, -(tracker_next.sortIndex-1)*BAR_HEIGHT )
				point = tracker_current:GetPoint()
				tracker_current:SetPoint(point, relativeTo, relativePoint, xOfs, -(tracker_current.sortIndex-1)*BAR_HEIGHT )
			end
			
		end)
		
		local cooldowns = self.main_frame.trackers[name].cooldowns or CreateFrame('Frame', nil, self.main_frame.trackers[name])
		self.main_frame.trackers[name].cooldowns = cooldowns
		cooldowns:SetPoint('LEFT', self.main_frame.trackers[name], 'RIGHT', 0, 0)
		cooldowns:SetWidth(COOLDOWN_WIDTH)
		cooldowns:SetHeight(COOLDOWN_HEIGHT)
		cooldowns:SetBackdrop({
			bgFile=[[Interface\ChatFrame\ChatFrameBackground]],
			tile = true,
			tileSize = 16,
		})
		cooldowns:SetBackdropColor(0, 0, 0, .6)
		
		cooldowns.icons = {}
		cooldowns.MakeIcon = function(obj, parent)
			local iconFrame = CreateFrame('Frame', nil, parent)
			this.icons[obj.name] = iconFrame
			iconFrame:SetWidth(ICONF_WIDTH)
			iconFrame:SetHeight(ICONF_HEIGHT)
			iconFrame.unused = false
			
			local icon = iconFrame:CreateTexture()
			iconFrame.icon = icon
			icon:SetPoint('TOPLEFT', iconFrame, 'TOPLEFT', 0, 0)
			icon:SetWidth(ICON_WIDTH)
			icon:SetHeight(ICON_HEIGHT)
			icon:SetTexture(obj.texture)
			
			local text = iconFrame:CreateFontString()
			iconFrame.text = text
			text:SetFontObject(GameFontNormal)
			text:SetJustifyH('LEFT')
			--text:SetAllPoints(icon)
			text:SetPoint('LEFT', icon, 'RIGHT', 1, 0)
			
			return iconFrame
		end
		
		cooldowns.t = {}

			-- {
			-- 	{name='Kick', remaining=2, miss=false, cooldown=10, texture=[[Interface\Icons\Ability_Kick]]},
			-- }
		
		cooldowns:SetScript('OnUpdate', function()
			if PAUSE then return end
			-- update timers
			for i=getn(this.t), 1, -1 do
				this.t[i].remaining = this.t[i].remaining-arg1
				if this.t[i].remaining <= 0 then
					this.icons[this.t[i].name]:Hide()
					tremove(this.t, i)
				end
			end
			
			if getn(this.t) == 0 then this:Hide() return end
			
			this:SetWidth(getn(this.t) * ICONF_WIDTH)
			
			local iconFrame
			for i=1, getn(this.t) do
				iconFrame = this.icons[this.t[i].name] or this.MakeIcon(this.t[i], this)
				if i == 1 then
					iconFrame:SetPoint('LEFT', this, 'LEFT', 0, 0)
				else
					iconFrame:SetPoint('LEFT', this, 'LEFT', ICONF_WIDTH*(i-1), 0)
				end
				iconFrame.text:SetText(ceil(this.t[i].remaining))
				if this.t[i].miss then
					iconFrame.icon:SetVertexColor(1, 0, 0)
				else
					iconFrame.icon:SetVertexColor(1, 1, 1)
				end
				iconFrame:Show()
			end
		end)
		
		do
			local net = CreateFrame('Frame', nil, track_frame)
			track_frame.net = net
			net:SetPoint('LEFT', self.main_frame.trackers[name], 'LEFT', 4, 0)
			net:SetWidth(16)
			net:SetHeight(16)
			
			net:SetBackdrop({
				bgFile=[[Interface\Buttons\YELLOWORANGE64]],
				tile = false,
				tileSize = 16,
			})
			net:SetBackdropColor(1, 1, 1, 0)
			
			local backdrop = net:CreateTexture(nil, 'BORDER')
			net.backdrop = backdrop
			backdrop:SetAllPoints()
			backdrop:SetTexture([[Interface\Buttons\UI-RadioButton]])
			backdrop:SetTexCoord(0, 0.25, 0, 1)
			
			local status = net:CreateTexture(nil, 'ARTWORK')
			net.status = status
			status:SetAllPoints()
			status:SetTexture([[Interface\Buttons\UI-RadioButton]])
			status:SetTexCoord(0.26, 0.49, 0, 1)
			
			net:Hide()
			status:Hide()
		end
		
		return track_frame
	end
end

do
	local _inGroup = false
	function addon:HandlePlayerChange()
		local players = {}
		local group = false
		local numRaidMembers = GetNumRaidMembers()
		local numPartyMembers = GetNumPartyMembers()
		if numRaidMembers > 0 then
			local name, _, class
			for i=1, numRaidMembers do
				_, class = UnitClass(raid[i])
				name = UnitName(raid[i])
				if name and class then
					players[i] = {name=name,class=class}
				end
			end
			self.inGroup = true
			group = 1
		elseif numPartyMembers > 0 then
			local name, _, class
			for i=1, numPartyMembers do
				_, class = UnitClass(party[i])
				name = UnitName(party[i])
				if name and class then
					players[i] = {name=name,class=class}
				end
			end
			_, class = UnitClass('player')
			players[numPartyMembers+1] = {name=me,class=class}
			self.inGroup = true
			group = 2
		else
			self.inGroup = false
		end
		
		--[[if getn(self.groupMembers) == getn(players) then
			if (debug_level > 0) then self:print('HandlePlayerChange: nothing important has changed', 1) end
			return
		end]]
		
		self.groupMembers = players
		
		for k,frame in pairs(self.main_frame.trackers) do
			-- reset sort index from non-group players
			if not self:IsInGroup(frame.text:GetText()) then
				frame.sortIndex = nil
			end
			frame:Hide()
		end
		self.main_frame.trackersCount = 0
		
		if group ~= _inGroup then
			_inGroup = group
			if self.inGroup then
				-- trigger network message when joining a party/raid
				self:NetworkSendUpdate(self.Network.Version..';'..self.updateURL, nil, "BULK")
			end
		end
		
		if self.inGroup and self.enabled then
			local track_frame
			local unsorted = {}
			
			for i=1, getn(self.groupMembers) do
				if CLASSES[self.groupMembers[i].class] then
					self.main_frame.trackersCount = self.main_frame.trackersCount + 1
					track_frame = self:CreateTracker(self.groupMembers[i].name, self.groupMembers[i].class)
					unsorted[self.main_frame.trackersCount] = track_frame
				end
			end
			
			sort(unsorted, function(a, b)
				-- sort by index pairs, then index if any, then name
				if a.sortIndex and b.sortIndex then
					return a.sortIndex < b.sortIndex
				end
				if a.sortIndex and not b.sortIndex then
					return true
				end
				if b.sortIndex and not a.sortIndex then
					return false
				end

				return a.text:GetText() < b.text:GetText()
			end)
			
			if (debug_level > 0) then self:print('adjusting frames position', 1) end
			local point, relativeTo, relativePoint, xOfs, yOfs
			for i=1, self.main_frame.trackersCount do
				unsorted[i].button_up:Enable()
				unsorted[i].button_down:Enable()
				unsorted[i].button_up:Show()
				unsorted[i].button_down:Show()
				point, relativeTo, relativePoint, xOfs, yOfs = unsorted[i]:GetPoint()
				if i == 1 then
<<<<<<< HEAD
					self:print(format('[%d] %s is first', unsorted[i].sortIndex or -1, unsorted[i].text:GetText()), 2)
					unsorted[i]:SetPoint(point, relativeTo, relativePoint, xOfs, 0)
					unsorted[i].button_up:Disable()
				elseif i == self.main_frame.trackersCount then
					self:print(format('[%d] %s is last (of %d)', unsorted[i].sortIndex or -1, unsorted[i].text:GetText(), self.main_frame.trackersCount), 2)
					unsorted[i]:SetPoint(point, relativeTo, relativePoint, xOfs, -(self.main_frame.trackersCount-1)*BAR_HEIGHT )
					unsorted[i].button_down:Disable()
				elseif self.main_frame.trackersCount == 1 then
					self:print(format('[%d] %s is alone', unsorted[i].sortIndex or -1, unsorted[i].text:GetText()), 2)
=======
					if (debug_level > 0) then self:print(format('[%d] %s is first', unsorted[i].sortIndex or -1, unsorted[i].text:GetText()), 1) end
					unsorted[i]:SetPoint(point, relativeTo, relativePoint, xOfs, 0)
					unsorted[i].button_up:Disable()
				elseif i == self.main_frame.trackersCount then
					if (debug_level > 0) then self:print(format('[%d] %s is last (of %d)', unsorted[i].sortIndex or -1, unsorted[i].text:GetText(), self.main_frame.trackersCount), 1) end
					unsorted[i]:SetPoint(point, relativeTo, relativePoint, xOfs, -(self.main_frame.trackersCount-1)*BAR_HEIGHT )
					unsorted[i].button_down:Disable()
				elseif self.main_frame.trackersCount == 1 then
					if (debug_level > 0) then self:print(format('[%d] %s is alone', unsorted[i].sortIndex or -1, unsorted[i].text:GetText()), 1) end
>>>>>>> 8c019268fafd36dff8d627783758794a9e3a5830
					unsorted[i]:SetPoint(point, relativeTo, relativePoint, xOfs, 0)
					unsorted[i].button_up:Disable()
					unsorted[i].button_down:Disable()
				else
<<<<<<< HEAD
					self:print(format('[%d] %s', unsorted[i].sortIndex or -1, unsorted[i].text:GetText()), 2)
=======
					if (debug_level > 0) then self:print(format('[%d] %s', unsorted[i].sortIndex or -1, unsorted[i].text:GetText()), 1) end
>>>>>>> 8c019268fafd36dff8d627783758794a9e3a5830
					unsorted[i]:SetPoint(point, relativeTo, relativePoint, xOfs, -(i-1)*BAR_HEIGHT )
				end
				
				if self.locked then
					unsorted[i].button_up:Hide()
					unsorted[i].button_down:Hide()
					unsorted[i]:SetWidth(BAR_WIDTH_LOCKED)
				else
					unsorted[i]:SetWidth(BAR_WIDTH)
				end
				
				unsorted[i].sortIndex = i
				unsorted[i]:Show()
<<<<<<< HEAD
				self:print(format('Showing frame for [%d] %s', unsorted[i].sortIndex, unsorted[i].text:GetText()), 2)
=======
				if (debug_level > 0) then self:print(format('Showing frame for [%d] %s', unsorted[i].sortIndex, unsorted[i].text:GetText()), 1) end
>>>>>>> 8c019268fafd36dff8d627783758794a9e3a5830
			end
			
			self:RegisterCombatEvents()
		else
			self:UnregisterCombatEvents()
		end
		if self.locked and (not self.inGroup) then
			self.main_frame:Hide()
		else
			self.main_frame:Show()
		end
	end
end
_G.WhoKicksNow = addon
