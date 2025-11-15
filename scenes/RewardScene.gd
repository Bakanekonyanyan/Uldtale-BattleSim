# RewardScene.gd - ItemList-based reward collection system

extends Control

signal rewards_accepted
signal next_wave
signal next_floor
signal quit_dungeon

var rewards: Dictionary = {}
var player_character: CharacterData
var is_boss_fight: bool = false
var current_floor: int = 1
var max_floor: int = 25
var setup_complete = false
var xp_gained: int = 0

# Track collected items
var collected_items: Dictionary = {}  # item_key -> true

@onready var reward_label: RichTextLabel = $UI/RewardLabel
@onready var continue_button: Button = $UI/ContinueButton
@onready var quit_button: Button = $UI/QuitButton
@onready var next_floor_button: Button = $UI/NextFloorButton
@onready var equip_button = $UI/EquipmentButton
@onready var use_consumable_button = $UI/InventoryButton

# NEW: ItemList-based UI
var reward_items_list: ItemList
var item_info_label: RichTextLabel
var accept_button: Button
var accept_all_button: Button
var dispose_button: Button
var dispose_all_button: Button
var auto_rewards_label: Label

func _ready():
	print("RewardScene: _ready called")
	
	# Restore saved reward state
	var saved_state = SceneManager.get_saved_reward_state()
	if saved_state != null:
		rewards = saved_state.rewards
		xp_gained = saved_state.xp_gained
		
		if saved_state.has("collected_items"):
			collected_items = saved_state.collected_items
		
		if saved_state.has("is_boss_fight"):
			is_boss_fight = saved_state.is_boss_fight
		if saved_state.has("current_floor"):
			current_floor = saved_state.current_floor
		if saved_state.has("max_floor"):
			max_floor = saved_state.max_floor
		
		print("RewardScene: Restored saved state")
		_connect_signals_to_scene_manager()
	
	call_deferred("deferred_setup")

func deferred_setup():
	print("RewardScene: deferred_setup called")
	setup_ui()
	setup_item_list_ui()
	
	if not setup_complete:
		display_rewards()
	
	update_button_visibility()
	setup_complete = true

func setup_ui():
	# Connect existing buttons
	if continue_button:
		if continue_button.is_connected("pressed", Callable(self, "_on_continue_pressed")):
			continue_button.disconnect("pressed", Callable(self, "_on_continue_pressed"))
		continue_button.connect("pressed", Callable(self, "_on_continue_pressed"))
		
	if quit_button:
		if quit_button.is_connected("pressed", Callable(self, "_on_quit_pressed")):
			quit_button.disconnect("pressed", Callable(self, "_on_quit_pressed"))
		quit_button.connect("pressed", Callable(self, "_on_quit_pressed"))
		
	if next_floor_button:
		if next_floor_button.is_connected("pressed", Callable(self, "_on_next_floor_pressed")):
			next_floor_button.disconnect("pressed", Callable(self, "_on_next_floor_pressed"))
		next_floor_button.connect("pressed", Callable(self, "_on_next_floor_pressed"))
		
	if equip_button:
		if equip_button.is_connected("pressed", Callable(self, "_on_equip_pressed")):
			equip_button.disconnect("pressed", Callable(self, "_on_equip_pressed"))
		equip_button.connect("pressed", Callable(self, "_on_equip_pressed"))
		
	if use_consumable_button:
		if use_consumable_button.is_connected("pressed", Callable(self, "_on_use_consumable_pressed")):
			use_consumable_button.disconnect("pressed", Callable(self, "_on_use_consumable_pressed"))
		use_consumable_button.connect("pressed", Callable(self, "_on_use_consumable_pressed"))

