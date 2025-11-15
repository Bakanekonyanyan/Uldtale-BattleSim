# res://scripts/autoload/ShopManager.gd
# Manages persistent shop inventory across game sessions
extends Node

# Consumables: unlimited stock, always available
var consumable_inventory: Dictionary = {
	"health_potion": {"price": 25},
	"mana_potion": {"price": 30},
	"stamina_potion": {"price": 30},
	"flame_flask": {"price": 50},
	"frost_crystal": {"price": 50},
	"thunder_orb": {"price": 50},
	"venom_vial": {"price": 50},
	"stone_shard": {"price": 10},
	"rotten_dung": {"price": 10},
	"smoke_bomb": {"price": 15},
	"berserker_brew": {"price": 30},
	"holy_water": {"price": 50},
}

# Equipment: one-time purchases, removed when bought
var equipment_inventory: Dictionary = {}

# NEW: Buyback system (cleared when floor changes)
var buyback_inventory: Dictionary = {}  # item_key -> {item: Item/Equipment, price: int, quantity: int}
var last_floor: int = 0

# Track if shop has been initialized
var shop_initialized: bool = false

func _ready():
	initialize_shop()

func initialize_shop():
	"""Initialize shop with starting equipment - call once per game"""
	if shop_initialized:
		print("ShopManager: Already initialized")
		return
	
	print("ShopManager: Initializing shop with starting equipment...")
	
	equipment_inventory.clear()
	
	# Add one of each common weapon
	_add_common_weapons()
	
	# Add one of each common armor piece
	_add_common_armor()
	
	shop_initialized = true
	print("ShopManager: Shop initialized with %d equipment items" % equipment_inventory.size())

func _add_common_weapons():
	"""Add one of each common weapon type"""
	var weapon_ids = [
		"short_sword",
		"longsword",
		"katana",
		"wakizashi",
		"dagger",
		"mace",
		"axe",
		"spear",
		"scepter",
		"staff",
		"greatsword",
		"lance",
		"curved_greatsword",
		"great_katana",
		"great_hammer",
		"great_axe",
		"halberd",
		"great_staff",
		"buckler",
		"shield",
		"great_shield"
	]
	
	for weapon_id in weapon_ids:
		var equipment = ItemManager.create_equipment_for_floor(weapon_id, 1)
		if equipment:
			equipment.rarity = "common"
			equipment.item_level = 1
			equipment.damage = equipment.damage
			equipment.armor_value = equipment.armor_value
			equipment.stat_modifiers = {}
			equipment.status_effect_type = Skill.StatusEffect.NONE
			equipment.status_effect_chance = 0.0
			equipment.bonus_damage = 0
			
			var template = ItemManager.get_equipment_template(weapon_id)
			if template.has("name"):
				equipment.name = template["name"]
			
			var price = equipment.value
			price = (price / 2.5) 
			
			var unique_key = "%s_%d" % [weapon_id, Time.get_ticks_msec()]
			equipment_inventory[unique_key] = {
				"equipment": equipment,
				"price": price,
				"quantity": 1
			}
			
			print("ShopManager: Added %s (common) for %d copper" % [equipment.name, price])

func _add_common_armor():
	"""Add one of each common armor piece"""
	var armor_ids = [
		"cloth_cap",
		"cloth_robe",
		"cloth_gloves",
		"cloth_pants",
		"cloth_shoes",
		"leather_helm",
		"leather_armor",
		"leather_gloves",
		"leather_leggings",
		"leather_boots",
		"mail_coif",
		"mail_hauberk",
		"mail_gauntlets",
		"mail_chausses",
		"mail_boots",
		"plate_helm",
		"plate_armor",
		"plate_gauntlets",
		"plate_greaves",
		"plate_sabatons"
	]
	
	for armor_id in armor_ids:
		var equipment = ItemManager.create_equipment_for_floor(armor_id, 1)
		if equipment:
			equipment.rarity = "common"
			equipment.item_level = 1
			equipment.damage = equipment.damage
			equipment.armor_value = equipment.armor_value
			equipment.stat_modifiers = {}
			equipment.status_effect_type = Skill.StatusEffect.NONE
			equipment.status_effect_chance = 0.0
			equipment.bonus_damage = 0
			
			var template = ItemManager.get_equipment_template(armor_id)
			if template.has("name"):
				equipment.name = template["name"]
			
			var price = equipment.value
			
			var unique_key = "%s_%d" % [armor_id, Time.get_ticks_msec()]
			equipment_inventory[unique_key] = {
				"equipment": equipment,
				"price": price,
				"quantity": 1
			}
			
			print("ShopManager: Added %s (common) for %d copper" % [equipment.name, price])

