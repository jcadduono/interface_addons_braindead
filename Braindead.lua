local ADDON = 'Braindead'
if select(2, UnitClass('player')) ~= 'DEATHKNIGHT' then
	DisableAddOn(ADDON)
	return
end
local ADDON_PATH = 'Interface\\AddOns\\' .. ADDON .. '\\'

-- reference heavily accessed global functions from local scope for performance
local min = math.min
local max = math.max
local floor = math.floor
local GetRuneCooldown = _G.GetRuneCooldown
local GetSpellCharges = _G.GetSpellCharges
local GetSpellCooldown = _G.GetSpellCooldown
local GetSpellInfo = _G.GetSpellInfo
local GetTime = _G.GetTime
local GetUnitSpeed = _G.GetUnitSpeed
local UnitAura = _G.UnitAura
local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo
local UnitDetailedThreatSituation = _G.UnitDetailedThreatSituation
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local UnitPower = _G.UnitPower
local UnitPowerMax = _G.UnitPowerMax
-- end reference global functions

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

SLASH_Braindead1, SLASH_Braindead2, SLASH_Braindead3 = '/bd', '/brain', '/braindead'
BINDING_HEADER_BRAINDEAD = ADDON

local function InitOpts()
	local function SetDefaults(t, ref)
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
		cd_ttd = 8,
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

-- combat event related functions container
local CombatEvent = {}

-- automatically registered events container
local events = {}

local timer = {
	combat = 0,
	display = 0,
	health = 0,
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
	level = 1,
	spec = 0,
	group_size = 1,
	target_mode = 0,
	gcd = 1.5,
	gcd_remains = 0,
	cast_remains = 0,
	execute_remains = 0,
	haste_factor = 1,
	moving = false,
	health = {
		current = 0,
		max = 100,
	},
	runic_power = {
		current = 0,
		max = 100,
	},
	runes = {
		max = 6,
		ready = 0,
		regen = 0,
		remains = {},
	},
	pet = {
		active = false,
		alive = false,
		stuck = false,
		health = {
			current = 0,
			max = 100,
		},
	},
	swing = {
		mh = {
			last = 0,
			speed = 0,
			remains = 0,
		},
		oh = {
			last = 0,
			speed = 0,
			remains = 0,
		},
		last_taken = 0,
	},
	threat = {
		status = 0,
		pct = 0,
		lead = 0,
	},
	equipped = {
		twohand = false,
		offhand = false,
	},
	set_bonus = {
		t28 = 0,
	},
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
	},
	main_freecast = false,
	use_cds = false,
	drw_remains = 0,
	pooling_for_aotd = false,
	pooling_for_gargoyle = false,
}

-- current target information
local Target = {
	boss = false,
	guid = 0,
	health = {
		current = 0,
		loss_per_sec = 0,
		max = 100,
		pct = 100,
		history = {},
	},
	hostile = false,
	estimated_range = 30,
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
braindeadPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
braindeadPanel.border:Hide()
braindeadPanel.dimmer = braindeadPanel:CreateTexture(nil, 'BORDER')
braindeadPanel.dimmer:SetAllPoints(braindeadPanel)
braindeadPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
braindeadPanel.dimmer:Hide()
braindeadPanel.swipe = CreateFrame('Cooldown', nil, braindeadPanel, 'CooldownFrameTemplate')
braindeadPanel.swipe:SetAllPoints(braindeadPanel)
braindeadPanel.swipe:SetDrawBling(false)
braindeadPanel.swipe:SetDrawEdge(false)
braindeadPanel.text = CreateFrame('Frame', nil, braindeadPanel)
braindeadPanel.text:SetAllPoints(braindeadPanel)
braindeadPanel.text.tl = braindeadPanel.text:CreateFontString(nil, 'OVERLAY')
braindeadPanel.text.tl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
braindeadPanel.text.tl:SetPoint('TOPLEFT', braindeadPanel, 'TOPLEFT', 2.5, -3)
braindeadPanel.text.tl:SetJustifyH('LEFT')
braindeadPanel.text.tr = braindeadPanel.text:CreateFontString(nil, 'OVERLAY')
braindeadPanel.text.tr:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
braindeadPanel.text.tr:SetPoint('TOPRIGHT', braindeadPanel, 'TOPRIGHT', -2.5, -3)
braindeadPanel.text.tr:SetJustifyH('RIGHT')
braindeadPanel.text.bl = braindeadPanel.text:CreateFontString(nil, 'OVERLAY')
braindeadPanel.text.bl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
braindeadPanel.text.bl:SetPoint('BOTTOMLEFT', braindeadPanel, 'BOTTOMLEFT', 2.5, 3)
braindeadPanel.text.bl:SetJustifyH('LEFT')
braindeadPanel.text.br = braindeadPanel.text:CreateFontString(nil, 'OVERLAY')
braindeadPanel.text.br:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
braindeadPanel.text.br:SetPoint('BOTTOMRIGHT', braindeadPanel, 'BOTTOMRIGHT', -2.5, 3)
braindeadPanel.text.br:SetJustifyH('RIGHT')
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
braindeadPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
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
braindeadCooldownPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
braindeadCooldownPanel.dimmer = braindeadCooldownPanel:CreateTexture(nil, 'BORDER')
braindeadCooldownPanel.dimmer:SetAllPoints(braindeadCooldownPanel)
braindeadCooldownPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
braindeadCooldownPanel.dimmer:Hide()
braindeadCooldownPanel.swipe = CreateFrame('Cooldown', nil, braindeadCooldownPanel, 'CooldownFrameTemplate')
braindeadCooldownPanel.swipe:SetAllPoints(braindeadCooldownPanel)
braindeadCooldownPanel.swipe:SetDrawBling(false)
braindeadCooldownPanel.swipe:SetDrawEdge(false)
braindeadCooldownPanel.text = braindeadCooldownPanel:CreateFontString(nil, 'OVERLAY')
braindeadCooldownPanel.text:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
braindeadCooldownPanel.text:SetAllPoints(braindeadCooldownPanel)
braindeadCooldownPanel.text:SetJustifyH('CENTER')
braindeadCooldownPanel.text:SetJustifyV('CENTER')
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
braindeadInterruptPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
braindeadInterruptPanel.swipe = CreateFrame('Cooldown', nil, braindeadInterruptPanel, 'CooldownFrameTemplate')
braindeadInterruptPanel.swipe:SetAllPoints(braindeadInterruptPanel)
braindeadInterruptPanel.swipe:SetDrawBling(false)
braindeadInterruptPanel.swipe:SetDrawEdge(false)
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
braindeadExtraPanel.border:SetTexture(ADDON_PATH .. 'border.blp')

-- Start AoE

Player.target_modes = {
	[SPEC.NONE] = {
		{1, ''}
	},
	[SPEC.BLOOD] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'},
		{6, '6+'},
	},
	[SPEC.FROST] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'},
	},
	[SPEC.UNHOLY] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'},
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
	local npcId = guid:match('^%a+%-0%-%d+%-%d+%-%d+%-(%d+)')
	if not npcId or self.ignored_units[tonumber(npcId)] then
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
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
end

function autoAoe:Update()
	local count = 0
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
	local update
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
	all = {},
	bySpellId = {},
	velocity = {},
	autoAoe = {},
	trackAuras = {},
}

function Ability:Add(spellId, buff, player, spellId2)
	local ability = {
		spellIds = type(spellId) == 'table' and spellId or { spellId },
		spellId = 0,
		spellId2 = spellId2,
		name = false,
		icon = false,
		requires_charge = false,
		requires_react = false,
		requires_pet = false,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		hasted_ticks = false,
		known = false,
		rank = 0,
		runic_power_cost = 0,
		rune_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		max_range = 40,
		velocity = 0,
		last_used = 0,
		aura_target = buff and 'player' or 'target',
		aura_filter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
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
	return self:Cooldown() <= (seconds or 0) and (not self.requires_react or self:React() > (seconds or 0))
end

function Ability:Usable(seconds)
	if not self.known then
		return false
	end
	if self:RunicPowerCost() > Player.runic_power.current then
		return false
	end
	if self:RuneCost() > Player.runes.ready then
		return false
	end
	if self.requires_charge and self:Charges() == 0 then
		return false
	end
	if self.requires_pet and not Player.pet.active then
		return false
	end
	return self:Ready(seconds)
end

function Ability:Remains()
	if self:Casting() or self:Traveling() > 0 then
		return self:Duration()
	end
	local _, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.aura_target, i, self.aura_filter)
		if not id then
			return 0
		elseif self:Match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(0, expires - Player.ctime - Player.execute_remains)
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

function Ability:Up(...)
	return self:Remains(...) > 0
end

function Ability:Down(...)
	return self:Remains(...) <= 0
end

function Ability:SetVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.traveling = {}
	else
		self.traveling = nil
		self.velocity = 0
	end
end

function Ability:Traveling(all)
	if not self.traveling then
		return 0
	end
	local count = 0
	for _, cast in next, self.traveling do
		if all or cast.dstGUID == Target.guid then
			if Player.time - cast.start < self.max_range / self.velocity then
				count = count + 1
			end
		end
	end
	return count
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity
end

function Ability:Ticking()
	local count, ticking = 0, {}
	if self.aura_targets then
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > Player.execute_remains then
				ticking[guid] = true
			end
		end
	end
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity then
				ticking[cast.dstGUID] = true
			end
		end
	end
	for _ in next, ticking do
		count = count + 1
	end
	return count
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
	local _, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.aura_target, i, self.aura_filter)
		if not id then
			return 0
		elseif self:Match(id) then
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

function Ability:ChargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if self:Casting() then
		if charges >= max_charges then
			return charges - 1
		end
		charges = charges - 1
	end
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, Player.ctime - recharge_start + Player.execute_remains)) / recharge_time)
end

function Ability:Charges()
	return floor(self:ChargesFractional())
end

function Ability:MaxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:FullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if self:Casting() then
		if charges >= max_charges then
			return recharge_time
		end
		charges = charges - 1
	end
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - Player.execute_remains)
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
		return 0
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

function Ability:AutoAoe(removeUnaffected, trigger)
	self.auto_aoe = {
		remove = removeUnaffected,
		targets = {},
		target_count = 0,
		trigger = 'SPELL_DAMAGE',
	}
	if trigger == 'periodic' then
		self.auto_aoe.trigger = 'SPELL_PERIODIC_DAMAGE'
	elseif trigger == 'apply' then
		self.auto_aoe.trigger = 'SPELL_AURA_APPLIED'
	elseif trigger == 'cast' then
		self.auto_aoe.trigger = 'SPELL_CAST_SUCCESS'
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
		self.auto_aoe.target_count = 0
		for guid in next, self.auto_aoe.targets do
			autoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
			self.auto_aoe.target_count = self.auto_aoe.target_count + 1
		end
		autoAoe:Update()
	end
end

function Ability:Targets()
	if self.auto_aoe and self:Up() then
		return self.auto_aoe.target_count
	end
	return 0
end

function Ability:CastFailed(dstGUID, missType)
	if self.requires_pet and missType == 'No path available' then
		Player.pet.stuck = true
	end
end

function Ability:CastSuccess(dstGUID)
	self.last_used = Player.time
	Player.last_ability = self
	if self.triggers_gcd then
		Player.previous_gcd[10] = nil
		table.insert(Player.previous_gcd, 1, self)
	end
	if self.aura_targets and self.requires_react then
		self:RemoveAura(self.aura_target == 'player' and Player.guid or dstGUID)
	end
	if Opt.auto_aoe and self.auto_aoe and self.auto_aoe.trigger == 'SPELL_CAST_SUCCESS' then
		autoAoe:Add(dstGUID, true)
	end
	if self.requires_pet then
		Player.pet.stuck = false
	end
	if self.traveling and self.next_castGUID then
		self.traveling[self.next_castGUID] = {
			guid = self.next_castGUID,
			start = self.last_used,
			dstGUID = dstGUID,
		}
		self.next_castGUID = nil
	end
	if Opt.previous then
		braindeadPreviousPanel.ability = self
		braindeadPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
		braindeadPreviousPanel.icon:SetTexture(self.icon)
		braindeadPreviousPanel:SetShown(braindeadPanel:IsVisible())
	end
end

function Ability:CastLanded(dstGUID, event, missType)
	if self.traveling then
		local oldest
		for guid, cast in next, self.traveling do
			if Player.time - cast.start >= self.max_range / self.velocity + 0.2 then
				self.traveling[guid] = nil -- spell traveled 0.2s past max range, delete it, this should never happen
			elseif cast.dstGUID == dstGUID and (not oldest or cast.start < oldest.start) then
				oldest = cast
			end
		end
		if oldest then
			Target.estimated_range = min(self.max_range, floor(self.velocity * max(0, Player.time - oldest.start)))
			self.traveling[oldest.guid] = nil
		end
	end
	if self.range_est_start then
		Target.estimated_range = floor(max(5, min(self.max_range, self.velocity * (Player.time - self.range_est_start))))
		self.range_est_start = nil
	elseif self.max_range < Target.estimated_range then
		Target.estimated_range = self.max_range
	end
	if Opt.previous and Opt.miss_effect and event == 'SPELL_MISSED' and braindeadPreviousPanel.ability == self then
		braindeadPreviousPanel.border:SetTexture(ADDON_PATH .. 'misseffect.blp')
	end
end

-- Start DoT tracking

local trackAuras = {}

function trackAuras:Purge()
	for _, ability in next, abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
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

-- End DoT tracking

