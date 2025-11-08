# res://scenes/battle/Battle.gd
extends Node2D

signal battle_completed(player_won, xp_gained)

var player_character: CharacterData
var enemy_character: CharacterData
var current_turn: String = "player"
var turn_number: int = 0  # Global turn counter for the entire battle
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
@onready var combat_log = $CombatLog
@onready var debug_log = $DebugWindow/DebugText

func _ready():
	setup_battle()
	update_dungeon_labels()

# Sets up the player character for the battle
func set_player(character: CharacterData):
	player_character = character

# Sets up the enemy character for battle (scaling is now done in EnemyFactory)
func set_enemy(new_enemy: CharacterData):
	enemy_character = new_enemy
	enemy_character.calculate_secondary_attributes()
	print("Enemy loaded:", enemy_character.name)
	print("Enemy skills:", enemy_character.skills)
	print("Enemy HP: %d/%d | Attack: %.1f | Defense: %.1f" % [enemy_character.current_hp, enemy_character.max_hp, enemy_character.attack_power, enemy_character.toughness])

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
				var cd = player_character.get_skill_cooldown(skill_name)
				if cd > 0:
					skill_button.text = "%s (CD: %d)" % [skill.name, cd]
					skill_button.disabled = true
				else:
					skill_button.text = skill.name
				skill_button.connect("pressed", Callable(self, "_on_skill_used").bind(skill))
				action_buttons.add_child(skill_button)

# Handles player attack action
func _on_attack_pressed():
	var result = player_character.attack(enemy_character)
	update_turn_label(result)
	add_to_combat_log("[color=yellow]Player:[/color] " + result)
	update_ui()
	check_battle_end()
	if enemy_character.current_hp > 0:
		end_turn()

# Handles player defend action
func _on_defend_pressed():
	var result = player_character.defend()
	update_turn_label(result)
	add_to_combat_log("[color=yellow]Player:[/color] " + result)
	update_ui()
	end_turn()

# Handles player items action
func _on_items_pressed():
	inventory_menu.show_inventory(player_character.inventory, player_character.currency)

# Handles player skill usage
func _on_skill_used(skill: Skill):
	# Check if skill is on cooldown
	if not player_character.is_skill_ready(skill.name):
		var cd_remaining = player_character.get_skill_cooldown(skill.name)
		update_turn_label("%s is on cooldown for %d more turn(s)" % [skill.name, cd_remaining])
		return
	
	if player_character.current_mp < skill.mp_cost:
		update_turn_label("Not enough MP to use this skill")
		return
	
	player_character.current_mp -= skill.mp_cost
	
	# Determine targets based on skill target type
	var targets = []
	match skill.target:
		Skill.TargetType.SELF:
			targets = [player_character]
		Skill.TargetType.ALLY:
			targets = [player_character]  # In 1v1, ally = self
		Skill.TargetType.ALL_ALLIES:
			targets = [player_character]  # In 1v1, all allies = self
		Skill.TargetType.ENEMY:
			targets = [enemy_character]
		Skill.TargetType.ALL_ENEMIES:
			targets = [enemy_character]  # In 1v1, all enemies = enemy
	
	var result = skill.use(player_character, targets)
	
	# Set skill on cooldown
	player_character.use_skill_cooldown(skill.name, skill.cooldown)
	
	update_turn_label(result)
	add_to_combat_log("[color=cyan]Player used %s:[/color] %s" % [skill.name, result])
	update_ui()
	check_battle_end()
	if enemy_character.current_hp > 0:
		end_turn()

# Handles item usage
func _on_item_used(item: Item):
	if item.item_type == Item.ItemType.CONSUMABLE:
		var result = item.use(player_character, [player_character])
		update_turn_label(result)
		add_to_combat_log("[color=lime]Player used %s:[/color] %s" % [item.name, result])
		player_character.inventory.remove_item(item.id, 1)
		update_ui()
		check_battle_end()
		if enemy_character.current_hp > 0:
			end_turn()
	else:
		update_turn_label("This item cannot be used in battle.")

