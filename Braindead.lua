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

SLASH_Braindead1, SLASH_Braindead2 = '/brain', '/bd'
BINDING_HEADER_BRAINDEAD = 'Braindead'

local function InitializeOpts()
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
		death_strike_threshold = 60,
	})
end

-- specialization constants
local SPEC = {
	NONE = 0,
	BLOOD = 1,
	FROST = 2,
	UNHOLY = 3,
}

local events, glows = {}, {}

local timer = {
	combat = 0,
	display = 0,
	health = 0
}

local currentSpec, currentForm, targetMode, combatStartTime = 0, 0, 0, 0

-- current target information
local Target = {
	boss = false,
	guid = 0,
	healthArray = {},
	hostile = false
}

-- list of previous GCD abilities
local PreviousGCD = {}

-- items equipped with special effects
local ItemEquipped = {
	RampingAmplitudeGigavoltEngine = false,
}

-- Azerite trait API access
local Azerite = {}

local var = {
	gcd = 1.5,
	time_diff = 0,
	runic_power = 0,
	runic_power_max = 100,
	runes = 0,
	rune_max = 6,
	rune_regen = 0,
}

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
braindeadPanel.text = braindeadPanel:CreateFontString(nil, 'OVERLAY')
braindeadPanel.text:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
braindeadPanel.text:SetTextColor(1, 1, 1, 1)
braindeadPanel.text:SetAllPoints(braindeadPanel)
braindeadPanel.text:SetJustifyH('CENTER')
braindeadPanel.text:SetJustifyV('CENTER')
braindeadPanel.swipe = CreateFrame('Cooldown', nil, braindeadPanel, 'CooldownFrameTemplate')
braindeadPanel.swipe:SetAllPoints(braindeadPanel)
braindeadPanel.dimmer = braindeadPanel:CreateTexture(nil, 'BORDER')
braindeadPanel.dimmer:SetAllPoints(braindeadPanel)
braindeadPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
braindeadPanel.dimmer:Hide()
braindeadPanel.targets = braindeadPanel:CreateFontString(nil, 'OVERLAY')
braindeadPanel.targets:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
braindeadPanel.targets:SetPoint('BOTTOMRIGHT', braindeadPanel, 'BOTTOMRIGHT', -1.5, 3)
braindeadPanel.button = CreateFrame('Button', 'braindeadPanelButton', braindeadPanel)
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

-- Start Auto AoE

