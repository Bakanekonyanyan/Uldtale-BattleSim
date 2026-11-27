# res://scenes/battle/core/BattleFormulas.gd
# ALL battle math lives here. Tune the constants below; every damage, heal,
# mitigation and status-proc roll in CombatEngine and Skill goes through these.
#
# Model
# -----
#   offense   = attack_power + weapon damage   (physical)
#             = spell_power                    (magical)
#   raw hit   = offense * BASE_SCALE * (1 + skill_power * SKILL_POWER_SCALE)
#               (basic attacks have skill_power 0)
#   mitigated = raw * DEFENSE_K / (DEFENSE_K + defense)
#   defense   = toughness + armor * ARMOR_SCALE  (physical)
#             = spell_ward + armor * ARMOR_SCALE * ARMOR_VS_MAGIC  (magical)
#
# So defense 0 = full damage, defense 100 = half damage, defense 300 = quarter.
# Skills are "a basic attack, boosted by their power": power 25 -> x1.25,
# power 55 -> x1.55. Their real value comes from AoE, status and buffs, and they
# cost resources and have cooldowns, so they must not dwarf basic attacks.

class_name BattleFormulas
extends RefCounted

# --- Damage ---
const BASE_SCALE := 0.75           # fraction of offense a plain hit deals
const SKILL_POWER_SCALE := 0.01    # each point of skill power adds +1% damage
const WEAPON_DAMAGE_SCALE := 1.0   # weapon damage added to physical offense
const MIN_DAMAGE := 1

# --- Defense ---
const DEFENSE_K := 100.0           # defense needed to halve damage
const MAX_ARMOR_PENETRATION := 0.75 # physical attacks ignore at most 75% of defense
const ARMOR_SCALE := 0.5           # each point of armor = 0.5 defense
const ARMOR_VS_MAGIC := 0.5        # ...and half of that again against magic

# --- Crits ---
const CRIT_MULT_MIN := 1.5
const CRIT_MULT_MAX := 2.0

# --- Healing ---
const HEAL_SPELL_POWER_SCALE := 0.5  # heal = power + spell_power * this

# --- Status effects carried by DAMAGE skills ---
# Dedicated status/debuff skills always apply their effect; damage skills only
# have a chance per effect per target hit.
const DAMAGE_SKILL_STATUS_CHANCE := 0.35

# --- Buffs / debuffs from skills ---
# Skill power is a PERCENT of the target's base attribute (power 40 = +/-60%).
# It used to be added as flat stat points: Roar (40) took 40 Agility off a
# level-1 hero with ~6, and the boss's Royal Decree added +60 Strength.
const BUFF_PERCENT_PER_POWER := 0.015
# Durations tick at the START of the target's turn, so a "3 turn" buff used to
# boost only 2 of the caster's actions (after spending a turn to cast it). Buff/
# debuff skills add this so the number on the skill = turns actually affected.
const BUFF_DURATION_BONUS := 1
# Debuff skills also hit each target for this fraction of a basic attack, so a
# debuff is "an attack plus a debuff" rather than a turn spent not attacking.
const DEBUFF_HIT_SCALE := 0.75

# --- Basic attack resource regen ---
const ATTACK_RESOURCE_REGEN := 0.08  # basic attacks restore 8% max MP and SP

# =============================================================

## You and your party (the combat rhythm applies to heroes, not enemies).
static func is_hero_side(c: CharacterData) -> bool:
	return c != null and (c.is_player or c.has_meta("hero_side"))

static func rhythm() -> Dictionary:
	return BattleRules.cfg().get("rhythm", {})

## A skill's MP/SP cost for `c`: heavier for heroes, and rising with level so
## skills stay a budget rather than a free rotation (combat.json rhythm).
static func skill_cost(c: CharacterData, base: int) -> int:
	if base <= 0 or not is_hero_side(c):
		return base
	var r = rhythm()
	return int(ceil(base * float(r.get("skill_cost_mult", 1.0)) * (1.0 + float(r.get("cost_per_level", 0.0)) * max(0, c.level - 1))))

## Share of max MP/SP a basic attack restores.
static func attack_restore(c: CharacterData) -> float:
	return float(rhythm().get("attack_restore", ATTACK_RESOURCE_REGEN)) if is_hero_side(c) else ATTACK_RESOURCE_REGEN

static func physical_offense(c: CharacterData) -> float:
	return c.attack_power + get_weapon_damage(c) * WEAPON_DAMAGE_SCALE

static func magical_offense(c: CharacterData) -> float:
	return c.spell_power

static func physical_defense(c: CharacterData) -> float:
	return c.toughness + get_armor(c) * ARMOR_SCALE

static func magical_defense(c: CharacterData) -> float:
	return c.spell_ward + get_armor(c) * ARMOR_SCALE * ARMOR_VS_MAGIC

## Fraction of damage that gets through a given defense value (0..1].
static func mitigation(defense: float) -> float:
	return DEFENSE_K / (DEFENSE_K + max(0.0, defense))

