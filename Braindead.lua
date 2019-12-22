if select(2, UnitClass('player')) ~= 'DEATHKNIGHT' then
	DisableAddOn('Braindead')
	return
end

-- copy heavily accessed global functions into local scope for performance
local GetSpellCooldown = _G.GetSpellCooldown
local GetSpellCharges = _G.GetSpellCharges
local GetTime = _G.GetTime
local UnitCastingInfo = _G.UnitCastingInfo
local UnitAura = _G.UnitAura
-- end copy global functions

-- useful functions
local function between(n, min, max)
	return n >= min and n <= max
end

local function startsWith(str, start) -- case insensitive check to see if a string matches the start of another string
	if type(str) ~= 'string' then
		return false
	end
   return string.lower(str:sub(1, start:len())) == start:lower()
end
-- end useful functions

Braindead = {}
local Opt -- use this as a local table reference to Braindead

SLASH_Braindead1, SLASH_Braindead2 = '/bd', '/brain'
BINDING_HEADER_BRAINDEAD = 'Braindead'

local function InitOpts()
	local function SetDefaults(t, ref)
		local k, v
		for k, v in next, ref do
			if t[k] == nil then
				local pchar
				if type(v) == 'boolean' then
					pchar = v and 'true' or 'false'
				elseif type(v) == 'table' then
					pchar = 'table'
				else
					pchar = v
				end
				t[k] = v
			elseif type(t[k]) == 'table' then
				SetDefaults(t[k], v)
			end
		end
	end
	SetDefaults(Braindead, { -- defaults
		locked = false,
		snap = false,
		scale = {
			main = 1,
			previous = 0.7,
			cooldown = 0.7,
			interrupt = 0.4,
			extra = 0.4,
			glow = 1,
		},
		glow = {
			main = true,
			cooldown = true,
			interrupt = false,
			extra = true,
			blizzard = false,
			color = { r = 1, g = 1, b = 1 },
		},
		hide = {
			blood = false,
			frost = false,
			unholy = false,
		},
		alpha = 1,
		frequency = 0.2,
		previous = true,
		always_on = false,
		cooldown = true,
		spell_swipe = true,
		dimmer = true,
		miss_effect = true,
		boss_only = false,
		interrupt = true,
		aoe = false,
		auto_aoe = false,
		auto_aoe_ttl = 10,
		pot = false,
		trinket = true,
		death_strike_threshold = 60,
	})
end

-- UI related functions container
local UI = {
	anchor = {},
	glows = {},
}

-- automatically registered events container
local events = {}

local timer = {
	combat = 0,
	display = 0,
	health = 0
}

-- specialization constants
local SPEC = {
	NONE = 0,
	BLOOD = 1,
	FROST = 2,
	UNHOLY = 3,
}

-- current player information
local Player = {
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	spec = 0,
	target_mode = 0,
	gcd = 1.5,
	health = 0,
	health_max = 0,
	runic_power = 0,
	runic_power_max = 100,
	runes = {},
	runes_ready = 0,
	rune_max = 6,
	rune_regen = 0,
	group_size = 1,
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
	},
}

-- current target information
local Target = {
	boss = false,
	guid = 0,
	healthArray = {},
	hostile = false,
	estimated_range = 30,
}

-- Azerite trait API access
local Azerite = {}

local braindeadPanel = CreateFrame('Frame', 'braindeadPanel', UIParent)
braindeadPanel:SetPoint('CENTER', 0, -169)
braindeadPanel:SetFrameStrata('BACKGROUND')
braindeadPanel:SetSize(64, 64)
braindeadPanel:SetMovable(true)
braindeadPanel:Hide()
braindeadPanel.icon = braindeadPanel:CreateTexture(nil, 'BACKGROUND')
braindeadPanel.icon:SetAllPoints(braindeadPanel)
braindeadPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
braindeadPanel.border = braindeadPanel:CreateTexture(nil, 'ARTWORK')
braindeadPanel.border:SetAllPoints(braindeadPanel)
braindeadPanel.border:SetTexture('Interface\\AddOns\\Braindead\\border.blp')
braindeadPanel.border:Hide()
braindeadPanel.dimmer = braindeadPanel:CreateTexture(nil, 'BORDER')
braindeadPanel.dimmer:SetAllPoints(braindeadPanel)
braindeadPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
braindeadPanel.dimmer:Hide()
braindeadPanel.swipe = CreateFrame('Cooldown', nil, braindeadPanel, 'CooldownFrameTemplate')
braindeadPanel.swipe:SetAllPoints(braindeadPanel)
braindeadPanel.text = CreateFrame('Frame', nil, braindeadPanel)
braindeadPanel.text:SetAllPoints(braindeadPanel)
braindeadPanel.text.br = braindeadPanel.text:CreateFontString(nil, 'OVERLAY')
braindeadPanel.text.br:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
braindeadPanel.text.br:SetPoint('BOTTOMRIGHT', braindeadPanel, 'BOTTOMRIGHT', -1.5, 3)
braindeadPanel.text.center = braindeadPanel.text:CreateFontString(nil, 'OVERLAY')
braindeadPanel.text.center:SetFont('Fonts\\FRIZQT__.TTF', 9, 'OUTLINE')
braindeadPanel.text.center:SetAllPoints(braindeadPanel.text)
braindeadPanel.text.center:SetJustifyH('CENTER')
braindeadPanel.text.center:SetJustifyV('CENTER')
braindeadPanel.button = CreateFrame('Button', nil, braindeadPanel)
braindeadPanel.button:SetAllPoints(braindeadPanel)
braindeadPanel.button:RegisterForClicks('LeftButtonDown', 'RightButtonDown', 'MiddleButtonDown')
local braindeadPreviousPanel = CreateFrame('Frame', 'braindeadPreviousPanel', UIParent)
braindeadPreviousPanel:SetFrameStrata('BACKGROUND')
braindeadPreviousPanel:SetSize(64, 64)
braindeadPreviousPanel:Hide()
braindeadPreviousPanel:RegisterForDrag('LeftButton')
braindeadPreviousPanel:SetScript('OnDragStart', braindeadPreviousPanel.StartMoving)
braindeadPreviousPanel:SetScript('OnDragStop', braindeadPreviousPanel.StopMovingOrSizing)
braindeadPreviousPanel:SetMovable(true)
braindeadPreviousPanel.icon = braindeadPreviousPanel:CreateTexture(nil, 'BACKGROUND')
braindeadPreviousPanel.icon:SetAllPoints(braindeadPreviousPanel)
braindeadPreviousPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
braindeadPreviousPanel.border = braindeadPreviousPanel:CreateTexture(nil, 'ARTWORK')
braindeadPreviousPanel.border:SetAllPoints(braindeadPreviousPanel)
braindeadPreviousPanel.border:SetTexture('Interface\\AddOns\\Braindead\\border.blp')
local braindeadCooldownPanel = CreateFrame('Frame', 'braindeadCooldownPanel', UIParent)
braindeadCooldownPanel:SetSize(64, 64)
braindeadCooldownPanel:SetFrameStrata('BACKGROUND')
braindeadCooldownPanel:Hide()
braindeadCooldownPanel:RegisterForDrag('LeftButton')
braindeadCooldownPanel:SetScript('OnDragStart', braindeadCooldownPanel.StartMoving)
braindeadCooldownPanel:SetScript('OnDragStop', braindeadCooldownPanel.StopMovingOrSizing)
braindeadCooldownPanel:SetMovable(true)
braindeadCooldownPanel.icon = braindeadCooldownPanel:CreateTexture(nil, 'BACKGROUND')
braindeadCooldownPanel.icon:SetAllPoints(braindeadCooldownPanel)
braindeadCooldownPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
braindeadCooldownPanel.border = braindeadCooldownPanel:CreateTexture(nil, 'ARTWORK')
braindeadCooldownPanel.border:SetAllPoints(braindeadCooldownPanel)
braindeadCooldownPanel.border:SetTexture('Interface\\AddOns\\Braindead\\border.blp')
braindeadCooldownPanel.cd = CreateFrame('Cooldown', nil, braindeadCooldownPanel, 'CooldownFrameTemplate')
braindeadCooldownPanel.cd:SetAllPoints(braindeadCooldownPanel)
local braindeadInterruptPanel = CreateFrame('Frame', 'braindeadInterruptPanel', UIParent)
braindeadInterruptPanel:SetFrameStrata('BACKGROUND')
braindeadInterruptPanel:SetSize(64, 64)
braindeadInterruptPanel:Hide()
braindeadInterruptPanel:RegisterForDrag('LeftButton')
braindeadInterruptPanel:SetScript('OnDragStart', braindeadInterruptPanel.StartMoving)
braindeadInterruptPanel:SetScript('OnDragStop', braindeadInterruptPanel.StopMovingOrSizing)
braindeadInterruptPanel:SetMovable(true)
braindeadInterruptPanel.icon = braindeadInterruptPanel:CreateTexture(nil, 'BACKGROUND')
braindeadInterruptPanel.icon:SetAllPoints(braindeadInterruptPanel)
braindeadInterruptPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
braindeadInterruptPanel.border = braindeadInterruptPanel:CreateTexture(nil, 'ARTWORK')
braindeadInterruptPanel.border:SetAllPoints(braindeadInterruptPanel)
braindeadInterruptPanel.border:SetTexture('Interface\\AddOns\\Braindead\\border.blp')
braindeadInterruptPanel.cast = CreateFrame('Cooldown', nil, braindeadInterruptPanel, 'CooldownFrameTemplate')
braindeadInterruptPanel.cast:SetAllPoints(braindeadInterruptPanel)
local braindeadExtraPanel = CreateFrame('Frame', 'braindeadExtraPanel', UIParent)
braindeadExtraPanel:SetFrameStrata('BACKGROUND')
braindeadExtraPanel:SetSize(64, 64)
braindeadExtraPanel:Hide()
braindeadExtraPanel:RegisterForDrag('LeftButton')
braindeadExtraPanel:SetScript('OnDragStart', braindeadExtraPanel.StartMoving)
braindeadExtraPanel:SetScript('OnDragStop', braindeadExtraPanel.StopMovingOrSizing)
braindeadExtraPanel:SetMovable(true)
braindeadExtraPanel.icon = braindeadExtraPanel:CreateTexture(nil, 'BACKGROUND')
braindeadExtraPanel.icon:SetAllPoints(braindeadExtraPanel)
braindeadExtraPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
braindeadExtraPanel.border = braindeadExtraPanel:CreateTexture(nil, 'ARTWORK')
braindeadExtraPanel.border:SetAllPoints(braindeadExtraPanel)
braindeadExtraPanel.border:SetTexture('Interface\\AddOns\\Braindead\\border.blp')

-- Start AoE

Player.target_modes = {
	[SPEC.NONE] = {
		{1, ''}
	},
	[SPEC.BLOOD] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'}
	},
	[SPEC.FROST] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'}
	},
	[SPEC.UNHOLY] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'}
	},
}