local targetModes = {
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

local function SetTargetMode(mode)
	if mode == targetMode then
		return
	end
	targetMode = min(mode, #targetModes[currentSpec])
	var.enemy_count = targetModes[currentSpec][targetMode][1]
	braindeadPanel.targets:SetText(targetModes[currentSpec][targetMode][2])
end
Braindead_SetTargetMode = SetTargetMode

function ToggleTargetMode()
	local mode = targetMode + 1
	SetTargetMode(mode > #targetModes[currentSpec] and 1 or mode)
end
Braindead_ToggleTargetMode = ToggleTargetMode

local function ToggleTargetModeReverse()
	local mode = targetMode - 1
	SetTargetMode(mode < 1 and #targetModes[currentSpec] or mode)
end
Braindead_ToggleTargetModeReverse = ToggleTargetModeReverse

local autoAoe = {
	targets = {},
	blacklist = {}
}

function autoAoe:add(guid, update)
	if self.blacklist[guid] then
		return
	end
	local new = not self.targets[guid]
	self.targets[guid] = var.time
	if update and new then
		self:update()
	end
end

function autoAoe:remove(guid)
	self.blacklist[guid] = var.time
	if self.targets[guid] then
		self.targets[guid] = nil
		self:update()
	end
end

function autoAoe:clear()
	local guid
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
end

function autoAoe:update()
	local count, i = 0
	for i in next, self.targets do
		count = count + 1
	end
	if count <= 1 then
		SetTargetMode(1)
		return
	end
	var.enemy_count = count
	for i = #targetModes[currentSpec], 1, -1 do
		if count >= targetModes[currentSpec][i][1] then
			SetTargetMode(i)
			var.enemy_count = count
			return
		end
	end
end

function autoAoe:purge()
	local update, guid, t
	for guid, t in next, self.targets do
		if var.time - t > Opt.auto_aoe_ttl then
			self.targets[guid] = nil
			update = true
		end
	end
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	for guid, t in next, self.blacklist do
		if var.time - t > 2 then
			self.blacklist[guid] = nil
		end
	end
	if update then
		self:update()
	end
end

-- End Auto AoE

-- Start Abilities

local Ability = {}
Ability.__index = Ability
local abilities = {
	all = {}
}

function Ability.add(spellId, buff, player, spellId2)
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
		velocity = 0,
		auraTarget = buff and 'player' or 'target',
		auraFilter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
	}
	setmetatable(ability, Ability)
	abilities.all[#abilities.all + 1] = ability
	return ability
end

function Ability:match(spell)
	if type(spell) == 'number' then
		return spell == self.spellId or (self.spellId2 and spell == self.spellId2)
	elseif type(spell) == 'string' then
		return spell:lower() == self.name:lower()
	elseif type(spell) == 'table' then
		return spell == self
	end
	return false
end

function Ability:ready(seconds)
	return self:cooldown() <= (seconds or 0)
end

function Ability:usable()
	if not self.known then
		return false
	end
	if self:runeCost() > var.runes then
		return false
	end
	if self:runicPowerCost() > var.runic_power then
		return false
	end
	if self.requires_charge and self:charges() == 0 then
		return false
	end
	if self.requires_pet and not var.pet_active then
		return false
	end
	return self:ready()
end

function Ability:remains()
	if self:traveling() then
		return self:duration()
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(expires - var.time - var.execute_remains, 0)
		end
	end
	return 0
end

function Ability:refreshable()
	if self.buff_duration > 0 then
		return self:remains() < self:duration() * 0.3
	end
	return self:down()
end

function Ability:up()
	if self:traveling() or self:casting() then
		return true
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return false
		end
		if self:match(id) then
			return expires == 0 or expires - var.time > var.execute_remains
		end
	end
end

function Ability:down()
	return not self:up()
end

function Ability:setVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.travel_start = {}
	else
		self.travel_start = nil
		self.velocity = 0
	end
end

function Ability:traveling()
	if self.travel_start and self.travel_start[Target.guid] then
		if var.time - self.travel_start[Target.guid] < 40 / self.velocity then
			return true
		end
		self.travel_start[Target.guid] = nil
	end
end

function Ability:ticking()
	if self.aura_targets then
		local count, guid, aura = 0
		for guid, aura in next, self.aura_targets do
			if aura.expires - (var.time - var.time_diff) > var.execute_remains then
				count = count + 1
			end
		end
		return count
	end
	return self:up() and 1 or 0
end

function Ability:cooldownDuration()
	return self.hasted_cooldown and (var.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:cooldown()
	if self.cooldown_duration > 0 and self:casting() then
		return self.cooldown_duration
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (var.time - start) - var.execute_remains)
end

function Ability:stack()
	local _, i, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:match(id) then
			return (expires == 0 or expires - var.time > var.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:runeCost()
	return self.rune_cost
end

function Ability:runicPowerCost()
	return self.runic_power_cost
end

function Ability:charges()
	return (GetSpellCharges(self.spellId)) or 0
end

function Ability:chargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, var.time - recharge_start + var.execute_remains)) / recharge_time)
end

function Ability:fullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (var.time - recharge_start) - var.execute_remains)
end

function Ability:maxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:duration()
	return self.hasted_duration and (var.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:casting()
	return var.ability_casting == self
end

function Ability:channeling()
	return UnitChannelInfo('player') == self.name
end

function Ability:castTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return self.triggers_gcd and var.gcd or 0
	end
	return castTime / 1000
end

function Ability:tickTime()
	return self.hasted_ticks and (var.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:previous()
	if self:casting() or self:channeling() then
		return true
	end
	return PreviousGCD[1] == self or var.last_ability == self
end

function Ability:azeriteRank()
	return Azerite.traits[self.spellId] or 0
end

function Ability:autoAoe(removeUnaffected)
	self.auto_aoe = {
		remove = removeUnaffected,
		targets = {}
	}
end

function Ability:recordTargetHit(guid)
	self.auto_aoe.targets[guid] = var.time
	if not self.auto_aoe.start_time then
		self.auto_aoe.start_time = self.auto_aoe.targets[guid]
	end
end

function Ability:updateTargetsHit()
	if self.auto_aoe.start_time and var.time - self.auto_aoe.start_time >= 0.3 then
		self.auto_aoe.start_time = nil
		if self.auto_aoe.remove then
			autoAoe:clear()
		end
		local guid
		for guid in next, self.auto_aoe.targets do
			autoAoe:add(guid)
			self.auto_aoe.targets[guid] = nil
		end
		autoAoe:update()
	end
end

-- start DoT tracking

local trackAuras = {}

function trackAuras:purge()
	local now = var.time - var.time_diff
	local _, ability, guid, expires
	for _, ability in next, abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= now then
				ability:removeAura(guid)
			end
		end
	end
end

function trackAuras:remove(guid)
	local _, ability
	for _, ability in next, abilities.trackAuras do
		ability:removeAura(guid)
	end
end

function Ability:trackAuras()
	self.aura_targets = {}
end

function Ability:applyAura(timeStamp, guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = {
		expires = timeStamp + self:duration()
	}
	self.aura_targets[guid] = aura
end

function Ability:refreshAura(timeStamp, guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		self:applyAura(timeStamp, guid)
		return
	end
	local remains = aura.expires - timeStamp
	local duration = self:duration()
	aura.expires = timeStamp + min(duration * 1.3, remains + duration)
end

function Ability:removeAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- end DoT tracking

-- Death Knight Abilities
---- Multiple Specializations
local AntiMagicShell = Ability.add(48707, true, true)
AntiMagicShell.buff_duration = 5
AntiMagicShell.cooldown_duration = 60
AntiMagicShell.triggers_gcd = false
local ChainsOfIce = Ability.add(45524, false)
ChainsOfIce.buff_duration = 8
ChainsOfIce.rune_cost = 1
local DarkCommand = Ability.add(56222, false)
DarkCommand.buff_duration = 3
DarkCommand.cooldown_duration = 8
DarkCommand.triggers_gcd = false
local DeathAndDecay = Ability.add(43265, false, true, 52212)
DeathAndDecay.buff_duration = 10
DeathAndDecay.cooldown_duration = 30
DeathAndDecay.rune_cost = 1
DeathAndDecay.tick_interval = 1
DeathAndDecay:autoAoe()
local DeathGrip = Ability.add(49576, false, true)
DeathGrip.cooldown_duration = 25
DeathGrip.requires_charge = true
local DeathsAdvance = Ability.add(48265, true, true)
DeathsAdvance.buff_duration = 8
DeathsAdvance.cooldown_duration = 45
DeathsAdvance.triggers_gcd = false
local DeathStrike = Ability.add(49998, false, true)
DeathStrike.runic_power_cost = 45
local IceboundFortitude = Ability.add(48792, true, true)
IceboundFortitude.buff_duration = 8
IceboundFortitude.cooldown_duration = 180
IceboundFortitude.triggers_gcd = false
local MindFreeze = Ability.add(47528, false, true)
MindFreeze.buff_duration = 3
MindFreeze.cooldown_duration = 15
MindFreeze.triggers_gcd = false
local RaiseAlly = Ability.add(61999, false, true)
RaiseAlly.cooldown_duration = 600
RaiseAlly.runic_power_cost = 30
------ Procs

------ Talents
local Asphyxiate = Ability.add(108194, false, true)
Asphyxiate.buff_duration = 4
Asphyxiate.cooldown_duration = 45
local SummonGargoyle = Ability.add(49206, true, true)
SummonGargoyle.buff_duration = 35
SummonGargoyle.cooldown_duration = 180
---- Blood

------ Talents

------ Procs

---- Frost

------ Talents

------ Procs

---- Unholy
local Apocalypse = Ability.add(275699, false, true)
Apocalypse.cooldown_duration = 90
local ArmyOfTheDead = Ability.add(42650, true, true, 42651)
ArmyOfTheDead.buff_duration = 4
ArmyOfTheDead.cooldown_duration = 480
ArmyOfTheDead.rune_cost = 3
local ControlUndead = Ability.add(111673, true, true)
ControlUndead.buff_duration = 300
ControlUndead.rune_cost = 1
local DarkTransformation = Ability.add(63560, true, true)
DarkTransformation.buff_duration = 15
DarkTransformation.cooldown_duration = 60
DarkTransformation.requires_pet = true
local DeathCoil = Ability.add(47541, false, true, 47632)
DeathCoil.runic_power_cost = 40
DeathCoil:setVelocity(35)
local FesteringStrike = Ability.add(85948, false, true)
FesteringStrike.rune_cost = 2
local FesteringWound = Ability.add(194310, false, true, 194311)
FesteringWound.buff_duration = 30
local Outbreak = Ability.add(77575, false, true, 196782)
Outbreak.buff_duration = 6
Outbreak.rune_cost = 1
Outbreak:trackAuras()
local RaiseDead = Ability.add(46584, false, true)
RaiseDead.cooldown_duration = 30
local ScourgeStrike = Ability.add(55090, false, true, 70890)
ScourgeStrike.rune_cost = 1
local VirulentPlague = Ability.add(191587, false, true)
VirulentPlague.buff_duration = 21
VirulentPlague.tick_interval = 1.5
VirulentPlague:autoAoe()
VirulentPlague:trackAuras()
------ Talents
local BurstingSores = Ability.add(207264, false, true, 207267)
BurstingSores:autoAoe()
local ClawingShadows = Ability.add(207311, false, true)
ClawingShadows.rune_cost = 1
local DeathPact = Ability.add(48743, true, true)
DeathPact.buff_duration = 15
DeathPact.cooldown_duration = 120
local Defile = Ability.add(152280, false, true, 156000)
Defile.buff_duration = 10
Defile.cooldown_duration = 20
Defile.rune_cost = 1
Defile.tick_interval = 1
Defile:autoAoe()
local EbonFever = Ability.add(207269, false, true)
local Epidemic = Ability.add(207317, false, true, 212739)
Epidemic.runic_power_cost = 30
Epidemic:autoAoe(true)
local Pestilence = Ability.add(277234, false, true)
local RaiseAbomination = Ability.add(288853, true, true)
RaiseAbomination.buff_duration = 25
RaiseAbomination.cooldown_duration = 90
local SoulReaper = Ability.add(130736, false, true)
SoulReaper.buff_duration = 8
SoulReaper.cooldown_duration = 45
local UnholyBlight = Ability.add(115989, true, true)
UnholyBlight.buff_duration = 6
UnholyBlight.cooldown_duration = 45
UnholyBlight.rune_cost = 1
UnholyBlight.dot = Ability.add(115994, false, true)
UnholyBlight.dot.buff_duration = 14
UnholyBlight.dot.tick_interval = 2
UnholyBlight:autoAoe(true)
local UnholyFrenzy = Ability.add(207289, true, true)
UnholyFrenzy.buff_duration = 12
UnholyFrenzy.cooldown_duration = 75
------ Procs
local DarkSuccor = Ability.add(101568, true, true)
DarkSuccor.buff_duration = 20
local RunicCorruption = Ability.add(51462, true, true, 51460)
RunicCorruption.buff_duration = 3
local SuddenDoom = Ability.add(49530, true, true, 81340)
SuddenDoom.buff_duration = 10
local VirulentEruption = Ability.add(191685, false, true)
-- Azerite Traits

-- Racials
local ArcaneTorrent = Ability.add(50613, true, true) -- Blood Elf
-- Trinket Effects
local MagusOfTheDead = Ability.add(288417, true, true)
-- End Abilities

-- Start Inventory Items

local InventoryItem, inventoryItems = {}, {}
InventoryItem.__index = InventoryItem

function InventoryItem.add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon
	}
	setmetatable(item, InventoryItem)
	inventoryItems[#inventoryItems + 1] = item
	return item
end

function InventoryItem:charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:previous() or PreviousGCD[1] == self.created_by) then
		charges = max(charges, self.max_charges)
	end
	return charges
end

function InventoryItem:count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:previous() or PreviousGCD[1] == self.created_by) then
		count = max(count, 1)
	end
	return count
end

function InventoryItem:cooldown()
	local startTime, duration = GetItemCooldown(self.itemId)
	return startTime == 0 and 0 or duration - (var.time - startTime)
end

function InventoryItem:ready(seconds)
	return self:cooldown() <= (seconds or 0)
end

function InventoryItem:usable(seconds)
	if self:charges() == 0 then
		return false
	end
	return self:ready(seconds)
end

-- Inventory Items
local FlaskOfTheUndertow = InventoryItem.add(152641)
FlaskOfTheUndertow.buff = Ability.add(251839, true, true)
local BattlePotionOfStrength = InventoryItem.add(163224)
BattlePotionOfStrength.buff = Ability.add(279153, true, true)
BattlePotionOfStrength.buff.triggers_gcd = false
-- End Inventory Items

-- Start Azerite Trait API

Azerite.equip_slots = { 1, 3, 5 } -- Head, Shoulder, Chest

function Azerite:initialize()
	self.locations = {}
	self.traits = {}
	local i
	for i = 1, #self.equip_slots do
		self.locations[i] = ItemLocation:CreateFromEquipmentSlot(self.equip_slots[i])
	end
end

function Azerite:update()
	local _, loc, tinfo, tslot, pid, pinfo
	for pid in next, self.traits do
		self.traits[pid] = nil
	end
	for _, loc in next, self.locations do
		if GetInventoryItemID('player', loc:GetEquipmentSlot()) and C_AzeriteEmpoweredItem.IsAzeriteEmpoweredItem(loc) then
			tinfo = C_AzeriteEmpoweredItem.GetAllTierInfo(loc)
			for _, tslot in next, tinfo do
				if tslot.azeritePowerIDs then
					for _, pid in next, tslot.azeritePowerIDs do
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
end

-- End Azerite Trait API

-- Start Helpful Functions

local function Health()
	return var.health
end

local function HealthMax()
	return var.health_max
end

local function HealthPct()
	return var.health / var.health_max * 100
end

local function Runes()
	return var.runes
end

local function RuneDeficit()
	return var.rune_max - var.runes
end

local function RuneRegen()
	return var.rune_regen
end

local function RunicPower()
	return var.runic_power
end

local function RunicPowerDeficit()
	return var.runic_power_max - var.runic_power
end

local function GCD()
	return var.gcd
end

local function Enemies()
	return var.enemy_count
end

local function TimeInCombat()
	if combatStartTime > 0 then
		return var.time - combatStartTime
	end
	return 0
end

local function BloodlustActive()
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if (
			id == 2825 or	-- Bloodlust (Horde Shaman)
			id == 32182 or	-- Heroism (Alliance Shaman)
			id == 80353 or	-- Time Warp (Mage)
			id == 90355 or	-- Ancient Hysteria (Druid Pet - Core Hound)
			id == 160452 or -- Netherwinds (Druid Pet - Nether Ray)
			id == 264667 or -- Primal Rage (Druid Pet - Ferocity)
			id == 178207 or -- Drums of Fury (Leatherworking)
			id == 146555 or -- Drums of Rage (Leatherworking)
			id == 230935 or -- Drums of the Mountain (Leatherworking)
			id == 256740    -- Drums of the Maelstrom (Leatherworking)
		) then
			return true
		end
	end
end

local function TargetIsStunnable()
	if Target.player then
		return true
	end
	if Target.boss then
		return false
	end
	if var.instance == 'raid' then
		return false
	end
	if Target.healthMax > var.health_max * 10 then
		return false
	end
	return true
end

local function InArenaOrBattleground()
	return var.instance == 'arena' or var.instance == 'pvp'
end

-- End Helpful Functions

-- Start Ability Modifications

function DeathCoil:runicPowerCost()
	if SuddenDoom:up() then
		return 0
	end
	return self.runic_power_cost
end

function DeathStrike:runicPowerCost()
	if DarkSuccor:up() then
		return 0
	end
	return self.runic_power_cost
end

function VirulentPlague:duration()
	if EbonFever.known then
		return Ability.duration(self) / 2
	end
	return Ability.duration(self)
end

-- End Ability Modifications

local function UseCooldown(ability, overwrite, always)
	if always or (Opt.cooldown and (not Opt.boss_only or Target.boss) and (not var.cd or overwrite)) then
		var.cd = ability
	end
end

local function UseExtra(ability, overwrite)
	if not var.extra or overwrite then
		var.extra = ability
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
	if TimeInCombat() == 0 then
		if Opt.pot and not InArenaOrBattleground() then
			if FlaskOfTheUndertow:usable() and FlaskOfTheUndertow.buff:remains() < 300 then
				UseCooldown(FlaskOfTheUndertow)
			end
			if BattlePotionOfStrength:usable() then
				UseCooldown(BattlePotionOfStrength)
			end
		end
	end
end

APL[SPEC.FROST].main = function(self)
	if TimeInCombat() == 0 then
		if Opt.pot and not InArenaOrBattleground() then
			if FlaskOfTheUndertow:usable() and FlaskOfTheUndertow.buff:remains() < 300 then
				UseCooldown(FlaskOfTheUndertow)
			end
			if BattlePotionOfStrength:usable() then
				UseCooldown(BattlePotionOfStrength)
			end
		end
	end
end

APL[SPEC.UNHOLY].main = function(self)
	if not var.pet_active and RaiseDead:usable() then
		UseExtra(RaiseDead)
	end
	if TimeInCombat() == 0 then
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
		if Opt.pot and not InArenaOrBattleground() then
			if FlaskOfTheUndertow:usable() and FlaskOfTheUndertow.buff:remains() < 300 then
				UseCooldown(FlaskOfTheUndertow)
			end
			if BattlePotionOfStrength:usable() then
				UseCooldown(BattlePotionOfStrength)
			end
		end
		if Target.boss then
			if ArmyOfTheDead:usable() then
				UseCooldown(ArmyOfTheDead)
			end
			if RaiseAbomination:usable() then
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
	if ArcaneTorrent:usable() and RunicPowerDeficit() > 65 and (SummonGargoyle:up() or not SummonGargoyle.known) and RuneDeficit() >= 5 then
		UseExtra(ArcaneTorrent)
	end
	if Opt.pot and BattlePotionOfStrength:usable() and (ArmyOfTheDead:ready() or SummonGargoyle:up() or UnholyFrenzy:up()) then
		UseExtra(BattlePotionOfStrength)
	end
	if Outbreak:usable() and Outbreak:ticking() < 1 and VirulentPlague:remains() <= GCD() and Target.timeToDie > (VirulentPlague:remains() + 1) then
		return Outbreak
	end
	var.use_cds = Target.boss or Target.timeToDie > (12 - min(Enemies(), 6))
	var.pooling_for_aotd = ArmyOfTheDead.known and (Target.boss or Target.timeToDie > 40) and ArmyOfTheDead:ready(5)
	var.pooling_for_gargoyle =  var.use_cds and SummonGargoyle.known and SummonGargoyle:ready(5)
	self:cooldowns()
	if Enemies() >= 2 then
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
	if var.use_cds then
		if var.pooling_for_aotd and ArmyOfTheDead:usable() then
			return UseCooldown(ArmyOfTheDead)
		end
		if RaiseAbomination:usable() then
			return UseCooldown(RaiseAbomination)
		end
		if Apocalypse:usable() and FesteringWound:stack() >= 4 then
			return UseCooldown(Apocalypse)
		end
		if DarkTransformation:usable() then
			return UseCooldown(DarkTransformation)
		end
		if SummonGargoyle:usable() and RunicPowerDeficit() < 14 then
			return UseCooldown(SummonGargoyle)
		end
		if UnholyFrenzy:usable() then
			if MagusOfTheDead.known or ItemEquipped.RampingAmplitudeGigavoltEngine then
				if Apocalypse:ready(2) then
					return UseCooldown(UnholyFrenzy)
				end
			elseif FesteringWound:stack() < 4 then
				return UseCooldown(UnholyFrenzy)
			end
			if Enemies() >= 2 and ((DeathAndDecay:ready(GCD()) and not Defile.known) or (Defile.known and Defile:ready(GCD()))) then
				return UseCooldown(UnholyFrenzy)
			end
		end
	end
	if SoulReaper:usable() then
		if between(Target.timeToDie, 4, 8) then
			return UseCooldown(SoulReaper)
		end
		if Enemies() == 1 and Runes() <= (UnholyFrenzy:up() and 1 or 0) then
			return UseCooldown(SoulReaper)
		end
	end
	if UnholyBlight:usable() then
		return UseCooldown(UnholyBlight)
	end
end

APL[SPEC.UNHOLY].aoe = function(self)
--[[
actions.aoe=death_and_decay,if=cooldown.apocalypse.remains
actions.aoe+=/defile
actions.aoe+=/epidemic,if=death_and_decay.ticking&rune<2&!variable.pooling_for_gargoyle
actions.aoe+=/death_coil,if=death_and_decay.ticking&rune<2&!variable.pooling_for_gargoyle
actions.aoe+=/scourge_strike,if=death_and_decay.ticking&cooldown.apocalypse.remains
actions.aoe+=/clawing_shadows,if=death_and_decay.ticking&cooldown.apocalypse.remains
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
	if Outbreak:usable() and Outbreak:ticking() < 1 and VirulentPlague:ticking() < Enemies() then
		return Outbreak
	end
	local apocalypse_not_ready = not var.use_cds or not Apocalypse.known or not Apocalypse:ready()
	if DeathAndDecay:usable() and apocalypse_not_ready and Target.timeToDie > max(6 - Enemies(), 2) then
		return DeathAndDecay
	end
	if Defile:usable() then
		return Defile
	end
	if DeathAndDecay:up() then
		if not var.pooling_for_gargoyle and Runes() < 2 then
			if Epidemic:usable() and VirulentPlague:ticking() >= 2 then
				return Epidemic
			end
			if DeathCoil:usable() then
				return DeathCoil
			end
		end
		if apocalypse_not_ready then
			if ScourgeStrike:usable() then
				return ScourgeStrike
			end
			if ClawingShadows:usable() then
				return ClawingShadows
			end
		end
	end
	if Epidemic:usable() and not var.pooling_for_gargoyle and VirulentPlague:ticking() >= 2 then
		return Epidemic
	end
	if FesteringStrike:usable() and FesteringWound:stack() <= 1 then
		if not DeathAndDecay:ready() then
			return FesteringStrike
		end
		if BurstingSores.known and Enemies() >= 2 then
			return FesteringStrike
		end
	end
	local apocalypse_not_ready_5 = not var.use_cds or not Apocalypse.known or not Apocalypse:ready(5)
	if DeathCoil:usable() then
		if SuddenDoom:up() and (RuneDeficit() >= 4 or not var.pooling_for_gargoyle) then
			return DeathCoil
		end
		if SummonGargoyle:up() then
			return DeathCoil
		end
		if not var.pooling_for_gargoyle and RunicPowerDeficit() < 14 and (apocalypse_not_ready_5 or FesteringWound:stack() > 4) then
			return DeathCoil
		end
	end
	if not var.pooling_for_aotd and ((FesteringWound:up() and apocalypse_not_ready_5) or FesteringWound:stack() > 4) then
		if ScourgeStrike:usable() then
			return ScourgeStrike
		end
		if ClawingShadows:usable() then
			return ClawingShadows
		end
	end
	if RunicPowerDeficit() < 20 and not var.pooling_for_gargoyle then
		if HealthPct() < Opt.death_strike_threshold and DeathStrike:usable() then
			return DeathStrike
		end
		if DeathCoil:usable() then
			return DeathCoil
		end
	end
	if not var.pooling_for_aotd and FesteringStrike:usable() and ((((FesteringWound:stack() < 4 and UnholyFrenzy:down()) or FesteringWound:stack() < 3) and Apocalypse:ready(3)) or FesteringWound:stack() < 1) then
		return FesteringStrike
	end
	if DeathStrike:usable() and DarkSuccor:up() then
		return DeathStrike
	end
	if not var.pooling_for_gargoyle then
		if HealthPct() < Opt.death_strike_threshold and DeathStrike:usable() then
			return DeathStrike
		end
		if DeathCoil:usable() then
			return DeathCoil
		end
	end
	if SoulReaper:usable() then
		if Runes() <= (UnholyFrenzy:up() and 1 or 0) then
			return SoulReaper
		end
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
	local apocalypse_not_ready_5 = not var.use_cds or not Apocalypse.known or not Apocalypse:ready(5)
	if DeathCoil:usable() then
		if SummonGargoyle:up() or (SuddenDoom:up() and not var.pooling_for_gargoyle) then
			return DeathCoil
		end
		if not var.pooling_for_gargoyle and RunicPowerDeficit() < 14 and (apocalypse_not_ready_5 or FesteringWound:stack() > 4) then
			return DeathCoil
		end
	end
	local apocalypse_not_ready = not var.use_cds or not Apocalypse.known or not Apocalypse:ready()
	if apocalypse_not_ready then
		if Pestilence.known and DeathAndDecay:usable() and Target.timeToDie > 6 then
			return DeathAndDecay
		end
		if Defile:usable() then
			return Defile
		end
	end
	if (not var.use_aod or not ArmyOfTheDead:ready(5)) and ((FesteringWound:up() and apocalypse_not_ready_5) or FesteringWound:stack() > 4) then
		if ScourgeStrike:usable() then
			return ScourgeStrike
		end
		if ClawingShadows:usable() then
			return ClawingShadows
		end
	end
	if RunicPowerDeficit() < 20 and not var.pooling_for_gargoyle then
		if HealthPct() < Opt.death_strike_threshold and DeathStrike:usable() then
			return DeathStrike
		end
		if DeathCoil:usable() then
			return DeathCoil
		end
	end
	if FesteringStrike:usable() and (not var.use_aod or not ArmyOfTheDead:ready(5)) and ((((FesteringWound:stack() < 4 and UnholyFrenzy:down()) or FesteringWound:stack() < 3) and Apocalypse:ready(3)) or FesteringWound:stack() < 1) then
		return FesteringStrike
	end
	if DeathStrike:usable() and DarkSuccor:up() then
		return DeathStrike
	end
	if not var.pooling_for_gargoyle then
		if HealthPct() < Opt.death_strike_threshold and DeathStrike:usable() then
			return DeathStrike
		end
		if DeathCoil:usable() then
			return DeathCoil
		end
	end
	if SoulReaper:usable() then
		if Runes() <= (UnholyFrenzy:up() and 1 or 0) then
			return SoulReaper
		end
	end
end

APL.Interrupt = function(self)
	if MindFreeze:usable() then
		return MindFreeze
	end
	if Asphyxiate:usable() and TargetIsStunnable() then
		return Asphyxiate
	end
end

-- End Action Priority Lists

local function UpdateInterrupt()
	local _, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
	if not start then
		_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
	end
	if not start or notInterruptible then
		var.interrupt = nil
		braindeadInterruptPanel:Hide()
		return
	end
	var.interrupt = APL.Interrupt()
	if var.interrupt then
		braindeadInterruptPanel.icon:SetTexture(var.interrupt.icon)
		braindeadInterruptPanel.icon:Show()
		braindeadInterruptPanel.border:Show()
	else
		braindeadInterruptPanel.icon:Hide()
		braindeadInterruptPanel.border:Hide()
	end
	braindeadInterruptPanel:Show()
	braindeadInterruptPanel.cast:SetCooldown(start / 1000, (ends - start) / 1000)
end

local function DenyOverlayGlow(actionButton)
	if not Opt.glow.blizzard then
		actionButton.overlay:Hide()
	end
end

hooksecurefunc('ActionButton_ShowOverlayGlow', DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

local function UpdateGlowColorAndScale()
	local w, h, glow, i
	local r = Opt.glow.color.r
	local g = Opt.glow.color.g
	local b = Opt.glow.color.b
	for i = 1, #glows do
		glow = glows[i]
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

local function CreateOverlayGlows()
	local b, i
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.button = button
			glows[#glows + 1] = glow
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
	UpdateGlowColorAndScale()
end

local function UpdateGlows()
	local glow, icon, i
	for i = 1, #glows do
		glow = glows[i]
		icon = glow.button.icon:GetTexture()
		if icon and glow.button.icon:IsVisible() and (
			(Opt.glow.main and var.main and icon == var.main.icon) or
			(Opt.glow.cooldown and var.cd and icon == var.cd.icon) or
			(Opt.glow.interrupt and var.interrupt and icon == var.interrupt.icon) or
			(Opt.glow.extra and var.extra and icon == var.extra.icon)
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

function events:ACTIONBAR_SLOT_CHANGED()
	UpdateGlows()
end

local function ShouldHide()
	return (currentSpec == SPEC.NONE or
		   (currentSpec == SPEC.BLOOD and Opt.hide.blood) or
		   (currentSpec == SPEC.FROST and Opt.hide.frost) or
		   (currentSpec == SPEC.UNHOLY and Opt.hide.unholy))
end

local function Disappear()
	braindeadPanel:Hide()
	braindeadPanel.icon:Hide()
	braindeadPanel.border:Hide()
	braindeadPanel.text:Hide()
	braindeadCooldownPanel:Hide()
	braindeadInterruptPanel:Hide()
	braindeadExtraPanel:Hide()
	var.main, var.last_main = nil
	var.cd, var.last_cd = nil
	var.interrupt = nil
	var.extra, var.last_extra = nil
	UpdateGlows()
end

function Equipped(itemID, slot)
	if slot then
		return GetInventoryItemID('player', slot) == itemId
	end
	local i
	for i = 1, 19 do
		if GetInventoryItemID('player', i) == itemID then
			return true
		end
	end
	return false
end

local function UpdateDraggable()
	braindeadPanel:EnableMouse(Opt.aoe or not Opt.locked)
	if Opt.aoe then
		braindeadPanel.button:Show()
	else
		braindeadPanel.button:Hide()
	end
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

local function SnapAllPanels()
	braindeadPreviousPanel:ClearAllPoints()
	braindeadPreviousPanel:SetPoint('BOTTOMRIGHT', braindeadPanel, 'BOTTOMLEFT', -10, -5)
	braindeadCooldownPanel:ClearAllPoints()
	braindeadCooldownPanel:SetPoint('BOTTOMLEFT', braindeadPanel, 'BOTTOMRIGHT', 10, -5)
	braindeadInterruptPanel:ClearAllPoints()
	braindeadInterruptPanel:SetPoint('TOPLEFT', braindeadPanel, 'TOPRIGHT', 16, 25)
	braindeadExtraPanel:ClearAllPoints()
	braindeadExtraPanel:SetPoint('TOPRIGHT', braindeadPanel, 'TOPLEFT', -16, 25)
end

local resourceAnchor = {}

local ResourceFramePoints = {
	['blizzard'] = {
		[SPEC.BLOOD] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -18 }
		},
		[SPEC.FROST] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -18 }
		},
		[SPEC.UNHOLY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -18 }
		},
	},
	['kui'] = {
		[SPEC.BLOOD] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 30 },
			['below'] = { 'TOP', 'BOTTOM', 0, -4 }
		},
		[SPEC.FROST] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 30 },
			['below'] = { 'TOP', 'BOTTOM', 0, -4 }
		},
		[SPEC.UNHOLY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 30 },
			['below'] = { 'TOP', 'BOTTOM', 0, -4 }
		},
	},
}

