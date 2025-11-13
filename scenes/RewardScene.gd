# RewardScene.gd - FIXED state preservation

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
var rewards_collected = false
var xp_gained: int = 0

@onready var reward_label: RichTextLabel = $UI/RewardLabel
@onready var continue_button: Button = $UI/ContinueButton
@onready var quit_button: Button = $UI/QuitButton
@onready var next_floor_button: Button = $UI/NextFloorButton
@onready var equip_button = $UI/EquipmentButton
@onready var use_consumable_button = $UI/InventoryButton
@onready var accept_reward_button = $UI/AcceptRewardButton

func set_rewards_accepted(value: bool) -> void:
	rewards_collected = value
	print("RewardScene: Rewards collected state set to: ", value)

func _ready():
	print("RewardScene: _ready called")
	print("Rewards already collected: ", rewards_collected)
	call_deferred("deferred_setup")

func deferred_setup():
	print("RewardScene: deferred_setup called")
	setup_ui()
	
	# CRITICAL FIX: Always display rewards on first load
	if not setup_complete:
		display_rewards()
	
	setup_complete = true

func setup_ui():
	# Connect buttons
	if continue_button:
		if continue_button.is_connected("pressed", Callable(self, "_on_continue_pressed")):
			continue_button.disconnect("pressed", Callable(self, "_on_continue_pressed"))
		continue_button.connect("pressed", Callable(self, "_on_continue_pressed"))
		continue_button.visible = not is_boss_fight
		
	if quit_button:
		if quit_button.is_connected("pressed", Callable(self, "_on_quit_pressed")):
			quit_button.disconnect("pressed", Callable(self, "_on_quit_pressed"))
		quit_button.connect("pressed", Callable(self, "_on_quit_pressed"))
		
	if next_floor_button:
		if next_floor_button.is_connected("pressed", Callable(self, "_on_next_floor_pressed")):
			next_floor_button.disconnect("pressed", Callable(self, "_on_next_floor_pressed"))
		next_floor_button.connect("pressed", Callable(self, "_on_next_floor_pressed"))
		next_floor_button.visible = is_boss_fight and current_floor < max_floor
		
	if equip_button:
		if equip_button.is_connected("pressed", Callable(self, "_on_equip_pressed")):
			equip_button.disconnect("pressed", Callable(self, "_on_equip_pressed"))
		equip_button.connect("pressed", Callable(self, "_on_equip_pressed"))
		
	if use_consumable_button:
		if use_consumable_button.is_connected("pressed", Callable(self, "_on_use_consumable_pressed")):
			use_consumable_button.disconnect("pressed", Callable(self, "_on_use_consumable_pressed"))
		use_consumable_button.connect("pressed", Callable(self, "_on_use_consumable_pressed"))
		
	if accept_reward_button:
		if accept_reward_button.is_connected("pressed", Callable(self, "_on_accept_reward_pressed")):
			accept_reward_button.disconnect("pressed", Callable(self, "_on_accept_reward_pressed"))
		accept_reward_button.connect("pressed", Callable(self, "_on_accept_reward_pressed"))
		
		# Update button state based on collection status
		if rewards_collected:
			accept_reward_button.visible = false
			accept_reward_button.disabled = true

func set_rewards(new_rewards: Dictionary):
	print("RewardScene: set_rewards called with: ", new_rewards)
	rewards = new_rewards
	
	# CRITICAL FIX: Display immediately if already ready
	if is_inside_tree():
		display_rewards()

func set_xp_gained(xp: int):
	print("RewardScene: set_xp_gained called with: ", xp)
	xp_gained = xp
	
	# CRITICAL FIX: Update display if already ready
	if is_inside_tree():
		display_rewards()

func set_dungeon_info(boss_fight: bool, floor: int, max_floor_val: int):
	is_boss_fight = boss_fight
	current_floor = floor
	max_floor = max_floor_val
	print("RewardScene: Dungeon info set - Boss: ", is_boss_fight, ", Floor: ", current_floor)

func set_player_character(character: CharacterData):
	player_character = character
	print("RewardScene: Player character set")

func display_rewards():
	if not reward_label:
		print("RewardScene: reward_label not ready yet")
		return
	
	print("RewardScene: Displaying rewards")
	print("RewardScene: XP: ", xp_gained)
	print("RewardScene: Rewards: ", rewards)
	print("RewardScene: Already collected: ", rewards_collected)
	
	if rewards_collected:
		reward_label.text = "[b][color=green]Rewards already collected![/color][/b]"
		if accept_reward_button:
			accept_reward_button.visible = false
			accept_reward_button.disabled = true
		return

	if rewards.is_empty() and xp_gained == 0:
		reward_label.text = "[b][color=yellow]No rewards to display[/color][/b]"
		return

	var reward_text = "[b]You received:[/b]\n\n"
	
	if xp_gained > 0:
		reward_text += "[color=cyan]%d XP[/color]\n" % xp_gained
	
	# Display currency
	if rewards.has("currency"):
		reward_text += "[color=yellow]%d Gold[/color]\n" % rewards["currency"]
	
	# Display consumables/materials (stored as item_id: quantity)
	for item_id in rewards:
		if item_id in ["currency", "xp", "equipment_instances"]:
			continue  # Skip special keys
		
		var item = ItemManager.get_item(item_id)
		if item:
			reward_text += "[color=white]%dx %s[/color]\n" % [rewards[item_id], item.name]
	
	# NEW: Display equipment instances (stored as objects)
	if rewards.has("equipment_instances"):
		var equipment_list = rewards["equipment_instances"]
		for equipment in equipment_list:
			if equipment is Equipment:
				var color = equipment.get_rarity_color()
				reward_text += "[color=%s]%s[/color] [ilvl %d]\n" % [
					color, 
					equipment.name,
					equipment.item_level
				]
	
	reward_label.bbcode_enabled = true
	reward_label.text = reward_text
	print("RewardScene: Displayed rewards text")

