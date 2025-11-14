# res://scenes/battle/components/ui/BattleUIController.gd
# Handles all battle UI updates and player input
# Replaces BattleUIManager with scene-based approach

extends Node  # FIXED: Changed from RefCounted to Node
class_name BattleUIController

signal action_selected(action: BattleAction)

# UI Node references - set via @export or in _ready()
@export var player_info_label: Label
@export var enemy_info_label: Label
@export var turn_label: Label
@export var combat_log: RichTextLabel
@export var debug_log: RichTextLabel
@export var xp_label: Label
@export var action_buttons: VBoxContainer
@export var wave_label: Label
@export var floor_label: Label
@export var dungeon_description_label: Label
@export var inventory_menu: Control

var player: CharacterData
var enemy: CharacterData

func _ready():
	print("BattleUIController: Ready")
	
	# FIXED: These are direct children, use $NodeName
	if not player_info_label:
		player_info_label = $PlayerInfo
	if not enemy_info_label:
		enemy_info_label = $EnemyInfo
	if not turn_label:
		turn_label = $TurnLabel
	if not combat_log:
		combat_log = $CombatLog
	if not debug_log:
		debug_log = $DebugWindow/DebugText
	if not xp_label:
		xp_label = $XPLabel
	if not action_buttons:
		action_buttons = $ActionButtons
	if not wave_label:
		wave_label = $WaveLabel
	if not floor_label:
		floor_label = $FloorLabel
	if not dungeon_description_label:
		dungeon_description_label = $DungeonDescriptionLabel
	if not inventory_menu:
		inventory_menu = $InventoryMenu
	
	# Debug: Log which nodes were found
	print("BattleUIController: Found nodes:")
	print("  player_info_label: ", player_info_label != null)
	print("  enemy_info_label: ", enemy_info_label != null)
	print("  turn_label: ", turn_label != null)
	print("  combat_log: ", combat_log != null)
	print("  action_buttons: ", action_buttons != null)
	
func initialize(p_player: CharacterData, p_enemy: CharacterData):
	"""Initialize with battle participants"""
	player = p_player
	enemy = p_enemy
	print("BattleUIController: Initialized for %s vs %s" % [player.name, enemy.name])
	
	# Connect inventory menu if it exists
	if inventory_menu and inventory_menu.has_signal("item_selected"):
		if not inventory_menu.is_connected("item_selected", Callable(self, "_on_inventory_item_selected")):
			inventory_menu.connect("item_selected", Callable(self, "_on_inventory_item_selected"))
	
	update_character_info()
	update_xp_display()

# === DISPLAY UPDATES ===

func update_character_info():
	"""Update player and enemy info displays"""
	if player_info_label and player:
		player_info_label.text = "Player: %s\nHP: %d/%d\nMP: %d/%d\nSP: %d/%d\nStatus: %s" % [
			player.name, player.current_hp, player.max_hp,
			player.current_mp, player.max_mp,
			player.current_sp, player.max_sp,
			player.get_status_effects_string()
		]
	
	if enemy_info_label and enemy:
		enemy_info_label.text = "Enemy: %s\nHP: %d/%d\nMP: %d/%d\nSP: %d/%d\nStatus: %s" % [
			enemy.name, enemy.current_hp, enemy.max_hp,
			enemy.current_mp, enemy.max_mp,
			enemy.current_sp, enemy.max_sp,
			enemy.get_status_effects_string()
		]

func update_turn_display(text: String):
	"""Update turn status message"""
	if turn_label:
		turn_label.text = text

func update_xp_display():
	"""Update XP progress display"""
	if xp_label and player:
		xp_label.text = "XP: %d / %d" % [player.xp, LevelSystem.calculate_xp_for_level(player.level)]

func update_dungeon_info(wave: int, floor: int, description: String):
	"""Update dungeon context displays"""
	if wave_label:
		wave_label.text = "Wave: %d" % wave
	if floor_label:
		floor_label.text = "Floor: %d" % floor
	if dungeon_description_label:
		dungeon_description_label.text = description

func add_combat_log(message: String, color: String = "white"):
	"""Add colored message to combat log"""
	if combat_log:
		combat_log.append_text("[color=%s]%s[/color]\n" % [color, message])

func display_result(result: ActionResult):
	"""Display action result with appropriate color"""
	var color = result.get_log_color()
	add_combat_log(result.message, color)
	update_character_info()
	update_xp_display()

# === ACTION SETUP ===

func setup_player_actions(item_action_used: bool):
	"""Setup player action buttons"""
	clear_action_buttons()
	
	# Base actions
	_add_action_button("Attack", func(): emit_signal("action_selected", BattleAction.attack(player, enemy)))
	_add_action_button("Defend", func(): emit_signal("action_selected", BattleAction.defend(player)))
	
	# Items button
	var item_text = "Items (Used)" if item_action_used else "Items (Bonus Action)"
	_add_action_button(item_text, func(): _show_inventory())
	
	# View equipment
	_add_action_button("View Enemy Equipment", func(): _show_enemy_equipment())
	
	# Skills
	_add_skill_buttons()