func setup_item_list_ui():
	"""Create ItemList-based UI similar to Inventory/Stash"""
	
	# Auto rewards label (XP/Gold - always collected)
	auto_rewards_label = Label.new()
	auto_rewards_label.position = Vector2(320, 40)
	auto_rewards_label.custom_minimum_size = Vector2(300, 60)
	auto_rewards_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(auto_rewards_label)
	
	# ItemList for rewards
	reward_items_list = ItemList.new()
	reward_items_list.position = Vector2(88, 120)
	reward_items_list.custom_minimum_size = Vector2(280, 320)
	reward_items_list.select_mode = ItemList.SELECT_SINGLE
	reward_items_list.item_clicked.connect(_on_reward_item_clicked)
	add_child(reward_items_list)
	
	# Item info display
	item_info_label = RichTextLabel.new()
	item_info_label.position = Vector2(680, 120)
	item_info_label.custom_minimum_size = Vector2(450, 400)
	item_info_label.bbcode_enabled = true
	item_info_label.fit_content = true
	item_info_label.text = "Select an item to view details"
	add_child(item_info_label)
	
	# Action buttons container
	var button_container = VBoxContainer.new()
	button_container.position = Vector2(400, 140)
	button_container.add_theme_constant_override("separation", 10)
	add_child(button_container)
	
	# Accept selected button
	accept_button = Button.new()
	accept_button.text = "Accept Selected"
	accept_button.custom_minimum_size = Vector2(180, 40)
	accept_button.disabled = true
	accept_button.pressed.connect(_on_accept_selected_pressed)
	button_container.add_child(accept_button)
	
	# Accept all button
	accept_all_button = Button.new()
	accept_all_button.text = "Accept All Items"
	accept_all_button.custom_minimum_size = Vector2(180, 40)
	accept_all_button.pressed.connect(_on_accept_all_pressed)
	button_container.add_child(accept_all_button)
	
	# Dispose selected button
	dispose_button = Button.new()
	dispose_button.text = "Dispose Selected"
	dispose_button.custom_minimum_size = Vector2(180, 40)
	dispose_button.disabled = true
	dispose_button.pressed.connect(_on_dispose_selected_pressed)
	button_container.add_child(dispose_button)
	
	# Dispose all button
	dispose_all_button = Button.new()
	dispose_all_button.text = "Dispose All Items"
	dispose_all_button.custom_minimum_size = Vector2(180, 40)
	dispose_all_button.pressed.connect(_on_dispose_all_pressed)
	button_container.add_child(dispose_all_button)

func set_rewards(new_rewards: Dictionary):
	print("RewardScene: set_rewards called")
	rewards = new_rewards
	collected_items.clear()
	
	if is_inside_tree():
		display_rewards()

func set_xp_gained(xp: int):
	print("RewardScene: set_xp_gained called with: ", xp)
	xp_gained = xp
	
	if is_inside_tree():
		display_rewards()

func set_dungeon_info(boss_fight: bool, floor: int, max_floor_val: int):
	is_boss_fight = boss_fight
	current_floor = floor
	max_floor = max_floor_val
	print("RewardScene: Dungeon info set - Boss: ", is_boss_fight, ", Floor: ", current_floor)
	
	if is_inside_tree():
		update_button_visibility()

func set_player_character(character: CharacterData):
	player_character = character
	print("RewardScene: Player character set")
	
	if is_inside_tree():
		display_rewards()

