# RewardScene.gd
extends Control

signal rewards_accepted
signal next_floor
signal quit_dungeon

var rewards: Dictionary = {}
var player_character: CharacterData
var is_boss_fight: bool = false
var current_floor: int = 1
var max_floor: int = 3

@onready var reward_label: Label = $RewardLabel
@onready var continue_button: Button = $ContinueButton
@onready var quit_button: Button = $QuitButton
@onready var next_floor_button: Button = $NextFloorButton
var xp_gained: int = 0

func _ready():
	setup_ui()
	display_rewards()

func setup_ui():
	if continue_button:
		continue_button.connect("pressed", Callable(self, "_on_continue_pressed"))
	if quit_button:
		quit_button.connect("pressed", Callable(self, "_on_quit_pressed"))
	if next_floor_button:
		next_floor_button.connect("pressed", Callable(self, "_on_next_floor_pressed"))
		next_floor_button.visible = is_boss_fight and current_floor < max_floor

func set_rewards(new_rewards: Dictionary):
	rewards = new_rewards

func set_player_character(character: CharacterData):
	player_character = character

func set_xp_gained(xp: int):
	xp_gained = xp

func set_dungeon_info(boss_fight: bool, floor: int, max_floor: int):
	is_boss_fight = boss_fight
	current_floor = floor
	if next_floor_button:
		next_floor_button.visible = is_boss_fight and floor < max_floor
		
func display_rewards():
	if not reward_label:
		return

	var reward_text = "You received:\n"
	reward_text += "%d XP\n" % xp_gained
	for item_id in rewards:
		if item_id == "currency":
			reward_text += "%d Gold\n" % rewards[item_id]
		else:
			var item = ItemManager.get_item(item_id)
			if item:
				reward_text += "%dx %s\n" % [rewards[item_id], item.name]
			else:
				print("Warning: Item not found: ", item_id)
	reward_label.text = reward_text
	print("Displayed rewards: ", reward_text)

func _on_next_floor_pressed():
	emit_signal("next_floor")
	queue_free()

func _on_continue_pressed():
	print("Accepting rewards: ", rewards)
	for item_id in rewards:
		if item_id == "currency":
			player_character.currency.add(rewards[item_id])
			print("Added ", rewards[item_id], " currency to player")
		else:
			var item = ItemManager.get_item(item_id)
			if item:
				print("Adding item to inventory: ", item.name, " x", rewards[item_id])
				player_character.inventory.add_item(item, rewards[item_id])
			else:
				print("Warning: Failed to add item to inventory: ", item_id)
	SaveManager.save_game(player_character)
	print("Character saved after receiving rewards")
	emit_signal("rewards_accepted")
	queue_free()
	
func _on_quit_pressed():
	# Add rewards to player's inventory and currency before quitting
	for item_id in rewards:
		if item_id == "currency":
			player_character.currency.add(rewards[item_id])
		else:
			var item = ItemManager.get_item(item_id)
			if item:
				player_character.inventory.add_item(item, rewards[item_id])
	
	# Signal that the player wants to quit the dungeon
	emit_signal("quit_dungeon")
	
	# Remove the reward scene
	queue_free()
