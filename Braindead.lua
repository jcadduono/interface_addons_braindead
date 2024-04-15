local ADDON = 'Braindead'
local ADDON_PATH = 'Interface\\AddOns\\' .. ADDON .. '\\'

BINDING_CATEGORY_BRAINDEAD = ADDON
BINDING_NAME_BRAINDEAD_TARGETMORE = "Toggle Targets +"
BINDING_NAME_BRAINDEAD_TARGETLESS = "Toggle Targets -"
BINDING_NAME_BRAINDEAD_TARGET1 = "Set Targets to 1"
BINDING_NAME_BRAINDEAD_TARGET2 = "Set Targets to 2"
BINDING_NAME_BRAINDEAD_TARGET3 = "Set Targets to 3"
BINDING_NAME_BRAINDEAD_TARGET4 = "Set Targets to 4"
BINDING_NAME_BRAINDEAD_TARGET5 = "Set Targets to 5+"

local function log(...)
	print(ADDON, '-', ...)
end

if select(2, UnitClass('player')) ~= 'DEATHKNIGHT' then
	log('[|cFFFF0000Error|r]', 'Not loading because you are not the correct class! Consider disabling', ADDON, 'for this character.')
	return
end

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
local UnitAttackSpeed = _G.UnitAttackSpeed
local UnitAura = _G.UnitAura
local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo
local UnitDetailedThreatSituation = _G.UnitDetailedThreatSituation
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local UnitPower = _G.UnitPower
local UnitPowerMax = _G.UnitPowerMax
local UnitSpellHaste = _G.UnitSpellHaste
-- end reference global functions

-- useful functions
local function between(n, min, max)
	return n >= min and n <= max
end

local function clamp(n, min, max)
	return (n < min and min) or (n > max and max) or n
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
			animation = false,
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
local Events = {}

-- player ability template
local Ability = {}
Ability.__index = Ability

-- classified player abilities
local Abilities = {
	all = {},
	bySpellId = {},
	velocity = {},
	autoAoe = {},
	trackAuras = {},
}

-- summoned pet template
local SummonedPet = {}
SummonedPet.__index = SummonedPet

-- classified summoned pets
local SummonedPets = {
	all = {},
	known = {},
	byUnitId = {},
}

-- methods for target tracking / aoe modes
local AutoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {},
}

-- timers for updating combat/display/hp info
local Timer = {
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

-- action priority list container
local APL = {
	[SPEC.NONE] = {},
	[SPEC.BLOOD] = {},
	[SPEC.FROST] = {},
	[SPEC.UNHOLY] = {},
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
	execute_remains = 0,
	haste_factor = 1,
	moving = false,
	health = {
		current = 0,
		max = 100,
		pct = 100,
	},
	cast = {
		start = 0,
		ends = 0,
		remains = 0,
	},
	runic_power = {
		current = 0,
		max = 100,
		deficit = 100,
	},
	runes = {
		max = 6,
		ready = 0,
		deficit = 0,
		regen = 0,
		remains = {},
	},
	threat = {
		status = 0,
		pct = 0,
		lead = 0,
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
	equipped = {
		twohand = false,
		offhand = false,
	},
	set_bonus = {
		t29 = 0, -- Haunted Frostbrood Remains
		t30 = 0, -- Lingering Phantom's Encasement
		t31 = 0, -- Risen Nightmare's Gravemantle
	},
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
		[190958] = true, -- Soleah's Secret Technique
		[193757] = true, -- Ruby Whelp Shell
		[202612] = true, -- Screaming Black Dragonscale
		[203729] = true, -- Ominous Chromatic Essence
	},
	main_freecast = false,
	use_cds = false,
	drw_remains = 0,
	pooling_for_aotd = false,
	pooling_for_gargoyle = false,
}

-- current pet information
local Pet = {
	active = false,
	alive = false,
	stuck = false,
	health = {
		current = 0,
		max = 100,
		pct = 100,
	},
	energy = {
		current = 0,
		max = 100,
	},
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

function AutoAoe:Add(guid, update)
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

function AutoAoe:Remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:Update()
	end
end

function AutoAoe:Clear()
	for _, ability in next, Abilities.autoAoe do
		ability.auto_aoe.start_time = nil
		for guid in next, ability.auto_aoe.targets do
			ability.auto_aoe.targets[guid] = nil
		end
	end
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
	self:Update()
end

function AutoAoe:Update()
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

function AutoAoe:Purge()
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
		last_gained = 0,
		last_used = 0,
		aura_target = buff and 'player' or 'target',
		aura_filter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or ''),
	}
	setmetatable(ability, self)
	Abilities.all[#Abilities.all + 1] = ability
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
	if self.requires_pet and not Pet.active then
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
			return max(0, expires - Player.ctime - (self.off_gcd and 0 or Player.execute_remains))
		end
	end
	return 0
end

function Ability:Expiring(seconds)
	local remains = self:Remains()
	return remains > 0 and remains < (seconds or Player.gcd)
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
			if Player.time - cast.start < self.max_range / self.velocity + (self.travel_delay or 0) then
				count = count + 1
			end
		end
	end
	return count
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity + (self.travel_delay or 0)
end

function Ability:Ticking()
	local count, ticking = 0, {}
	if self.aura_targets then
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > (self.off_gcd and 0 or Player.execute_remains) then
				ticking[guid] = true
			end
		end
	end
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity + (self.travel_delay or 0) then
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
		return self:CooldownDuration()
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:CooldownExpected()
	if self.last_used == 0 then
		return self:Cooldown()
	end
	if self.cooldown_duration > 0 and self:Casting() then
		return self:CooldownDuration()
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	local remains = duration - (Player.ctime - start)
	local reduction = (Player.time - self.last_used) / (self:CooldownDuration() - remains)
	return max(0, (remains * reduction) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Stack()
	local _, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.aura_target, i, self.aura_filter)
		if not id then
			return 0
		elseif self:Match(id) then
			return (expires == 0 or expires - Player.ctime > (self.off_gcd and 0 or Player.execute_remains)) and count or 0
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
	return charges + ((max(0, Player.ctime - recharge_start + (self.off_gcd and 0 or Player.execute_remains))) / recharge_time)
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
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:Casting()
	return Player.cast.ability == self
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
	if Player.cast.ability then
		if i == 1 then
			return Player.cast.ability == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
end

function Ability:UsedWithin(seconds)
	return self.last_used >= (Player.time - seconds)
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
		self.auto_aoe.target_count = 0
		if self.auto_aoe.remove then
			for guid in next, AutoAoe.targets do
				AutoAoe.targets[guid] = nil
			end
		end
		for guid in next, self.auto_aoe.targets do
			AutoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
			self.auto_aoe.target_count = self.auto_aoe.target_count + 1
		end
		AutoAoe:Update()
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
		Pet.stuck = true
	end
end

function Ability:CastSuccess(dstGUID)
	self.last_used = Player.time
	if self.requires_pet then
		Pet.stuck = false
	end
	if self.pet_spell and not self.player_triggered then
		return
	end
	Player.last_ability = self
	if self.triggers_gcd then
		Player.previous_gcd[10] = nil
		table.insert(Player.previous_gcd, 1, self)
	end
	if self.aura_targets and self.requires_react then
		self:RemoveAura(self.aura_target == 'player' and Player.guid or dstGUID)
	end
	if Opt.auto_aoe and self.auto_aoe and self.auto_aoe.trigger == 'SPELL_CAST_SUCCESS' then
		AutoAoe:Add(dstGUID, true)
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
			if Player.time - cast.start >= self.max_range / self.velocity + (self.travel_delay or 0) + 0.2 then
				self.traveling[guid] = nil -- spell traveled 0.2s past max range, delete it, this should never happen
			elseif cast.dstGUID == dstGUID and (not oldest or cast.start < oldest.start) then
				oldest = cast
			end
		end
		if oldest then
			Target.estimated_range = floor(clamp(self.velocity * max(0, Player.time - oldest.start - (self.travel_delay or 0)), 0, self.max_range))
			self.traveling[oldest.guid] = nil
		end
	end
	if self.range_est_start then
		Target.estimated_range = floor(clamp(self.velocity * (Player.time - self.range_est_start - (self.travel_delay or 0)), 5, self.max_range))
		self.range_est_start = nil
	elseif self.max_range < Target.estimated_range then
		Target.estimated_range = self.max_range
	end
	if Opt.auto_aoe and self.auto_aoe then
		if event == 'SPELL_MISSED' and (missType == 'EVADE' or (missType == 'IMMUNE' and not self.ignore_immune)) then
			AutoAoe:Remove(dstGUID)
		elseif event == self.auto_aoe.trigger or (self.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and event == 'SPELL_AURA_REFRESH') then
			self:RecordTargetHit(dstGUID)
		end
	end
	if Opt.previous and Opt.miss_effect and event == 'SPELL_MISSED' and braindeadPreviousPanel.ability == self then
		braindeadPreviousPanel.border:SetTexture(ADDON_PATH .. 'misseffect.blp')
	end
end

-- Start DoT tracking

local trackAuras = {}

function trackAuras:Purge()
	for _, ability in next, Abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
	for _, ability in next, Abilities.trackAuras do
		ability:RemoveAura(guid)
	end
end

function Ability:TrackAuras()
	self.aura_targets = {}
end

function Ability:ApplyAura(guid)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid] or {}
	aura.expires = Player.time + self:Duration()
	self.aura_targets[guid] = aura
	return aura
end

function Ability:RefreshAura(guid)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		return self:ApplyAura(guid)
	end
	local duration = self:Duration()
	aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + duration))
	return aura
end

function Ability:RefreshAuraAll()
	local duration = self:Duration()
	for guid, aura in next, self.aura_targets do
		aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + duration))
	end
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- End DoT tracking

--[[
Note: To get talent_node value for a talent, hover over talent and use macro:
/dump GetMouseFocus():GetNodeID()
]]