func display_rewards():
	"""Display rewards in ItemList format"""
	if not reward_items_list or not auto_rewards_label:
		print("RewardScene: UI not ready yet")
		return
	
	print("RewardScene: Displaying rewards")
	
	# Show auto-collected rewards
	var auto_text = "Auto-Collected:\n"
	if xp_gained > 0:
		auto_text += "+%d XP\n" % xp_gained
	if rewards.has("currency"):
		auto_text += "+%d Gold" % rewards["currency"]
	
	auto_rewards_label.text = auto_text
	
	# Populate ItemList
	reward_items_list.clear()
	var index = 0
	
	# Add consumables/materials
	for item_id in rewards:
		if item_id in ["currency", "xp", "equipment_instances"]:
			continue
		
		var item = ItemManager.get_item(item_id)
		if item:
			var quantity = rewards[item_id]
			var collected = collected_items.has(item_id)
			
			var display_text = "%s (x%d)" % [item.name, quantity]
			if collected:
				display_text += " [Collected]"
			
			reward_items_list.add_item(display_text)
			
			# Store metadata
			reward_items_list.set_item_metadata(index, {
				"type": "consumable",
				"id": item_id,
				"item": item,
				"quantity": quantity,
				"collected": collected
			})
			
			# Gray out if collected
			if collected:
				reward_items_list.set_item_custom_fg_color(index, Color(0.5, 0.5, 0.5))
			
			index += 1
	
	# Add equipment
	if rewards.has("equipment_instances"):
		var equipment_list = rewards["equipment_instances"]
		for i in range(equipment_list.size()):
			var equipment = equipment_list[i]
			if equipment is Equipment:
				var equip_key = "equip_%d" % i
				var collected = collected_items.has(equip_key)
				
				var display_text = "%s [ilvl %d]" % [equipment.name, equipment.item_level]
				if collected:
					display_text += " [Collected]"
				
				reward_items_list.add_item(display_text)
				
				# Color by rarity
				if not collected:
					var rarity_color = Color(equipment.get_rarity_color())
					reward_items_list.set_item_custom_fg_color(index, rarity_color)
				else:
					reward_items_list.set_item_custom_fg_color(index, Color(0.5, 0.5, 0.5))
				
				# Store metadata
				reward_items_list.set_item_metadata(index, {
					"type": "equipment",
					"key": equip_key,
					"item": equipment,
					"collected": collected
				})
				
				index += 1
	
	print("RewardScene: Populated ItemList with %d items" % index)

func _on_reward_item_clicked(index: int, _at_position: Vector2, _mouse_button_index: int):
	"""Handle item selection"""
	print("Reward item clicked at index: ", index)
	
	var metadata = reward_items_list.get_item_metadata(index)
	if not metadata:
		return
	
	# Enable/disable buttons based on collection status
	var is_collected = metadata.get("collected", false)
	accept_button.disabled = is_collected
	dispose_button.disabled = is_collected
	
	# Display item info
	display_item_info(metadata["item"])

func display_item_info(item: Item):
	"""Display detailed item information"""
	if not item_info_label:
		return
	
	var info_text = ""
	
	if item is Equipment:
		info_text = item.get_full_description()
	else:
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

func _on_accept_selected_pressed():
	"""Accept the selected item"""
	var selected = reward_items_list.get_selected_items()
	if selected.is_empty():
		return
	
	var index = selected[0]
	var metadata = reward_items_list.get_item_metadata(index)
	
	if metadata.get("collected", false):
		print("Item already collected")
		return
	
	# Add to inventory
	if metadata["type"] == "consumable":
		var item = metadata["item"]
		var quantity = metadata["quantity"]
		player_character.inventory.add_item(item, quantity)
		collected_items[metadata["id"]] = true
		print("Accepted: %dx %s" % [quantity, item.name])
	
	elif metadata["type"] == "equipment":
		var equipment = metadata["item"]
		player_character.inventory.add_item(equipment, 1)
		collected_items[metadata["key"]] = true
		print("Accepted: %s" % equipment.name)
	
	# Save and refresh
	SaveManager.save_game(player_character)
	display_rewards()
	item_info_label.text = "Select an item to view details"
	accept_button.disabled = true
	dispose_button.disabled = true

