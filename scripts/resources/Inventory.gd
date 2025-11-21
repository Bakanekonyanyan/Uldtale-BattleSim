# Inventory.gd
class_name Inventory
extends Resource

@export var items: Dictionary = {}  # Dictionary of item_name: {item: Item, quantity: int}
@export var capacity: int = 30

func add_item(item: Item, quantity: int = 1) -> bool:
	# Equipment should never stack - each piece is unique with its own rarity
	if item is Equipment:
		# Generate a unique key for this equipment piece
		var unique_key = "%s_%d" % [item.id, Time.get_ticks_msec()]
		
		# Store the key in the equipment so we can remove it later
		item.inventory_key = unique_key
		
		# Make sure we don't exceed capacity
		if items.size() >= capacity:
			print("❌ Inventory is full, can't add ", item.display_name)
			return false
		
		# Add as unique item with quantity 1
		items[unique_key] = {"item": item, "quantity": 1}
		print(" Added unique equipment: '%s' (rarity: %s, damage: %d, armor: %d, mods: %s) with key: %s" % [
			item.display_name, 
			item.rarity, 
			item.damage, 
			item.armor_value,
			item.stat_modifiers,
			unique_key
		])
		return true
	
	# Regular items can stack
	if items.size() >= capacity and item.id not in items:
		print("❌ Inventory is full, can't add ", item.display_name)
		return false
	
	if item.id in items:
		items[item.id].quantity += quantity
	else:
		items[item.id] = {"item": item, "quantity": quantity}
	
	print(" Added %dx %s to inventory" % [quantity, item.display_name])
	return true

func remove_item(item_id: String, quantity: int = 1) -> bool:
	if item_id not in items or items[item_id].quantity < quantity:
		print("❌ Failed to remove item from inventory: ", item_id)
		return false
	
	items[item_id].quantity -= quantity
	if items[item_id].quantity == 0:
		items.erase(item_id)
	
	print(" Successfully removed %d of item %s from inventory" % [quantity, item_id])
	return true

func get_item(item_name: String) -> Item:
	return items[item_name].item if item_name in items else null

func get_quantity(item_name: String) -> int:
	return items[item_name].quantity if item_name in items else 0

func clear():
	items.clear()
