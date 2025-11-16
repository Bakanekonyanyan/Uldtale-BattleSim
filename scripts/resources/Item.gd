# res://scripts/resources/Item.gd
class_name Item
extends Resource

enum ItemType { CONSUMABLE, MATERIAL, TREASURE, INGREDIENT, WEAPON, ARMOR, KEY_ITEM }
enum ConsumableType { DAMAGE, HEAL, BUFF, DEBUFF, RESTORE, CURE }

@export var id: String
@export var name: String
@export var description: String
@export var item_type: ItemType
@export var value: int
@export var stackable: bool = false
@export var max_stack: int = 1

# For consumables
@export var consumable_type: ConsumableType
@export var effect_power: int
@export var effect_duration: int
@export var status_effect: Skill.StatusEffect = Skill.StatusEffect.NONE
@export var buff_type: String = ""
@export var poison_chance: float = 1.0
@export var combat_usable: bool = false
@export var effect_percent: float = 0.0
@export var is_percentage_based: bool = false

static func create_from_dict(item_id: String, data: Dictionary) -> Item:
	var item = Item.new()
	item.id = item_id
	item.name = data.name
	item.description = data.description
	item.item_type = ItemType[data.item_type]
	item.value = data.value
	item.stackable = data.get("stackable", false)
	item.max_stack = data.get("max_stack", 1)
	
	if item.item_type == ItemType.CONSUMABLE:
		item.consumable_type = ConsumableType[data.consumable_type]
		item.combat_usable = data.get("combat_usable", false)
		
		item.is_percentage_based = data.get("is_percentage_based", false)
		
		if item.is_percentage_based:
			item.effect_percent = data.get("effect_percent", 0.0)
			item.effect_power = 0
		else:
			item.effect_power = data.effect_power
			item.effect_percent = 0.0
		
		item.effect_duration = data.effect_duration
		
		if data.has("status_effect"):
			item.status_effect = Skill.StatusEffect[data.status_effect]
		
		item.buff_type = data.get("buff_type", "")
		item.poison_chance = data.get("poison_chance", 1.0)
	
	return item

func use(user: CharacterData, targets: Array) -> String:
	if item_type != ItemType.CONSUMABLE:
		return "This item cannot be used in battle."
	
	var result = ""
	match consumable_type:
		ConsumableType.DAMAGE:
			result = deal_damage(user, targets)
		ConsumableType.HEAL:
			result = heal(user, targets)
		ConsumableType.BUFF:
			result = apply_buff(user, targets)
		ConsumableType.DEBUFF:
			result = apply_debuff(user, targets)
		ConsumableType.RESTORE:
			result = restore(user, targets)
		ConsumableType.CURE:
			result = cure_status(user, targets)
	
	return result

func heal(user: CharacterData, targets: Array) -> String:
	var total_heal = 0
	
	for target in targets:
		var heal_amount = 0
		
		if is_percentage_based:
			heal_amount = int(target.max_hp * effect_percent)
		else:
			heal_amount = effect_power
		
		target.heal(heal_amount)
		total_heal += heal_amount
	
	if is_percentage_based:
		return "%s restored %.0f%% HP (%d HP) to %d target(s)" % [
			name, effect_percent * 100, total_heal, targets.size()
		]
	else:
		return "%s healed %d HP to %d target(s)" % [name, total_heal, targets.size()]

func restore(user: CharacterData, targets: Array) -> String:
	var total_restore = 0
	
	for target in targets:
		var restore_amount = 0
		
		if is_percentage_based:
			var mp_restore = int(target.max_mp * effect_percent)
			var sp_restore = int(target.max_sp * effect_percent)
			target.restore_mp(mp_restore)
			target.restore_sp(sp_restore)
			restore_amount = mp_restore + sp_restore
		else:
			target.restore_mp(effect_power)
			restore_amount = effect_power
		
		total_restore += restore_amount
	
	if is_percentage_based:
		return "%s restored %.0f%% MP/SP to %d target(s)" % [
			name, effect_percent * 100, targets.size()
		]
	else:
		return "%s restored %d MP to %d target(s)" % [name, total_restore, targets.size()]

func deal_damage(user: CharacterData, targets: Array) -> String:
	var total_damage = 0
	
	for target in targets:
		var damage = 0
		
		if is_percentage_based:
			damage = int(target.max_hp * effect_percent)
		else:
			damage = effect_power
		
		target.take_damage(damage)
		total_damage += damage
		
		if status_effect != Skill.StatusEffect.NONE:
			if poison_chance < 1.0:
				if RandomManager.randf() <= poison_chance:
					target.apply_status_effect(status_effect, effect_duration)
					return "%s dealt %d damage and inflicted %s!" % [
						name, total_damage, Skill.StatusEffect.keys()[status_effect]
					]
			else:
				target.apply_status_effect(status_effect, effect_duration)
				return "%s dealt %d damage and inflicted %s for %d turns!" % [
					name, total_damage, Skill.StatusEffect.keys()[status_effect], effect_duration
				]
	
	return "%s dealt %d damage to %d target(s)" % [name, total_damage, targets.size()]

