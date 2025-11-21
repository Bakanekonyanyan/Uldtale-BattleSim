# RewardScene.gd - ENHANCED UX/UI
extends Control

signal rewards_accepted
signal next_wave
signal next_floor
signal quit_dungeon

var rewards: Dictionary = {}
var player_character: CharacterData
var is_boss_fight: bool = false
var current_floor: int = 1
var current_wave: int = 1
var max_floor: int = 25
var xp_gained: int = 0
var dungeon_description
var collected_items: Dictionary = {}
var auto_rewards_given: bool = false

@onready var reward_label: RichTextLabel = $UI/RewardLabel
@onready var continue_button: Button = $UI/ContinueButton
@onready var quit_button: Button = $UI/QuitButton
@onready var next_floor_button: Button = $UI/NextFloorButton
@onready var equip_button = $UI/EquipmentButton
@onready var use_consumable_button = $UI/InventoryButton
@onready var reward_items_list: ItemList = $UI/CollectionContainer/RewardItemsList
@onready var item_info_label: RichTextLabel = $UI/CollectionContainer/ItemInfoLabel
@onready var accept_button: Button = $UI/CollectionContainer/ButtonContainer/AcceptButton
@onready var accept_all_button: Button = $UI/CollectionContainer/ButtonContainer/AcceptAllButton
@onready var dispose_button: Button = $UI/CollectionContainer/ButtonContainer/DisposeButton
@onready var dispose_all_button: Button = $UI/CollectionContainer/ButtonContainer/DisposeAllButton
@onready var auto_rewards_label: RichTextLabel = $UI/AutoRewardsLabel
@onready var collection_container: Control = $UI/CollectionContainer

func _ready():
	print("RewardScene: _ready called")
	
	# Restore saved state if exists
	var saved_state = SceneManager.get_saved_reward_state()
	if saved_state != null:
		rewards = saved_state.rewards
		xp_gained = saved_state.xp_gained
		
		if saved_state.has("collected_items"):
			collected_items = saved_state.collected_items
		
		if saved_state.has("auto_rewards_given"):
			auto_rewards_given = saved_state.auto_rewards_given
		
		if saved_state.has("is_boss_fight"):
			is_boss_fight = saved_state.is_boss_fight
		if saved_state.has("current_floor"):
			current_floor = saved_state.current_floor
		if saved_state.has("max_floor"):
			max_floor = saved_state.max_floor
	
	# Connect UI signals
	setup_ui_signals()
	_connect_signals_to_scene_manager()
	update_button_visibility()

