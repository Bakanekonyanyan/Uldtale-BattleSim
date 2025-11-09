# res://scripts/resources/Item.gd
class_name Item
extends Resource

enum ItemType { CONSUMABLE, MATERIAL, TREASURE, INGREDIENT, WEAPON, ARMOR, KEY_ITEM }
enum ConsumableType { DAMAGE, HEAL, BUFF, DEBUFF, RESTORE, CURE }

@export var id: String
@export var name: String
@export var description: String
@export var item_type: ItemType
@export var value: int  # Value in copper
@export var stackable: bool = false
@export var max_stack: int = 1

# For consumables
@export var consumable_type: ConsumableType
@export var effect_power: int
@export var effect_duration: int
@export var status_effect: Skill.StatusEffect = Skill.StatusEffect.NONE
@export var buff_type: String = ""  # ATTACK, DODGE, etc.
@export var poison_chance: float = 1.0  # For special items like dung
@export var combat_usable: bool = false

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
		item.effect_power = data.effect_power
		item.effect_duration = data.effect_duration
		item.combat_usable = data.get("combat_usable", false)
		
		# Optional status effect
		if data.has("status_effect"):
			item.status_effect = Skill.StatusEffect[data.status_effect]
		
		# Optional buff type
		item.buff_type = data.get("buff_type", "")
		
		# Special chance modifiers
		item.poison_chance = data.get("poison_chance", 1.0)
	
	return item

# In Item.gd
func use(user: CharacterData, targets: Array) -> String:
	print("Using item: ", name, " (ID: ", id, ")")
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
	
	# Remove the item from inventory after use
	if user.inventory.remove_item(id, 1): 
		print("Item removed from inventory: ", id)
	else:
		print("Failed to remove item from inventory: ", id)
	
	return result

func deal_damage(user: CharacterData, targets: Array) -> String:
	var total_damage = 0
	for target in targets:
		var damage = effect_power
		target.take_damage(damage)
		total_damage += damage
		
		# Apply status effect if present
		if status_effect != Skill.StatusEffect.NONE:
			# Special handling for items with chance (like dung)
			if poison_chance < 1.0:
				if randf() <= poison_chance:
					target.apply_status_effect(status_effect, effect_duration)
					return "%s dealt %d damage and inflicted %s!" % [name, total_damage, Skill.StatusEffect.keys()[status_effect]]
			else:
				target.apply_status_effect(status_effect, effect_duration)
				return "%s dealt %d damage and inflicted %s for %d turns!" % [name, total_damage, Skill.StatusEffect.keys()[status_effect], effect_duration]
	
	return "%s dealt %d damage to %d target(s)" % [name, total_damage, targets.size()]

func heal(user: CharacterData, targets: Array) -> String:
	var total_heal = 0
	for target in targets:
		var heal_amount = effect_power
		target.heal(heal_amount)
		total_heal += heal_amount
	return "%s healed %d HP to %d target(s)" % [name, total_heal, targets.size()]

func apply_buff(user: CharacterData, targets: Array) -> String:
	for target in targets:
		if buff_type == "ATTACK":
			target.apply_buff(Skill.AttributeTarget.STRENGTH, effect_power, effect_duration)
		elif buff_type == "DODGE":
			# Temporarily increase dodge chance
			target.dodge += effect_power / 100.0
			# You may want to track this separately to remove later
	return "%s applied %s buff to %d target(s) for %d turns" % [name, buff_type, targets.size(), effect_duration]

func apply_debuff(user: CharacterData, targets: Array) -> String:
	for target in targets:
		if status_effect != Skill.StatusEffect.NONE:
			target.apply_status_effect(status_effect, effect_duration)
	return "%s applied debuff to %d target(s)" % [name, targets.size()]

func restore(user: CharacterData, targets: Array) -> String:
	var total_restore = 0
	for target in targets:
		var restore_amount = effect_power
		target.restore_mp(restore_amount)
		total_restore += restore_amount
	return "%s restored %d MP to %d target(s)" % [name, total_restore, targets.size()]

func cure_status(user: CharacterData, targets: Array) -> String:
	for target in targets:
		# Clear all status effects
		target.status_effects.clear()
		# Also heal if specified
		if effect_power > 0:
			target.heal(effect_power)
	
	if effect_power > 0:
		return "%s cured all status effects and healed %d HP!" % [name, effect_power]
	else:
		return "%s cured all status effects!" % name