-- Death Knight Abilities
---- Multiple Specializations
local AntiMagicShell = Ability:Add(48707, true, true)
AntiMagicShell.buff_duration = 5
AntiMagicShell.cooldown_duration = 60
AntiMagicShell.triggers_gcd = false
local AntiMagicZone = Ability:Add(51052, true, true)
AntiMagicZone.buff_duration = 8
AntiMagicZone.cooldown_duration = 120
local ChainsOfIce = Ability:Add(45524, false)
ChainsOfIce.buff_duration = 8
ChainsOfIce.rune_cost = 1
local DarkCommand = Ability:Add(56222, false)
DarkCommand.buff_duration = 3
DarkCommand.cooldown_duration = 8
DarkCommand.triggers_gcd = false
local DeathAndDecay = Ability:Add(43265, true, true)
DeathAndDecay.cooldown_duration = 30
DeathAndDecay.rune_cost = 1
DeathAndDecay.buff = Ability:Add(188290, true, true)
DeathAndDecay.buff.buff_duration = 10
DeathAndDecay.damage = Ability:Add(52212, false, true)
DeathAndDecay.damage.tick_interval = 1
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
local Lichborne = Ability:Add(49039, true, true)
Lichborne.buff_duration = 10
Lichborne.cooldown_duration = 120
Lichborne.triggers_gcd = false
local MindFreeze = Ability:Add(47528, false, true)
MindFreeze.buff_duration = 3
MindFreeze.cooldown_duration = 15
MindFreeze.triggers_gcd = false
local RaiseAlly = Ability:Add(61999, false, true)
RaiseAlly.cooldown_duration = 600
RaiseAlly.runic_power_cost = 30
local RaiseDead = Ability:Add(46585, false, true)
RaiseDead.cooldown_duration = 120
local RuneOfRazorice = Ability:Add(53343, true, true)
RuneOfRazorice.bonus_id = 3370
local RuneOfTheFallenCrusader = Ability:Add(53344, true, true)
RuneOfTheFallenCrusader.bonus_id = 3368
local RuneOfHysteria = Ability:Add(326911, true, true)
RuneOfHysteria.bonus_id = 6243
local RuneOfTheStoneskinGargoyle = Ability:Add(62158, true, true)
RuneOfTheStoneskinGargoyle.bonus_id = 3847
------ Procs
local Hysteria = Ability:Add(326913, true, true, 326918) -- triggered by Rune of Hysteria
Hysteria.buff_duration = 8
local Razorice = Ability:Add(51714, false, true) -- triggered by Rune of Razorice
Razorice.buff_duration = 20
local UnholyStrength = Ability:Add(53365, true, true) -- triggered by Rune of the Fallen Crusader
UnholyStrength.buff_duration = 15
------ Talents
local Asphyxiate = Ability:Add(108194, false, true)
Asphyxiate.buff_duration = 4
Asphyxiate.cooldown_duration = 45
local DeathPact = Ability:Add(48743, false, true)
DeathPact.buff_duration = 15
DeathPact.cooldown_duration = 120
DeathPact.aura_target = 'player'
DeathPact.triggers_gcd = false
local SummonGargoyle = Ability:Add(49206, true, true)
SummonGargoyle.buff_duration = 30
SummonGargoyle.cooldown_duration = 180
---- Blood
local BloodBoil = Ability:Add(50842, false, true)
BloodBoil.cooldown_duration = 7.5
BloodBoil.requires_charge = true
BloodBoil:AutoAoe(true)
local BloodPlague = Ability:Add(55078, false, true)
BloodPlague.buff_duration = 24
BloodPlague.tick_interval = 3
BloodPlague:TrackAuras()
local DancingRuneWeapon = Ability:Add(49028, true, true, 81256)
DancingRuneWeapon.buff_duration = 8
DancingRuneWeapon.cooldown_duration = 120
local DeathsCaress = Ability:Add(195292, false, true)
DeathsCaress.rune_cost = 1
local GorefiendsGrasp = Ability:Add(108199, false, true)
GorefiendsGrasp.cooldown_duration = 120
local HeartStrike = Ability:Add(206930, false, true)
HeartStrike.buff_duration = 8
HeartStrike.rune_cost = 1
local Marrowrend = Ability:Add(195182, false, true)
Marrowrend.rune_cost = 2
local Ossuary = Ability:Add(219786, true, true, 219788)
local RelishInBlood = Ability:Add(317610, true, true)
local VampiricBlood = Ability:Add(55233, true, true)
VampiricBlood.buff_duration = 10
VampiricBlood.cooldown_duration = 90
VampiricBlood.triggers_gcd = false
------ Talents
local Blooddrinker = Ability:Add(206931, false, true)
Blooddrinker.buff_duration = 3
Blooddrinker.cooldown_duration = 30
Blooddrinker.rune_cost = 1
Blooddrinker.tick_interval = 1
Blooddrinker.hasted_duration = true
Blooddrinker.hasted_ticks = true
local BloodTap = Ability:Add(221699, true, true)
BloodTap.cooldown_duration = 60
BloodTap.requires_charge = true
local Bonestorm = Ability:Add(194844, true, true)
Bonestorm.buff_duration = 1
Bonestorm.cooldown_duration = 60
Bonestorm.runic_power_cost = 10
Bonestorm.tick_interval = 1
Bonestorm.damage = Ability:Add(196528, false, true)
Bonestorm.damage:AutoAoe()
local Consumption = Ability:Add(274156, false, true, 274893)
Consumption.cooldown_duration = 30
Consumption:AutoAoe()
local Heartbreaker = Ability:Add(210738, false, true)
local Hemostasis = Ability:Add(273946, true, true, 273947)
Hemostasis.buff_duration = 15
local RapidDecomposition = Ability:Add(194662, false, true)
local Tombstone = Ability:Add(219809, true, true)
Tombstone.buff_duration = 8
Tombstone.cooldown_duration = 60
------ Procs
local BoneShield = Ability:Add(195181, true, true)
BoneShield.buff_duration = 30
local CrimsonScourge = Ability:Add(81136, true, true, 81141)
CrimsonScourge.buff_duration = 15
------ Tier Bonuses
local EndlessRuneWaltz = Ability:Add(364399, true, true, 366008) -- T28 2 piece
---- Frost
local EmpowerRuneWeapon = Ability:Add(47568, true, true)
EmpowerRuneWeapon.buff_duration = 20
EmpowerRuneWeapon.cooldown_duration = 120
EmpowerRuneWeapon.triggers_gcd = false
local FrostFever = Ability:Add(55095, false, true)
FrostFever.buff_duration = 24
FrostFever.tick_interval = 3
FrostFever:TrackAuras()
local FrostStrike = Ability:Add(49143, false, true)
FrostStrike.runic_power_cost = 25
local FrostwyrmsFury = Ability:Add(279302, false, true, 279303)
FrostwyrmsFury.buff_duration = 10
FrostwyrmsFury.cooldown_duration = 180
FrostwyrmsFury:AutoAoe()
local HowlingBlast = Ability:Add(49184, false, true)
HowlingBlast.rune_cost = 1
HowlingBlast:AutoAoe()
local Obliterate = Ability:Add(49020, false, true)
Obliterate.rune_cost = 2
local PillarOfFrost = Ability:Add(51271, true, true)
PillarOfFrost.buff_duration = 12
PillarOfFrost.cooldown_duration = 60
PillarOfFrost.triggers_gcd = false
local RemorselessWinter = Ability:Add(196770, true, true)
RemorselessWinter.buff_duration = 8
RemorselessWinter.cooldown_duration = 20
RemorselessWinter.rune_cost = 1
RemorselessWinter.damage = Ability:Add(196771, false, true)
RemorselessWinter.damage:AutoAoe()
------ Talents
local Avalanche = Ability:Add(207142, false, true, 207150)
local BlindingSleet = Ability:Add(207167, false)
BlindingSleet.buff_duration = 5
BlindingSleet.cooldown_duration = 60
local BreathOfSindragosa = Ability:Add(152279, true, true)
BreathOfSindragosa.buff_duration = 120
BreathOfSindragosa.cooldown_duration = 120
BreathOfSindragosa.damage = Ability:Add(155166, false, true)
BreathOfSindragosa.damage:AutoAoe()
local ColdHeart = Ability:Add(281208, true, true, 281209)
local Frostscythe = Ability:Add(207230, false, true)
Frostscythe.rune_cost = 1
Frostscythe:AutoAoe()
local FrozenPulse = Ability:Add(194909, false, true, 195750)
FrozenPulse:AutoAoe()
local GatheringStorm = Ability:Add(194912, true, true, 211805)
local GlacialAdvance = Ability:Add(194913, false, true, 195975)
GlacialAdvance.cooldown_duration = 6
GlacialAdvance.runic_power_cost = 30
GlacialAdvance.hasted_cooldown = true
local HornOfWinter = Ability:Add(57330, true, true)
HornOfWinter.cooldown_duration = 45
local HypothermicPresence = Ability:Add(321995, true, true)
HypothermicPresence.buff_duration = 8
HypothermicPresence.cooldown_duration = 45
HypothermicPresence.triggers_gcd = false
local Icecap = Ability:Add(207126, true, true)
local IcyTalons = Ability:Add(194878, true, true, 194879)
IcyTalons.buff_duration = 6
local Obliteration = Ability:Add(281238, true, true, 207256)
local RunicAttenuation = Ability:Add(207104, true, true, 221322)
------ Procs
local KillingMachine = Ability:Add(51128, true, true, 51124)
KillingMachine.buff_duration = 10
local Rime = Ability:Add(59057, true, true, 59052)
Rime.buff_duration = 15
---- Unholy
local Apocalypse = Ability:Add(275699, false, true)
Apocalypse.cooldown_duration = 90
local ArmyOfTheDead = Ability:Add(42650, true, true, 42651)
ArmyOfTheDead.buff_duration = 4
ArmyOfTheDead.cooldown_duration = 480
ArmyOfTheDead.rune_cost = 1
local ControlUndead = Ability:Add(111673, true, true)
ControlUndead.buff_duration = 300
ControlUndead.rune_cost = 1
local DarkTransformation = Ability:Add(63560, true, true)
DarkTransformation.buff_duration = 15
DarkTransformation.cooldown_duration = 60
DarkTransformation.requires_pet = true
DarkTransformation.aura_target = 'pet'
local DeathCoil = Ability:Add(47541, false, true, 47632)
DeathCoil.runic_power_cost = 40
DeathCoil:SetVelocity(35)
local Epidemic = Ability:Add(207317, false, true, 212739)
Epidemic.runic_power_cost = 30
Epidemic.splash = Ability:Add(215969, false, true)
Epidemic.splash:AutoAoe(true)
local FesteringStrike = Ability:Add(85948, false, true)
FesteringStrike.rune_cost = 2
local FesteringWound = Ability:Add(194310, false, true, 194311)
FesteringWound.buff_duration = 30
local Outbreak = Ability:Add(77575, false, true)
Outbreak.rune_cost = 1
local RaiseDeadUnholy = Ability:Add(46584, false, true)
RaiseDeadUnholy.cooldown_duration = 30
local SacrificialPact = Ability:Add(327574, false, true)
SacrificialPact.cooldown_duration = 120
SacrificialPact.runic_power_cost = 20
local ScourgeStrike = Ability:Add(55090, false, true, 70890)
ScourgeStrike.rune_cost = 1
local VirulentPlague = Ability:Add(191587, false, true)
VirulentPlague.buff_duration = 27
VirulentPlague.tick_interval = 3
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
local Pestilence = Ability:Add(277234, false, true)
local RaiseAbomination = Ability:Add(288853, true, true)
RaiseAbomination.buff_duration = 25
RaiseAbomination.cooldown_duration = 90
local SoulReaper = Ability:Add(343294, false, true)
SoulReaper.rune_cost = 1
SoulReaper.buff_duration = 5
SoulReaper.cooldown_duration = 6
local UnholyBlight = Ability:Add(115989, true, true)
UnholyBlight.buff_duration = 6
UnholyBlight.cooldown_duration = 45
UnholyBlight.rune_cost = 1
UnholyBlight.dot = Ability:Add(115994, false, true)
UnholyBlight.dot.buff_duration = 14
UnholyBlight.dot.tick_interval = 2
UnholyBlight:AutoAoe(true)
local UnholyAssault = Ability:Add(207289, true, true)
UnholyAssault.buff_duration = 12
UnholyAssault.cooldown_duration = 75
------ Procs
local DarkSuccor = Ability:Add(101568, true, true)
DarkSuccor.buff_duration = 20
local RunicCorruption = Ability:Add(51462, true, true, 51460)
RunicCorruption.buff_duration = 3
local SuddenDoom = Ability:Add(49530, true, true, 81340)
SuddenDoom.buff_duration = 10
local VirulentEruption = Ability:Add(191685, false, true)
-- Covenant abilities
local AbominationLimb = Ability:Add(315443, true, true) -- Necrolord
AbominationLimb.buff_duration = 12
AbominationLimb.cooldown_duration = 120
AbominationLimb.tick_interval = 1
local DeathsDue = Ability:Add(324128, false, true) -- Night Fae, replaces Death and Decay
DeathsDue.cooldown_duration = 30
DeathsDue.rune_cost = 1
DeathsDue.learn_spellId = 315442
DeathsDue.buff = Ability:Add(324165, true, true)
DeathsDue.buff.buff_duration = 12
DeathsDue.damage = Ability:Add(341340, false, true)
DeathsDue.damage.tick_interval = 1
DeathsDue.damage:AutoAoe()
local FirstStrike = Ability:Add(325069, true, true, 325381) -- Night Fae (Korayn Soulbind)
local Fleshcraft = Ability:Add(324631, true, true) -- Necrolord
Fleshcraft.buff_duration = 120
Fleshcraft.cooldown_duration = 120
local LeadByExample = Ability:Add(342156, true, true, 342181) -- Necrolord (Emeni Soulbind)
LeadByExample.buff_duration = 10
local PustuleEruption = Ability:Add(351094, true, true) -- Necrolord (Emeni Soulbind)
local ShackleTheUnworthy = Ability:Add(312202, false, true) -- Kyrian
ShackleTheUnworthy.cooldown_duration = 60
ShackleTheUnworthy.buff_duration = 14
ShackleTheUnworthy.tick_interval = 2
ShackleTheUnworthy.hasted_ticks = true
ShackleTheUnworthy:TrackAuras()
local SwarmingMist = Ability:Add(311648, true, true) -- Venthyr
SwarmingMist.cooldown_duration = 60
SwarmingMist.buff_duration = 8
SwarmingMist.rune_cost = 1
local SummonSteward = Ability:Add(324739, false, true) -- Kyrian
SummonSteward.cooldown_duration = 300
-- Soulbind conduits
local EradicatingBlow = Ability:Add(337934, false, true, 337936)
EradicatingBlow.buff_duration = 10
EradicatingBlow.conduit_id = 83
local Everfrost = Ability:Add(337988, false, true, 337989)
Everfrost.buff_duration = 8
Everfrost.conduit_id = 91
local Proliferation = Ability:Add(338664, true, true)
Proliferation.conduit_id = 128
local UnleashedFrenzy = Ability:Add(338492, false, true, 338501)
UnleashedFrenzy.buff_duration = 6
UnleashedFrenzy.conduit_id = 122
-- Legendary effects
local BitingCold = Ability:Add(334678, true, true)
BitingCold.bonus_id = 6945
local CrimsonRuneWeapon = Ability:Add(334525, true, true, 334526)
CrimsonRuneWeapon.buff_duration = 10
CrimsonRuneWeapon.bonus_id = 6941
local KoltirasFavor = Ability:Add(334583, true, true)
KoltirasFavor.bonus_id = 6944
local Phearomones = Ability:Add(335177, false, true)
Phearomones.bonus_id = 6954
local RageOfTheFrozenChampion = Ability:Add(341724, true, true)
RageOfTheFrozenChampion.bonus_id = 7160
local RampantTransferance = Ability:Add(353882, false, true)
RampantTransferance.bonus_id = 7466
local Unity = Ability:Add(364758, true, true)
Unity.bonus_id = 8119
-- PvP talents

-- Racials

-- Trinket effects

-- End Abilities

-- Start Summoned Pets

local SummonedPet, Pet = {}, {}
SummonedPet.__index = SummonedPet
local summonedPets = {
	all = {},
	known = {},
	byNpcId = {},
}

function summonedPets:Find(guid)
	local npcId = guid:match('^Creature%-0%-%d+%-%d+%-%d+%-(%d+)')
	return npcId and self.byNpcId[tonumber(npcId)]
end

function summonedPets:Purge()
	local _, pet, guid, unit
	for _, pet in next, self.known do
		for guid, unit in next, pet.active_units do
			if unit.expires <= Player.time then
				pet.active_units[guid] = nil
			end
		end
	end
end

function summonedPets:Count()
	local _, pet, guid, unit
	local count = 0
	for _, pet in next, self.known do
		count = count + pet:Count()
	end
	return count
end

