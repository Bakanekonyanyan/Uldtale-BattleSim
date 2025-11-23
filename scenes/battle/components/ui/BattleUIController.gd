# Complete Fixed BattleUIController.gd
# res://scenes/battle/components/ui/BattleUIController.gd

class_name BattleUIController
extends Node

signal action_selected(action: BattleAction)

var player: CharacterData
var enemies: Array[CharacterData] = []

# UI Components
@onready var player_info: RichTextLabel = $PlayerInfo
@onready var turn_label: Label = $TurnLabel
@onready var action_buttons: VBoxContainer = $ActionButtons
@onready var wave_label: Label = $WaveLabel
@onready var floor_label: Label = $FloorLabel
@onready var dungeon_description_label: RichTextLabel = $DungeonDescriptionLabel
@onready var xp_label: Label = $XPLabel
@onready var combat_log: RichTextLabel = $CombatLog
@onready var combat_log_label: Label = $CombatLogLabel
@onready var combat_log_window: Panel = $CombatLogWindow
@onready var debug_window: Panel = $DebugWindow
@onready var debug_log: RichTextLabel = $DebugWindow/DebugLog
@onready var debug_toggle: Button = $DebugToggleButton
@onready var inventory_menu = $InventoryMenu
@onready var enemy_scroll_container: ScrollContainer = $EnemyScrollContainer
@onready var enemy_info_container: VBoxContainer = $EnemyScrollContainer/EnemyInfoContainer
@onready var target_selector: TargetSelector = $TargetSelector
@onready var skill_menu_panel: Panel = $SkillMenuPanel
@onready var skill_menu_vbox: VBoxContainer = $SkillMenuPanel/SkillMenuVBox
@onready var skill_buttons_container: VBoxContainer = $SkillMenuPanel/SkillMenuVBox/SkillButtonsContainer
@onready var no_skills_label: Label = $SkillMenuPanel/SkillMenuVBox/NoSkillsLabel
@onready var skill_menu_cancel_button: Button = $SkillMenuPanel/SkillMenuVBox/SkillMenuCancelButton
@onready var skill_info_dialog: AcceptDialog = $SkillInfoDialog
@onready var skill_info_rich_label: RichTextLabel = $SkillInfoDialog/SkillInfoRichLabel
@onready var enemy_info_dialog: AcceptDialog = $EnemyInfoDialog
@onready var enemy_info_rich_label: RichTextLabel = $EnemyInfoDialog/EnemyInfoRichLabel

var enemy_panels: Array[Panel] = []
var ui_locked: bool = false

func _ready():
	if debug_window:
		debug_window.hide()
	if debug_toggle:
		debug_toggle.pressed.connect(_toggle_debug)
	if skill_menu_cancel_button:
		skill_menu_cancel_button.pressed.connect(_on_skill_menu_cancelled)
	if inventory_menu:
		inventory_menu.item_selected.connect(_on_inventory_item_selected)
	if skill_menu_panel:
		skill_menu_panel.hide()
	
# === INITIALIZATION ===

func initialize_multi(p_player: CharacterData, p_enemies: Array[CharacterData]):
	player = p_player
	enemies = p_enemies
	_create_enemy_panels()
	update_all_character_info()

func initialize(p_player: CharacterData, single_enemy: CharacterData):
	initialize_multi(p_player, [single_enemy])

func _create_enemy_panels():
	for panel in enemy_panels:
		panel.queue_free()
	enemy_panels.clear()
	
	if not enemy_info_container:
		return
	
	for i in range(enemies.size()):
		var vbox = VBoxContainer.new()
		
		var panel = Panel.new()
		panel.custom_minimum_size = Vector2(300, 120)
		
		var rich_label = RichTextLabel.new()
		rich_label.bbcode_enabled = true
		rich_label.fit_content = true
		rich_label.scroll_active = true
		rich_label.custom_minimum_size = Vector2(280, 80)
		rich_label.position = Vector2(10, 10)
		
		panel.add_child(rich_label)
		vbox.add_child(panel)
		
		# Inspect button
		var inspect_btn = Button.new()
		inspect_btn.text = "Inspect %s" % enemies[i].name
		inspect_btn.custom_minimum_size = Vector2(280, 30)
		var enemy_index = i
		inspect_btn.pressed.connect(func(): _show_enemy_info(enemy_index))
		vbox.add_child(inspect_btn)
		
		enemy_info_container.add_child(vbox)
		enemy_panels.append(panel)

