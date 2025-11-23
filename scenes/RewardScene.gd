# RewardScene.gd - REFACTORED - COMPLETE
# Uses RewardsManager for state, maintains all original functionality

extends Control

var rewards: Dictionary = {}
var player_character: CharacterData
var is_boss_fight: bool = false
var current_floor: int = 1
var current_wave: int = 1
var max_floor: int = 25
var xp_gained: int = 0
var dungeon_description: String = ""
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
	
	# Restore saved state from RewardsManager
	var saved_state = RewardsManager.get_saved_state()
	if not saved_state.is_empty():
		print("RewardScene: Restoring saved state from RewardsManager")
		rewards = saved_state.get("rewards", {})
		xp_gained = saved_state.get("xp_gained", 0)
		collected_items = saved_state.get("collected_items", {})
		auto_rewards_given = saved_state.get("auto_rewards_given", false)
		is_boss_fight = saved_state.get("is_boss_fight", false)
		current_floor = saved_state.get("current_floor", 1)
		current_wave = saved_state.get("current_wave", 1)
		max_floor = saved_state.get("max_floor", 25)
	
	setup_ui_signals()
	update_button_visibility()

func setup_ui_signals():
	if continue_button:
		continue_button.pressed.connect(_on_continue_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)
	if next_floor_button:
		next_floor_button.pressed.connect(_on_next_floor_pressed)
	if equip_button:
		equip_button.pressed.connect(_on_equip_pressed)
	if use_consumable_button:
		use_consumable_button.pressed.connect(_on_use_consumable_pressed)
	if reward_items_list:
		reward_items_list.item_selected.connect(_on_item_selected)
		reward_items_list.item_clicked.connect(_on_item_clicked)
	if accept_button:
		accept_button.pressed.connect(_on_accept_selected_pressed)
	if accept_all_button:
		accept_all_button.pressed.connect(_on_accept_all_pressed)
	if dispose_button:
		dispose_button.pressed.connect(_on_dispose_selected_pressed)
	if dispose_all_button:
		dispose_all_button.pressed.connect(_on_dispose_all_pressed)

# === SETTERS ===
func set_rewards(new_rewards: Dictionary):
	rewards = new_rewards

func set_xp_gained(xp: int):
	xp_gained = xp

func set_dungeon_info(boss_fight: bool, wave: int, floor: int, max_floor_val: int, description: String = ""):
	is_boss_fight = boss_fight
	current_wave = wave
	current_floor = floor
	max_floor = max_floor_val
	dungeon_description = description

func set_player_character(character: CharacterData):
	player_character = character

func initialize_display():
	print("RewardScene: initialize_display called")
	display_rewards()
	update_button_visibility()
	_check_and_auto_collect()

func _check_and_auto_collect():
	if not _has_collectable_items() and not auto_rewards_given:
		_add_auto_rewards()

func _has_collectable_items() -> bool:
	for item_id in rewards:
		if item_id not in ["currency", "xp", "equipment_instances"]:
			return true
	if rewards.has("equipment_instances") and rewards["equipment_instances"].size() > 0:
		return true
	return false

# === DISPLAY ===
func display_rewards():
	if not player_character:
		return
	
	# Auto-rewards label
	if auto_rewards_label:
		var auto_text = "[center][b][color=#FFD700]═══ AUTO-COLLECTED REWARDS ═══[/color][/b][/center]\n\n"
		if xp_gained > 0:
			auto_text += "[color=#88FF88]✦ +%d XP[/color]\n" % xp_gained
		if rewards.has("currency"):
			auto_text += "[color=#FFD700]💰 +%d Gold[/color]\n" % rewards["currency"]
		if auto_rewards_given:
			auto_text += "\n[color=#66DD66][i]✓ Collected[/i][/color]"
		else:
			auto_text += "\n[color=#FFAA44][i]⏳ Will be collected when you proceed[/i][/color]"
		auto_rewards_label.bbcode_enabled = true
		auto_rewards_label.text = auto_text
	
	# Collection list
	var has_collectable = _has_collectable_items()
	if collection_container:
		collection_container.visible = has_collectable
	
	if not has_collectable:
		return
	
	if reward_items_list:
		reward_items_list.clear()
		
		# Add consumables/materials
		for item_id in rewards:
			if item_id in ["currency", "xp", "equipment_instances"]:
				continue
			
			var is_collected = collected_items.has(item_id)
			var item = ItemManager.get_item(item_id)
			if item:
				var display_text = "%dx %s" % [rewards[item_id], item.display_name]
				if is_collected:
					display_text += " [COLLECTED]"
				
				reward_items_list.add_item(display_text)
				var idx = reward_items_list.get_item_count() - 1
				
				if is_collected:
					reward_items_list.set_item_custom_fg_color(idx, Color(0.5, 0.5, 0.5))
					reward_items_list.set_item_disabled(idx, true)
				
				reward_items_list.set_item_metadata(idx, {
					"type": "consumable",
					"id": item_id,
					"item": item,
					"quantity": rewards[item_id],
					"collected": is_collected
				})
		
		# Add equipment
		if rewards.has("equipment_instances"):
			for i in range(rewards["equipment_instances"].size()):
				var equip_key = "equip_%d" % i
				var is_collected = collected_items.has(equip_key)
				var equipment = rewards["equipment_instances"][i]
				
				if equipment is Equipment:
					var display_text = "%s [ilvl %d]" % [equipment.display_name, equipment.item_level]
					if is_collected:
						display_text += " [COLLECTED]"
					
					reward_items_list.add_item(display_text)
					var idx = reward_items_list.get_item_count() - 1
					
					if is_collected:
						reward_items_list.set_item_custom_fg_color(idx, Color(0.5, 0.5, 0.5))
						reward_items_list.set_item_disabled(idx, true)
					else:
						var color = equipment.get_rarity_color()
						reward_items_list.set_item_custom_fg_color(idx, Color(color))
					
					reward_items_list.set_item_metadata(idx, {
						"type": "equipment",
						"key": equip_key,
						"item": equipment,
						"collected": is_collected
					})
	
	# Reset button states - START ENABLED
	if accept_button:
		accept_button.disabled = true  # Disabled until selection
	if dispose_button:
		dispose_button.disabled = true
	if accept_all_button:
		accept_all_button.disabled = _all_items_collected()
	if dispose_all_button:
		dispose_all_button.disabled = _all_items_collected()