## Raw (pre-crit, pre-element) damage for a hit.
## skill_power = 0 for basic attacks. damage_type: DamageTypes.Type, or
## FROM_WEAPON (-1) to use the attacker's main-hand weapon (physical hits only).
static func hit_damage(attacker: CharacterData, target: CharacterData, is_physical: bool, skill_power: float = 0.0, damage_type: int = -1, skill = null) -> float:
	var offense = physical_offense(attacker) if is_physical else magical_offense(attacker)
	var defense = physical_defense(target) if is_physical else magical_defense(target)
	if is_physical:
		defense *= 1.0 - get_armor_penetration(attacker)
	var raw = offense * BASE_SCALE * (1.0 + skill_power * SKILL_POWER_SCALE)
	raw *= attacker.damage_multiplier  # enemy tuning (EnemyFactory), 1.0 for players
	raw *= MomentumSystem.get_damage_multiplier() if attacker.is_player else 1.0
	var weak := false
	if is_physical:
		var tm = DamageTypes.multiplier(target, DamageTypes.attack_type(attacker, damage_type))
		raw *= tm
		weak = tm > 1.05
	if not weak and skill is Skill and target.elemental_resistances:
		for el in skill.elements:
			var n = Skill.ElementType.keys()[el]
			if ElementalDamage.Element.has(n) and target.elemental_resistances.get_total_weakness(ElementalDamage.Element[n]) > 0.0:
				weak = true
				break
	if weak:   # exploiting a weakness is worth aiming for (combat.json weakness_bonus)
		raw *= 1.0 + float(BattleRules.cfg().get("weakness_bonus", 0.0))
	# Talents (data/talents.json): attacker's damage bonuses, target's damage reduction
	if attacker.talents or target.talents:
		var ctx = TalentManager.hit_context(attacker, target, is_physical, skill, damage_type)
		if attacker.talents:
			raw *= attacker.talents.damage_mult(ctx)
		if target.talents:
			raw *= target.talents.defense_mult(ctx)
	# A riposte after a Perfect Guard (combat.json rhythm)
	if attacker.get_meta("riposte", false):
		raw *= 1.0 + float(rhythm().get("riposte_bonus", 0.0))
	# A charged (telegraphed) strike hits harder
	if attacker.get_meta("charged_strike", false):
		raw *= float(BattleRules.cfg().get("intents", {}).get("charge_power_mult", 1.5))
	# Broken enemies take extra damage until their skipped turn (BattleRules)
	if target.get_meta("broken", false):
		raw *= 1.0 + float(BattleRules.cfg().get("break", {}).get("broken_damage_bonus", 0.3))
	return raw * mitigation(defense)

## Talent lifesteal after a hit landed: heals the attacker. Returns HP healed.
static func apply_lifesteal(attacker: CharacterData, target: CharacterData, dealt: float, is_physical: bool, skill = null, damage_type: int = -1) -> int:
	if attacker == null or dealt <= 0 or not attacker.is_alive():
		return 0
	var f = attacker.talents.lifesteal(TalentManager.hit_context(attacker, target, is_physical, skill, damage_type)) if attacker.talents else 0.0
	if attacker.get_meta("elite_affix", "") == "vampiric":   # elite affix (data/elites.json)
		f += float(EliteAffixes.affix("vampiric").get("lifesteal", 0.3))
	if f <= 0.0:
		return 0
	return attacker.heal(int(round(dealt * f)))

static func roll_crit(attacker: CharacterData) -> float:
	"""Returns the damage multiplier: 1.0, or 1.5-2.0 on a crit."""
	if RandomManager.randf() < attacker.critical_hit_rate:
		return CRIT_MULT_MIN + RandomManager.randf() * (CRIT_MULT_MAX - CRIT_MULT_MIN)
	return 1.0

static func finalize(damage: float) -> int:
	return max(MIN_DAMAGE, int(round(damage)))

static func heal_amount(caster: CharacterData, skill_power: float) -> int:
	var bonus = caster.talents.heal_bonus() if caster.talents else 0.0
	return int((skill_power + caster.spell_power * HEAL_SPELL_POWER_SCALE) * (1.0 + bonus))

static func buff_amount(target: CharacterData, attribute: Skill.AttributeTarget, skill_power: float) -> int:
	var attr_name = Skill.AttributeTarget.keys()[attribute].to_lower()
	var base = float(target.get(attr_name)) if attr_name in target else 0.0
	return max(1, int(round(base * skill_power * BUFF_PERCENT_PER_POWER)))

## Stored duration for effects applied by BUFF/DEBUFF skills (see BUFF_DURATION_BONUS).
static func effect_duration(skill_duration: int) -> int:
	return skill_duration + BUFF_DURATION_BONUS

static func status_procs(is_damage_skill: bool, user: CharacterData = null) -> bool:
	var chance = DAMAGE_SKILL_STATUS_CHANCE + (user.talents.status_chance_bonus() if user and user.talents else 0.0)
	return (not is_damage_skill) or RandomManager.randf() < chance

# --- Equipment helpers ---

## Fraction of the target's physical defense this attacker ignores (gear "armor_penetration").
static func get_armor_penetration(c: CharacterData) -> float:
	return clamp(float(c.armor_penetration), 0.0, MAX_ARMOR_PENETRATION)

static func get_armor(c: CharacterData) -> float:
	var total := 0.0
	for slot in ["head", "chest", "hands", "legs", "feet", "off_hand"]:
		var item = c.equipment.get(slot)
		if item and item is Equipment:
			total += item.armor_value
	return total

static func get_weapon_damage(c: CharacterData) -> float:
	var weapon = c.equipment.get("main_hand")
	if weapon and weapon is Equipment:
		return weapon.damage
	return 0.0