local function OnResourceFrameHide()
	if Opt.snap then
		braindeadPanel:ClearAllPoints()
	end
end

local function OnResourceFrameShow()
	if Opt.snap then
		braindeadPanel:ClearAllPoints()
		local p = ResourceFramePoints[resourceAnchor.name][currentSpec][Opt.snap]
		braindeadPanel:SetPoint(p[1], resourceAnchor.frame, p[2], p[3], p[4])
		SnapAllPanels()
	end
end

local function HookResourceFrame()
	if KuiNameplatesCoreSaved and KuiNameplatesCoreCharacterSaved and
		not KuiNameplatesCoreSaved.profiles[KuiNameplatesCoreCharacterSaved.profile].use_blizzard_personal
	then
		resourceAnchor.name = 'kui'
		resourceAnchor.frame = KuiNameplatesPlayerAnchor
	else
		resourceAnchor.name = 'blizzard'
		resourceAnchor.frame = ClassNameplateManaBarFrame
	end
	resourceAnchor.frame:HookScript("OnHide", OnResourceFrameHide)
	resourceAnchor.frame:HookScript("OnShow", OnResourceFrameShow)
end

local function UpdateAlpha()
	braindeadPanel:SetAlpha(Opt.alpha)
	braindeadPreviousPanel:SetAlpha(Opt.alpha)
	braindeadCooldownPanel:SetAlpha(Opt.alpha)
	braindeadInterruptPanel:SetAlpha(Opt.alpha)
	braindeadExtraPanel:SetAlpha(Opt.alpha)