# === DISPLAY UPDATES ===

func update_all_character_info():
	update_player_info()
	update_enemies_info()

func update_player_info():
	if not player or not player_info:
		return
	
	var status_text = player.get_status_effects_string()
	player_info.text = "[b]%s[/b]\nHP: %d/%d\nMP: %d/%d\nSP: %d/%d\nStatus: %s" % [
		player.name,
		player.current_hp, player.max_hp,
		player.current_mp, player.max_mp,
		player.current_sp, player.max_sp,
		status_text
	]

func update_enemies_info():
	for i in range(min(enemies.size(), enemy_panels.size())):
		var enemy = enemies[i]
		var panel = enemy_panels[i]
		var rich_label = panel.get_child(0) if panel.get_child_count() > 0 else null
		
		if not rich_label or not (rich_label is RichTextLabel):
			continue
		
		var status_text = enemy.get_status_effects_string()
		var hp_percent = float(enemy.current_hp) / float(enemy.max_hp) * 100.0
		
		var color = _get_hp_color(hp_percent)
		var alive_status = "[color=lime]ALIVE[/color]" if enemy.is_alive() else "[color=red]DEFEATED[/color]"
		
		rich_label.clear()
		rich_label.append_text("[b][color=%s]%s[/color][/b] %s\nHP: %d/%d (%.0f%%)\nMP: %d/%d | SP: %d/%d\nStatus: %s" % [
			color, enemy.name, alive_status,
			enemy.current_hp, enemy.max_hp, hp_percent,
			enemy.current_mp, enemy.max_mp,
			enemy.current_sp, enemy.max_sp,
			status_text
		])

func _get_hp_color(hp_percent: float) -> String:
	if hp_percent < 25: return "red"
	if hp_percent < 50: return "orange"
	if hp_percent < 75: return "yellow"
	return "white"

func update_character_info(p_player: CharacterData, single_enemy: CharacterData):
	player = p_player
	update_all_character_info()

func update_turn_display(text: String):
	if turn_label:
		turn_label.text = text

func update_xp_display():
	if xp_label and player:
		var xp_required = LevelSystem.calculate_xp_for_level(player.level)
		xp_label.text = "XP: %d/%d (Level %d)" % [player.xp, xp_required, player.level]

func update_debug_display():
	if not debug_log:
		return
	
	debug_log.clear()
	debug_log.append_text("[b]Player Stats:[/b]\n")
	debug_log.append_text("ATK: %d | DEF: %d\n" % [player.get_attack_power(), player.get_defense()])
	debug_log.append_text("Accuracy: %.2f | Dodge: %.2f\n" % [player.accuracy, player.dodge])
	debug_log.append_text("Crit Rate: %.2f\n\n" % player.critical_hit_rate)
	
	for i in range(enemies.size()):
		var enemy = enemies[i]
		debug_log.append_text("[b]%s Stats:[/b]\n" % enemy.name)
		debug_log.append_text("ATK: %d | DEF: %d\n" % [enemy.get_attack_power(), enemy.get_defense()])
		debug_log.append_text("Accuracy: %.2f | Dodge: %.2f\n" % [enemy.accuracy, enemy.dodge])
		debug_log.append_text("Crit Rate: %.2f\n\n" % enemy.critical_hit_rate)

func update_dungeon_info(wave: int, floor: int, description: String):
	if wave_label:
		wave_label.text = "Wave: %d" % wave
	if floor_label:
		floor_label.text = "Floor: %d" % floor
	if dungeon_description_label:
		dungeon_description_label.text = description

func hide_dungeon_info():
	if wave_label: wave_label.hide()
	if floor_label: floor_label.hide()
	if dungeon_description_label: dungeon_description_label.hide()

# === COMBAT LOG ===

func add_combat_log(message: String, color: String = "white"):
	if combat_log:
		combat_log.append_text("[color=%s]%s[/color]\n" % [color, message])

func display_result(result: ActionResult, action: BattleAction):
	if not result:
		return
	add_combat_log(result.get_description(), result.get_log_color())
	update_all_character_info()

# === ACTION BUTTONS ===

