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
# Skill power is a PERCENT of the target's base attribute (power 40 = +/-40%).
# It used to be added as flat stat points: Roar (40) took 40 Agility off a
# level-1 hero with ~6, and the boss's Royal Decree added +60 Strength.
const BUFF_PERCENT_PER_POWER := 0.01

# --- Basic attack resource regen ---
const ATTACK_RESOURCE_REGEN := 0.08  # basic attacks restore 8% max MP and SP

# =============================================================

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
## skill_power = 0 for basic attacks.
static func hit_damage(attacker: CharacterData, target: CharacterData, is_physical: bool, skill_power: float = 0.0) -> float:
	var offense = physical_offense(attacker) if is_physical else magical_offense(attacker)
	var defense = physical_defense(target) if is_physical else magical_defense(target)
	var raw = offense * BASE_SCALE * (1.0 + skill_power * SKILL_POWER_SCALE)
	raw *= attacker.damage_multiplier  # enemy tuning (EnemyFactory), 1.0 for players
	raw *= MomentumSystem.get_damage_multiplier() if attacker.is_player else 1.0
	return raw * mitigation(defense)

static func roll_crit(attacker: CharacterData) -> float:
	"""Returns the damage multiplier: 1.0, or 1.5-2.0 on a crit."""
	if RandomManager.randf() < attacker.critical_hit_rate:
		return CRIT_MULT_MIN + RandomManager.randf() * (CRIT_MULT_MAX - CRIT_MULT_MIN)
	return 1.0

static func finalize(damage: float) -> int:
	return max(MIN_DAMAGE, int(round(damage)))

static func heal_amount(caster: CharacterData, skill_power: float) -> int:
	return int(skill_power + caster.spell_power * HEAL_SPELL_POWER_SCALE)

static func buff_amount(target: CharacterData, attribute: Skill.AttributeTarget, skill_power: float) -> int:
	var attr_name = Skill.AttributeTarget.keys()[attribute].to_lower()
	var base = float(target.get(attr_name)) if attr_name in target else 0.0
	return max(1, int(round(base * skill_power * BUFF_PERCENT_PER_POWER)))

static func status_procs(is_damage_skill: bool) -> bool:
	return (not is_damage_skill) or RandomManager.randf() < DAMAGE_SKILL_STATUS_CHANCE

# --- Equipment helpers ---

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
