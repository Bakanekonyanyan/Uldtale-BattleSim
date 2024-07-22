# RewardScene.gd
extends Control

signal rewards_accepted
signal quit_dungeon

var rewards: Dictionary = {}
var player_character: CharacterData

@onready var reward_label: Label = $RewardLabel
@onready var continue_button: Button = $ContinueButton
@onready var quit_button: Button = $QuitButton

func _ready():
	setup_ui()
	display_rewards()

func setup_ui():
	if continue_button:
		continue_button.connect("pressed", Callable(self, "_on_continue_pressed"))
	if quit_button:
		quit_button.connect("pressed", Callable(self, "_on_quit_pressed"))

func set_rewards(new_rewards: Dictionary):
	rewards = new_rewards

func set_player_character(character: CharacterData):
	player_character = character

func display_rewards():
	if not reward_label:
		return

	var reward_text = "You received:\n"
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
