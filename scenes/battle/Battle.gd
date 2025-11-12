# res://scenes/battle/Battle.gd
extends Node2D

signal battle_completed(player_won: bool, xp_gained: int)

var player_character: CharacterData
var enemy_character: CharacterData
var is_boss_battle: bool = false
var current_wave: int
var current_floor: int
var dungeon_description: String

var combat_manager: CombatManager
var turn_manager: TurnManager
var ui_manager: BattleUIManager

@onready var inventory_menu = $InventoryMenu

func _ready():
	_initialize_managers()

func _initialize_managers():
	combat_manager = CombatManager.new()
	turn_manager = TurnManager.new()
	ui_manager = BattleUIManager.new()
	
	ui_manager.initialize({
		"player_info": $PlayerInfo,
		"enemy_info": $EnemyInfo,
		"turn_label": $TurnLabel,
		"combat_log": $CombatLog,
		"debug_log": $DebugWindow/DebugText,
		"xp_label": $XPLabel,
		"action_buttons": $ActionButtons
	})
	
	turn_manager.turn_started.connect(_on_turn_started)
	turn_manager.turn_ended.connect(_on_turn_ended)
	turn_manager.turn_skipped.connect(_on_turn_skipped)

func start_battle():
	if not validate_characters():
		return
	
	initialize_resources()
	inventory_menu.show_inventory(player_character.inventory, player_character.currency)
	inventory_menu.hide()
	
	# Initialize TurnManager with character references
	turn_manager.initialize(player_character, enemy_character)
	
	update_all_ui()
	
	# REMOVED: turn_manager.current_turn = "player" 
	# Now handled by turn_manager.determine_first_turn() in initialize()
	
	# Display who goes first
	var first_char = turn_manager.get_current_character()
	var first_name = first_char.name if first_char else "Unknown"
	ui_manager.update_turn_display("Battle starts! %s goes first." % first_name)
	
	# NEW: Always setup player action buttons, but disable them if enemy goes first
	setup_player_actions()
	ui_manager.enable_actions(turn_manager.is_player_turn())
	
	# Start first turn
	turn_manager.start_turn(first_char)

func set_player(character: CharacterData):
	player_character = character

func set_enemy(new_enemy: CharacterData):
	enemy_character = new_enemy
	enemy_character.calculate_secondary_attributes()
	
	if enemy_character.current_sp == 0:
		enemy_character.current_sp = enemy_character.max_sp

func set_dungeon_info(wave: int, floor: int, description: String):
	current_wave = wave
	current_floor = floor
	dungeon_description = description
	update_dungeon_labels()
	
	call_deferred("start_battle")

func update_dungeon_labels():
	$WaveLabel.text = "Wave: %d" % current_wave
	$FloorLabel.text = "Floor: %d" % current_floor
	$DungeonDescriptionLabel.text = dungeon_description

func validate_characters() -> bool:
	if not player_character or not enemy_character:
		push_error("Battle: Missing characters")
		return false
	return true

func initialize_resources():
	if player_character.current_sp == 0:
		player_character.current_sp = player_character.max_sp

func _on_turn_started(character: CharacterData):
	var status_message = combat_manager.process_status_effects(character)
	if status_message:
		ui_manager.update_turn_display(status_message)
		ui_manager.add_combat_log("[color=purple]Status:[/color] " + status_message)
		update_all_ui()
		await get_tree().create_timer(1.0).timeout
	
	if not combat_manager.is_character_alive(character):
		_handle_death(character)
		return
	
	if character.is_stunned:
		var stun_msg = "%s is stunned and loses their turn!" % character.name
		turn_manager.skip_turn(character, "stunned")
		ui_manager.update_turn_display(stun_msg)
		ui_manager.add_combat_log("[color=purple]" + stun_msg + "[/color]")
		character.is_stunned = false
		await get_tree().create_timer(1.0).timeout
		turn_manager.end_turn(character)
		return
	
	turn_manager.advance_phase()
	if character == player_character:
		# NEW: Refresh player actions and enable them
		setup_player_actions()
		ui_manager.enable_actions(true)
	else:
		execute_enemy_turn()

