# res://scenes/battle/components/ui/BattleUIController.gd
#  REFACTORED: UI elements now defined in scene, less dynamic creation

class_name BattleUIController
extends Node

signal action_selected(action: BattleAction)

var player: CharacterData
var enemies: Array[CharacterData] = []

# UI Components (now from scene)
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

# Enemy display (now from scene)
@onready var enemy_scroll_container: ScrollContainer = $EnemyScrollContainer
@onready var enemy_info_container: VBoxContainer = $EnemyScrollContainer/EnemyInfoContainer

# Target selector (now from scene)
@onready var target_selector: TargetSelector = $TargetSelector

# Skill menu (now from scene)
@onready var skill_menu_panel: Panel = $SkillMenuPanel
@onready var skill_menu_vbox: VBoxContainer = $SkillMenuPanel/SkillMenuVBox
@onready var skill_buttons_container: VBoxContainer = $SkillMenuPanel/SkillMenuVBox/SkillButtonsContainer
@onready var no_skills_label: Label = $SkillMenuPanel/SkillMenuVBox/NoSkillsLabel
@onready var skill_menu_cancel_button: Button = $SkillMenuPanel/SkillMenuVBox/SkillMenuCancelButton

var enemy_panels: Array[Panel] = []
var ui_locked: bool = false

func _ready():
	if debug_window:
		debug_window.hide()
	
	if debug_toggle:
		debug_toggle.pressed.connect(_toggle_debug)
	
	# Setup skill menu cancel button
	if skill_menu_cancel_button:
		skill_menu_cancel_button.pressed.connect(_on_skill_menu_cancelled)
	
	# Setup inventory signals
	if inventory_menu:
		inventory_menu.item_selected.connect(_on_inventory_item_selected)
	
	# Hide skill menu initially
	if skill_menu_panel:
		skill_menu_panel.hide()

# === INITIALIZATION ===

func initialize_multi(p_player: CharacterData, p_enemies: Array[CharacterData]):
	"""Initialize UI for multi-enemy battle"""
	player = p_player
	enemies = p_enemies
	
	print("BattleUIController: Initialized with player and %d enemies" % enemies.size())
	
	_create_enemy_panels()
	update_all_character_info()

func initialize(p_player: CharacterData, single_enemy: CharacterData):
	"""Legacy single-enemy initialization"""
	initialize_multi(p_player, [single_enemy])

func _create_enemy_panels():
	""" Create panels with RichTextLabel for BBCode rendering"""
	# Clear existing panels
	for panel in enemy_panels:
		panel.queue_free()
	enemy_panels.clear()
	
	if not enemy_info_container:
		return
	
	# Create panel for each enemy
	for i in range(enemies.size()):
		var enemy = enemies[i]
		
		var panel = Panel.new()
		panel.custom_minimum_size = Vector2(300, 120)
		
		# Use RichTextLabel for BBCode support
		var rich_label = RichTextLabel.new()
		rich_label.bbcode_enabled = true
		rich_label.fit_content = true
		rich_label.scroll_active = true
		rich_label.custom_minimum_size = Vector2(280, 100)
		rich_label.position = Vector2(10, 10)
		
		panel.add_child(rich_label)
		enemy_info_container.add_child(panel)
		enemy_panels.append(panel)
	
	print("BattleUIController: Created %d enemy panels with BBCode support" % enemy_panels.size())

# === CHARACTER INFO UPDATES ===

func update_all_character_info():
	"""Update display for player and all enemies"""
	update_player_info()
	update_enemies_info()

func update_player_info():
	"""Update player info display"""
	if not player or not player_info:
		return
	
	var status_text = player.get_status_effects_string()
	
	player_info.text = "[b]%s[/b]\nHP: %d/%d\nMP: %d/%d\nSP: %d/%d\nStatus: %s" % [
		player.name,
		player.current_hp,
		player.max_hp,
		player.current_mp,
		player.max_mp,
		player.current_sp,
		player.max_sp,
		status_text
	]

