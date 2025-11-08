# res://scenes/battle/Battle.gd
extends Node2D

signal battle_completed(player_won, xp_gained)

var player_character: CharacterData
var enemy_character: CharacterData
var current_turn: String = "player"
var is_boss_battle: bool = false
var current_wave: int
var current_floor: int
var dungeon_description: String

@onready var wave_label = $WaveLabel
@onready var floor_label = $FloorLabel
@onready var dungeon_description_label = $DungeonDescriptionLabel
@onready var player_info = $PlayerInfo
@onready var enemy_info = $EnemyInfo
@onready var action_buttons = $ActionButtons
@onready var turn_label = $TurnLabel
@onready var inventory_menu = $InventoryMenu
@onready var xp_label = $XPLabel

func _ready():
	setup_battle()
	update_dungeon_labels()

# Sets up the player character for the battle
func set_player(character: CharacterData):
	player_character = character

# Creates and scales the enemy character based on the current floor
func set_enemy(new_enemy: CharacterData):
	enemy_character = new_enemy
	for _i in range(current_floor - 1):
		enemy_character.level_up()
	enemy_character.calculate_secondary_attributes()

# Sets up the dungeon info and updates labels
func set_dungeon_info(wave: int, floor: int, description: String):
	current_wave = wave
	current_floor = floor
	dungeon_description = description
	update_dungeon_labels()

# Updates the dungeon labels with current info
func update_dungeon_labels():
	$WaveLabel.text = "Wave: %d" % current_wave
	$FloorLabel.text = "Floor: %d" % current_floor
	$DungeonDescriptionLabel.text = dungeon_description

# Sets up the battle, including characters and UI
func setup_battle():
	player_character = player_character if player_character else CharacterManager.get_current_character()
	enemy_character = enemy_character if enemy_character else EnemyFactory.create_enemy()
	
	if not player_character or not enemy_character:
		print("Battle: Error - Failed to load characters")
		SceneManager.change_scene("res://scenes/ui/MainMenu.tscn")
		return
	
	inventory_menu.show_inventory(player_character.inventory, player_character.currency)
	inventory_menu.hide()
	
	update_ui()
	setup_action_buttons()
	start_battle()

# Starts the battle, setting the first turn
func start_battle():
	current_turn = "player"
	update_turn_label("Battle starts! It's your turn.")
	enable_player_actions(true)

# Updates the turn label with the given text
func update_turn_label(text: String):
	turn_label.text = text

# Enables or disables player action buttons
func enable_player_actions(enabled: bool):
	for button in action_buttons.get_children():
		if button is Button:
			button.disabled = !enabled

# Sets up the action buttons, including skill buttons
func setup_action_buttons():
	for child in action_buttons.get_children():
		child.queue_free()
	
	var buttons = ["Attack", "Defend", "Items"]
	for button_name in buttons:
		var button = Button.new()
		button.text = button_name
		button.connect("pressed", Callable(self, "_on_" + button_name.to_lower() + "_pressed"))
		action_buttons.add_child(button)
	
	if player_character:
		for skill_name in player_character.skills:
			var skill = SkillManager.get_skill(skill_name)
			if skill:
				var skill_button = Button.new()
				skill_button.text = skill.name
				skill_button.connect("pressed", Callable(self, "_on_skill_used").bind(skill))
				action_buttons.add_child(skill_button)

# Handles player attack action
func _on_attack_pressed():
	var result = player_character.attack(enemy_character)
	update_turn_label(result)
	update_ui()
	check_battle_end()
	if enemy_character.current_hp > 0:
		end_turn()

# Handles player defend action
func _on_defend_pressed():
	var result = player_character.defend()
	update_turn_label(result)
	update_ui()
	end_turn()

# Handles player items action
func _on_items_pressed():
	inventory_menu.show_inventory(player_character.inventory, player_character.currency)

# Handles player skill usage
func _on_skill_used(skill: Skill):
	if player_character.current_mp < skill.mp_cost:
		update_turn_label("Not enough MP to use this skill")
		return
	
	player_character.current_mp -= skill.mp_cost
	var targets = [enemy_character]  # For now, we'll just target the enemy
	var result = skill.use(player_character, targets)
	update_turn_label(result)
	update_ui()
	check_battle_end()
	if enemy_character.current_hp > 0:
		end_turn()

