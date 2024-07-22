# res://scenes/battle/Battle.gd
extends Node2D

signal battle_completed(player_won)

var player_character: CharacterData
var enemy_character: CharacterData
var current_turn: String = "player"  # "player" or "enemy"
var turn_order: Array = []
var is_boss_battle: bool = false

@onready var player_info = $PlayerInfo
@onready var enemy_info = $EnemyInfo
@onready var action_buttons = $ActionButtons
@onready var turn_label = $TurnLabel
@onready var inventory_menu = $InventoryMenu

func set_player(character: CharacterData):
	player_character = character

# In Battle.gd

func set_enemy(new_enemy: CharacterData):
	enemy_character = new_enemy
	# Any other setup you need to do with the enemy character

func _ready():
	print("Battle: _ready called")
	setup_battle()

func setup_battle():
	print("Battle: setup_battle called")
	
	if not player_character:
		player_character = CharacterManager.get_current_character()
	
	if player_character == null:
		print("Battle: Error - Failed to load player character")
		SceneManager.change_scene("res://scenes/ui/MainMenu.tscn")
		return
	
	print("Battle: Player character loaded: ", player_character.name)
	
	if inventory_menu:
		inventory_menu.show_inventory(player_character.inventory, player_character.currency)
		inventory_menu.hide()
	else:
		print("Battle: Warning - inventory_menu not found")
	
	if not enemy_character:
		enemy_character = EnemyFactory.create_enemy()
	
	if enemy_character == null:
		print("Battle: Error - Failed to create enemy character")
		SceneManager.change_scene("res://scenes/ui/MainMenu.tscn")
		return
	
	print("Battle: Enemy character created: ", enemy_character.name)
	
	update_ui()
	setup_action_buttons()
	start_battle()

func start_battle():
	print("start_battle called")
	current_turn = "player"
	update_turn_label("Battle starts! It's your turn.")
	enable_player_actions(true)
	print("Player actions enabled")

func update_turn_label(text: String):
	print("Updating turn label: ", text)
	if turn_label:
		turn_label.text = text
	else:
		print("Error: turn_label not found!")

func enable_player_actions(enabled: bool):
	print("enable_player_actions called with: ", enabled)
	if action_buttons:
		for button in action_buttons.get_children():
			if button is Button:
				button.disabled = !enabled
				print("Button ", button.name, " disabled set to ", !enabled)
	else:
		print("Error: action_buttons not found!")

func setup_action_buttons():
	print("Setting up action buttons")
	for child in action_buttons.get_children():
		child.queue_free()
	
	var buttons = ["Attack", "Defend", "Items"]
	for button_name in buttons:
		var button = Button.new()
		button.text = button_name
		button.connect("pressed", Callable(self, "_on_" + button_name.to_lower() + "_pressed"))
		action_buttons.add_child(button)
		print("Added button: ", button_name)

	if player_character:
		for skill_name in player_character.skills:
			var skill = SkillManager.get_skill(skill_name)
			if skill:
				var skill_button = Button.new()
				skill_button.text = skill.name
				skill_button.connect("pressed", Callable(self, "_on_skill_used").bind(skill))
				action_buttons.add_child(skill_button)
				print("Added skill button: ", skill.name)
	else:
		print("Error: player_character is null, cannot set up skill buttons")
	
	print("Action buttons setup complete. Total buttons: ", action_buttons.get_child_count())

func _on_attack_pressed():
	print("Attack button pressed")
	var result = player_character.attack(enemy_character)
	update_turn_label(result)
	print("Calling update_ui from [func on_attack_pressed]")
	update_ui()
	check_battle_end()
	if enemy_character.current_hp > 0:
		end_turn()

func _on_defend_pressed():
	print("Defend button pressed")
	var result = player_character.defend()
	update_turn_label(result)
	print("Calling update_ui from [func on_defend_pressed]")
	update_ui()
	end_turn()

func _on_items_pressed():
	print("Items button pressed")
	inventory_menu.show_inventory(player_character.inventory, player_character.currency)