-- Death Knight Abilities
---- Baseline
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
local DeathCoil = Ability:Add(47541, false, true, 47632)
DeathCoil.runic_power_cost = 40
DeathCoil:SetVelocity(35)
local DeathGrip = Ability:Add(49576, false, true)
DeathGrip.cooldown_duration = 25
DeathGrip.requires_charge = true
local DeathsAdvance = Ability:Add(48265, true, true)
DeathsAdvance.buff_duration = 8
DeathsAdvance.cooldown_duration = 45
DeathsAdvance.triggers_gcd = false
local Lichborne = Ability:Add(49039, true, true)
Lichborne.buff_duration = 10
Lichborne.cooldown_duration = 120
Lichborne.triggers_gcd = false
local RaiseAlly = Ability:Add(61999, false, true)
RaiseAlly.cooldown_duration = 600
RaiseAlly.runic_power_cost = 30
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
local AbominationLimb = Ability:Add(383269, true, true)
AbominationLimb.buff_duration = 12
AbominationLimb.cooldown_duration = 120
AbominationLimb.tick_interval = 1
local AntiMagicShell = Ability:Add(48707, true, true)
AntiMagicShell.buff_duration = 5
AntiMagicShell.cooldown_duration = 60
AntiMagicShell.triggers_gcd = false
local AntiMagicZone = Ability:Add(51052, true, true)
AntiMagicZone.buff_duration = 8
AntiMagicZone.cooldown_duration = 120
local Asphyxiate = Ability:Add(108194, false, true)
Asphyxiate.buff_duration = 4
Asphyxiate.cooldown_duration = 45
local BlindingSleet = Ability:Add(207167, false)
BlindingSleet.buff_duration = 5
BlindingSleet.cooldown_duration = 60
local ChainsOfIce = Ability:Add(45524, false)
ChainsOfIce.buff_duration = 8
ChainsOfIce.rune_cost = 1
local CleavingStrikes = Ability:Add(316916, true, true)
local ControlUndead = Ability:Add(111673, true, true)
ControlUndead.buff_duration = 300
ControlUndead.rune_cost = 1
local DeathPact = Ability:Add(48743, false, true)
DeathPact.buff_duration = 15
DeathPact.cooldown_duration = 120
DeathPact.aura_target = 'player'
DeathPact.triggers_gcd = false
local DeathStrike = Ability:Add(49998, false, true)
DeathStrike.runic_power_cost = 45
local IceboundFortitude = Ability:Add(48792, true, true)
IceboundFortitude.buff_duration = 8
IceboundFortitude.cooldown_duration = 180
IceboundFortitude.triggers_gcd = false
local IcyTalons = Ability:Add(194878, true, true, 194879)
IcyTalons.buff_duration = 10
IcyTalons.talent_node = 76051
local ImprovedDeathStrike = Ability:Add(374277, true, true)
local MindFreeze = Ability:Add(47528, false, true)
MindFreeze.buff_duration = 3
MindFreeze.cooldown_duration = 15
MindFreeze.triggers_gcd = false
local RaiseDead = Ability:Add(46585, false, true)
RaiseDead.cooldown_duration = 120
local RunicAttenuation = Ability:Add(207104, true, true, 221322)
local SacrificialPact = Ability:Add(327574, false, true)
SacrificialPact.cooldown_duration = 120
SacrificialPact.runic_power_cost = 20
local SoulReaper = Ability:Add(343294, false, true)
SoulReaper.rune_cost = 1
SoulReaper.buff_duration = 5
SoulReaper.cooldown_duration = 6
local UnholyGround = Ability:Add(374265, true, true, 374271)
---- Blood
local BloodShield = Ability:Add(77513, true, true, 77535)
BloodShield.buff_duration = 10
------ Talents
local BloodBoil = Ability:Add(50842, false, true)
BloodBoil.cooldown_duration = 7.5
BloodBoil.requires_charge = true
BloodBoil:AutoAoe(true)
local Blooddrinker = Ability:Add(206931, false, true)
Blooddrinker.buff_duration = 3
Blooddrinker.cooldown_duration = 30
Blooddrinker.rune_cost = 1
Blooddrinker.tick_interval = 1
Blooddrinker.hasted_duration = true
Blooddrinker.hasted_ticks = true
local BloodPlague = Ability:Add(55078, false, true)
BloodPlague.buff_duration = 24
BloodPlague.tick_interval = 3
BloodPlague:TrackAuras()
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
local Coagulopathy = Ability:Add(391477, true, true, 391481)
Coagulopathy.buff_duration = 8
local Consumption = Ability:Add(274156, false, true, 274893)
Consumption.cooldown_duration = 30
Consumption:AutoAoe()
local DancingRuneWeapon = Ability:Add(49028, true, true, 81256)
DancingRuneWeapon.buff_duration = 8
DancingRuneWeapon.cooldown_duration = 120
local DeathsCaress = Ability:Add(195292, false, true)
DeathsCaress.rune_cost = 1
DeathsCaress:SetVelocity(45)
local GorefiendsGrasp = Ability:Add(108199, false, true)
GorefiendsGrasp.cooldown_duration = 120
local Heartbreaker = Ability:Add(210738, false, true)
local HeartStrike = Ability:Add(206930, false, true)
HeartStrike.buff_duration = 8
HeartStrike.rune_cost = 1
local Hemostasis = Ability:Add(273946, true, true, 273947)
Hemostasis.buff_duration = 15
local InsatiableBlade = Ability:Add(377637, true, true)
local Marrowrend = Ability:Add(195182, false, true)
Marrowrend.rune_cost = 2
local Ossuary = Ability:Add(219786, true, true, 219788)
local RapidDecomposition = Ability:Add(194662, false, true)
local RelishInBlood = Ability:Add(317610, true, true)
local SanguineGround = Ability:Add(391458, true, true, 391459)
local ShatteringBone = Ability:Add(377640, false, true, 377642)
ShatteringBone.talent_node = 76128
ShatteringBone:AutoAoe()
local Tombstone = Ability:Add(219809, true, true)
Tombstone.buff_duration = 8
Tombstone.cooldown_duration = 60
local VampiricBlood = Ability:Add(55233, true, true)
VampiricBlood.buff_duration = 10
VampiricBlood.cooldown_duration = 90
VampiricBlood.triggers_gcd = false
------ Procs
local BoneShield = Ability:Add(195181, true, true)
BoneShield.buff_duration = 30
local CrimsonScourge = Ability:Add(81136, true, true, 81141)
CrimsonScourge.buff_duration = 15
------ Tier Bonuses
local AshenDecay = Ability:Add(425721, true, true) -- T31 2pc
AshenDecay.buff_duration = 20
AshenDecay.debuff = Ability:Add(425719, false, true)
AshenDecay.debuff.buff_duration = 8
AshenDecay.debuff:TrackAuras()
---- Frost
------ Talents
local Avalanche = Ability:Add(207142, false, true, 207150)
local BitingCold = Ability:Add(377056, false, true)
local Bonegrinder = Ability:Add(377098, true, true, 377101)
Bonegrinder.buff_duration = 10
local BreathOfSindragosa = Ability:Add(152279, true, true)
BreathOfSindragosa.buff_duration = 120
BreathOfSindragosa.cooldown_duration = 120
BreathOfSindragosa.damage = Ability:Add(155166, false, true)
BreathOfSindragosa.damage:AutoAoe()
local ChillStreak = Ability:Add(305392, false, true, 204206)
ChillStreak.buff_duration = 4
ChillStreak.cooldown_duration = 45
ChillStreak.rune_cost = 1
ChillStreak:AutoAoe(false, 'apply')
local ColdHeart = Ability:Add(281208, true, true, 281209)
local EmpowerRuneWeapon = Ability:Add(47568, true, true)
EmpowerRuneWeapon.buff_duration = 20
EmpowerRuneWeapon.cooldown_duration = 120
EmpowerRuneWeapon.triggers_gcd = false
local EnduringStrength = Ability:Add(377190, true, true, 377195)
EnduringStrength.buff_duration = 6
EnduringStrength.talent_node = 76100
local Everfrost = Ability:Add(376938, false, true, 376974)
Everfrost.buff_duration = 8
local FrostFever = Ability:Add(55095, false, true)
FrostFever.buff_duration = 24
FrostFever.tick_interval = 3
FrostFever:TrackAuras()
local Frostscythe = Ability:Add(207230, false, true)
Frostscythe.rune_cost = 1
Frostscythe:AutoAoe()
local FrostStrike = Ability:Add(49143, false, true)
FrostStrike.runic_power_cost = 30
local FrostwyrmsFury = Ability:Add(279302, false, true, 279303)
FrostwyrmsFury.buff_duration = 10
FrostwyrmsFury.cooldown_duration = 180
FrostwyrmsFury:AutoAoe()
local FrigidExecutioner = Ability:Add(377073, false, true)
local Frostreaper = Ability:Add(317214, false, true)
local GatheringStorm = Ability:Add(194912, true, true, 211805)
GatheringStorm.buff_duration = 8
local GlacialAdvance = Ability:Add(194913, false, true, 195975)
GlacialAdvance.runic_power_cost = 30
GlacialAdvance:AutoAoe(true)
local HornOfWinter = Ability:Add(57330, true, true)
HornOfWinter.cooldown_duration = 45
local HowlingBlast = Ability:Add(49184, false, true)
HowlingBlast.rune_cost = 1
HowlingBlast:AutoAoe(true)
local Icebreaker = Ability:Add(392950, false, true)
Icebreaker.talent_node = 76033
local Icecap = Ability:Add(207126, true, true)
local ImprovedObliterate = Ability:Add(317198, false, true)
local Obliterate = Ability:Add(49020, false, true)
Obliterate.rune_cost = 2
local Obliteration = Ability:Add(281238, true, true, 207256)
local PillarOfFrost = Ability:Add(51271, true, true)
PillarOfFrost.buff_duration = 12
PillarOfFrost.cooldown_duration = 60
PillarOfFrost.triggers_gcd = false
local RageOfTheFrozenChampion = Ability:Add(377076, false, true)
local RemorselessWinter = Ability:Add(196770, true, true)
RemorselessWinter.buff_duration = 8
RemorselessWinter.cooldown_duration = 20
RemorselessWinter.rune_cost = 1
RemorselessWinter.damage = Ability:Add(196771, false, true)
RemorselessWinter.damage:AutoAoe(true)
local ShatteringBlade = Ability:Add(207057, false, true)
local UnleashedFrenzy = Ability:Add(376905, true, true, 376907)
UnleashedFrenzy.buff_duration = 10
------ Procs
local DarkSuccor = Ability:Add(178819, true, true, 101568)
DarkSuccor.buff_duration = 20
local KillingMachine = Ability:Add(51128, true, true, 51124)
KillingMachine.buff_duration = 10
local Rime = Ability:Add(59057, true, true, 59052)
Rime.buff_duration = 15
------ Tier Bonuses
local ChillingRage = Ability:Add(424165, true, true)
ChillingRage.buff_duration = 12
---- Unholy
------ Talents
local Apocalypse = Ability:Add(275699, false, true)
Apocalypse.cooldown_duration = 90
local ArmyOfTheDead = Ability:Add(42650, true, true, 42651)
ArmyOfTheDead.buff_duration = 4
ArmyOfTheDead.cooldown_duration = 480
ArmyOfTheDead.rune_cost = 1
local BurstingSores = Ability:Add(207264, false, true, 207267)
BurstingSores:AutoAoe(true)
local ClawingShadows = Ability:Add(207311, false, true)
ClawingShadows.rune_cost = 1
local DarkTransformation = Ability:Add(63560, true, true)
DarkTransformation.buff_duration = 15
DarkTransformation.cooldown_duration = 60
DarkTransformation.requires_pet = true
DarkTransformation.aura_target = 'pet'
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
local FesteringStrike = Ability:Add(85948, false, true)
FesteringStrike.rune_cost = 2
local FesteringWound = Ability:Add(194310, false, true, 194311)
FesteringWound.buff_duration = 30
FesteringWound:AutoAoe(false, 'apply')
local Outbreak = Ability:Add(77575, false, true)
Outbreak.rune_cost = 1
local Pestilence = Ability:Add(277234, false, true)
local RaiseAbomination = Ability:Add(288853, true, true)
RaiseAbomination.buff_duration = 25
RaiseAbomination.cooldown_duration = 90
local RaiseDeadUnholy = Ability:Add(46584, false, true)
RaiseDeadUnholy.cooldown_duration = 30
local ScourgeStrike = Ability:Add(55090, false, true, 70890)
ScourgeStrike.rune_cost = 1
local SummonGargoyle = Ability:Add(49206, true, true)
SummonGargoyle.buff_duration = 25
SummonGargoyle.cooldown_duration = 180
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
local VirulentPlague = Ability:Add(191587, false, true)
VirulentPlague.buff_duration = 27
VirulentPlague.tick_interval = 3
VirulentPlague:AutoAoe(false, 'apply')
VirulentPlague:TrackAuras()
------ Procs
local RunicCorruption = Ability:Add(51462, true, true, 51460)
RunicCorruption.buff_duration = 3
local SuddenDoom = Ability:Add(49530, true, true, 81340)
SuddenDoom.buff_duration = 10
local VirulentEruption = Ability:Add(191685, false, true)
------ Tier Bonuses

-- PvP talents

-- Racials

-- Trinket effects
local MarkOfFyralath = Ability:Add(414532, false, true) -- DoT applied by Fyr'alath the Dreamrender
MarkOfFyralath.buff_duration = 15
MarkOfFyralath.tick_interval = 3
MarkOfFyralath.hasted_ticks = true
MarkOfFyralath.no_pandemic = true
MarkOfFyralath:TrackAuras()
-- End Abilities

-- Start Summoned Pets

function SummonedPets:Find(guid)
	local unitId = guid:match('^Creature%-0%-%d+%-%d+%-%d+%-(%d+)')
	return unitId and self.byUnitId[tonumber(unitId)]
end

function SummonedPets:Purge()
	for _, pet in next, self.known do
		for guid, unit in next, pet.active_units do
			if unit.expires <= Player.time then
				pet.active_units[guid] = nil
			end
		end
	end
end