func setup_player_actions(item_used: bool, main_action_taken: bool):
	if not action_buttons:
		return
	
	for child in action_buttons.get_children():
		child.queue_free()
	
	if not main_action_taken:
		_add_attack_button()
		_add_defend_button()
		if player.skills.size() > 0:
			_add_skills_button()
	
	_add_items_button(item_used)

func _add_attack_button():
	var btn = _create_action_button("Attack")
	btn.pressed.connect(_on_attack_pressed)
	action_buttons.add_child(btn)

func _add_defend_button():
	var btn = _create_action_button("Defend")
	btn.pressed.connect(_on_defend_pressed)
	action_buttons.add_child(btn)

func _add_skills_button():
	var btn = _create_action_button("Skills")
	btn.pressed.connect(_on_skills_pressed)
	action_buttons.add_child(btn)

func _add_items_button(item_used: bool):
	var btn = _create_action_button("Items" + (" (Used)" if item_used else ""))
	btn.disabled = item_used
	btn.pressed.connect(_on_items_pressed)
	action_buttons.add_child(btn)

func _create_action_button(text: String) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(200, 40)
	return btn

# === ACTION HANDLERS ===

func _on_attack_pressed():
	var living_enemies = _get_living_enemies()
	if living_enemies.is_empty():
		add_combat_log("No valid targets!", "red")
		return
	
	lock_ui()
	show_target_selection(living_enemies,
		func(target): emit_signal("action_selected", BattleAction.attack(player, target)),
		func(): unlock_ui(); enable_actions()
	)

func _on_defend_pressed():
	lock_ui()
	emit_signal("action_selected", BattleAction.defend(player))

func _on_skills_pressed():
	_show_skill_menu()

func _on_items_pressed():
	if inventory_menu:
		lock_ui()
		inventory_menu.show_inventory(player, enemies)

# === SKILL MENU ===

func _show_skill_menu():
	if not skill_menu_panel or not skill_buttons_container:
		push_error("BattleUIController: Skill menu components not found")
		return
	
	for child in skill_buttons_container.get_children():
		child.queue_free()
	
	var has_any_skills = false
	for skill_name in player.skills:
		# CRITICAL: Get player's skill instance, not template
		var skill = player.get_skill_instance(skill_name)
		if not skill:
			continue
		
		has_any_skills = true
		
		var cooldown = player.get_skill_cooldown(skill_name)
		var can_use = _can_use_skill(skill, cooldown)
		
		var skill_container = _create_skill_button(skill, cooldown, can_use)
		skill_buttons_container.add_child(skill_container)
	
	if no_skills_label:
		no_skills_label.visible = not has_any_skills
	
	skill_menu_panel.show()
	lock_ui()

func _can_use_skill(skill: Skill, cooldown: int) -> bool:
	if cooldown > 0:
		return false
	
	if skill.ability_type != Skill.AbilityType.PHYSICAL and player.current_mp < skill.mp_cost:
		return false
	
	if skill.ability_type == Skill.AbilityType.PHYSICAL and player.current_sp < skill.sp_cost:
		return false
	
	return true

func _create_skill_button(skill: Skill, cooldown: int, can_use: bool) -> HBoxContainer:
	"""Create skill button with info button - returns HBoxContainer"""
	var hbox = HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(300, 40)
	
	# Main skill button
	var btn = Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Get skill level display
	var level_str = skill.get_level_string() if skill.has_method("get_level_string") else "I"
	
	if cooldown > 0:
		btn.text = "%s [Lv %s] (CD: %d)" % [skill.name, level_str, cooldown]
	else:
		var cost_parts = []
		if skill.mp_cost > 0:
			cost_parts.append("MP: %d" % skill.mp_cost)
		if skill.sp_cost > 0:
			cost_parts.append("SP: %d" % skill.sp_cost)
		
		var cost_str = " | ".join(cost_parts) if not cost_parts.is_empty() else "Free"
		btn.text = "%s [Lv %s] (%s)" % [skill.name, level_str, cost_str]
	
	btn.disabled = not can_use
	btn.pressed.connect(func(): _on_skill_selected(skill))
	
	# Info button
	var info_btn = Button.new()
	info_btn.text = "?"
	info_btn.custom_minimum_size = Vector2(30, 40)
	info_btn.tooltip_text = "View skill details"
	info_btn.pressed.connect(func(): _show_skill_info(skill))
	
	hbox.add_child(btn)
	hbox.add_child(info_btn)
	
	return hbox