func _on_skill_used(skill: Skill):
	print("Skill used: ", skill.name)
	if player_character.current_mp < skill.mp_cost:
		update_turn_label("Not enough MP to use this skill")
		return
	
	player_character.current_mp -= skill.mp_cost
	var targets = [enemy_character]  # For now, we'll just target the enemy
	if skill.target == Skill.TargetType.ALL_ENEMIES:
		targets = [enemy_character]  # In a real battle, this would be all enemies
	elif skill.target == Skill.TargetType.SELF:
		targets = [player_character]
	elif skill.target == Skill.TargetType.ALLY or skill.target == Skill.TargetType.ALL_ALLIES:
		targets = [player_character]  # In a real battle, this would be all allies or a chosen ally
	
	var result = skill.use(player_character, targets)
	update_turn_label(result)
	print("Calling update_ui from [func on_skill_used]")
	update_ui()
	check_battle_end()
	if enemy_character.current_hp > 0:
		end_turn()

func _on_item_used(item: Item):
	print("Item used: ", item.name)
	print("Inventory before use: ", player_character.inventory.items)
	var targets = [player_character]  # For healing items, target the player
	if item.item_type == Item.ItemType.CONSUMABLE:
		print("Using item: ", item.name, " (ID: ", item.id, ")")
		var result = item.use(player_character, targets)
		update_turn_label(result)
		
		# Here's where we remove the item from inventory using its ID
		var removed = player_character.inventory.remove_item(item.id, 1)
		if removed:
			print("Successfully removed item from inventory")
		else:
			print("Failed to remove item from inventory")
		
		print("Item use result: ", result)
		print("Inventory after use: ", player_character.inventory.items)
		print("Calling update_ui from [func on_item_used]")
		update_ui()
		check_battle_end()
		if enemy_character.current_hp > 0:
			end_turn()
	else:
		update_turn_label("This item cannot be used in battle.")

func execute_turn(character: CharacterData):
	print("Executing turn for: ", character.name)
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

func execute_enemy_turn():
	print("Executing enemy turn")
	update_turn_label("Enemy's turn")
	await get_tree().create_timer(1.0).timeout

	# Simple AI: 60% chance to attack, 20% chance to defend, 20% chance to use a skill
	var action = randf()
	var result = ""
	
	if action < 0.6:
		result = enemy_character.attack(player_character)
	elif action < 0.8:
		result = enemy_character.defend()
	else:
		if enemy_character.skills.size() > 0:
			var skill_name = enemy_character.skills[randi() % enemy_character.skills.size()]
			var skill = SkillManager.get_skill(skill_name)
			if skill:
				var targets = []
				match skill.target:
					Skill.TargetType.ENEMY, Skill.TargetType.ALL_ENEMIES:
						targets = [player_character]
					Skill.TargetType.SELF, Skill.TargetType.ALLY, Skill.TargetType.ALL_ALLIES:
						targets = [enemy_character]
				result = skill.use(enemy_character, targets)
			else:
				result = "Enemy tried to use an unknown skill"
		else:
			result = enemy_character.attack(player_character)
	
	update_turn_label(result)
	print("Calling update_ui from [func execute_enemy_turn]")
	update_ui()
	await get_tree().create_timer(2.0).timeout

	check_battle_end()
	if player_character.current_hp > 0:
		end_turn()

func end_turn():
	print("Ending turn")
	if current_turn == "player":
		current_turn = "enemy"
		enemy_character.reset_defense()  # Reset defense at the end of player's turn
		enable_player_actions(false)
		await get_tree().create_timer(1.0).timeout
		execute_turn(enemy_character)
	else:
		current_turn = "player"
		player_character.reset_defense()  # Reset defense at the end of enemy's turn
		execute_turn(player_character)
	update_turn_label("It's %s's turn" % current_turn)