function Player:SetTargetMode(mode)
	if mode == self.target_mode then
		return
	end
	self.target_mode = min(mode, #self.target_modes[self.spec])
	self.enemies = self.target_modes[self.spec][self.target_mode][1]
	braindeadPanel.text.br:SetText(self.target_modes[self.spec][self.target_mode][2])
end

function Player:ToggleTargetMode()
	local mode = self.target_mode + 1
	self:SetTargetMode(mode > #self.target_modes[self.spec] and 1 or mode)
end

function Player:ToggleTargetModeReverse()
	local mode = self.target_mode - 1
	self:SetTargetMode(mode < 1 and #self.target_modes[self.spec] or mode)
end

-- Target Mode Keybinding Wrappers
function Braindead_SetTargetMode(mode)
	Player:SetTargetMode(mode)
end

function Braindead_ToggleTargetMode()
	Player:ToggleTargetMode()
end

function Braindead_ToggleTargetModeReverse()
	Player:ToggleTargetModeReverse()
end

-- End AoE

-- Start Auto AoE

local autoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {
		[120651] = true, -- Explosives (Mythic+ affix)
	},
}

function autoAoe:Add(guid, update)
	if self.blacklist[guid] then
		return
	end
	local unitId = guid:match('^%w+-%d+-%d+-%d+-%d+-(%d+)')
	if unitId and self.ignored_units[tonumber(unitId)] then
		self.blacklist[guid] = Player.time + 10
		return
	end
	local new = not self.targets[guid]
	self.targets[guid] = Player.time
	if update and new then
		self:Update()
	end
end

function autoAoe:Remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:Update()
	end
end

function autoAoe:Clear()
	local guid
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
end

function autoAoe:Update()
	local count, i = 0
	for i in next, self.targets do
		count = count + 1
	end
	if count <= 1 then
		Player:SetTargetMode(1)
		return
	end
	Player.enemies = count
	for i = #Player.target_modes[Player.spec], 1, -1 do
		if count >= Player.target_modes[Player.spec][i][1] then
			Player:SetTargetMode(i)
			Player.enemies = count
			return
		end
	end
end

function autoAoe:Purge()
	local update, guid, t
	for guid, t in next, self.targets do
		if Player.time - t > Opt.auto_aoe_ttl then
			self.targets[guid] = nil
			update = true
		end
	end
	-- remove expired blacklisted enemies
	for guid, t in next, self.blacklist do
		if Player.time > t then
			self.blacklist[guid] = nil
		end
	end
	if update then
		self:Update()
	end
end

-- End Auto AoE

-- Start Abilities

local Ability = {}
Ability.__index = Ability
local abilities = {
	all = {}
}

function Ability:Add(spellId, buff, player, spellId2)
	local ability = {
		spellId = spellId,
		spellId2 = spellId2,
		name = false,
		icon = false,
		requires_charge = false,
		requires_pet = false,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		hasted_ticks = false,
		known = false,
		runic_power_cost = 0,
		rune_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		max_range = 40,
		velocity = 0,
		auraTarget = buff and 'player' or 'target',
		auraFilter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
	}
	setmetatable(ability, self)
	abilities.all[#abilities.all + 1] = ability
	return ability
end

function Ability:Match(spell)
	if type(spell) == 'number' then
		return spell == self.spellId or (self.spellId2 and spell == self.spellId2)
	elseif type(spell) == 'string' then
		return spell:lower() == self.name:lower()
	elseif type(spell) == 'table' then
		return spell == self
	end
	return false
end

function Ability:Ready(seconds)
	return self:Cooldown() <= (seconds or 0)
end

function Ability:Usable()
	if not self.known then
		return false
	end
	if self:RuneCost() > Player.runes_ready then
		return false
	end
	if self:RunicPowerCost() > Player.runic_power then
		return false
	end
	if self.requires_pet and not Player.pet_active then
		return false
	end
	if self.requires_charge and self:Charges() == 0 then
		return false
	end
	return self:Ready()
end

function Ability:Remains()
	if self:Casting() or self:Traveling() then
		return self:Duration()
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:Match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(expires - Player.ctime - Player.execute_remains, 0)
		end
	end
	return 0
end

function Ability:Refreshable()
	if self.buff_duration > 0 then
		return self:Remains() < self:Duration() * 0.3
	end
	return self:Down()
end

function Ability:Up()
	return self:Remains() > 0
end

function Ability:Down()
	return not self:Up()
end

function Ability:SetVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.travel_start = {}
	else
		self.travel_start = nil
		self.velocity = 0
	end
end

function Ability:Traveling()
	if self.travel_start and self.travel_start[Target.guid] then
		if Player.time - self.travel_start[Target.guid] < self.max_range / self.velocity then
			return true
		end
		self.travel_start[Target.guid] = nil
	end
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity
end

function Ability:Ticking()
	if self.aura_targets then
		local count, guid, aura = 0
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > Player.execute_remains then
				count = count + 1
			end
		end
		return count
	end
	return self:Up() and 1 or 0
end

function Ability:TickTime()
	return self.hasted_ticks and (Player.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:CooldownDuration()
	return self.hasted_cooldown and (Player.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:Cooldown()
	if self.cooldown_duration > 0 and self:Casting() then
		return self.cooldown_duration
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - Player.execute_remains)
end

function Ability:Stack()
	local _, i, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:Match(id) then
			return (expires == 0 or expires - Player.ctime > Player.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:RuneCost()
	return self.rune_cost
end

function Ability:RunicPowerCost()
	return self.runic_power_cost
end

function Ability:Charges()
	return (GetSpellCharges(self.spellId)) or 0
end

function Ability:ChargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, Player.ctime - recharge_start + Player.execute_remains)) / recharge_time)
end

function Ability:FullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - Player.execute_remains)
end

function Ability:MaxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:Duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:Casting()
	return Player.ability_casting == self
end

function Ability:Channeling()
	return UnitChannelInfo('player') == self.name
end

function Ability:CastTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return self.triggers_gcd and Player.gcd or 0
	end
	return castTime / 1000
end

function Ability:Previous(n)
	local i = n or 1
	if Player.ability_casting then
		if i == 1 then
			return Player.ability_casting == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
end

function Ability:AzeriteRank()
	return Azerite.traits[self.spellId] or 0
end

function Ability:AutoAoe(removeUnaffected, trigger)
	self.auto_aoe = {
		remove = removeUnaffected,
		targets = {}
	}
	if trigger == 'periodic' then
		self.auto_aoe.trigger = 'SPELL_PERIODIC_DAMAGE'
	elseif trigger == 'apply' then
		self.auto_aoe.trigger = 'SPELL_AURA_APPLIED'
	else
		self.auto_aoe.trigger = 'SPELL_DAMAGE'
	end
end

function Ability:RecordTargetHit(guid)
	self.auto_aoe.targets[guid] = Player.time
	if not self.auto_aoe.start_time then
		self.auto_aoe.start_time = self.auto_aoe.targets[guid]
	end
end

function Ability:UpdateTargetsHit()
	if self.auto_aoe.start_time and Player.time - self.auto_aoe.start_time >= 0.3 then
		self.auto_aoe.start_time = nil
		if self.auto_aoe.remove then
			autoAoe:Clear()
		end
		local guid
		for guid in next, self.auto_aoe.targets do
			autoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
		end
		autoAoe:Update()
	end
end

-- start DoT tracking

local trackAuras = {}

function trackAuras:Purge()
	local _, ability, guid, expires
	for _, ability in next, abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
	local _, ability
	for _, ability in next, abilities.trackAuras do
		ability:RemoveAura(guid)
	end
end

function Ability:TrackAuras()
	self.aura_targets = {}
end

function Ability:ApplyAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = {
		expires = Player.time + self:Duration()
	}
	self.aura_targets[guid] = aura
end

function Ability:RefreshAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		self:ApplyAura(guid)
		return
	end
	local duration = self:Duration()
	aura.expires = Player.time + min(duration * 1.3, (aura.expires - Player.time) + duration)
end

function Ability:RefreshAuraAll()
	local guid, aura, remains
	local duration = self:Duration()
	for guid, aura in next, self.aura_targets do
		aura.expires = Player.time + min(duration * 1.3, (aura.expires - Player.time) + duration)
	end
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- end DoT tracking

-- Death Knight Abilities
---- Multiple Specializations
local AntiMagicShell = Ability:Add(48707, true, true)
AntiMagicShell.buff_duration = 5
AntiMagicShell.cooldown_duration = 60
AntiMagicShell.triggers_gcd = false
local ChainsOfIce = Ability:Add(45524, false)
ChainsOfIce.buff_duration = 8
ChainsOfIce.rune_cost = 1
local DarkCommand = Ability:Add(56222, false)
DarkCommand.buff_duration = 3
DarkCommand.cooldown_duration = 8
DarkCommand.triggers_gcd = false
local DeathAndDecay = Ability:Add(43265, true, true, 188290)
DeathAndDecay.buff_duration = 10
DeathAndDecay.cooldown_duration = 30
DeathAndDecay.rune_cost = 1
DeathAndDecay.tick_interval = 1
DeathAndDecay.damage = Ability:Add(52212, false, true)
DeathAndDecay.damage:AutoAoe()
local DeathGrip = Ability:Add(49576, false, true)
DeathGrip.cooldown_duration = 25
DeathGrip.requires_charge = true
local DeathsAdvance = Ability:Add(48265, true, true)
DeathsAdvance.buff_duration = 8
DeathsAdvance.cooldown_duration = 45
DeathsAdvance.triggers_gcd = false
local DeathStrike = Ability:Add(49998, false, true)
DeathStrike.runic_power_cost = 45
local IceboundFortitude = Ability:Add(48792, true, true)
IceboundFortitude.buff_duration = 8
IceboundFortitude.cooldown_duration = 180
IceboundFortitude.triggers_gcd = false
local MindFreeze = Ability:Add(47528, false, true)
MindFreeze.buff_duration = 3
MindFreeze.cooldown_duration = 15
MindFreeze.triggers_gcd = false
local RaiseAlly = Ability:Add(61999, false, true)
RaiseAlly.cooldown_duration = 600
RaiseAlly.runic_power_cost = 30
------ Procs

------ Talents
local Asphyxiate = Ability:Add(108194, false, true)
Asphyxiate.buff_duration = 4
Asphyxiate.cooldown_duration = 45
local SummonGargoyle = Ability:Add(49206, true, true)
SummonGargoyle.buff_duration = 35
SummonGargoyle.cooldown_duration = 180
---- Blood
local BloodBoil = Ability:Add(50842, false, true)
BloodBoil.cooldown_duration = 7.5
BloodBoil.requires_charge = true
BloodBoil:AutoAoe(true)
local BloodPlague = Ability:Add(55078, false, true)
BloodPlague.buff_duration = 24
BloodPlague.tick_interval = 3
BloodPlague:AutoAoe()
BloodPlague:TrackAuras()
local DancingRuneWeapon = Ability:Add(49028, true, true, 81256)
DancingRuneWeapon.buff_duration = 8
DancingRuneWeapon.cooldown_duration = 120
local DeathsCaress = Ability:Add(195292, false, true)
DeathsCaress.rune_cost = 1
local HeartStrike = Ability:Add(206930, false, true)
HeartStrike.buff_duration = 8
HeartStrike.rune_cost = 1
local Marrowrend = Ability:Add(195182, false, true)
Marrowrend.rune_cost = 2
------ Talents
local Blooddrinker = Ability:Add(206931, false, true)
Blooddrinker.buff_duration = 3
Blooddrinker.cooldown_duration = 30
Blooddrinker.rune_cost = 1
Blooddrinker.tick_interval = 1
Blooddrinker.hasted_duration = true
Blooddrinker.hasted_ticks = true
local Bonestorm = Ability:Add(194844, true, true)
Bonestorm.buff_duration = 1
Bonestorm.cooldown_duration = 60
Bonestorm.runic_power_cost = 10
Bonestorm.tick_interval = 1
Bonestorm.damage = Ability:Add(196528, false, true)
Bonestorm.damage:AutoAoe()
local Consumption = Ability:Add(274156, false, true)
Consumption.cooldown_duration = 45
Consumption:AutoAoe()
local Heartbreaker = Ability:Add(210738, false, true)
local Hemostasis = Ability:Add(273946, true, true, 273947)
Hemostasis.buff_duration = 15
local Ossuary = Ability:Add(219786, true, true, 219788)
local RapidDecomposition = Ability:Add(194662, false, true)
local RuneStrike = Ability:Add(210764, false, true)
RuneStrike.cooldown_duration = 60
RuneStrike.rune_cost = 1
RuneStrike.requires_charge = true
local Tombstone = Ability:Add(219809, false, true)
Tombstone.buff_duration = 8
Tombstone.cooldown_duration = 60
------ Procs
local BoneShield = Ability:Add(195181, true, true)
BoneShield.buff_duration = 30
local CrimsonScourge = Ability:Add(81136, true, true, 81141)
CrimsonScourge.buff_duration = 15
---- Frost

------ Talents

------ Procs

---- Unholy
local Apocalypse = Ability:Add(275699, false, true)
Apocalypse.cooldown_duration = 90
local ArmyOfTheDead = Ability:Add(42650, true, true, 42651)
ArmyOfTheDead.buff_duration = 4
ArmyOfTheDead.cooldown_duration = 480
ArmyOfTheDead.rune_cost = 3
local ControlUndead = Ability:Add(111673, true, true)
ControlUndead.buff_duration = 300
ControlUndead.rune_cost = 1
local DarkTransformation = Ability:Add(63560, true, true)
DarkTransformation.buff_duration = 15
DarkTransformation.cooldown_duration = 60
DarkTransformation.requires_pet = true
local DeathCoil = Ability:Add(47541, false, true, 47632)
DeathCoil.runic_power_cost = 40
DeathCoil:SetVelocity(35)
local FesteringStrike = Ability:Add(85948, false, true)
FesteringStrike.rune_cost = 2
local FesteringWound = Ability:Add(194310, false, true, 194311)
FesteringWound.buff_duration = 30
local Outbreak = Ability:Add(77575, false, true, 196782)
Outbreak.buff_duration = 6
Outbreak.rune_cost = 1
Outbreak:TrackAuras()
local RaiseDead = Ability:Add(46584, false, true)
RaiseDead.cooldown_duration = 30
local ScourgeStrike = Ability:Add(55090, false, true, 70890)
ScourgeStrike.rune_cost = 1
local VirulentPlague = Ability:Add(191587, false, true)
VirulentPlague.buff_duration = 21
VirulentPlague.tick_interval = 1.5
VirulentPlague:AutoAoe(false, 'apply')
VirulentPlague:TrackAuras()
------ Talents
local BurstingSores = Ability:Add(207264, false, true, 207267)
BurstingSores:AutoAoe(true)
local ClawingShadows = Ability:Add(207311, false, true)
ClawingShadows.rune_cost = 1
local DeathPact = Ability:Add(48743, true, true)
DeathPact.buff_duration = 15
DeathPact.cooldown_duration = 120
local Defile = Ability:Add(152280, false, true, 156000)
Defile.buff_duration = 10
Defile.cooldown_duration = 20
Defile.rune_cost = 1
Defile.tick_interval = 1
Defile:AutoAoe()
local EbonFever = Ability:Add(207269, false, true)
local Epidemic = Ability:Add(207317, false, true, 212739)
Epidemic.runic_power_cost = 30
Epidemic.splash = Ability:Add(215969, false, true)
Epidemic.splash:AutoAoe(true)
local Pestilence = Ability:Add(277234, false, true)
local RaiseAbomination = Ability:Add(288853, true, true)
RaiseAbomination.buff_duration = 25
RaiseAbomination.cooldown_duration = 90
local SoulReaper = Ability:Add(130736, false, true)
SoulReaper.buff_duration = 8
SoulReaper.cooldown_duration = 45
local UnholyBlight = Ability:Add(115989, true, true)
UnholyBlight.buff_duration = 6
UnholyBlight.cooldown_duration = 45
UnholyBlight.rune_cost = 1
UnholyBlight.dot = Ability:Add(115994, false, true)
UnholyBlight.dot.buff_duration = 14
UnholyBlight.dot.tick_interval = 2
UnholyBlight:AutoAoe(true)
local UnholyFrenzy = Ability:Add(207289, true, true)
UnholyFrenzy.buff_duration = 12
UnholyFrenzy.cooldown_duration = 75
------ Procs
local DarkSuccor = Ability:Add(101568, true, true)
DarkSuccor.buff_duration = 20
local RunicCorruption = Ability:Add(51462, true, true, 51460)
RunicCorruption.buff_duration = 3
local SuddenDoom = Ability:Add(49530, true, true, 81340)
SuddenDoom.buff_duration = 10
local VirulentEruption = Ability:Add(191685, false, true)
-- Azerite Traits
local MagusOfTheDead = Ability:Add(288417, true, true)
-- Heart of Azeroth
---- Major Essences
local ConcentratedFlame = Ability:Add(295373, true, true, 295378)
ConcentratedFlame.buff_duration = 180
ConcentratedFlame.cooldown_duration = 30
ConcentratedFlame.requires_charge = true
ConcentratedFlame.essence_id = 12
ConcentratedFlame.essence_major = true
ConcentratedFlame:SetVelocity(40)
ConcentratedFlame.dot = Ability:Add(295368, false, true)
ConcentratedFlame.dot.buff_duration = 6
ConcentratedFlame.dot.tick_interval = 2
ConcentratedFlame.dot.essence_id = 12
ConcentratedFlame.dot.essence_major = true
local GuardianOfAzeroth = Ability:Add(295840, false, true)
GuardianOfAzeroth.cooldown_duration = 180
GuardianOfAzeroth.essence_id = 14
GuardianOfAzeroth.essence_major = true
local FocusedAzeriteBeam = Ability:Add(295258, false, true)
FocusedAzeriteBeam.cooldown_duration = 90
FocusedAzeriteBeam.essence_id = 5
FocusedAzeriteBeam.essence_major = true
local MemoryOfLucidDreams = Ability:Add(298357, true, true)
MemoryOfLucidDreams.buff_duration = 15
MemoryOfLucidDreams.cooldown_duration = 120
MemoryOfLucidDreams.essence_id = 27
MemoryOfLucidDreams.essence_major = true
local PurifyingBlast = Ability:Add(295337, false, true, 295338)
PurifyingBlast.cooldown_duration = 60
PurifyingBlast.essence_id = 6
PurifyingBlast.essence_major = true
PurifyingBlast:AutoAoe(true)
local RippleInSpace = Ability:Add(302731, true, true)
RippleInSpace.buff_duration = 2
RippleInSpace.cooldown_duration = 60
RippleInSpace.essence_id = 15
RippleInSpace.essence_major = true
local TheUnboundForce = Ability:Add(298452, false, true)
TheUnboundForce.cooldown_duration = 45
TheUnboundForce.essence_id = 28
TheUnboundForce.essence_major = true
local VisionOfPerfection = Ability:Add(299370, true, true, 303345)
VisionOfPerfection.buff_duration = 10
VisionOfPerfection.essence_id = 22
VisionOfPerfection.essence_major = true
local WorldveinResonance = Ability:Add(295186, true, true)
WorldveinResonance.cooldown_duration = 60
WorldveinResonance.essence_id = 4
WorldveinResonance.essence_major = true
---- Minor Essences
local AncientFlame = Ability:Add(295367, false, true)
AncientFlame.buff_duration = 10
AncientFlame.essence_id = 12
local CondensedLifeForce = Ability:Add(295367, false, true)
CondensedLifeForce.essence_id = 14
local FocusedEnergy = Ability:Add(295248, true, true)
FocusedEnergy.buff_duration = 4
FocusedEnergy.essence_id = 5
local Lifeblood = Ability:Add(295137, true, true)
Lifeblood.essence_id = 4
local LucidDreams = Ability:Add(298343, true, true)
LucidDreams.buff_duration = 8
LucidDreams.essence_id = 27
local PurificationProtocol = Ability:Add(295305, false, true)
PurificationProtocol.essence_id = 6
PurificationProtocol:AutoAoe()
local RealityShift = Ability:Add(302952, true, true)
RealityShift.buff_duration = 20
RealityShift.cooldown_duration = 30
RealityShift.essence_id = 15
local RecklessForce = Ability:Add(302917, true, true)
RecklessForce.essence_id = 28
local StriveForPerfection = Ability:Add(299369, true, true)
StriveForPerfection.essence_id = 22
-- Racials
local ArcaneTorrent = Ability:Add(50613, true, true) -- Blood Elf
-- Trinket Effects

-- End Abilities

-- Start Inventory Items

local InventoryItem, inventoryItems, Trinket = {}, {}, {}
InventoryItem.__index = InventoryItem

function InventoryItem:Add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon,
		can_use = false,
	}
	setmetatable(item, self)
	inventoryItems[#inventoryItems + 1] = item
	return item
end

function InventoryItem:Charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		charges = max(charges, self.max_charges)
	end
	return charges
end

function InventoryItem:Count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		count = max(count, 1)
	end
	return count
end

function InventoryItem:Cooldown()
	local startTime, duration
	if self.equip_slot then
		startTime, duration = GetInventoryItemCooldown('player', self.equip_slot)
	else
		startTime, duration = GetItemCooldown(self.itemId)
	end
	return startTime == 0 and 0 or duration - (Player.ctime - startTime)
end

function InventoryItem:Ready(seconds)
	return self:Cooldown() <= (seconds or 0)
end

function InventoryItem:Equipped()
	return self.equip_slot and true
end

function InventoryItem:Usable(seconds)
	if not self.can_use then
		return false
	end
	if not self:Equipped() and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

-- Inventory Items
local GreaterFlaskOfTheUndertow = InventoryItem:Add(168654)
GreaterFlaskOfTheUndertow.buff = Ability:Add(298841, true, true)
local PotionOfUnbridledFury = InventoryItem:Add(169299)
PotionOfUnbridledFury.buff = Ability:Add(300714, true, true)
PotionOfUnbridledFury.buff.triggers_gcd = false
-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
-- End Inventory Items

-- Start Azerite Trait API

Azerite.equip_slots = { 1, 3, 5 } -- Head, Shoulder, Chest

function Azerite:Init()
	self.locations = {}
	self.traits = {}
	self.essences = {}
	local i
	for i = 1, #self.equip_slots do
		self.locations[i] = ItemLocation:CreateFromEquipmentSlot(self.equip_slots[i])
	end
end

function Azerite:Update()
	local _, loc, slot, pid, pinfo
	for pid in next, self.traits do
		self.traits[pid] = nil
	end
	for pid in next, self.essences do
		self.essences[pid] = nil
	end
	if UnitEffectiveLevel('player') < 110 then
		print('disabling azerite, player is effectively level', UnitEffectiveLevel('player'))
		return -- disable all Azerite/Essences for players scaled under 110
	end
	for _, loc in next, self.locations do
		if GetInventoryItemID('player', loc:GetEquipmentSlot()) and C_AzeriteEmpoweredItem.IsAzeriteEmpoweredItem(loc) then
			for _, slot in next, C_AzeriteEmpoweredItem.GetAllTierInfo(loc) do
				if slot.azeritePowerIDs then
					for _, pid in next, slot.azeritePowerIDs do
						if C_AzeriteEmpoweredItem.IsPowerSelected(loc, pid) then
							self.traits[pid] = 1 + (self.traits[pid] or 0)
							pinfo = C_AzeriteEmpoweredItem.GetPowerInfo(pid)
							if pinfo and pinfo.spellID then
								self.traits[pinfo.spellID] = self.traits[pid]
							end
						end
					end
				end
			end
		end
	end
	for _, loc in next, C_AzeriteEssence.GetMilestones() or {} do
		if loc.slot then
			pid = C_AzeriteEssence.GetMilestoneEssence(loc.ID)
			if pid then
				pinfo = C_AzeriteEssence.GetEssenceInfo(pid)
				self.essences[pid] = {
					id = pid,
					rank = pinfo.rank,
					major = loc.slot == 0,
				}
			end
		end
	end
end

-- End Azerite Trait API

-- Start Player API

function Player:Health()
	return self.health
end

function Player:HealthMax()
	return self.health_max
end

function Player:HealthPct()
	return self.health / self.health_max * 100
end

function Player:Runes()
	return self.runes_ready
end

function Player:RuneDeficit()
	return self.rune_max - self.runes_ready
end

function Player:RuneRegen()
	return self.rune_regen
end

function Player:RuneTimeTo(runes)
	return max(self.runes[runes] - self.execute_remains, 0)
end

function Player:RunicPower()
	return self.runic_power
end

function Player:RunicPowerDeficit()
	return self.runic_power_max - self.runic_power
end

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	return 0
end

function Player:BloodlustActive()
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if (
			id == 2825 or   -- Bloodlust (Horde Shaman)
			id == 32182 or  -- Heroism (Alliance Shaman)
			id == 80353 or  -- Time Warp (Mage)
			id == 90355 or  -- Ancient Hysteria (Hunter Pet - Core Hound)
			id == 160452 or -- Netherwinds (Hunter Pet - Nether Ray)
			id == 264667 or -- Primal Rage (Hunter Pet - Ferocity)
			id == 178207 or -- Drums of Fury (Leatherworking)
			id == 146555 or -- Drums of Rage (Leatherworking)
			id == 230935 or -- Drums of the Mountain (Leatherworking)
			id == 256740    -- Drums of the Maelstrom (Leatherworking)
		) then
			return true
		end
	end
end

function Player:Equipped(itemID, slot)
	if slot then
		return GetInventoryItemID('player', slot) == itemID, slot
	end
	local i
	for i = 1, 19 do
		if GetInventoryItemID('player', i) == itemID then
			return true, i
		end
	end
	return false
end

function Player:InArenaOrBattleground()
	return self.instance == 'arena' or self.instance == 'pvp'
end

function Player:UpdateAbilities()
	self.rune_max = UnitPowerMax('player', 5)
	self.runic_power_max = UnitPowerMax('player', 6)
	local _, ability

	for _, ability in next, abilities.all do
		ability.name, _, ability.icon = GetSpellInfo(ability.spellId)
		ability.known = false
		if C_LevelLink.IsSpellLocked(ability.spellId) or (ability.spellId2 and C_LevelLink.IsSpellLocked(ability.spellId2)) then
			-- spell is locked, do not mark as known
		elseif IsPlayerSpell(ability.spellId) or (ability.spellId2 and IsPlayerSpell(ability.spellId2)) then
			ability.known = true
		elseif Azerite.traits[ability.spellId] then
			ability.known = true
		elseif ability.essence_id and Azerite.essences[ability.essence_id] then
			if ability.essence_major then
				ability.known = Azerite.essences[ability.essence_id].major
			else
				ability.known = true
			end
		end
	end

	BloodPlague.known = BloodBoil.known
	BoneShield.known = Marrowrend.known
	Bonestorm.damage.known = Bonestorm.known
	VirulentPlague.known = Outbreak.known
	VirulentEruption.known = VirulentPlague.known
	FesteringWound.known = FesteringStrike.known
	if Defile.known then
		DeathAndDecay.known = false
	end
	if ClawingShadows.known then
		ScourgeStrike.known = false
	end
	if RaiseAbomination.known then
		ArmyOfTheDead.known = false
	end
	DeathAndDecay.damage.known = DeathAndDecay.known

	abilities.bySpellId = {}
	abilities.velocity = {}
	abilities.autoAoe = {}
	abilities.trackAuras = {}
	for _, ability in next, abilities.all do
		if ability.known then
			abilities.bySpellId[ability.spellId] = ability
			if ability.spellId2 then
				abilities.bySpellId[ability.spellId2] = ability
			end
			if ability.velocity > 0 then
				abilities.velocity[#abilities.velocity + 1] = ability
			end
			if ability.auto_aoe then
				abilities.autoAoe[#abilities.autoAoe + 1] = ability
			end
			if ability.aura_targets then
				abilities.trackAuras[#abilities.trackAuras + 1] = ability
			end
		end
	end
end

function Player:UpdatePet()
	self.pet = UnitGUID('pet')
	self.pet_alive = self.pet and not UnitIsDead('pet') and true
	self.pet_active = (self.pet_alive and not self.pet_stuck or IsFlying()) and true
end

function Player:UpdateRunes()
	while #self.runes > self.rune_max do
		self.runes[#self.runes] = nil
	end
	local i, start, duration
	self.runes_ready = 0
	for i = 1, self.rune_max do
		start, duration = GetRuneCooldown(i)
		self.runes[i] = max(start + duration - self.ctime, 0)
		if self.runes[i] <= self.execute_remains then
			self.runes_ready = self.runes_ready + 1
		end
	end
	table.sort(self.runes)
end

-- End Player API

-- Start Target API

function Target:UpdateHealth()
	timer.health = 0
	self.health = UnitHealth('target')
	table.remove(self.healthArray, 1)
	self.healthArray[15] = self.health
	self.timeToDieMax = self.health / UnitHealthMax('player') * 15
	self.healthPercentage = self.healthMax > 0 and (self.health / self.healthMax * 100) or 100
	self.healthLostPerSec = (self.healthArray[1] - self.health) / 3
	self.timeToDie = self.healthLostPerSec > 0 and min(self.timeToDieMax, self.health / self.healthLostPerSec) or self.timeToDieMax
end

function Target:Update()
	UI:Disappear()
	if UI:ShouldHide() then
		return
	end
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.boss = false
		self.stunnable = true
		self.classification = 'normal'
		self.player = false
		self.level = UnitLevel('player')
		self.healthMax = 0
		self.hostile = true
		local i
		for i = 1, 15 do
			self.healthArray[i] = 0
		end
		if Opt.always_on then
			self:UpdateHealth()
			UI:UpdateCombat()
			braindeadPanel:Show()
			return true
		end
		if Opt.previous and Player.combat_start == 0 then
			braindeadPreviousPanel:Hide()
		end
		return
	end
	if guid ~= self.guid then
		self.guid = guid
		local i
		for i = 1, 15 do
			self.healthArray[i] = UnitHealth('target')
		end
	end
	self.boss = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.level = UnitLevel('target')
	self.healthMax = UnitHealthMax('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		if self.level == -1 or (Player.instance == 'party' and self.level >= UnitLevel('player') + 2) then
			self.boss = true
			self.stunnable = false
		elseif Player.instance == 'raid' or (self.healthMax > Player.health_max * 10) then
			self.stunnable = false
		end
	end
	if self.hostile or Opt.always_on then
		self:UpdateHealth()
		UI:UpdateCombat()
		braindeadPanel:Show()
		return true
	end
end

-- End Target API

-- Start Ability Modifications

function ConcentratedFlame.dot:Remains()
	if ConcentratedFlame:Traveling() then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function DeathAndDecay:RuneCost()
	if CrimsonScourge.known and CrimsonScourge:Up() then
		return 0
	end
	return Ability.RuneCost(self)
end

function DeathCoil:RunicPowerCost()
	if SuddenDoom:Up() then
		return 0
	end
	return Ability.RunicPowerCost(self)
end

function DeathStrike:RunicPowerCost()
	if DarkSuccor:Up() then
		return 0
	end
	local cost = Ability.RunicPowerCost(self)
	if Ossuary.known and Ossuary:Up() then
		cost = cost - 5
	end
	return cost
end

function HeartStrike:Targets()
	return min(Player.enemies, DeathAndDecay:Up() and 5 or 2)
end

function VirulentPlague:Duration()
	local duration = Ability.Duration(self)
	if EbonFever.known then
		duration =  duration / 2
	end
	return duration
end

function Asphyxiate:Usable()
	if not Target.stunnable then
		return false
	end
	return Ability.Usable(self)
end

-- End Ability Modifications

local function UseCooldown(ability, overwrite)
	if Opt.cooldown and (not Opt.boss_only or Target.boss) and (not Player.cd or overwrite) then
		Player.cd = ability
	end
end

local function UseExtra(ability, overwrite)
	if not Player.extra or overwrite then
		Player.extra = ability
	end
end

-- Begin Action Priority Lists

local APL = {
	[SPEC.NONE] = {
		main = function() end
	},
	[SPEC.BLOOD] = {},
	[SPEC.FROST] = {},
	[SPEC.UNHOLY] = {},
}

APL[SPEC.BLOOD].main = function(self)
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
# Snapshot raid buffed stats before combat begins and pre-potting is done.
actions.precombat+=/snapshot_stats
actions.precombat+=/potion
]]
		if Opt.pot and not Player:InArenaOrBattleground() then
			if GreaterFlaskOfTheUndertow:Usable() and GreaterFlaskOfTheUndertow.buff:Remains() < 300 then
				UseCooldown(GreaterFlaskOfTheUndertow)
			end
			if Target.boss and PotionOfUnbridledFury:Usable() then
				UseCooldown(PotionOfUnbridledFury)
			end
		end
		if DeathAndDecay:Usable() then
			UseCooldown(DeathAndDecay)
		end
	end
--[[
actions+=/blood_fury,if=cooldown.dancing_rune_weapon.ready&(!cooldown.blooddrinker.ready|!talent.blooddrinker.enabled)
actions+=/berserking
actions+=/use_items,if=cooldown.dancing_rune_weapon.remains>90
actions+=/use_item,name=razdunks_big_red_button
actions+=/use_item,name=merekthas_fang
actions+=/potion,if=buff.dancing_rune_weapon.up
actions+=/dancing_rune_weapon,if=!talent.blooddrinker.enabled|!cooldown.blooddrinker.ready
actions+=/tombstone,if=buff.bone_shield.stack>=7
actions+=/call_action_list,name=standard
]]
	Player.use_cds = Target.boss or Target.timeToDie > (12 - min(Player.enemies, 6))
	Player.pooling_for_bonestorm = Bonestorm.known and Player.enemies >= 3 and not self.drw_up and Bonestorm:Ready(4)
	self.bs_remains = BoneShield:Remains()
	self.bs_stack = self.bs_remains == 0 and 0 or BoneShield:Stack()
	self.drw_up = DancingRuneWeapon:Up()
	if Opt.trinket then
		if Trinket1:Usable() and (not DancingRuneWeapon:Ready(90) or Trinket1.itemId == 159611 or Trinket1.itemId == 158367) then
			UseCooldown(Trinket1)
		elseif Trinket2:Usable() and (not DancingRuneWeapon:Ready(90) or Trinket2.itemId == 159611 or Trinket2.itemId == 158367) then
			UseCooldown(Trinket2)
		end
	end
	if Opt.pot and Target.boss and PotionOfUnbridledFury:Usable() and self.drw_up then
		UseCooldown(PotionOfUnbridledFury)
	end
	if Player.use_cds and not self.drw_up and DancingRuneWeapon:Usable() and not Player.pooling_for_bonestorm and (not Blooddrinker.known or not Blooddrinker:Ready()) then
		UseCooldown(DancingRuneWeapon)
	end
	if Player.use_cds and Tombstone:Usable() and self.bs_stack >= 7 then
		UseCooldown(Tombstone)
	end
	return self:standard()
end

APL[SPEC.BLOOD].standard = function(self)
--[[
actions.standard=death_strike,if=runic_power.deficit<=10
actions.standard+=/blooddrinker,if=!buff.dancing_rune_weapon.up
actions.standard+=/marrowrend,if=(buff.bone_shield.remains<=rune.time_to_3|buff.bone_shield.remains<=(gcd+cooldown.blooddrinker.ready*talent.blooddrinker.enabled*2)|buff.bone_shield.stack<3)&runic_power.deficit>=20
actions.standard+=/blood_boil,if=charges_fractional>=1.8&(buff.hemostasis.stack<=(5-spell_targets.blood_boil)|spell_targets.blood_boil>2)
actions.standard+=/marrowrend,if=buff.bone_shield.stack<5&talent.ossuary.enabled&runic_power.deficit>=15
actions.standard+=/bonestorm,if=runic_power>=100&!buff.dancing_rune_weapon.up
actions.standard+=/death_strike,if=runic_power.deficit<=(15+buff.dancing_rune_weapon.up*5+spell_targets.heart_strike*talent.heartbreaker.enabled*2)|target.time_to_die<10
actions.standard+=/death_and_decay,if=spell_targets.death_and_decay>=3
actions.standard+=/rune_strike,if=(charges_fractional>=1.8|buff.dancing_rune_weapon.up)&rune.time_to_3>=gcd
actions.standard+=/heart_strike,if=buff.dancing_rune_weapon.up|rune.time_to_4<gcd
actions.standard+=/blood_boil,if=buff.dancing_rune_weapon.up
actions.standard+=/death_and_decay,if=buff.crimson_scourge.up|talent.rapid_decomposition.enabled|spell_targets.death_and_decay>=2
actions.standard+=/consumption
actions.standard+=/blood_boil
actions.standard+=/heart_strike,if=rune.time_to_3<gcd|buff.bone_shield.stack>6
actions.standard+=/use_item,name=grongs_primal_rage
actions.standard+=/rune_strike
actions.standard+=/arcane_torrent,if=runic_power.deficit>20
]]
	if DeathStrike:Usable() and Player:RunicPowerDeficit() <= 10 and (not Player.pooling_for_bonestorm or not Bonestorm:Ready(2)) then
		return DeathStrike
	end
	if Blooddrinker:Usable() and not self.drw_up and Player:HealthPct() < 80 then
		return Blooddrinker
	end
	if Marrowrend:Usable() then
		if Player:RunicPowerDeficit() >= 20 and (self.bs_remains <= Player:RuneTimeTo(3) or self.bs_stack < 3) then
			return Marrowrend
		end
		if self.bs_stack < 1 or self.bs_remains <= (Player.gcd * 2 + (Blooddrinker.known and Blooddrinker:Ready() and 3 or 0)) then
			return Marrowrend
		end
	end
	if BloodBoil:Usable() then
		if BloodBoil:ChargesFractional() >= 1.8 and (Player.enemies > 2 or (Hemostasis.known and Hemostasis:Stack() <= (5 - Player.enemies))) then
			return BloodBoil
		end
		if Hemostasis.known and DeathStrike:Usable() and Player:HealthPct() < 60 and Hemostasis:Stack() <= (5 - Player.enemies) then
			return BloodBoil
		end
		if BloodPlague:Down() or BloodPlague:Ticking() < Player.enemies then
			return BloodBoil
		end
	end
	if Ossuary.known and Marrowrend:Usable() and self.bs_stack < 5 and Player:RunicPowerDeficit() >= 15 then
		return Marrowrend
	end
	if Player.pooling_for_bonestorm and Bonestorm:Usable() and Player:RunicPower() >= 100 then
		UseCooldown(Bonestorm)
	end
	if DeathStrike:Usable() then
		if Player.enemies == 1 and Target.timeToDie < 2 then
			return DeathStrike
		end
		if Hemostasis.known then
			if Player:HealthPct() < 60 and Hemostasis:Stack() >= 5 then
				return DeathStrike
			end
			if Player:HealthPct() < 40 and not BloodBoil:Ready() then
				return DeathStrike
			end
		elseif Player:HealthPct() < 40 then
			return DeathStrike
		end
	end
	if DeathAndDecay:Usable() and Player.enemies >= 3 then
		return DeathAndDecay
	end
	if DeathStrike:Usable() and not Player.pooling_for_bonestorm and Player:RunicPowerDeficit() <= (15 + (self.drw_up and 5 or 0) + (Heartbreaker.known and HeartStrike:Targets() * 2 or 0)) then
		return DeathStrike
	end
	if RuneStrike:Usable() and Player:RuneTimeTo(3) >= Player.gcd and (RuneStrike:ChargesFractional() >= 1.8 or self.drw_up) then
		return RuneStrike
	end
	if HeartStrike:Usable() then
		if self.drw_up or Player:RuneTimeTo(4) < Player.gcd then
			return HeartStrike
		end
		if HeartStrike:Targets() >= 4 then
			return HeartStrike
		end
	end
	if BloodBoil:Usable() then
		if self.drw_up then
			return BloodBoil
		end
		if Hemostasis.known and Player:HealthPct() < 60 and Hemostasis:Stack() <= (5 - Player.enemies) then
			return BloodBoil
		end
	end
	if DeathAndDecay:Usable() and (Player.enemies >= 2 or Target.timeToDie > 4 and (RapidDecomposition.known or CrimsonScourge:Up())) then
		return DeathAndDecay
	end
	if Player.use_cds and Bonestorm:Usable() and Player.enemies >= 2 and Target.timeToDie > 8 and Player:RunicPower() >= 100 then
		UseCooldown(Bonestorm)
	end
	if Player.use_cds and Consumption:Usable() then
		UseCooldown(Consumption)
	end
	if BloodBoil:Usable() then
		return BloodBoil
	end
	if HeartStrike:Usable() and (Player:RuneTimeTo(3) < Player.gcd or self.bs_stack > 6) then
		return HeartStrike
	end
	if RuneStrike:Usable() then
		return RuneStrike
	end
	if not Player.pooling_for_bonestorm and DeathStrike:Usable() and Player:RunicPowerDeficit() <= 30 and self.bs_stack >= 5 and self.bs_remains > (Player.gcd + Player:RuneTimeTo(3)) then
		return DeathStrike
	end
	if HeartStrike:Usable() and Player.enemies == 1 and self.bs_stack >= 5 and self.bs_remains > Target.timeToDie then
		return HeartStrike
	end
	if ArcaneTorrent:Usable() and Player:RunicPowerDeficit() > 20 then
		UseExtra(ArcaneTorrent)
	end
end

APL[SPEC.FROST].main = function(self)
	if Player:TimeInCombat() == 0 then
		if Opt.pot and not Player:InArenaOrBattleground() then
			if GreaterFlaskOfTheUndertow:Usable() and GreaterFlaskOfTheUndertow.buff:Remains() < 300 then
				UseCooldown(GreaterFlaskOfTheUndertow)
			end
			if Target.boss and PotionOfUnbridledFury:Usable() then
				UseCooldown(PotionOfUnbridledFury)
			end
		end
	end
end

APL[SPEC.UNHOLY].main = function(self)
	Player.use_cds = Target.boss or Target.timeToDie > (12 - min(Player.enemies, 6))
	Player.pooling_for_aotd = ArmyOfTheDead.known and Target.boss and ArmyOfTheDead:Ready(5)
	Player.pooling_for_gargoyle = Player.use_cds and SummonGargoyle.known and SummonGargoyle:Ready(5)

	if not Player.pet_active and RaiseDead:Usable() then
		UseExtra(RaiseDead)
	end
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
# Snapshot raid buffed stats before combat begins and pre-potting is done.
actions.precombat+=/snapshot_stats
actions.precombat+=/potion
actions.precombat+=/raise_dead
actions.precombat+=/army_of_the_dead,delay=2
]]
		if Opt.pot and not Player:InArenaOrBattleground() then
			if GreaterFlaskOfTheUndertow:Usable() and GreaterFlaskOfTheUndertow.buff:Remains() < 300 then
				UseCooldown(GreaterFlaskOfTheUndertow)
			end
			if Target.boss and PotionOfUnbridledFury:Usable() then
				UseCooldown(PotionOfUnbridledFury)
			end
		end
		if Target.boss then
			if ArmyOfTheDead:Usable() then
				UseCooldown(ArmyOfTheDead)
			end
			if RaiseAbomination:Usable() then
				UseCooldown(RaiseAbomination)
			end
		end
	end
--[[
actions+=/variable,name=pooling_for_gargoyle,value=cooldown.summon_gargoyle.remains<5&talent.summon_gargoyle.enabled
actions+=/arcane_torrent,if=runic_power.deficit>65&(pet.gargoyle.active|!talent.summon_gargoyle.enabled)&rune.deficit>=5
actions+=/potion,if=cooldown.army_of_the_dead.ready|pet.gargoyle.active|buff.unholy_frenzy.up
# Maintaining Virulent Plague is a priority
actions+=/outbreak,target_if=dot.virulent_plague.remains<=gcd
actions+=/call_action_list,name=cooldowns
actions+=/run_action_list,name=aoe,if=active_enemies>=2
actions+=/call_action_list,name=generic
]]
	if ArcaneTorrent:Usable() and Player:RunicPowerDeficit() > 65 and (SummonGargoyle:Up() or not SummonGargoyle.known) and Player:RuneDeficit() >= 5 then
		UseExtra(ArcaneTorrent)
	end
	if Opt.pot and Target.boss and PotionOfUnbridledFury:Usable() and (ArmyOfTheDead:Ready() or SummonGargoyle:Up() or UnholyFrenzy:Up()) then
		UseExtra(PotionOfUnbridledFury)
	end
	if Outbreak:Usable() and Outbreak:Ticking() < 1 and VirulentPlague:Remains() <= Player.gcd and Target.timeToDie > (VirulentPlague:Remains() + 1) then
		return Outbreak
	end
	self:cooldowns()
	if Player.enemies >= 2 then
		return self:aoe()
	end
	return self:generic()
end

APL[SPEC.UNHOLY].cooldowns = function(self)
--[[
actions.cooldowns=army_of_the_dead
actions.cooldowns+=/apocalypse,if=debuff.festering_wound.stack>=4
actions.cooldowns+=/dark_transformation,if=!raid_event.adds.exists|raid_event.adds.in>15
actions.cooldowns+=/summon_gargoyle,if=runic_power.deficit<14
actions.cooldowns+=/unholy_frenzy,if=debuff.festering_wound.stack<4&!(equipped.ramping_amplitude_gigavolt_engine|azerite.magus_of_the_dead.enabled)
actions.cooldowns+=/unholy_frenzy,if=cooldown.apocalypse.remains<2&(equipped.ramping_amplitude_gigavolt_engine|azerite.magus_of_the_dead.enabled)
actions.cooldowns+=/unholy_frenzy,if=active_enemies>=2&((cooldown.death_and_decay.remains<=gcd&!talent.defile.enabled)|(cooldown.defile.remains<=gcd&talent.defile.enabled))
actions.cooldowns+=/soul_reaper,target_if=target.time_to_die<8&target.time_to_die>4
actions.cooldowns+=/soul_reaper,if=(!raid_event.adds.exists|raid_event.adds.in>20)&rune<=(1-buff.unholy_frenzy.up)
actions.cooldowns+=/unholy_blight
]]
	if Player.use_cds then
		if Player.pooling_for_aotd and ArmyOfTheDead:Usable() then
			return UseCooldown(ArmyOfTheDead)
		end
		if RaiseAbomination:Usable() then
			return UseCooldown(RaiseAbomination)
		end
		if Apocalypse:Usable() and FesteringWound:Stack() >= 4 then
			return UseCooldown(Apocalypse)
		end
		if DarkTransformation:Usable() then
			return UseCooldown(DarkTransformation)
		end
		if SummonGargoyle:Usable() and Player:RunicPowerDeficit() < 14 then
			return UseCooldown(SummonGargoyle)
		end
		if UnholyFrenzy:Usable() then
			if MagusOfTheDead.known or (Trinket1.itemId == 165580 or Trinket2.itemId == 165580) then
				if Apocalypse:Ready(2) then
					return UseCooldown(UnholyFrenzy)
				end
			elseif FesteringWound:Stack() < 4 then
				return UseCooldown(UnholyFrenzy)
			end
			if Player.enemies >= 2 and ((DeathAndDecay:Ready(Player.gcd) and not Defile.known) or (Defile.known and Defile:Ready(Player.gcd))) then
				return UseCooldown(UnholyFrenzy)
			end
		end
	end
	if SoulReaper:Usable() then
		if between(Target.timeToDie, 4, 8) then
			return UseCooldown(SoulReaper)
		end
		if Player.enemies == 1 and Player:Runes() <= (UnholyFrenzy:Up() and 1 or 0) then
			return UseCooldown(SoulReaper)
		end
	end
	if UnholyBlight:Usable() then
		return UseCooldown(UnholyBlight)
	end
end

APL[SPEC.UNHOLY].aoe = function(self)
--[[
actions.aoe=death_and_decay,if=cooldown.apocalypse.remains
actions.aoe+=/defile
actions.aoe+=/epidemic,if=death_and_decay.ticking&rune<2&!variable.pooling_for_gargoyle
actions.aoe+=/death_coil,if=death_and_decay.ticking&rune<2&!variable.pooling_for_gargoyle
actions.aoe+=/scourge_strike,if=death_and_decay.ticking&cooldown.apocalypse.remains&(!talent.bursting_sores.enabled|debuff.festering_wound.up)
actions.aoe+=/clawing_shadows,if=death_and_decay.ticking&cooldown.apocalypse.remains&(!talent.bursting_sores.enabled|debuff.festering_wound.up)
actions.aoe+=/epidemic,if=!variable.pooling_for_gargoyle
actions.aoe+=/festering_strike,target_if=debuff.festering_wound.stack<=1&cooldown.death_and_decay.remains
actions.aoe+=/festering_strike,if=talent.bursting_sores.enabled&spell_targets.bursting_sores>=2&debuff.festering_wound.stack<=1
actions.aoe+=/death_coil,if=buff.sudden_doom.react&rune.deficit>=4
actions.aoe+=/death_coil,if=buff.sudden_doom.react&!variable.pooling_for_gargoyle|pet.gargoyle.active
actions.aoe+=/death_coil,if=runic_power.deficit<14&(cooldown.apocalypse.remains>5|debuff.festering_wound.stack>4)&!variable.pooling_for_gargoyle
actions.aoe+=/scourge_strike,if=((debuff.festering_wound.up&cooldown.apocalypse.remains>5)|debuff.festering_wound.stack>4)&cooldown.army_of_the_dead.remains>5
actions.aoe+=/clawing_shadows,if=((debuff.festering_wound.up&cooldown.apocalypse.remains>5)|debuff.festering_wound.stack>4)&cooldown.army_of_the_dead.remains>5
actions.aoe+=/death_coil,if=runic_power.deficit<20&!variable.pooling_for_gargoyle
actions.aoe+=/festering_strike,if=((((debuff.festering_wound.stack<4&!buff.unholy_frenzy.up)|debuff.festering_wound.stack<3)&cooldown.apocalypse.remains<3)|debuff.festering_wound.stack<1)&cooldown.army_of_the_dead.remains>5
actions.aoe+=/death_coil,if=!variable.pooling_for_gargoyle
]]
	if Outbreak:Usable() and Outbreak:Ticking() < 1 and VirulentPlague:Ticking() < Player.enemies then
		return Outbreak
	end
	local apocalypse_not_ready = not Player.use_cds or not Apocalypse.known or not Apocalypse:Ready()
	if DeathAndDecay:Usable() and apocalypse_not_ready and Target.timeToDie > max(6 - Player.enemies, 2) then
		return DeathAndDecay
	end
	if Defile:Usable() then
		return Defile
	end
	if DeathAndDecay:Up() then
		if not Player.pooling_for_gargoyle and Player:Runes() < 2 then
			if Epidemic:Usable() and VirulentPlague:Ticking() >= 2 then
				return Epidemic
			end
			if DeathCoil:Usable() then
				return DeathCoil
			end
		end
		if apocalypse_not_ready and (not BurstingSores.known or FesteringWound:Up()) then
			if ScourgeStrike:Usable() then
				return ScourgeStrike
			end
			if ClawingShadows:Usable() then
				return ClawingShadows
			end
		end
	end
	if Epidemic:Usable() and not Player.pooling_for_gargoyle and VirulentPlague:Ticking() >= 2 then
		return Epidemic
	end
	if FesteringStrike:Usable() and FesteringWound:Stack() <= 1 then
		if not DeathAndDecay:Ready() then
			return FesteringStrike
		end
		if BurstingSores.known and Player.enemies >= 2 then
			return FesteringStrike
		end
	end
	local apocalypse_not_ready_5 = not Player.use_cds or not Apocalypse.known or not Apocalypse:Ready(5)
	if DeathCoil:Usable() then
		if SuddenDoom:Up() and (Player:RuneDeficit() >= 4 or not Player.pooling_for_gargoyle) then
			return DeathCoil
		end
		if SummonGargoyle:Up() then
			return DeathCoil
		end
		if not Player.pooling_for_gargoyle and Player:RunicPowerDeficit() < 14 and (apocalypse_not_ready_5 or FesteringWound:Stack() > 4) then
			return DeathCoil
		end
	end
	if not Player.pooling_for_aotd and ((FesteringWound:Up() and apocalypse_not_ready_5) or FesteringWound:Stack() > 4) then
		if ScourgeStrike:Usable() then
			return ScourgeStrike
		end
		if ClawingShadows:Usable() then
			return ClawingShadows
		end
	end
	if Player:RunicPowerDeficit() < 20 and not Player.pooling_for_gargoyle then
		if Player:HealthPct() < Opt.death_strike_threshold and DeathStrike:Usable() then
			return DeathStrike
		end
		if DeathCoil:Usable() then
			return DeathCoil
		end
	end
	if not Player.pooling_for_aotd and FesteringStrike:Usable() and ((((FesteringWound:Stack() < 4 and UnholyFrenzy:Down()) or FesteringWound:Stack() < 3) and Apocalypse:Ready(3)) or FesteringWound:Stack() < 1) then
		return FesteringStrike
	end
	if DeathStrike:Usable() and DarkSuccor:Up() then
		return DeathStrike
	end
	if not Player.pooling_for_gargoyle then
		if Player:HealthPct() < Opt.death_strike_threshold and DeathStrike:Usable() then
			return DeathStrike
		end
		if DeathCoil:Usable() then
			return DeathCoil
		end
	end
	if SoulReaper:Usable() then
		if Player:Runes() <= (UnholyFrenzy:Up() and 1 or 0) then
			return SoulReaper
		end
	end
	if ConcentratedFlame:Usable() and ConcentratedFlame.dot:Down() then
		return ConcentratedFlame
	end
end

APL[SPEC.UNHOLY].generic = function(self)
--[[
actions.generic=death_coil,if=buff.sudden_doom.react&!variable.pooling_for_gargoyle|pet.gargoyle.active
actions.generic+=/death_coil,if=runic_power.deficit<14&(cooldown.apocalypse.remains>5|debuff.festering_wound.stack>4)&!variable.pooling_for_gargoyle
actions.generic+=/death_and_decay,if=talent.pestilence.enabled&cooldown.apocalypse.remains
actions.generic+=/defile,if=cooldown.apocalypse.remains
actions.generic+=/scourge_strike,if=((debuff.festering_wound.up&cooldown.apocalypse.remains>5)|debuff.festering_wound.stack>4)&cooldown.army_of_the_dead.remains>5
actions.generic+=/clawing_shadows,if=((debuff.festering_wound.up&cooldown.apocalypse.remains>5)|debuff.festering_wound.stack>4)&cooldown.army_of_the_dead.remains>5
actions.generic+=/death_coil,if=runic_power.deficit<20&!variable.pooling_for_gargoyle
actions.generic+=/festering_strike,if=((((debuff.festering_wound.stack<4&!buff.unholy_frenzy.up)|debuff.festering_wound.stack<3)&cooldown.apocalypse.remains<3)|debuff.festering_wound.stack<1)&cooldown.army_of_the_dead.remains>5
actions.generic+=/death_coil,if=!variable.pooling_for_gargoyle
]]
	local apocalypse_not_ready_5 = not Player.use_cds or not Apocalypse.known or not Apocalypse:Ready(5)
	if DeathCoil:Usable() then
		if SummonGargoyle:Up() or (SuddenDoom:Up() and not Player.pooling_for_gargoyle) then
			return DeathCoil
		end
		if not Player.pooling_for_gargoyle and Player:RunicPowerDeficit() < 14 and (apocalypse_not_ready_5 or FesteringWound:Stack() > 4) then
			return DeathCoil
		end
	end
	local apocalypse_not_ready = not Player.use_cds or not Apocalypse.known or not Apocalypse:Ready()
	if apocalypse_not_ready then
		if Pestilence.known and DeathAndDecay:Usable() and Target.timeToDie > 6 then
			return DeathAndDecay
		end
		if Defile:Usable() then
			return Defile
		end
	end
	if not Player.pooling_for_aotd and ((FesteringWound:Up() and apocalypse_not_ready_5) or FesteringWound:Stack() > 4) then
		if ScourgeStrike:Usable() then
			return ScourgeStrike
		end
		if ClawingShadows:Usable() then
			return ClawingShadows
		end
	end
	if Player:RunicPowerDeficit() < 20 and not Player.pooling_for_gargoyle then
		if Player:HealthPct() < Opt.death_strike_threshold and DeathStrike:Usable() then
			return DeathStrike
		end
		if DeathCoil:Usable() then
			return DeathCoil
		end
	end
	if not Player.pooling_for_aotd and FesteringStrike:Usable() and ((((FesteringWound:Stack() < 4 and UnholyFrenzy:Down()) or FesteringWound:Stack() < 3) and Apocalypse:Ready(3)) or FesteringWound:Stack() < 1) then
		return FesteringStrike
	end
	if DeathStrike:Usable() and DarkSuccor:Up() then
		return DeathStrike
	end
	if not Player.pooling_for_gargoyle then
		if Player:HealthPct() < Opt.death_strike_threshold and DeathStrike:Usable() then
			return DeathStrike
		end
		if DeathCoil:Usable() then
			return DeathCoil
		end
	end
	if ConcentratedFlame:Usable() and ConcentratedFlame.dot:Down() then
		return ConcentratedFlame
	end
	if SoulReaper:Usable() then
		if Player:Runes() <= (UnholyFrenzy:Up() and 1 or 0) then
			return SoulReaper
		end
	end
end

APL.Interrupt = function(self)
	if MindFreeze:Usable() then
		return MindFreeze
	end
	if Asphyxiate:Usable() then
		return Asphyxiate
	end
end

-- End Action Priority Lists

-- Start UI API

function UI.DenyOverlayGlow(actionButton)
	if not Opt.glow.blizzard then
		actionButton.overlay:Hide()
	end
end
hooksecurefunc('ActionButton_ShowOverlayGlow', UI.DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

function UI:UpdateGlowColorAndScale()
	local w, h, glow, i
	local r = Opt.glow.color.r
	local g = Opt.glow.color.g
	local b = Opt.glow.color.b
	for i = 1, #self.glows do
		glow = self.glows[i]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
		glow.spark:SetVertexColor(r, g, b)
		glow.innerGlow:SetVertexColor(r, g, b)
		glow.innerGlowOver:SetVertexColor(r, g, b)
		glow.outerGlow:SetVertexColor(r, g, b)
		glow.outerGlowOver:SetVertexColor(r, g, b)
		glow.ants:SetVertexColor(r, g, b)
	end
end

function UI:CreateOverlayGlows()
	local b, i
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.button = button
			self.glows[#self.glows + 1] = glow
		end
	end
	for i = 1, 12 do
		GenerateGlow(_G['ActionButton' .. i])
		GenerateGlow(_G['MultiBarLeftButton' .. i])
		GenerateGlow(_G['MultiBarRightButton' .. i])
		GenerateGlow(_G['MultiBarBottomLeftButton' .. i])
		GenerateGlow(_G['MultiBarBottomRightButton' .. i])
	end
	for i = 1, 10 do
		GenerateGlow(_G['PetActionButton' .. i])
	end
	if Bartender4 then
		for i = 1, 120 do
			GenerateGlow(_G['BT4Button' .. i])
		end
	end
	if Dominos then
		for i = 1, 60 do
			GenerateGlow(_G['DominosActionButton' .. i])
		end
	end
	if ElvUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['ElvUI_Bar' .. b .. 'Button' .. i])
			end
		end
	end
	if LUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['LUIBarBottom' .. b .. 'Button' .. i])
				GenerateGlow(_G['LUIBarLeft' .. b .. 'Button' .. i])
				GenerateGlow(_G['LUIBarRight' .. b .. 'Button' .. i])
			end
		end
	end
	UI:UpdateGlowColorAndScale()
end

function UI:UpdateGlows()
	local glow, icon, i
	for i = 1, #self.glows do
		glow = self.glows[i]
		icon = glow.button.icon:GetTexture()
		if icon and glow.button.icon:IsVisible() and (
			(Opt.glow.main and Player.main and icon == Player.main.icon) or
			(Opt.glow.cooldown and Player.cd and icon == Player.cd.icon) or
			(Opt.glow.interrupt and Player.interrupt and icon == Player.interrupt.icon) or
			(Opt.glow.extra and Player.extra and icon == Player.extra.icon)
			) then
			if not glow:IsVisible() then
				glow.animIn:Play()
			end
		elseif glow:IsVisible() then
			glow.animIn:Stop()
			glow:Hide()
		end
	end
end

function UI:UpdateDraggable()
	braindeadPanel:EnableMouse(Opt.aoe or not Opt.locked)
	braindeadPanel.button:SetShown(Opt.aoe)
	if Opt.locked then
		braindeadPanel:SetScript('OnDragStart', nil)
		braindeadPanel:SetScript('OnDragStop', nil)
		braindeadPanel:RegisterForDrag(nil)
		braindeadPreviousPanel:EnableMouse(false)
		braindeadCooldownPanel:EnableMouse(false)
		braindeadInterruptPanel:EnableMouse(false)
		braindeadExtraPanel:EnableMouse(false)
	else
		if not Opt.aoe then
			braindeadPanel:SetScript('OnDragStart', braindeadPanel.StartMoving)
			braindeadPanel:SetScript('OnDragStop', braindeadPanel.StopMovingOrSizing)
			braindeadPanel:RegisterForDrag('LeftButton')
		end
		braindeadPreviousPanel:EnableMouse(true)
		braindeadCooldownPanel:EnableMouse(true)
		braindeadInterruptPanel:EnableMouse(true)
		braindeadExtraPanel:EnableMouse(true)
	end
end

function UI:UpdateAlpha()
	braindeadPanel:SetAlpha(Opt.alpha)
	braindeadPreviousPanel:SetAlpha(Opt.alpha)
	braindeadCooldownPanel:SetAlpha(Opt.alpha)
	braindeadInterruptPanel:SetAlpha(Opt.alpha)
	braindeadExtraPanel:SetAlpha(Opt.alpha)
end

function UI:UpdateScale()
	braindeadPanel:SetSize(64 * Opt.scale.main, 64 * Opt.scale.main)
	braindeadPreviousPanel:SetSize(64 * Opt.scale.previous, 64 * Opt.scale.previous)
	braindeadCooldownPanel:SetSize(64 * Opt.scale.cooldown, 64 * Opt.scale.cooldown)
	braindeadInterruptPanel:SetSize(64 * Opt.scale.interrupt, 64 * Opt.scale.interrupt)
	braindeadExtraPanel:SetSize(64 * Opt.scale.extra, 64 * Opt.scale.extra)
end

function UI:SnapAllPanels()
	braindeadPreviousPanel:ClearAllPoints()
	braindeadPreviousPanel:SetPoint('TOPRIGHT', braindeadPanel, 'BOTTOMLEFT', -3, 40)
	braindeadCooldownPanel:ClearAllPoints()
	braindeadCooldownPanel:SetPoint('TOPLEFT', braindeadPanel, 'BOTTOMRIGHT', 3, 40)
	braindeadInterruptPanel:ClearAllPoints()
	braindeadInterruptPanel:SetPoint('BOTTOMLEFT', braindeadPanel, 'TOPRIGHT', 3, -21)
	braindeadExtraPanel:ClearAllPoints()
	braindeadExtraPanel:SetPoint('BOTTOMRIGHT', braindeadPanel, 'TOPLEFT', -3, -21)
end

UI.anchor_points = {
	blizzard = { -- Blizzard Personal Resource Display (Default)
		[SPEC.BLOOD] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 49 },
			['below'] = { 'TOP', 'BOTTOM', 0, -3 }
		},
		[SPEC.FROST] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 49 },
			['below'] = { 'TOP', 'BOTTOM', 0, -3 }
		},
		[SPEC.UNHOLY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 49 },
			['below'] = { 'TOP', 'BOTTOM', 0, -3 }
		},
	},
	kui = { -- Kui Nameplates
		[SPEC.BLOOD] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, 6 }
		},
		[SPEC.FROST] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, 6 }
		},
		[SPEC.UNHOLY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, 6 }
		},
	},
}