function SummonedPets:Update()
	wipe(self.known)
	wipe(self.byUnitId)
	for _, pet in next, self.all do
		pet.known = pet.summon_spell and pet.summon_spell.known
		if pet.known then
			self.known[#SummonedPets.known + 1] = pet
			self.byUnitId[pet.unitId] = pet
		end
	end
end

function SummonedPets:Count()
	local count = 0
	for _, pet in next, self.known do
		count = count + pet:Count()
	end
	return count
end

function SummonedPets:Clear()
	for _, pet in next, self.known do
		pet:Clear()
	end
end

function SummonedPet:Add(unitId, duration, summonSpell)
	local pet = {
		unitId = unitId,
		duration = duration,
		active_units = {},
		summon_spell = summonSpell,
		known = false,
	}
	setmetatable(pet, self)
	SummonedPets.all[#SummonedPets.all + 1] = pet
	return pet
end

function SummonedPet:Remains(initial)
	local expires_max = 0
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
	local count = 0
	for guid, unit in next, self.active_units do
		if unit.expires - Player.time > Player.execute_remains then
			count = count + 1
		end
	end
	return count
end

function SummonedPet:Expiring(seconds)
	local count = 0
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
		spawn = Player.time,
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

function SummonedPet:ExtendAll(seconds)
	for guid, unit in next, self.active_units do
		if unit.expires > Player.time then
			unit.expires = unit.expires + seconds
		end
	end
end

function SummonedPet:Clear()
	for guid in next, self.active_units do
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
		off_gcd = true,
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
	local start, duration
	if self.equip_slot then
		start, duration = GetInventoryItemCooldown('player', self.equip_slot)
	else
		start, duration = GetItemCooldown(self.itemId)
	end
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - (self.off_gcd and 0 or Player.execute_remains))
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

-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
Trinket.AlgetharPuzzleBox = InventoryItem:Add(193701)
local FyralathTheDreamrender = InventoryItem:Add(206448)
FyralathTheDreamrender.cooldown_duration = 120
FyralathTheDreamrender.off_gcd = false
-- End Inventory Items

-- Start Abilities Functions

function Abilities:Update()
	wipe(self.bySpellId)
	wipe(self.velocity)
	wipe(self.autoAoe)
	wipe(self.trackAuras)
	for _, ability in next, self.all do
		if ability.known then
			self.bySpellId[ability.spellId] = ability
			if ability.spellId2 then
				self.bySpellId[ability.spellId2] = ability
			end
			if ability.velocity > 0 then
				self.velocity[#self.velocity + 1] = ability
			end
			if ability.auto_aoe then
				self.autoAoe[#self.autoAoe + 1] = ability
			end
			if ability.aura_targets then
				self.trackAuras[#self.trackAuras + 1] = ability
			end
		end
	end
end

-- End Abilities Functions

-- Start Player Functions

function Player:RuneTimeTo(runes)
	return max(self.runes.remains[runes] - self.execute_remains, 0)
end

function Player:ResetSwing(mainHand, offHand, missed)
	local mh, oh = UnitAttackSpeed('player')
	if mainHand then
		self.swing.mh.speed = (mh or 0)
		self.swing.mh.last = self.time
	end
	if offHand then
		self.swing.oh.speed = (oh or 0)
		self.swing.oh.last = self.time
	end
end

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	if self.cast.ability and self.cast.ability.triggers_combat then
		return 0.1
	end
	return 0
end

function Player:UnderMeleeAttack()
	return (self.time - self.swing.last_taken) < 3
end

function Player:UnderAttack()
	return self.threat.status >= 3 or self:UnderMeleeAttack()
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
			id == 381301 or -- Feral Hide Drums (Leatherworking)
			id == 390386    -- Fury of the Aspects (Evoker)
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

function Player:UpdateKnown()
	self.runes.max = UnitPowerMax('player', 5)
	self.runic_power.max = UnitPowerMax('player', 6)

	local node
	local configId = C_ClassTalents.GetActiveConfigID()
	for _, ability in next, Abilities.all do
		ability.known = false
		ability.rank = 0
		for _, spellId in next, ability.spellIds do
			ability.spellId, ability.name, _, ability.icon = spellId, GetSpellInfo(spellId)
			if IsPlayerSpell(spellId) or (ability.learn_spellId and IsPlayerSpell(ability.learn_spellId)) then
				ability.known = true
				break
			end
		end
		if ability.bonus_id then -- used for checking enchants and crafted effects
			ability.known = self:BonusIdEquipped(ability.bonus_id)
		end
		if ability.talent_node and configId then
			node = C_Traits.GetNodeInfo(configId, ability.talent_node)
			if node then
				ability.rank = node.activeRank
				ability.known = ability.rank > 0
			end
		end
		if C_LevelLink.IsSpellLocked(ability.spellId) or (ability.check_usable and not IsUsableSpell(ability.spellId)) then
			ability.known = false -- spell is locked, do not mark as known
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
	if Defile.known then
		DeathAndDecay.known = false
	end
	if ClawingShadows.known then
		ScourgeStrike.known = false
	end
	if RaiseAbomination.known then
		ArmyOfTheDead.known = false
	end
	DeathAndDecay.buff.known = DeathAndDecay.known
	DeathAndDecay.damage.known = DeathAndDecay.known
	Hysteria.known = RuneOfHysteria.known
	Razorice.known = RuneOfRazorice.known or GlacialAdvance.known or Avalanche.known
	UnholyStrength.known = RuneOfTheFallenCrusader.known
	if self.spec == SPEC.BLOOD then
		AshenDecay.known = self.set_bonus.t31 >= 2
		AshenDecay.debuff.known = AshenDecay.known
	elseif self.spec == SPEC.FROST then
		ChillingRage.known = self.set_bonus.t31 >= 2
	end
	MarkOfFyralath.known = FyralathTheDreamrender:Equipped()

	if DancingRuneWeapon.known then
		braindeadPanel.text.center:SetFont('Fonts\\FRIZQT__.TTF', 14, 'OUTLINE')
	else
		braindeadPanel.text.center:SetFont('Fonts\\FRIZQT__.TTF', 9, 'OUTLINE')
	end

	Abilities:Update()
	SummonedPets:Update()

	if APL[self.spec].precombat_variables then
		APL[self.spec]:precombat_variables()
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
		if threat_table and threat_table[1] and threat_table[2] and threat_table[1][1] == self.name then
			self.threat.lead = max(0, threat_table[1][6] - threat_table[2][6])
		end
	end
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
	self.runes.deficit = self.runes.max - self.runes.ready
end

function Player:Update()
	local _, start, ends, duration, spellId, speed_mh, speed_oh
	self.main =  nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	self:UpdateTime()
	self.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	self.gcd = 1.5 * self.haste_factor
	start, duration = GetSpellCooldown(61304)
	self.gcd_remains = start > 0 and duration - (self.ctime - start) or 0
	_, _, _, start, ends, _, _, _, spellId = UnitCastingInfo('player')
	if spellId then
		self.cast.ability = Abilities.bySpellId[spellId]
		self.cast.start = start / 1000
		self.cast.ends = ends / 1000
		self.cast.remains = self.cast.ends - self.ctime
	else
		self.cast.ability = nil
		self.cast.start = 0
		self.cast.ends = 0
		self.cast.remains = 0
	end
	self.execute_remains = max(self.cast.remains, self.gcd_remains)
	speed_mh, speed_oh = UnitAttackSpeed('player')
	self.swing.mh.speed = speed_mh or 0
	self.swing.oh.speed = speed_oh or 0
	self.swing.mh.remains = max(0, self.swing.mh.last + self.swing.mh.speed - self.time)
	self.swing.oh.remains = max(0, self.swing.oh.last + self.swing.oh.speed - self.time)
	self.moving = GetUnitSpeed('player') ~= 0
	self:UpdateRunes()
	self:UpdateThreat()

	Pet:Update()

	SummonedPets:Purge()
	trackAuras:Purge()
	if Opt.auto_aoe then
		for _, ability in next, Abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		AutoAoe:Purge()
	end

	self.main = APL[self.spec]:Main()
end

function Player:Init()
	local _
	if #UI.glows == 0 then
		UI:DisableOverlayGlows()
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
	end
	braindeadPreviousPanel.ability = nil
	self.guid = UnitGUID('player')
	self.name = UnitName('player')
	self.level = UnitLevel('player')
	_, self.instance = IsInInstance()
	Events:GROUP_ROSTER_UPDATE()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

-- End Player Functions

-- Start Pet Functions

function Pet:Update()
	self.guid = UnitGUID('pet')
	self.alive = self.guid and not UnitIsDead('pet')
	self.active = (self.alive and not self.stuck or IsFlying()) and true
	self.energy.max = self.active and UnitPowerMax('pet', 3) or 100
	self.energy.current = UnitPower('pet', 3)
end

-- End Pet Functions

-- Start Target Functions

function Target:UpdateHealth(reset)
	Timer.health = 0
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
	if UI:ShouldHide() then
		return UI:Disappear()
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
		return UI:Disappear()
	end
	if guid ~= self.guid then
		self.guid = guid
		self:UpdateHealth(true)
	end
	self.boss = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	self.level = UnitLevel('target')
	if self.level == -1 then
		self.level = Player.level + 3
	end
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		self.boss = self.level >= (Player.level + 3)
		self.stunnable = self.level < (Player.level + 2)
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		braindeadPanel:Show()
		return true
	end
	UI:Disappear()
end

function Target:TimeToPct(pct)
	if self.health.pct <= pct then
		return 0
	end
	if self.health.loss_per_sec <= 0 then
		return self.timeToDieMax
	end
	return min(self.timeToDieMax, (self.health.current - (self.health.max * (pct / 100))) / self.health.loss_per_sec)
end

function Target:Stunned()
	if Asphyxiate:Up() then
		return true
	end
	return false
end

-- End Target Functions

-- Start Ability Modifications

function ArmyOfTheDead:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	Pet.ArmyOfTheDead.summoned_by = self
	Pet.MagusOfTheDead.summoned_by = self
end
Apocalypse.CastSuccess = ArmyOfTheDead.CastSuccess

function BloodPlague:Remains()
	if DeathsCaress:Traveling() > 0 then
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
	if ImprovedDeathStrike.known then
		cost = cost - 5
	end
	if Ossuary.known and Ossuary:Up() then
		cost = cost - 5
	end
	return cost
end

function HeartStrike:Targets()
	return min(Player.enemies, (CleavingStrikes.known and DeathAndDecay.buff:Up()) and 5 or 2)
end

function Obliterate:Targets()
	return min(Player.enemies, (CleavingStrikes.known and DeathAndDecay.buff:Up()) and 3 or 1)
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

function FesteringWound:CastLanded(dstGUID, event, ...)
	if Opt.auto_aoe and BurstingSores.known and (event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED') then
		BurstingSores:RecordTargetHit(dstGUID)
	end
	Ability.CastLanded(self, dstGUID, event, ...)
end

function Asphyxiate:Usable()
	if not Target.stunnable then
		return false
	end
	return Ability.Usable(self)
end
BlindingSleet.Usable = Asphyxiate.Usable

function RaiseDead:Usable()
	if Pet.alive then
		return false
	end
	return Ability.Usable(self)
end

function SacrificialPact:Usable()
	if RaiseDeadUnholy.known and not Pet.alive then
		return false
	end
	if RaiseDead.known and Pet.RisenGhoul:Down() then
		return false
	end
	return Ability.Usable(self)
end

function MarkOfFyralath:Refresh(guid)
	if self.known and self.aura_targets[guid] then
		self.aura_targets[guid].expires = Player.time + self.buff_duration
	end
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

APL[SPEC.NONE].Main = function(self)
end

APL[SPEC.BLOOD].Main = function(self)
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
actions.precombat+=/snapshot_stats
actions.precombat+=/variable,name=trinket_1_buffs,value=trinket.1.has_use_buff|(trinket.1.has_buff.strength|trinket.1.has_buff.mastery|trinket.1.has_buff.versatility|trinket.1.has_buff.haste|trinket.1.has_buff.crit)
actions.precombat+=/variable,name=trinket_2_buffs,value=trinket.2.has_use_buff|(trinket.2.has_buff.strength|trinket.2.has_buff.mastery|trinket.2.has_buff.versatility|trinket.2.has_buff.haste|trinket.2.has_buff.crit)
actions.precombat+=/variable,name=trinket_1_exclude,value=trinket.1.is.ruby_whelp_shell|trinket.1.is.whispering_incarnate_icon
actions.precombat+=/variable,name=trinket_2_exclude,value=trinket.2.is.ruby_whelp_shell|trinket.2.is.whispering_incarnate_icon
actions.precombat+=/variable,name=damage_trinket_priority,op=setif,value=2,value_else=1,condition=trinket.2.ilvl>trinket.1.ilvl
]]
		if DeathAndDecay:Usable() then
			UseCooldown(DeathAndDecay)
		end
	else

	end
--[[
actions=auto_attack
actions+=/variable,name=death_strike_dump_amount,value=65
actions+=/variable,name=bone_shield_refresh_value,value=4,op=setif,condition=!talent.deaths_caress.enabled|talent.consumption.enabled|talent.blooddrinker.enabled,value_else=5
actions+=/mind_freeze,if=target.debuff.casting.react
# Use <a href='https://www.wowhead.com/spell=10060/power-infusion'>Power Infusion</a> while <a href='https://www.wowhead.com/spell=49028/dancing-rune-weapon'>Dancing Rune Weapon</a> is up, or on cooldown if <a href='https://www.wowhead.com/spell=49028/dancing-rune-weapon'>Dancing Rune Weapon</a> is not talented
actions+=/invoke_external_buff,name=power_infusion,if=buff.dancing_rune_weapon.up|!talent.dancing_rune_weapon
actions+=/potion,if=buff.dancing_rune_weapon.up
actions+=/call_action_list,name=trinkets
actions+=/raise_dead
actions+=/icebound_fortitude,if=!(buff.dancing_rune_weapon.up|buff.vampiric_blood.up)&(target.cooldown.pause_action.remains>=8|target.cooldown.pause_action.duration>0)
actions+=/vampiric_blood,if=!buff.vampiric_blood.up&!buff.vampiric_strength.up
actions+=/vampiric_blood,if=!(buff.dancing_rune_weapon.up|buff.icebound_fortitude.up|buff.vampiric_blood.up|buff.vampiric_strength.up)&(target.cooldown.pause_action.remains>=13|target.cooldown.pause_action.duration>0)
actions+=/deaths_caress,if=!buff.bone_shield.up
actions+=/death_and_decay,if=!death_and_decay.ticking&(talent.unholy_ground|talent.sanguine_ground|spell_targets.death_and_decay>3|buff.crimson_scourge.up)
actions+=/death_strike,if=buff.coagulopathy.remains<=gcd|buff.icy_talons.remains<=gcd|runic_power>=variable.death_strike_dump_amount|runic_power.deficit<=variable.heart_strike_rp|target.time_to_die<10
actions+=/blooddrinker,if=!buff.dancing_rune_weapon.up
actions+=/call_action_list,name=racials
actions+=/sacrificial_pact,if=!buff.dancing_rune_weapon.up&(pet.ghoul.remains<2|target.time_to_die<gcd)
actions+=/blood_tap,if=(rune<=2&rune.time_to_4>gcd&charges_fractional>=1.8)|rune.time_to_3>gcd
actions+=/gorefiends_grasp,if=talent.tightening_grasp.enabled
actions+=/empower_rune_weapon,if=rune<6&runic_power.deficit>5
actions+=/abomination_limb
actions+=/dancing_rune_weapon,if=!buff.dancing_rune_weapon.up
actions+=/run_action_list,name=drw_up,if=buff.dancing_rune_weapon.up
actions+=/call_action_list,name=standard
]]
	Player.drw_remains = DancingRuneWeapon:Remains()
	Player.use_cds = Target.boss or Target.player or Target.timeToDie > (Opt.cd_ttd - min(Player.enemies - 1, 6)) or Player.drw_remains > 0
	self.heart_strike_rp = (15 + (Player.drw_remains > 0 and 10 or 0) + (Heartbreaker.known and HeartStrike:Targets() * 2 or 0))
	self.death_strike_dump_amount = (BloodShield:Up() and Player.health.pct > 70) and 90 or 65
	self.bone_shield_refresh_value = (not DeathsCaress.known or Consumption.known or Blooddrinker.known) and 4 or 5

	if Player.use_cds then
		if Opt.trinket then
			self:trinkets()
		end
		if RaiseDead:Usable() then
			UseExtra(RaiseDead)
		elseif Player:UnderAttack() and Player.drw_remains == 0 and IceboundFortitude:Down() and VampiricBlood:Down() and not DancingRuneWeapon:Ready(InsatiableBlade.known and 10 or 0) then
			if IceboundFortitude:Usable() then
				UseExtra(IceboundFortitude)
			elseif VampiricBlood:Usable() then
				UseExtra(VampiricBlood)
			end
		end
	end
	if DeathStrike:Usable() and Player.health.pct < 50 then
		return DeathStrike
	end
	if Marrowrend:Usable() and BoneShield:Down() and Player:UnderAttack() then
		return Marrowrend
	end
	if DeathsCaress:Usable() and BoneShield:Down() then
		return DeathsCaress
	end
	if DeathAndDecay:Usable() and DeathAndDecay.buff:Down() and (SanguineGround.known or UnholyGround.known or Player.enemies > 3 or CrimsonScourge:Up()) then
		return DeathAndDecay
	end
	if DeathStrike:Usable() and (
		(Coagulopathy.known and Coagulopathy:Remains() <= Player.gcd) or
		(IcyTalons.known and IcyTalons:Remains() <= Player.gcd) or
		(Player.runic_power.current >= self.death_strike_dump_amount) or
		(Player.runic_power.deficit <= self.heart_strike_rp)
	) then
		return DeathStrike
	end
	if Player.use_cds then
		if Blooddrinker:Usable() and Player.drw_remains == 0 then
			UseCooldown(Blooddrinker)
		end
		if SacrificialPact:Usable() and Player.drw_remains == 0 and (Pet.RisenGhoul:Remains() < 2 or Target.timeToDie < Player.gcd) then
			UseExtra(SacrificialPact)
		end
		if BloodTap:Usable() and (Player:RuneTimeTo(3) > Player.gcd or (Player.runes.ready <= 2 and Player:RuneTimeTo(4) > Player.gcd and BloodTap:ChargesFractional() >= 1.8)) then
			UseCooldown(BloodTap)
		end
		if AbominationLimb:Usable() then
			UseCooldown(AbominationLimb)
		end
		if DancingRuneWeapon:Usable() and Player.drw_remains == 0 then
			UseCooldown(DancingRuneWeapon)
		end
		if EmpowerRuneWeapon:Usable() and Player.runes.ready < 6 and Player.runic_power.deficit > 5 then
			UseCooldown(EmpowerRuneWeapon)
		end
	end
	if Player.drw_remains > 0 then
		return self:drw_up()
	end
	return self:standard()
end

APL[SPEC.BLOOD].drw_up = function(self)
--[[
actions.drw_up=blood_boil,if=!dot.blood_plague.ticking
actions.drw_up+=/tombstone,if=buff.bone_shield.stack>5&rune>=2&runic_power.deficit>=30&!talent.shattering_bone|(talent.shattering_bone.enabled&death_and_decay.ticking)
actions.drw_up+=/death_strike,if=buff.coagulopathy.remains<=gcd|buff.icy_talons.remains<=gcd
actions.drw_up+=/marrowrend,if=(buff.bone_shield.remains<=4|buff.bone_shield.stack<variable.bone_shield_refresh_value)&runic_power.deficit>20
actions.drw_up+=/soul_reaper,if=active_enemies=1&target.time_to_pct_35<5&target.time_to_die>(dot.soul_reaper.remains+5)
actions.drw_up+=/soul_reaper,target_if=min:dot.soul_reaper.remains,if=target.time_to_pct_35<5&active_enemies>=2&target.time_to_die>(dot.soul_reaper.remains+5)
actions.drw_up+=/death_and_decay,if=!death_and_decay.ticking&(talent.sanguine_ground|talent.unholy_ground)
actions.drw_up+=/blood_boil,if=spell_targets.blood_boil>2&charges_fractional>=1.1
actions.drw_up+=/variable,name=heart_strike_rp_drw,value=(25+spell_targets.heart_strike*talent.heartbreaker.enabled*2)
actions.drw_up+=/death_strike,if=runic_power.deficit<=variable.heart_strike_rp_drw|runic_power>=variable.death_strike_dump_amount
actions.drw_up+=/consumption
actions.drw_up+=/blood_boil,if=charges_fractional>=1.1&buff.hemostasis.stack<5
actions.drw_up+=/heart_strike,if=rune.time_to_2<gcd|runic_power.deficit>=variable.heart_strike_rp_drw
]]
	if AshenDecay.known and HeartStrike:Usable() and Player.runic_power.deficit >= self.heart_strike_rp and AshenDecay:Up() and AshenDecay.debuff:Down() and min(5, Player.enemies) <= HeartStrike:Targets() then
		return HeartStrike
	end
	if BloodBoil:Usable() and BloodPlague:Down() then
		return BloodBoil
	end
	if Player.use_cds and Tombstone:Usable() and BoneShield:Stack() > 5 and (
		(ShatteringBone.known and DeathAndDecay.buff:Up() and (not AshenDecay.known or AshenDecay.debuff:Up() or AshenDecay:Down())) or
		(not ShatteringBone.known and Player.runes.ready >= 2 and Player.runic_power.deficit >= 30)
	) then
		UseCooldown(Tombstone)
	end
	if DeathStrike:Usable() and ((Coagulopathy.known and Coagulopathy:Remains() <= Player.gcd) or (IcyTalons.known and IcyTalons:Remains() <= Player.gcd)) then
		return DeathStrike
	end
	if Marrowrend:Usable() and (BoneShield:Remains() <= 4 or (BoneShield:Stack() < self.bone_shield_refresh_value and Player.runic_power.deficit > 20)) then
		return Marrowrend
	end
	if SoulReaper:Usable() and Target:TimeToPct(35) < 5 and Target.timeToDie > (SoulReaper:Remains() + 5) then
		UseCooldown(SoulReaper)
	end
	if DeathAndDecay:Usable() and DeathAndDecay.buff:Down() and (SanguineBlood.known or UnholyGround.known) then
		return DeathAndDecay
	end
	if BloodBoil:Usable() and Player.enemies > 2 and BloodBoil:ChargesFractional() >= 1.1 then
		return BloodBoil
	end
	if DeathStrike:Usable() and ((Player.runic_power.deficit <= self.heart_strike_rp) or (Player.runic_power.current >= self.death_strike_dump_amount)) then
		return DeathStrike
	end
	if Player.use_cds and Consumption:Usable() then
		UseCooldown(Consumption)
	end
	if Hemostasis.known and BloodBoil:Usable() and BloodBoil:ChargesFractional() >= 1.1 and Hemostasis:Stack() < 5 then
		return BloodBoil
	end
	if HeartStrike:Usable() and (Player:RuneTimeTo(2) < Player.gcd or Player.runic_power.deficit >= self.heart_strike_rp) then
		return HeartStrike
	end
end

APL[SPEC.BLOOD].standard = function(self)
--[[
actions.standard=tombstone,if=buff.bone_shield.stack>5&rune>=2&runic_power.deficit>=30&!talent.shattering_bone|(talent.shattering_bone.enabled&death_and_decay.ticking)&cooldown.dancing_rune_weapon.remains>=25
actions.standard+=/variable,name=heart_strike_rp,value=(10+spell_targets.heart_strike*talent.heartbreaker.enabled*2)
actions.standard+=/death_strike,if=buff.coagulopathy.remains<=gcd|buff.icy_talons.remains<=gcd|runic_power>=variable.death_strike_dump_amount|runic_power.deficit<=variable.heart_strike_rp|target.time_to_die<10
actions.standard+=/deaths_caress,if=(buff.bone_shield.remains<=4|(buff.bone_shield.stack<variable.bone_shield_refresh_value+1))&runic_power.deficit>10&!(talent.insatiable_blade&cooldown.dancing_rune_weapon.remains<buff.bone_shield.remains)&!talent.consumption.enabled&!talent.blooddrinker.enabled&rune.time_to_3>gcd
actions.standard+=/marrowrend,if=(buff.bone_shield.remains<=4|buff.bone_shield.stack<variable.bone_shield_refresh_value)&runic_power.deficit>20&!(talent.insatiable_blade&cooldown.dancing_rune_weapon.remains<buff.bone_shield.remains)
actions.standard+=/consumption
actions.standard+=/soul_reaper,if=active_enemies=1&target.time_to_pct_35<5&target.time_to_die>(dot.soul_reaper.remains+5)
actions.standard+=/soul_reaper,target_if=min:dot.soul_reaper.remains,if=target.time_to_pct_35<5&active_enemies>=2&target.time_to_die>(dot.soul_reaper.remains+5)
actions.standard+=/bonestorm,if=runic_power>=100
actions.standard+=/blood_boil,if=charges_fractional>=1.8&(buff.hemostasis.stack<=(5-spell_targets.blood_boil)|spell_targets.blood_boil>2)
actions.standard+=/heart_strike,if=rune.time_to_4<gcd
actions.standard+=/blood_boil,if=charges_fractional>=1.1
actions.standard+=/heart_strike,if=(rune>1&(rune.time_to_3<gcd|buff.bone_shield.stack>7))
]]
	if Player.use_cds and Tombstone:Usable() and BoneShield:Stack() > 5 and (
		(ShatteringBone.known and DeathAndDecay.buff:Up() and not DancingRuneWeapon:Ready(25) and (not AshenDecay.known or AshenDecay.debuff:Up() or AshenDecay:Down())) or
		(not ShatteringBone.known and Player.runes.ready >= 2 and Player.runic_power.deficit >= 30)
	) then
		UseCooldown(Tombstone)
	end
	if DeathStrike:Usable() and ((Coagulopathy.known and Coagulopathy:Remains() <= Player.gcd) or (IcyTalons.known and IcyTalons:Remains() <= Player.gcd) or (Player.runic_power.current >= self.death_strike_dump_amount) or (Player.runic_power.deficit <= self.heart_strike_rp)) then
		return DeathStrike
	end
	if DeathsCaress:Usable() and (BoneShield:Remains() <= 5 or (BoneShield:Stack() < (self.bone_shield_refresh_value + 1) and Player.runic_power.deficit > 10)) and not (Player.use_cds and InsatiableBlade.known and DancingRuneWeapon:Ready(BoneShield:Remains() - 2)) and not Consumption.known and not Blooddrinker.known and Player:RuneTimeTo(3) > Player.gcd then
		return DeathsCaress
	end
	if Marrowrend:Usable() and (BoneShield:Remains() <= 5 or (BoneShield:Stack() < self.bone_shield_refresh_value and Player.runic_power.deficit > 20)) and not (Player.use_cds and InsatiableBlade.known and DancingRuneWeapon:Ready(BoneShield:Remains() - 2)) then
		return Marrowrend
	end
	if AshenDecay.known and HeartStrike:Usable() and Player.runic_power.deficit >= self.heart_strike_rp and AshenDecay:Up() and AshenDecay.debuff:Down() and min(5, Player.enemies) <= HeartStrike:Targets() then
		return HeartStrike
	end
	if Player.use_cds and Consumption:Usable() then
		UseCooldown(Consumption)
	end
	if SoulReaper:Usable() and Target:TimeToPct(35) < 5 and Target.timeToDie > (SoulReaper:Remains() + 5) then
		UseCooldown(SoulReaper)
	end
	if Player.use_cds and Bonestorm:Usable() and Player.runic_power.current >= 100 then
		UseCooldown(Bonestorm)
	end
	if BloodBoil:Usable() and BloodBoil:ChargesFractional() >= 1.8 and (Player.enemies > 2 or Hemostasis:Stack() <= (5 - Player.enemies)) then
		return BloodBoil
	end
	if HeartStrike:Usable() and Player:RuneTimeTo(4) < Player.gcd then
		return HeartStrike
	end
	if BloodBoil:Usable() and BloodBoil:ChargesFractional() >= 1.1 then
		return BloodBoil
	end
	if HeartStrike:Usable() and Player.runes.ready > 1 and (Player:RuneTimeTo(3) < Player.gcd or BoneShield:Stack() > 7) then
		return HeartStrike
	end
end

APL[SPEC.BLOOD].trinkets = function(self)
--[[
actions.trinkets=use_item,name=fyralath_the_dreamrender,if=dot.mark_of_fyralath.ticking
# Prioritize damage dealing on use trinkets over trinkets that give buffs
actions.trinkets+=/use_item,use_off_gcd=1,slot=trinket1,if=!variable.trinket_1_buffs&(variable.damage_trinket_priority=1|trinket.2.cooldown.remains|!trinket.2.has_cooldown)
actions.trinkets+=/use_item,use_off_gcd=1,slot=trinket2,if=!variable.trinket_2_buffs&(variable.damage_trinket_priority=2|trinket.1.cooldown.remains|!trinket.1.has_cooldown)
actions.trinkets+=/use_item,use_off_gcd=1,slot=main_hand,if=!equipped.fyralath_the_dreamrender&(variable.trinket_1_buffs|trinket.1.cooldown.remains)&(variable.trinket_2_buffs|trinket.2.cooldown.remains)
actions.trinkets+=/use_item,use_off_gcd=1,slot=trinket1,if=variable.trinket_1_buffs&(buff.dancing_rune_weapon.up|!talent.dancing_rune_weapon|cooldown.dancing_rune_weapon.remains>20)&(variable.trinket_2_exclude|trinket.2.cooldown.remains|!trinket.2.has_cooldown|variable.trinket_2_buffs)
actions.trinkets+=/use_item,use_off_gcd=1,slot=trinket2,if=variable.trinket_2_buffs&(buff.dancing_rune_weapon.up|!talent.dancing_rune_weapon|cooldown.dancing_rune_weapon.remains>20)&(variable.trinket_1_exclude|trinket.1.cooldown.remains|!trinket.1.has_cooldown|variable.trinket_1_buffs)
]]
	if FyralathTheDreamrender:Usable() and MarkOfFyralath:Ticking() >= HeartStrike:Targets() and Player.drw_remains == 0 and (not AshenDecay.known or (AshenDecay.debuff:Remains() >= 4 and AshenDecay.debuff:Ticking() >= HeartStrike:Targets())) and (
		not Player:UnderAttack() or
		(Player.runic_power.current >= 35 and Player.health.pct >= 80 and BoneShield:Stack() >= self.bone_shield_refresh_value and BloodShield:Up())
	) then
		return UseCooldown(FyralathTheDreamrender)
	end
	if Trinket1:Usable() then
		return UseCooldown(Trinket1)
	end
	if Trinket2:Usable() then
		return UseCooldown(Trinket2)
	end
end


APL[SPEC.FROST].Main = function(self)
	Player.use_cds = Target.boss or Target.player or Target.timeToDie > (Opt.cd_ttd - min(Player.enemies - 1, 6)) or EmpowerRuneWeapon:Up() or PillarOfFrost:Up() or (BreathOfSindragosa.known and BreathOfSindragosa:Up()) or (CleavingStrikes.known and Player.enemies >= 2 and DeathAndDecay.buff:Up())

	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
# Snapshot raid buffed stats before combat begins and pre-potting is done.
actions.precombat+=/snapshot_stats
actions.precombat+=/variable,name=trinket_1_exclude,value=trinket.1.is.ruby_whelp_shell|trinket.1.is.whispering_incarnate_icon
actions.precombat+=/variable,name=trinket_2_exclude,value=trinket.2.is.ruby_whelp_shell|trinket.2.is.whispering_incarnate_icon
# Evaluates a trinkets cooldown, divided by pillar of frost, empower rune weapon, or breath of sindragosa's cooldown. If it's value has no remainder return 1, else return 0.5.
actions.precombat+=/variable,name=trinket_1_sync,op=setif,value=1,value_else=0.5,condition=trinket.1.has_use_buff&(talent.pillar_of_frost&!talent.breath_of_sindragosa&(trinket.1.cooldown.duration%%cooldown.pillar_of_frost.duration=0)|talent.breath_of_sindragosa&(cooldown.breath_of_sindragosa.duration%%trinket.1.cooldown.duration=0))
actions.precombat+=/variable,name=trinket_2_sync,op=setif,value=1,value_else=0.5,condition=trinket.2.has_use_buff&(talent.pillar_of_frost&!talent.breath_of_sindragosa&(trinket.2.cooldown.duration%%cooldown.pillar_of_frost.duration=0)|talent.breath_of_sindragosa&(cooldown.breath_of_sindragosa.duration%%trinket.2.cooldown.duration=0))
actions.precombat+=/variable,name=trinket_1_buffs,value=trinket.1.has_use_buff|(trinket.1.has_buff.strength|trinket.1.has_buff.mastery|trinket.1.has_buff.versatility|trinket.1.has_buff.haste|trinket.1.has_buff.crit&!variable.trinket_1_exclude)
actions.precombat+=/variable,name=trinket_2_buffs,value=trinket.2.has_use_buff|(trinket.2.has_buff.strength|trinket.2.has_buff.mastery|trinket.2.has_buff.versatility|trinket.2.has_buff.haste|trinket.2.has_buff.crit&!variable.trinket_2_exclude)
actions.precombat+=/variable,name=trinket_priority,op=setif,value=2,value_else=1,condition=!variable.trinket_1_buffs&variable.trinket_2_buffs|variable.trinket_2_buffs&((trinket.2.cooldown.duration%trinket.2.proc.any_dps.duration)*(1.5+trinket.2.has_buff.strength)*(variable.trinket_2_sync))>((trinket.1.cooldown.duration%trinket.1.proc.any_dps.duration)*(1.5+trinket.1.has_buff.strength)*(variable.trinket_1_sync))
actions.precombat+=/variable,name=trinket_1_manual,value=trinket.1.is.algethar_puzzle_box
actions.precombat+=/variable,name=trinket_2_manual,value=trinket.2.is.algethar_puzzle_box
actions.precombat+=/variable,name=rw_buffs,value=talent.gathering_storm|talent.everfrost
actions.precombat+=/variable,name=2h_check,value=main_hand.2h
]]
		if Opt.trinket and Player.use_cds and Trinket.AlgetharPuzzleBox:Usable() and PillarOfFrost:Ready(2) and EmpowerRuneWeapon:Ready(2) then
			UseCooldown(Trinket.AlgetharPuzzleBox)
		end
		if HowlingBlast:Usable() and FrostFever:Down() and (not Obliteration.known or PillarOfFrost:Down() or KillingMachine:Down()) then
			return HowlingBlast
		end
	else

	end
--[[
actions=auto_attack
# Prevent specified trinkets being used with automatic lines actions+=/variable,name=specified_trinket,value=
actions+=/variable,name=st_planning,value=active_enemies=1&(raid_event.adds.in>15|!raid_event.adds.exists)
actions+=/variable,name=adds_remain,value=active_enemies>=2&(!raid_event.adds.exists|raid_event.adds.exists&raid_event.adds.remains>5)
actions+=/variable,name=rime_buffs,value=buff.rime.react&(talent.rage_of_the_frozen_champion|talent.avalanche|talent.icebreaker)
actions+=/variable,name=rp_buffs,value=talent.unleashed_frenzy&(buff.unleashed_frenzy.remains<gcd.max*3|buff.unleashed_frenzy.stack<3)|talent.icy_talons&(buff.icy_talons.remains<gcd.max*3|buff.icy_talons.stack<3)
actions+=/variable,name=rw_wait,value=variable.rw_buffs&!cooldown.remorseless_winter.remains&buff.remorseless_winter.down
actions+=/variable,name=cooldown_check,value=talent.pillar_of_frost&buff.pillar_of_frost.up|!talent.pillar_of_frost&buff.empower_rune_weapon.up|!talent.pillar_of_frost&!talent.empower_rune_weapon
actions+=/variable,name=frostscythe_priority,value=talent.frostscythe&(buff.killing_machine.react|active_enemies>=3)&(!talent.improved_obliterate&!talent.frigid_executioner&!talent.frostreaper&!talent.might_of_the_frozen_wastes|!talent.cleaving_strikes|talent.cleaving_strikes&(active_enemies>6|!death_and_decay.ticking&active_enemies>3))
# Formulaic approach to determine the time before these abilities come off cooldown that the simulation should star to pool resources. Capped at 15s in the run_action_list call.
actions+=/variable,name=oblit_pooling_time,op=setif,value=((cooldown.pillar_of_frost.remains_expected+1)%gcd.max)%((rune+3)*(runic_power+5))*100,value_else=3,condition=runic_power<35&rune<2&cooldown.pillar_of_frost.remains_expected<10
actions+=/variable,name=breath_pooling_time,op=setif,value=((cooldown.breath_of_sindragosa.remains+1)%gcd.max)%((rune+1)*(runic_power+20))*100,value_else=3,condition=runic_power.deficit>10&cooldown.breath_of_sindragosa.remains<10
actions+=/variable,name=pooling_runes,value=rune<4&talent.obliteration&cooldown.pillar_of_frost.remains_expected<variable.oblit_pooling_time
actions+=/variable,name=pooling_runic_power,value=talent.breath_of_sindragosa&cooldown.breath_of_sindragosa.remains<variable.breath_pooling_time|talent.obliteration&runic_power<35&cooldown.pillar_of_frost.remains_expected<variable.oblit_pooling_time
actions+=/invoke_external_buff,name=power_infusion,if=(buff.pillar_of_frost.up|!talent.pillar_of_frost)&(talent.obliteration|talent.breath_of_sindragosa&buff.breath_of_sindragosa.up|!talent.breath_of_sindragosa&!talent.obliteration)
# Interrupt
actions+=/mind_freeze,if=target.debuff.casting.react
actions+=/antimagic_shell,if=runic_power.deficit>40
actions+=/antimagic_zone,if=death_knight.amz_absorb_percent>0&runic_power.deficit>70&talent.assimilation&(buff.breath_of_sindragosa.up&cooldown.empower_rune_weapon.charges<2|!talent.breath_of_sindragosa&!buff.pillar_of_frost.up)
# Maintain Frost Fever, Icy Talons and Unleashed Frenzy
actions+=/howling_blast,if=!dot.frost_fever.ticking&active_enemies>=2&(!talent.obliteration|talent.obliteration&(!buff.pillar_of_frost.up|buff.pillar_of_frost.up&!buff.killing_machine.react))
actions+=/glacial_advance,if=active_enemies>=2&variable.rp_buffs&talent.obliteration&talent.breath_of_sindragosa&!buff.pillar_of_frost.up&!buff.breath_of_sindragosa.up&cooldown.breath_of_sindragosa.remains>variable.breath_pooling_time
actions+=/glacial_advance,if=active_enemies>=2&variable.rp_buffs&talent.breath_of_sindragosa&!buff.breath_of_sindragosa.up&cooldown.breath_of_sindragosa.remains>variable.breath_pooling_time
actions+=/glacial_advance,if=active_enemies>=2&variable.rp_buffs&!talent.breath_of_sindragosa&talent.obliteration&!buff.pillar_of_frost.up
actions+=/frost_strike,if=active_enemies=1&variable.rp_buffs&talent.obliteration&talent.breath_of_sindragosa&!buff.pillar_of_frost.up&!buff.breath_of_sindragosa.up&cooldown.breath_of_sindragosa.remains>variable.breath_pooling_time
actions+=/frost_strike,if=active_enemies=1&variable.rp_buffs&talent.breath_of_sindragosa&!buff.breath_of_sindragosa.up&cooldown.breath_of_sindragosa.remains>variable.breath_pooling_time
actions+=/frost_strike,if=active_enemies=1&variable.rp_buffs&!talent.breath_of_sindragosa&talent.obliteration&!buff.pillar_of_frost.up
actions+=/remorseless_winter,if=!remains&!talent.breath_of_sindragosa&!talent.obliteration&variable.rw_buffs
actions+=/remorseless_winter,if=!remains&talent.obliteration&active_enemies>=3&variable.adds_remain
# Choose Action list to run
actions+=/call_action_list,name=trinkets
actions+=/call_action_list,name=cooldowns
actions+=/call_action_list,name=racials
actions+=/call_action_list,name=cold_heart,if=talent.cold_heart&(!buff.killing_machine.up|talent.breath_of_sindragosa)&((debuff.razorice.stack=5|!death_knight.runeforge.razorice&!talent.glacial_advance&!talent.avalanche)|fight_remains<=gcd)
actions+=/run_action_list,name=breath_oblit,if=buff.breath_of_sindragosa.up&talent.obliteration&buff.pillar_of_frost.up
actions+=/run_action_list,name=breath,if=buff.breath_of_sindragosa.up&(!talent.obliteration|talent.obliteration&!buff.pillar_of_frost.up)
actions+=/run_action_list,name=obliteration,if=talent.obliteration&buff.pillar_of_frost.up&!buff.breath_of_sindragosa.up
actions+=/call_action_list,name=aoe,if=active_enemies>=2
actions+=/call_action_list,name=single_target,if=active_enemies=1
]]
	self.st_planning = Player.enemies <= 1
	self.adds_remain = Player.enemies >= 2
	self.rime_buffs = Rime:Up() and (RageOfTheFrozenChampion.known or Avalanche.known or Icebreaker.known)
	self.rw_buffs = GatheringStorm.known or Everfrost.known
	self.rp_buffs = (UnleashedFrenzy.known and (UnleashedFrenzy:Stack() < 3 or UnleashedFrenzy:Remains() < (Player.gcd * 3))) or (IcyTalons.known and (IcyTalons:Stack() < 3 or IcyTalons:Remains() < (Player.gcd * 3)))
	self.rw_wait = self.rw_buffs and RemorselessWinter:Ready() and RemorselessWinter:Down()
	self.cooldown_check = (not PillarOfFrost.known and not EmpowerRuneWeapon.known) or (PillarOfFrost.known and PillarOfFrost:Up()) or (not PillarOfFrost.known and EmpowerRuneWeapon:Up())
	self.frostscythe_priority = Frostscythe.known and (KillingMachine:Up() or Player.enemies >= 3) and (not CleavingStrikes.known or (not ImprovedObliterate.known and not FrigidExecutioner.known and not Frostreaper.known and not MightOfTheFrozenWastes.known) or Player.enemies > 6 or (DeathAndDecay.buff:Down() and Player.enemies > 3))
	if PillarOfFrost.known and Player.runic_power.current < 35 and Player.runes.ready < 2 and PillarOfFrost:CooldownExpected() < 10 then
		self.oblit_pooling_time = ((PillarOfFrost:CooldownExpected() + 1) / Player.gcd) / ((Player.runes.ready + 3) * (Player.runic_power.current + 5)) * 100
	else
		self.oblit_pooling_time = 3
	end
	if BreathOfSindragosa.known and Player.runic_power.deficit > 10 and BreathOfSindragosa:Ready(10) then
		self.breath_pooling_time = ((BreathOfSindragosa:Cooldown() + 1) / Player.gcd) / ((Player.runes.ready + 1) * (Player.runic_power.current + 20)) * 100
	else
		self.breath_pooling_time = 3
	end
	self.pooling_runes = Player.use_cds and Obliteration.known and Player.runes.ready < 4 and PillarOfFrost:CooldownExpected() < self.oblit_pooling_time
	self.pooling_runic_power = Player.use_cds and ((BreathOfSindragosa.known and BreathOfSindragosa:Ready(self.breath_pooling_time)) or (Obliteration.known and Player.runic_power.current < 35 and PillarOfFrost:CooldownExpected() < self.oblit_pooling_time))

	if HowlingBlast:Usable() and Player.enemies >= 2 and FrostFever:Down() and (not Obliteration.known or PillarOfFrost:Down() or KillingMachine:Down()) then
		return HowlingBlast
	end
	if self.rp_buffs then
		if GlacialAdvance:Usable() and Player.enemies >= 2 and (
			(Obliteration.known and BreathOfSindragosa.known and PillarOfFrost:Down() and BreathOfSindragosa:Down() and not BreathOfSindragosa:Ready(self.breath_pooling_time)) or
			(BreathOfSindragosa.known and BreathOfSindragosa:Down() and not BreathOfSindragosa:Ready(self.breath_pooling_time)) or
			(not BreathOfSindragosa.known and Obliteration.known and PillarOfFrost:Down())
		) then
			return GlacialAdvance
		end
		if FrostStrike:Usable() and Player.enemies <= 1 and (
			(Obliteration.known and BreathOfSindragosa.known and PillarOfFrost:Down() and BreathOfSindragosa:Down() and not BreathOfSindragosa:Ready(self.breath_pooling_time)) or
			(BreathOfSindragosa.known and BreathOfSindragosa:Down() and not BreathOfSindragosa:Ready(self.breath_pooling_time)) or
			(not BreathOfSindragosa.known and Obliteration.known and PillarOfFrost:Down())
		) then
			return FrostStrike
		end
	end
	if RemorselessWinter:Usable() and RemorselessWinter:Down() and (
		(not BreathOfSindragosa.known and not Obliteration.known and self.rw_buffs) or
		(Obliteration.known and Player.enemies >= 3 and self.adds_remain)
	) then
		return RemorselessWinter
	end
	if Player.use_cds then
		if Opt.trinket then
			self:trinkets()
		end
		self:cooldowns()
	end
	if ColdHeart.known and (BreathOfSindragosa.known or KillingMachine:Down()) and (Razorice:Stack() >= 5 or (not RuneOfRazorice.known and not GlacialAdvance.known and not Avalanche.known) or (Target.boss and Target.timeToDie < Player.gcd)) then
		local apl = self:cold_heart()
		if apl then return apl end
	end
	if BreathOfSindragosa.known and BreathOfSindragosa:Up() then
		if Obliteration.known and PillarOfFrost:Up() then
			return self:breath_oblit()
		end
		return self:breath()
	end
	if Obliteration.known and PillarOfFrost:Up() then
		return self:obliteration()
	end
	if Player.enemies >= 2 then
		return self:aoe()
	end
	return self:single_target()
end

APL[SPEC.FROST].aoe = function(self)
--[[
actions.aoe=remorseless_winter,if=!remains
actions.aoe+=/obliterate,if=buff.killing_machine.react&!variable.frostscythe_priority&talent.cleaving_strikes&death_and_decay.ticking
actions.aoe+=/howling_blast,if=buff.rime.react|!dot.frost_fever.ticking
actions.aoe+=/glacial_advance,if=!variable.pooling_runic_power&variable.rp_buffs
actions.aoe+=/obliterate,if=buff.killing_machine.react&!variable.frostscythe_priority&(buff.killing_machine.stack=2|buff.killing_machine.remains<gcd|buff.bonegrinder_crit.up&(buff.bonegrinder_crit.remains<gcd|buff.bonegrinder_crit.stack>=5))
actions.aoe+=/frostscythe,if=buff.killing_machine.react&variable.frostscythe_priority&(buff.killing_machine.stack=2|buff.killing_machine.remains<gcd|buff.bonegrinder_crit.up&(buff.bonegrinder_crit.remains<gcd|buff.bonegrinder_crit.stack>=5))
actions.aoe+=/obliterate,if=!variable.frostscythe_priority&(talent.cleaving_strikes&death_and_decay.ticking|!variable.pooling_runes&buff.killing_machine.react|rune.time_to_4<gcd)
actions.aoe+=/glacial_advance,if=!variable.pooling_runic_power
actions.aoe+=/frostscythe,if=variable.frostscythe_priority
actions.aoe+=/obliterate,if=!variable.frostscythe_priority
actions.aoe+=/frost_strike,if=!variable.pooling_runic_power&!talent.glacial_advance
actions.aoe+=/horn_of_winter,if=rune<2&runic_power.deficit>25
actions.aoe+=/arcane_torrent,if=runic_power.deficit>25
]]
	if RemorselessWinter:Usable() and RemorselessWinter:Down() then
		return RemorselessWinter
	end
	if CleavingStrikes.known and not self.frostscythe_priority and Obliterate:Usable() and KillingMachine:Up() and DeathAndDecay.buff:Up() then
		return Obliterate
	end
	if HowlingBlast:Usable() and (Rime:Up() or FrostFever:Down()) then
		return HowlingBlast
	end
	if not self.pooling_runic_power and GlacialAdvance:Usable() and self.rp_buffs then
		return GlacialAdvance
	end
	if not self.frostscythe_priority and Obliterate:Usable() and KillingMachine:Up() and (KillingMachine:Stack() >= 2 or KillingMachine:Remains() < Player.gcd or (Bonegrinder:Up() and (Bonegrinder:Remains() < Player.gcd or Bonegrinder:Stack() >= 5))) then
		return Obliterate
	end
	if self.frostscythe_priority and Frostscythe:Usable() and KillingMachine:Up() and (KillingMachine:Stack() >= 2 or KillingMachine:Remains() < Player.gcd or (Bonegrinder:Up() and (Bonegrinder:Remains() < Player.gcd or Bonegrinder:Stack() >= 5))) then
		return Frostscythe
	end
	if DeathStrike:Usable() and Player.health.pct < (DarkSuccor:Up() and 80 or Opt.death_strike_threshold) then
		UseCooldown(DeathStrike)
	end
	if not self.frostscythe_priority and Obliterate:Usable() and (Player:RuneTimeTo(4) < Player.gcd or (not self.pooling_runes and KillingMachine:Up()) or (CleavingStrikes.known and DeathAndDecay.buff:Up())) then
		return Obliterate
	end
	if not self.pooling_runic_power and GlacialAdvance:Usable() then
		return GlacialAdvance
	end
	if self.frostscythe_priority and Frostscythe:Usable() then
		return Frostscythe
	end
	if not self.frostscythe_priority and Obliterate:Usable() then
		return Obliterate
	end
	if not self.pooling_runic_power and FrostStrike:Usable() and not GlacialAdvance.known then
		return FrostStrike
	end
	if DeathStrike:Usable() and DarkSuccor:Up() then
		UseCooldown(DeathStrike)
	end
	if HornOfWinter:Usable() and Player.runes.ready < 2 and Player.runic_power.deficit > 25 then
		return HornOfWinter
	end
end

APL[SPEC.FROST].breath = function(self)
--[[
actions.breath=remorseless_winter,if=!remains&(variable.rw_buffs|variable.adds_remain)
actions.breath+=/howling_blast,if=variable.rime_buffs&runic_power>(45-talent.rage_of_the_frozen_champion*8)
actions.breath+=/horn_of_winter,if=rune<2&runic_power.deficit>25
actions.breath+=/obliterate,target_if=max:(debuff.razorice.stack+1)%(debuff.razorice.remains+1)*death_knight.runeforge.razorice,if=buff.killing_machine.react&!variable.frostscythe_priority
actions.breath+=/frostscythe,if=buff.killing_machine.react&variable.frostscythe_priority
actions.breath+=/frostscythe,if=variable.frostscythe_priority&runic_power>45
actions.breath+=/obliterate,target_if=max:(debuff.razorice.stack+1)%(debuff.razorice.remains+1)*death_knight.runeforge.razorice,if=runic_power.deficit>40|buff.pillar_of_frost.up&runic_power.deficit>15
actions.breath+=/death_and_decay,if=runic_power<32&rune.time_to_2>runic_power%16
actions.breath+=/remorseless_winter,if=runic_power<32&rune.time_to_2>runic_power%16
actions.breath+=/howling_blast,if=runic_power<32&rune.time_to_2>runic_power%16
actions.breath+=/obliterate,target_if=max:(debuff.razorice.stack+1)%(debuff.razorice.remains+1)*death_knight.runeforge.razorice,if=runic_power.deficit>25
actions.breath+=/howling_blast,if=buff.rime.react
actions.breath+=/arcane_torrent,if=runic_power<60
]]

end

APL[SPEC.FROST].breath_oblit = function(self)
--[[
actions.breath_oblit=frostscythe,if=buff.killing_machine.up&variable.frostscythe_priority
actions.breath_oblit+=/obliterate,target_if=max:(debuff.razorice.stack+1)%(debuff.razorice.remains+1)*death_knight.runeforge.razorice,if=buff.killing_machine.up
actions.breath_oblit+=/howling_blast,if=buff.rime.react
actions.breath_oblit+=/howling_blast,if=!buff.killing_machine.up
actions.breath_oblit+=/horn_of_winter,if=runic_power.deficit>25
actions.breath_oblit+=/arcane_torrent,if=runic_power.deficit>20
]]

end



APL[SPEC.FROST].cold_heart = function(self)
--[[
actions.cold_heart=chains_of_ice,if=fight_remains<gcd&(rune<2|!buff.killing_machine.up&(!variable.2h_check&buff.cold_heart.stack>=4|variable.2h_check&buff.cold_heart.stack>8)|buff.killing_machine.up&(!variable.2h_check&buff.cold_heart.stack>8|variable.2h_check&buff.cold_heart.stack>10))
actions.cold_heart+=/chains_of_ice,if=!talent.obliteration&buff.pillar_of_frost.up&buff.cold_heart.stack>=10&(buff.pillar_of_frost.remains<gcd*(1+(talent.frostwyrms_fury&cooldown.frostwyrms_fury.ready))|buff.unholy_strength.up&buff.unholy_strength.remains<gcd)
actions.cold_heart+=/chains_of_ice,if=!talent.obliteration&death_knight.runeforge.fallen_crusader&!buff.pillar_of_frost.up&cooldown.pillar_of_frost.remains_expected>15&(buff.cold_heart.stack>=10&buff.unholy_strength.up|buff.cold_heart.stack>=13)
actions.cold_heart+=/chains_of_ice,if=!talent.obliteration&!death_knight.runeforge.fallen_crusader&buff.cold_heart.stack>=10&!buff.pillar_of_frost.up&cooldown.pillar_of_frost.remains_expected>20
actions.cold_heart+=/chains_of_ice,if=talent.obliteration&!buff.pillar_of_frost.up&(buff.cold_heart.stack>=14&(buff.unholy_strength.up|buff.chaos_bane.up)|buff.cold_heart.stack>=19|cooldown.pillar_of_frost.remains_expected<3&buff.cold_heart.stack>=14)
]]

end

APL[SPEC.FROST].cooldowns = function(self)
--[[
actions.cooldowns=potion,if=variable.cooldown_check|fight_remains<25
actions.cooldowns+=/empower_rune_weapon,if=talent.obliteration&!buff.empower_rune_weapon.up&rune<6&(!variable.rw_wait&cooldown.pillar_of_frost.remains_expected<7&(variable.adds_remain|variable.st_planning)|buff.pillar_of_frost.up)|fight_remains<20
actions.cooldowns+=/empower_rune_weapon,use_off_gcd=1,if=buff.breath_of_sindragosa.up&talent.breath_of_sindragosa&!buff.empower_rune_weapon.up&(runic_power<70&rune<3|time<10)
actions.cooldowns+=/empower_rune_weapon,use_off_gcd=1,if=!talent.breath_of_sindragosa&!talent.obliteration&!buff.empower_rune_weapon.up&rune<5&(cooldown.pillar_of_frost.remains_expected<7|buff.pillar_of_frost.up|!talent.pillar_of_frost)
actions.cooldowns+=/abomination_limb,if=talent.obliteration&!buff.pillar_of_frost.up&cooldown.pillar_of_frost.remains<3&(variable.adds_remain|variable.st_planning)|fight_remains<12
actions.cooldowns+=/abomination_limb,if=talent.breath_of_sindragosa&(variable.adds_remain|variable.st_planning)
actions.cooldowns+=/abomination_limb,if=!talent.breath_of_sindragosa&!talent.obliteration&(variable.adds_remain|variable.st_planning)
actions.cooldowns+=/chill_streak,if=set_bonus.tier31_2pc&buff.chilling_rage.remains<3
actions.cooldowns+=/chill_streak,if=!set_bonus.tier31_2pc&active_enemies>=2&(!death_and_decay.ticking&talent.cleaving_strikes|!talent.cleaving_strikes|active_enemies<=5)
actions.cooldowns+=/pillar_of_frost,if=talent.obliteration&(variable.adds_remain|variable.st_planning)&(buff.empower_rune_weapon.up|cooldown.empower_rune_weapon.remains)&!variable.rw_wait|fight_remains<12
actions.cooldowns+=/pillar_of_frost,if=talent.breath_of_sindragosa&(variable.adds_remain|variable.st_planning)&(!talent.icecap&(runic_power>70|cooldown.breath_of_sindragosa.remains>40)|talent.icecap&(cooldown.breath_of_sindragosa.remains>10|buff.breath_of_sindragosa.up))
actions.cooldowns+=/pillar_of_frost,if=talent.icecap&!talent.obliteration&!talent.breath_of_sindragosa&(variable.adds_remain|variable.st_planning)
actions.cooldowns+=/breath_of_sindragosa,if=!buff.breath_of_sindragosa.up&runic_power>60&(variable.adds_remain|variable.st_planning)|fight_remains<30
actions.cooldowns+=/frostwyrms_fury,if=active_enemies=1&(talent.pillar_of_frost&buff.pillar_of_frost.remains<gcd*2&buff.pillar_of_frost.up&!talent.obliteration|!talent.pillar_of_frost)&(!raid_event.adds.exists|(raid_event.adds.in>15+raid_event.adds.duration|talent.absolute_zero&raid_event.adds.in>15+raid_event.adds.duration))|fight_remains<3
actions.cooldowns+=/frostwyrms_fury,if=active_enemies>=2&(talent.pillar_of_frost&buff.pillar_of_frost.up|raid_event.adds.exists&raid_event.adds.up&raid_event.adds.in>cooldown.pillar_of_frost.remains_expected-raid_event.adds.in-raid_event.adds.duration)&(buff.pillar_of_frost.remains<gcd*2|raid_event.adds.exists&raid_event.adds.remains<gcd*2)
actions.cooldowns+=/frostwyrms_fury,if=talent.obliteration&(talent.pillar_of_frost&buff.pillar_of_frost.up&!variable.2h_check|!buff.pillar_of_frost.up&variable.2h_check&cooldown.pillar_of_frost.remains&(!talent.enduring_strength|buff.enduring_strength.up|active_enemies>=5)|!talent.pillar_of_frost)&((buff.pillar_of_frost.remains<gcd|buff.unholy_strength.up&buff.unholy_strength.remains<gcd)&(debuff.razorice.stack=5|!death_knight.runeforge.razorice&!talent.glacial_advance))
actions.cooldowns+=/raise_dead,if=buff.empower_rune_weapon.up|fight_remains<30
actions.cooldowns+=/soul_reaper,if=fight_remains>5&target.time_to_pct_35<5&active_enemies<=2&(talent.obliteration&(buff.pillar_of_frost.up&!buff.killing_machine.react|!buff.pillar_of_frost.up)|talent.breath_of_sindragosa&(buff.breath_of_sindragosa.up&runic_power>40|!buff.breath_of_sindragosa.up)|!talent.breath_of_sindragosa&!talent.obliteration)
actions.cooldowns+=/sacrificial_pact,if=!talent.glacial_advance&!buff.breath_of_sindragosa.up&pet.ghoul.remains<gcd*2&active_enemies>3
actions.cooldowns+=/any_dnd,if=!death_and_decay.ticking&variable.adds_remain&(buff.pillar_of_frost.remains>5&(buff.killing_machine.up|!talent.obliteration&buff.pillar_of_frost.remains<11)|!buff.pillar_of_frost.up&(charges_fractional>1.75|buff.enduring_strength.remains>10|buff.killing_machine.up&cooldown.pillar_of_frost.remains_expected>30*(2-charges_fractional))|fight_remains<11)&(active_enemies>5|talent.cleaving_strikes&active_enemies>=2)
]]
	if EmpowerRuneWeapon:Usable() and EmpowerRuneWeapon:Down() and (
		(Target.boss and Target.timeToDie < 20) or
		(Obliteration.known and Player.runes.ready < 6 and (PillarOfFrost:Up() or (not self.rw_wait and PillarOfFrost:CooldownExpected() < 7 and (self.st_planning or self.adds_remain)))) or
		(BreathOfSindragosa.known and BreathOfSindragosa:Up() and (Player.runic_power.current < 70 and Player.runes.ready < 3 or Player:TimeInCombat() < 10)) or
		(not BreathOfSindragosa.known and not Obliteration.known and Player.runes.ready < 5 and (not PillarOfFrost.known or PillarOfFrost:Up() or PillarOfFrost:CooldownExpected() < 7))
	) then
		UseCooldown(EmpowerRuneWeapon)
	end
	if AbominationLimb:Usable() and (
		(Target.boss and Target.timeToDie < 12) or
		(Obliteration.known and PillarOfFrost:Down() and PillarOfFrost:Ready(3) and (self.st_planning or self.adds_remain)) or
		(BreathOfSindragosa.known and (self.st_planning or self.adds_remain)) or
		(not BreathOfSindragosa.known and not Obliteration.known and (self.st_planning or self.adds_remain))
	) then
		UseCooldown(AbominationLimb)
	end
	if ChillStreak:Usable() and (
		(ChillingRage.known and ChillingRage:Remains() < 3) or
		(not ChillingRage.known and Player.enemies >= 2 and (not CleavingStrikes.known or Player.enemies <= 5 or DeathAndDecay.buff:Down()))
	) then
		UseCooldown(ChillStreak)
	end
	if PillarOfFrost:Usable() and PillarOfFrost:Down() and (
		(Target.boss and Target.timeToDie < 12) or
		(Obliteration.known and (self.st_planning or self.adds_remain) and (EmpowerRuneWeapon:Up() or not EmpowerRuneWeapon:Ready()) and not self.rw_wait) or
		(BreathOfSindragosa.known and (self.st_planning or self.adds_remain) and ((not Icecap.known and (Player.runic_power.current > 70 or not BreathOfSindragosa:Ready(40))) or (Icecap.known and (not BreathOfSindragosa:Ready(10) or BreathOfSindragosa:Up())))) or
		(Icecap.known and not Obliteration.known and not BreathOfSindragosa.known and (self.st_planning or self.adds_remain))
	) then
		UseCooldown(PillarOfFrost)
	end
	if BreathOfSindragosa:Usable() and BreathOfSindragosa:Down() and Player.runic_power.current > 60 and (self.st_planning or self.adds_remain or (Target.boss and Target.timeToDie < 30)) then
		UseCooldown(BreathOfSindragosa)
	end
	if FrostwyrmsFury:Usable() and (
		(Target.boss and Target.timeToDie < 3) or
		(not Obliteration.known and PillarOfFrost:Up() and PillarOfFrost:Remains() < (Player.gcd * 2)) or
		(Obliteration.known and ((Player.equipped.twohand and PillarOfFrost:Down() and not PillarOfFrost:Ready() and (not EnduringStrength.known or EnduringStrength:Up() or Player.enemies >= 5)) or (not Player.equipped.twohand and PillarOfFrost:Up())) and ((PillarOfFrost:Up() and UnholyStrength:Up()) or PillarOfFrost:Remains() < (Player.gcd * 2) or (UnholyStrength:Up() and UnholyStrength:Remains() < (Player.gcd * 2))) and (Razorice:Stack() >= 5 or (not RuneOfRazorice.known and not GlacialAdvance.known)))
	) then
		UseCooldown(FrostwyrmsFury)
	end
	if RaiseDead:Usable() and (EmpowerRuneWeapon:Up() or (Target.boss and Target.timeToDie < 30)) then
		UseExtra(RaiseDead)
	end
	if SoulReaper:Usable() and Target.timeToDie > 5 and Target:TimeToPct(35) < 5 and Player.enemies <= 2 and ((not Obliteration.known and not BreathOfSindragosa.known) or (Obliteration.known and (PillarOfFrost:Down() or KillingMachine:Down())) or (BreathOfSindragosa.known and (BreathOfSindragosa:Down() or Player.runic_power.current > 40))) then
		UseCooldown(SoulReaper)
	end
	if SacrificialPact:Usable() and Player.enemies > 3 and not GlacialAdvance.known and (Target.timeToDie < 3 or ((not BreathOfSindragosa.known or BreathOfSindragosa:Down()) and (not Obliteration.known or PillarOfFrost:Down()) and Pet.RisenGhoul:Remains() < 3)) then
		UseExtra(SacrificialPact)
	end
	if DeathAndDecay:Usable() and Player.enemies >= 2 and DeathAndDecay.buff:Down() and ((PillarOfFrost:Remains() > 5 and (KillingMachine:Up() or (not Obliteration.known and PillarOfFrost:Remains() < 11))) or (PillarOfFrost:Down() and (DeathAndDecay:ChargesFractional() > 1.75 or EnduringStrength:Remains() > 10 or (KillingMachine:Up() and PillarOfFrost:CooldownExpected() > (30 * (2 - DeathAndDecay:ChargesFractional()))))) or (Target.boss and Target.timeToDie < 11)) and (Player.enemies > 5 or CleavingStrikes.known) then
		UseCooldown(DeathAndDecay)
	end
end

APL[SPEC.FROST].obliteration = function(self)
--[[
actions.obliteration=obliterate,target_if=max:(debuff.razorice.stack+1)%(debuff.razorice.remains+1)*death_knight.runeforge.razorice,if=buff.killing_machine.react&talent.cleaving_strikes&death_and_decay.ticking&!variable.frostscythe_priority
actions.obliteration+=/howling_blast,if=buff.killing_machine.stack<2&buff.pillar_of_frost.remains<gcd&buff.rime.react
actions.obliteration+=/frost_strike,if=buff.killing_machine.stack<2&buff.pillar_of_frost.remains<gcd&active_enemies<=1
actions.obliteration+=/glacial_advance,if=buff.killing_machine.stack<2&buff.pillar_of_frost.remains<gcd&!death_and_decay.ticking
actions.obliteration+=/obliterate,target_if=max:(debuff.razorice.stack+1)%(debuff.razorice.remains+1)*death_knight.runeforge.razorice,if=buff.killing_machine.react&!variable.frostscythe_priority
actions.obliteration+=/frostscythe,if=buff.killing_machine.react&variable.frostscythe_priority
actions.obliteration+=/howling_blast,if=!dot.frost_fever.ticking&!buff.killing_machine.react
actions.obliteration+=/glacial_advance,if=!death_knight.runeforge.razorice&!buff.killing_machine.react&(debuff.razorice.stack<5|debuff.razorice.remains<gcd*3)
actions.obliteration+=/frost_strike,target_if=max:(debuff.razorice.stack+1)%(debuff.razorice.remains+1)*death_knight.runeforge.razorice,if=!buff.killing_machine.react&(rune<2|variable.rp_buffs|debuff.razorice.stack=5&talent.shattering_blade)&!variable.pooling_runic_power&(!talent.glacial_advance|active_enemies=1)
actions.obliteration+=/howling_blast,if=buff.rime.react&!buff.killing_machine.react
actions.obliteration+=/glacial_advance,if=!variable.pooling_runic_power&variable.rp_buffs&!buff.killing_machine.react&active_enemies>=2
actions.obliteration+=/frost_strike,target_if=max:(debuff.razorice.stack+1)%(debuff.razorice.remains+1)*death_knight.runeforge.razorice,if=!buff.killing_machine.react&!variable.pooling_runic_power&(!talent.glacial_advance|active_enemies=1)
actions.obliteration+=/howling_blast,if=!buff.killing_machine.react&runic_power<25
actions.obliteration+=/arcane_torrent,if=rune<1&runic_power<25
actions.obliteration+=/glacial_advance,if=!variable.pooling_runic_power&active_enemies>=2
actions.obliteration+=/frost_strike,target_if=max:(debuff.razorice.stack+1)%(debuff.razorice.remains+1)*death_knight.runeforge.razorice,if=!variable.pooling_runic_power&(!talent.glacial_advance|active_enemies=1)
actions.obliteration+=/howling_blast,if=buff.rime.react
actions.obliteration+=/remorseless_winter,if=!remains
actions.obliteration+=/obliterate,target_if=max:(debuff.razorice.stack+1)%(debuff.razorice.remains+1)*death_knight.runeforge.razorice
]]
	if not self.frostscythe_priority and Obliterate:Usable() and KillingMachine:Up() and DeathAndDecay.buff:Up() then
		return Obliterate
	end
	if KillingMachine:Stack() < 2 and PillarOfFrost:Remains() < Player.gcd then
		if HowlingBlast:Usable() and Rime:Up() then
			return HowlingBlast
		end
		if FrostStrike:Usable() and Player.enemies <= 1 then
			return FrostStrike
		end
		if GlacialAdvance:Usable() and DeathAndDecay.buff:Down() then
			return GlacialAdvance
		end
	end
	if KillingMachine:Up() then
		if not self.frostscythe_priority and Obliterate:Usable() then
			return Obliterate
		end
		if self.frostscythe_priority and Frostscythe:Usable() then
			return Frostscythe
		end
	else
		if HowlingBlast:Usable() and FrostFever:Down() then
			return HowlingBlast
		end
		if not RuneOfRazorice.known and GlacialAdvance:Usable() and (Razorice:Stack() < 5 or Razorice:Remains() < (Player.gcd * 3)) then
			return GlacialAdvance
		end
		if not self.pooling_runic_power and FrostStrike:Usable() and (Player.runes.ready < 2 or self.rp_buffs or (ShatteringBlade.known and Razorice:Stack() >= 5)) and (not GlacialAdvance.known or Player.enemies <= 1) then
			return FrostStrike
		end
		if HowlingBlast:Usable() and Rime:Up() then
			return HowlingBlast
		end
		if not self.pooling_runic_power and GlacialAdvance:Usable() and self.rp_buffs and Player.enemies >= 2 then
			return GlacialAdvance
		end
		if not self.pooling_runic_power and FrostStrike:Usable() and (not GlacialAdvance.known or Player.enemies <= 1) then
			return FrostStrike
		end
		if HowlingBlast:Usable() and Player.runic_power.current < 25 then
			return HowlingBlast
		end
	end
	if not self.pooling_runic_power then
		if GlacialAdvance:Usable() and Player.enemies >= 2 then
			return GlacialAdvance
		end
		if FrostStrike:Usable() and (not GlacialAdvance.known or Player.enemies <= 1) then
			return FrostStrike
		end
	end
	if HowlingBlast:Usable() and Rime:Up() then
		return HowlingBlast
	end
	if RemorselessWinter:Usable() and RemorselessWinter:Down() then
		return RemorselessWinter
	end
	if Obliterate:Usable() then
		return Obliterate
	end
end

APL[SPEC.FROST].single_target = function(self)
--[[
actions.single_target=remorseless_winter,if=!remains&(variable.rw_buffs|variable.adds_remain)
actions.single_target+=/frost_strike,if=buff.killing_machine.stack<2&runic_power.deficit<20&!variable.2h_check
actions.single_target+=/frostscythe,if=buff.killing_machine.react&variable.frostscythe_priority
actions.single_target+=/obliterate,if=buff.killing_machine.react
actions.single_target+=/howling_blast,if=buff.rime.react&talent.icebreaker.rank=2
actions.single_target+=/horn_of_winter,if=rune<4&runic_power.deficit>25&talent.obliteration&talent.breath_of_sindragosa
actions.single_target+=/frost_strike,if=!variable.pooling_runic_power&(variable.rp_buffs|runic_power.deficit<25|debuff.razorice.stack=5&talent.shattering_blade)
actions.single_target+=/howling_blast,if=variable.rime_buffs
actions.single_target+=/glacial_advance,if=!variable.pooling_runic_power&!death_knight.runeforge.razorice&(debuff.razorice.stack<5|debuff.razorice.remains<gcd*3)
actions.single_target+=/obliterate,if=!variable.pooling_runes
actions.single_target+=/horn_of_winter,if=rune<4&runic_power.deficit>25&(!talent.breath_of_sindragosa|cooldown.breath_of_sindragosa.remains>cooldown.horn_of_winter.duration)
actions.single_target+=/arcane_torrent,if=runic_power.deficit>20
actions.single_target+=/frost_strike,if=!variable.pooling_runic_power
]]
	if RemorselessWinter:Usable() and RemorselessWinter:Down() and (self.rw_buffs or self.adds_remain) then
		return RemorselessWinter
	end
	if not Player.equipped.twohand and FrostStrike:Usable() and KillingMachine:Stack() < 2 and Player.runic_power.deficit < 20 then
		return FrostStrike
	end
	if self.frostscythe_priority and Frostscythe:Usable() and KillingMachine:Up() then
		return Frostscythe
	end
	if Obliterate:Usable() and KillingMachine:Up() then
		return Obliterate
	end
	if HowlingBlast:Usable() and Icebreaker.rank == 2 and Rime:Up() then
		return HowlingBlast
	end
	if DeathStrike:Usable() and Player.health.pct < (DarkSuccor:Up() and 80 or Opt.death_strike_threshold) then
		UseCooldown(DeathStrike)
	end
	if HornOfWinter:Usable() and Player.runes.ready < 4 and Player.runic_power.deficit > 25 and Obliteration.known and BreathOfSindragosa.known then
		return HornOfWinter
	end
	if not Player.pooling_runic_power and FrostStrike:Usable() and (self.rp_buffs or Player.runic_power.deficit < 25 or (ShatteringBlade.known and Razorice:Stack() >= 5)) then
		return FrostStrike
	end
	if HowlingBlast:Usable() and self.rime_buffs then
		return HowlingBlast
	end
	if not Player.pooling_runic_power and GlacialAdvance:Usable() and not RuneOfRazorice.known and (Razorice:Stack() < 5 or Razorice:Remains() < (Player.gcd * 3)) then
		return GlacialAdvance
	end
	if not self.pooling_runes and Obliterate:Usable() then
		return Obliterate
	end
	if HornOfWinter:Usable() and Player.runes.ready < 4 and Player.runic_power.deficit > 25 and (not BreathOfSindragosa.known or not BreathOfSindragosa:Ready(HornOfWinter:CooldownDuration())) then
		return HornOfWinter
	end
	if not Player.pooling_runic_power and FrostStrike:Usable() then
		return FrostStrike
	end
	if DeathStrike:Usable() and DarkSuccor:Up() then
		UseCooldown(DeathStrike)
	end
end

APL[SPEC.FROST].trinkets = function(self)
--[[
actions.trinkets=use_item,name=fyralath_the_dreamrender,if=dot.mark_of_fyralath.ticking&!buff.pillar_of_frost.up&!buff.bloodlust.up&!buff.empower_rune_weapon.up&!variable.rp_buffs
actions.trinkets+=/use_item,use_off_gcd=1,name=algethar_puzzle_box,if=!buff.pillar_of_frost.up&cooldown.pillar_of_frost.remains<2&(!talent.breath_of_sindragosa|runic_power>60&(buff.breath_of_sindragosa.up|cooldown.breath_of_sindragosa.remains<2))
# Trinkets The trinket with the highest estimated value, will be used first and paired with Pillar of Frost.
actions.trinkets+=/use_item,use_off_gcd=1,slot=trinket1,if=variable.trinket_1_buffs&!variable.trinket_1_manual&(!buff.pillar_of_frost.up&trinket.1.cast_time>0|!trinket.1.cast_time>0)&(buff.breath_of_sindragosa.up|buff.pillar_of_frost.up)&(variable.trinket_2_exclude|!trinket.2.has_cooldown|trinket.2.cooldown.remains|variable.trinket_priority=1)|trinket.1.proc.any_dps.duration>=fight_remains
actions.trinkets+=/use_item,use_off_gcd=1,slot=trinket2,if=variable.trinket_2_buffs&!variable.trinket_2_manual&(!buff.pillar_of_frost.up&trinket.2.cast_time>0|!trinket.2.cast_time>0)&(buff.breath_of_sindragosa.up|buff.pillar_of_frost.up)&(variable.trinket_1_exclude|!trinket.1.has_cooldown|trinket.1.cooldown.remains|variable.trinket_priority=2)|trinket.2.proc.any_dps.duration>=fight_remains
# If only one on use trinket provides a buff, use the other on cooldown. Or if neither trinket provides a buff, use both on cooldown.
actions.trinkets+=/use_item,use_off_gcd=1,slot=trinket1,if=!variable.trinket_1_buffs&!variable.trinket_1_manual&(!variable.trinket_1_buffs&(trinket.2.cooldown.remains|!variable.trinket_2_buffs)|(trinket.1.cast_time>0&!buff.pillar_of_frost.up|!trinket.1.cast_time>0)|talent.pillar_of_frost&cooldown.pillar_of_frost.remains_expected>20|!talent.pillar_of_frost)
actions.trinkets+=/use_item,use_off_gcd=1,slot=trinket2,if=!variable.trinket_2_buffs&!variable.trinket_2_manual&(!variable.trinket_2_buffs&(trinket.1.cooldown.remains|!variable.trinket_1_buffs)|(trinket.2.cast_time>0&!buff.pillar_of_frost.up|!trinket.2.cast_time>0)|talent.pillar_of_frost&cooldown.pillar_of_frost.remains_expected>20|!talent.pillar_of_frost)
actions.trinkets+=/use_item,use_off_gcd=1,slot=main_hand,if=(!variable.trinket_1_buffs|trinket.1.cooldown.remains)&(!variable.trinket_2_buffs|trinket.2.cooldown.remains)
]]
	if FyralathTheDreamrender:Usable() and MarkOfFyralath:Ticking() >= Obliterate:Targets() and PillarOfFrost:Down() and not Player:BloodlustActive() and EmpowerRuneWeapon:Down() and not self.rp_buffs then
		return UseCooldown(FyralathTheDreamrender)
	end
	if Trinket.AlgetharPuzzleBox:Usable() and PillarOfFrost:Down() and PillarOfFrost:Ready(2) and (not BreathOfSindragosa.known or (Player.runic_power.current > 60 and (BreathOfSindragosa:Up() or BreathOfSindragosa:Ready(2)))) then
		return UseCooldown(Trinket.AlgetharPuzzleBox)
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

	if not Pet.active and RaiseDeadUnholy:Usable() then
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
		if Target.boss then
			if ArmyOfTheDead:Usable() then
				UseCooldown(ArmyOfTheDead)
			end
			if RaiseAbomination:Usable() then
				UseCooldown(RaiseAbomination)
			end
		end
	else

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
		if SummonGargoyle:Usable() and Player.runic_power.deficit < 14 then
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
		if SwarmingMist:Usable() and (Player.runic_power.current < 60 or Player.enemies >= 3) then
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
		if not Player.pooling_for_gargoyle and Player.runes.ready < 2 then
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
		if SuddenDoom:Up() and (Player.runes.deficit >= 4 or not Player.pooling_for_gargoyle) then
			return DeathCoil
		end
		if Pet.EbonGargoyle:Up() then
			return DeathCoil
		end
		if not Player.pooling_for_gargoyle and Player.runic_power.deficit < 14 and (apocalypse_not_ready_5 or FesteringWound:Stack() > 4) then
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
	if Player.runic_power.deficit < 20 and not Player.pooling_for_gargoyle then
		if SacrificialPact:Usable() and RaiseDeadUnholy:Usable(Player.gcd) and not DarkTransformation:Ready(3) and DarkTransformation:Down() and (not UnholyAssault.known or UnholyAssault:Down()) then
			UseCooldown(SacrificialPact)
		end
		if Player.health.pct < Opt.death_strike_threshold and DeathStrike:Usable() then
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
		if Player.health.pct < Opt.death_strike_threshold and DeathStrike:Usable() then
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
		if not Player.pooling_for_gargoyle and Player.runic_power.deficit < 14 and (apocalypse_not_ready_5 or FesteringWound:Stack() > 4) then
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
	if Player.runic_power.deficit < 20 and not Player.pooling_for_gargoyle then
		if Player.health.pct < Opt.death_strike_threshold and DeathStrike:Usable() then
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
		if Player.health.pct < Opt.death_strike_threshold and DeathStrike:Usable() then
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

-- Start UI Functions

function UI.DenyOverlayGlow(actionButton)
	if Opt.glow.blizzard then
		return
	end
	local alert = actionButton.SpellActivationAlert
	if not alert then
		return
	end
	if alert.ProcStartAnim:IsPlaying() then
		alert.ProcStartAnim:Stop()
	end
	alert:Hide()
end
hooksecurefunc('ActionButton_ShowOverlayGlow', UI.DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

function UI:UpdateGlowColorAndScale()
	local w, h, glow
	local r, g, b = Opt.glow.color.r, Opt.glow.color.g, Opt.glow.color.b
	for i = 1, #self.glows do
		glow = self.glows[i]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
		glow.ProcStartFlipbook:SetVertexColor(r, g, b)
		glow.ProcLoopFlipbook:SetVertexColor(r, g, b)
	end
end

function UI:DisableOverlayGlows()
	if LibStub and LibStub.GetLibrary and not Opt.glow.blizzard then
		local lib = LibStub:GetLibrary('LibButtonGlow-1.0', true)
		if lib then
			lib.ShowOverlayGlow = function(self)
				return
			end
		end
	end
end

function UI:CreateOverlayGlows()
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.ProcStartAnim:Play() -- will bug out if ProcLoop plays first
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
	self:UpdateGlowColorAndScale()
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
				glow:Show()
				if Opt.glow.animation then
					glow.ProcStartAnim:Play()
				else
					glow.ProcLoop:Play()
				end
			end
		elseif glow:IsVisible() then
			if glow.ProcStartAnim:IsPlaying() then
				glow.ProcStartAnim:Stop()
			end
			if glow.ProcLoop:IsPlaying() then
				glow.ProcLoop:Stop()
			end
			glow:Hide()
		end
	end
end

function UI:UpdateDraggable()
	local draggable = not (Opt.locked or Opt.snap or Opt.aoe)
	braindeadPanel:SetMovable(not Opt.snap)
	braindeadPreviousPanel:SetMovable(not Opt.snap)
	braindeadCooldownPanel:SetMovable(not Opt.snap)
	braindeadInterruptPanel:SetMovable(not Opt.snap)
	braindeadExtraPanel:SetMovable(not Opt.snap)
	if not Opt.snap then
		braindeadPanel:SetUserPlaced(true)
		braindeadPreviousPanel:SetUserPlaced(true)
		braindeadCooldownPanel:SetUserPlaced(true)
		braindeadInterruptPanel:SetUserPlaced(true)
		braindeadExtraPanel:SetUserPlaced(true)
	end
	braindeadPanel:EnableMouse(draggable or Opt.aoe)
	braindeadPanel.button:SetShown(Opt.aoe)
	braindeadPreviousPanel:EnableMouse(draggable)
	braindeadCooldownPanel:EnableMouse(draggable)
	braindeadInterruptPanel:EnableMouse(draggable)
	braindeadExtraPanel:EnableMouse(draggable)
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
			['below'] = { 'TOP', 'BOTTOM', 0, -12 },
		},
		[SPEC.FROST] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 49 },
			['below'] = { 'TOP', 'BOTTOM', 0, -12 },
		},
		[SPEC.UNHOLY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 49 },
			['below'] = { 'TOP', 'BOTTOM', 0, -12 },
		}
	},
	kui = { -- Kui Nameplates
		[SPEC.BLOOD] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -2 },
		},
		[SPEC.FROST] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -2 },
		},
		[SPEC.UNHOLY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -2 },
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
	self:UpdateGlows()