func _handle_death(character: CharacterData):
	var death_msg = "%s has been defeated!" % character.name
	ui_manager.update_turn_display(death_msg)
	ui_manager.add_combat_log("[color=red][b]" + death_msg + "[/b][/color]")
	update_all_ui()
	await get_tree().create_timer(1.5).timeout
	check_battle_end()

func setup_player_actions():
	ui_manager.clear_action_buttons()
	
	var base_actions = ["Attack", "Defend", "Items", "View Enemy Equipment"]
	for action_name in base_actions:
		var button = Button.new()
		button.text = action_name
		button.custom_minimum_size = Vector2(180, 40)
		var method = "_on_" + action_name.to_lower().replace(" ", "_") + "_pressed"
		button.pressed.connect(Callable(self, method))
		ui_manager.action_buttons.add_child(button)
	
	setup_skill_buttons()
	# REMOVED: ui_manager.enable_actions(true) 
	# Enabling is now handled by the caller based on turn state

func setup_skill_buttons():
	for skill_name in player_character.skills:
		var skill = player_character.get_skill_instance(skill_name)
		if not skill:
			skill = SkillManager.get_skill(skill_name)
		if not skill:
			continue
		
		var button = Button.new()
		button.custom_minimum_size = Vector2(180, 40)
		var cd = player_character.get_skill_cooldown(skill_name)
		var level_text = " Lv." + skill.get_level_string()
		
		var cost_type = "MP" if skill.ability_type != Skill.AbilityType.PHYSICAL else "SP"
		var cost = skill.mp_cost if cost_type == "MP" else skill.sp_cost
		var available = player_character.current_mp if cost_type == "MP" else player_character.current_sp
		
		var is_on_cooldown = cd > 0
		var insufficient_resources = available < cost
		
		if is_on_cooldown:
			button.text = "%s%s (CD: %d) [%d %s]" % [skill.name, level_text, cd, cost, cost_type]
			button.disabled = true
		elif insufficient_resources:
			button.text = "%s%s [%d %s]" % [skill.name, level_text, cost, cost_type]
			button.disabled = true
		else:
			button.text = "%s%s [%d %s]" % [skill.name, level_text, cost, cost_type]
			button.disabled = false
		
		if not button.disabled:
			button.pressed.connect(Callable(self, "_on_skill_used").bind(skill))
		
		ui_manager.action_buttons.add_child(button)

func decide_enemy_action() -> Dictionary:
	var enemy_hp_percent = float(enemy_character.current_hp) / float(enemy_character.max_hp)
	var available_skills = []
	
	for skill_name in enemy_character.skills:
		var skill = SkillManager.get_skill(skill_name)
		if not skill or enemy_character.get_skill_cooldown(skill_name) > 0:
			continue
		
		var has_resources = false
		if skill.ability_type == Skill.AbilityType.PHYSICAL:
			has_resources = enemy_character.current_sp >= skill.sp_cost
		else:
			has_resources = enemy_character.current_mp >= skill.mp_cost
		
		if has_resources:
			available_skills.append(skill)
	
	if enemy_hp_percent < 0.3:
		for skill in available_skills:
			if skill.type == Skill.SkillType.HEAL:
				return {"type": "skill", "skill": skill}
		return {"type": "defend"}
	
	if available_skills.size() > 0 and randf() < 0.6:
		return {"type": "skill", "skill": available_skills[randi() % available_skills.size()]}
	
	return {"type": "attack"}

func _on_turn_skipped(_character: CharacterData, _reason: String):
	pass

func _on_items_pressed():
	inventory_menu.show_inventory(player_character.inventory, player_character.currency)

func _on_view_enemy_equipment_pressed():
	show_enemy_equipment_dialog()