function UI.OnResourceFrameHide()
	if Opt.snap then
		braindeadPanel:ClearAllPoints()
	end
end

function UI.OnResourceFrameShow()
	if Opt.snap then
		local p = UI.anchor.points[Player.spec][Opt.snap]
		braindeadPanel:ClearAllPoints()
		braindeadPanel:SetPoint(p[1], UI.anchor.frame, p[2], p[3], p[4])
		UI:SnapAllPanels()
	end
end

function UI:HookResourceFrame()
	if KuiNameplatesCoreSaved and KuiNameplatesCoreCharacterSaved and
		not KuiNameplatesCoreSaved.profiles[KuiNameplatesCoreCharacterSaved.profile].use_blizzard_personal
	then
		self.anchor.points = self.anchor_points.kui
		self.anchor.frame = KuiNameplatesPlayerAnchor
	else
		self.anchor.points = self.anchor_points.blizzard
		self.anchor.frame = NamePlateDriverFrame:GetClassNameplateBar()
	end
	if self.anchor.frame then
		self.anchor.frame:HookScript('OnHide', self.OnResourceFrameHide)
		self.anchor.frame:HookScript('OnShow', self.OnResourceFrameShow)
	end
end

function UI:ShouldHide()
	return (Player.spec == SPEC.NONE or
		   (Player.spec == SPEC.BLOOD and Opt.hide.blood) or
		   (Player.spec == SPEC.FROST and Opt.hide.frost) or
		   (Player.spec == SPEC.UNHOLY and Opt.hide.unholy))