func setup_ui_signals():
	"""Connect all UI signals"""
	continue_button.pressed.connect(_on_continue_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	next_floor_button.pressed.connect(_on_next_floor_pressed)
	equip_button.pressed.connect(_on_equip_pressed)
	use_consumable_button.pressed.connect(_on_use_consumable_pressed)
	reward_items_list.item_clicked.connect(_on_reward_item_clicked)
	accept_button.pressed.connect(_on_accept_selected_pressed)
	accept_all_button.pressed.connect(_on_accept_all_pressed)
	dispose_button.pressed.connect(_on_dispose_selected_pressed)
	dispose_all_button.pressed.connect(_on_dispose_all_pressed)

func set_rewards(new_rewards: Dictionary):
	print("RewardScene: set_rewards called with %d keys" % new_rewards.size())
	rewards = new_rewards

func set_xp_gained(xp: int):
	print("RewardScene: set_xp_gained called with: ", xp)
	xp_gained = xp

@warning_ignore("shadowed_global_identifier")
func set_dungeon_info(_boss_fight: bool, wave: int, floor: int, _max_floor: int, description: String):
	is_boss_fight = _boss_fight
	current_wave = wave
	current_floor = floor
	max_floor = _max_floor
	
	if description == null or description == "":
		dungeon_description = "Dungeon Floor %d" % floor
	elif typeof(description) == TYPE_STRING:
		dungeon_description = description
	else:
		dungeon_description = str(description)

	print("RewardScene: Dungeon info set - Boss: %s, Floor: %d, Wave: %d" % [is_boss_fight, current_floor, current_wave])

func set_player_character(character: CharacterData):
	print("RewardScene: set_player_character called")
	
	if not character:
		push_error("RewardScene: Attempted to set null player_character!")
		return
	
	player_character = character
	print("RewardScene: Player character set successfully")

func initialize_display():
	"""Called by SceneManager after all setup is complete"""
	print("RewardScene: initialize_display called")
	display_rewards()
	update_button_visibility()
	_check_and_auto_collect()

func _check_and_auto_collect():
	"""Check if there are no collectable items and auto-collect if needed"""
	if not player_character:
		print("RewardScene: Cannot auto-collect - no player character")
		return
	
	if not _has_collectable_items() and not auto_rewards_given:
		print("RewardScene: No collectable items - auto-collecting rewards")
		_add_auto_rewards()
		_save_state_and_character()

func _has_collectable_items() -> bool:
	"""Check if there are any items that need to be collected/disposed"""
	for item_id in rewards:
		if item_id not in ["currency", "xp", "equipment_instances"]:
			return true
	
	if rewards.has("equipment_instances"):
		if rewards["equipment_instances"].size() > 0:
			return true
	
	return false

func display_rewards():
	if not player_character:
		print("RewardScene: Cannot display rewards - no player character")
		return
	
	print("RewardScene: Displaying rewards (%d collected)" % collected_items.size())
	
	# Enhanced auto-collected rewards display
	var auto_text = "[center][b][color=#FFD700]═══ AUTO-COLLECTED REWARDS ═══[/color][/b][/center]\n\n"
	
	if xp_gained > 0:
		auto_text += "[color=#88FF88]✦ +%d XP[/color]\n" % xp_gained
	
	if rewards.has("currency"):
		auto_text += "[color=#FFD700]💰 +%d Gold[/color]\n" % rewards["currency"]
	
	if auto_rewards_given:
		auto_text += "\n[color=#66DD66][i]✓ Collected[/i][/color]"
	else:
		auto_text += "\n[color=#FFAA44][i]⏳ Will be collected when you proceed[/i][/color]"
	
	auto_rewards_label.text = auto_text

	var has_collectable_items = _has_collectable_items()
	
	# Hide collection UI if there are no collectable items
	collection_container.visible = has_collectable_items
	print("RewardScene: Collection UI visibility set to: ", has_collectable_items)
	
	if not has_collectable_items:
		print("RewardScene: No collectable items - skipping ItemList population")
		return
	
	# Populate ItemList with enhanced formatting
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
			
			var display_text = _format_reward_item(item, quantity, collected)
			reward_items_list.add_item(display_text)
			
			reward_items_list.set_item_metadata(index, {
				"type": "consumable",
				"id": item_id,
				"item": item,
				"quantity": quantity,
				"collected": collected
			})
			
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
				
				var display_text = _format_reward_item(equipment, 1, collected)
				reward_items_list.add_item(display_text)
				
				if not collected:
					var rarity_color = Color(equipment.get_rarity_color())
					reward_items_list.set_item_custom_fg_color(index, rarity_color)
				else:
					reward_items_list.set_item_custom_fg_color(index, Color(0.5, 0.5, 0.5))
				
				reward_items_list.set_item_metadata(index, {
					"type": "equipment",
					"key": equip_key,
					"item": equipment,
					"collected": collected
				})
				
				index += 1
	
	print("RewardScene: Populated ItemList with %d items" % index)

func _format_reward_item(item: Item, quantity: int, collected: bool) -> String:
	"""Format reward item display for better readability"""
	var display = ""
	
	if item is Equipment:
		display = "%s  [%s]  (ilvl %d)" % [
			item.display_name,
			item.rarity.capitalize(),
			item.item_level
		]
	else:
		display = "%s" % item.display_name
		if quantity > 1:
			display += "  ×%d" % quantity
	
	if collected:
		display += "  [✓ Collected]"
	
	return display

func _on_reward_item_clicked(index: int, _at_position: Vector2, _mouse_button_index: int):
	print("Reward item clicked at index: ", index)
	
	var metadata = reward_items_list.get_item_metadata(index)
	if not metadata:
		return
	
	var is_collected = metadata.get("collected", false)
	accept_button.disabled = is_collected
	dispose_button.disabled = is_collected
	
	display_item_info(metadata["item"])

func display_item_info(item: Item):
	"""Enhanced item info display"""
	var info_text = ""
	
	if item is Equipment:
		info_text = item.get_full_description()
	else:
		info_text = "[center][b][color=#FFD700]%s[/color][/b][/center]\n" % item.display_name
		info_text += "[color=#CCCCCC]%s[/color]\n\n" % item.description
		
		if item.item_type == Item.ItemType.CONSUMABLE:
			info_text += "[color=#00DDFF][b]═══ EFFECT ═══[/b][/color]\n"
			
			match item.consumable_type:
				Item.ConsumableType.DAMAGE:
					info_text += "[color=#FF6666]⚔ Deals %d damage[/color]\n" % item.effect_power
					if item.status_effect != Skill.StatusEffect.NONE:
						var effect_name = Skill.StatusEffect.keys()[item.status_effect]
						info_text += "[color=#BB88FF]✦ Inflicts %s for %d turns[/color]\n" % [effect_name, item.effect_duration]
				Item.ConsumableType.HEAL:
					info_text += "[color=#66FF66]❤ Restores %d HP[/color]\n" % item.effect_power
				Item.ConsumableType.RESTORE:
					info_text += "[color=#6666FF]✦ Restores %d MP/SP[/color]\n" % item.effect_power
				Item.ConsumableType.BUFF:
					info_text += "[color=#FFDD66]↑ Increases %s by %d for %d turns[/color]\n" % [item.buff_type, item.effect_power, item.effect_duration]
				Item.ConsumableType.CURE:
					info_text += "[color=#66FFDD]✚ Cures all status effects[/color]\n"
					if item.effect_power > 0:
						info_text += "[color=#66FF66]❤ Restores %d HP[/color]\n" % item.effect_power
		
		# Show value
		if item.value > 0:
			info_text += "\n[color=#FFD700]Value: %d copper[/color]" % item.value
	
	item_info_label.text = info_text

func _on_accept_selected_pressed():
	var selected = reward_items_list.get_selected_items()
	if selected.is_empty():
		return
	
	var index = selected[0]
	var metadata = reward_items_list.get_item_metadata(index)
	
	if metadata.get("collected", false):
		print("Item already collected")
		return
	
	if metadata["type"] == "consumable":
		var item = metadata["item"]
		var quantity = metadata["quantity"]
		player_character.inventory.add_item(item, quantity)
		collected_items[metadata["id"]] = true
		print("Accepted: %dx %s" % [quantity, item.display_name])
	
	elif metadata["type"] == "equipment":
		var equipment = metadata["item"]
		player_character.inventory.add_item(equipment, 1)
		collected_items[metadata["key"]] = true
		print("Accepted: %s" % equipment.display_name)
	
	_save_state_and_character()
	display_rewards()
	item_info_label.text = "[center][color=#888888][i]Select an item to view details[/i][/color][/center]"
	accept_button.disabled = true
	dispose_button.disabled = true

func _on_accept_all_pressed():
	print("Accept all pressed")
	
	for item_id in rewards:
		if item_id in ["currency", "xp", "equipment_instances"]:
			continue
		
		if not collected_items.has(item_id):
			var item = ItemManager.get_item(item_id)
			if item:
				var quantity = rewards[item_id]
				player_character.inventory.add_item(item, quantity)
				collected_items[item_id] = true
				print("Accepted: %dx %s" % [quantity, item.display_name])
	
	if rewards.has("equipment_instances"):
		var equipment_list = rewards["equipment_instances"]
		for i in range(equipment_list.size()):
			var equip_key = "equip_%d" % i
			
			if not collected_items.has(equip_key):
				var equipment = equipment_list[i]
				if equipment is Equipment:
					player_character.inventory.add_item(equipment, 1)
					collected_items[equip_key] = true
					print("Accepted: %s" % equipment.display_name)
	
	_add_auto_rewards()
	_save_state_and_character()
	display_rewards()
	item_info_label.text = "[center][color=#66FF66][b]✓ All items collected![/b][/color][/center]"

func _on_dispose_selected_pressed():
	var selected = reward_items_list.get_selected_items()
	if selected.is_empty():
		return
	
	var index = selected[0]
	var metadata = reward_items_list.get_item_metadata(index)
	
	if metadata.get("collected", false):
		return
	
	var item = metadata["item"]
	var dialog = ConfirmationDialog.new()
	dialog.title = "Dispose Item?"
	dialog.dialog_text = "Are you sure you want to dispose of %s?" % item.display_name
	dialog.ok_button_text = "Yes, Dispose"
	dialog.cancel_button_text = "Cancel"
	add_child(dialog)
	dialog.popup_centered()
	
	dialog.confirmed.connect(func():
		if metadata["type"] == "consumable":
			collected_items[metadata["id"]] = true
		elif metadata["type"] == "equipment":
			collected_items[metadata["key"]] = true
		
		print("Disposed: %s" % item.display_name)
		_save_state_and_character()
		display_rewards()
		item_info_label.text = "[center][color=#FF8888][i]Item disposed[/i][/color][/center]"
		dialog.queue_free()
	)
	
	dialog.canceled.connect(func(): dialog.queue_free())

func _on_dispose_all_pressed():
	var dialog = ConfirmationDialog.new()
	dialog.title = "Dispose All Items?"
	dialog.dialog_text = "Are you sure you want to dispose of ALL uncollected items?\n\nXP and gold will still be collected."
	dialog.ok_button_text = "Yes, Dispose All"
	dialog.cancel_button_text = "Cancel"
	add_child(dialog)
	dialog.popup_centered()
	
	dialog.confirmed.connect(func():
		for item_id in rewards:
			if item_id not in ["currency", "xp", "equipment_instances"]:
				collected_items[item_id] = true
		
		if rewards.has("equipment_instances"):
			var equipment_list = rewards["equipment_instances"]
			for i in range(equipment_list.size()):
				collected_items["equip_%d" % i] = true
		
		_add_auto_rewards()
		_save_state_and_character()
		display_rewards()
		item_info_label.text = "[center][color=#FF8888][i]All items disposed[/i][/color][/center]"
		print("All items disposed")
		dialog.queue_free()
	)
	
	dialog.canceled.connect(func(): dialog.queue_free())

func _add_auto_rewards():
	if not player_character:
		push_error("RewardScene: Cannot add auto rewards - player_character is null!")
		return
	
	if auto_rewards_given:
		print("RewardScene: Auto rewards already given, skipping")
		return
	
	if rewards.has("currency"):
		player_character.currency.add(rewards["currency"])
		print("Added currency: ", rewards["currency"])
	
	if xp_gained > 0:
		var old_level = player_character.level
		player_character.gain_xp(xp_gained)
		
		if player_character.level > old_level:
			call_deferred("show_level_up_overlay")
	
	auto_rewards_given = true
	print("RewardScene: Auto rewards given, flag set")

func _all_items_collected() -> bool:
	if not _has_collectable_items():
		print("RewardScene: No collectable items - auto-allowing progression")
		return true
	
	for item_id in rewards:
		if item_id not in ["currency", "xp", "equipment_instances"]:
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

func _save_state_and_character():
	if not player_character:
		push_error("RewardScene: Cannot save - player_character is null!")
		return
	
	SaveManager.save_game(player_character)
	SceneManager.save_reward_state(rewards, xp_gained, _all_items_collected(), collected_items, auto_rewards_given)
	print("RewardScene: Saved state - %d collected, auto_given=%s" % [collected_items.size(), auto_rewards_given])

func _on_continue_pressed():
	if not _all_items_collected():
		show_collection_prompt("continue")
		return
	
	_add_auto_rewards()
	
	rewards.clear()
	collected_items.clear()
	auto_rewards_given = false
	SceneManager.clear_saved_reward_state()

	SceneManager.reward_scene_active = false
	SaveManager.save_game(player_character)
	emit_signal("next_wave")
	emit_signal("rewards_accepted")

func _on_next_floor_pressed():
	if not _all_items_collected():
		show_collection_prompt("advance to the next floor")
		return
	
	_add_auto_rewards()
	
	rewards.clear()
	collected_items.clear()
	auto_rewards_given = false
	SceneManager.clear_saved_reward_state()
	
	SaveManager.save_game(player_character)
	emit_signal("next_floor")

func _on_quit_pressed():
	if not _all_items_collected():
		_on_accept_all_pressed()
	
	_add_auto_rewards()
	
	rewards.clear()
	collected_items.clear()
	auto_rewards_given = false
	SceneManager.clear_saved_reward_state()
	
	SaveManager.save_game(player_character)
	SceneManager.reward_scene_active = false
	SceneManager.change_to_town(player_character)
	emit_signal("quit_dungeon")

func _on_equip_pressed():
	SceneManager.save_reward_state(rewards, xp_gained, _all_items_collected(), collected_items, auto_rewards_given)
	SceneManager.reward_scene_active = true
	SceneManager.push_scene("res://scenes/EquipmentScene.tscn", player_character)

func _on_use_consumable_pressed():
	SceneManager.save_reward_state(rewards, xp_gained, _all_items_collected(), collected_items, auto_rewards_given)
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