function SummonedPet:Add(npcId, duration, summonSpell)
	local pet = {
		npcId = npcId,
		duration = duration,
		active_units = {},
		summon_spell = summonSpell,
		known = false,
	}
	setmetatable(pet, self)
	summonedPets.all[#summonedPets.all + 1] = pet
	return pet
end

function SummonedPet:Remains(initial)
	local expires_max, guid, unit = 0
	for guid, unit in next, self.active_units do
		if (not initial or unit.initial) and unit.expires > expires_max then
			expires_max = unit.expires
		end
	end
	return max(0, expires_max - Player.time - Player.execute_remains)
end

function SummonedPet:Up(...)
	return self:Remains(...) > 0
end

function SummonedPet:Down(...)
	return self:Remains(...) <= 0
end

function SummonedPet:Count()
	local count, guid, unit = 0
	for guid, unit in next, self.active_units do
		if unit.expires - Player.time > Player.execute_remains then
			count = count + 1
		end
	end
	return count
end

function SummonedPet:Expiring(seconds)
	local count, guid, unit = 0
	for guid, unit in next, self.active_units do
		if unit.expires - Player.time <= (seconds or Player.execute_remains) then
			count = count + 1
		end
	end
	return count
end

function SummonedPet:AddUnit(guid)
	local unit = {
		guid = guid,
		expires = Player.time + self.duration,
	}
	self.active_units[guid] = unit
	return unit
end

function SummonedPet:RemoveUnit(guid)
	if self.active_units[guid] then
		self.active_units[guid] = nil
	end
end

-- Summoned Pets
Pet.RisenGhoul = SummonedPet:Add(26125, 60, RaiseDead)
Pet.ArmyOfTheDead = SummonedPet:Add(24207, 30, ArmyOfTheDead)
Pet.MagusOfTheDead = SummonedPet:Add(163366, 30, ArmyOfTheDead)
Pet.EbonGargoyle = SummonedPet:Add(27829, 30, SummonGargoyle)
Pet.RuneWeapon = SummonedPet:Add(27893, 8, DancingRuneWeapon)
-- End Summoned Pets

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
		charges = max(self.max_charges, charges)
	end
	return charges
end

function InventoryItem:Count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		count = max(1, count)
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
local EternalAugmentRune = InventoryItem:Add(190384)
EternalAugmentRune.buff = Ability:Add(367405, true, true)
local EternalFlask = InventoryItem:Add(171280)
EternalFlask.buff = Ability:Add(307166, true, true)
local PhialOfSerenity = InventoryItem:Add(177278) -- Provided by Summon Steward
PhialOfSerenity.max_charges = 3
local PotionOfPhantomFire = InventoryItem:Add(171349)
PotionOfPhantomFire.buff = Ability:Add(307495, true, true)
local PotionOfSpectralStrength = InventoryItem:Add(171275)
PotionOfSpectralStrength.buff = Ability:Add(307164, true, true)
local SpectralFlaskOfPower = InventoryItem:Add(171276)
SpectralFlaskOfPower.buff = Ability:Add(307185, true, true)
-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
Trinket.SoleahsSecretTechnique = InventoryItem:Add(190958)
Trinket.SoleahsSecretTechnique.buff = Ability:Add(368512, true, true)
Trinket.InscrutableQuantumDevice = InventoryItem:Add(179350)
Trinket.OverwhelmingPowerCrystal = InventoryItem:Add(179342)
Trinket.TheFirstSigil = InventoryItem:Add(188271)
-- End Inventory Items

-- Start Player API

function Player:Health()
	return self.health.current
end

function Player:HealthMax()
	return self.health.max
end

function Player:HealthPct()
	return self.health.current / self.health.max * 100
end

function Player:Runes()
	return self.runes.ready
end

function Player:RuneDeficit()
	return self.runes.max - self.runes.ready
end

function Player:RuneTimeTo(runes)
	return max(self.runes.remains[runes] - self.execute_remains, 0)
end

function Player:RunicPower()
	return self.runic_power.current
end

function Player:RunicPowerDeficit()
	return self.runic_power.max - self.runic_power.current
end

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	if self.ability_casting and self.ability_casting.triggers_combat then
		return 0.1
	end
	return 0
end

function Player:UnderAttack()
	return self.threat.status >= 3 or (self.time - self.last_swing_taken) < 3
end

function Player:BloodlustActive()
	local _, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if not id then
			return false
		elseif (
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
	for i = (slot or 1), (slot or 19) do
		if GetInventoryItemID('player', i) == itemID then
			return true, i
		end
	end
	return false
end

function Player:BonusIdEquipped(bonusId, slot)
	local link, item
	for i = (slot or 1), (slot or 19) do
		link = GetInventoryItemLink('player', i)
		if link then
			item = link:match('Hitem:%d+:([%d:]+)')
			if item then
				for id in item:gmatch('(%d+)') do
					if tonumber(id) == bonusId then
						return true
					end
				end
			end
		end
	end
	return false
end

function Player:InArenaOrBattleground()
	return self.instance == 'arena' or self.instance == 'pvp'
end

function Player:UpdateTime(timeStamp)
	self.ctime = GetTime()
	if timeStamp then
		self.time_diff = self.ctime - timeStamp
	end
	self.time = self.ctime - self.time_diff
end

function Player:UpdateAbilities()
	self.rescan_abilities = false
	self.runes.max = UnitPowerMax('player', 5)
	self.runic_power.max = UnitPowerMax('player', 6)

	local node
	for _, ability in next, abilities.all do
		ability.known = false
		for _, spellId in next, ability.spellIds do
			ability.spellId, ability.name, _, ability.icon = spellId, GetSpellInfo(spellId)
			if IsPlayerSpell(spellId) or (ability.learn_spellId and IsPlayerSpell(ability.learn_spellId)) then
				ability.known = true
				break
			end
		end
		if C_LevelLink.IsSpellLocked(ability.spellId) then
			ability.known = false -- spell is locked, do not mark as known
		end
		if ability.bonus_id then -- used for checking enchants and Legendary crafted effects
			ability.known = self:BonusIdEquipped(ability.bonus_id)
		end
		if ability.conduit_id then
			node = C_Soulbinds.FindNodeIDActuallyInstalled(C_Soulbinds.GetActiveSoulbindID(), ability.conduit_id)
			if node then
				node = C_Soulbinds.GetNode(node)
				if node then
					if node.conduitID == 0 then
						self.rescan_abilities = true -- rescan on next target, conduit data has not finished loading
					else
						ability.known = node.state == 3
						ability.rank = node.conduitRank
					end
				end
			end
		end
	end

	BloodPlague.known = BloodBoil.known
	BoneShield.known = Marrowrend.known
	Bonestorm.damage.known = Bonestorm.known
	BreathOfSindragosa.damage.known = BreathOfSindragosa.known
	FrostFever.known = HowlingBlast.known
	RemorselessWinter.damage.known = RemorselessWinter.known
	VirulentPlague.known = Outbreak.known
	VirulentEruption.known = VirulentPlague.known
	FesteringWound.known = FesteringStrike.known
	if Defile.known or DeathsDue.known then
		DeathAndDecay.known = false
	end
	if ClawingShadows.known then
		ScourgeStrike.known = false
	end
	if RaiseAbomination.known then
		ArmyOfTheDead.known = false
	end
	DeathAndDecay.buff.known = DeathAndDecay.known or DeathsDue.known
	DeathAndDecay.damage.known = DeathAndDecay.known
	DeathsDue.buff.known = DeathsDue.known
	DeathsDue.damage.known = DeathsDue.known
	EndlessRuneWaltz.known = self.set_bonus.t28 >= 2
	if Unity.known then
		RampantTransferance.known = DeathsDue.known
	end
	Hysteria.known = RuneOfHysteria.known
	Razorice.known = RuneOfRazorice.known
	UnholyStrength.known = RuneOfTheFallenCrusader.known

	wipe(abilities.bySpellId)
	wipe(abilities.velocity)
	wipe(abilities.autoAoe)
	wipe(abilities.trackAuras)
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

	wipe(summonedPets.known)
	wipe(summonedPets.byNpcId)
	for _, pet in next, summonedPets.all do
		pet.known = pet.summon_spell and pet.summon_spell.known
		if pet.known then
			summonedPets.known[#summonedPets.known + 1] = pet
			summonedPets.byNpcId[pet.npcId] = pet
		end
	end

	if DancingRuneWeapon.known then
		braindeadPanel.text.center:SetFont('Fonts\\FRIZQT__.TTF', 14, 'OUTLINE')
	else
		braindeadPanel.text.center:SetFont('Fonts\\FRIZQT__.TTF', 9, 'OUTLINE')
	end
end

function Player:UpdateThreat()
	local _, status, pct
	_, status, pct = UnitDetailedThreatSituation('player', 'target')
	self.threat.status = status or 0
	self.threat.pct = pct or 0
	self.threat.lead = 0
	if self.threat.status >= 3 and DETAILS_PLUGIN_TINY_THREAT then
		local threat_table = DETAILS_PLUGIN_TINY_THREAT.player_list_indexes
		if threat_table and threat_table[1] and threat_table[2] and threat_table[1][1] == Player.name then
			self.threat.lead = max(0, threat_table[1][6] - threat_table[2][6])
		end
	end
end

function Player:UpdatePet()
	self.pet.guid = UnitGUID('pet')
	self.pet.alive = self.pet.guid and not UnitIsDead('pet') and true
	self.pet.active = (self.pet.alive and not self.pet.stuck or IsFlying()) and true
end

function Player:UpdateRunes()
	wipe(self.runes.remains)
	self.runes.ready = 0
	local start, duration
	for i = 1, self.runes.max do
		start, duration = GetRuneCooldown(i)
		self.runes.remains[i] = max(0, (start or 0) + (duration or 0) - self.ctime)
		if self.runes.remains[i] <= self.execute_remains then
			self.runes.ready = self.runes.ready + 1
		end
	end
	table.sort(self.runes.remains)
end

function Player:Update()
	local _, start, duration, remains, spellId
	self.main =  nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	self:UpdateTime()
	start, duration = GetSpellCooldown(61304)
	self.gcd_remains = start > 0 and duration - (self.ctime - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	self.ability_casting = abilities.bySpellId[spellId]
	self.cast_remains = remains and (remains / 1000 - self.ctime) or 0
	self.execute_remains = max(self.cast_remains, self.gcd_remains)
	self.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	self.health.current = UnitHealth('player')
	self.health.max = UnitHealthMax('player')
	self.runic_power.current = UnitPower('player', 6)
	self.moving = GetUnitSpeed('player') ~= 0
	self:UpdateRunes()
	self:UpdateThreat()
	self:UpdatePet()

	summonedPets:Purge()
	trackAuras:Purge()
	if Opt.auto_aoe then
		for _, ability in next, abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		autoAoe:Purge()
	end
end

function Player:Init()
	local _
	if #UI.glows == 0 then
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
	end
	braindeadPreviousPanel.ability = nil
	self.guid = UnitGUID('player')
	self.name = UnitName('player')
	self.level = UnitLevel('player')
	_, self.instance = IsInInstance()
	events:GROUP_ROSTER_UPDATE()
	events:PLAYER_SPECIALIZATION_CHANGED('player')
end

-- End Player API

-- Start Target API

function Target:UpdateHealth(reset)
	timer.health = 0
	self.health.current = UnitHealth('target')
	self.health.max = UnitHealthMax('target')
	if self.health.current <= 0 then
		self.health.current = Player.health.max
		self.health.max = self.health.current
	end
	if reset then
		for i = 1, 25 do
			self.health.history[i] = self.health.current
		end
	else
		table.remove(self.health.history, 1)
		self.health.history[25] = self.health.current
	end
	self.timeToDieMax = self.health.current / Player.health.max * 10
	self.health.pct = self.health.max > 0 and (self.health.current / self.health.max * 100) or 100
	self.health.loss_per_sec = (self.health.history[1] - self.health.current) / 5
	self.timeToDie = self.health.loss_per_sec > 0 and min(self.timeToDieMax, self.health.current / self.health.loss_per_sec) or self.timeToDieMax
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
		self.level = Player.level
		self.hostile = false
		self:UpdateHealth(true)
		if Opt.always_on then
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
		self:UpdateHealth(true)
	end
	self.boss = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.level = UnitLevel('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		if self.level == -1 or (Player.instance == 'party' and self.level >= Player.level + 2) then
			self.boss = true
			self.stunnable = false
		elseif Player.instance == 'raid' or (self.health.max > Player.health.max * 10) then
			self.stunnable = false
		end
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		braindeadPanel:Show()
		return true
	end
end

function Target:Stunned()
	if Asphyxiate:Up() then
		return true
	end
	return false
end

-- End Target API

-- Start Ability Modifications

function Ability:RunicPowerCost()
	local cost = self.runic_power_cost
	if HypothermicPresence.known and HypothermicPresence:Up() then
		cost = cost * (1 - 0.35)
	end
	return cost
end

function ArmyOfTheDead:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	Pet.ArmyOfTheDead.summoned_by = self
	Pet.MagusOfTheDead.summoned_by = self
end
Apocalypse.CastSuccess = ArmyOfTheDead.CastSuccess

function DeathAndDecay:RuneCost()
	if CrimsonScourge.known and CrimsonScourge:Up() then
		return 0
	end
	return Ability.RuneCost(self)
end
DeathsDue.RuneCost = DeathAndDecay.RuneCost

function HowlingBlast:RuneCost()
	if Rime.known and Rime:Up() then
		return 0
	end
	return Ability.RuneCost(self)
end

function DeathCoil:RunicPowerCost()
	if SuddenDoom.known and SuddenDoom:Up() then
		return 0
	end
	return Ability.RunicPowerCost(self)
end

function Epidemic:RunicPowerCost()
	if SuddenDoom.known and SuddenDoom:Up() then
		return 0
	end
	return Ability.RunicPowerCost(self)
end

function DeathStrike:RunicPowerCost()
	if DarkSuccor.known and DarkSuccor:Up() then
		return 0
	end
	local cost = Ability.RunicPowerCost(self)
	if Ossuary.known and Ossuary:Up() then
		cost = cost - 5
	end
	return cost
end

function HeartStrike:Targets()
	return min(Player.enemies, DeathAndDecay.buff:Up() and 5 or 2)
end

function Obliterate:Targets()
	return min(Player.enemies, (DeathsDue.known and DeathAndDecay.buff:Up()) and 2 or 1)
end

function Tombstone:Usable()
	if BoneShield:Down() then
		return false
	end
	return Ability.Usable(self)
end

function VirulentPlague:Duration()
	local duration = Ability.Duration(self)
	if EbonFever.known then
		duration = duration / 2
	end
	return duration
end

function Outbreak:CastLanded(...)
	Ability.CastLanded(self, ...)
	VirulentPlague:RefreshAuraAll()
end

function Asphyxiate:Usable()
	if not Target.stunnable then
		return false
	end
	return Ability.Usable(self)
end
BlindingSleet.Usable = Asphyxiate.Usable

function ShackleTheUnworthy:Duration()
	local duration = Ability.Duration(self)
	if Proliferation.known then
		duration = duration + 3
	end
	return duration
end

function RaiseDead:Usable()
	if Player.pet.alive then
		return false
	end
	return Ability.Usable(self)
end

function SacrificialPact:Usable()
	if RaiseDeadUnholy.known and not Player.pet.alive then
		return false
	end
	if RaiseDead.known and Pet.RisenGhoul:Down() then
		return false
	end
	return Ability.Usable(self)
end

-- End Ability Modifications

-- Start Summoned Pet Modifications

function Pet.ArmyOfTheDead:AddUnit(guid)
	local unit = SummonedPet.AddUnit(self, guid)
	unit.summoned_by = self.summoned_by or ArmyOfTheDead
	if unit.summoned_by == Apocalypse then
		unit.expires = Player.time + 15
	end
	return unit
end
Pet.MagusOfTheDead.AddUnit = Pet.ArmyOfTheDead.AddUnit

-- End Summoned Pet Modifications

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

APL[SPEC.BLOOD].Main = function(self)
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
# Snapshot raid buffed stats before combat begins and pre-potting is done.
actions.precombat+=/snapshot_stats
actions.precombat+=/fleshcraft
]]
		if Trinket.SoleahsSecretTechnique:Usable() and Trinket.SoleahsSecretTechnique.buff:Remains() < 300 and Player.group_size > 1 then
			UseCooldown(Trinket.SoleahsSecretTechnique)
		end
		if SummonSteward:Usable() and PhialOfSerenity:Charges() < 1 then
			UseExtra(SummonSteward)
		end
		if Fleshcraft:Usable() and Fleshcraft:Remains() < 10 then
			UseExtra(Fleshcraft)
		end
		if not Player:InArenaOrBattleground() then
			if EternalAugmentRune:Usable() and EternalAugmentRune.buff:Remains() < 300 then
				UseCooldown(EternalAugmentRune)
			end
			if EternalFlask:Usable() and EternalFlask.buff:Remains() < 300 and SpectralFlaskOfPower.buff:Remains() < 300 then
				UseCooldown(EternalFlask)
			end
			if Opt.pot and SpectralFlaskOfPower:Usable() and SpectralFlaskOfPower.buff:Remains() < 300 and EternalFlask.buff:Remains() < 300 then
				UseCooldown(SpectralFlaskOfPower)
			end
		end
		if DeathAndDecay:Usable() then
			UseCooldown(DeathAndDecay)
		end
	else
		if Trinket.SoleahsSecretTechnique:Usable() and Trinket.SoleahsSecretTechnique.buff:Remains() < 10 and Player.group_size > 1 then
			UseExtra(Trinket.SoleahsSecretTechnique)
		end
	end
--[[
actions=auto_attack
actions+=/variable,name=death_strike_dump_amount,if=!covenant.night_fae,value=70
actions+=/variable,name=death_strike_dump_amount,if=covenant.night_fae,value=55
# Interrupt
actions+=/mind_freeze,if=target.debuff.casting.react
# Since the potion cooldown has changed, we'll sync with DRW
actions+=/potion,if=buff.dancing_rune_weapon.up
actions+=/use_items
actions+=/use_item,name=gavel_of_the_first_arbiter
actions+=/raise_dead
actions+=/blooddrinker,if=!buff.dancing_rune_weapon.up&(!covenant.night_fae|buff.deaths_due.remains>7)
actions+=/call_action_list,name=racials
# Attempt to sacrifice the ghoul if we predictably will not do much in the near future
actions+=/sacrificial_pact,if=(!covenant.night_fae|buff.deaths_due.remains>6)&buff.dancing_rune_weapon.remains>4&(pet.ghoul.remains<2|target.time_to_die<gcd)
actions+=/call_action_list,name=covenants
actions+=/blood_tap,if=(rune<=2&rune.time_to_4>gcd&charges_fractional>=1.8)|rune.time_to_3>gcd
actions+=/dancing_rune_weapon,if=!buff.dancing_rune_weapon.up
actions+=/run_action_list,name=drw_up,if=buff.dancing_rune_weapon.up
actions+=/call_action_list,name=standard
]]
	Player.drw_remains = DancingRuneWeapon:Remains()
	Player.use_cds = Target.boss or Target.player or Target.timeToDie > (Opt.cd_ttd - min(Player.enemies - 1, 6)) or Player.drw_remains > 0
	self.heart_strike_rp = (15 + (Player.drw_remains > 0 and 10 or 0) + (Heartbreaker.known and HeartStrike:Targets() * 2 or 0)) * (DeathsDue.known and DeathAndDecay.buff:Up() and 1 or 1.2)
	self.death_strike_prio_amount = self.heart_strike_rp + (67 - (Player:HealthPct() / 1.5))
	self.death_strike_dump_amount = 70 - (DeathsDue.known and 15 or 0)

	if Player.use_cds then
		if Opt.pot and Target.boss and PotionOfSpectralStrength:Usable() and Player.drw_remains > 0 then
			UseCooldown(PotionOfSpectralStrength)
		end
		if Opt.trinket then
			if Trinket.InscrutableQuantumDevice:Usable() and DancingRuneWeapon:Up() then
				UseCooldown(Trinket.InscrutableQuantumDevice)
			elseif Trinket.TheFirstSigil:Usable() and DancingRuneWeapon:Up() then
				UseCooldown(Trinket.TheFirstSigil)
			elseif Trinket.OverwhelmingPowerCrystal:Usable() and ((ShackleTheUnworthy.known and ShackleTheUnworthy:Ticking() > 0) or (not ShackleTheUnworthy.known and DancingRuneWeapon:Up())) then
				UseCooldown(Trinket.OverwhelmingPowerCrystal)
			elseif Trinket1:Usable() then
				UseCooldown(Trinket1)
			elseif Trinket2:Usable() then
				UseCooldown(Trinket2)
			end
		end
		if RaiseDead:Usable() then
			UseExtra(RaiseDead)
		end
		if Blooddrinker:Usable() and Player.drw_remains == 0 and (not DeathsDue.known or DeathsDue.buff:Remains() > 7) then
			UseCooldown(Blooddrinker)
		end
		if SacrificialPact:Usable() and (not DeathsDue.known or DeathsDue.buff:Remains() > 6) and DancingRuneWeapon:Remains() > 4 and (Pet.RisenGhoul:Remains() < 2 or Target.timeToDie < Player.gcd) then
			UseExtra(SacrificialPact)
		end
		if not Player.cd then
			self:covenants()
		end
		if BloodTap:Usable() and (Player:RuneTimeTo(3) > Player.gcd or (Player:Runes() <= 2 and Player:RuneTimeTo(4) > Player.gcd and BloodTap:ChargesFractional() >= 1.8)) then
			UseCooldown(BloodTap)
		end
		if DancingRuneWeapon:Usable() and Player.drw_remains == 0 then
			UseCooldown(DancingRuneWeapon)
		end
	end
	if DeathStrike:Usable() and Player:HealthPct() < 30 then
		return DeathStrike
	end
	if Player.drw_remains > 0 then
		local apl = self:drw_up()
		if apl then return apl end
	end
	return self:standard()
end

APL[SPEC.BLOOD].covenants = function(self)
--[[
actions.covenants=deaths_due,if=!buff.deaths_due.up|buff.deaths_due.remains<4|buff.crimson_scourge.up
actions.covenants+=/swarming_mist,if=cooldown.dancing_rune_weapon.remains>3&runic_power>=(90-(spell_targets.swarming_mist*3))
actions.covenants+=/abomination_limb
actions.covenants+=/fleshcraft,if=soulbind.pustule_eruption|soulbind.volatile_solvent&!buff.volatile_solvent_humanoid.up,interrupt_immediate=1,interrupt_global=1,interrupt_if=soulbind.volatile_solvent
actions.covenants+=/shackle_the_unworthy,if=runic_power<100&active_dot.shackle_the_unworthy=0&dot.blood_plague.remains
]]
	if DeathsDue:Usable() and DeathAndDecay.buff:Down() and (DeathsDue.buff:Remains() < 4 or CrimsonScourge:Up()) then
		UseCooldown(DeathsDue)
	end
	if SwarmingMist:Usable() and not DancingRuneWeapon:Ready(3) and Player:RunicPower() >= (90 - (Player.enemies * 3)) then
		UseCooldown(SwarmingMist)
	end
	if AbominationLimb:Usable() then
		UseCooldown(AbominationLimb)
	end
	if ShackleTheUnworthy:Usable() and Player:RunicPower() < 100 and ShackleTheUnworthy:Ticking() == 0 and BloodPlague:Up() then
		UseCooldown(ShackleTheUnworthy)
	end
end

APL[SPEC.BLOOD].drw_up = function(self)
--[[
actions.drw_up=tombstone,if=buff.bone_shield.stack>5&rune>=2&runic_power.deficit>=30&runeforge.crimson_rune_weapon
actions.drw_up+=/marrowrend,if=(buff.bone_shield.remains<=rune.time_to_3|(buff.bone_shield.stack<2&(!covenant.necrolord|buff.abomination_limb.up)))&runic_power.deficit>20
actions.drw_up+=/blood_boil,if=((charges>=2&rune<=1)|dot.blood_plague.remains<=2)|(spell_targets.blood_boil>5&charges_fractional>=1.1)&!(covenant.venthyr&buff.swarming_mist.up)
actions.drw_up+=/variable,name=heart_strike_rp_drw,value=(25+spell_targets.heart_strike*talent.heartbreaker.enabled*2)
actions.drw_up+=/death_strike,if=((runic_power.deficit<=variable.heart_strike_rp_drw)|(runic_power.deficit<=variable.death_strike_dump_amount&covenant.venthyr))&!(talent.bonestorm.enabled&cooldown.bonestorm.remains<2)
actions.drw_up+=/death_and_decay,if=(spell_targets.death_and_decay==3&buff.crimson_scourge.up)|spell_targets.death_and_decay>=4
actions.drw_up+=/bonestorm,if=runic_power>=100&buff.endless_rune_waltz.stack>4&!(covenant.venthyr&cooldown.swarming_mist.remains<3)
actions.drw_up+=/heart_strike,if=rune.time_to_2<gcd|runic_power.deficit>=variable.heart_strike_rp_drw
actions.drw_up+=/consumption
]]
	if CrimsonRuneWeapon.known and Tombstone:Usable() and BoneShield:Stack() > 5 and Player:Runes() >= 2 and Player:RunicPowerDeficit() >= 30 then
		UseCooldown(Tombstone)
	end
	if Marrowrend:Usable() and Player:RunicPowerDeficit() > 20 and (BoneShield:Remains() <= Player:RuneTimeTo(3) or (BoneShield:Stack() < 2 and (not AbominationLimb.known or AbominationLimb:Up()))) then
		return Marrowrend
	end
	if BloodBoil:Usable() and (((BloodBoil:Charges() >= 2 and Player:Runes() <= 1) or BloodPlague:Remains() <= 2) or ((Player.enemies > 5 and BloodBoil:ChargesFractional() >= 1.1) and (not SwarmingMist.known or SwarmingMist:Down()))) then
		return BloodBoil
	end
	if DeathStrike:Usable() and ((Player:RunicPowerDeficit() <= self.heart_strike_rp) or (SwarmingMist.known and Player:RunicPowerDeficit() <= self.death_strike_prio_amount)) and not (Bonestorm.known and Bonestorm:Ready(2)) then
		return DeathStrike
	end
	if DeathAndDecay:Usable() and Player.enemies >= (CrimsonScourge:Up() and 3 or 4) then
		return DeathAndDecay
	end
	if Bonestorm:Usable() and Player:RunicPower() >= 100 and EndlessRuneWaltz:Stack() > 4 and not (SwarmingMist.known and SwarmingMist:Ready(3)) then
		UseCooldown(Bonestorm)
	end
	if HeartStrike:Usable() and (Player:RuneTimeTo(2) < Player.gcd or Player:RunicPowerDeficit() >= self.heart_strike_rp) then
		return HeartStrike
	end
	if Consumption:Usable() then
		UseCooldown(Consumption)
	end
end

APL[SPEC.BLOOD].standard = function(self)
--[[
actions.standard=heart_strike,if=covenant.night_fae&death_and_decay.ticking&(buff.deaths_due.up&buff.deaths_due.remains<6)
actions.standard+=/tombstone,if=buff.bone_shield.stack>5&rune>=2&runic_power.deficit>=30&!(covenant.venthyr&cooldown.swarming_mist.remains<3)
actions.standard+=/marrowrend,if=(buff.bone_shield.remains<=rune.time_to_3|buff.bone_shield.remains<=(gcd+cooldown.blooddrinker.ready*talent.blooddrinker.enabled*4)|buff.bone_shield.stack<6|((!covenant.night_fae|buff.deaths_due.remains>5)&buff.bone_shield.remains<7))&runic_power.deficit>20&!(runeforge.crimson_rune_weapon&cooldown.dancing_rune_weapon.remains<buff.bone_shield.remains)
actions.standard+=/death_strike,if=runic_power.deficit<=variable.death_strike_dump_amount&!(talent.bonestorm.enabled&cooldown.bonestorm.remains<2)&!(covenant.venthyr&cooldown.swarming_mist.remains<3)
actions.standard+=/blood_boil,if=charges_fractional>=1.8&(buff.hemostasis.stack<=(5-spell_targets.blood_boil)|spell_targets.blood_boil>2)
actions.standard+=/death_and_decay,if=buff.crimson_scourge.up&talent.relish_in_blood.enabled&runic_power.deficit>10
actions.standard+=/bonestorm,if=runic_power>=100&!(covenant.venthyr&cooldown.swarming_mist.remains<3)
actions.standard+=/variable,name=heart_strike_rp,value=(15+spell_targets.heart_strike*talent.heartbreaker.enabled*2),op=setif,condition=covenant.night_fae&death_and_decay.ticking,value_else=(15+spell_targets.heart_strike*talent.heartbreaker.enabled*2)*1.2
actions.standard+=/death_strike,if=(runic_power.deficit<=variable.heart_strike_rp)|target.time_to_die<10
actions.standard+=/death_and_decay,if=spell_targets.death_and_decay>=3
actions.standard+=/heart_strike,if=rune.time_to_4<gcd
actions.standard+=/death_and_decay,if=buff.crimson_scourge.up|talent.rapid_decomposition.enabled
actions.standard+=/consumption
actions.standard+=/blood_boil,if=charges_fractional>=1.1
actions.standard+=/heart_strike,if=rune>1&(rune.time_to_3<gcd|buff.bone_shield.stack>7)
]]
	if DeathsDue.known and HeartStrike:Usable() and DeathAndDecay.buff:Up() and DeathsDue.buff:Up() and DeathsDue.buff:Remains() < 6 then
		return HeartStrike
	end
	if Player.use_cds and Tombstone:Usable() and BoneShield:Stack() > 5 and Player:Runes() >= 2 and Player:RunicPowerDeficit() >= 30 and not (SwarmingMist.known and SwarmingMist:Ready(3)) then
		UseCooldown(Tombstone)
	end
	if Marrowrend:Usable() and Player:RunicPowerDeficit() > 20 and not (CrimsonRuneWeapon.known and DancingRuneWeapon:Ready(BoneShield:Remains())) and (BoneShield:Stack() < 6 or BoneShield:Remains() <= Player:RuneTimeTo(3) or BoneShield:Remains() <= (Player.gcd + (Blooddrinker.known and Blooddrinker:Ready() and 4 or 0)) or ((not DeathsDue.known or DeathsDue.buff:Remains() > 5) and BoneShield:Remains() < 7)) then
		return Marrowrend
	end
	if DeathStrike:Usable() and Player:RunicPowerDeficit() <= self.death_strike_prio_amount and not (Bonestorm.known and Bonestorm:Ready(2)) and not (SwarmingMist.known and SwarmingMist:Ready(3)) then
		return DeathStrike
	end
	if BloodBoil:Usable() and BloodBoil:ChargesFractional() >= 1.8 and (Player.enemies > 2 or (Hemostasis.known and Hemostasis:Stack() <= (5 - Player.enemies))) then
		return BloodBoil
	end
	if RelishInBlood.known and DeathAndDecay:Usable() and CrimsonScourge:Up() and Player:RunicPowerDeficit() > 10 then
		return DeathAndDecay
	end
	if Player.use_cds and Bonestorm:Usable() and Player:RunicPower() >= 100 and not (SwarmingMist.known and SwarmingMist:Ready(3)) then
		UseCooldown(Bonestorm)
	end
	if DeathStrike:Usable() and (Player:RunicPowerDeficit() <= self.heart_strike_rp or (Target.boss and Player.enemies == 1 and Target.timeToDie < (Player.gcd * 2))) then
		return DeathStrike
	end
	if DeathAndDecay:Usable() and Player.enemies >= 3 then
		return DeathAndDecay
	end
	if HeartStrike:Usable() and Player:RuneTimeTo(4) < Player.gcd then
		return HeartStrike
	end
	if DeathAndDecay:Usable() and (RapidDecomposition.known or CrimsonScourge:Up()) then
		return DeathAndDecay
	end
	if Player.use_cds and Consumption:Usable() then
		UseCooldown(Consumption)
	end
	if BloodBoil:Usable() and BloodBoil:ChargesFractional() >= 1.1 then
		return BloodBoil
	end
	if DeathStrike:Usable() and Player:RunicPowerDeficit() <= self.death_strike_dump_amount and not (Bonestorm.known and Bonestorm:Ready(2)) and not (SwarmingMist.known and SwarmingMist:Ready(3)) then
		return DeathStrike
	end
	if HeartStrike:Usable() and Player:Runes() > 1 and (Player:RuneTimeTo(3) < Player.gcd or BoneShield:Stack() > 7) then
		return HeartStrike
	end
end

APL[SPEC.FROST].Main = function(self)
	self.rw_buffs = GatheringStorm.known or Everfrost.known or BitingCold.known
	self.st_planning = Player.enemies == 1
	self.adds_remain = Player.enemies >= 2
	self.rotfc_rime = Rime:Up() and (not RageOfTheFrozenChampion.known or Player:RunicPowerDeficit() > 8)
	self.frost_strike_conduits = (EradicatingBlow.known and EradicatingBlow:Stack() == 2) or (UnleashedFrenzy.known and UnleashedFrenzy:Remains() < (Player.gcd * 2))
	self.deaths_due_active = DeathsDue.known and DeathAndDecay.buff:Up()
	Player.use_cds = Target.boss or Target.player or Target.timeToDie > (Opt.cd_ttd - min(Player.enemies - 1, 6)) or EmpowerRuneWeapon:Up() or PillarOfFrost:Up() or (BreathOfSindragosa.known and BreathOfSindragosa:Up())

	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
# Snapshot raid buffed stats before combat begins and pre-potting is done.
actions.precombat+=/snapshot_stats
actions.precombat+=/fleshcraft
# Evaluates a trinkets cooldown, divided by pillar of frost or breath of sindragosa's cooldown. If it's value has no remainder return 1, else return 0.5.
actions.precombat+=/variable,name=trinket_1_sync,op=setif,value=1,value_else=0.5,condition=trinket.1.has_use_buff&(!talent.breath_of_sindragosa&(trinket.1.cooldown.duration%%cooldown.pillar_of_frost.duration=0)|talent.breath_of_sindragosa&(cooldown.breath_of_sindragosa.duration%%trinket.1.cooldown.duration=0)|talent.icecap)
actions.precombat+=/variable,name=trinket_2_sync,op=setif,value=1,value_else=0.5,condition=trinket.2.has_use_buff&(!talent.breath_of_sindragosa&(trinket.2.cooldown.duration%%cooldown.pillar_of_frost.duration=0)|talent.breath_of_sindragosa&(cooldown.breath_of_sindragosa.duration%%trinket.2.cooldown.duration=0)|talent.icecap)
# Estimates a trinkets value by comparing the cooldown of the trinket, divided by the duration of the buff it provides. Has a strength modifier to give a higher priority to strength trinkets, as well as a modifier for if a trinket will or will not sync with cooldowns.
actions.precombat+=/variable,name=trinket_priority,op=setif,value=2,value_else=1,condition=!trinket.1.has_use_buff&trinket.2.has_use_buff|trinket.2.has_use_buff&((trinket.2.cooldown.duration%trinket.2.proc.any_dps.duration)*(1.5+trinket.2.has_buff.strength)*(variable.trinket_2_sync))>((trinket.1.cooldown.duration%trinket.1.proc.any_dps.duration)*(1.5+trinket.1.has_buff.strength)*(variable.trinket_1_sync))
actions.precombat+=/variable,name=rw_buffs,value=talent.gathering_storm|conduit.everfrost|runeforge.biting_cold
]]
		if Trinket.SoleahsSecretTechnique:Usable() and Trinket.SoleahsSecretTechnique.buff:Remains() < 300 and Player.group_size > 1 then
			UseCooldown(Trinket.SoleahsSecretTechnique)
		end
		if SummonSteward:Usable() and PhialOfSerenity:Charges() < 1 then
			UseExtra(SummonSteward)
		end
		if Fleshcraft:Usable() and Fleshcraft:Remains() < 10 then
			UseExtra(Fleshcraft)
		end
		if not Player:InArenaOrBattleground() then
			if EternalAugmentRune:Usable() and EternalAugmentRune.buff:Remains() < 300 then
				UseCooldown(EternalAugmentRune)
			end
			if EternalFlask:Usable() and EternalFlask.buff:Remains() < 300 and SpectralFlaskOfPower.buff:Remains() < 300 then
				UseCooldown(EternalFlask)
			end
			if Opt.pot and SpectralFlaskOfPower:Usable() and SpectralFlaskOfPower.buff:Remains() < 300 and EternalFlask.buff:Remains() < 300 then
				UseCooldown(SpectralFlaskOfPower)
			end
		end
	else
		if Trinket.SoleahsSecretTechnique:Usable() and Trinket.SoleahsSecretTechnique.buff:Remains() < 10 and Player.group_size > 1 then
			UseExtra(Trinket.SoleahsSecretTechnique)
		end
	end
--[[
actions=auto_attack
# Prevent specified trinkets being used with automatic lines
actions+=/variable,name=specified_trinket,value=(equipped.inscrutable_quantum_device|equipped.the_first_sigil)&(cooldown.inscrutable_quantum_device.ready|cooldown.the_first_sigil.remains)|equipped.the_first_sigil&equipped.inscrutable_quantum_device
actions+=/variable,name=st_planning,value=active_enemies=1&(raid_event.adds.in>15|!raid_event.adds.exists)
actions+=/variable,name=adds_remain,value=active_enemies>=2&(!raid_event.adds.exists|raid_event.adds.exists&(raid_event.adds.remains>5|target.1.time_to_die>10))
actions+=/variable,name=rotfc_rime,value=buff.rime.up&(!runeforge.rage_of_the_frozen_champion|runeforge.rage_of_the_frozen_champion&runic_power.deficit>8)
actions+=/variable,name=frost_strike_conduits,value=conduit.eradicating_blow&buff.eradicating_blow.stack=2|conduit.unleashed_frenzy&buff.unleashed_frenzy.remains<(gcd*2)
actions+=/variable,name=deaths_due_active,value=death_and_decay.ticking&covenant.night_fae
# Apply Frost Fever, maintain Icy Talons and keep Remorseless Winter rolling
actions+=/remorseless_winter,if=!remains&conduit.everfrost&talent.gathering_storm&(!talent.obliteration&cooldown.pillar_of_frost.remains|set_bonus.tier28_4pc&talent.obliteration&!buff.pillar_of_frost.up)
actions+=/howling_blast,target_if=!dot.frost_fever.remains&(talent.icecap|!buff.breath_of_sindragosa.up&talent.breath_of_sindragosa|talent.obliteration&cooldown.pillar_of_frost.remains&!buff.killing_machine.up)
actions+=/glacial_advance,if=buff.icy_talons.remains<=gcd*2&talent.icy_talons&spell_targets.glacial_advance>=2&(talent.icecap|talent.breath_of_sindragosa&cooldown.breath_of_sindragosa.remains>15|talent.obliteration&!buff.pillar_of_frost.up)
actions+=/frost_strike,if=buff.icy_talons.remains<=gcd*2&talent.icy_talons&(talent.icecap|talent.breath_of_sindragosa&!buff.breath_of_sindragosa.up&cooldown.breath_of_sindragosa.remains>10|talent.obliteration&!buff.pillar_of_frost.up)
actions+=/obliterate,if=variable.deaths_due_active&death_and_decay.active_remains<(gcd*1.5)&(!talent.obliteration|!buff.pillar_of_frost.up)
# Interrupt
actions+=/mind_freeze,if=target.debuff.casting.react
# Choose Action list to run
actions+=/call_action_list,name=covenants
actions+=/call_action_list,name=racials
actions+=/call_action_list,name=trinkets
actions+=/call_action_list,name=cooldowns
actions+=/call_action_list,name=cold_heart,if=talent.cold_heart&(!buff.killing_machine.up|talent.breath_of_sindragosa)&((debuff.razorice.stack=5|!death_knight.runeforge.razorice)|fight_remains<=gcd)
actions+=/run_action_list,name=bos_ticking,if=buff.breath_of_sindragosa.up
actions+=/run_action_list,name=bos_pooling,if=talent.breath_of_sindragosa&!buff.breath_of_sindragosa.up&(cooldown.breath_of_sindragosa.remains<10)&(raid_event.adds.in>25|!raid_event.adds.exists|cooldown.pillar_of_frost.remains<10&raid_event.adds.exists&raid_event.adds.in<10)
actions+=/run_action_list,name=obliteration,if=buff.pillar_of_frost.up&talent.obliteration
actions+=/run_action_list,name=obliteration_pooling,if=!set_bonus.tier28_4pc&!runeforge.rage_of_the_frozen_champion&talent.obliteration&cooldown.pillar_of_frost.remains<10&(variable.st_planning|raid_event.adds.exists&raid_event.adds.in<10|!raid_event.adds.exists)
actions+=/run_action_list,name=aoe,if=active_enemies>=2
actions+=/call_action_list,name=standard
]]
	if RemorselessWinter:Usable() and RemorselessWinter:Down() and Everfrost.known and GatheringStorm.known and ((not Obliteration.known and not PillarOfFrost:Ready()) or (Player.set_bonus.t28 >= 4 and Obliteration.known and PillarOfFrost:Down())) then
		return RemorselessWinter
	end
	if HowlingBlast:Usable() and FrostFever:Down() and (Icecap.known or (BreathOfSindragosa.known and BreathOfSindragosa:Down()) or (Obliteration.known and not PillarOfFrost:Ready() and KillingMachine:Down())) then
		return HowlingBlast
	end
	if IcyTalons.known and IcyTalons:Remains() <= (Player.gcd * 2) then
		if GlacialAdvance:Usable() and Player.enemies >= 2 and (Icecap.known or (BreathOfSindragosa.known and not BreathOfSindragosa:Ready(15)) or (Obliteration.known and PillarOfFrost:Down())) then
			return GlacialAdvance
		end
		if FrostStrike:Usable() and (Icecap.known or (BreathOfSindragosa.known and not BreathOfSindragosa:Ready(10)) or (Obliteration.known and PillarOfFrost:Down())) then
			return FrostStrike
		end
	end
	if Obliterate:Usable() and self.deaths_due_active and DeathAndDecay.buff:Remains() < (Player.gcd * 1.5) and (not Obliteration.known or PillarOfFrost:Down()) then
		return Obliterate
	end
	if Player.use_cds then
		self:covenants()
		if Opt.trinket then
			self:trinkets()
		end
		self:cooldowns()
	end
	if BreathOfSindragosa.known then
		if BreathOfSindragosa:Up() then
			return self:bos_ticking()
		end
		if Player.use_cds and BreathOfSindragosa:Ready(10) then
			return self:bos_pooling()
		end
	end
	if Obliteration.known then
		if PillarOfFrost:Up() then
			return self:obliteration()
		end
		if Player.use_cds and Player.set_bonus.t28 < 4 and not RageOfTheFrozenChampion.known and PillarOfFrost:Ready(10) then
			return self:obliteration_pooling()
		end
	end
	if Player.enemies >= 2 then
		return self:aoe()
	end
	return self:standard()
end

APL[SPEC.FROST].aoe = function(self)
--[[
actions.aoe=remorseless_winter,if=remains<gcd
actions.aoe+=/glacial_advance,if=talent.frostscythe
actions.aoe+=/frostscythe,if=buff.killing_machine.react&!variable.deaths_due_active&(!talent.gathering_storm|rune>=2|cooldown.remorseless_winter.remains>rune.time_to_2)
actions.aoe+=/obliterate,if=buff.killing_machine.react&variable.deaths_due_active&(!talent.gathering_storm|rune>=3|cooldown.remorseless_winter.remains>rune.time_to_3)
actions.aoe+=/howling_blast,if=variable.rotfc_rime&talent.avalanche
actions.aoe+=/glacial_advance,if=!buff.rime.up&active_enemies<=3|active_enemies>3
# Formulaic approach to create a pseudo priority target list for applying razorice in aoe
actions.aoe+=/frost_strike,target_if=max:(debuff.razorice.stack+1)%(debuff.razorice.remains+1)*death_knight.runeforge.razorice,if=cooldown.remorseless_winter.remains<=2*gcd&talent.gathering_storm
actions.aoe+=/howling_blast,if=variable.rotfc_rime
actions.aoe+=/frostscythe,if=talent.gathering_storm&buff.remorseless_winter.up&active_enemies>2&!variable.deaths_due_active
actions.aoe+=/obliterate,if=variable.deaths_due_active&buff.deaths_due.stack<4|talent.gathering_storm&buff.remorseless_winter.up
actions.aoe+=/frost_strike,target_if=max:(debuff.razorice.stack+1)%(debuff.razorice.remains+1)*death_knight.runeforge.razorice,if=runic_power.deficit<(15+talent.runic_attenuation*5)
actions.aoe+=/frostscythe,if=!variable.deaths_due_active
actions.aoe+=/obliterate,target_if=max:(debuff.razorice.stack+1)%(debuff.razorice.remains+1)*death_knight.runeforge.razorice,if=runic_power.deficit>(25+talent.runic_attenuation*5)&(!covenant.night_fae|variable.deaths_due_active|cooldown.deaths_due.remains>gcd*3)
actions.aoe+=/glacial_advance
actions.aoe+=/frostscythe
actions.aoe+=/sacrificial_pact,if=!buff.empower_rune_weapon.up&active_enemies>=4
actions.aoe+=/frost_strike,target_if=max:(debuff.razorice.stack+1)%(debuff.razorice.remains+1)*death_knight.runeforge.razorice
actions.aoe+=/horn_of_winter
actions.aoe+=/arcane_torrent
]]
	if RemorselessWinter:Usable() and RemorselessWinter:Remains() < Player.gcd then
		return RemorselessWinter
	end
	if GlacialAdvance:Usable() and Frostscythe.known then
		return GlacialAdvance
	end
	if Frostscythe:Usable() and not self.deaths_due_active and KillingMachine:Up() and (not GatheringStorm.known or Player:Runes() >= 2 or not RemorselessWinter:Ready(Player:RuneTimeTo(2))) then
		return Frostscythe
	end
	if Obliterate:Usable() and self.deaths_due_active and KillingMachine:Up() and (not GatheringStorm.known or Player:Runes() >= 3 or not RemorselessWinter:Ready(Player:RuneTimeTo(3))) then
		return Obliterate
	end
	if HowlingBlast:Usable() and self.rotfc_rime and (Avalanche.known or FrostFever:Down()) then
		return HowlingBlast
	end
	if GlacialAdvance:Usable() and (Player.enemies > 3 or Rime:Down()) then
		return GlacialAdvance
	end
	if FrostStrike:Usable() and GatheringStorm.known and RemorselessWinter:Ready(2 * Player.gcd) then
		return FrostStrike
	end
	if HowlingBlast:Usable() and self.rotfc_rime then
		return HowlingBlast
	end
	if Frostscythe:Usable() and GatheringStorm.known and RemorselessWinter:Up() and Player.enemies > 2 and not self.deaths_due_active then
		return Frostscythe
	end
	if Obliterate:Usable() and ((self.deaths_due_active and DeathsDue.buff:Stack() < 4) or (GatheringStorm.known and RemorselessWinter:Up())) then
		return Obliterate
	end
	if FrostStrike:Usable() and Player:RunicPowerDeficit() < (15 + (RunicAttenuation.known and 5 or 0)) then
		return FrostStrike
	end
	if Frostscythe:Usable() and not self.deaths_due_active then
		return Frostscythe
	end
	if Obliterate:Usable() and Player:RunicPowerDeficit() > (25 + (RunicAttenuation.known and 5 or 0)) and (not DeathsDue.known or self.deaths_due_active or not DeathsDue:Ready(Player.gcd * 3)) then
		return Obliterate
	end
	if GlacialAdvance:Usable() then
		return GlacialAdvance
	end
	if Frostscythe:Usable() then
		return Frostscythe
	end
	if SacrificialPact:Usable() and EmpowerRuneWeapon:Down() and Player.enemies >= 4 then
		UseExtra(SacrificialPact)
	end
	if FrostStrike:Usable() then
		return FrostStrike
	end
	if HornOfWinter:Usable() then
		return HornOfWinter
	end
end

APL[SPEC.FROST].bos_pooling = function(self)
--[[
# Breath of Sindragosa pooling rotation : starts 10s before BoS is available
actions.bos_pooling=remorseless_winter,if=remains<gcd&(active_enemies>=2|variable.rw_buffs)
actions.bos_pooling+=/obliterate,target_if=max:(debuff.razorice.stack+1)%(debuff.razorice.remains+1)*death_knight.runeforge.razorice,if=buff.killing_machine.react&cooldown.pillar_of_frost.remains>3
actions.bos_pooling+=/howling_blast,if=variable.rotfc_rime
actions.bos_pooling+=/frostscythe,if=buff.killing_machine.react&runic_power.deficit>(15+talent.runic_attenuation*5)&spell_targets.frostscythe>2&!variable.deaths_due_active
actions.bos_pooling+=/frostscythe,if=runic_power.deficit>=(35+talent.runic_attenuation*5)&spell_targets.frostscythe>2&!variable.deaths_due_active
actions.bos_pooling+=/obliterate,target_if=max:(debuff.razorice.stack+1)%(debuff.razorice.remains+1)*death_knight.runeforge.razorice,if=runic_power.deficit>=25
actions.bos_pooling+=/glacial_advance,if=runic_power.deficit<20&spell_targets.glacial_advance>=2&cooldown.pillar_of_frost.remains>5
actions.bos_pooling+=/frost_strike,target_if=max:(debuff.razorice.stack+1)%(debuff.razorice.remains+1)*death_knight.runeforge.razorice,if=runic_power.deficit<20&cooldown.pillar_of_frost.remains>5
actions.bos_pooling+=/glacial_advance,if=cooldown.pillar_of_frost.remains>rune.time_to_4&runic_power.deficit<40&spell_targets.glacial_advance>=2
actions.bos_pooling+=/frost_strike,target_if=max:(debuff.razorice.stack+1)%(debuff.razorice.remains+1)*death_knight.runeforge.razorice,if=cooldown.pillar_of_frost.remains>rune.time_to_4&runic_power.deficit<40
]]

end

APL[SPEC.FROST].bos_ticking = function(self)
--[[
# Breath of Sindragosa Active Rotation
actions.bos_ticking=obliterate,target_if=max:(debuff.razorice.stack+1)%(debuff.razorice.remains+1)*death_knight.runeforge.razorice,if=runic_power<=(45+talent.runic_attenuation*5)
actions.bos_ticking+=/remorseless_winter,if=remains<gcd&(variable.rw_buffs|active_enemies>=2|runic_power<32&rune.time_to_2<runic_power%16)
actions.bos_ticking+=/death_and_decay,if=runic_power<32&rune.time_to_2<runic_power%16
actions.bos_ticking+=/howling_blast,if=variable.rotfc_rime&(runic_power>=45|rune.time_to_3<=gcd|runeforge.rage_of_the_frozen_champion|spell_targets.howling_blast>=2|buff.rime.remains<3)|runic_power<32&rune.time_to_2<runic_power%16
actions.bos_ticking+=/frostscythe,if=buff.killing_machine.up&spell_targets.frostscythe>2&!variable.deaths_due_active
actions.bos_ticking+=/obliterate,target_if=max:(debuff.razorice.stack+1)%(debuff.razorice.remains+1)*death_knight.runeforge.razorice,if=buff.killing_machine.react
actions.bos_ticking+=/horn_of_winter,if=runic_power<=60&rune.time_to_3>gcd
actions.bos_ticking+=/frostscythe,if=spell_targets.frostscythe>2&!variable.deaths_due_active
actions.bos_ticking+=/obliterate,target_if=max:(debuff.razorice.stack+1)%(debuff.razorice.remains+1)*death_knight.runeforge.razorice,if=runic_power.deficit>25|rune.time_to_4<gcd
actions.bos_ticking+=/howling_blast,if=variable.rotfc_rime
actions.bos_ticking+=/arcane_torrent,if=runic_power<50
]]

end

APL[SPEC.FROST].cold_heart = function(self)
--[[
# Cold Heart Conditions
actions.cold_heart=chains_of_ice,if=fight_remains<gcd&(rune<2|!buff.killing_machine.up&(!main_hand.2h&buff.cold_heart.stack>=4+runeforge.koltiras_favor|main_hand.2h&buff.cold_heart.stack>8+runeforge.koltiras_favor)|buff.killing_machine.up&(!main_hand.2h&buff.cold_heart.stack>8+runeforge.koltiras_favor|main_hand.2h&buff.cold_heart.stack>10+runeforge.koltiras_favor))
# Use during Pillar with Icecap/Breath
actions.cold_heart+=/chains_of_ice,if=!talent.obliteration&buff.pillar_of_frost.up&buff.cold_heart.stack>=10&(buff.pillar_of_frost.remains<gcd*(1+cooldown.frostwyrms_fury.ready)|buff.unholy_strength.up&buff.unholy_strength.remains<gcd|buff.chaos_bane.up&buff.chaos_bane.remains<gcd)
# Outside of Pillar useage with Icecap/Breath
actions.cold_heart+=/chains_of_ice,if=!talent.obliteration&death_knight.runeforge.fallen_crusader&!buff.pillar_of_frost.up&cooldown.pillar_of_frost.remains>15&(buff.cold_heart.stack>=10&(buff.unholy_strength.up|buff.chaos_bane.up)|buff.cold_heart.stack>=13)
actions.cold_heart+=/chains_of_ice,if=!talent.obliteration&!death_knight.runeforge.fallen_crusader&buff.cold_heart.stack>=10&!buff.pillar_of_frost.up&cooldown.pillar_of_frost.remains>20
# Prevent Cold Heart overcapping during pillar
actions.cold_heart+=/chains_of_ice,if=talent.obliteration&!buff.pillar_of_frost.up&(buff.cold_heart.stack>=14&(buff.unholy_strength.up|buff.chaos_bane.up)|buff.cold_heart.stack>=19|cooldown.pillar_of_frost.remains<3&buff.cold_heart.stack>=14)
]]

end

APL[SPEC.FROST].cooldowns = function(self)
--[[
# Potion
actions.cooldowns=potion,if=buff.pillar_of_frost.up
# Cooldowns
actions.cooldowns+=/empower_rune_weapon,if=talent.obliteration&rune<6&(variable.st_planning|variable.adds_remain)&(cooldown.pillar_of_frost.remains<5&(cooldown.fleshcraft.remains>5&soulbind.pustule_eruption|!soulbind.pustule_eruption)|buff.pillar_of_frost.up)|fight_remains<20
actions.cooldowns+=/empower_rune_weapon,if=talent.breath_of_sindragosa&rune<5&runic_power<(60-(death_knight.runeforge.hysteria*5)-(runeforge.rampant_transference*5))&(buff.breath_of_sindragosa.up|fight_remains<20)
actions.cooldowns+=/empower_rune_weapon,if=talent.icecap
actions.cooldowns+=/pillar_of_frost,if=talent.breath_of_sindragosa&(variable.st_planning|variable.adds_remain)&(cooldown.breath_of_sindragosa.remains|buff.breath_of_sindragosa.up&runic_power>45|cooldown.breath_of_sindragosa.ready&runic_power>65)
actions.cooldowns+=/pillar_of_frost,if=talent.icecap&!buff.pillar_of_frost.up
actions.cooldowns+=/pillar_of_frost,if=talent.obliteration&(runic_power>=35|buff.abomination_limb.up|runeforge.rage_of_the_frozen_champion)&(variable.st_planning|variable.adds_remain)&(!talent.gathering_storm.enabled|buff.remorseless_winter.up)&(!covenant.night_fae|variable.deaths_due_active|cooldown.deaths_due.remains>12)
actions.cooldowns+=/breath_of_sindragosa,if=!buff.breath_of_sindragosa.up&runic_power>60&(buff.pillar_of_frost.up|cooldown.pillar_of_frost.remains>15)
actions.cooldowns+=/frostwyrms_fury,if=active_enemies=1&buff.pillar_of_frost.remains<gcd&buff.pillar_of_frost.up&!talent.obliteration&(!raid_event.adds.exists|raid_event.adds.in>30)|fight_remains<3
actions.cooldowns+=/frostwyrms_fury,if=active_enemies>=2&(buff.pillar_of_frost.up|raid_event.adds.exists&raid_event.adds.in>cooldown.pillar_of_frost.remains+7)&(buff.pillar_of_frost.remains<gcd|raid_event.adds.exists&raid_event.adds.remains<gcd)
actions.cooldowns+=/frostwyrms_fury,if=talent.obliteration&(main_hand.2h&!buff.pillar_of_frost.up|!main_hand.2h&buff.pillar_of_frost.up)&((buff.pillar_of_frost.up&buff.unholy_strength.up|buff.pillar_of_frost.remains<gcd*2|buff.unholy_strength.up&buff.unholy_strength.remains<gcd*2)&(debuff.razorice.stack=5|!death_knight.runeforge.razorice))&(!covenant.night_fae|active_enemies>1&buff.first_strike.up&buff.first_strike.remains<gcd|cooldown.deaths_due.remains&!variable.deaths_due_active|buff.deaths_due.up&(buff.deaths_due.stack>=4|buff.deaths_due.remains<gcd*3))
actions.cooldowns+=/hypothermic_presence,if=talent.breath_of_sindragosa&runic_power<60&rune<=3&(buff.breath_of_sindragosa.up|cooldown.breath_of_sindragosa.remains>40)|!talent.breath_of_sindragosa&runic_power<=75
actions.cooldowns+=/raise_dead,if=cooldown.pillar_of_frost.remains<=5
actions.cooldowns+=/sacrificial_pact,if=active_enemies>=2&(fight_remains<3|!buff.breath_of_sindragosa.up&(pet.ghoul.remains<gcd|raid_event.adds.exists&raid_event.adds.remains<3&raid_event.adds.in>pet.ghoul.remains))
actions.cooldowns+=/death_and_decay,if=active_enemies>5|runeforge.phearomones
]]
	if Opt.pot and Target.boss and PotionOfSpectralStrength:Usable() and PillarOfFrost:Up() then
		UseExtra(PotionOfSpectralStrength)
	end
	if EmpowerRuneWeapon:Usable() and EmpowerRuneWeapon:Down() and (
		(Target.boss and Target.timeToDie < 20) or
		(Obliteration.known and Player:Runes() < 6 and (self.st_planning or self.adds_remain) and (PillarOfFrost:Up() or (PillarOfFrost:Ready(5) and (not PustuleEruption.known or not Fleshcraft.known or not Fleshcraft:Ready(5))))) or
		(BreathOfSindragosa.known and BreathOfSindragosa:Up() and Player:Runes() < 5 and Player:RunicPower() < (60 - (RuneOfHysteria.known and 5 or 0) - (RampantTransferance.known and 5 or 0))) or
		(Icecap.known)
	) then
		UseCooldown(EmpowerRuneWeapon)
	end
	if PillarOfFrost:Usable() and PillarOfFrost:Down() and (
		(Obliteration.known and ((Player:RunicPower() >= 35 or (AbominationLimb.known and AbominationLimb:Up()) or RageOfTheFrozenChampion.known) and (self.st_planning or self.adds_remain) and (not GatheringStorm.known or RemorselessWinter:Up()) and (not DeathsDue.known or self.deaths_due_active or not DeathsDue:Ready(12)))) or
		(BreathOfSindragosa.known and (self.st_planning or self.adds_remain) and (not BreathOfSindragosa:Ready() or (BreathOfSindragosa:Up() and Player:RunicPower() > 45) or (BreathOfSindragosa:Ready() and Player:RunicPower() > 65))) or
		(Icecap.known)
	) then
		UseCooldown(PillarOfFrost)
	end
	if BreathOfSindragosa:Usable() and BreathOfSindragosa:Down() and Player:RunicPower() > 60 and (PillarOfFrost:Up() or not PillarOfFrost:Ready(15)) then
		UseCooldown(BreathOfSindragosa)
	end
	if FrostwyrmsFury:Usable() and (
		(Target.boss and Target.timeToDie < 3) or
		(not Obliteration.known and PillarOfFrost:Up() and PillarOfFrost:Remains() < Player.gcd) or
		(Obliteration.known and ((Player.equipped.twohand and PillarOfFrost:Down()) or (not Player.equipped.twohand and PillarOfFrost:Up())) and ((PillarOfFrost:Up() and UnholyStrength:Up()) or PillarOfFrost:Remains() < (Player.gcd * 2) or (UnholyStrength:Up() and UnholyStrength:Remains() < (Player.gcd * 2))) and (not RuneOfRazorice.known or Razorice:Stack() >= 5) and (not DeathsDue.known or (FirstStrike.known and Player.enemies > 1 and FirstStrike:Up() and FirstStrike:Remains() < Player.gcd) or (not self.deaths_due_active and not DeathsDue:Ready()) or (DeathsDue.buff:Up() and (DeathsDue.buff:Stack() >= 4 or DeathsDue.buff:Remains() < (Player.gcd * 3)))))
	) then
		UseCooldown(FrostwyrmsFury)
	end
	if HypothermicPresence:Usable() and (
		(BreathOfSindragosa.known and Player:RunicPower() < 60 and Player:Runes() <= 3 and (BreathOfSindragosa:Up() or not BreathOfSindragosa:Ready(40))) or
		(not BreathOfSindragosa.known and Player:RunicPower() <= 75)
	) then
		UseCooldown(BreathOfSindragosa)
	end
	if RaiseDead:Usable() and PillarOfFrost:Ready(5) then
		UseExtra(RaiseDead)
	end
	if SacrificialPact:Usable() and Player.enemies >= 2 and (Target.timeToDie < 3 or ((not BreathOfSindragosa.known or BreathOfSindragosa:Down()) and (not Obliteration.known or PillarOfFrost:Down()) and Pet.RisenGhoul:Remains() < 3)) then
		UseExtra(SacrificialPact)
	end
	if DeathAndDecay:Usable() and (Player.enemies > 5 or Phearomones.known) then
		UseCooldown(DeathAndDecay)
	end
end

APL[SPEC.FROST].covenants = function(self)
--[[
# Covenant Abilities
actions.covenants=deaths_due,if=!variable.deaths_due_active&(!talent.obliteration|runeforge.phearomones|cooldown.pillar_of_frost.remains<gcd|rune.time_to_3<gcd*2&cooldown.pillar_of_frost.remains>9)&(variable.st_planning|variable.adds_remain)
actions.covenants+=/swarming_mist,if=runic_power.deficit>13&cooldown.pillar_of_frost.remains<3&!talent.breath_of_sindragosa&variable.st_planning
actions.covenants+=/swarming_mist,if=!talent.breath_of_sindragosa&variable.adds_remain
actions.covenants+=/swarming_mist,if=talent.breath_of_sindragosa&(buff.breath_of_sindragosa.up&(variable.st_planning&runic_power.deficit>40|variable.adds_remain&runic_power.deficit>60|variable.adds_remain&raid_event.adds.remains<9&raid_event.adds.exists)|!buff.breath_of_sindragosa.up&cooldown.breath_of_sindragosa.remains)
actions.covenants+=/abomination_limb,if=cooldown.pillar_of_frost.remains<gcd*2&variable.st_planning&(talent.breath_of_sindragosa&runic_power>65&cooldown.breath_of_sindragosa.remains<2|!talent.breath_of_sindragosa)
actions.covenants+=/abomination_limb,if=variable.adds_remain
actions.covenants+=/shackle_the_unworthy,if=variable.st_planning&(cooldown.pillar_of_frost.remains<3|talent.icecap)
actions.covenants+=/shackle_the_unworthy,if=variable.adds_remain
actions.covenants+=/fleshcraft,if=!buff.pillar_of_frost.up&(soulbind.pustule_eruption|soulbind.volatile_solvent&!buff.volatile_solvent_humanoid.up),interrupt_immediate=1,interrupt_global=1,interrupt_if=soulbind.volatile_solvent
]]
	if DeathsDue:Usable() and not self.deaths_due_active and (not Obliteration.known or Phearomones.known or PillarOfFrost:Ready(Player.gcd) or (Player:RuneTimeTo(3) < (Player.gcd * 2) and not PillarOfFrost:Ready(9))) and (self.st_planning or self.adds_remain) then
		return UseCooldown(DeathsDue)
	end
	if ShackleTheUnworthy:Usable() and ShackleTheUnworthy:Ticking() == 0 and (self.adds_remain or (self.st_planning and (Icecap.known or PillarOfFrost:Ready(3) or PillarOfFrost:Up()))) then
		return UseCooldown(ShackleTheUnworthy)
	end
end

APL[SPEC.FROST].obliteration = function(self)
--[[
# Obliteration rotation
actions.obliteration=remorseless_winter,if=!remains&active_enemies>=3&variable.rw_buffs
actions.obliteration+=/frost_strike,if=!buff.killing_machine.up&(rune<2|talent.icy_talons&buff.icy_talons.remains<gcd*2|conduit.unleashed_frenzy&(buff.unleashed_frenzy.remains<gcd*2|buff.unleashed_frenzy.stack<3))
actions.obliteration+=/howling_blast,target_if=!buff.killing_machine.up&rune>=3&(buff.rime.remains<3&buff.rime.up|!dot.frost_fever.ticking)
actions.obliteration+=/glacial_advance,if=!buff.killing_machine.up&spell_targets.glacial_advance>=2|!buff.killing_machine.up&(debuff.razorice.stack<5|debuff.razorice.remains<gcd*4)
actions.obliteration+=/frostscythe,if=buff.killing_machine.react&spell_targets.frostscythe>2&!variable.deaths_due_active
actions.obliteration+=/obliterate,target_if=max:(debuff.razorice.stack+1)%(debuff.razorice.remains+1)*death_knight.runeforge.razorice,if=buff.killing_machine.react
actions.obliteration+=/frost_strike,if=active_enemies=1&variable.frost_strike_conduits
actions.obliteration+=/howling_blast,if=variable.rotfc_rime&spell_targets.howling_blast>=2
actions.obliteration+=/glacial_advance,if=spell_targets.glacial_advance>=2
actions.obliteration+=/frost_strike,target_if=max:(debuff.razorice.stack+1)%(debuff.razorice.remains+1)*death_knight.runeforge.razorice,if=!talent.avalanche&!buff.killing_machine.up|talent.avalanche&!variable.rotfc_rime|variable.rotfc_rime&rune.time_to_2>=gcd
actions.obliteration+=/howling_blast,if=variable.rotfc_rime
actions.obliteration+=/obliterate,target_if=max:(debuff.razorice.stack+1)%(debuff.razorice.remains+1)*death_knight.runeforge.razorice
]]
	if RemorselessWinter:Usable() and RemorselessWinter:Down() and Player.enemies >= 3 and self.rw_buffs then
		return RemorselessWinter
	end
	if FrostStrike:Usable() and KillingMachine:Down() and (Player:Runes() < 2 or (IcyTalons.known and IcyTalons:Remains() < (Player.gcd * 2)) or (UnleashedFrenzy.known and (UnleashedFrenzy:Remains() < (Player.gcd * 2) or UnleashedFrenzy:Stacks() < 3))) then
		return FrostStrike
	end
	if HowlingBlast:Usable() and KillingMachine:Down() and Player:Runes() >= 3 and ((Rime:Up() and Rime:Remains() < 3) or FrostFever:Down()) then
		return HowlingBlast
	end
	if GlacialAdvance:Usable() and KillingMachine:Down() and (Player.enemies >= 2 or Razorice:Stack() < 5 or Razorice:Remains() < (Player.gcd * 4)) then
		return GlacialAdvance
	end
	if Frostscythe:Usable() and KillingMachine:Up() and Player.enemies > 2 and not self.deaths_due_active then
		return Frostscythe
	end
	if Obliterate:Usable() and KillingMachine:Up() then
		return Obliterate
	end
	if FrostStrike:Usable() and Player.enemies == 1 and self.frost_strike_conduits then
		return FrostStrike
	end
	if HowlingBlast:Usable() and self.rotfc_rime and Player.enemies >= 2 then
		return HowlingBlast
	end
	if GlacialAdvance:Usable() and Player.enemies >= 2 then
		return GlacialAdvance
	end
	if FrostStrike:Usable() and ((not Avalanche.known and KillingMachine:Down()) or (Avalanche.known and not self.rotfc_rime) or (self.rotfc_rime and Player:RuneTimeTo(2) >= Player.gcd)) then
		return FrostStrike
	end
	if HowlingBlast:Usable() and self.rotfc_rime then
		return HowlingBlast
	end
	if Obliterate:Usable() then
		return Obliterate
	end
end

APL[SPEC.FROST].obliteration_pooling = function(self)
--[[
# Pooling For Obliteration: Starts 10 seconds before Pillar of Frost comes off CD
actions.obliteration_pooling=remorseless_winter,if=remains<gcd&(variable.rw_buffs|active_enemies>=2)
actions.obliteration_pooling+=/glacial_advance,if=spell_targets.glacial_advance>=2&talent.frostscythe
actions.obliteration_pooling+=/frostscythe,if=buff.killing_machine.react&active_enemies>2&!variable.deaths_due_active
actions.obliteration_pooling+=/obliterate,target_if=max:(debuff.razorice.stack+1)%(debuff.razorice.remains+1)*death_knight.runeforge.razorice,if=buff.killing_machine.react
actions.obliteration_pooling+=/frost_strike,if=active_enemies=1&variable.frost_strike_conduits
actions.obliteration_pooling+=/howling_blast,if=variable.rotfc_rime
actions.obliteration_pooling+=/glacial_advance,if=spell_targets.glacial_advance>=2&runic_power.deficit<60
actions.obliteration_pooling+=/frost_strike,target_if=max:(debuff.razorice.stack+1)%(debuff.razorice.remains+1)*death_knight.runeforge.razorice,if=runic_power.deficit<70
actions.obliteration_pooling+=/obliterate,target_if=max:(debuff.razorice.stack+1)%(debuff.razorice.remains+1)*death_knight.runeforge.razorice,if=rune>=3&(!main_hand.2h|covenant.necrolord|covenant.kyrian)|rune>=4&main_hand.2h
actions.obliteration_pooling+=/frostscythe,if=active_enemies>=4&!variable.deaths_due_active
]]
	if RemorselessWinter:Usable() and RemorselessWinter:Remains() < Player.gcd and (self.rw_buffs or Player.enemies >= 2) then
		return RemorselessWinter
	end
	if Frostscythe.known then
		if GlacialAdvance:Usable() and Player.enemies >= 2 then
			return GlacialAdvance
		end
		if Frostscythe:Usable() and KillingMachine:Up() and Player.enemies > 2 and not self.deaths_due_active then
			return Frostscythe
		end
	end
	if Obliterate:Usable() and KillingMachine:Up() then
		return Obliterate
	end
	if FrostStrike:Usable() and Player.enemies == 1 and self.frost_strike_conduits then
		return FrostStrike
	end
	if HowlingBlast:Usable() and self.rotfc_rime then
		return HowlingBlast
	end
	if GlacialAdvance:Usable() and Player.enemies >= 2 and Player:RunicPowerDeficit() < 60 then
		return GlacialAdvance
	end
	if FrostStrike:Usable() and Player:RunicPowerDeficit() < 70 then
		return FrostStrike
	end
	if Obliterate:Usable() and ((Player:Runes() >= 3 and (not Player.equipped.twohand or AbominationLimb.known or ShackleTheUnworthy.known)) or (Player.equipped.twohand and Player:Runes() >= 4)) then
		return Obliterate
	end
	if Frostscythe:Usable() and Player.enemies >= 4 and not self.deaths_due_active then
		return Frostscythe
	end
end

APL[SPEC.FROST].standard = function(self)
--[[
# Standard single-target rotation
actions.standard=remorseless_winter,if=remains<gcd&variable.rw_buffs
actions.standard+=/obliterate,if=buff.killing_machine.react
actions.standard+=/howling_blast,if=variable.rotfc_rime&buff.rime.remains<3
actions.standard+=/frost_strike,if=variable.frost_strike_conduits
actions.standard+=/glacial_advance,if=!death_knight.runeforge.razorice&(debuff.razorice.stack<5|debuff.razorice.remains<gcd*4)
actions.standard+=/frost_strike,if=cooldown.remorseless_winter.remains<=2*gcd&talent.gathering_storm
actions.standard+=/howling_blast,if=variable.rotfc_rime
actions.standard+=/obliterate,if=rune.time_to_5<gcd
actions.standard+=/frost_strike,if=runic_power.deficit<(15+talent.runic_attenuation*5)
actions.standard+=/obliterate,if=!buff.frozen_pulse.up&talent.frozen_pulse|variable.deaths_due_active&buff.deaths_due.stack<4|(main_hand.2h|!covenant.night_fae|!set_bonus.tier28_4pc)&talent.gathering_storm&buff.remorseless_winter.up|!set_bonus.tier28_4pc&runic_power.deficit>(25+talent.runic_attenuation*5)
actions.standard+=/frost_strike
actions.standard+=/obliterate,if=rune.time_to_4<gcd&(!talent.gathering_storm|cooldown.remorseless_winter.remains>gcd*2)
actions.standard+=/horn_of_winter
actions.standard+=/arcane_torrent
]]
	if RemorselessWinter:Usable() and RemorselessWinter:Remains() < Player.gcd and self.rw_buffs then
		return RemorselessWinter
	end
	if Obliterate:Usable() and KillingMachine:Up() then
		return Obliterate
	end
	if HowlingBlast:Usable() and self.rotfc_rime and Rime:Remains() < 3 then
		return HowlingBlast
	end
	if FrostStrike:Usable() and self.frost_strike_conduits then
		return FrostStrike
	end
	if HowlingBlast:Usable() and self.rotfc_rime then
		return HowlingBlast
	end
	if Obliterate:Usable() and Player:RuneTimeTo(5) < Player.gcd then
		return Obliterate
	end
	if FrostStrike:Usable() and Player:RunicPowerDeficit() < (15 + (RunicAttenuation.known and 5 or 0)) then
		return FrostStrike
	end
	if Obliterate:Usable() and (
		(FrozenPulse.known and FrozenPulse:Down()) or
		(self.deaths_due_active and DeathsDue.buff:Stack() < 4) or
		((Player.equipped.twohand or not DeathsDue.known or Player.set_bonus.t28 < 4) and GatheringStorm.known and RemorselessWinter:Up()) or
		(Player.set_bonus.t28 < 4 and Player:RunicPowerDeficit() > (25 + (RunicAttenuation.known and 5 or 0)))
	) then
		return Obliterate
	end
	if FrostStrike:Usable() then
		return FrostStrike
	end
	if Obliterate:Usable() and Player:RuneTimeTo(4) < Player.gcd and (not GatheringStorm.known or not RemorselessWinter:Ready(Player.gcd * 2)) then
		return Obliterate
	end
	if HornOfWinter:Usable() then
		return HornOfWinter
	end
end

APL[SPEC.FROST].trinkets = function(self)
--[[
# Trinkets
actions.trinkets=use_item,name=inscrutable_quantum_device,if=!talent.breath_of_sindragosa&buff.pillar_of_frost.up&buff.empower_rune_weapon.up|talent.breath_of_sindragosa&((buff.pillar_of_frost.up&cooldown.breath_of_sindragosa.ready)|(buff.pillar_of_frost.up&((fight_remains-cooldown.breath_of_sindragosa.remains)<21)))|fight_remains<21|death_knight.disable_iqd_execute=0&target.time_to_pct_20<5
actions.trinkets+=/use_item,name=gavel_of_the_first_arbiter
actions.trinkets+=/use_item,name=scars_of_fraternal_strife
actions.trinkets+=/use_item,name=the_first_sigil,if=buff.pillar_of_frost.up&buff.empower_rune_weapon.up
# The trinket with the highest estimated value, will be used first and paired with Pillar of Frost.
actions.trinkets+=/use_item,slot=trinket1,if=!variable.specified_trinket&buff.pillar_of_frost.up&(!talent.icecap|talent.icecap&buff.pillar_of_frost.remains>=10)&(!trinket.2.has_cooldown|trinket.2.cooldown.remains|variable.trinket_priority=1)|trinket.1.proc.any_dps.duration>=fight_remains
actions.trinkets+=/use_item,slot=trinket2,if=!variable.specified_trinket&buff.pillar_of_frost.up&(!talent.icecap|talent.icecap&buff.pillar_of_frost.remains>=10)&(!trinket.1.has_cooldown|trinket.1.cooldown.remains|variable.trinket_priority=2)|trinket.2.proc.any_dps.duration>=fight_remains
# If only one on use trinket provides a buff, use the other on cooldown. Or if neither trinket provides a buff, use both on cooldown.
actions.trinkets+=/use_item,slot=trinket1,if=!variable.specified_trinket&(!trinket.1.has_use_buff&(trinket.2.cooldown.remains|!trinket.2.has_use_buff)|cooldown.pillar_of_frost.remains>20)
actions.trinkets+=/use_item,slot=trinket2,if=!variable.specified_trinket&(!trinket.2.has_use_buff&(trinket.1.cooldown.remains|!trinket.1.has_use_buff)|cooldown.pillar_of_frost.remains>20)
]]
	if Trinket.InscrutableQuantumDevice:Usable() and (
		(not BreathOfSindragosa.known and PillarOfFrost:Up() and EmpowerRuneWeapon:Up()) or
		(BreathOfSindragosa.known and PillarOfFrost:Up() and (BreathOfSindragosa:Ready() or (Target.boss and (Target.timeToDie - BreathOfSindragosa:Cooldown()) < 21))) or
		(Target.boss and Target.timeToDie < 21)
	) then
		return UseCooldown(Trinket.InscrutableQuantumDevice)
	end
	if Trinket.TheFirstSigil:Usable() and PillarOfFrost:Up() and EmpowerRuneWeapon:Up() then
		return UseCooldown(Trinket.TheFirstSigil)
	end
	if Trinket.OverwhelmingPowerCrystal:Usable() and ((PillarOfFrost:Up() and (not Icecap.known or PillarOfFrost:Remains() >= 10)) or (Target.boss and Target.timeToDie < 21)) then
		return UseCooldown(Trinket.OverwhelmingPowerCrystal)
	end
	if Trinket1:Usable() and ((PillarOfFrost:Up() and (not Icecap.known or PillarOfFrost:Remains() >= 10)) or (Target.boss and Target.timeToDie < 21)) then
		return UseCooldown(Trinket1)
	end
	if Trinket2:Usable() and ((PillarOfFrost:Up() and (not Icecap.known or PillarOfFrost:Remains() >= 10)) or (Target.boss and Target.timeToDie < 21)) then
		return UseCooldown(Trinket2)
	end
end

APL[SPEC.UNHOLY].Main = function(self)
	Player.use_cds = Target.boss or Target.player or Target.timeToDie > (Opt.cd_ttd - min(Player.enemies - 1, 6)) or DarkTransformation:Up() or (ArmyOfTheDead.known and ArmyOfTheDead:Up()) or (UnholyAssault.known and UnholyAssault:Up()) or (SummonGargoyle.known and Pet.EbonGargoyle:Up())
	Player.pooling_for_aotd = ArmyOfTheDead.known and Target.boss and ArmyOfTheDead:Ready(5)
	Player.pooling_for_gargoyle = Player.use_cds and SummonGargoyle.known and SummonGargoyle:Ready(5)

	if not Player.pet.active and RaiseDeadUnholy:Usable() then
		UseExtra(RaiseDeadUnholy)
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
		if Trinket.SoleahsSecretTechnique:Usable() and Trinket.SoleahsSecretTechnique.buff:Remains() < 300 and Player.group_size > 1 then
			UseCooldown(Trinket.SoleahsSecretTechnique)
		end
		if SummonSteward:Usable() and PhialOfSerenity:Charges() < 1 then
			UseExtra(SummonSteward)
		end
		if Fleshcraft:Usable() and Fleshcraft:Remains() < 10 then
			UseExtra(Fleshcraft)
		end
		if not Player:InArenaOrBattleground() then
			if EternalAugmentRune:Usable() and EternalAugmentRune.buff:Remains() < 300 then
				UseCooldown(EternalAugmentRune)
			end
			if EternalFlask:Usable() and EternalFlask.buff:Remains() < 300 and SpectralFlaskOfPower.buff:Remains() < 300 then
				UseCooldown(EternalFlask)
			end
			if Opt.pot and SpectralFlaskOfPower:Usable() and SpectralFlaskOfPower.buff:Remains() < 300 and EternalFlask.buff:Remains() < 300 then
				UseCooldown(SpectralFlaskOfPower)
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
	else
		if Trinket.SoleahsSecretTechnique:Usable() and Trinket.SoleahsSecretTechnique.buff:Remains() < 10 and Player.group_size > 1 then
			UseExtra(Trinket.SoleahsSecretTechnique)
		end
	end
--[[
actions+=/variable,name=pooling_for_gargoyle,value=cooldown.summon_gargoyle.remains<5&talent.summon_gargoyle.enabled
actions+=/arcane_torrent,if=runic_power.deficit>65&(pet.gargoyle.active|!talent.summon_gargoyle.enabled)&rune.deficit>=5
actions+=/potion,if=cooldown.army_of_the_dead.ready|pet.gargoyle.active|buff.unholy_assault.up
# Maintaining Virulent Plague is a priority
actions+=/outbreak,target_if=dot.virulent_plague.remains<=gcd
actions+=/call_action_list,name=cooldowns
actions+=/run_action_list,name=aoe,if=active_enemies>=2
actions+=/call_action_list,name=generic
]]
	if Opt.pot and Target.boss and PotionOfSpectralStrength:Usable() and (ArmyOfTheDead:Ready() or Pet.EbonGargoyle:Up() or UnholyAssault:Up()) then
		UseExtra(PotionOfSpectralStrength)
	end
	if Outbreak:Usable() and VirulentPlague:Remains() <= Player.gcd and Target.timeToDie > (VirulentPlague:Remains() + 1) then
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
actions.cooldowns+=/unholy_assault,if=debuff.festering_wound.stack<4&!equipped.ramping_amplitude_gigavolt_engine
actions.cooldowns+=/unholy_assault,if=cooldown.apocalypse.remains<2&equipped.ramping_amplitude_gigavolt_engine
actions.cooldowns+=/unholy_assault,if=active_enemies>=2&((cooldown.death_and_decay.remains<=gcd&!talent.defile.enabled)|(cooldown.defile.remains<=gcd&talent.defile.enabled))
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
		if UnholyAssault:Usable() then
			if MagusOfTheDead.known or (Trinket1.itemId == 165580 or Trinket2.itemId == 165580) then
				if Apocalypse:Ready(2) then
					return UseCooldown(UnholyAssault)
				end
			elseif FesteringWound:Stack() < 4 then
				return UseCooldown(UnholyAssault)
			end
			if Player.enemies >= 2 and ((DeathAndDecay:Ready(Player.gcd) and not Defile.known) or (Defile.known and Defile:Ready(Player.gcd))) then
				return UseCooldown(UnholyAssault)
			end
		end
		if SwarmingMist:Usable() and (Player:RunicPower() < 60 or Player.enemies >= 3) then
			UseCooldown(SwarmingMist)
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
actions.aoe+=/festering_strike,if=((((debuff.festering_wound.stack<4&!buff.unholy_assault.up)|debuff.festering_wound.stack<3)&cooldown.apocalypse.remains<3)|debuff.festering_wound.stack<1)&cooldown.army_of_the_dead.remains>5
actions.aoe+=/death_coil,if=!variable.pooling_for_gargoyle
]]
	if Outbreak:Usable() and not Outbreak:Previous() and VirulentPlague:Ticking() < Player.enemies then
		return Outbreak
	end
	local apocalypse_not_ready = not Player.use_cds or not Apocalypse.known or not Apocalypse:Ready()
	if DeathAndDecay:Usable() and apocalypse_not_ready and Target.timeToDie > max(6 - Player.enemies, 2) then
		return DeathAndDecay
	end
	if Defile:Usable() then
		return Defile
	end
	if DeathAndDecay.buff:Up() then
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
		if Pet.EbonGargoyle:Up() then
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
		if SacrificialPact:Usable() and RaiseDeadUnholy:Usable(Player.gcd) and not DarkTransformation:Ready(3) and DarkTransformation:Down() and (not UnholyAssault.known or UnholyAssault:Down()) then
			UseCooldown(SacrificialPact)
		end
		if Player:HealthPct() < Opt.death_strike_threshold and DeathStrike:Usable() then
			return DeathStrike
		end
		if DeathCoil:Usable() then
			return DeathCoil
		end
	end
	if not Player.pooling_for_aotd and FesteringStrike:Usable() and ((((FesteringWound:Stack() < 4 and UnholyAssault:Down()) or FesteringWound:Stack() < 3) and Apocalypse:Ready(3)) or FesteringWound:Stack() < 1) then
		return FesteringStrike
	end
	if DeathStrike:Usable() and DarkSuccor:Up() then
		return DeathStrike
	end
	if not Player.pooling_for_gargoyle then
		if SacrificialPact:Usable() and RaiseDeadUnholy:Usable(Player.gcd) and not DarkTransformation:Ready(3) and DarkTransformation:Down() and (not UnholyAssault.known or UnholyAssault:Down()) then
			UseCooldown(SacrificialPact)
		end
		if Player:HealthPct() < Opt.death_strike_threshold and DeathStrike:Usable() then
			return DeathStrike
		end
		if DeathCoil:Usable() then
			return DeathCoil
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
actions.generic+=/festering_strike,if=((((debuff.festering_wound.stack<4&!buff.unholy_assault.up)|debuff.festering_wound.stack<3)&cooldown.apocalypse.remains<3)|debuff.festering_wound.stack<1)&cooldown.army_of_the_dead.remains>5
actions.generic+=/death_coil,if=!variable.pooling_for_gargoyle
]]
	local apocalypse_not_ready_5 = not Player.use_cds or not Apocalypse.known or not Apocalypse:Ready(5)
	if DeathCoil:Usable() then
		if Pet.EbonGargoyle:Up() or (SuddenDoom:Up() and not Player.pooling_for_gargoyle) then
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
	if not Player.pooling_for_aotd and FesteringStrike:Usable() and ((((FesteringWound:Stack() < 4 and UnholyAssault:Down()) or FesteringWound:Stack() < 3) and Apocalypse:Ready(3)) or FesteringWound:Stack() < 1) then
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
end