func get_consumable_item(item_id: String) -> Item:
	"""Get consumable item (unlimited stock)"""
	return ItemManager.get_item(item_id)

func get_consumable_price(item_id: String) -> int:
	"""Get price for consumable"""
	return consumable_inventory.get(item_id, {}).get("price", 0)

func get_equipment_list() -> Array:
	"""Get list of available equipment"""
	var items = []
	for key in equipment_inventory:
		items.append({
			"key": key,
			"equipment": equipment_inventory[key]["equipment"],
			"price": equipment_inventory[key]["price"],
			"quantity": equipment_inventory[key]["quantity"]
		})
	return items

func purchase_equipment(item_key: String) -> bool:
	"""Purchase equipment (removes from shop inventory)"""
	if not equipment_inventory.has(item_key):
		print("ShopManager: Equipment not found: %s" % item_key)
		return false
	
	var item_data = equipment_inventory[item_key]
	if item_data["quantity"] <= 0:
		print("ShopManager: Equipment out of stock: %s" % item_key)
		return false
	
	equipment_inventory.erase(item_key)
	print("ShopManager: Sold equipment: %s" % item_data["equipment"].name)
	return true

# === NEW: BUYBACK SYSTEM ===

func add_to_buyback(item: Variant, sell_price: int, quantity: int = 1):
	"""Add item to buyback inventory"""
	var buyback_key: String
	
	if item is Equipment:
		# Equipment: use inventory_key or generate unique key
		buyback_key = item.inventory_key if item.inventory_key != "" else "%s_%d" % [item.id, Time.get_ticks_msec()]
	else:
		# Consumables/materials: use item ID
		buyback_key = item.id
	
	# Calculate buyback price (sell price * 1.5, rounded up)
	var buyback_price = int(ceil(sell_price * 1.5))
	
	if buyback_inventory.has(buyback_key):
		# Stack consumables/materials
		if not (item is Equipment):
			buyback_inventory[buyback_key]["quantity"] += quantity
	else:
		buyback_inventory[buyback_key] = {
			"item": item,
			"price": buyback_price,
			"quantity": quantity
		}
	
	print("ShopManager: Added to buyback - %s (x%d) for %d copper" % [item.name, quantity, buyback_price])

func get_buyback_list() -> Array:
	"""Get list of items available for buyback"""
	var items = []
	for key in buyback_inventory:
		items.append({
			"key": key,
			"item": buyback_inventory[key]["item"],
			"price": buyback_inventory[key]["price"],
			"quantity": buyback_inventory[key]["quantity"]
		})
	return items

func buyback_item(item_key: String, quantity: int = 1) -> Dictionary:
	"""Buy back an item from buyback inventory"""
	if not buyback_inventory.has(item_key):
		return {"success": false, "message": "Item not in buyback"}
	
	var buyback_data = buyback_inventory[item_key]
	
	if buyback_data["quantity"] < quantity:
		return {"success": false, "message": "Not enough quantity"}
	
	# Calculate total price
	var total_price = buyback_data["price"] * quantity
	
	# Reduce quantity
	buyback_data["quantity"] -= quantity
	
	# Remove if quantity reaches 0
	if buyback_data["quantity"] <= 0:
		buyback_inventory.erase(item_key)
	
	return {
		"success": true,
		"item": buyback_data["item"],
		"price": total_price,
		"quantity": quantity
	}

func clear_buyback_on_floor_change(new_floor: int):
	"""Clear buyback inventory when floor changes"""
	if new_floor != last_floor:
		print("ShopManager: Floor changed from %d to %d - clearing buyback" % [last_floor, new_floor])
		buyback_inventory.clear()
		last_floor = new_floor

func reset_shop():
	"""Reset shop inventory (for new game/testing)"""
	equipment_inventory.clear()
	buyback_inventory.clear()
	shop_initialized = false
	print("ShopManager: Shop inventory reset")