func _on_accept_all_pressed():
	"""Accept all uncollected items"""
	print("Accept all pressed")
	
	# Add consumables/materials
	for item_id in rewards:
		if item_id in ["currency", "xp", "equipment_instances"]:
			continue
		
		if not collected_items.has(item_id):
			var item = ItemManager.get_item(item_id)
			if item:
				var quantity = rewards[item_id]
				player_character.inventory.add_item(item, quantity)
				collected_items[item_id] = true
				print("Accepted: %dx %s" % [quantity, item.name])
	
	# Add equipment
	if rewards.has("equipment_instances"):
		var equipment_list = rewards["equipment_instances"]
		for i in range(equipment_list.size()):
			var equip_key = "equip_%d" % i
			
			if not collected_items.has(equip_key):
				var equipment = equipment_list[i]
				if equipment is Equipment:
					player_character.inventory.add_item(equipment, 1)
					collected_items[equip_key] = true
					print("Accepted: %s" % equipment.name)
	
	# Add auto rewards
	_add_auto_rewards()
	
	# Save and refresh
	SaveManager.save_game(player_character)
	display_rewards()
	item_info_label.text = "All items collected!"

func _on_dispose_selected_pressed():
	"""Dispose of selected item"""
	var selected = reward_items_list.get_selected_items()
	if selected.is_empty():
		return
	
	var index = selected[0]
	var metadata = reward_items_list.get_item_metadata(index)
	
	if metadata.get("collected", false):
		return
	
	# Show confirmation
	var item = metadata["item"]
	var dialog = ConfirmationDialog.new()
	dialog.title = "Dispose Item?"
	dialog.dialog_text = "Are you sure you want to dispose of %s?" % item.name
	dialog.ok_button_text = "Yes, Dispose"
	dialog.cancel_button_text = "Cancel"
	add_child(dialog)
	dialog.popup_centered()
	
	dialog.confirmed.connect(func():
		# Mark as collected but don't add to inventory
		if metadata["type"] == "consumable":
			collected_items[metadata["id"]] = true
		elif metadata["type"] == "equipment":
			collected_items[metadata["key"]] = true
		
		print("Disposed: %s" % item.name)
		display_rewards()
		item_info_label.text = "Item disposed"
		dialog.queue_free()
	)
	
	dialog.canceled.connect(func(): dialog.queue_free())

func _on_dispose_all_pressed():
	"""Dispose of all items"""
	var dialog = ConfirmationDialog.new()
	dialog.title = "Dispose All Items?"
	dialog.dialog_text = "Are you sure you want to dispose of ALL uncollected items?\n\nXP and gold will still be collected."
	dialog.ok_button_text = "Yes, Dispose All"
	dialog.cancel_button_text = "Cancel"
	add_child(dialog)
	dialog.popup_centered()
	
	dialog.confirmed.connect(func():
		# Mark all as collected without adding to inventory
		for item_id in rewards:
			if item_id not in ["currency", "xp", "equipment_instances"]:
				collected_items[item_id] = true
		
		if rewards.has("equipment_instances"):
			var equipment_list = rewards["equipment_instances"]
			for i in range(equipment_list.size()):
				collected_items["equip_%d" % i] = true
		
		# Add auto rewards
		_add_auto_rewards()
		
		SaveManager.save_game(player_character)
		display_rewards()
		item_info_label.text = "All items disposed"
		print("All items disposed")
		dialog.queue_free()
	)
	
	dialog.canceled.connect(func(): dialog.queue_free())

func _add_auto_rewards():
	"""Add XP and currency automatically"""
	if rewards.has("currency"):
		player_character.currency.add(rewards["currency"])
		print("Added currency: ", rewards["currency"])
	
	if xp_gained > 0:
		var old_level = player_character.level
		player_character.gain_xp(xp_gained)
		
		if player_character.level > old_level:
			call_deferred("show_level_up_overlay")
		
		xp_gained = 0

func _all_items_collected() -> bool:
	"""Check if all items have been collected/disposed"""
	for item_id in rewards:
		if item_id in ["currency", "xp", "equipment_instances"]:
			continue
		if not collected_items.has(item_id):
			return false
	
	if rewards.has("equipment_instances"):
		var equipment_list = rewards["equipment_instances"]
		for i in range(equipment_list.size()):
			if not collected_items.has("equip_%d" % i):
				return false
	
	return true