func update_enemies_info():
	""" Update enemy info with proper BBCode rendering"""
	for i in range(min(enemies.size(), enemy_panels.size())):
		var enemy = enemies[i]
		var panel = enemy_panels[i]
		var rich_label = panel.get_child(0) if panel.get_child_count() > 0 else null
		
		if not rich_label or not (rich_label is RichTextLabel):
			continue
		
		var status_text = enemy.get_status_effects_string()
		var hp_percent = float(enemy.current_hp) / float(enemy.max_hp) * 100.0
		
		var color = "white"
		if hp_percent < 25:
			color = "red"
		elif hp_percent < 50:
			color = "orange"
		elif hp_percent < 75:
			color = "yellow"
		
		var alive_status = "[color=lime]ALIVE[/color]" if enemy.is_alive() else "[color=red]DEFEATED[/color]"
		
		# Clear and set new text
		rich_label.clear()
		rich_label.append_text("[b][color=%s]%s[/color][/b] %s\nHP: %d/%d (%.0f%%)\nMP: %d/%d | SP: %d/%d\nStatus: %s" % [
			color,
			enemy.name,
			alive_status,
			enemy.current_hp,
			enemy.max_hp,
			hp_percent,
			enemy.current_mp,
			enemy.max_mp,
			enemy.current_sp,
			enemy.max_sp,
			status_text
		])

func update_character_info(p_player: CharacterData, single_enemy: CharacterData):
	"""Legacy function for backwards compatibility"""
	player = p_player
	update_all_character_info()

# === TARGET SELECTION ===

func show_target_selection(targets: Array[CharacterData], on_selected: Callable, on_cancelled: Callable):
	"""Show target selector and connect callbacks"""
	if not target_selector:
		push_error("BattleUIController: No target selector available")
		on_cancelled.call()
		return
	
	# Disconnect old signals safely
	for connection in target_selector.target_selected.get_connections():
		target_selector.target_selected.disconnect(connection.callable)
	
	for connection in target_selector.target_cancelled.get_connections():
		target_selector.target_cancelled.disconnect(connection.callable)
	
	# Connect new callbacks
	target_selector.target_selected.connect(func(target):
		on_selected.call(target)
		target_selector.hide()
	, CONNECT_ONE_SHOT)
	
	target_selector.target_cancelled.connect(func():
		on_cancelled.call()
		target_selector.hide()
	, CONNECT_ONE_SHOT)
	
	#  Show selector without auto-confirm
	target_selector.show_target_selection(targets, "Select Target", false)

# === COMBAT LOG ===

func add_combat_log(message: String, color: String = "white"):
	"""Add message to combat log"""
	if not combat_log:
		return
	
	combat_log.append_text("[color=%s]%s[/color]\n" % [color, message])

# === ACTION BUTTONS ===

func setup_player_actions(item_used: bool, main_action_taken: bool):
	"""Setup action buttons for player turn"""
	if not action_buttons:
		return
	
	# Clear existing buttons
	for child in action_buttons.get_children():
		child.queue_free()
	
	# Attack button
	if not main_action_taken:
		var attack_btn = Button.new()
		attack_btn.text = "Attack"
		attack_btn.custom_minimum_size = Vector2(200, 40)
		attack_btn.pressed.connect(_on_attack_pressed)
		action_buttons.add_child(attack_btn)
	
	# Defend button
	if not main_action_taken:
		var defend_btn = Button.new()
		defend_btn.text = "Defend"
		defend_btn.custom_minimum_size = Vector2(200, 40)
		defend_btn.pressed.connect(_on_defend_pressed)
		action_buttons.add_child(defend_btn)
	
	# Skills button
	if not main_action_taken and player.skills.size() > 0:
		var skills_btn = Button.new()
		skills_btn.text = "Skills"
		skills_btn.custom_minimum_size = Vector2(200, 40)
		skills_btn.pressed.connect(_on_skills_pressed)
		action_buttons.add_child(skills_btn)
	
	#  Items button - always show but disable if used
	var items_btn = Button.new()
	items_btn.text = "Items" + (" (Used)" if item_used else "")
	items_btn.custom_minimum_size = Vector2(200, 40)
	items_btn.disabled = item_used
	items_btn.pressed.connect(_on_items_pressed)
	action_buttons.add_child(items_btn)