end

function UI:Reset()
	braindeadPanel:ClearAllPoints()
	braindeadPanel:SetPoint('CENTER', 0, -169)
	self:SnapAllPanels()
end

function UI:UpdateDisplay()
	Timer.display = 0
	local border, dim, dim_cd, text_center, text_cd

	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
		dim_cd = not ((not Player.cd) or
		           (Player.cd.spellId and IsUsableSpell(Player.cd.spellId)) or
		           (Player.cd.itemId and IsUsableItem(Player.cd.itemId)))
	end
	if Player.main then
		if Player.main.requires_react then
			local react = Player.main:React()
			if react > 0 then
				text_center = format('%.1f', react)
			end
		end
		if Player.main_freecast then
			border = 'freecast'
		end
	end
	if Player.cd and Player.cd.requires_react then
		local react = Player.cd:React()
		if react > 0 then
			text_cd = format('%.1f', react)
		end
	end
	if DancingRuneWeapon.known and Player.drw_remains > 0 then
		text_center = format('%.1fs', Player.drw_remains)
	elseif ArmyOfTheDead.known and Player.pooling_for_aotd then
		text_center = format('Pool for\n%s', ArmyOfTheDead.name)
	elseif SummonGargoyle.known and Player.pooling_for_gargoyle then
		text_center = format('Pool for\n%s', SummonGargoyle.name)
	end
	if border ~= braindeadPanel.border.overlay then
		braindeadPanel.border.overlay = border
		braindeadPanel.border:SetTexture(ADDON_PATH .. (border or 'border') .. '.blp')
	end

	braindeadPanel.dimmer:SetShown(dim)
	braindeadPanel.text.center:SetText(text_center)
	--braindeadPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
	braindeadCooldownPanel.text:SetText(text_cd)
	braindeadCooldownPanel.dimmer:SetShown(dim_cd)