func show_level_up_overlay():
	print("RewardScene: Showing level-up overlay")
	
	# Hide UI during level-up
	if reward_items_list:
		reward_items_list.visible = false
	if accept_button:
		accept_button.visible = false
	if accept_all_button:
		accept_all_button.visible = false
	if dispose_button:
		dispose_button.visible = false
	if dispose_all_button:
		dispose_all_button.visible = false
	
	var level_up_scene = load("res://scenes/LevelUpScene.tscn").instantiate()
	add_child(level_up_scene)
	level_up_scene.setup(player_character)
	
	await level_up_scene.level_up_complete
	level_up_scene.queue_free()
	
	# Restore UI
	if reward_items_list:
		reward_items_list.visible = true
	if accept_button:
		accept_button.visible = true
	if accept_all_button:
		accept_all_button.visible = true
	if dispose_button:
		dispose_button.visible = true
	if dispose_all_button:
		dispose_all_button.visible = true

func _on_continue_pressed():
	if not _all_items_collected():
		show_collection_prompt("continue")
		return
	
	_add_auto_rewards()
	
	rewards.clear()
	collected_items.clear()
	SceneManager.clear_saved_reward_state()
	
	SceneManager.reward_scene_active = false
	SaveManager.save_game(player_character)
	emit_signal("rewards_accepted")

func _on_next_floor_pressed():
	if not _all_items_collected():
		show_collection_prompt("advance to the next floor")
		return
	
	_add_auto_rewards()
	
	rewards.clear()
	collected_items.clear()
	SceneManager.clear_saved_reward_state()
	
	SaveManager.save_game(player_character)
	emit_signal("next_floor")

func _on_quit_pressed():
	# Auto-collect remaining items
	if not _all_items_collected():
		_on_accept_all_pressed()
	
	_add_auto_rewards()
	
	rewards.clear()
	collected_items.clear()
	SceneManager.clear_saved_reward_state()
	
	SaveManager.save_game(player_character)
	SceneManager.reward_scene_active = false
	SceneManager.change_to_town(player_character)

func _on_equip_pressed():
	SceneManager.save_reward_state(rewards, xp_gained, false, collected_items)
	SceneManager.reward_scene_active = true
	SceneManager.push_scene("res://scenes/EquipmentScene.tscn", player_character)

func _on_use_consumable_pressed():
	SceneManager.save_reward_state(rewards, xp_gained, false, collected_items)
	SceneManager.reward_scene_active = true
	SceneManager.push_scene("res://scenes/InventoryScene.tscn", player_character)

func show_collection_prompt(action: String):
	var dialog = ConfirmationDialog.new()
	dialog.title = "Items Remaining"
	dialog.dialog_text = "You must collect or dispose of all items before you can %s!\n\nUse the action buttons to manage items." % action
	dialog.ok_button_text = "OK"
	add_child(dialog)
	dialog.popup_centered()

func _connect_signals_to_scene_manager():
	if SceneManager.has_method("_connect_reward_scene_signals"):
		SceneManager._connect_reward_scene_signals()
	else:
		if not is_connected("rewards_accepted", Callable(SceneManager, "_on_rewards_accepted")):
			connect("rewards_accepted", Callable(SceneManager, "_on_rewards_accepted"))
		if not is_connected("next_floor", Callable(SceneManager, "_on_next_floor")):
			connect("next_floor", Callable(SceneManager, "_on_next_floor"))

func update_button_visibility():
	if continue_button:
		continue_button.visible = not is_boss_fight
	if next_floor_button:
		next_floor_button.visible = is_boss_fight and current_floor < max_floor
	if quit_button:
		quit_button.visible = true
	if equip_button:
		equip_button.visible = true
	if use_consumable_button:
		use_consumable_button.visible = true