func update_button_visibility():
	if continue_button:
		continue_button.visible = not is_boss_fight
	if next_floor_button:
		next_floor_button.visible = is_boss_fight and current_floor < max_floor

# === ITEM SELECTION ===
func _on_item_selected(index: int):
	var metadata = reward_items_list.get_item_metadata(index)
	if not metadata:
		return
	
	var is_collected = metadata.get("collected", false)
	
	# Enable/disable buttons based on collection status
	if accept_button:
		accept_button.disabled = is_collected
	if dispose_button:
		dispose_button.disabled = is_collected

func _on_item_clicked(index: int, at_position: Vector2, mouse_button_index: int):
	if not item_info_label:
		return
	
	var metadata = reward_items_list.get_item_metadata(index)
	if not metadata:
		return
	
	var info_text = ""
	var item = metadata["item"]
	
	if metadata["type"] == "consumable":
		info_text = "[b]%s[/b]\n%s\n\nQuantity: %d" % [
			item.display_name,
			item.description if item.has("description") else "",
			metadata["quantity"]
		]
	elif metadata["type"] == "equipment":
		info_text = "[b]%s[/b]\nRarity: %s\nItem Level: %d\n" % [
			item.display_name,
			item.rarity,
			item.item_level
		]
		if item.damage > 0:
			info_text += "Damage: %d\n" % item.damage
		if item.armor_value > 0:
			info_text += "Armor: %d\n" % item.armor_value
	
	if metadata.get("collected", false):
		info_text += "\n[color=green]✓ COLLECTED[/color]"
	
	item_info_label.bbcode_enabled = true
	item_info_label.text = info_text

# === COLLECTION ACTIONS ===
func _on_accept_selected_pressed():
	var selected = reward_items_list.get_selected_items()
	if selected.is_empty():
		return
	
	var index = selected[0]
	var metadata = reward_items_list.get_item_metadata(index)
	
	if metadata.get("collected", false):
		return
	
	if metadata["type"] == "consumable":
		var item = metadata["item"]
		var quantity = metadata["quantity"]
		player_character.inventory.add_item(item, quantity)
		collected_items[metadata["id"]] = true
	elif metadata["type"] == "equipment":
		var equipment = metadata["item"]
		player_character.inventory.add_item(equipment, 1)
		collected_items[metadata["key"]] = true
	
	_save_state()
	display_rewards()
	if item_info_label:
		item_info_label.text = "[center][color=#888888][i]Select an item[/i][/color][/center]"

func _on_accept_all_pressed():
	for item_id in rewards:
		if item_id in ["currency", "xp", "equipment_instances"]:
			continue
		if not collected_items.has(item_id):
			var item = ItemManager.get_item(item_id)
			if item:
				player_character.inventory.add_item(item, rewards[item_id])
				collected_items[item_id] = true
	
	if rewards.has("equipment_instances"):
		for i in range(rewards["equipment_instances"].size()):
			var equip_key = "equip_%d" % i
			if not collected_items.has(equip_key):
				var equipment = rewards["equipment_instances"][i]
				if equipment is Equipment:
					player_character.inventory.add_item(equipment, 1)
					collected_items[equip_key] = true
	
	_save_state()
	display_rewards()
	if item_info_label:
		item_info_label.text = "[center][color=#66FF66][b]✓ All collected![/b][/color][/center]"

