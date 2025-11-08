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

# Combat log
var combat_log: Array[String] = []
const MAX_LOG_ENTRIES = 20

# Debug window
var debug_enabled: bool = false

# Skill cooldowns
var player_skill_cooldowns: Dictionary = {}  # skill_name: turns_remaining
var enemy_skill_cooldowns: Dictionary = {}

@onready var wave_label = $WaveLabel
@onready var floor_label = $FloorLabel
@onready var dungeon_description_label = $DungeonDescriptionLabel
@onready var player_info = $PlayerInfo
@onready var enemy_info = $EnemyInfo
@onready var action_buttons = $ActionButtons
@onready var turn_label = $TurnLabel
@onready var inventory_menu = $InventoryMenu
@onready var xp_label = $XPLabel

# Combat log
@onready var combat_log_label = $CombatLog

# Debug window
@onready var debug_window = $DebugWindow
@onready var debug_toggle_button = $DebugToggleButton
@onready var debug_text = $DebugWindow/DebugText

func _ready():
	setup_battle()
	update_dungeon_labels()
	
	# Setup debug toggle button
	if debug_toggle_button:
		debug_toggle_button.connect("pressed", Callable(self, "toggle_debug_window"))
	
	# Initialize combat log
	add_to_combat_log("Battle begins!")

# Sets up the player character for the battle
func set_player(character: CharacterData):
	player_character = character

# Creates and scales the enemy character based on the current floor
func set_enemy(new_enemy: CharacterData):
	enemy_character = new_enemy
	for _i in range(current_floor - 1):
		enemy_character.level_up()
	enemy_character.calculate_secondary_attributes()
	print("Enemy loaded:", enemy_character.name)
	print("Enemy skills:", enemy_character.skills)

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
				
				# Show cooldown in button text
				if player_skill_cooldowns.has(skill.name) and player_skill_cooldowns[skill.name] > 0:
					skill_button.text = "%s (%d)" % [skill.name, player_skill_cooldowns[skill.name]]
					skill_button.disabled = true
				else:
					skill_button.text = skill.name
					skill_button.disabled = false
				
				skill_button.connect("pressed", Callable(self, "_on_skill_used").bind(skill))
				action_buttons.add_child(skill_button)

# Handles player attack action
func _on_attack_pressed():
	var result = player_character.attack(enemy_character)
	add_to_combat_log("[color=cyan]Player:[/color] " + result)
	update_turn_label(result)
	update_ui()
	update_debug_window()
	check_battle_end()
	if enemy_character.current_hp > 0:
		end_turn()

# Handles player defend action
func _on_defend_pressed():
	var result = player_character.defend()
	add_to_combat_log("[color=cyan]Player:[/color] " + result)
	update_turn_label(result)
	update_ui()
	update_debug_window()
	end_turn()

# Handles player items action
func _on_items_pressed():
	inventory_menu.show_inventory(player_character.inventory, player_character.currency)

# Handles player skill usage
func _on_skill_used(skill: Skill):
	# Check cooldown first
	if not can_use_skill(skill, true):
		var turns_left = player_skill_cooldowns[skill.name]
		var msg = "%s is on cooldown (%d turns remaining)" % [skill.name, turns_left]
		update_turn_label(msg)
		add_to_combat_log("[color=orange]" + msg + "[/color]")
		return
	
	if player_character.current_mp < skill.mp_cost:
		var msg = "Not enough MP to use %s" % skill.name
		update_turn_label(msg)
		add_to_combat_log("[color=orange]" + msg + "[/color]")
		return
	
	player_character.current_mp -= skill.mp_cost
	
	# Determine targets based on skill's target type
	var targets = []
	match skill.target:
		Skill.TargetType.SELF, Skill.TargetType.ALLY:
			targets = [player_character]
		Skill.TargetType.ENEMY:
			targets = [enemy_character]
		Skill.TargetType.ALL_ALLIES:
			targets = [player_character]
		Skill.TargetType.ALL_ENEMIES:
			targets = [enemy_character]
	
	var result = skill.use(player_character, targets)
	
	# Add to combat log
	add_to_combat_log("[color=cyan]Player used %s:[/color] %s" % [skill.name, result])
	
	# Start cooldown
	use_skill_with_cooldown(skill, true)
	
	update_turn_label(result)
	update_ui()
	update_debug_window()
	check_battle_end()
	if enemy_character.current_hp > 0:
		end_turn()

