# Inventory.gd
class_name Inventory
extends Resource

@export var items: Dictionary = {}  # Dictionary of item_name: {item: Item, quantity: int}
@export var capacity: int = 20

func add_item(item: Item, quantity: int = 1) -> bool:
	if items.size() >= capacity and item.id not in items:
		print("Inventory is full, can't add ", item.name)
		return false
	
	if item.id in items:
		items[item.id].quantity += quantity
	else:
		items[item.id] = {"item": item, "quantity": quantity}
	
	print("Added ", quantity, "x ", item.name, " to inventory")
	return true

func remove_item(item_id: String, quantity: int = 1) -> bool:
	if item_id not in items or items[item_id].quantity < quantity:
		print("Failed to remove item from inventory: ", item_id)
		return false
	
	items[item_id].quantity -= quantity
	if items[item_id].quantity == 0:
		items.erase(item_id)
	
	print("Successfully removed ", quantity, " of item ", item_id, " from inventory")
	return true

func get_item(item_name: String) -> Item:
	return items[item_name].item if item_name in items else null

func get_quantity(item_name: String) -> int:
	return items[item_name].quantity if item_name in items else 0

func clear():
	items.clear()
