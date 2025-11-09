# res://scenes/battle/Battle.gd
extends Node2D

signal battle_completed(player_won, xp_gained)

var player_character: CharacterData
var enemy_character: CharacterData
var current_turn: String = "player"
var turn_number: int = 0
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

func set_player(character: CharacterData):
	player_character = character

func set_enemy(new_enemy: CharacterData):
	enemy_character = new_enemy
	enemy_character.calculate_secondary_attributes()
	print("Enemy loaded:", enemy_character.name)
	print("Enemy skills:", enemy_character.skills)
	print("Enemy HP: %d/%d | SP: %d/%d | Attack: %.1f | Defense: %.1f" % [
		enemy_character.current_hp, 
		enemy_character.max_hp, 
		enemy_character.current_sp,
		enemy_character.max_sp,
		enemy_character.attack_power, 
		enemy_character.toughness
	])

func set_dungeon_info(wave: int, floor: int, description: String):
	current_wave = wave
	current_floor = floor
	dungeon_description = description
	update_dungeon_labels()

func update_dungeon_labels():
	$WaveLabel.text = "Wave: %d" % current_wave
	$FloorLabel.text = "Floor: %d" % current_floor
	$DungeonDescriptionLabel.text = dungeon_description

func setup_battle():
	player_character = player_character if player_character else CharacterManager.get_current_character()
	enemy_character = enemy_character if enemy_character else EnemyFactory.create_enemy()
	
	if not player_character or not enemy_character:
		print("Battle: Error - Failed to load characters")
		SceneManager.change_scene("res://scenes/ui/MainMenu.tscn")
		return
	
	# Validate player character has all required properties
	if not validate_character(player_character, "Player"):
		return
	
	# Validate enemy character has all required properties
	if not validate_character(enemy_character, "Enemy"):
		return
	
	# CRITICAL FIX: Ensure SP is initialized
	if player_character.current_sp == 0:
		player_character.current_sp = player_character.max_sp
		print("Initialized player SP to max: %d" % player_character.max_sp)
	
	if enemy_character.current_sp == 0:
		enemy_character.current_sp = enemy_character.max_sp
		print("Initialized enemy SP to max: %d" % enemy_character.max_sp)
	
	inventory_menu.show_inventory(player_character.inventory, player_character.currency)
	inventory_menu.hide()
	
	update_ui()
	setup_action_buttons()
	start_battle()

func validate_character(character: CharacterData, char_type: String) -> bool:
	"""Validate that a character has all required properties initialized"""
	if not character or not is_instance_valid(character):
		push_error("Battle: %s character is null or invalid" % char_type)
		SceneManager.change_scene("res://scenes/ui/MainMenu.tscn")
		return false
	
	# Check critical properties
	var required_properties = ["dodge", "toughness", "accuracy", "critical_hit_rate", 
								"max_hp", "current_hp", "max_mp", "current_mp", 
								"max_sp", "current_sp", "attack_power", "spell_power"]
	
	for prop in required_properties:
		if not prop in character:
			push_error("Battle: %s character missing property: %s" % [char_type, prop])
			SceneManager.change_scene("res://scenes/ui/MainMenu.tscn")
			return false
	
	# Ensure current values are within valid ranges
	character.current_hp = clamp(character.current_hp, 0, character.max_hp)
	character.current_mp = clamp(character.current_mp, 0, character.max_mp)
	character.current_sp = clamp(character.current_sp, 0, character.max_sp)
	
	print("Battle: %s character validated: %s (HP: %d/%d, MP: %d/%d, SP: %d/%d)" % [
		char_type, character.name,
		character.current_hp, character.max_hp,
		character.current_mp, character.max_mp,
		character.current_sp, character.max_sp
	])
	
	return true

func start_battle():
	current_turn = "player"
	update_turn_label("Battle starts! It's your turn.")
	enable_player_actions(true)

func update_turn_label(text: String):
	turn_label.text = text

func enable_player_actions(enabled: bool):
	for button in action_buttons.get_children():
		if button is Button:
			button.disabled = !enabled