# ✅ FIX: Corrected buff application using buff_manager and effect_percent
func apply_buff(user: CharacterData, targets: Array) -> String:
	print("[ITEM DEBUG] apply_buff called: %s | buff_type=%s | effect_percent=%.2f | effect_power=%d | duration=%d" % [
		name, buff_type, effect_percent, effect_power, effect_duration
	])
	
	var buff_value = 0
	if is_percentage_based:
		# Use effect_percent for percentage-based buffs
		buff_value = int(effect_percent * 100)  # Convert 0.5 → 50
	else:
		buff_value = effect_power
	
	for target in targets:
		if buff_type == "ATTACK":
			# Apply STRENGTH buff via buff_manager
			target.apply_buff(Skill.AttributeTarget.STRENGTH, buff_value, effect_duration)
			print("[ITEM DEBUG] Applied STRENGTH buff: +%d for %d turns" % [buff_value, effect_duration])
		
		elif buff_type == "DODGE":
			# ✅ FIX: Use buff_manager for AGILITY (affects dodge calculation)
			# OR use a custom dodge buff if your BuffDebuffManager supports it
			# For now, we'll use AGILITY as it affects dodge:
			target.apply_buff(Skill.AttributeTarget.AGILITY, buff_value, effect_duration)
			print("[ITEM DEBUG] Applied AGILITY buff (dodge): +%d for %d turns" % [buff_value, effect_duration])
		
		else:
			print("[ITEM DEBUG] WARNING: Unknown buff_type '%s'" % buff_type)
	
	if is_percentage_based:
		return "%s applied %s buff (+%.0f%%) to %d target(s) for %d turns" % [
			name, buff_type, effect_percent * 100, targets.size(), effect_duration
		]
	else:
		return "%s applied %s buff (+%d) to %d target(s) for %d turns" % [
			name, buff_type, buff_value, targets.size(), effect_duration
		]

func apply_debuff(user: CharacterData, targets: Array) -> String:
	for target in targets:
		if status_effect != Skill.StatusEffect.NONE:
			target.apply_status_effect(status_effect, effect_duration)
	return "%s applied debuff to %d target(s)" % [name, targets.size()]

# ✅ FIX: Corrected cure logic to use status_manager properly
func cure_status(user: CharacterData, targets: Array) -> String:
	print("[ITEM DEBUG] cure_status called: %s | status_effect=%s | effect_power=%d | is_percentage=%s" % [
		name, 
		Skill.StatusEffect.keys()[status_effect] if status_effect != Skill.StatusEffect.NONE else "ALL",
		effect_power,
		is_percentage_based
	])
	
	var heal_amount = 0
	if is_percentage_based and effect_percent > 0:
		# Calculate heal from percentage (e.g., holy_water)
		heal_amount = int(targets[0].max_hp * effect_percent) if not targets.is_empty() else 0
	elif effect_power > 0:
		heal_amount = effect_power
	
	for target in targets:
		# Check if specific status effect is defined (antidote, coolroot, etc.)
		if status_effect != Skill.StatusEffect.NONE:
			# ✅ FIX: Use status_manager to remove specific effect
			if target.status_manager and target.status_manager.active_effects.has(status_effect):
				var msg = target.status_manager.remove_effect(status_effect)
				print("[ITEM DEBUG] Removed specific effect: %s" % msg)
			else:
				print("[ITEM DEBUG] Target does not have %s" % Skill.StatusEffect.keys()[status_effect])
		else:
			# Clear ALL status effects (e.g., holy_water)
			# ✅ FIX: Use status_manager instead of deprecated property
			if target.status_manager:
				target.status_manager.clear_all_effects()
				print("[ITEM DEBUG] Cleared all status effects")
		
		# Apply healing if specified
		if heal_amount > 0:
			target.heal(heal_amount)
			print("[ITEM DEBUG] Healed %d HP" % heal_amount)
	
	# Build result message
	var result = ""
	if status_effect != Skill.StatusEffect.NONE:
		# Specific cure
		result = "%s cured %s" % [name, Skill.StatusEffect.keys()[status_effect]]
	else:
		# Cure all
		result = "%s cured all status effects" % name
	
	if heal_amount > 0:
		if is_percentage_based:
			result += " and healed %.0f%% HP (%d HP)!" % [effect_percent * 100, heal_amount]
		else:
			result += " and healed %d HP!" % heal_amount
	else:
		result += "!"
	
	return result