end

local function UpdateTargetHealth()
	timer.health = 0
	Target.health = UnitHealth('target')
	table.remove(Target.healthArray, 1)
	Target.healthArray[15] = Target.health
	Target.timeToDieMax = Target.health / UnitHealthMax('player') * 15
	Target.healthPercentage = Target.healthMax > 0 and (Target.health / Target.healthMax * 100) or 100
	Target.healthLostPerSec = (Target.healthArray[1] - Target.health) / 3
	Target.timeToDie = Target.healthLostPerSec > 0 and min(Target.timeToDieMax, Target.health / Target.healthLostPerSec) or Target.timeToDieMax
end

local function UpdateDisplay()
	timer.display = 0
	if Opt.dimmer then
		if not var.main then
			braindeadPanel.dimmer:Hide()
		elseif var.main.spellId and IsUsableSpell(var.main.spellId) then
			braindeadPanel.dimmer:Hide()
		elseif var.main.itemId and IsUsableItem(var.main.itemId) then
			braindeadPanel.dimmer:Hide()
		else
			braindeadPanel.dimmer:Show()
		end
	end
end

local function GetAvailableRunes()
	local runes, i, start, duration = 0
	for i = 1, var.rune_max do
		start, duration = GetRuneCooldown(i)
		if start == 0 or (start + duration - var.time < var.execute_remains) then
			runes = runes + 1
		end
	end
	return runes