func _on_accept_reward_pressed():
	print("RewardScene: Accept reward pressed")
	
	if rewards.is_empty() or rewards_collected:
		print("RewardScene: Rewards already collected or empty")
		reward_label.text = "[b][color=red]Rewards already collected![/color][/b]"
		accept_reward_button.visible = false
		accept_reward_button.disabled = true
		return
	
	print("Accepting rewards: ", rewards)
	
	# Add currency
	if rewards.has("currency"):
		player_character.currency.add(rewards["currency"])
		print("Added ", rewards["currency"], " currency")
	
	# Add consumables/materials (by item_id)
	for item_id in rewards:
		if item_id in ["currency", "xp", "equipment_instances"]:
			continue
		
		var item = ItemManager.get_item(item_id)
		if item:
			var quantity = rewards[item_id]
			print("Adding item: ", item.name, " x", quantity)
			player_character.inventory.add_item(item, quantity)
	
	# NEW: Add equipment instances directly (no get_item() call)
	if rewards.has("equipment_instances"):
		var equipment_list = rewards["equipment_instances"]
		for equipment in equipment_list:
			if equipment is Equipment:
				print("Adding equipment instance: ", equipment.name, " (ilvl %d)" % equipment.item_level)
				# Add the EXACT instance, not a new one
				player_character.inventory.add_item(equipment, 1)
	
	# Mark as collected
	rewards_collected = true
	SceneManager.rewards_accepted = true
	
	# Clear rewards
	rewards.clear()
	
	# Save
	SaveManager.save_game(player_character)
	print("Character saved after receiving rewards")
	
	# Update UI
	reward_label.text = "[b][color=green]Rewards collected![/color][/b]"
	accept_reward_button.visible = false
	accept_reward_button.disabled = true
	
	# Apply XP and show level-up
	if xp_gained > 0:
		var old_level = player_character.level
		player_character.gain_xp(xp_gained)
		xp_gained = 0
		
		if player_character.level > old_level:
			print("RewardScene: Player leveled up!")
			await show_level_up_overlay()

func show_level_up_overlay():
	print("RewardScene: Showing level-up overlay")
	
	# Hide buttons during level-up
	if continue_button:
		continue_button.visible = false
	if next_floor_button:
		next_floor_button.visible = false
	if quit_button:
		quit_button.visible = false
	if equip_button:
		equip_button.visible = false
	if use_consumable_button:
		use_consumable_button.visible = false
	
	var level_up_scene = load("res://scenes/LevelUpScene.tscn").instantiate()
	add_child(level_up_scene)
	
	level_up_scene.visible = true
	level_up_scene.show()
	level_up_scene.setup(player_character)
	
	await level_up_scene.level_up_complete
	
	print("RewardScene: Level-up complete")
	level_up_scene.queue_free()
	
	# Restore buttons
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

func _on_continue_pressed():
	print("RewardScene: Continue pressed")
	
	# Check if rewards collected
	if not rewards_collected:
		show_collection_prompt("continue")
		return
	
	SceneManager.reward_scene_active = false
	SaveManager.save_game(player_character)
	DungeonStateManager.advance_wave()
	emit_signal("rewards_accepted")

func _on_next_floor_pressed():
	print("RewardScene: Next floor pressed")
	
	# Check if rewards collected
	if not rewards_collected:
		show_collection_prompt("next floor")
		return
	
	player_character.current_floor += 1
	SaveManager.save_game(player_character)
	emit_signal("next_floor")

func _on_quit_pressed():

	print("RewardScene: Quit pressed")
	
	if rewards.has("currency"):
		player_character.currency.add(rewards["currency"])
		print("Added ", rewards["currency"], " currency")
		
	if xp_gained > 0:
		var old_level = player_character.level
		player_character.gain_xp(xp_gained)
		xp_gained = 0
		
		if player_character.level > old_level:
			print("RewardScene: Player leveled up!")
			await show_level_up_overlay()
	SaveManager.save_game(player_character)
	SceneManager.reward_scene_active = false
	SceneManager.change_to_town(player_character)

func _on_equip_pressed():
	print("RewardScene: Equipment pressed - rewards_collected: ", rewards_collected)
	SceneManager.change_scene_with_return("res://scenes/EquipmentScene.tscn", player_character)

func _on_use_consumable_pressed():
	print("RewardScene: Inventory pressed - rewards_collected: ", rewards_collected)
	SceneManager.change_scene_with_return("res://scenes/InventoryScene.tscn", player_character)

func show_collection_prompt(action: String):
	var dialog = ConfirmationDialog.new()
	dialog.title = "Collect Rewards First"
	dialog.dialog_text = "You must accept your rewards before you can %s!" % action
	dialog.ok_button_text = "OK"
	add_child(dialog)
	dialog.popup_centered()
