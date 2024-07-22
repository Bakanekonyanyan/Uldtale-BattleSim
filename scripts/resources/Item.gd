# res://scripts/resources/Item.gd
class_name Item
extends Resource

enum ItemType { CONSUMABLE, MATERIAL, TREASURE, INGREDIENT, WEAPON, ARMOR, KEY_ITEM }
enum ConsumableType { DAMAGE, HEAL, BUFF, DEBUFF, RESTORE }

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
		target.apply_buff(Skill.AttributeTarget.STRENGTH, effect_power, effect_duration)  # Example buff
	return "%s applied a buff to %d target(s)" % [name, targets.size()]

func apply_debuff(user: CharacterData, targets: Array) -> String:
	for target in targets:
		target.apply_debuff(Skill.AttributeTarget.STRENGTH, effect_power, effect_duration)  # Example debuff
	return "%s applied a debuff to %d target(s)" % [name, targets.size()]

func restore(user: CharacterData, targets: Array) -> String:
	var total_restore = 0
	for target in targets:
		var restore_amount = effect_power
		target.restore_mp(restore_amount)
		total_restore += restore_amount
	return "%s restored %d MP to %d target(s)" % [name, total_restore, targets.size()]
