# LootManager.gd
extends Node

enum Rarity {COMMON, UNCOMMON, RARE, EPIC, LEGENDARY, SET}

const RARITY_COLORS = {
	Rarity.COMMON: Color.WHITE,
	Rarity.UNCOMMON: Color.BLUE,
	Rarity.RARE: Color.YELLOW,
	Rarity.EPIC: Color.PURPLE,
	Rarity.LEGENDARY: Color.ORANGE,
	Rarity.SET: Color.GREEN
}

const RARITY_NAMES = {
	Rarity.COMMON: "Common",
	Rarity.UNCOMMON: "Uncommon",
	Rarity.RARE: "Rare",
	Rarity.EPIC: "Epic",
	Rarity.LEGENDARY: "Legendary",
	Rarity.SET: "Set"
}

const RARITY_MULTIPLIERS = {
	Rarity.COMMON: 1.0,
	Rarity.UNCOMMON: 1.5,
	Rarity.RARE: 2.0,
	Rarity.EPIC: 2.5,
	Rarity.LEGENDARY: 4.0,
	Rarity.SET: 5.0
}

const SET_SLOTS = ["head", "chest", "hands", "legs", "feet", "main_hand", "off_hand"]

func determine_rarity() -> Rarity:
	var roll = randf()
	if roll < 0.6:
		return Rarity.COMMON
	elif roll < 0.8:
		return Rarity.UNCOMMON
	elif roll < 0.93:
		return Rarity.RARE
	elif roll < 0.98:
		return Rarity.EPIC
	elif roll < 0.999:
		return Rarity.LEGENDARY
	else:
		return Rarity.SET

func generate_equipment_with_rarity(base_item: Dictionary) -> Dictionary:
	var rarity = determine_rarity()
	return apply_rarity(base_item.duplicate(), rarity)

func apply_rarity(item: Dictionary, rarity: Rarity) -> Dictionary:
	var rarity_multiplier = RARITY_MULTIPLIERS[rarity]
	item["rarity"] = rarity
	
	if item["type"] == "weapon":
		item["damage"] = int(item["damage"] * rarity_multiplier)
	elif item["type"] == "armor":
		item["armor_value"] = int(item["armor_value"] * rarity_multiplier)
	
	if "attribute_increase" in item:
		if item["attribute_increase"] is int:
			item["attribute_increase"] = int(item["attribute_increase"] * rarity_multiplier)
		elif item["attribute_increase"] is Array:
			item["attribute_increase"] = item["attribute_increase"].map(func(x): return int(x * rarity_multiplier))
	
	item["value"] = int(item["value"] * rarity_multiplier)
	
	return item
	
func apply_set_bonus(item: Equipment, character: CharacterData):
	var set_name = item.set_name
	var set_count = 0
	
	for slot in SET_SLOTS:
		var equipped_item = character.equipment.get(slot)
		if equipped_item and equipped_item.rarity == Rarity.SET and equipped_item.set_name == set_name:
			set_count += 1
	
	if set_count == SET_SLOTS.size():
		# Full set bonus
		var full_multiplier = RARITY_MULTIPLIERS[Rarity.SET]
		var current_multiplier = 1.5  # The base multiplier we applied earlier
		var additional_multiplier = full_multiplier / current_multiplier
		
		item.damage = int(item.damage * additional_multiplier)
		item.armor_value = int(item.armor_value * additional_multiplier)
		
		if item.attribute_increase is int:
			item.attribute_increase = int(item.attribute_increase * additional_multiplier)
		elif item.attribute_increase is Array:
			item.attribute_increase = item.attribute_increase.map(func(x): return int(x * additional_multiplier))
		
		for effect in item.effects:
			if item.effects[effect] is int or item.effects[effect] is float:
				item.effects[effect] *= additional_multiplier
		
		item.value = int(item.value * additional_multiplier)

func get_rarity_color(rarity: Rarity) -> Color:
	return RARITY_COLORS[rarity]

func get_rarity_name(rarity: Rarity) -> String:
	return RARITY_NAMES[rarity]