end

function UI:UpdateCombat()
	Timer.combat = 0

	Player:Update()

	if Player.main then
		braindeadPanel.icon:SetTexture(Player.main.icon)
		Player.main_freecast = (Player.main.runic_power_cost > 0 and Player.main:RunicPowerCost() == 0) or (Player.main.rune_cost > 0 and Player.main:RuneCost() == 0) or (Player.main.Free and Player.main:Free())
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
	if Opt.frequency - Timer.combat > seconds then
		Timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

-- End UI Functions

-- Start Event Handling

function Events:ADDON_LOADED(name)
	if name == ADDON then
		Opt = Braindead
		local firstRun = not Opt.frequency
		InitOpts()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		if firstRun then
			log('It looks like this is your first time running ' .. ADDON .. ', why don\'t you take some time to familiarize yourself with the commands?')
			log('Type |cFFFFD000' .. SLASH_Braindead1 .. '|r for a list of commands.')
			UI:SnapAllPanels()
		end
		if UnitLevel('player') < 10 then
			log('[|cFFFFD000Warning|r]', ADDON, 'is not designed for players under level 10, and almost certainly will not operate properly!')
		end
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
	   e == 'SPELL_ABSORBED' or
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
		AutoAoe:Remove(dstGUID)
	end
	local pet = SummonedPets:Find(dstGUID)
	if pet then
		pet:RemoveUnit(dstGUID)
	end
