# res://scenes/RewardScene.gd
extends Control

signal rewards_accepted
signal next_wave
signal next_floor
signal quit_dungeon

var rewards: Dictionary = {}
var player_character: CharacterData
var is_boss_fight: bool = false
var current_floor: int = 1
var max_floor: int = 10
var setup_complete = false
var rewards_collected = false  # NEW: Track if rewards were accepted
var continue_pressed = false # 
var new_floor_pressed = false

@onready var reward_label: Label = $UI/RewardLabel
@onready var continue_button: Button = $UI/ContinueButton
@onready var quit_button: Button = $UI/QuitButton
@onready var next_floor_button: Button = $UI/NextFloorButton
@onready var equip_button = $UI/EquipmentButton
@onready var use_consumable_button = $UI/InventoryButton
@onready var accept_reward_button = $UI/AcceptRewardButton
var xp_gained: int = 0

func _ready():
	print("RewardScene: _ready called")
	call_deferred("deferred_setup")

func deferred_setup():
	print("RewardScene: deferred_setup called")
	setup_ui()
	display_rewards()
	setup_complete = true

func setup_ui():
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
	
	print("RewardScene: UI setup complete - Boss fight: ", is_boss_fight, ", Floor: ", current_floor, "/", max_floor)

func _on_accept_reward_pressed():
	# CRITICAL FIX: Don't allow accepting empty rewards
	if rewards.is_empty() or rewards_collected:
		print("RewardScene: Rewards already collected or empty")
		return
	
	print("Accepting rewards: ", rewards)
	for item_id in rewards:
		if item_id == "currency":
			player_character.currency.add(rewards[item_id])
			print("Added ", rewards[item_id], " currency to player")
		else:
			# All other items (no need to check != "xp" since XP is handled separately)
			var item = ItemManager.get_item(item_id)
			if item:
				var quantity = rewards[item_id]
				print("Adding item to inventory: ", item.name, " x", quantity, " Rarity: ", item.rarity if item is Equipment else "N/A")
				player_character.inventory.add_item(item, quantity)
			else:
				print("Warning: Failed to add item to inventory: ", item_id)
	
	# CRITICAL FIX: Clear the rewards immediately after collecting
	rewards.clear()
	
	SaveManager.save_game(player_character)
	print("Character saved after receiving rewards")
	
	reward_label.text = "Rewards already collected!"
	accept_reward_button.visible = false
	rewards_collected = true  # Mark as collected
	
	# Just mark rewards as collected, don't clear the temp data yet
	print("RewardScene: Rewards collected, temp data preserved for navigation")
	
	# Apply XP and show level-up immediately after accepting rewards
	if xp_gained > 0:
		var old_level = player_character.level
		player_character.gain_xp(xp_gained)
		xp_gained = 0  # CRITICAL FIX: Clear XP so it can't be gained twice
		if SceneManager.reward_data_temp.has("xp_gained"):
			SceneManager.reward_data_temp["xp_gained"] = 0
		
		if player_character.level > old_level:
			print("RewardScene: Player leveled up from ", old_level, " to ", player_character.level)
			await show_level_up_overlay()

func show_level_up_overlay():
	print("RewardScene: Showing level-up overlay")
	
	# Hide all UI buttons during level-up
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
	
	var viewport_size = get_viewport_rect().size
	if level_up_scene.has_node("Background"):
		var background = level_up_scene.get_node("Background")
		var scene_size = background.size
		level_up_scene.position = (viewport_size - scene_size) / 2
	
	level_up_scene.visible = true
	level_up_scene.show()
	level_up_scene.setup(player_character)
	
	await level_up_scene.level_up_complete
	
	print("RewardScene: Level-up complete")
	level_up_scene.queue_free()
	
	# Restore button visibility
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

func set_rewards(new_rewards: Dictionary):
	rewards = new_rewards
	rewards_collected = false  # Reset when new rewards are set
	print("RewardScene: Rewards set: ", rewards)