func setup_action_buttons():
	for child in action_buttons.get_children():
		child.queue_free()
	
	var buttons = ["Attack", "Defend", "Items", "View Enemy Equipment"]
	for button_name in buttons:
		var button = Button.new()
		button.text = button_name
		var method_name = "_on_" + button_name.to_lower().replace(" ", "_") + "_pressed"
		button.connect("pressed", Callable(self, method_name))
		action_buttons.add_child(button)
	
	if player_character:
		for skill_name in player_character.skills:
			var skill = player_character.get_skill_instance(skill_name)
			if not skill:
				skill = SkillManager.get_skill(skill_name)
			if skill:
				var skill_button = Button.new()
				var cd = player_character.get_skill_cooldown(skill_name)
				
				# Get skill level display
				var level_text = " Lv." + skill.get_level_string()
				
				# Display SP or MP cost based on ability type
				var cost_text = ""
				var cost_value = 0
				var resource_available = 0
				
				if skill.ability_type == Skill.AbilityType.PHYSICAL:
					cost_text = "[%d SP]"
					cost_value = skill.sp_cost
					resource_available = player_character.current_sp
				else:
					cost_text = "[%d MP]"
					cost_value = skill.mp_cost
					resource_available = player_character.current_mp
				
				if cd > 0:
					skill_button.text = "%s%s (CD: %d) " % [skill.name, level_text, cd] + cost_text % cost_value
					skill_button.disabled = true
				elif resource_available < cost_value:
					# Not enough resources
					skill_button.text = "%s%s " % [skill.name, level_text] + cost_text % cost_value
					skill_button.disabled = true
				else:
					skill_button.text = "%s%s " % [skill.name, level_text] + cost_text % cost_value
				
				skill_button.connect("pressed", Callable(self, "_on_skill_used").bind(skill))
				action_buttons.add_child(skill_button)

func _on_attack_pressed():
	var result = player_character.attack(enemy_character)
	update_turn_label(result)
	add_to_combat_log("[color=yellow]Player:[/color] " + result)
	update_ui()
	check_battle_end()
	if enemy_character.current_hp > 0:
		end_turn()

func _on_defend_pressed():
	var result = player_character.defend()
	update_turn_label(result)
	add_to_combat_log("[color=yellow]Player:[/color] " + result)
	update_ui()
	end_turn()

func _on_items_pressed():
	inventory_menu.show_inventory(player_character.inventory, player_character.currency)

func _on_view_enemy_equipment_pressed():
	show_enemy_equipment_dialog()

func show_enemy_equipment_dialog():
	var dialog = AcceptDialog.new()
	dialog.title = "Enemy Equipment"
	dialog.ok_button_text = "Close"
	
	var rich_label = RichTextLabel.new()
	rich_label.bbcode_enabled = true
	rich_label.fit_content = true
	rich_label.custom_minimum_size = Vector2(400, 300)
	rich_label.append_text(get_enemy_equipment_text())
	
	dialog.add_child(rich_label)
	add_child(dialog)
	dialog.popup_centered()
	await dialog.confirmed
	dialog.queue_free()

func get_enemy_equipment_text() -> String:
	var text = "[b]%s's Equipment:[/b]\n\n" % enemy_character.name
	
	for slot in enemy_character.equipment:
		var item = enemy_character.equipment[slot]
		var slot_name = slot.capitalize().replace("_", " ")
		if item and item is Equipment:
			var color = item.get_rarity_color()
			text += "[b]%s:[/b] [color=%s]%s[/color] (%s)\n" % [slot_name, color, item.name, item.rarity.capitalize()]
			text += "  Damage: %d | Armor: %d\n" % [item.damage, item.armor_value]
		else:
			text += "[b]%s:[/b] Empty\n" % slot_name
	
	return text