func show_battle_complete_dialog(xp_gained: int):
	var dialog_scene = load("res://scenes/BattleCompleteDialog.tscn")
	if not dialog_scene:
		emit_signal("battle_completed", true, xp_gained)
		return
	
	var dialog = dialog_scene.instantiate()
	add_child(dialog)
	
	dialog.show_dialog(player_character, xp_gained)
	
	dialog.connect("press_on_selected", Callable(self, "_on_press_on_selected").bind(xp_gained))
	dialog.connect("take_breather_selected", Callable(self, "_on_take_breather_selected").bind(xp_gained))

func _on_turn_ended(character: CharacterData):
	character.reset_defense()
	ui_manager.enable_actions(false)

func _on_attack_pressed():
	var result = combat_manager.execute_attack(player_character, enemy_character)
	ui_manager.update_turn_display(result)
	ui_manager.add_combat_log("[color=yellow]Player:[/color] " + result)
	update_all_ui()
	
	var outcome = combat_manager.check_battle_outcome(player_character, enemy_character)
	if outcome != "ongoing":
		check_battle_end()
		return
	
	turn_manager.end_turn(player_character)

func _on_defend_pressed():
	var result = combat_manager.execute_defend(player_character)
	ui_manager.update_turn_display(result)
	ui_manager.add_combat_log("[color=yellow]Player:[/color] " + result)
	update_all_ui()
	turn_manager.end_turn(player_character)

func _on_skill_used(skill: Skill):
	var targets = combat_manager.get_skill_targets(skill, player_character, enemy_character)
	var result = combat_manager.execute_skill(player_character, skill, targets)
	
	if not result.success:
		ui_manager.update_turn_display(result.message)
		return
	
	var level_up_msg = player_character.use_skill(skill.name)
	if level_up_msg != "":
		ui_manager.add_combat_log("[color=cyan]" + level_up_msg + "[/color]")
	
	ui_manager.update_turn_display(result.message)
	ui_manager.add_combat_log("[color=orange]Player used %s:[/color] %s" % [skill.name, result.message])
	update_all_ui()
	
	var outcome = combat_manager.check_battle_outcome(player_character, enemy_character)
	if outcome != "ongoing":
		check_battle_end()
		return
	
	turn_manager.end_turn(player_character)

func _on_item_used(item: Item):
	if item.item_type != Item.ItemType.CONSUMABLE:
		ui_manager.update_turn_display("This item cannot be used in battle.")
		return
	
	var item_id = item.id
	if not player_character.inventory.items.has(item_id):
		ui_manager.update_turn_display("Item no longer available.")
		return
	
	var item_quantity = player_character.inventory.items[item_id].quantity
	if item_quantity <= 0:
		ui_manager.update_turn_display("No more of this item.")
		return
	
	print("Using item: %s (Quantity before: %d)" % [item.name, item_quantity])
	
	var targets = []
	match item.consumable_type:
		Item.ConsumableType.DAMAGE, Item.ConsumableType.DEBUFF:
			targets = [enemy_character]
		_:
			targets = [player_character]
	
	var result = item.use(player_character, targets)
	
	var removed = player_character.inventory.remove_item(item_id, 1)
	if removed:
		print("Item removed successfully. Remaining: %d" % player_character.inventory.get_quantity(item_id))
	else:
		print("ERROR: Failed to remove item from inventory!")
	
	ui_manager.update_turn_display(result)
	ui_manager.add_combat_log("[color=lime]Player used %s:[/color] %s" % [item.name, result])
	update_all_ui()
	
	var outcome = combat_manager.check_battle_outcome(player_character, enemy_character)
	if outcome != "ongoing":
		check_battle_end()
		return
	
	turn_manager.end_turn(player_character)