# Executes a turn for the given character
func execute_turn(character: CharacterData):
	# Reduce cooldowns at the START of this character's turn
	character.reduce_cooldowns()
	
	var status_message = character.update_status_effects()
	if status_message:
		update_turn_label(status_message)
		add_to_combat_log("[color=purple]Status Effect:[/color] " + status_message)
		update_ui()
		await get_tree().create_timer(1.0).timeout
	
	if character.is_stunned:
		var stun_msg = "%s is stunned and loses their turn!" % character.name
		update_turn_label(stun_msg)
		add_to_combat_log("[color=purple]" + stun_msg + "[/color]")
		character.is_stunned = false
		await get_tree().create_timer(1.0).timeout
		end_turn()
		return
	
	if character == player_character:
		setup_action_buttons()  # Refresh buttons to show updated cooldowns
		enable_player_actions(true)
	else:
		execute_enemy_turn()

# Battle.gd - Smart Enemy AI Update
# Add this new function to replace execute_enemy_turn()

func execute_enemy_turn():
	update_turn_label("Enemy's turn")
	await get_tree().create_timer(1.0).timeout

	var action = decide_enemy_action()
	var result = ""
	
	match action.type:
		"attack":
			result = enemy_character.attack(player_character)
			add_to_combat_log("[color=red]Enemy:[/color] " + result)
		"defend":
			result = enemy_character.defend()
			add_to_combat_log("[color=red]Enemy:[/color] " + result)
		"skill":
			var skill = action.skill
			enemy_character.current_mp -= skill.mp_cost
			
			var targets = get_skill_targets(skill, enemy_character, player_character)
			result = skill.use(enemy_character, targets)
			add_to_combat_log("[color=orange]Enemy used %s:[/color] %s" % [skill.name, result])
			
			enemy_character.use_skill_cooldown(skill.name, skill.cooldown)
			print("Enemy used skill:", skill.name, "| Remaining MP:", enemy_character.current_mp)
	
	update_turn_label(result)
	update_ui()
	await get_tree().create_timer(2.0).timeout

	check_battle_end()
	if player_character.current_hp > 0:
		end_turn()

