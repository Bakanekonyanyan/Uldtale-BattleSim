# res://scenes/InventoryScene.gd
extends Control

# In InventoryScene.gd, add item info display:

var player_character: CharacterData

@onready var item_list = $UI/ItemList
@onready var use_button = $UI/UseButton
@onready var back_button = $UI/BackButton
@onready var capacity_label = $UI/CapacityLabel
@onready var item_info_label = $UI/ItemInfoLabel  # ADD THIS NODE TO SCENE

func _ready():
	player_character = CharacterManager.get_current_character()
	if not player_character:
		print("Oops! No character loaded.")
		return
	
	refresh_inventory()
	
	use_button.connect("pressed", Callable(self, "_on_use_pressed"))
	back_button.connect("pressed", Callable(self, "_on_back_pressed"))
	item_list.connect("item_selected", Callable(self, "_on_item_selected"))
	
	# Initialize item info
	clear_item_info()

func refresh_inventory():
	item_list.clear()
	var index = 0
	
	for item_id in player_character.inventory.items:
		var item_data = player_character.inventory.items[item_id]
		var item = item_data.item
		
		if item.item_type == Item.ItemType.CONSUMABLE:
			item_list.add_item("%s (x%d)" % [item.name, item_data.quantity])
			index += 1
	
	# Update capacity display
	update_capacity_display()
	clear_item_info()

func update_capacity_display():
	if capacity_label:
		var current = player_character.inventory.items.size()
		var max_cap = player_character.inventory.capacity
		capacity_label.text = "Inventory: %d/%d" % [current, max_cap]

func _on_item_selected(index):
	use_button.disabled = false
	
	# Get the selected consumable
	var consumable_items = []
	for item_id in player_character.inventory.items:
		var item = player_character.inventory.items[item_id].item
		if item.item_type == Item.ItemType.CONSUMABLE:
			consumable_items.append(item)
	
	if index >= 0 and index < consumable_items.size():
		display_item_info(consumable_items[index])

func display_item_info(item: Item):
	if not item_info_label:
		return
	
	var info_text = ""
	
	if item_info_label is RichTextLabel:
		item_info_label.bbcode_enabled = true
		
		info_text = "[b]%s[/b]\n\n%s\n\n" % [item.name, item.description]
		
		if item.item_type == Item.ItemType.CONSUMABLE:
			info_text += "[color=cyan][b]Effect:[/b][/color]\n"
			
			match item.consumable_type:
				Item.ConsumableType.DAMAGE:
					info_text += "  Deals %d damage\n" % item.effect_power
					if item.status_effect != Skill.StatusEffect.NONE:
						var effect_name = Skill.StatusEffect.keys()[item.status_effect]
						info_text += "  Inflicts [color=purple]%s[/color] for %d turns\n" % [effect_name, item.effect_duration]
				Item.ConsumableType.HEAL:
					info_text += "  Restores %d HP\n" % item.effect_power
				Item.ConsumableType.RESTORE:
					info_text += "  Restores %d MP/SP\n" % item.effect_power
				Item.ConsumableType.BUFF:
					info_text += "  Increases %s by %d for %d turns\n" % [item.buff_type, item.effect_power, item.effect_duration]
				Item.ConsumableType.CURE:
					info_text += "  Cures all status effects\n"
					if item.effect_power > 0:
						info_text += "  Restores %d HP\n" % item.effect_power
		
		item_info_label.text = info_text
	else:
		# Fallback for regular Label
		info_text = "%s\n\n%s" % [item.name, item.description]
		item_info_label.text = info_text

func clear_item_info():
	if item_info_label:
		item_info_label.text = "Select an item to view details"

func _on_use_pressed():
	var selected_items = item_list.get_selected_items()
	if selected_items.size() > 0:
		var item_index = selected_items[0]
		var item_id = player_character.inventory.items.keys()[item_index]
		var item = player_character.inventory.items[item_id].item
		if item.item_type == Item.ItemType.CONSUMABLE:
			var result = item.use(player_character, [player_character])
			print(result)
			refresh_inventory()

func _on_back_pressed():
	CharacterManager.save_character(player_character)
	SceneManager.return_to_previous_scene()