func execute_enemy_turn():
	ui_manager.update_turn_display("Enemy's turn")
	await get_tree().create_timer(1.0).timeout
	
	if not combat_manager.is_character_alive(enemy_character):
		check_battle_end()
		return
	
	var action = decide_enemy_action()
	var result = ""
	
	match action.type:
		"attack":
			result = combat_manager.execute_attack(enemy_character, player_character)
			ui_manager.add_combat_log("[color=red]Enemy:[/color] " + result)
		"defend":
			result = combat_manager.execute_defend(enemy_character)
			ui_manager.add_combat_log("[color=red]Enemy:[/color] " + result)
		"skill":
			var targets = combat_manager.get_skill_targets(action.skill, enemy_character, player_character)
			var skill_result = combat_manager.execute_skill(enemy_character, action.skill, targets)
			if skill_result.success:
				result = skill_result.message
				ui_manager.add_combat_log("[color=orange]Enemy used %s:[/color] %s" % [action.skill.name, result])
	
	ui_manager.update_turn_display(result)
	update_all_ui()
	await get_tree().create_timer(2.0).timeout
	
	var outcome = combat_manager.check_battle_outcome(player_character, enemy_character)
	if outcome != "ongoing":
		check_battle_end()
		return
	
	turn_manager.end_turn(enemy_character)

func update_all_ui():
	ui_manager.update_character_info(player_character, enemy_character)
	ui_manager.update_xp_display(player_character.xp, player_character.level)
	ui_manager.update_debug_display(player_character, enemy_character)

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
			text += "[b]%s:[/b] [color=%s]%s[/color]\n" % [slot_name, color, item.name]
		else:
			text += "[b]%s:[/b] Empty\n" % slot_name
	return text

func _on_take_breather_selected(xp_gained: int):
	print("Battle: Player taking a breather, showing rewards...")
	
	MomentumSystem.reset_momentum()
	
	emit_signal("battle_completed", true, xp_gained)

func show_level_up_overlay():
	print("Battle: Showing level-up overlay during momentum")
	
	var level_up_scene = load("res://scenes/LevelUpScene.tscn").instantiate()
	add_child(level_up_scene)
	
	level_up_scene.visible = true
	level_up_scene.show()
	level_up_scene.setup(player_character)
	
	await level_up_scene.level_up_complete
	
	print("Battle: Level-up complete, continuing momentum")
	level_up_scene.queue_free()

func check_battle_end():
	var outcome = combat_manager.check_battle_outcome(player_character, enemy_character)
	match outcome:
		"victory":
			ui_manager.enable_actions(false)
			var xp = enemy_character.level * 50 * current_floor
			await get_tree().create_timer(1.0).timeout
			
			if is_boss_battle:
				if current_floor > player_character.max_floor_cleared:
					player_character.update_max_floor_cleared(current_floor)
					print("Battle: NEW RECORD! Boss defeated on floor %d, max_floor_cleared updated to %d" % [
						current_floor,
						player_character.max_floor_cleared
					])
					SaveManager.save_game(player_character)
					print("Battle: Progress saved with new max_floor_cleared: %d" % player_character.max_floor_cleared)
				else:
					print("Battle: Boss defeated on floor %d (max cleared: %d)" % [
						current_floor, 
						player_character.max_floor_cleared
					])
			
			show_battle_complete_dialog(xp)
		"defeat":
			ui_manager.enable_actions(false)
			await get_tree().create_timer(1.0).timeout
			emit_signal("battle_completed", false, 0)

func _on_press_on_selected(xp_gained: int):
	print("Battle: Player pressed on! Gaining momentum...")
	
	MomentumSystem.gain_momentum()
	
	var level_before = player_character.level
	
	player_character.gain_xp(xp_gained)
	
	if player_character.level > level_before:
		print("Battle: Level up detected during momentum!")
		await show_level_up_overlay()
	
	SaveManager.save_game(player_character)
	print("Battle: Progress saved - max_floor_cleared: %d" % player_character.max_floor_cleared)
	
	emit_signal("battle_completed", true, -1)