# New AI decision-making function
func decide_enemy_action() -> Dictionary:
	var available_actions = []
	
	# Evaluate HP situation
	var enemy_hp_percent = float(enemy_character.current_hp) / float(enemy_character.max_hp)
	var player_hp_percent = float(player_character.current_hp) / float(player_character.max_hp)
	
	# Check available skills
	var available_skills = []
	for skill_name in enemy_character.skills:
		var skill = SkillManager.get_skill(skill_name)
		if skill and enemy_character.is_skill_ready(skill_name) and enemy_character.current_mp >= skill.mp_cost:
			available_skills.append(skill)
	
	# PRIORITY 1: Self-preservation (Heal if low HP and has heal skill)
	if enemy_hp_percent < 0.3:
		for skill in available_skills:
			if skill.type == Skill.SkillType.HEAL:
				print("AI: Low HP detected (%.1f%%), using heal skill" % (enemy_hp_percent * 100))
				return {"type": "skill", "skill": skill, "priority": 10}
	
	# PRIORITY 2: Finish off low HP player
	if player_hp_percent < 0.25:
		# Look for high damage skills
		for skill in available_skills:
			if skill.type == Skill.SkillType.DAMAGE:
				print("AI: Player low HP (%.1f%%), going for kill" % (player_hp_percent * 100))
				return {"type": "skill", "skill": skill, "priority": 9}
		# If no damage skill, attack
		print("AI: Player low HP, attacking for kill")
		return {"type": "attack", "priority": 9}
	
	# PRIORITY 3: Apply debuffs if player has none
	if player_character.debuffs.size() == 0 and player_character.status_effects.size() == 0:
		for skill in available_skills:
			if skill.type == Skill.SkillType.DEBUFF or skill.type == Skill.SkillType.INFLICT_STATUS:
				print("AI: Applying debuff to weaken player")
				return {"type": "skill", "skill": skill, "priority": 8}
	
	# PRIORITY 4: Buff self if no buffs active and HP is healthy
	if enemy_character.buffs.size() == 0 and enemy_hp_percent > 0.5:
		for skill in available_skills:
			if skill.type == Skill.SkillType.BUFF:
				print("AI: Buffing self for advantage")
				return {"type": "skill", "skill": skill, "priority": 7}
	
	# PRIORITY 5: Use powerful damage skills when MP is high
	var mp_percent = float(enemy_character.current_mp) / float(enemy_character.max_mp)
	if mp_percent > 0.6:
		# Find highest power damage skill
		var best_damage_skill = null
		var highest_power = 0
		for skill in available_skills:
			if skill.type == Skill.SkillType.DAMAGE and skill.power > highest_power:
				best_damage_skill = skill
				highest_power = skill.power
		
		if best_damage_skill:
			print("AI: MP high (%.1f%%), using powerful damage skill" % (mp_percent * 100))
			return {"type": "skill", "skill": best_damage_skill, "priority": 6}
	
	# PRIORITY 6: Defend if low HP and no heal available
	if enemy_hp_percent < 0.35:
		print("AI: Low HP and no heal, defending")
		return {"type": "defend", "priority": 5}
	
	# PRIORITY 7: Use any available damage skill
	for skill in available_skills:
		if skill.type == Skill.SkillType.DAMAGE:
			print("AI: Using available damage skill")
			return {"type": "skill", "skill": skill, "priority": 4}
	
	# PRIORITY 8: Use restore skills if MP is low
	if mp_percent < 0.3:
		for skill in available_skills:
			if skill.type == Skill.SkillType.RESTORE:
				print("AI: MP low, using restore skill")
				return {"type": "skill", "skill": skill, "priority": 3}
	
	# PRIORITY 9: Random behavior for variety (20% chance)
	if randf() < 0.2:
		var random_action = randf()
		if random_action < 0.5 and available_skills.size() > 0:
			print("AI: Random skill use")
			return {"type": "skill", "skill": available_skills[randi() % available_skills.size()], "priority": 2}
		elif random_action < 0.7:
			print("AI: Random defend")
			return {"type": "defend", "priority": 2}
	
	# DEFAULT: Basic attack
	print("AI: Default attack")
	return {"type": "attack", "priority": 1}

# Helper function to get correct targets for a skill
func get_skill_targets(skill: Skill, caster: CharacterData, opponent: CharacterData) -> Array:
	var targets = []
	match skill.target:
		Skill.TargetType.SELF:
			targets = [caster]
		Skill.TargetType.ALLY:
			targets = [caster]  # In 1v1, ally = self
		Skill.TargetType.ALL_ALLIES:
			targets = [caster]  # In 1v1, all allies = self
		Skill.TargetType.ENEMY:
			targets = [opponent]
		Skill.TargetType.ALL_ENEMIES:
			targets = [opponent]  # In 1v1, all enemies = opponent
	return targets
	
# Ends the current turn and starts the next
func end_turn():
	turn_number += 1
	print("\n=== Turn %d Complete ===" % turn_number)
	
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
	update_turn_label("Turn %d - %s's turn" % [turn_number + 1, current_turn.capitalize()])

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
	
	# Update debug log with secondary stats
	if debug_log:
		update_debug_log()

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

# Adds a message to the combat log (player-facing)
func add_to_combat_log(message: String):
	if combat_log:
		combat_log.append_text(message + "\n")