end

CombatEvent.SWING_DAMAGE = function(event, srcGUID, dstGUID, amount, overkill, spellSchool, resisted, blocked, absorbed, critical, glancing, crushing, offHand)
	if srcGUID == Player.guid then
		Player:ResetSwing(not offHand, offHand)
		if Opt.auto_aoe then
			AutoAoe:Add(dstGUID, true)
		end
		MarkOfFyralath:Refresh(dstGUID)
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	elseif srcGUID == Pet.guid then
		if Opt.auto_aoe then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Pet.guid then
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SWING_MISSED = function(event, srcGUID, dstGUID, missType, offHand, amountMissed)
	if srcGUID == Player.guid then
		Player:ResetSwing(not offHand, offHand, true)
		if Opt.auto_aoe and not (missType == 'EVADE' or missType == 'IMMUNE') then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	elseif srcGUID == Pet.guid then
		if Opt.auto_aoe and not (missType == 'EVADE' or missType == 'IMMUNE') then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Pet.guid then
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SPELL_SUMMON = function(event, srcGUID, dstGUID)
	if srcGUID ~= Player.guid then
		return
	end
	local pet = SummonedPets:Find(dstGUID)
	if pet then
		pet:AddUnit(dstGUID)
	end
end

CombatEvent.SPELL = function(event, srcGUID, dstGUID, spellId, spellName, spellSchool, missType, overCap, powerType)
	if not (srcGUID == Player.guid or srcGUID == Pet.guid) then
		local pet = SummonedPets:Find(srcGUID)
		if pet then
			local unit = pet.active_units[srcGUID]
			if unit then
				if event == 'SPELL_CAST_SUCCESS' and pet.CastSuccess then
					pet:CastSuccess(unit, spellId, dstGUID)
				elseif event == 'SPELL_CAST_START' and pet.CastStart then
					pet:CastStart(unit, spellId, dstGUID)
				elseif event == 'SPELL_CAST_FAILED' and pet.CastFailed then
					pet:CastFailed(unit, spellId, dstGUID, missType)
				elseif (event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED' or event == 'SPELL_MISSED' or event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH') and pet.CastLanded then
					pet:CastLanded(unit, spellId, dstGUID, event, missType)
				end
				--log(format('PET %d EVENT %s SPELL %s ID %d', pet.unitId, event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0))
			end
		end
		return
	end

	if srcGUID == Pet.guid then
		if Pet.stuck and (event == 'SPELL_CAST_SUCCESS' or event == 'SPELL_DAMAGE' or event == 'SWING_DAMAGE') then
			Pet.stuck = false
		elseif not Pet.stuck and event == 'SPELL_CAST_FAILED' and missType == 'No path available' then
			Pet.stuck = true
		end
	end

	local ability = spellId and Abilities.bySpellId[spellId]
	if not ability then
		--log(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0))
		return
	end

	UI:UpdateCombatWithin(0.05)
	if event == 'SPELL_CAST_SUCCESS' then
		return ability:CastSuccess(dstGUID)
	elseif event == 'SPELL_CAST_START' then
		return ability.CastStart and ability:CastStart(dstGUID)
	elseif event == 'SPELL_CAST_FAILED'  then
		return ability.CastFailed and ability:CastFailed(dstGUID, missType)
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
	if dstGUID == Player.guid or dstGUID == Pet.guid then
		if event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
			ability.last_gained = Player.time
		end
		return -- ignore buffs beyond here
	end
	if event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED' or event == 'SPELL_MISSED' or event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
		ability:CastLanded(dstGUID, event, missType)
		if MarkOfFyralath.known and event ~= 'SPELL_MISSED' then
			MarkOfFyralath:Refresh(dstGUID)
		end
	end