# Handles item usage
func _on_item_used(item: Item):
	# Check if item is actually a consumable before proceeding
	if item.item_type != Item.ItemType.CONSUMABLE:
		update_turn_label("This item cannot be used in battle.")
		return
	
	# Use the consumable
	var result = item.use(player_character, [player_character])
	add_to_combat_log("[color=cyan]Player used %s:[/color] %s" % [item.name, result])
	update_turn_label(result)
	update_ui()
	update_debug_window()
	check_battle_end()
	if enemy_character.current_hp > 0:
		end_turn()

# Executes a turn for the given character
func execute_turn(character: CharacterData):
	var status_message = character.update_status_effects()
	if status_message:
		add_to_combat_log(status_message)
		update_turn_label(status_message)
		update_ui()
		await get_tree().create_timer(1.0).timeout
	
	if character.is_stunned:
		var stun_msg = "%s is stunned and loses their turn!" % character.name
		add_to_combat_log("[color=purple]" + stun_msg + "[/color]")
		update_turn_label(stun_msg)
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
	
	print("Enemy Turn Debug:")
	print("- Current MP:", enemy_character.current_mp)
	print("- Skills:", enemy_character.skills)

	if action < 0.2:
		result = enemy_character.attack(player_character)
		add_to_combat_log("[color=red]Enemy:[/color] " + result)
	elif action < 0.3:
		result = enemy_character.defend()
		add_to_combat_log("[color=red]Enemy:[/color] " + result)
	else:
		if enemy_character.skills.size() > 0:
			var skill_name = enemy_character.skills[randi() % enemy_character.skills.size()]
			var skill = SkillManager.get_skill(skill_name)
			if not skill:
				result = "Enemy tried to use an unknown skill: %s" % skill_name
				add_to_combat_log("[color=red]" + result + "[/color]")
			elif enemy_character.current_mp < skill.mp_cost:
				result = "Enemy tried to use %s but didn't have enough MP" % skill.name
				print("Enemy MP too low for skill:", skill.name, "| MP:", enemy_character.current_mp, "/", skill.mp_cost)
				# fallback to a normal attack if not enough MP
				result = enemy_character.attack(player_character)
				add_to_combat_log("[color=red]Enemy:[/color] " + result)
			else:
				# Check cooldown
				if not can_use_skill(skill, false):
					# Skill on cooldown, use attack instead
					result = enemy_character.attack(player_character)
					add_to_combat_log("[color=red]Enemy:[/color] " + result)
				else:
					# use skill
					enemy_character.current_mp -= skill.mp_cost
					use_skill_with_cooldown(skill, false)
					var targets = [player_character] if skill.target in [Skill.TargetType.ENEMY, Skill.TargetType.ALL_ENEMIES] else [enemy_character]
					result = skill.use(enemy_character, targets)
					add_to_combat_log("[color=red]Enemy used %s:[/color] %s" % [skill.name, result])
					print("Enemy used skill:", skill.name, "| Remaining MP:", enemy_character.current_mp)
		else:
			result = enemy_character.attack(player_character)
			add_to_combat_log("[color=red]Enemy:[/color] " + result)
	
	update_turn_label(result)
	update_ui()
	update_debug_window()
	await get_tree().create_timer(2.0).timeout

	check_battle_end()
	if player_character.current_hp > 0:
		end_turn()

