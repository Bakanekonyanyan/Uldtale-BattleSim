# res://scripts/resources/ElementalDamage.gd
# Handles elemental damage calculations, resistances, and weaknesses
# Integrates with existing status effect system

class_name ElementalDamage
extends RefCounted
# Elemental types mapped to their associated status effects
enum Element {
	NONE,
	EARTH,      # Poison
	FIRE,       # Burn
	ICE,        # Freeze
	WIND,       # Bleed
	LIGHTNING,  # Shock
	HOLY,       # Confused/Blind
	DARK        # Sleep/Blind
}

# Map elements to their primary status effect
const ELEMENT_TO_STATUS = {
	Element.EARTH: Skill.StatusEffect.POISON,
	Element.FIRE: Skill.StatusEffect.BURN,
	Element.ICE: Skill.StatusEffect.FREEZE,
	Element.WIND: Skill.StatusEffect.BLEED,
	Element.LIGHTNING: Skill.StatusEffect.SHOCK,
	Element.HOLY: Skill.StatusEffect.CONFUSED,
	Element.DARK: Skill.StatusEffect.SLEEP
}

# Alternative status effects for some elements
const ELEMENT_SECONDARY_STATUS = {
	Element.HOLY: Skill.StatusEffect.BLIND,
	Element.DARK: Skill.StatusEffect.BLIND
}

# Elemental color coding for UI
const ELEMENT_COLORS = {
	Element.EARTH: "green",
	Element.FIRE: "orange",
	Element.ICE: "cyan",
	Element.WIND: "lightgreen",
	Element.LIGHTNING: "yellow",
	Element.HOLY: "gold",
	Element.DARK: "purple"
}

# Calculate final damage after elemental modifiers
static func calculate_elemental_damage(
	base_damage: float,
	element: Element,
	attacker_bonus: float,
	target_resistance: float,
	target_weakness: float
) -> Dictionary:
	"""
	Returns: {
		damage: final damage amount,
		multiplier: total multiplier applied,
		is_resistant: was damage reduced?,
		is_weak: was damage amplified?
	}
	"""
	if element == Element.NONE:
		return {
			"damage": base_damage,
			"multiplier": 1.0,
			"is_resistant": false,
			"is_weak": false
		}
	
	# Start with attacker's elemental bonus
	var total_multiplier = 1.0 + attacker_bonus
	
	# Apply target's resistance (reduces damage)
	total_multiplier *= (1.0 - target_resistance)
	
	# Apply target's weakness (increases damage)
	total_multiplier *= (1.0 + target_weakness)
	
	# Ensure minimum 10% damage gets through
	total_multiplier = max(total_multiplier, 0.1)
	
	var final_damage = base_damage * total_multiplier
	
	return {
		"damage": final_damage,
		"multiplier": total_multiplier,
		"is_resistant": target_resistance > 0,
		"is_weak": target_weakness > 0
	}

# Get status effect proc chance based on element
static func get_status_proc_chance(element: Element, base_chance: float = 0.3) -> float:
	"""Returns the chance to apply status effect from elemental attack"""
	if element == Element.NONE:
		return 0.0
	
	# Different elements have different proc rates
	match element:
		Element.EARTH, Element.FIRE:
			return base_chance * 1.2  # 36% default
		Element.ICE, Element.LIGHTNING:
			return base_chance * 1.0  # 30% default
		Element.WIND:
			return base_chance * 1.5  # 45% default (bleed is easier to inflict)
		Element.HOLY, Element.DARK:
			return base_chance * 0.8  # 24% default (control effects are more powerful)
	
	return base_chance

# Try to apply status effect from elemental attack
static func try_apply_status(
	element: Element,
	target: CharacterData,
	duration: int = 3,
	chance_override: float = -1.0
) -> bool:
	"""Attempt to apply elemental status effect to target"""
	if element == Element.NONE:
		return false
	
	if not ELEMENT_TO_STATUS.has(element):
		return false
	
	var proc_chance = chance_override if chance_override >= 0 else get_status_proc_chance(element)
	
	if randf() < proc_chance:
		var status = ELEMENT_TO_STATUS[element]
		target.apply_status_effect(status, duration)
		
		# Some elements have chance for secondary effect
		if ELEMENT_SECONDARY_STATUS.has(element) and randf() < 0.15:
			var secondary = ELEMENT_SECONDARY_STATUS[element]
			target.apply_status_effect(secondary, duration - 1)
		
		return true
	
	return false

# Get descriptive name for element
static func get_element_name(element: Element) -> String:
	return Element.keys()[element].capitalize()

# Get color for UI display
static func get_element_color(element: Element) -> String:
	return ELEMENT_COLORS.get(element, "white")

# Get damage type message for combat log
static func get_damage_message(
	attacker_name: String,
	target_name: String,
	damage: int,
	element: Element,
	is_weak: bool,
	is_resistant: bool
) -> String:
	var element_name = get_element_name(element)
	var color = get_element_color(element)
	
	var msg = "%s deals [color=%s]%d %s damage[/color] to %s" % [
		attacker_name,
		color,
		damage,
		element_name,
		target_name
	]
	
	if is_weak:
		msg += " [color=orange](WEAK!)[/color]"
	elif is_resistant:
		msg += " [color=cyan](RESIST)[/color]"
	
	return msg