func _on_skill_used(skill_raw):
	# Get the skill instance from the character
	var skill = skill_raw
	if skill_raw is String:
		skill = player_character.get_skill_instance(skill_raw)
	elif skill_raw is Skill:
		# If we have a base skill, get the character's leveled instance
		skill = player_character.get_skill_instance(skill_raw.name)
		if not skill:
			skill = skill_raw
	
	if not skill:
		update_turn_label("Error: Skill not found")
		return
		
	if not player_character.is_skill_ready(skill.name):
		var cd_remaining = player_character.get_skill_cooldown(skill.name)
		update_turn_label("%s is on cooldown for %d more turn(s)" % [skill.name, cd_remaining])
		return
	
	# Check SP for physical skills, MP for magical skills
	if skill.ability_type == Skill.AbilityType.PHYSICAL:
		if player_character.current_sp < skill.sp_cost:
			update_turn_label("Not enough SP to use this skill (Have: %d, Need: %d)" % [player_character.current_sp, skill.sp_cost])
			return
		player_character.current_sp -= skill.sp_cost
		print("Used %d SP. Remaining: %d/%d" % [skill.sp_cost, player_character.current_sp, player_character.max_sp])
	else:
		if player_character.current_mp < skill.mp_cost:
			update_turn_label("Not enough MP to use this skill (Have: %d, Need: %d)" % [player_character.current_mp, skill.mp_cost])
			return
		player_character.current_mp -= skill.mp_cost
		print("Used %d MP. Remaining: %d/%d" % [skill.mp_cost, player_character.current_mp, player_character.max_mp])
	
	var targets = []
	match skill.target:
		Skill.TargetType.SELF:
			targets = [player_character]
		Skill.TargetType.ALLY:
			targets = [player_character]
		Skill.TargetType.ALL_ALLIES:
			targets = [player_character]
		Skill.TargetType.ENEMY:
			targets = [enemy_character]
		Skill.TargetType.ALL_ENEMIES:
			targets = [enemy_character]
	
	var result = skill.use(player_character, targets)
	
	# Track skill usage and check for level up
	var level_up_msg = player_character.use_skill(skill.name)
	if level_up_msg != "":
		add_to_combat_log("[color=cyan]" + level_up_msg + "[/color]")
	
	update_turn_label(result)
	add_to_combat_log("[color=orange]Player used %s (Lv.%s):[/color] %s" % [skill.name, skill.get_level_string(), result])
	
	player_character.use_skill_cooldown(skill.name, skill.cooldown)
	
	update_ui()
	check_battle_end()
	if enemy_character.current_hp > 0:
		end_turn()

func _on_item_used(item: Item):
	if item.item_type == Item.ItemType.CONSUMABLE:
		# Determine targets based on consumable type
		var targets = []
		match item.consumable_type:
			Item.ConsumableType.DAMAGE, Item.ConsumableType.DEBUFF:
				# Damage and debuff items target the enemy
				targets = [enemy_character]
			Item.ConsumableType.HEAL, Item.ConsumableType.BUFF, Item.ConsumableType.RESTORE, Item.ConsumableType.CURE:
				# Heal, buff, restore, and cure items target the player
				targets = [player_character]
			_:
				# Default to player if unknown type
				targets = [player_character]
		
		var result = item.use(player_character, targets)
		update_turn_label(result)
		add_to_combat_log("[color=lime]Player used %s:[/color] %s" % [item.name, result])
		player_character.inventory.remove_item(item.id, 1)
		update_ui()
		check_battle_end()
		if enemy_character.current_hp > 0:
			end_turn()
	else:
		update_turn_label("This item cannot be used in battle.")

func execute_turn(character: CharacterData):
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
		setup_action_buttons()
		enable_player_actions(true)
	else:
		execute_enemy_turn()

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
			# Use SP for physical skills, MP for magical skills
			if skill.ability_type == Skill.AbilityType.PHYSICAL:
				enemy_character.current_sp -= skill.sp_cost
			else:
				enemy_character.current_mp -= skill.mp_cost
			
			var targets = get_skill_targets(skill, enemy_character, player_character)
			result = skill.use(enemy_character, targets)
			add_to_combat_log("[color=orange]Enemy used %s:[/color] %s" % [skill.name, result])
			
			enemy_character.use_skill_cooldown(skill.name, skill.cooldown)
			print("Enemy used skill:", skill.name, "| Remaining MP:", enemy_character.current_mp, "| Remaining SP:", enemy_character.current_sp)
	
	update_turn_label(result)
	update_ui()
	await get_tree().create_timer(2.0).timeout

	check_battle_end()
	if player_character.current_hp > 0:
		end_turn()