end

local function UpdateCombat()
	timer.combat = 0
	local _, start, duration, remains, spellId
	var.time = GetTime()
	var.last_main = var.main
	var.last_cd = var.cd
	var.last_extra = var.extra
	var.main =  nil
	var.cd = nil
	var.extra = nil
	start, duration = GetSpellCooldown(61304)
	var.gcd_remains = start > 0 and duration - (var.time - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	var.ability_casting = abilities.bySpellId[spellId]
	var.execute_remains = max(remains and (remains / 1000 - var.time) or 0, var.gcd_remains)
	var.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	var.gcd = 1.5 * var.haste_factor
	var.health = UnitHealth('player')
	var.health_max = UnitHealthMax('player')
	var.runes = GetAvailableRunes()
	_, var.rune_regen = GetRuneCooldown(1)
	var.runic_power = UnitPower('player', 6)
	var.pet_active = IsFlying() or UnitExists('pet') and not UnitIsDead('pet')

	trackAuras:purge()
	if Opt.auto_aoe then
		local ability
		for _, ability in next, abilities.autoAoe do
			ability:updateTargetsHit()
		end
		autoAoe:purge()
	end

	var.main = APL[currentSpec]:main()
	if var.main ~= var.last_main then
		if var.main then
			braindeadPanel.icon:SetTexture(var.main.icon)
			braindeadPanel.icon:Show()
			braindeadPanel.border:Show()
		else
			braindeadPanel.icon:Hide()
			braindeadPanel.border:Hide()
		end
	end
	if var.cd ~= var.last_cd then
		if var.cd then
			braindeadCooldownPanel.icon:SetTexture(var.cd.icon)
			braindeadCooldownPanel:Show()
		else
			braindeadCooldownPanel:Hide()
		end
	end
	if var.extra ~= var.last_extra then
		if var.extra then
			braindeadExtraPanel.icon:SetTexture(var.extra.icon)
			braindeadExtraPanel:Show()
		else
			braindeadExtraPanel:Hide()
		end
	end
	if Opt.interrupt then
		UpdateInterrupt()
	end
	UpdateGlows()
	UpdateDisplay()
end

local function UpdateCombatWithin(seconds)
	if Opt.frequency - timer.combat > seconds then
		timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

function events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local start, duration
		local _, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			start = castStart / 1000
			duration = (castEnd - castStart) / 1000
		else
			start, duration = GetSpellCooldown(61304)
			if start <= 0 then
				return braindeadPanel.swipe:Hide()
			end
		end
		braindeadPanel.swipe:SetCooldown(start, duration)
		braindeadPanel.swipe:Show()
	end
end

function events:UNIT_POWER_UPDATE(srcName, powerType)
	if srcName == 'player' and powerType == 'RUNIC_POWER' then
		UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_START(srcName)
	if Opt.interrupt and srcName == 'target' then
		UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_STOP(srcName)
	if Opt.interrupt and srcName == 'target' then
		UpdateCombatWithin(0.05)
	end
end

function events:ADDON_LOADED(name)
	if name == 'Braindead' then
		Opt = Braindead
		if not Opt.frequency then
			print('It looks like this is your first time running Braindead, why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_Braindead1 .. '|r for a list of commands.')
		end
		if UnitLevel('player') < 110 then
			print('[|cFFFFD000Warning|r] Braindead is not designed for players under level 110, and almost certainly will not operate properly!')
		end
		InitializeOpts()
		Azerite:initialize()
		UpdateDraggable()
		UpdateAlpha()
		SnapAllPanels()
		braindeadPanel:SetScale(Opt.scale.main)
		braindeadPreviousPanel:SetScale(Opt.scale.previous)
		braindeadCooldownPanel:SetScale(Opt.scale.cooldown)
		braindeadInterruptPanel:SetScale(Opt.scale.interrupt)
		braindeadExtraPanel:SetScale(Opt.scale.extra)
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED()
	local timeStamp, eventType, _, srcGUID, _, _, _, dstGUID, _, _, _, spellId, spellName, _, missType = CombatLogGetCurrentEventInfo()
	var.time = GetTime()
	if eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
		trackAuras:remove(dstGUID)
		if Opt.auto_aoe then
			autoAoe:remove(dstGUID)
		end
	end
	if Opt.auto_aoe and (eventType == 'SWING_DAMAGE' or eventType == 'SWING_MISSED') then
		if dstGUID == var.player then
			autoAoe:add(srcGUID, true)
		elseif srcGUID == var.player and not (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:add(dstGUID, true)
		end
	end
	if srcGUID ~= var.player or not (
	   eventType == 'SPELL_CAST_START' or
	   eventType == 'SPELL_CAST_SUCCESS' or
	   eventType == 'SPELL_CAST_FAILED' or
	   eventType == 'SPELL_AURA_REMOVED' or
	   eventType == 'SPELL_DAMAGE' or
	   eventType == 'SPELL_PERIODIC_DAMAGE' or
	   eventType == 'SPELL_HEAL' or
	   eventType == 'SPELL_MISSED' or
	   eventType == 'SPELL_AURA_APPLIED' or
	   eventType == 'SPELL_AURA_REFRESH' or
	   eventType == 'SPELL_AURA_REMOVED')
	then
		return
	end
	local castedAbility = abilities.bySpellId[spellId]
	if not castedAbility then
		--print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', eventType, spellName, spellId))
		return
	end
--[[ DEBUG ]
	print(format('EVENT %s TRACK CHECK FOR %s ID %d', eventType, spellName, spellId))
	if eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' or eventType == 'SPELL_PERIODIC_DAMAGE' or eventType == 'SPELL_DAMAGE' then
		print(format('%s: %s - time: %.2f - time since last: %.2f', eventType, spellName, timeStamp, timeStamp - (castedAbility.last_trigger or timeStamp)))
		castedAbility.last_trigger = timeStamp
	end
--[ DEBUG ]]
	var.time_diff = var.time - timeStamp
	UpdateCombatWithin(0.05)
	if eventType == 'SPELL_CAST_SUCCESS' then
		var.last_ability = castedAbility
		if castedAbility.triggers_gcd then
			PreviousGCD[10] = nil
			table.insert(PreviousGCD, 1, castedAbility)
		end
		if castedAbility.travel_start then
			castedAbility.travel_start[dstGUID] = var.time
		end
		if Opt.previous and braindeadPanel:IsVisible() then
			braindeadPreviousPanel.ability = castedAbility
			braindeadPreviousPanel.border:SetTexture('Interface\\AddOns\\Braindead\\border.blp')
			braindeadPreviousPanel.icon:SetTexture(castedAbility.icon)
			braindeadPreviousPanel:Show()
		end
		return
	end
	if castedAbility.aura_targets then
		if eventType == 'SPELL_AURA_APPLIED' then
			castedAbility:applyAura(timeStamp, dstGUID)
		elseif eventType == 'SPELL_AURA_REFRESH' then
			castedAbility:refreshAura(timeStamp, dstGUID)
		elseif eventType == 'SPELL_AURA_REMOVED' then
			castedAbility:removeAura(dstGUID)
		elseif eventType == 'SPELL_PERIODIC_DAMAGE' then
			if castedAbility == VirulentPlague and Outbreak:ticking() > 0 then
				castedAbility:refreshAura(timeStamp, dstGUID)
			end
		end
	end
	if eventType == 'SPELL_MISSED' or eventType == 'SPELL_DAMAGE' or eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
		if castedAbility.travel_start and castedAbility.travel_start[dstGUID] then
			castedAbility.travel_start[dstGUID] = nil
		end
		if Opt.auto_aoe then
			if missType == 'EVADE' or missType == 'IMMUNE' then
				autoAoe:remove(dstGUID)
			elseif castedAbility.auto_aoe then
				castedAbility:recordTargetHit(dstGUID)
			end
		end
		if Opt.previous and Opt.miss_effect and eventType == 'SPELL_MISSED' and braindeadPanel:IsVisible() and castedAbility == braindeadPreviousPanel.ability then
			braindeadPreviousPanel.border:SetTexture('Interface\\AddOns\\Braindead\\misseffect.blp')
		end
	end
end

local function UpdateTargetInfo()
	Disappear()
	if ShouldHide() then
		return
	end
	local guid = UnitGUID('target')
	if not guid then
		Target.guid = nil
		Target.boss = false
		Target.player = false
		Target.hostile = true
		Target.healthMax = 0
		local i
		for i = 1, 15 do
			Target.healthArray[i] = 0
		end
		if Opt.always_on then
			UpdateTargetHealth()
			UpdateCombat()
			braindeadPanel:Show()
			return true
		end
		if Opt.previous and combatStartTime == 0 then
			braindeadPreviousPanel:Hide()
		end
		return
	end
	if guid ~= Target.guid then
		Target.guid = guid
		local i
		for i = 1, 15 do
			Target.healthArray[i] = UnitHealth('target')
		end
	end
	Target.level = UnitLevel('target')
	Target.healthMax = UnitHealthMax('target')
	Target.player = UnitIsPlayer('target')
	if Target.player then
		Target.boss = false
	elseif Target.level == -1 then
		Target.boss = true
	elseif var.instance == 'party' and Target.level >= UnitLevel('player') + 2 then
		Target.boss = true
	else
		Target.boss = false
	end
	Target.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	if Target.hostile or Opt.always_on then
		UpdateTargetHealth()
		UpdateCombat()
		braindeadPanel:Show()
		return true
	end
end

function events:PLAYER_TARGET_CHANGED()
	UpdateTargetInfo()
end

function events:UNIT_FACTION(unitID)
	if unitID == 'target' then
		UpdateTargetInfo()
	end
end

function events:UNIT_FLAGS(unitID)
	if unitID == 'target' then
		UpdateTargetInfo()
	end
end

function events:PLAYER_REGEN_DISABLED()
	combatStartTime = GetTime()
end

function events:PLAYER_REGEN_ENABLED()
	combatStartTime = 0
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
		autoAoe:clear()
		autoAoe:update()
	end
	if var.last_ability then
		var.last_ability = nil
		braindeadPreviousPanel:Hide()
	end
end

local function UpdateAbilityData()
	var.rune_max = UnitPowerMax('player', 5)
	var.runic_power_max = UnitPowerMax('player', 6)
	local _, ability
	for _, ability in next, abilities.all do
		ability.name, _, ability.icon = GetSpellInfo(ability.spellId)
		ability.known = (IsPlayerSpell(ability.spellId) or (ability.spellId2 and IsPlayerSpell(ability.spellId2)) or Azerite.traits[ability.spellId]) and true or false
	end
	if currentSpec == SPEC.UNHOLY then
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
	end
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

function events:PLAYER_EQUIPMENT_CHANGED()
	Azerite:update()
	UpdateAbilityData()
	ItemEquipped.RampingAmplitudeGigavoltEngine = Equipped(165580)
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitName)
	if unitName == 'player' then
		currentSpec = GetSpecialization() or 0
		Azerite:update()
		UpdateAbilityData()
		local _, i
		for i = 1, #inventoryItems do
			inventoryItems[i].name, _, _, _, _, _, _, _, _, inventoryItems[i].icon = GetItemInfo(inventoryItems[i].itemId)
		end
		braindeadPreviousPanel.ability = nil
		PreviousGCD = {}
		SetTargetMode(1)
		UpdateTargetInfo()
		events:PLAYER_REGEN_ENABLED()
	end
end

function events:PLAYER_ENTERING_WORLD()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_SPECIALIZATION_CHANGED('player')
	if #glows == 0 then
		CreateOverlayGlows()
		HookResourceFrame()
	end
	local _
	_, var.instance = IsInInstance()
	var.player = UnitGUID('player')
end

braindeadPanel.button:SetScript('OnClick', function(self, button, down)
	if down then
		if button == 'LeftButton' then
			ToggleTargetMode()
		elseif button == 'RightButton' then
			ToggleTargetModeReverse()
		elseif button == 'MiddleButton' then
			SetTargetMode(1)
		end
	end
end)

braindeadPanel:SetScript('OnUpdate', function(self, elapsed)
	timer.combat = timer.combat + elapsed
	timer.display = timer.display + elapsed
	timer.health = timer.health + elapsed
	if timer.combat >= Opt.frequency then
		UpdateCombat()
	end
	if timer.display >= 0.05 then
		UpdateDisplay()
	end
	if timer.health >= 0.2 then
		UpdateTargetHealth()
	end
end)

braindeadPanel:SetScript('OnEvent', function(self, event, ...) events[event](self, ...) end)
local event
for event in next, events do
	braindeadPanel:RegisterEvent(event)
end

function SlashCmdList.Braindead(msg, editbox)
	msg = { strsplit(' ', strlower(msg)) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UpdateDraggable()
		end
		return print('Braindead - Locked: ' .. (Opt.locked and '|cFF00C000On' or '|cFFC00000Off'))
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
			OnResourceFrameShow()
		end
		return print('Braindead - Snap to Blizzard combat resources frame: ' .. (Opt.snap and ('|cFF00C000' .. Opt.snap) or '|cFFC00000Off'))
	end
	if msg[1] == 'scale' then
		if startsWith(msg[2], 'prev') then
			if msg[3] then
				Opt.scale.previous = tonumber(msg[3]) or 0.7
				braindeadPreviousPanel:SetScale(Opt.scale.previous)
			end
			return print('Braindead - Previous ability icon scale set to: |cFFFFD000' .. Opt.scale.previous .. '|r times')
		end
		if msg[2] == 'main' then
			if msg[3] then
				Opt.scale.main = tonumber(msg[3]) or 1
				braindeadPanel:SetScale(Opt.scale.main)
			end
			return print('Braindead - Main ability icon scale set to: |cFFFFD000' .. Opt.scale.main .. '|r times')
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.scale.cooldown = tonumber(msg[3]) or 0.7
				braindeadCooldownPanel:SetScale(Opt.scale.cooldown)
			end
			return print('Braindead - Cooldown ability icon scale set to: |cFFFFD000' .. Opt.scale.cooldown .. '|r times')
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.scale.interrupt = tonumber(msg[3]) or 0.4
				braindeadInterruptPanel:SetScale(Opt.scale.interrupt)
			end
			return print('Braindead - Interrupt ability icon scale set to: |cFFFFD000' .. Opt.scale.interrupt .. '|r times')
		end
		if startsWith(msg[2], 'to') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				braindeadExtraPanel:SetScale(Opt.scale.extra)
			end
			return print('Braindead - Extra cooldown ability icon scale set to: |cFFFFD000' .. Opt.scale.extra .. '|r times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UpdateGlowColorAndScale()
			end
			return print('Braindead - Action button glow scale set to: |cFFFFD000' .. Opt.scale.glow .. '|r times')
		end
		return print('Braindead - Default icon scale options: |cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000extra 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Opt.alpha = max(min((tonumber(msg[2]) or 100), 100), 0) / 100
			UpdateAlpha()
		end
		return print('Braindead - Icon transparency set to: |cFFFFD000' .. Opt.alpha * 100 .. '%|r')
	end
	if startsWith(msg[1], 'freq') then
		if msg[2] then
			Opt.frequency = tonumber(msg[2]) or 0.2
		end
		return print('Braindead - Calculation frequency (max time to wait between each update): Every |cFFFFD000' .. Opt.frequency .. '|r seconds')
	end
	if startsWith(msg[1], 'glow') then
		if msg[2] == 'main' then
			if msg[3] then
				Opt.glow.main = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Braindead - Glowing ability buttons (main icon): ' .. (Opt.glow.main and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.glow.cooldown = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Braindead - Glowing ability buttons (cooldown icon): ' .. (Opt.glow.cooldown and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.glow.interrupt = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Braindead - Glowing ability buttons (interrupt icon): ' .. (Opt.glow.interrupt and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Braindead - Glowing ability buttons (extra icon): ' .. (Opt.glow.extra and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				Opt.glow.blizzard = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Braindead - Blizzard default proc glow: ' .. (Opt.glow.blizzard and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = max(min(tonumber(msg[3]) or 0, 1), 0)
				Opt.glow.color.g = max(min(tonumber(msg[4]) or 0, 1), 0)
				Opt.glow.color.b = max(min(tonumber(msg[5]) or 0, 1), 0)
				UpdateGlowColorAndScale()
			end
			return print('Braindead - Glow color:', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return print('Braindead - Possible glow options: |cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
	end
	if startsWith(msg[1], 'prev') then
		if msg[2] then
			Opt.previous = msg[2] == 'on'
			UpdateTargetInfo()
		end
		return print('Braindead - Previous ability icon: ' .. (Opt.previous and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'always' then
		if msg[2] then
			Opt.always_on = msg[2] == 'on'
			UpdateTargetInfo()
		end
		return print('Braindead - Show the Braindead UI without a target: ' .. (Opt.always_on and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return print('Braindead - Use Braindead for cooldown management: ' .. (Opt.cooldown and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'swipe' then
		if msg[2] then
			Opt.spell_swipe = msg[2] == 'on'
			if not Opt.spell_swipe then
				braindeadPanel.swipe:Hide()
			end
		end
		return print('Braindead - Spell casting swipe animation: ' .. (Opt.spell_swipe and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if startsWith(msg[1], 'dim') then
		if msg[2] then
			Opt.dimmer = msg[2] == 'on'
			if not Opt.dimmer then
				braindeadPanel.dimmer:Hide()
			end
		end
		return print('Braindead - Dim main ability icon when you don\'t have enough resources to use it: ' .. (Opt.dimmer and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'miss' then
		if msg[2] then
			Opt.miss_effect = msg[2] == 'on'
		end
		return print('Braindead - Red border around previous ability when it fails to hit: ' .. (Opt.miss_effect and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'aoe' then
		if msg[2] then
			Opt.aoe = msg[2] == 'on'
			Braindead_SetTargetMode(1)
			UpdateDraggable()
		end
		return print('Braindead - Allow clicking main ability icon to toggle amount of targets (disables moving): ' .. (Opt.aoe and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'bossonly' then
		if msg[2] then
			Opt.boss_only = msg[2] == 'on'
		end
		return print('Braindead - Only use cooldowns on bosses: ' .. (Opt.boss_only and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'hidespec' or startsWith(msg[1], 'spec') then
		if msg[2] then
			if startsWith(msg[2], 'b') then
				Opt.hide.blood = not Opt.hide.blood
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('Braindead - Blood specialization: |cFFFFD000' .. (Opt.hide.blood and '|cFFC00000Off' or '|cFF00C000On'))
			end
			if startsWith(msg[2], 'f') then
				Opt.hide.frost = not Opt.hide.frost
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('Braindead - Frost specialization: |cFFFFD000' .. (Opt.hide.frost and '|cFFC00000Off' or '|cFF00C000On'))
			end
			if startsWith(msg[2], 'u') then
				Opt.hide.unholy = not Opt.hide.unholy
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('Braindead - Unholy specialization: |cFFFFD000' .. (Opt.hide.unholy and '|cFFC00000Off' or '|cFF00C000On'))
			end
		end
		return print('Braindead - Possible hidespec options: |cFFFFD000blood|r/|cFFFFD000frost|r/|cFFFFD000unholy|r - toggle disabling Braindead for specializations')
	end
	if startsWith(msg[1], 'int') then
		if msg[2] then
			Opt.interrupt = msg[2] == 'on'
		end
		return print('Braindead - Show an icon for interruptable spells: ' .. (Opt.interrupt and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'auto' then
		if msg[2] then
			Opt.auto_aoe = msg[2] == 'on'
		end
		return print('Braindead - Automatically change target mode on AoE spells: ' .. (Opt.auto_aoe and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'ttl' then
		if msg[2] then
			Opt.auto_aoe_ttl = tonumber(msg[2]) or 10
		end
		return print('Braindead - Length of time target exists in auto AoE after being hit: |cFFFFD000' .. Opt.auto_aoe_ttl .. '|r seconds')
	end
	if startsWith(msg[1], 'pot') then
		if msg[2] then
			Opt.pot = msg[2] == 'on'
		end
		return print('Braindead - Show Battle potions in cooldown UI: ' .. (Opt.pot and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'ds' then
		if msg[2] then
			Opt.death_strike_threshold = max(min(tonumber(msg[2]) or 60, 100), 0)
		end
		return print('Prophetic - Health percentage threshold to recommend Death Strike: |cFFFFD000' .. Opt.death_strike_threshold .. '%|r')
	end
	if msg[1] == 'reset' then
		braindeadPanel:ClearAllPoints()
		braindeadPanel:SetPoint('CENTER', 0, -169)
		SnapAllPanels()
		return print('Braindead - Position has been reset to default')
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
		'pot |cFF00C000on|r/|cFFC00000off|r - show Battle potions in cooldown UI',
		'ds |cFFFFD000[percent]|r - health percentage threshold to recommend Death Strike',
		'|cFFFFD000reset|r - reset the location of the Braindead UI to default',
	} do
		print('  ' .. SLASH_Braindead1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Contact |cFFC41F3BRaids|cFFFFD000-Zul\'jin|r or |cFFFFD000Spy#1955|r (the author of this addon)')
end