end

function UI:Disappear()
	braindeadPanel:Hide()
	braindeadPanel.icon:Hide()
	braindeadPanel.border:Hide()
	braindeadCooldownPanel:Hide()
	braindeadInterruptPanel:Hide()
	braindeadExtraPanel:Hide()
	Player.main = nil
	Player.cd = nil
	Player.interrupt = nil
	Player.extra = nil
	UI:UpdateGlows()
end

function UI:UpdateDisplay()
	timer.display = 0
	local dim, text_center
	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
	end
	if Player.pooling_for_bonestorm then
		braindeadPanel.text.center:SetText('Pool for\n' .. Bonestorm.name)
		text_center = true
	elseif Player.pooling_for_aotd then
		braindeadPanel.text.center:SetText('Pool for\n' .. ArmyOfTheDead.name)
		text_center = true
	elseif Player.pooling_for_gargoyle then
		braindeadPanel.text.center:SetText('Pool for\n' .. SummonGargoyle.name)
		text_center = true
	end
	braindeadPanel.dimmer:SetShown(dim)
	braindeadPanel.text.center:SetShown(text_center)
end

function UI:UpdateCombat()
	timer.combat = 0
	local _, start, duration, remains, spellId
	Player.ctime = GetTime()
	Player.time = Player.ctime - Player.time_diff
	Player.main =  nil
	Player.cd = nil
	Player.interrupt = nil
	Player.extra = nil
	start, duration = GetSpellCooldown(61304)
	Player.gcd_remains = start > 0 and duration - (Player.ctime - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	Player.ability_casting = abilities.bySpellId[spellId]
	Player.execute_remains = max(remains and (remains / 1000 - Player.ctime) or 0, Player.gcd_remains)
	Player.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	Player.gcd = 1.5 * Player.haste_factor
	Player.health = UnitHealth('player')
	Player.health_max = UnitHealthMax('player')
	_, Player.rune_regen = GetRuneCooldown(1)
	Player.runic_power = UnitPower('player', 6)
	Player:UpdatePet()
	Player:UpdateRunes()

	trackAuras:Purge()
	if Opt.auto_aoe then
		local ability
		for _, ability in next, abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		autoAoe:Purge()
	end

	Player.main = APL[Player.spec]:main()
	if Player.main then
		braindeadPanel.icon:SetTexture(Player.main.icon)
	end
	if Player.cd then
		braindeadCooldownPanel.icon:SetTexture(Player.cd.icon)
	end
	if Player.extra then
		braindeadExtraPanel.icon:SetTexture(Player.extra.icon)
	end
	if Opt.interrupt then
		local ends, notInterruptible
		_, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
		if not start then
			_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
		end
		if start and not notInterruptible then
			Player.interrupt = APL.Interrupt()
			braindeadInterruptPanel.cast:SetCooldown(start / 1000, (ends - start) / 1000)
		end
		if Player.interrupt then
			braindeadInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		end
		braindeadInterruptPanel.icon:SetShown(Player.interrupt)
		braindeadInterruptPanel.border:SetShown(Player.interrupt)
		braindeadInterruptPanel:SetShown(start and not notInterruptible)
	end
	braindeadPanel.icon:SetShown(Player.main)
	braindeadPanel.border:SetShown(Player.main)
	braindeadCooldownPanel:SetShown(Player.cd)
	braindeadExtraPanel:SetShown(Player.extra)
	self:UpdateDisplay()
	self:UpdateGlows()
end

function UI:UpdateCombatWithin(seconds)
	if Opt.frequency - timer.combat > seconds then
		timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

-- End UI API

-- Start Event Handling

function events:ADDON_LOADED(name)
	if name == 'Braindead' then
		Opt = Braindead
		if not Opt.frequency then
			print('It looks like this is your first time running ' .. name .. ', why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_Braindead1 .. '|r for a list of commands.')
		end
		if UnitLevel('player') < 110 then
			print('[|cFFFFD000Warning|r] ' .. name .. ' is not designed for players under level 110, and almost certainly will not operate properly!')
		end
		InitOpts()
		Azerite:Init()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		UI:SnapAllPanels()
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED()
	local timeStamp, eventType, _, srcGUID, _, _, _, dstGUID, _, _, _, spellId, spellName, _, missType = CombatLogGetCurrentEventInfo()
	Player.time = timeStamp
	Player.ctime = GetTime()
	Player.time_diff = Player.ctime - Player.time

	if eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
		trackAuras:Remove(dstGUID)
		if Opt.auto_aoe then
			autoAoe:Remove(dstGUID)
		end
	end
	if Opt.auto_aoe and (eventType == 'SWING_DAMAGE' or eventType == 'SWING_MISSED') then
		if dstGUID == Player.guid or dstGUID == Player.pet then
			autoAoe:Add(srcGUID, true)
		elseif (srcGUID == Player.guid or srcGUID == Player.pet) and not (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:Add(dstGUID, true)
		end
	end

	if (srcGUID ~= Player.guid and srcGUID ~= Player.pet) then
		return
	end

	if srcGUID == Player.pet then
		if Player.pet_stuck and (eventType == 'SPELL_CAST_SUCCESS' or eventType == 'SPELL_DAMAGE' or eventType == 'SWING_DAMAGE') then
			Player.pet_stuck = false
		elseif not Player.pet_stuck and eventType == 'SPELL_CAST_FAILED' and missType == 'No path available' then
			Player.pet_stuck = true
		end
	end

	local ability = spellId and abilities.bySpellId[spellId]
	if not ability then
		--print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', eventType, spellName, spellId))
		return
	end

	if not (
	   eventType == 'SPELL_CAST_START' or
	   eventType == 'SPELL_CAST_SUCCESS' or
	   eventType == 'SPELL_CAST_FAILED' or
	   eventType == 'SPELL_AURA_REMOVED' or
	   eventType == 'SPELL_DAMAGE' or
	   eventType == 'SPELL_PERIODIC_DAMAGE' or
	   eventType == 'SPELL_MISSED' or
	   eventType == 'SPELL_AURA_APPLIED' or
	   eventType == 'SPELL_AURA_REFRESH' or
	   eventType == 'SPELL_AURA_REMOVED')
	then
		return
	end

	UI:UpdateCombatWithin(0.05)
	if eventType == 'SPELL_CAST_SUCCESS' then
		if srcGUID == Player.guid or ability.player_triggered then
			Player.last_ability = ability
			if ability.triggers_gcd then
				Player.previous_gcd[10] = nil
				table.insert(Player.previous_gcd, 1, ability)
			end
			if ability.travel_start then
				ability.travel_start[dstGUID] = Player.time
			end
			if Opt.previous and braindeadPanel:IsVisible() then
				braindeadPreviousPanel.ability = ability
				braindeadPreviousPanel.border:SetTexture('Interface\\AddOns\\Braindead\\border.blp')
				braindeadPreviousPanel.icon:SetTexture(ability.icon)
				braindeadPreviousPanel:Show()
			end
		end
		if Player.pet_stuck and ability.requires_pet then
			Player.pet_stuck = false
		end
		return
	end
	if eventType == 'SPELL_CAST_FAILED' then
		if ability.requires_pet and missType == 'No path available' then
			Player.pet_stuck = true
		end
		return
	end
	if dstGUID == Player.guid or dstGUID == Player.pet then
		return -- ignore buffs beyond here
	end
	if ability.aura_targets then
		if eventType == 'SPELL_AURA_APPLIED' then
			ability:ApplyAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REFRESH' then
			ability:RefreshAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REMOVED' then
			ability:RemoveAura(dstGUID)
		end
		if ability == Outbreak then
			VirulentPlague:RefreshAuraAll()
		elseif ability == VirulentPlague and eventType == 'SPELL_PERIODIC_DAMAGE' then
			if not ability.aura_targets[dstGUID] then
				ability:ApplyAura(dstGUID) -- BUG: VP tick on unrecorded target, assume freshly applied (possibly by Raise Abomination?)
			end
		end
	end
	if Opt.auto_aoe then
		if eventType == 'SPELL_MISSED' and (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:Remove(dstGUID)
		elseif ability.auto_aoe and (eventType == ability.auto_aoe.trigger or ability.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and eventType == 'SPELL_AURA_REFRESH') then
			ability:RecordTargetHit(dstGUID)
		elseif BurstingSores.known and ability == FesteringWound and eventType == 'SPELL_DAMAGE' then
			BurstingSores:RecordTargetHit(dstGUID)
		end
	end
	if eventType == 'SPELL_MISSED' or eventType == 'SPELL_DAMAGE' or eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
		if ability.travel_start and ability.travel_start[dstGUID] then
			ability.travel_start[dstGUID] = nil
		end
		if Opt.previous and Opt.miss_effect and eventType == 'SPELL_MISSED' and braindeadPanel:IsVisible() and ability == braindeadPreviousPanel.ability then
			braindeadPreviousPanel.border:SetTexture('Interface\\AddOns\\Braindead\\misseffect.blp')
		end
	end
end

function events:PLAYER_TARGET_CHANGED()
	Target:Update()
end

function events:UNIT_FACTION(unitID)
	if unitID == 'target' then
		Target:Update()
	end
end

function events:UNIT_FLAGS(unitID)
	if unitID == 'target' then
		Target:Update()
	end
end

function events:PLAYER_REGEN_DISABLED()
	Player.combat_start = GetTime() - Player.time_diff
end

function events:PLAYER_REGEN_ENABLED()
	Player.combat_start = 0
	Player.pet_stuck = false
	Target.estimated_range = 30
	Player.previous_gcd = {}
	if Player.last_ability then
		Player.last_ability = nil
		braindeadPreviousPanel:Hide()
	end
	local _, ability, guid
	for _, ability in next, abilities.velocity do
		for guid in next, ability.travel_start do
			ability.travel_start[guid] = nil
		end
	end
	if Opt.auto_aoe then
		for _, ability in next, abilities.autoAoe do
			ability.auto_aoe.start_time = nil
			for guid in next, ability.auto_aoe.targets do
				ability.auto_aoe.targets[guid] = nil
			end
		end
		autoAoe:Clear()
		autoAoe:Update()
	end
	Player.pooling_for_bonestorm = false
	Player.pooling_for_aotd = false
	Player.pooling_for_gargoyle = false
end

function events:PLAYER_EQUIPMENT_CHANGED()
	local _, i, equipType, hasCooldown
	Trinket1.itemId = GetInventoryItemID('player', 13) or 0
	Trinket2.itemId = GetInventoryItemID('player', 14) or 0
	for _, i in next, Trinket do -- use custom APL lines for these trinkets
		if Trinket1.itemId == i.itemId then
			Trinket1.itemId = 0
		end
		if Trinket2.itemId == i.itemId then
			Trinket2.itemId = 0
		end
	end
	for i = 1, #inventoryItems do
		inventoryItems[i].name, _, _, _, _, _, _, _, equipType, inventoryItems[i].icon = GetItemInfo(inventoryItems[i].itemId or 0)
		inventoryItems[i].can_use = inventoryItems[i].name and true or false
		if equipType and equipType ~= '' then
			hasCooldown = 0
			_, inventoryItems[i].equip_slot = Player:Equipped(inventoryItems[i].itemId)
			if inventoryItems[i].equip_slot then
				_, _, hasCooldown = GetInventoryItemCooldown('player', inventoryItems[i].equip_slot)
			end
			inventoryItems[i].can_use = hasCooldown == 1
		end
		if Player.item_use_blacklist[inventoryItems[i].itemId] then
			inventoryItems[i].can_use = false
		end
	end
	Azerite:Update()
	Player:UpdateAbilities()
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitName)
	if unitName ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	braindeadPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	Target:Update()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_REGEN_ENABLED()
end

function events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local _, start, duration, castStart, castEnd
		_, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			start = castStart / 1000
			duration = (castEnd - castStart) / 1000
		else
			start, duration = GetSpellCooldown(61304)
		end
		braindeadPanel.swipe:SetCooldown(start, duration)
	end
end

function events:UNIT_POWER_UPDATE(srcName, powerType)
	if srcName == 'player' and powerType == 'RUNIC_POWER' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_START(srcName)
	if Opt.interrupt and srcName == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_STOP(srcName)
	if Opt.interrupt and srcName == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateAbilities()
end

function events:AZERITE_ESSENCE_UPDATE()
	Azerite:Update()
	Player:UpdateAbilities()
end

function events:GROUP_ROSTER_UPDATE()
	Player.group_size = min(max(GetNumGroupMembers(), 1), 10)
end

function events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

function events:UI_ERROR_MESSAGE(errorId)
	if (
	    errorId == 394 or -- pet is rooted
	    errorId == 396 or -- target out of pet range
	    errorId == 400    -- no pet path to target
	) then
		Player.pet_stuck = true
	end
end

function events:PLAYER_ENTERING_WORLD()
	if #UI.glows == 0 then
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
	end
	local _
	_, Player.instance = IsInInstance()
	Player.guid = UnitGUID('player')
	events:PLAYER_SPECIALIZATION_CHANGED('player')
	events:GROUP_ROSTER_UPDATE()
end

braindeadPanel.button:SetScript('OnClick', function(self, button, down)
	if down then
		if button == 'LeftButton' then
			Player:ToggleTargetMode()
		elseif button == 'RightButton' then
			Player:ToggleTargetModeReverse()
		elseif button == 'MiddleButton' then
			Player:SetTargetMode(1)
		end
	end
end)

braindeadPanel:SetScript('OnUpdate', function(self, elapsed)
	timer.combat = timer.combat + elapsed
	timer.display = timer.display + elapsed
	timer.health = timer.health + elapsed
	if timer.combat >= Opt.frequency then
		UI:UpdateCombat()
	end
	if timer.display >= 0.05 then
		UI:UpdateDisplay()
	end
	if timer.health >= 0.2 then
		Target:UpdateHealth()
	end
end)

braindeadPanel:SetScript('OnEvent', function(self, event, ...) events[event](self, ...) end)
local event
for event in next, events do
	braindeadPanel:RegisterEvent(event)
end

-- End Event Handling

-- Start Slash Commands

-- this fancy hack allows you to click BattleTag links to add them as a friend!
local ChatFrame_OnHyperlinkShow_Original = ChatFrame_OnHyperlinkShow
function ChatFrame_OnHyperlinkShow(chatFrame, link, ...)
	local linkType, linkData = link:match('(.-):(.*)')
	if linkType == 'BNadd' then
		return BattleTagInviteFrame_Show(linkData)
	end
	return ChatFrame_OnHyperlinkShow_Original(chatFrame, link, ...)
end

local function Status(desc, opt, ...)
	local opt_view
	if type(opt) == 'string' then
		if opt:sub(1, 2) == '|c' then
			opt_view = opt
		else
			opt_view = '|cFFFFD000' .. opt .. '|r'
		end
	elseif type(opt) == 'number' then
		opt_view = '|cFFFFD000' .. opt .. '|r'
	else
		opt_view = opt and '|cFF00C000On|r' or '|cFFC00000Off|r'
	end
	print('Braindead -', desc .. ':', opt_view, ...)
end

function SlashCmdList.Braindead(msg, editbox)
	msg = { strsplit(' ', msg:lower()) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UI:UpdateDraggable()
		end
		return Status('Locked', Opt.locked)
	end
	if startsWith(msg[1], 'snap') then
		if msg[2] then
			if msg[2] == 'above' or msg[2] == 'over' then
				Opt.snap = 'above'
			elseif msg[2] == 'below' or msg[2] == 'under' then
				Opt.snap = 'below'
			else
				Opt.snap = false
				braindeadPanel:ClearAllPoints()
			end
			UI.OnResourceFrameShow()
		end
		return Status('Snap to Blizzard combat resources frame', Opt.snap)
	end
	if msg[1] == 'scale' then
		if startsWith(msg[2], 'prev') then
			if msg[3] then
				Opt.scale.previous = tonumber(msg[3]) or 0.7
				UI:UpdateScale()
			end
			return Status('Previous ability icon scale', Opt.scale.previous, 'times')
		end
		if msg[2] == 'main' then
			if msg[3] then
				Opt.scale.main = tonumber(msg[3]) or 1
				UI:UpdateScale()
			end
			return Status('Main ability icon scale', Opt.scale.main, 'times')
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.scale.cooldown = tonumber(msg[3]) or 0.7
				UI:UpdateScale()
			end
			return Status('Cooldown ability icon scale', Opt.scale.cooldown, 'times')
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.scale.interrupt = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Interrupt ability icon scale', Opt.scale.interrupt, 'times')
		end
		if startsWith(msg[2], 'ex') or startsWith(msg[2], 'pet') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Extra/Pet cooldown ability icon scale', Opt.scale.extra, 'times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UI:UpdateGlowColorAndScale()
			end
			return Status('Action button glow scale', Opt.scale.glow, 'times')
		end
		return Status('Default icon scale options', '|cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000pet 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Opt.alpha = max(min((tonumber(msg[2]) or 100), 100), 0) / 100
			UI:UpdateAlpha()
		end
		return Status('Icon transparency', Opt.alpha * 100 .. '%')
	end
	if startsWith(msg[1], 'freq') then
		if msg[2] then
			Opt.frequency = tonumber(msg[2]) or 0.2
		end
		return Status('Calculation frequency (max time to wait between each update): Every', Opt.frequency, 'seconds')
	end
	if startsWith(msg[1], 'glow') then
		if msg[2] == 'main' then
			if msg[3] then
				Opt.glow.main = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (main icon)', Opt.glow.main)
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.glow.cooldown = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (cooldown icon)', Opt.glow.cooldown)
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.glow.interrupt = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (interrupt icon)', Opt.glow.interrupt)
		end
		if startsWith(msg[2], 'ex') or startsWith(msg[2], 'pet') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (extra/pet cooldown icon)', Opt.glow.extra)
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				Opt.glow.blizzard = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Blizzard default proc glow', Opt.glow.blizzard)
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = max(min(tonumber(msg[3]) or 0, 1), 0)
				Opt.glow.color.g = max(min(tonumber(msg[4]) or 0, 1), 0)
				Opt.glow.color.b = max(min(tonumber(msg[5]) or 0, 1), 0)
				UI:UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000pet|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
	end
	if startsWith(msg[1], 'prev') then
		if msg[2] then
			Opt.previous = msg[2] == 'on'
			Target:Update()
		end
		return Status('Previous ability icon', Opt.previous)
	end
	if msg[1] == 'always' then
		if msg[2] then
			Opt.always_on = msg[2] == 'on'
			Target:Update()
		end
		return Status('Show the Braindead UI without a target', Opt.always_on)
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return Status('Use Braindead for cooldown management', Opt.cooldown)
	end
	if msg[1] == 'swipe' then
		if msg[2] then
			Opt.spell_swipe = msg[2] == 'on'
		end
		return Status('Spell casting swipe animation', Opt.spell_swipe)
	end
	if startsWith(msg[1], 'dim') then
		if msg[2] then
			Opt.dimmer = msg[2] == 'on'
		end
		return Status('Dim main ability icon when you don\'t have enough resources to use it', Opt.dimmer)
	end
	if msg[1] == 'miss' then
		if msg[2] then
			Opt.miss_effect = msg[2] == 'on'
		end
		return Status('Red border around previous ability when it fails to hit', Opt.miss_effect)
	end
	if msg[1] == 'aoe' then
		if msg[2] then
			Opt.aoe = msg[2] == 'on'
			Player:SetTargetMode(1)
			UI:UpdateDraggable()
		end
		return Status('Allow clicking main ability icon to toggle amount of targets (disables moving)', Opt.aoe)
	end
	if msg[1] == 'bossonly' then
		if msg[2] then
			Opt.boss_only = msg[2] == 'on'
		end
		return Status('Only use cooldowns on bosses', Opt.boss_only)
	end
	if msg[1] == 'hidespec' or startsWith(msg[1], 'spec') then
		if msg[2] then
			if startsWith(msg[2], 'bl') then
				Opt.hide.blood = not Opt.hide.blood
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Blood specialization', not Opt.hide.blood)
			end
			if startsWith(msg[2], 'fr') then
				Opt.hide.frost = not Opt.hide.frost
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Frost specialization', not Opt.hide.frost)
			end
			if startsWith(msg[2], 'un') or startsWith(msg[2], 'uh') then
				Opt.hide.unholy = not Opt.hide.unholy
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Unholy specialization', not Opt.hide.unholy)
			end
		end
		return Status('Possible hidespec options', '|cFFFFD000blood|r/|cFFFFD000frost|r/|cFFFFD000unholy|r')
	end
	if startsWith(msg[1], 'int') then
		if msg[2] then
			Opt.interrupt = msg[2] == 'on'
		end
		return Status('Show an icon for interruptable spells', Opt.interrupt)
	end
	if msg[1] == 'auto' then
		if msg[2] then
			Opt.auto_aoe = msg[2] == 'on'
		end
		return Status('Automatically change target mode on AoE spells', Opt.auto_aoe)
	end
	if msg[1] == 'ttl' then
		if msg[2] then
			Opt.auto_aoe_ttl = tonumber(msg[2]) or 10
		end
		return Status('Length of time target exists in auto AoE after being hit', Opt.auto_aoe_ttl, 'seconds')
	end
	if startsWith(msg[1], 'pot') then
		if msg[2] then
			Opt.pot = msg[2] == 'on'
		end
		return Status('Show flasks and battle potions in cooldown UI', Opt.pot)
	end
	if startsWith(msg[1], 'tri') then
		if msg[2] then
			Opt.trinket = msg[2] == 'on'
		end
		return Status('Show on-use trinkets in cooldown UI', Opt.trinket)
	end
	if msg[1] == 'ds' then
		if msg[2] then
			Opt.death_strike_threshold = max(min(tonumber(msg[2]) or 60, 100), 0)
		end
		return Status('Health percentage threshold to recommend Death Strike', Opt.death_strike_threshold .. '%')
	end
	if msg[1] == 'reset' then
		braindeadPanel:ClearAllPoints()
		braindeadPanel:SetPoint('CENTER', 0, -169)
		UI:SnapAllPanels()
		return Status('Position has been reset to', 'default')
	end
	print('Braindead (version: |cFFFFD000' .. GetAddOnMetadata('Braindead', 'Version') .. '|r) - Commands:')
	local _, cmd
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the Braindead UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the Braindead UI to the Blizzard combat resources frame',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the Braindead UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the Braindead UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the Braindead UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use Braindead for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough resources to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000blood|r/|cFFFFD000frost|r/|cFFFFD000unholy|r - toggle disabling Braindead for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'ds |cFFFFD000[percent]|r - health percentage threshold to recommend Death Strike',
		'|cFFFFD000reset|r - reset the location of the Braindead UI to default',
	} do
		print('  ' .. SLASH_Braindead1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