# Updates the debug log with secondary stats for monitoring
func update_debug_log():
	if not debug_log:
		return
	
	debug_log.clear()
	debug_log.append_text("[b][color=cyan]PLAYER STATS[/color][/b]\n")
	debug_log.append_text("ATK Power: %.1f | Spell Power: %.1f\n" % [player_character.attack_power, player_character.spell_power])
	debug_log.append_text("Toughness: %.1f | Spell Ward: %.1f\n" % [player_character.toughness, player_character.spell_ward])
	debug_log.append_text("Accuracy: %.2f%% | Dodge: %.2f%% | Crit: %.2f%%\n" % [player_character.accuracy * 100, player_character.dodge * 100, player_character.critical_hit_rate * 100])
	
	# Show active buffs
	if player_character.buffs.size() > 0:
		debug_log.append_text("[color=green]Buffs:[/color] ")
		for attr in player_character.buffs:
			debug_log.append_text("%s +%d (%d turns) " % [Skill.AttributeTarget.keys()[attr], player_character.buffs[attr].value, player_character.buffs[attr].duration])
		debug_log.append_text("\n")
	
	# Show active debuffs (FIXED: minus sign for debuffs)
	if player_character.debuffs.size() > 0:
		debug_log.append_text("[color=red]Debuffs:[/color] ")
		for attr in player_character.debuffs:
			debug_log.append_text("%s -%d (%d turns) " % [Skill.AttributeTarget.keys()[attr], player_character.debuffs[attr].value, player_character.debuffs[attr].duration])
		debug_log.append_text("\n")
	
	debug_log.append_text("\n[b][color=orange]ENEMY STATS[/color][/b]\n")
	debug_log.append_text("ATK Power: %.1f | Spell Power: %.1f\n" % [enemy_character.attack_power, enemy_character.spell_power])
	debug_log.append_text("Toughness: %.1f | Spell Ward: %.1f\n" % [enemy_character.toughness, enemy_character.spell_ward])
	debug_log.append_text("Accuracy: %.2f%% | Dodge: %.2f%% | Crit: %.2f%%\n" % [enemy_character.accuracy * 100, enemy_character.dodge * 100, enemy_character.critical_hit_rate * 100])
	
	# Show active buffs
	if enemy_character.buffs.size() > 0:
		debug_log.append_text("[color=green]Buffs:[/color] ")
		for attr in enemy_character.buffs:
			debug_log.append_text("%s +%d (%d turns) " % [Skill.AttributeTarget.keys()[attr], enemy_character.buffs[attr].value, enemy_character.buffs[attr].duration])
		debug_log.append_text("\n")
	
	# Show active debuffs (FIXED: minus sign for debuffs)
	if enemy_character.debuffs.size() > 0:
		debug_log.append_text("[color=red]Debuffs:[/color] ")
		for attr in enemy_character.debuffs:
			debug_log.append_text("%s -%d (%d turns) " % [Skill.AttributeTarget.keys()[attr], enemy_character.debuffs[attr].value, enemy_character.debuffs[attr].duration])
		debug_log.append_text("\n")

# Add this test function to Battle.gd to verify rarity distribution:
func test_rarity_distribution():
	var rarity_counts = {
		"common": 0,
		"uncommon": 0,
		"magic": 0,
		"epic": 0,
		"legendary": 0
	}
	
	# Generate 1000 random items
	for i in range(1000):
		var weapon = ItemManager.get_random_weapon()
		if weapon:
			var weapon_item = ItemManager.get_item(weapon)
			if weapon_item and weapon_item is Equipment:
				rarity_counts[weapon_item.rarity] += 1
	
	print("\n=== RARITY DISTRIBUTION TEST (1000 items) ===")
	for rarity in rarity_counts:
		var percent = (float(rarity_counts[rarity]) / 1000.0) * 100.0
		print("%s: %d (%.1f%%)" % [rarity.capitalize(), rarity_counts[rarity], percent])
	print("===========================================\n")
	
# The following functions have been commented out as they seem to be unused or for debugging purposes:
# func show_reward_scene(player_won: bool):
# func position_ui_elements():
# func print_visible_ui():
# func force_update_ui():