func _on_skill_menu_cancelled():
	if skill_menu_panel:
		skill_menu_panel.hide()
	unlock_ui()
	enable_actions()

func _show_skill_info(skill: Skill):
	"""Display detailed skill information in popup with RichTextLabel"""
	if not skill_info_dialog or not skill_info_rich_label:
		push_error("BattleUIController: Skill info dialog not found")
		return
	
	var info_text = "[center][b][color=cyan]%s[/color][/b][/center]\n" % skill.name
	info_text += "[center][i]%s[/i][/center]\n\n" % skill.description
	
	# Level & Power
	var level_str = skill.get_level_string() if skill.has_method("get_level_string") else "I"
	info_text += "[b][color=cyan]Level:[/color][/b] %s" % level_str
	
	if skill.level < 6 and skill.has_method("get_level_string"):
		var uses = skill.uses if "uses" in skill else 0
		var next_threshold = skill.LEVEL_THRESHOLDS[skill.level - 1] if "LEVEL_THRESHOLDS" in skill else 100
		info_text += " (%d/%d uses)\n" % [uses, next_threshold]
	else:
		info_text += " [color=gold](MAX)[/color]\n"
	
	# Type & Target
	info_text += "[b][color=cyan]Type:[/color][/b] %s\n" % Skill.SkillType.keys()[skill.type]
	info_text += "[b][color=cyan]Target:[/color][/b] %s\n" % Skill.TargetType.keys()[skill.target]
	
	# Costs
	if skill.mp_cost > 0 or skill.sp_cost > 0:
		info_text += "\n[b][color=yellow]Costs:[/color][/b]\n"
		if skill.mp_cost > 0:
			info_text += "  • MP: %d\n" % skill.mp_cost
		if skill.sp_cost > 0:
			info_text += "  • SP: %d\n" % skill.sp_cost
	
	# Power & Effects
	if skill.power > 0:
		info_text += "\n[b][color=cyan]Power:[/color][/b] %d\n" % skill.power
	
	if skill.duration > 0:
		info_text += "[b][color=cyan]Duration:[/color][/b] %d turns\n" % skill.duration
	
	if skill.cooldown > 0:
		info_text += "[b][color=cyan]Cooldown:[/color][/b] %d turns\n" % skill.cooldown
	
	# Attributes affected - Check both singular and plural
	var has_attribute_effect = false
	if "attribute_target" in skill:
		var attr_target = skill.attribute_target
		# Check if it's an array
		if attr_target is Array:
			if not attr_target.is_empty():
				var attr_names = []
				for attr in attr_target:
					attr_names.append(str(attr))
				info_text += "\n[b][color=cyan]Affects:[/color][/b] %s\n" % ", ".join(attr_names)
				has_attribute_effect = true
		# Check if it's an enum value (int) and not NONE (0)
		elif typeof(attr_target) == TYPE_INT and attr_target != 0:
			info_text += "\n[b][color=cyan]Affects:[/color][/b] %s\n" % Skill.AttributeTarget.keys()[attr_target]
			has_attribute_effect = true
		# Check if it's a string and not "NONE"
		elif typeof(attr_target) == TYPE_STRING and attr_target != "NONE":
			info_text += "\n[b][color=cyan]Affects:[/color][/b] %s\n" % attr_target
			has_attribute_effect = true
	
	if "attribute_targets" in skill:
		var attr_targets = skill.attribute_targets
		if attr_targets is Array and not attr_targets.is_empty():
			var attr_names = []
			for attr in attr_targets:
				attr_names.append(str(attr))
			info_text += "\n[b][color=cyan]Affects:[/color][/b] %s\n" % ", ".join(attr_names)
			has_attribute_effect = true
		elif typeof(attr_targets) == TYPE_STRING and attr_targets != "NONE":
			info_text += "\n[b][color=cyan]Affects:[/color][/b] %s\n" % attr_targets
			has_attribute_effect = true
	
	# Status effects - Check both singular and plural
	var status_list = []
	if "status_effect" in skill:
		var status = skill.status_effect
		if status is Array:
			for s in status:
				if s != "NONE" and typeof(s) == TYPE_STRING:
					status_list.append(s)
				elif typeof(s) == TYPE_INT and s != 0:
					status_list.append(Skill.StatusEffect.keys()[s])
		elif typeof(status) == TYPE_INT and status != 0:
			status_list.append(Skill.StatusEffect.keys()[status])
		elif typeof(status) == TYPE_STRING and status != "NONE":
			status_list.append(status)
	
	
	skill_info_rich_label.clear()
	skill_info_rich_label.append_text(info_text)
	skill_info_dialog.popup_centered()

