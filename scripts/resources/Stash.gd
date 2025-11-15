# Stash.gd
class_name Stash
extends Inventory

func _init():
	# Don't call super._init() since Resource doesn't have parameters
	items = {}  # Initialize the dictionary
	capacity = 999999  # Effectively unlimited

func add_item(item: Item, quantity: int = 1) -> bool:
	# Equipment should never stack - each piece is unique with its own rarity
	if item is Equipment:
		# Generate a unique key for this equipment piece
		var unique_key = "%s_%d" % [item.id, Time.get_ticks_msec()]
		
		# Store the key in the equipment so we can remove it later
		item.inventory_key = unique_key
		
		# ✅ NO CAPACITY CHECK - stash has unlimited space
		
		# Add as unique item with quantity 1
		items[unique_key] = {"item": item, "quantity": 1}
		print("✅ Added unique equipment to stash: '%s' (rarity: %s, damage: %d, armor: %d, mods: %s) with key: %s" % [
			item.name, 
			item.rarity, 
			item.damage, 
			item.armor_value,
			item.stat_modifiers,
			unique_key
		])
		return true
	
	# Regular items can stack - no capacity check needed for stash
	if item.id in items:
		items[item.id].quantity += quantity
	else:
		items[item.id] = {"item": item, "quantity": quantity}
	
	print("✅ Added %dx %s to stash" % [quantity, item.name])
	return true