func decide_enemy_action() -> Dictionary:
	var available_actions = []
	
	var enemy_hp_percent = float(enemy_character.current_hp) / float(enemy_character.max_hp)
	var player_hp_percent = float(player_character.current_hp) / float(player_character.max_hp)
	
	var available_skills = []
	for skill_name in enemy_character.skills:
		var skill = SkillManager.get_skill(skill_name)
		if skill and enemy_character.is_skill_ready(skill_name):
			# Check SP for physical skills, MP for magical skills
			if skill.ability_type == Skill.AbilityType.PHYSICAL:
				if enemy_character.current_sp >= skill.sp_cost:
					available_skills.append(skill)
			else:
				if enemy_character.current_mp >= skill.mp_cost:
					available_skills.append(skill)
	
	if enemy_hp_percent < 0.3:
		for skill in available_skills:
			if skill.type == Skill.SkillType.HEAL:
				print("AI: Low HP detected (%.1f%%), using heal skill" % (enemy_hp_percent * 100))
				return {"type": "skill", "skill": skill, "priority": 10}
	
	if player_hp_percent < 0.25:
		for skill in available_skills:
			if skill.type == Skill.SkillType.DAMAGE:
				print("AI: Player low HP (%.1f%%), going for kill" % (player_hp_percent * 100))
				return {"type": "skill", "skill": skill, "priority": 9}
		print("AI: Player low HP, attacking for kill")
		return {"type": "attack", "priority": 9}
	
	if player_character.debuffs.size() == 0 and player_character.status_effects.size() == 0:
		for skill in available_skills:
			if skill.type == Skill.SkillType.DEBUFF or skill.type == Skill.SkillType.INFLICT_STATUS:
				print("AI: Applying debuff to weaken player")
				return {"type": "skill", "skill": skill, "priority": 8}
	
	if enemy_character.buffs.size() == 0 and enemy_hp_percent > 0.5:
		for skill in available_skills:
			if skill.type == Skill.SkillType.BUFF:
				print("AI: Buffing self for advantage")
				return {"type": "skill", "skill": skill, "priority": 7}
	
	var mp_percent = float(enemy_character.current_mp) / float(enemy_character.max_mp)
	var sp_percent = float(enemy_character.current_sp) / float(enemy_character.max_sp)
	
	# Use skills if resources are available
	if mp_percent > 0.6 or sp_percent > 0.6:
		var best_damage_skill = null
		var highest_power = 0
		for skill in available_skills:
			if skill.type == Skill.SkillType.DAMAGE and skill.power > highest_power:
				best_damage_skill = skill
				highest_power = skill.power
		
		if best_damage_skill:
			print("AI: Resources high, using powerful damage skill")
			return {"type": "skill", "skill": best_damage_skill, "priority": 6}
	
	if enemy_hp_percent < 0.35:
		print("AI: Low HP and no heal, defending")
		return {"type": "defend", "priority": 5}
	
	for skill in available_skills:
		if skill.type == Skill.SkillType.DAMAGE:
			print("AI: Using available damage skill")
			return {"type": "skill", "skill": skill, "priority": 4}
	
	if randf() < 0.2:
		var random_action = randf()
		if random_action < 0.5 and available_skills.size() > 0:
			print("AI: Random skill use")
			return {"type": "skill", "skill": available_skills[randi() % available_skills.size()], "priority": 2}
		elif random_action < 0.7:
			print("AI: Random defend")
			return {"type": "defend", "priority": 2}
	
	print("AI: Default attack")
	return {"type": "attack", "priority": 1}

func get_skill_targets(skill: Skill, caster: CharacterData, opponent: CharacterData) -> Array:
	var targets = []
	match skill.target:
		Skill.TargetType.SELF:
			targets = [caster]
		Skill.TargetType.ALLY:
			targets = [caster]
		Skill.TargetType.ALL_ALLIES:
			targets = [caster]
		Skill.TargetType.ENEMY:
			targets = [opponent]
		Skill.TargetType.ALL_ENEMIES:
			targets = [opponent]
	return targets
	
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

func update_ui():
	if player_info and enemy_info and player_character and enemy_character:
		# FIXED: Added SP display
		player_info.text = "Player: %s\nHP: %d/%d\nMP: %d/%d\nSP: %d/%d\nStatus: %s" % [
			player_character.name, 
			player_character.current_hp, 
			player_character.max_hp,
			player_character.current_mp, 
			player_character.max_mp,
			player_character.current_sp,
			player_character.max_sp,
			player_character.get_status_effects_string()
		]
		enemy_info.text = "Enemy: %s\nHP: %d/%d\nMP: %d/%d\nSP: %d/%d\nStatus: %s" % [
			enemy_character.name, 
			enemy_character.current_hp, 
			enemy_character.max_hp,
			enemy_character.current_mp, 
			enemy_character.max_mp,
			enemy_character.current_sp,
			enemy_character.max_sp,
			enemy_character.get_status_effects_string()
		]
	
	if xp_label:
		xp_label.text = "XP: %d / %d" % [player_character.xp, LevelSystem.calculate_xp_for_level(player_character.level)]
	
	if debug_log:
		update_debug_log()