func _on_attack_pressed():
	"""Attack triggers target selection"""
	print("BattleUIController: Attack pressed - showing target selector")
	
	var living_enemies = _get_living_enemies()
	
	if living_enemies.is_empty():
		add_combat_log("No valid targets!", "red")
		return
	
	lock_ui()
	
	show_target_selection(living_enemies, func(target):
		print("BattleUIController: Target selected for attack: %s" % target.name)
		emit_signal("action_selected", BattleAction.attack(player, target))
	, func():
		print("BattleUIController: Attack cancelled")
		unlock_ui()
		enable_actions()
	)

func _on_defend_pressed():
	"""Defend auto-completes without target"""
	print("BattleUIController: Defend pressed - auto-completing")
	lock_ui()
	emit_signal("action_selected", BattleAction.defend(player))

func _on_skills_pressed():
	"""Show skill menu"""
	_show_skill_menu()

func _on_items_pressed():
	"""Show inventory for item selection"""
	if inventory_menu:
		lock_ui()
		inventory_menu.show_inventory(player, enemies)  #  Pass enemies list

func _show_skill_menu():
	""" REFACTORED: Use pre-built skill menu from scene"""
	if not skill_menu_panel or not skill_buttons_container:
		push_error("BattleUIController: Skill menu components not found")
		return
	
	# Clear existing skill buttons
	for child in skill_buttons_container.get_children():
		child.queue_free()
	
	# Add skill buttons
	var has_any_skills = false
	for skill_name in player.skills:
		var skill = SkillManager.get_skill(skill_name)
		if not skill:
			continue
		
		has_any_skills = true
		
		var cooldown = player.get_skill_cooldown(skill_name)
		var on_cooldown = cooldown > 0
		
		# Check if player has resources
		var can_use = true
		if skill.ability_type != Skill.AbilityType.PHYSICAL and player.current_mp < skill.mp_cost:
			can_use = false
		if skill.ability_type == Skill.AbilityType.PHYSICAL and player.current_sp < skill.sp_cost:
			can_use = false
		
		var btn = Button.new()
		
		# Show cooldown or resource costs
		if on_cooldown:
			btn.text = "%s (Cooldown: %d turns)" % [skill.name, cooldown]
		else:
			btn.text = "%s (MP: %d | SP: %d)" % [skill.name, skill.mp_cost, skill.sp_cost]
		
		btn.custom_minimum_size = Vector2(260, 35)
		btn.disabled = on_cooldown or not can_use
		
		# Capture skill in closure
		var current_skill = skill
		btn.pressed.connect(func():
			_on_skill_selected(current_skill)
		)
		
		skill_buttons_container.add_child(btn)
	
	# Show/hide "no skills" label
	if no_skills_label:
		no_skills_label.visible = not has_any_skills
	
	# Show the menu
	skill_menu_panel.show()
	lock_ui()

func _on_skill_menu_cancelled():
	"""Handle skill menu cancellation"""
	if skill_menu_panel:
		skill_menu_panel.hide()
	unlock_ui()
	enable_actions()