APL.Interrupt = function(self)
	if MindFreeze:Usable() then
		return MindFreeze
	end
	if Asphyxiate:Usable() then
		return Asphyxiate
	end
	if BlindingSleet:Usable() then
		return BlindingSleet
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
	local w, h, glow
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
	local glow, icon
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
			['below'] = { 'TOP', 'BOTTOM', 0, -12 }
		},
		[SPEC.FROST] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 49 },
			['below'] = { 'TOP', 'BOTTOM', 0, -12 }
		},
		[SPEC.UNHOLY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 49 },
			['below'] = { 'TOP', 'BOTTOM', 0, -12 }
		}
	},
	kui = { -- Kui Nameplates
		[SPEC.BLOOD] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -2 }
		},
		[SPEC.FROST] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -2 }
		},
		[SPEC.UNHOLY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -2 }
		},
	},
}

function UI.OnResourceFrameHide()
	if Opt.snap then
		braindeadPanel:ClearAllPoints()
	end
end

function UI.OnResourceFrameShow()
	if Opt.snap and UI.anchor.points then
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
	local dim, dim_cd, text_center, text_cd

	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
		dim_cd = not ((not Player.cd) or
		           (Player.cd.spellId and IsUsableSpell(Player.cd.spellId)) or
		           (Player.cd.itemId and IsUsableItem(Player.cd.itemId)))
	end
	if Player.main and Player.main.requires_react then
		local react = Player.main:React()
		if react > 0 then
			text_center = format('%.1f', react)
		end
	end
	if Player.cd and Player.cd.requires_react then
		local react = Player.cd:React()
		if react > 0 then
			text_cd = format('%.1f', react)
		end
	end
	if Player.main and Player.main_freecast then
		if not braindeadPanel.freeCastOverlayOn then
			braindeadPanel.freeCastOverlayOn = true
			braindeadPanel.border:SetTexture(ADDON_PATH .. 'freecast.blp')
		end
	elseif braindeadPanel.freeCastOverlayOn then
		braindeadPanel.freeCastOverlayOn = false
		braindeadPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
	end
	if DancingRuneWeapon.known and Player.drw_remains > 0 then
		text_center = format('%.1fs', Player.drw_remains)
	elseif ArmyOfTheDead.known and Player.pooling_for_aotd then
		text_center = format('Pool for\n%s', ArmyOfTheDead.name)
	elseif SummonGargoyle.known and Player.pooling_for_gargoyle then
		text_center = format('Pool for\n%s', SummonGargoyle.name)
	end

	braindeadPanel.dimmer:SetShown(dim)
	braindeadPanel.text.center:SetText(text_center)
	--braindeadPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
	braindeadCooldownPanel.text:SetText(text_cd)
	braindeadCooldownPanel.dimmer:SetShown(dim_cd)