# Ends the current turn and starts the next
func end_turn():
	# Update cooldowns at end of turn
	update_cooldowns()
	
	if current_turn == "player":
		current_turn = "enemy"
		enemy_character.reset_defense()
		enable_player_actions(false)
		add_to_combat_log("--- [color=red]Enemy Turn[/color] ---")
		await get_tree().create_timer(1.0).timeout
		execute_turn(enemy_character)
	else:
		current_turn = "player"
		player_character.reset_defense()
		add_to_combat_log("--- [color=cyan]Player Turn[/color] ---")
		execute_turn(player_character)
	
	update_turn_label("It's %s's turn" % current_turn)
	update_debug_window()

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
		add_to_combat_log("[color=green]Victory! Enemy defeated![/color]")
		emit_signal("battle_completed", true)
	elif player_character.current_hp <= 0:
		add_to_combat_log("[color=red]Defeat! Player has fallen![/color]")
		emit_signal("battle_completed", false)

# Calculates rewards for the battle
func calculate_rewards(player_won: bool) -> Dictionary:
	var rewards = {}
	if player_won:
		var base_reward = 100 * (3 if is_boss_battle else 1)
		rewards["currency"] = base_reward
		rewards["health_potion"] = 1 if randf() < 0.5 else 0
	return rewards

# ============================================
# COMBAT LOG FUNCTIONS
# ============================================

func add_to_combat_log(message: String):
	var timestamp = "[Turn %d]" % (get_total_turns() + 1)
	combat_log.append("%s %s" % [timestamp, message])
	if combat_log.size() > MAX_LOG_ENTRIES:
		combat_log.pop_front()
	update_combat_log_display()

func update_combat_log_display():
	if not combat_log_label:
		return
	
	combat_log_label.clear()
	for entry in combat_log:
		combat_log_label.append_text(entry + "\n")
	
	# Auto-scroll to bottom
	await get_tree().process_frame
	combat_log_label.scroll_to_line(combat_log.size())

func get_total_turns() -> int:
	# Simple turn counter based on log entries
	return combat_log.size()

# ============================================
# DEBUG WINDOW FUNCTIONS
# ============================================

func toggle_debug_window():
	debug_enabled = !debug_enabled
	if debug_window:
		debug_window.visible = debug_enabled
	if debug_enabled:
		update_debug_window()

func update_debug_window():
	if not debug_enabled or not debug_text or not player_character or not enemy_character:
		return
	
	var debug_info = ""
	
	# Player stats
	debug_info += "[b]=== PLAYER ===[/b]\n"
	debug_info += format_character_debug(player_character)
	
	debug_info += "\n[b]=== ENEMY ===[/b]\n"
	debug_info += format_character_debug(enemy_character)
	
	debug_info += "\n[b]=== COOLDOWNS ===[/b]\n"
	if player_skill_cooldowns.size() > 0:
		debug_info += "[color=cyan]Player:[/color]\n"
		for skill_name in player_skill_cooldowns:
			if player_skill_cooldowns[skill_name] > 0:
				debug_info += "  %s: %d turns\n" % [skill_name, player_skill_cooldowns[skill_name]]
	else:
		debug_info += "Player: No skills on cooldown\n"
	
	if enemy_skill_cooldowns.size() > 0:
		debug_info += "[color=red]Enemy:[/color]\n"
		for skill_name in enemy_skill_cooldowns:
			if enemy_skill_cooldowns[skill_name] > 0:
				debug_info += "  %s: %d turns\n" % [skill_name, enemy_skill_cooldowns[skill_name]]
	
	debug_text.text = debug_info