func _on_skill_selected(skill: Skill):
	"""Handle skill selection and target selection if needed"""
	print("BattleUIController: Skill selected: %s" % skill.name)
	
	# Hide skill menu
	if skill_menu_panel:
		skill_menu_panel.hide()
	
	lock_ui()
	
	# Determine if skill needs target selection
	var needs_target_selection = false
	
	match skill.target:
		Skill.TargetType.ENEMY:
			needs_target_selection = true
		Skill.TargetType.ALL_ENEMIES:
			needs_target_selection = false
		Skill.TargetType.SELF, Skill.TargetType.ALLY, Skill.TargetType.ALL_ALLIES:
			needs_target_selection = false
	
	if needs_target_selection:
		var living_enemies = _get_living_enemies()
		
		if living_enemies.is_empty():
			add_combat_log("No valid targets for skill!", "red")
			unlock_ui()
			enable_actions()
			return
		
		show_target_selection(living_enemies, func(target):
			print("BattleUIController: Target selected for skill: %s" % target.name)
			emit_signal("action_selected", BattleAction.skill(player, skill, [target]))
		, func():
			print("BattleUIController: Skill cancelled")
			unlock_ui()
			enable_actions()
		)
	else:
		var targets = _get_skill_targets(skill)
		emit_signal("action_selected", BattleAction.skill(player, skill, targets))

func _get_skill_targets(skill: Skill) -> Array[CharacterData]:
	"""Get appropriate targets for a skill"""
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

func _get_living_enemies() -> Array[CharacterData]:
	"""Get all living enemies"""
	var living: Array[CharacterData] = []
	for e in enemies:
		if e.is_alive():
			living.append(e)
	return living

# === INVENTORY ===

func _on_inventory_item_selected(item: Item, target: CharacterData):
	"""Handle item selection from inventory"""
	print("BattleUIController: Item selected: %s for %s" % [
		item.display_name, 
		target.name if target else "ALL"
	])
	
	var targets: Array[CharacterData] = []
	
	# Handle AOE items (target is null)
	if not target:
		match item.target_type:
			Item.TargetType.ALL_ENEMIES:
				targets = _get_living_enemies()
				print("BattleUIController: Item targeting all %d living enemies" % targets.size())
			Item.TargetType.ALL_ALLIES:
				targets.append(player)
				print("BattleUIController: Item targeting all allies (player)")
			_:
				push_error("BattleUIController: Unexpected null target for item type %s" % Item.TargetType.keys()[item.target_type])
				targets.append(player)
	else:
		targets.append(target)
		print("BattleUIController: Item targeting single target: %s" % target.name)
	
	emit_signal("action_selected", BattleAction.item(player, item, targets))

# === DISPLAY RESULT ===

func display_result(result: ActionResult, action: BattleAction):
	"""Display action result in combat log"""
	if not result:
		return
	
	var color = result.get_log_color()
	add_combat_log(result.get_description(), color)
	
	update_all_character_info()

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
	""" FIXED: Force hide all UI elements including combat log"""
	if action_buttons:
		action_buttons.hide()
	if player_info:
		player_info.hide()
	if enemy_scroll_container:
		enemy_scroll_container.hide()
	if combat_log:
		combat_log.hide()
	if combat_log_label:
		combat_log_label.hide()
	if combat_log_window:
		combat_log_window.hide()
	if turn_label:
		turn_label.hide()
	if xp_label:
		xp_label.hide()
	if wave_label:
		wave_label.hide()
	if floor_label:
		floor_label.hide()
	if dungeon_description_label:
		dungeon_description_label.hide()
	
	print("BattleUIController: All UI elements hidden")

# === DUNGEON INFO ===

func update_dungeon_info(wave: int, floor: int, description: String):
	if wave_label:
		wave_label.text = "Wave: %d" % wave
	if floor_label:
		floor_label.text = "Floor: %d" % floor
	if dungeon_description_label:
		dungeon_description_label.text = description

func hide_dungeon_info():
	if wave_label:
		wave_label.hide()
	if floor_label:
		floor_label.hide()
	if dungeon_description_label:
		dungeon_description_label.hide()

# === MISC ===

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

func _toggle_debug():
	if debug_window:
		debug_window.visible = !debug_window.visible
