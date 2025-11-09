# RewardScene.gd
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
var reward_accepted = false

@onready var reward_label: Label = $UI/RewardLabel
@onready var continue_button: Button = $UI/ContinueButton
@onready var quit_button: Button = $UI/QuitButton
@onready var next_floor_button: Button = $UI/NextFloorButton
@onready var equip_button = $UI/EquipmentButton
@onready var use_consumable_button = $UI/InventoryButton
@onready var accept_reward_button = $UI/AcceptRewardButton
var xp_gained: int = 0

# RewardScene.gd

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
		continue_button.connect("pressed", Callable(self, "_on_continue_pressed"))
	if quit_button:
		quit_button.connect("pressed", Callable(self, "_on_quit_pressed"))
	if next_floor_button:
		next_floor_button.connect("pressed", Callable(self, "_on_next_floor_pressed"))
		next_floor_button.visible = is_boss_fight and current_floor < max_floor
	if equip_button:
		equip_button.connect("pressed", Callable(self, "_on_equip_pressed"))
	if use_consumable_button:
		use_consumable_button.connect("pressed", Callable(self, "_on_use_consumable_pressed"))
	if accept_reward_button:
		accept_reward_button.connect("pressed", Callable(self, "_on_accept_reward_pressed"))
		
		
func _on_accept_reward_pressed():
	print("Accepting rewards: ", rewards)
	for item_id in rewards:
		if item_id == "currency":
			player_character.currency.add(rewards[item_id])
			print("Added ", rewards[item_id], " currency to player")
		elif item_id != "xp":
			var item = ItemManager.get_item(item_id)
			if item:
				print("Adding item to inventory: ", item.name, " x", rewards[item_id])
				player_character.inventory.add_item(item, rewards[item_id])
			else:
				print("Warning: Failed to add item to inventory: ", item_id)
	reward_label.text = ""
	accept_reward_button.visible = false
	rewards.clear()
	reward_accepted = false
	
	
func _on_equip_pressed():
	SceneManager.change_scene_with_return("res://scenes/EquipmentScene.tscn", player_character)

func _on_use_consumable_pressed():
	SceneManager.change_scene_with_return("res://scenes/InventoryScene.tscn", player_character)

func _on_continue_pressed():
	SceneManager.reward_scene_active = false
	print("RewardScene: Continue button pressed")
	if not setup_complete:
		print("Error: Setup not complete, cannot continue")
		return
	print("RewardScene: Player character: ", player_character.name if player_character else "NULL")
	
	if player_character == null:
		print("Error: Player character is null in RewardScene")
		return
	SaveManager.save_game(player_character)
	print("Character saved after receiving rewards")
	emit_signal("rewards_accepted")
	print("RewardScene: Emitted rewards_accepted signal")

func set_rewards(new_rewards: Dictionary):
	rewards = new_rewards
	print("RewardScene: Rewards set: ", rewards)

func set_xp_gained(xp: int):
	xp_gained = xp
	print("RewardScene: XP gained set: ", xp_gained)

func set_dungeon_info(boss_fight: bool, floor: int, max_floor: int):
	is_boss_fight = boss_fight
	current_floor = floor
	self.max_floor = max_floor
	print("RewardScene: Dungeon info set - Boss fight: ", is_boss_fight, ", Floor: ", current_floor, ", Max floor: ", max_floor)

func display_rewards():
	reward_accepted = true
	if not reward_label:
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
	SaveManager.save_game(player_character)
	emit_signal("next_floor")
	queue_free()

func _on_quit_pressed():
	SaveManager.save_game(player_character)
	SceneManager.reward_scene_active = false
	SceneManager.change_to_town(player_character)