func _on_skill_selected(skill: Skill):
	if skill_menu_panel:
		skill_menu_panel.hide()
	
	lock_ui()
	
	var needs_target = (skill.target == Skill.TargetType.ENEMY)
	
	if needs_target:
		var living_enemies = _get_living_enemies()
		if living_enemies.is_empty():
			add_combat_log("No valid targets for skill!", "red")
			unlock_ui()
			enable_actions()
			return
		
		show_target_selection(living_enemies,
			func(target): emit_signal("action_selected", BattleAction.skill(player, skill, [target])),
			func(): unlock_ui(); enable_actions()
		)
	else:
		var targets = _get_skill_targets(skill)
		emit_signal("action_selected", BattleAction.skill(player, skill, targets))

func _get_skill_targets(skill: Skill) -> Array[CharacterData]:
	var targets: Array[CharacterData] = []
	
	match skill.target:
		Skill.TargetType.SELF, Skill.TargetType.ALLY, Skill.TargetType.ALL_ALLIES:
			targets.append(player)
		Skill.TargetType.ENEMY:
			var living = _get_living_enemies()
			if not living.is_empty():
				targets.append(living[0])
		Skill.TargetType.ALL_ENEMIES:
			targets = _get_living_enemies()
	
	return targets

# === INVENTORY ===

func _on_inventory_item_selected(item: Item, target: CharacterData):
	var targets: Array[CharacterData] = []
	
	if not target:
		match item.target_type:
			Item.TargetType.ALL_ENEMIES:
				targets = _get_living_enemies()
			Item.TargetType.ALL_ALLIES:
				targets.append(player)
			_:
				targets.append(player)
	else:
		targets.append(target)
	
	emit_signal("action_selected", BattleAction.item(player, item, targets))

# === TARGET SELECTION ===

func show_target_selection(targets: Array[CharacterData], on_selected: Callable, on_cancelled: Callable):
	if not target_selector:
		push_error("BattleUIController: No target selector")
		on_cancelled.call()
		return
	
	for connection in target_selector.target_selected.get_connections():
		target_selector.target_selected.disconnect(connection.callable)
	
	for connection in target_selector.target_cancelled.get_connections():
		target_selector.target_cancelled.disconnect(connection.callable)
	
	target_selector.target_selected.connect(func(target):
		on_selected.call(target)
		target_selector.hide()
	, CONNECT_ONE_SHOT)
	
	target_selector.target_cancelled.connect(func():
		on_cancelled.call()
		target_selector.hide()
	, CONNECT_ONE_SHOT)
	
	target_selector.show_target_selection(targets, "Select Target", false)

# === UI STATE ===

func enable_actions():
	if action_buttons:
		for btn in action_buttons.get_children():
			if btn is Button:
				btn.disabled = false

func disable_actions():
	if action_buttons:
		for btn in action_buttons.get_children():
			if btn is Button:
				btn.disabled = true

func lock_ui():
	ui_locked = true
	disable_actions()

func unlock_ui():
	ui_locked = false

func _force_ui_invisible():
	if action_buttons: action_buttons.hide()
	if player_info: player_info.hide()
	if enemy_scroll_container: enemy_scroll_container.hide()
	if combat_log: combat_log.hide()
	if combat_log_label: combat_log_label.hide()
	if combat_log_window: combat_log_window.hide()
	if turn_label: turn_label.hide()
	if xp_label: xp_label.hide()
	if wave_label: wave_label.hide()
	if floor_label: floor_label.hide()
	if dungeon_description_label: dungeon_description_label.hide()

# === HELPERS ===

func _get_living_enemies() -> Array[CharacterData]:
	var living: Array[CharacterData] = []
	for e in enemies:
		if e.is_alive():
			living.append(e)
	return living

func _toggle_debug():
	if debug_window:
		debug_window.visible = !debug_window.visible