end

function UI:UpdateCombat()
	timer.combat = 0

	Player:Update()

	Player.main = APL[Player.spec]:Main()
	if Player.main then
		braindeadPanel.icon:SetTexture(Player.main.icon)
		Player.main_freecast = (Player.main.runic_power_cost > 0 and Player.main:RunicPowerCost() == 0) or (Player.main.rune_cost > 0 and Player.main:RuneCost() == 0)
	end
	if Player.cd then
		braindeadCooldownPanel.icon:SetTexture(Player.cd.icon)
		if Player.cd.spellId then
			local start, duration = GetSpellCooldown(Player.cd.spellId)
			braindeadCooldownPanel.swipe:SetCooldown(start, duration)
		end
	end
	if Player.extra then
		braindeadExtraPanel.icon:SetTexture(Player.extra.icon)
	end
	if Opt.interrupt then
		local _, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
		if not start then
			_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
		end
		if start and not notInterruptible then
			Player.interrupt = APL.Interrupt()
			braindeadInterruptPanel.swipe:SetCooldown(start / 1000, (ends - start) / 1000)
		end
		if Player.interrupt then
			braindeadInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		end
		braindeadInterruptPanel.icon:SetShown(Player.interrupt)
		braindeadInterruptPanel.border:SetShown(Player.interrupt)
		braindeadInterruptPanel:SetShown(start and not notInterruptible)
	end
	if Opt.previous and braindeadPreviousPanel.ability then
		if (Player.time - braindeadPreviousPanel.ability.last_used) > 10 then
			braindeadPreviousPanel.ability = nil
			braindeadPreviousPanel:Hide()
		end
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
	if name == ADDON then
		Opt = Braindead
		if not Opt.frequency then
			print('It looks like this is your first time running ' .. ADDON .. ', why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_Braindead1 .. '|r for a list of commands.')
		end
		if UnitLevel('player') < 10 then
			print('[|cFFFFD000Warning|r] ' .. ADDON .. ' is not designed for players under level 10, and almost certainly will not operate properly!')
		end
		InitOpts()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		UI:SnapAllPanels()
	end
end

CombatEvent.TRIGGER = function(timeStamp, event, _, srcGUID, _, _, _, dstGUID, _, _, _, ...)
	Player:UpdateTime(timeStamp)
	local e = event
	if (
	   e == 'UNIT_DESTROYED' or
	   e == 'UNIT_DISSIPATES' or
	   e == 'SPELL_INSTAKILL' or
	   e == 'PARTY_KILL')
	then
		e = 'UNIT_DIED'
	elseif (
	   e == 'SPELL_CAST_START' or
	   e == 'SPELL_CAST_SUCCESS' or
	   e == 'SPELL_CAST_FAILED' or
	   e == 'SPELL_DAMAGE' or
	   e == 'SPELL_ENERGIZE' or
	   e == 'SPELL_PERIODIC_DAMAGE' or
	   e == 'SPELL_MISSED' or
	   e == 'SPELL_AURA_APPLIED' or
	   e == 'SPELL_AURA_REFRESH' or
	   e == 'SPELL_AURA_REMOVED')
	then
		e = 'SPELL'
	end
	if CombatEvent[e] then
		return CombatEvent[e](event, srcGUID, dstGUID, ...)
	end
end

CombatEvent.UNIT_DIED = function(event, srcGUID, dstGUID)
	trackAuras:Remove(dstGUID)
	if Opt.auto_aoe then
		autoAoe:Remove(dstGUID)
	end
	local pet = summonedPets:Find(dstGUID)
	if pet then
		pet:RemoveUnit(dstGUID)
	end
end

CombatEvent.SWING_DAMAGE = function(event, srcGUID, dstGUID, amount, overkill, spellSchool, resisted, blocked, absorbed, critical, glancing, crushing, offHand)
	if srcGUID == Player.pet.guid then
		if Opt.auto_aoe then
			autoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.pet.guid then
		if Opt.auto_aoe then
			autoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SWING_MISSED = function(event, srcGUID, dstGUID, missType, offHand, amountMissed)
	if srcGUID == Player.pet.guid then
		if Opt.auto_aoe and not (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.pet.guid then
		if Opt.auto_aoe then
			autoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SPELL_SUMMON = function(event, srcGUID, dstGUID)
	if srcGUID ~= Player.guid then
		return
	end
	local pet = summonedPets:Find(dstGUID)
	if pet then
		pet:AddUnit(dstGUID)
	end
end

CombatEvent.SPELL = function(event, srcGUID, dstGUID, spellId, spellName, spellSchool, missType, overCap, powerType)
	local pet = summonedPets:Find(srcGUID)
	if pet then
		local unit = pet.active_units[srcGUID]
		if unit then
			if event == 'SPELL_CAST_SUCCESS' and pet.CastSuccess then
				pet:CastSuccess(unit, spellId, dstGUID)
			elseif event == 'SPELL_CAST_START' and pet.CastStart then
				pet:CastStart(unit, spellId, dstGUID)
			elseif event == 'SPELL_CAST_FAILED' and pet.CastFailed then
				pet:CastFailed(unit, spellId, dstGUID, missType)
			elseif event == 'SPELL_DAMAGE' and pet.SpellDamage then
				pet:SpellDamage(unit, spellId, dstGUID)
			end
			--print(format('PET %d EVENT %s SPELL %s ID %d', pet.npcId, event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0))
		end
		return
	end

	if not (srcGUID == Player.guid or srcGUID == Player.pet.guid) then
		return
	end

	if srcGUID == Player.pet.guid then
		if Player.pet.stuck and (event == 'SPELL_CAST_SUCCESS' or event == 'SPELL_DAMAGE' or event == 'SWING_DAMAGE') then
			Player.pet.stuck = false
		elseif not Player.pet.stuck and event == 'SPELL_CAST_FAILED' and missType == 'No path available' then
			Player.pet.stuck = true
		end
	end

	local ability = spellId and abilities.bySpellId[spellId]
	if not ability then
		--print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0))
		return
	end

	UI:UpdateCombatWithin(0.05)
	if event == 'SPELL_CAST_SUCCESS' then
		return ability:CastSuccess(dstGUID)
	elseif event == 'SPELL_CAST_START' then
		return ability.CastStart and ability:CastStart(dstGUID)
	elseif event == 'SPELL_CAST_FAILED'  then
		return ability:CastFailed(dstGUID, missType)
	elseif event == 'SPELL_ENERGIZE' then
		return ability.Energize and ability:Energize(missType, overCap, powerType)
	end
	if ability.aura_targets then
		if event == 'SPELL_AURA_APPLIED' then
			ability:ApplyAura(dstGUID)
		elseif event == 'SPELL_AURA_REFRESH' then
			ability:RefreshAura(dstGUID)
		elseif event == 'SPELL_AURA_REMOVED' then
			ability:RemoveAura(dstGUID)
		end
		if ability == VirulentPlague and eventType == 'SPELL_PERIODIC_DAMAGE' and not ability.aura_targets[dstGUID] then
			ability:ApplyAura(dstGUID) -- BUG: VP tick on unrecorded target, assume freshly applied (possibly by Raise Abomination?)
		end
	end
	if dstGUID == Player.guid or dstGUID == Player.pet.guid then
		return -- ignore buffs beyond here
	end
	if Opt.auto_aoe then
		if event == 'SPELL_MISSED' and (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:Remove(dstGUID)
		elseif ability.auto_aoe and (event == ability.auto_aoe.trigger or ability.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and event == 'SPELL_AURA_REFRESH') then
			ability:RecordTargetHit(dstGUID)
		elseif BurstingSores.known and ability == FesteringWound and (event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED') then
			BurstingSores:RecordTargetHit(dstGUID)
		end
	end
	if event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED' or event == 'SPELL_MISSED' or event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
		ability:CastLanded(dstGUID, event, missType)
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED()
	CombatEvent.TRIGGER(CombatLogGetCurrentEventInfo())
end

function events:PLAYER_TARGET_CHANGED()
	Target:Update()
	if Player.rescan_abilities then
		Player:UpdateAbilities()
	end
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

function events:UNIT_SPELLCAST_START(unitID, castGUID, spellId)
	if Opt.interrupt and unitID == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_STOP(unitID, castGUID, spellId)
	if Opt.interrupt and unitID == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end
events.UNIT_SPELLCAST_FAILED = events.UNIT_SPELLCAST_STOP
events.UNIT_SPELLCAST_INTERRUPTED = events.UNIT_SPELLCAST_STOP

function events:UNIT_SPELLCAST_SENT(unitId, destName, castGUID, spellId)
	if unitID ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = abilities.bySpellId[spellId]
	if not ability then
		return
	end
end

function events:UNIT_SPELLCAST_SUCCEEDED(unitID, castGUID, spellId)
	if unitID ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability.traveling then
		ability.next_castGUID = castGUID
	end
end

function events:PLAYER_REGEN_DISABLED()
	Player.combat_start = GetTime() - Player.time_diff
end

function events:PLAYER_REGEN_ENABLED()
	Player.combat_start = 0
	Player.pet.stuck = false
	Player.swing.last_taken = 0
	Target.estimated_range = 30
	wipe(Player.previous_gcd)
	if Player.last_ability then
		Player.last_ability = nil
		braindeadPreviousPanel:Hide()
	end
	for _, ability in next, abilities.velocity do
		for guid in next, ability.traveling do
			ability.traveling[guid] = nil
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
end

function events:PLAYER_EQUIPMENT_CHANGED()
	local _, equipType, hasCooldown
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

	_, _, _, _, _, _, _, _, equipType = GetItemInfo(GetInventoryItemID('player', 16) or 0)
	Player.equipped.twohand = equipType == 'INVTYPE_2HWEAPON'
	_, _, _, _, _, _, _, _, equipType = GetItemInfo(GetInventoryItemID('player', 17) or 0)
	Player.equipped.offhand = equipType == 'INVTYPE_WEAPON'

	Player.set_bonus.t28 = (Player:Equipped(188863) and 1 or 0) + (Player:Equipped(188864) and 1 or 0) + (Player:Equipped(188866) and 1 or 0) + (Player:Equipped(188867) and 1 or 0) + (Player:Equipped(188868) and 1 or 0)

	Player:UpdateAbilities()
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitId)
	if unitId ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	braindeadPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_REGEN_ENABLED()
	UI.OnResourceFrameShow()
	Player:Update()
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

function events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateAbilities()
end

function events:SOULBIND_ACTIVATED()
	Player:UpdateAbilities()
end

function events:SOULBIND_NODE_UPDATED()
	Player:UpdateAbilities()
end

function events:SOULBIND_PATH_CHANGED()
	Player:UpdateAbilities()
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
		Player.pet.stuck = true
	end
end

function events:GROUP_ROSTER_UPDATE()
	Player.group_size = max(1, min(40, GetNumGroupMembers()))
end

function events:PLAYER_ENTERING_WORLD()
	Player:Init()
	Target:Update()
	C_Timer.After(5, function() events:PLAYER_EQUIPMENT_CHANGED() end)
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
for event in next, events do
	braindeadPanel:RegisterEvent(event)
end

-- End Event Handling

-- Start Slash Commands

-- this fancy hack allows you to click BattleTag links to add them as a friend!
local SetHyperlink = ItemRefTooltip.SetHyperlink
ItemRefTooltip.SetHyperlink = function(self, link)
	local linkType, linkData = link:match('(.-):(.*)')
	if linkType == 'BNadd' then
		BattleTagInviteFrame_Show(linkData)
		return
	end
	SetHyperlink(self, link)
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
	print(ADDON, '-', desc .. ':', opt_view, ...)
end

SlashCmdList[ADDON] = function(msg, editbox)
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
		return Status('Snap to the Personal Resource Display frame', Opt.snap)
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
			Opt.alpha = max(0, min(100, tonumber(msg[2]) or 100)) / 100
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
				Opt.glow.color.r = max(0, min(1, tonumber(msg[3]) or 0))
				Opt.glow.color.g = max(0, min(1, tonumber(msg[4]) or 0))
				Opt.glow.color.b = max(0, min(1, tonumber(msg[5]) or 0))
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
		return Status('Show the ' .. ADDON .. ' UI without a target', Opt.always_on)
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return Status('Use ' .. ADDON .. ' for cooldown management', Opt.cooldown)
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
			if startsWith(msg[2], 'b') then
				Opt.hide.blood = not Opt.hide.blood
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Blood specialization', not Opt.hide.blood)
			end
			if startsWith(msg[2], 'f') then
				Opt.hide.frost = not Opt.hide.frost
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Frost specialization', not Opt.hide.frost)
			end
			if startsWith(msg[2], 'u') then
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
	if msg[1] == 'ttd' then
		if msg[2] then
			Opt.cd_ttd = tonumber(msg[2]) or 8
		end
		return Status('Minimum enemy lifetime to use cooldowns on (ignored on bosses)', Opt.cd_ttd, 'seconds')
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
			Opt.death_strike_threshold = max(0, min(100, tonumber(msg[2]) or 60))
		end
		return Status('Health percentage threshold to recommend Death Strike', Opt.death_strike_threshold .. '%')
	end
	if msg[1] == 'reset' then
		braindeadPanel:ClearAllPoints()
		braindeadPanel:SetPoint('CENTER', 0, -169)
		UI:SnapAllPanels()
		return Status('Position has been reset to', 'default')
	end
	print(ADDON, '(version: |cFFFFD000' .. GetAddOnMetadata(ADDON, 'Version') .. '|r) - Commands:')
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the ' .. ADDON .. ' UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the ' .. ADDON .. ' UI to the Personal Resource Display',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000pet|r/|cFFFFD000glow|r - adjust the scale of the ' .. ADDON .. ' UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the ' .. ADDON .. ' UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000pet|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the ' .. ADDON .. ' UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use ' .. ADDON .. ' for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough resources to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000blood|r/|cFFFFD000frost|r/|cFFFFD000unholy|r - toggle disabling ' .. ADDON .. ' for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'ttd |cFFFFD000[seconds]|r  - minimum enemy lifetime to use cooldowns on (default is 8 seconds, ignored on bosses)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'ds |cFFFFD000[percent]|r - health percentage threshold to recommend Death Strike',
		'|cFFFFD000reset|r - reset the location of the ' .. ADDON .. ' UI to default',
	} do
		print('  ' .. SLASH_Braindead1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands 