func _on_dispose_selected_pressed():
	var selected = reward_items_list.get_selected_items()
	if selected.is_empty():
		return
	
	var index = selected[0]
	var metadata = reward_items_list.get_item_metadata(index)
	
	if metadata.get("collected", false):
		return
	
	if metadata["type"] == "consumable":
		collected_items[metadata["id"]] = true
	elif metadata["type"] == "equipment":
		collected_items[metadata["key"]] = true
	
	_save_state()
	display_rewards()

func _on_dispose_all_pressed():
	for item_id in rewards:
		if item_id in ["currency", "xp", "equipment_instances"]:
			continue
		collected_items[item_id] = true
	
	if rewards.has("equipment_instances"):
		for i in range(rewards["equipment_instances"].size()):
			collected_items["equip_%d" % i] = true
	
	_save_state()
	display_rewards()

# === NAVIGATION ===
func _on_continue_pressed():
	if not _all_items_collected():
		_show_collection_prompt("continue")
		return
	
	_add_auto_rewards()
	_cleanup_and_continue()

func _on_next_floor_pressed():
	if not _all_items_collected():
		_show_collection_prompt("advance to the next floor")
		return
	
	_add_auto_rewards()
	_cleanup_and_next_floor()

func _on_quit_pressed():
	if not _all_items_collected():
		_on_accept_all_pressed()
	
	_add_auto_rewards()
	_cleanup()
	SaveManager.save_game(player_character)
	SceneManager.change_to_town(player_character)

func _on_equip_pressed():
	_save_state()
	SceneManager.push_scene("res://scenes/EquipmentScene.tscn", player_character)

func _on_use_consumable_pressed():
	_save_state()
	SceneManager.push_scene("res://scenes/InventoryScene.tscn", player_character)

# === HELPERS ===
func _all_items_collected() -> bool:
	if not _has_collectable_items():
		return true
	
	for item_id in rewards:
		if item_id not in ["currency", "xp", "equipment_instances"]:
			if not collected_items.has(item_id):
				return false
	
	if rewards.has("equipment_instances"):
		for i in range(rewards["equipment_instances"].size()):
			if not collected_items.has("equip_%d" % i):
				return false
	
	return true

func _add_auto_rewards():
	if auto_rewards_given:
		return
	
	if rewards.has("currency"):
		player_character.currency.add(rewards["currency"])
	
	if xp_gained > 0:
		player_character.gain_xp(xp_gained)
	
	auto_rewards_given = true

func _save_state():
	RewardsManager.save_state(rewards, xp_gained, _all_items_collected(), collected_items, auto_rewards_given)
	SaveManager.save_game(player_character)

func _cleanup():
	rewards.clear()
	collected_items.clear()
	auto_rewards_given = false
	RewardsManager.clear_saved_state()

func _cleanup_and_continue():
	_cleanup()
	SaveManager.save_game(player_character)
	
	player_character.current_hp = player_character.max_hp
	player_character.current_mp = player_character.max_mp
	player_character.current_sp = player_character.max_sp
	player_character.status_manager.clear_all_effects()
	
	if DungeonStateManager.is_boss_fight:
		if not DungeonStateManager.advance_floor():
			SceneManager.change_to_town(player_character)
			return
		
		SceneManager.navigate(SceneManager.ScenePath.DUNGEON, SceneManager.TransitionType.REPLACE, player_character)
		await get_tree().process_frame
		
		if SceneManager.current_scene.has_method("start_dungeon"):
			var battle_data = DungeonStateManager.advance_wave()
			SceneManager.current_scene.start_dungeon(battle_data)
	else:
		var battle_data = DungeonStateManager.advance_wave()
		SceneManager.start_battle(battle_data)

func _cleanup_and_next_floor():
	_cleanup()
	SaveManager.save_game(player_character)
	
	# Reset player state
	player_character.current_hp = player_character.max_hp
	player_character.current_mp = player_character.max_mp
	player_character.current_sp = player_character.max_sp
	player_character.status_manager.clear_all_effects()
	
	if not DungeonStateManager.advance_floor():
		SceneManager.change_to_town(player_character)
		return
	
	# Generate battle data and go DIRECTLY to battle
	var battle_data = DungeonStateManager.advance_wave()
	SceneManager.start_battle(battle_data)

func _show_collection_prompt(action: String):
	var dialog = ConfirmationDialog.new()
	dialog.title = "Items Remaining"
	dialog.dialog_text = "You must collect or dispose of all items before you can %s!" % action
	dialog.ok_button_text = "OK"
	add_child(dialog)
	dialog.popup_centered()