func _show_enemy_info(enemy_index: int):
	"""Display detailed enemy information including equipment with RichTextLabel"""
	if enemy_index < 0 or enemy_index >= enemies.size():
		return
	
	if not enemy_info_dialog or not enemy_info_rich_label:
		push_error("BattleUIController: Enemy info dialog not found")
		return
	
	var enemy = enemies[enemy_index]
	
	var info_text = "[center][b][color=cyan]%s[/color][/b][/center]\n" % enemy.name
	info_text += "[center]Level %d %s[/center]\n\n" % [enemy.level, enemy.character_class]
	
	# Status
	var status = "[color=lime]ALIVE[/color]" if enemy.is_alive() else "[color=red]DEFEATED[/color]"
	info_text += "[b]Status:[/b] %s\n\n" % status
	
	# === PRIMARY ATTRIBUTES ===
	info_text += "[b][color=cyan]PRIMARY ATTRIBUTES[/color][/b]\n"
	info_text += "Vit: %s | Str: %s | Dex: %s\n" % [
		enemy.get_attribute_display_compact("vitality"),
		enemy.get_attribute_display_compact("strength"),
		enemy.get_attribute_display_compact("dexterity")
	]
	info_text += "Int: %s | Fth: %s | Mnd: %s\n" % [
		enemy.get_attribute_display_compact("intelligence"),
		enemy.get_attribute_display_compact("faith"),
		enemy.get_attribute_display_compact("mind")
	]
	info_text += "End: %s | Arc: %s\n" % [
		enemy.get_attribute_display_compact("endurance"),
		enemy.get_attribute_display_compact("arcane")
	]
	info_text += "Agi: %s | Fort: %s\n\n" % [
		enemy.get_attribute_display_compact("agility"),
		enemy.get_attribute_display_compact("fortitude")
	]
	
	# === COMBAT STATS ===
	info_text += "[b][color=cyan]COMBAT STATS[/color][/b]\n"
	info_text += "HP: %d/%d | MP: %d/%d | SP: %d/%d\n" % [
		enemy.current_hp, enemy.max_hp,
		enemy.current_mp, enemy.max_mp,
		enemy.current_sp, enemy.max_sp
	]
	info_text += "ATK: %d | Spell Power: %d\n" % [
		enemy.get_attack_power(), enemy.spell_power
	]
	info_text += "DEF: %d | Toughness: %.1f\n" % [
		enemy.get_defense(), enemy.toughness
	]
	info_text += "Dodge: %.1f%% | Accuracy: %.1f%%\n" % [
		enemy.dodge * 100, enemy.accuracy * 100
	]
	info_text += "Crit: %.1f%% | Spell Ward: %.1f\n\n" % [
		enemy.critical_hit_rate * 100, enemy.spell_ward
	]
	
	# === EQUIPMENT ===
	info_text += "[b][color=cyan]EQUIPMENT[/color][/b]\n"
	var has_equipment = false
	
	for slot in ["main_hand", "off_hand", "head", "chest", "hands", "legs", "feet"]:
		var item = enemy.equipment.get(slot)
		if item and item is Equipment:
			has_equipment = true
			var color = item.get_rarity_color() if item.has_method("get_rarity_color") else "white"
			info_text += "[color=%s]%s:[/color] %s" % [
				color,
				slot.capitalize().replace("_", " "),
				item.display_name
			]
			
			# Show key stats
			if item.damage > 0:
				info_text += " [%d dmg]" % item.damage
			if item.armor_value > 0:
				info_text += " [%d armor]" % item.armor_value
			
			info_text += "\n"
	
	if not has_equipment:
		info_text += "[color=gray]No equipment[/color]\n"
	
	info_text += "\n"
	
	# === SKILLS ===
	if enemy.skills.size() > 0:
		info_text += "[b][color=cyan]SKILLS[/color][/b]\n"
		for skill_name in enemy.skills:
			var skill = enemy.get_skill_instance(skill_name)
			if skill:
				var level_str = skill.get_level_string() if skill.has_method("get_level_string") else "I"
				info_text += "• %s [Lv %s]\n" % [skill.name, level_str]
	else:
		info_text += "[b][color=cyan]SKILLS[/color][/b]\n[color=gray]No special skills[/color]\n"
	
	# Use the direct reference instead of get_node_or_null
	enemy_info_rich_label.clear()
	enemy_info_rich_label.append_text(info_text)
	enemy_info_dialog.popup_centered()