func check_battle_end():
	if enemy_character.current_hp <= 0:
		emit_signal("battle_completed", true)
	elif player_character.current_hp <= 0:
		emit_signal("battle_completed", false)

func calculate_rewards(player_won: bool) -> Dictionary:
	var rewards = {}
	if player_won:
		var base_reward = 100 * (3 if is_boss_battle else 1)
		rewards["currency"] = base_reward
		rewards["health_potion"] = 1 if randf() < 0.5 else 0
	return rewards

func add_to_combat_log(message: String):
	if combat_log:
		combat_log.append_text(message + "\n")

func update_debug_log():
	if not debug_log:
		return
	
	debug_log.clear()
	debug_log.append_text("[b][color=cyan]PLAYER STATS[/color][/b]\n")
	debug_log.append_text("ATK Power: %.1f | Spell Power: %.1f\n" % [player_character.attack_power, player_character.spell_power])
	debug_log.append_text("Toughness: %.1f | Spell Ward: %.1f\n" % [player_character.toughness, player_character.spell_ward])
	debug_log.append_text("Accuracy: %.2f%% | Dodge: %.2f%% | Crit: %.2f%%\n" % [player_character.accuracy * 100, player_character.dodge * 100, player_character.critical_hit_rate * 100])
	debug_log.append_text("SP: %d/%d | MP: %d/%d\n" % [player_character.current_sp, player_character.max_sp, player_character.current_mp, player_character.max_mp])
	
	if player_character.buffs.size() > 0:
		debug_log.append_text("[color=green]Buffs:[/color] ")
		for attr in player_character.buffs:
			debug_log.append_text("%s +%d (%d turns) " % [Skill.AttributeTarget.keys()[attr], player_character.buffs[attr].value, player_character.buffs[attr].duration])
		debug_log.append_text("\n")
	
	if player_character.debuffs.size() > 0:
		debug_log.append_text("[color=red]Debuffs:[/color] ")
		for attr in player_character.debuffs:
			debug_log.append_text("%s -%d (%d turns) " % [Skill.AttributeTarget.keys()[attr], player_character.debuffs[attr].value, player_character.debuffs[attr].duration])
		debug_log.append_text("\n")
	
	debug_log.append_text("\n[b][color=orange]ENEMY STATS[/color][/b]\n")
	debug_log.append_text("ATK Power: %.1f | Spell Power: %.1f\n" % [enemy_character.attack_power, enemy_character.spell_power])
	debug_log.append_text("Toughness: %.1f | Spell Ward: %.1f\n" % [enemy_character.toughness, enemy_character.spell_ward])
	debug_log.append_text("Accuracy: %.2f%% | Dodge: %.2f%% | Crit: %.2f%%\n" % [enemy_character.accuracy * 100, enemy_character.dodge * 100, enemy_character.critical_hit_rate * 100])
	debug_log.append_text("SP: %d/%d | MP: %d/%d\n" % [enemy_character.current_sp, enemy_character.max_sp, enemy_character.current_mp, enemy_character.max_mp])
	
	if enemy_character.buffs.size() > 0:
		debug_log.append_text("[color=green]Buffs:[/color] ")
		for attr in enemy_character.buffs:
			debug_log.append_text("%s +%d (%d turns) " % [Skill.AttributeTarget.keys()[attr], enemy_character.buffs[attr].value, enemy_character.buffs[attr].duration])
		debug_log.append_text("\n")
	
	if enemy_character.debuffs.size() > 0:
		debug_log.append_text("[color=red]Debuffs:[/color] ")
		for attr in enemy_character.debuffs:
			debug_log.append_text("%s -%d (%d turns) " % [Skill.AttributeTarget.keys()[attr], enemy_character.debuffs[attr].value, enemy_character.debuffs[attr].duration])
		debug_log.append_text("\n")