func _add_skill_buttons():
	"""Add buttons for available skills"""
	for skill_name in player.skills:
		var skill = player.get_skill_instance(skill_name)
		if not skill:
			continue
		
		var cd = player.get_skill_cooldown(skill_name)
		var level_text = " Lv." + skill.get_level_string()
		
		var cost_type = "MP" if skill.ability_type != Skill.AbilityType.PHYSICAL else "SP"
		var cost = skill.mp_cost if cost_type == "MP" else skill.sp_cost
		var available = player.current_mp if cost_type == "MP" else player.current_sp
		
		var is_on_cooldown = cd > 0
		var insufficient_resources = available < cost
		
		var button_text: String
		var is_disabled = false
		
		if is_on_cooldown:
			button_text = "%s%s (CD: %d) [%d %s]" % [skill.name, level_text, cd, cost, cost_type]
			is_disabled = true
		elif insufficient_resources:
			button_text = "%s%s [%d %s]" % [skill.name, level_text, cost, cost_type]
			is_disabled = true
		else:
			button_text = "%s%s [%d %s]" % [skill.name, level_text, cost, cost_type]
		
		if not is_disabled:
			var targets = _get_skill_targets(skill)
			_add_action_button(button_text, func(): emit_signal("action_selected", BattleAction.skill(player, skill, targets)))
		else:
			_add_disabled_button(button_text)

func _add_action_button(text: String, callback: Callable):
	"""Add an enabled action button"""
	if not action_buttons:
		return
	
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(180, 40)
	button.pressed.connect(callback)
	action_buttons.add_child(button)

func _add_disabled_button(text: String):
	"""Add a disabled button (for skills on cooldown, etc)"""
	if not action_buttons:
		return
	
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(180, 40)
	button.disabled = true
	action_buttons.add_child(button)

func clear_action_buttons():
	"""Remove all action buttons"""
	if action_buttons:
		for child in action_buttons.get_children():
			child.queue_free()

func enable_actions():
	"""Enable all action buttons"""
	if action_buttons:
		for button in action_buttons.get_children():
			if button is Button:
				# Don't re-enable buttons that are disabled for other reasons (cooldown, resources)
				pass

func disable_actions():
	"""Disable all action buttons"""
	if action_buttons:
		for button in action_buttons.get_children():
			if button is Button:
				button.disabled = true

# === HELPER METHODS ===

func _get_skill_targets(skill: Skill) -> Array[CharacterData]:
	"""Get targets for a skill"""
	var result: Array[CharacterData] = []
	
	match skill.target:
		Skill.TargetType.SELF, Skill.TargetType.ALLY, Skill.TargetType.ALL_ALLIES:
			result.append(player)
		Skill.TargetType.ENEMY, Skill.TargetType.ALL_ENEMIES:
			result.append(enemy)
	
	return result

func _show_inventory():
	"""Show inventory menu"""
	if inventory_menu and inventory_menu.has_method("show_inventory"):
		inventory_menu.show_inventory(player.inventory, player.currency)

func _on_inventory_item_selected(item: Item):
	"""Handle item selection from inventory"""
	var targets = []
	match item.consumable_type:
		Item.ConsumableType.DAMAGE, Item.ConsumableType.DEBUFF:
			targets = [enemy]
		_:
			targets = [player]
	
	emit_signal("action_selected", BattleAction.item(player, item, targets))

func _show_enemy_equipment():
	"""Show enemy equipment dialog"""
	var dialog = AcceptDialog.new()
	dialog.title = "Enemy Equipment"
	dialog.ok_button_text = "Close"
	
	var rich_label = RichTextLabel.new()
	rich_label.bbcode_enabled = true
	rich_label.fit_content = true
	rich_label.custom_minimum_size = Vector2(400, 300)
	rich_label.text = _get_enemy_equipment_text()
	
	dialog.add_child(rich_label)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()
	
	await dialog.confirmed
	dialog.queue_free()

func _get_enemy_equipment_text() -> String:
	"""Generate enemy equipment description"""
	var text = "[b]%s's Equipment:[/b]\n\n" % enemy.name
	for slot in enemy.equipment:
		var item = enemy.equipment[slot]
		var slot_name = slot.capitalize().replace("_", " ")
		if item and item is Equipment:
			var color = item.get_rarity_color()
			text += "[b]%s:[/b] [color=%s]%s[/color]\n" % [slot_name, color, item.name]
		else:
			text += "[b]%s:[/b] Empty\n" % slot_name
	return text