func format_character_debug(character: CharacterData) -> String:
	var text = ""
	text += "[color=yellow]HP:[/color] %d/%d | [color=cyan]MP:[/color] %d/%d\n" % [
		character.current_hp, character.max_hp, 
		character.current_mp, character.max_mp
	]
	
	# Primary attributes with modifiers
	text += "\n[u]Primary Attributes:[/u]\n"
	var attrs = [
		Skill.AttributeTarget.VITALITY,
		Skill.AttributeTarget.STRENGTH, 
		Skill.AttributeTarget.DEXTERITY,
		Skill.AttributeTarget.INTELLIGENCE,
		Skill.AttributeTarget.FAITH,
		Skill.AttributeTarget.AGILITY,
		Skill.AttributeTarget.FORTITUDE
	]
	
	for attr in attrs:
		var attr_name = Skill.AttributeTarget.keys()[attr]
		var base_val = character.get(attr_name.to_lower())
		var modified_val = character.get_attribute_with_buffs_and_debuffs(attr)
		var modifier = modified_val - base_val
		
		if modifier > 0:
			text += "  %s: %d [color=green](+%d)[/color]\n" % [attr_name, modified_val, modifier]
		elif modifier < 0:
			text += "  %s: %d [color=red](%d)[/color]\n" % [attr_name, modified_val, modifier]
		else:
			text += "  %s: %d\n" % [attr_name, base_val]
	
	# Secondary attributes
	text += "\n[u]Secondary Attributes:[/u]\n"
	text += "  Attack Power: %.1f\n" % character.get_attack_power()
	text += "  Spell Power: %.1f\n" % character.spell_power
	text += "  Defense: %d\n" % character.get_defense()
	text += "  Dodge: %.1f%%\n" % (character.dodge * 100)
	text += "  Crit Rate: %.1f%%\n" % (character.critical_hit_rate * 100)
	text += "  Accuracy: %.1f%%\n" % (character.accuracy * 100)
	
	# Active effects
	text += "\n[u]Active Effects:[/u]\n"
	var has_effects = false
	
	if character.status_effects.size() > 0:
		has_effects = true
		for effect in character.status_effects:
			var effect_name = Skill.StatusEffect.keys()[effect]
			text += "  [color=purple]%s[/color] (%d turns)\n" % [effect_name, character.status_effects[effect]]
	
	if character.buffs.size() > 0:
		has_effects = true
		for attr in character.buffs:
			var attr_name = Skill.AttributeTarget.keys()[attr]
			text += "  [color=green]Buff %s[/color]: +%d (%d turns)\n" % [
				attr_name, 
				character.buffs[attr].value, 
				character.buffs[attr].duration
			]
	
	if character.debuffs.size() > 0:
		has_effects = true
		for attr in character.debuffs:
			var attr_name = Skill.AttributeTarget.keys()[attr]
			# Debuff values are stored as positive, but represent reduction
			text += "  [color=red]Debuff %s[/color]: -%d (%d turns)\n" % [
				attr_name, 
				abs(character.debuffs[attr].value),  # Use abs() to ensure positive display
				character.debuffs[attr].duration
			]
	
	if not has_effects:
		text += "  None\n"
	
	return text

# ============================================
# COOLDOWN FUNCTIONS
# ============================================

func update_cooldowns():
	# Decrement player cooldowns
	for skill_name in player_skill_cooldowns.keys():
		player_skill_cooldowns[skill_name] -= 1
		if player_skill_cooldowns[skill_name] <= 0:
			add_to_combat_log("[color=cyan]%s ready![/color]" % skill_name)
			player_skill_cooldowns.erase(skill_name)
	
	# Decrement enemy cooldowns
	for skill_name in enemy_skill_cooldowns.keys():
		enemy_skill_cooldowns[skill_name] -= 1
		if enemy_skill_cooldowns[skill_name] <= 0:
			enemy_skill_cooldowns.erase(skill_name)
	
	# Refresh action buttons to update cooldown display
	setup_action_buttons()

func can_use_skill(skill: Skill, is_player: bool) -> bool:
	var cooldowns = player_skill_cooldowns if is_player else enemy_skill_cooldowns
	return not cooldowns.has(skill.name) or cooldowns[skill.name] <= 0

func use_skill_with_cooldown(skill: Skill, is_player: bool):
	var cooldowns = player_skill_cooldowns if is_player else enemy_skill_cooldowns
	if skill.cooldown > 0:
		cooldowns[skill.name] = skill.cooldown