func set_xp_gained(xp: int):
	xp_gained = xp
	print("RewardScene: XP gained set: ", xp_gained)

func set_dungeon_info(boss_fight: bool, floor: int, max_floor_val: int):
	is_boss_fight = boss_fight
	current_floor = floor
	max_floor = max_floor_val
	print("RewardScene: Dungeon info set - Boss fight: ", is_boss_fight, ", Floor: ", current_floor, ", Max floor: ", max_floor)

func display_rewards():
	if not reward_label:
		return
	
	# CRITICAL FIX: Don't display if rewards were already collected
	if rewards_collected:
		reward_label.text = "Rewards already collected!"
		if accept_reward_button:
			accept_reward_button.visible = false
		return

	var reward_text = "You received:\n"
	if xp_gained > 0:
		reward_text += "%d XP\n" % xp_gained
	for item_id in rewards:
		if item_id == "currency":
			reward_text += "%d Gold\n" % rewards[item_id]
		elif item_id != "xp":
			var item = ItemManager.get_item(item_id)
			if item:
				reward_text += "%dx %s\n" % [rewards[item_id], item.name]
			else:
				print("Warning: Item not found: ", item_id)
	reward_label.text = reward_text
	print("Displayed rewards: ", reward_text)

func set_player_character(character: CharacterData):
	player_character = character

func _on_next_floor_pressed():
	new_floor_pressed = true
	# CRITICAL FIX: Prompt if rewards not collected
	if not rewards_collected:
		show_collection_prompt("next floor")
		return
	
	print("RewardScene: Next floor button pressed")
	SaveManager.save_game(player_character)
	emit_signal("next_floor")

func _on_quit_pressed():
	print("RewardScene: Quit button pressed")
	SaveManager.save_game(player_character)
	SceneManager.reward_scene_active = false
	SceneManager.change_to_town(player_character)

func _on_continue_pressed():
	continue_pressed = true
	
	# CRITICAL FIX: Restore player character if null (happens when returning from Equipment/Inventory)
	if player_character == null:
		player_character = SceneManager.reward_data_temp.get("player_character")
		if player_character == null:
			print("Error: Cannot restore player character in RewardScene")
			return
	
	# CRITICAL FIX: Prompt if rewards not collected
	if not rewards_collected:
		show_collection_prompt("continue")
		return
	
	print("RewardScene: Continue button pressed")
	SceneManager.reward_scene_active = false
	
	if not setup_complete:
		print("Error: Setup not complete, cannot continue")
		return
	
	SaveManager.save_game(player_character)
	print("Character saved after receiving rewards")
	emit_signal("rewards_accepted")
	print("RewardScene: Emitted rewards_accepted signal")

func show_collection_prompt(action: String):
	var dialog = ConfirmationDialog.new()
	dialog.title = "Collect Rewards First"
	dialog.dialog_text = "You must accept your rewards before you can %s!\n\nDo you want to accept them now?" % action
	dialog.ok_button_text = "Push forward and disregard rubbish."
	dialog.cancel_button_text = "Cancel to Accept Rewards."
	dialog.connect("confirmed", Callable(self, "_on_ignore_rewards_pressed").bind())
	add_child(dialog)
	dialog.popup_centered()
	
	# Wait for user choice
	var confirmed = await dialog.confirmed
	dialog.confirmed.connect(_on_ignore_rewards_pressed)
	continue_pressed = false
	new_floor_pressed = false
	print("confirmed")
			
			
func _on_ignore_rewards_pressed():
	rewards_collected = true
	if continue_pressed == true:
		_on_continue_pressed()
		continue_pressed = false
	elif new_floor_pressed == true:
		_on_next_floor_pressed()
		new_floor_pressed = false
	

func _on_equip_pressed():
	SceneManager.change_scene_with_return("res://scenes/EquipmentScene.tscn", player_character)

func _on_use_consumable_pressed():
	SceneManager.change_scene_with_return("res://scenes/InventoryScene.tscn", player_character)