end

function Events:COMBAT_LOG_EVENT_UNFILTERED()
	CombatEvent.TRIGGER(CombatLogGetCurrentEventInfo())
end

function Events:PLAYER_TARGET_CHANGED()
	Target:Update()
end

function Events:UNIT_FACTION(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function Events:UNIT_FLAGS(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function Events:UNIT_HEALTH(unitId)
	if unitId == 'player' then
		Player.health.current = UnitHealth('player')
		Player.health.max = UnitHealthMax('player')
		Player.health.pct = Player.health.current / Player.health.max * 100
	elseif unitId == 'pet' then
		Pet.health.current = UnitHealth('pet')
		Pet.health.max = UnitHealthMax('pet')
		Pet.health.pct = Pet.health.current / Pet.health.max * 100
	end
end

function Events:UNIT_POWER_FREQUENT(unitId, powerType)
	if unitId == 'player' and powerType == 'RUNIC_POWER' then
		Player.runic_power.current = UnitPower('player', 6)
		Player.runic_power.deficit = Player.runic_power.max - Player.runic_power.current
	end
end

function Events:UNIT_SPELLCAST_START(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function Events:UNIT_SPELLCAST_STOP(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end
Events.UNIT_SPELLCAST_FAILED = Events.UNIT_SPELLCAST_STOP
Events.UNIT_SPELLCAST_INTERRUPTED = Events.UNIT_SPELLCAST_STOP

function Events:UNIT_SPELLCAST_SUCCEEDED(unitId, castGUID, spellId)
	if unitId ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = Abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability.traveling then
		ability.next_castGUID = castGUID
	end
end

function Events:UNIT_PET(unitId)
	if unitId ~= 'player' then
		return
	end
	Pet:Update()
end

function Events:PLAYER_REGEN_DISABLED()
	Player:UpdateTime()
	Player.combat_start = Player.time
end

function Events:PLAYER_REGEN_ENABLED()
	Player:UpdateTime()
	Player.combat_start = 0
	Player.swing.last_taken = 0
	Pet.stuck = false
	Target.estimated_range = 30
	wipe(Player.previous_gcd)
	if Player.last_ability then
		Player.last_ability = nil
		braindeadPreviousPanel:Hide()
	end
	for _, ability in next, Abilities.velocity do
		for guid in next, ability.traveling do
			ability.traveling[guid] = nil
		end
	end
	if Opt.auto_aoe then
		AutoAoe:Clear()
	end
	if APL[Player.spec].precombat_variables then
		APL[Player.spec]:precombat_variables()
	end
end

function Events:PLAYER_EQUIPMENT_CHANGED()
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

	Player.set_bonus.t29 = (Player:Equipped(200405) and 1 or 0) + (Player:Equipped(200407) and 1 or 0) + (Player:Equipped(200408) and 1 or 0) + (Player:Equipped(200409) and 1 or 0) + (Player:Equipped(200410) and 1 or 0)
	Player.set_bonus.t30 = (Player:Equipped(202459) and 1 or 0) + (Player:Equipped(202460) and 1 or 0) + (Player:Equipped(202461) and 1 or 0) + (Player:Equipped(202462) and 1 or 0) + (Player:Equipped(202464) and 1 or 0)
	Player.set_bonus.t31 = (Player:Equipped(207198) and 1 or 0) + (Player:Equipped(207199) and 1 or 0) + (Player:Equipped(207200) and 1 or 0) + (Player:Equipped(207201) and 1 or 0) + (Player:Equipped(207203) and 1 or 0)

	Player:ResetSwing(true, true)
	Player:UpdateKnown()
end

function Events:PLAYER_SPECIALIZATION_CHANGED(unitId)
	if unitId ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	braindeadPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	Events:PLAYER_EQUIPMENT_CHANGED()
	Events:PLAYER_REGEN_ENABLED()
	Events:UNIT_HEALTH('player')
	UI.OnResourceFrameShow()
	Target:Update()
	Player:Update()
end

function Events:TRAIT_CONFIG_UPDATED()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

function Events:SPELL_UPDATE_COOLDOWN()
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

function Events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateKnown()
end

function Events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

function Events:GROUP_ROSTER_UPDATE()
	Player.group_size = clamp(GetNumGroupMembers(), 1, 40)
end

function Events:PLAYER_ENTERING_WORLD()
	Player:Init()
	Target:Update()
	C_Timer.After(5, function() Events:PLAYER_EQUIPMENT_CHANGED() end)
end

function Events:UI_ERROR_MESSAGE(errorId)
	if (
	    errorId == 394 or -- pet is rooted
	    errorId == 396 or -- target out of pet range
	    errorId == 400    -- no pet path to target
	) then
		Pet.stuck = true
	end
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
	Timer.combat = Timer.combat + elapsed
	Timer.display = Timer.display + elapsed
	Timer.health = Timer.health + elapsed
	if Timer.combat >= Opt.frequency then
		UI:UpdateCombat()
	end
	if Timer.display >= 0.05 then
		UI:UpdateDisplay()
	end
	if Timer.health >= 0.2 then
		Target:UpdateHealth()
	end
end)

braindeadPanel:SetScript('OnEvent', function(self, event, ...) Events[event](self, ...) end)
for event in next, Events do
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
	log(desc .. ':', opt_view, ...)
end

SlashCmdList[ADDON] = function(msg, editbox)
	msg = { strsplit(' ', msg:lower()) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UI:UpdateDraggable()
		end
		if Opt.aoe or Opt.snap then
			Status('Warning', 'Panels cannot be moved when aoe or snap are enabled!')
		end
		return Status('Locked', Opt.locked)
	end
	if startsWith(msg[1], 'snap') then
		if msg[2] then
			if msg[2] == 'above' or msg[2] == 'over' then
				Opt.snap = 'above'
				Opt.locked = true
			elseif msg[2] == 'below' or msg[2] == 'under' then
				Opt.snap = 'below'
				Opt.locked = true
			else
				Opt.snap = false
				Opt.locked = false
				UI:Reset()
			end
			UI:UpdateDraggable()
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
			Opt.alpha = clamp(tonumber(msg[2]) or 100, 0, 100) / 100
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
		if startsWith(msg[2], 'anim') then
			if msg[3] then
				Opt.glow.animation = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Use extended animation (shrinking circle)', Opt.glow.animation)
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = clamp(tonumber(msg[3]) or 0, 0, 1)
				Opt.glow.color.g = clamp(tonumber(msg[4]) or 0, 0, 1)
				Opt.glow.color.b = clamp(tonumber(msg[5]) or 0, 0, 1)
				UI:UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, |cFFFFD000animation|r, and |cFFFFD000color')
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
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Blood specialization', not Opt.hide.blood)
			end
			if startsWith(msg[2], 'f') then
				Opt.hide.frost = not Opt.hide.frost
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Frost specialization', not Opt.hide.frost)
			end
			if startsWith(msg[2], 'u') then
				Opt.hide.unholy = not Opt.hide.unholy
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
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
			Opt.death_strike_threshold = clamp(tonumber(msg[2]) or 60, 0, 100)
		end
		return Status('Health percentage threshold to recommend Death Strike', Opt.death_strike_threshold .. '%')
	end
	if msg[1] == 'reset' then
		UI:Reset()
		return Status('Position has been reset to', 'default')
	end
	print(ADDON, '(version: |cFFFFD000' .. GetAddOnMetadata(ADDON, 'Version') .. '|r) - Commands:')
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the ' .. ADDON .. ' UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the ' .. ADDON .. ' UI to the Personal Resource Display',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000pet|r/|cFFFFD000glow|r - adjust the scale of the ' .. ADDON .. ' UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the ' .. ADDON .. ' UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r/|cFFFFD000animation|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
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