# Handles item usage
func _on_item_used(item: Item):
	if item.item_type == Item.ItemType.CONSUMABLE:
		var result = item.use(player_character, [player_character])
		update_turn_label(result)
		player_character.inventory.remove_item(item.id, 1)
		update_ui()
		check_battle_end()
		if enemy_character.current_hp > 0:
			end_turn()
	else:
		update_turn_label("This item cannot be used in battle.")

# Executes a turn for the given character
func execute_turn(character: CharacterData):
	var status_message = character.update_status_effects()
	if status_message:
		update_turn_label(status_message)
		update_ui()
		await get_tree().create_timer(1.0).timeout
	
	if character.is_stunned:
		update_turn_label("%s is stunned and loses their turn!" % character.name)
		character.is_stunned = false
		await get_tree().create_timer(1.0).timeout
		end_turn()
		return
	
	if character == player_character:
		enable_player_actions(true)
	else:
		execute_enemy_turn()

# Executes the enemy's turn
func execute_enemy_turn():
	update_turn_label("Enemy's turn")
	await get_tree().create_timer(1.0).timeout

	var action = randf()
	var result = ""
	
	if action < 0.6:
		result = enemy_character.attack(player_character)
	elif action < 0.8:
		result = enemy_character.defend()
	else:
		if enemy_character.skills.size() > 0:
			var skill = SkillManager.get_skill(enemy_character.skills[randi() % enemy_character.skills.size()])
			if skill:
				var targets = [player_character] if skill.target in [Skill.TargetType.ENEMY, Skill.TargetType.ALL_ENEMIES] else [enemy_character]
				result = skill.use(enemy_character, targets)
			else:
				result = "Enemy tried to use an unknown skill"
		else:
			result = enemy_character.attack(player_character)
	
	update_turn_label(result)
	update_ui()
	await get_tree().create_timer(2.0).timeout

	check_battle_end()
	if player_character.current_hp > 0:
		end_turn()

# Ends the current turn and starts the next
func end_turn():
	if current_turn == "player":
		current_turn = "enemy"
		enemy_character.reset_defense()
		enable_player_actions(false)
		await get_tree().create_timer(1.0).timeout
		execute_turn(enemy_character)
	else:
		current_turn = "player"
		player_character.reset_defense()
		execute_turn(player_character)
	update_turn_label("It's %s's turn" % current_turn)

# Updates the UI with current character info
func update_ui():
	if player_info and enemy_info and player_character and enemy_character:
		player_info.text = "Player: %s\nHP: %d/%d\nMP: %d/%d\nStatus: %s" % [
			player_character.name, 
			player_character.current_hp, 
			player_character.max_hp,
			player_character.current_mp, 
			player_character.max_mp,
			player_character.get_status_effects_string()
		]
		enemy_info.text = "Enemy: %s\nHP: %d/%d\nMP: %d/%d\nStatus: %s" % [
			enemy_character.name, 
			enemy_character.current_hp, 
			enemy_character.max_hp,
			enemy_character.current_mp, 
			enemy_character.max_mp,
			enemy_character.get_status_effects_string()
		]
	
	if xp_label:
		xp_label.text = "XP: %d / %d" % [player_character.xp, LevelSystem.calculate_xp_for_level(player_character.level)]

# Checks if the battle has ended
func check_battle_end():
	if enemy_character.current_hp <= 0:
		emit_signal("battle_completed", true)
	elif player_character.current_hp <= 0:
		emit_signal("battle_completed", false)

# Calculates rewards for the battle
func calculate_rewards(player_won: bool) -> Dictionary:
	var rewards = {}
	if player_won:
		var base_reward = 100 * (3 if is_boss_battle else 1)
		rewards["currency"] = base_reward
		rewards["health_potion"] = 1 if randf() < 0.5 else 0
	return rewards

# The following functions have been commented out as they seem to be unused or for debugging purposes:
# func show_reward_scene(player_won: bool):
# func position_ui_elements():
# func print_visible_ui():
# func force_update_ui():