func update_ui():
	print("update_ui function called")
	if player_info and enemy_info and player_character and enemy_character:
		print("Accessing player_character.name")
		var player_name = player_character.name
		print("Accessing enemy_character.name")
		var enemy_name = enemy_character.name
		player_info.text = "Player: %s\nHP: %d/%d\nMP: %d/%d\nStatus: %s" % [
			player_name, 
			player_character.current_hp, 
			player_character.max_hp,
			player_character.current_mp, 
			player_character.max_mp,
			player_character.get_status_effects_string()
		]
		enemy_info.text = "Enemy: %s\nHP: %d/%d\nMP: %d/%d\nStatus: %s" % [
			enemy_name, 
			enemy_character.current_hp, 
			enemy_character.max_hp,
			enemy_character.current_mp, 
			enemy_character.max_mp,
			enemy_character.get_status_effects_string()
		]
		print("UI updated successfully")
	else:
		print("Error: Unable to update UI. Missing UI elements or character data.")
		if not player_info:
			print("player_info is null")
		if not enemy_info:
			print("enemy_info is null")
		if not player_character:
			print("player_character is null")
		if not enemy_character:
			print("enemy_character is null")
	var current_scene = get_tree().current_scene
	if current_scene:
		print("Current scene: ", current_scene.name)
	else:
		print("Warning: current_scene is null")
	
	print("Visible UI elements:")
	print_visible_ui()

func print_visible_ui():
	var ui_elements = [player_info, enemy_info, action_buttons, turn_label]
	for element in ui_elements:
		if element:
			print(element.name, " visible: ", element.visible, " position: ", element.position)
		else:
			print("Element not found: ", element)

func check_battle_end():
	if enemy_character.current_hp <= 0:
		print("Battle: Player won")
		emit_signal("battle_completed", true)
		queue_free()
	elif player_character.current_hp <= 0:
		print("Battle: Player lost")
		emit_signal("battle_completed", false)
		queue_free()
		
func show_reward_scene(player_won: bool):
	var rewards = calculate_rewards(player_won)
	emit_signal("battle_completed", player_won)

func calculate_rewards(player_won: bool) -> Dictionary:
	var rewards = {}
	if player_won:
		var base_reward = 100
		if is_boss_battle:
			base_reward *= 3  # Triple rewards for boss battles
		rewards["currency"] = base_reward
		rewards["health_potion"] = 1 if randf() < 0.5 else 0  # 50% chance of health potion
	return rewards

func position_ui_elements():
	print("Positioning UI elements")
	var viewport_size = get_viewport_rect().size
	print("Viewport size: ", viewport_size)
	
	if player_info:
		player_info.position = Vector2(50, 50)
		print("player_info positioned at: ", player_info.position)
	else:
		print("player_info not found")
	
	if enemy_info:
		enemy_info.position = Vector2(viewport_size.x - 250, 50)
		print("enemy_info positioned at: ", enemy_info.position)
	else:
		print("enemy_info not found")
	
	if action_buttons:
		action_buttons.position = Vector2(50, viewport_size.y - 150)
		action_buttons.size = Vector2(viewport_size.x - 100, 100)
		print("action_buttons positioned at: ", action_buttons.position, " with size: ", action_buttons.size)
	else:
		print("action_buttons not found")
	
	if turn_label:
		turn_label.position = Vector2(viewport_size.x / 2 - 150, 20)
		turn_label.size = Vector2(300, 60)
		print("turn_label positioned at: ", turn_label.position, " with size: ", turn_label.size)
	else:
		print("turn_label not found")
	

func force_update_ui():
	print("Force updating UI")
	if player_info and enemy_info and player_character and enemy_character:
		player_info.text = "Player: %s\nHP: %d/%d\nMP: %d/%d" % [
			player_character.name, 
			player_character.current_hp, 
			player_character.max_hp,
			player_character.current_mp, 
			player_character.max_mp
		]
		enemy_info.text = "Enemy: %s\nHP: %d/%d\nMP: %d/%d" % [
			enemy_character.name, 
			enemy_character.current_hp, 
			enemy_character.max_hp,
			enemy_character.current_mp, 
			enemy_character.max_mp
		]
		print("UI force update complete")
	else:
		print("Error: Unable to force update UI. Missing UI elements or character data.")
		if not player_info:
			print("player_info is null")
		if not enemy_info:
			print("enemy_info is null")
		if not player_character:
			print("player_character is null")
		if not enemy_character:
			print("enemy_character is null")
