# res://scenes/battle/components/ui/BattleUIController.gd
extends Node
class_name BattleUIController

signal action_selected(action: BattleAction)

# UI Node references
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
@export var combat_log_window: Panel
@export var debug_window: Panel

var player: CharacterData
var enemy: CharacterData
var ui_locked: bool = false
var is_initialized: bool = false

func _ready():
	print("BattleUIController: Ready")
	
	if not player_info_label:
		player_info_label = $PlayerInfo
	if not enemy_info_label:
		enemy_info_label = $EnemyInfo
	if not turn_label:
		turn_label = $TurnLabel
	if not combat_log:
		combat_log = $CombatLog
	if not debug_log:
		debug_log = $DebugWindow/DebugLog
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
	if not combat_log_window:
		combat_log_window = $CombatLogWindow
	if not debug_window:
		debug_window = $DebugWindow
	
	_force_ui_visible()
	
	print("BattleUIController: All nodes ready")

func _force_ui_visible():
	var nodes = [
		player_info_label, enemy_info_label, turn_label,
		combat_log, xp_label, action_buttons,
		wave_label, floor_label, dungeon_description_label,
		combat_log, debug_log, combat_log_window, debug_window
	]
	
	for node in nodes:
		if node:
			node.visible = true
			node.modulate = Color(1, 1, 1, 1)

func _force_ui_invisible():
	var nodes = [
		player_info_label, enemy_info_label, turn_label,
		combat_log, xp_label, action_buttons,
		wave_label, floor_label, dungeon_description_label,
		combat_log, debug_log, combat_log_window, debug_window
	]
	
	for node in nodes:
		if node:
			node.visible = false
			node.modulate = Color(1, 1, 1, 1)

func lock_ui():
	if ui_locked:
		return
	
	ui_locked = true
	disable_actions()
	print("BattleUIController: UI LOCKED")

func unlock_ui():
	if not ui_locked:
		return
	
	ui_locked = false
	print("BattleUIController: UI UNLOCKED")

func is_ui_locked() -> bool:
	return ui_locked

func initialize(p_player: CharacterData, p_enemy: CharacterData):
	player = p_player
	enemy = p_enemy
	print("BattleUIController: Initializing for %s vs %s" % [player.name, enemy.name])
	
	if inventory_menu:
		print("BattleUIController: Found inventory_menu node")
		
		if inventory_menu.has_signal("item_selected"):
			if not inventory_menu.is_connected("item_selected", Callable(self, "_on_inventory_item_selected")):
				inventory_menu.connect("item_selected", Callable(self, "_on_inventory_item_selected"))
				print("BattleUIController: Connected to item_selected signal")
		
		if inventory_menu.has_signal("inventory_closed"):
			if not inventory_menu.is_connected("inventory_closed", Callable(self, "_on_inventory_closed")):
				inventory_menu.connect("inventory_closed", Callable(self, "_on_inventory_closed"))
				print("BattleUIController: Connected to inventory_closed signal")
		else:
			print("BattleUIController: WARNING - inventory_menu does not have 'inventory_closed' signal!")
	else:
		print("BattleUIController: WARNING - inventory_menu is null!")
	
	_force_initial_display()
	
	is_initialized = true
	print("BattleUIController: Initialization complete")

func _force_initial_display():
	update_character_info(player, enemy)
	update_xp_display()
	update_debug_display()
	update_turn_display("Battle starting...")
	
	if player_info_label:
		player_info_label.queue_redraw()
	if enemy_info_label:
		enemy_info_label.queue_redraw()
	if turn_label:
		turn_label.queue_redraw()
	
	print("BattleUIController: Forced initial display")

# === DISPLAY UPDATES ===

func update_turn_display(text: String):
	if turn_label:
		turn_label.text = text
		turn_label.queue_redraw()

func update_xp_display():
	if xp_label and player:
		xp_label.text = "XP: %d / %d" % [player.xp, LevelSystem.calculate_xp_for_level(player.level)]
		xp_label.queue_redraw()

func update_dungeon_info(wave: int, floor: int, description: String):
	if wave_label:
		wave_label.text = "Wave: %d" % wave
		wave_label.queue_redraw()
	if floor_label:
		floor_label.text = "Floor: %d" % floor
		floor_label.queue_redraw()
	if dungeon_description_label:
		dungeon_description_label.text = description
		dungeon_description_label.queue_redraw()

func add_combat_log(message: String, color: String = "white"):
	if combat_log:
		combat_log.append_text("[color=%s]%s[/color]\n" % [color, message])
		combat_log.queue_redraw()

# === ACTION SETUP ===

# ✅ FIX: Accept both flags
func setup_player_actions(item_action_used: bool, main_action_taken: bool):
	"""Setup player action buttons"""
	clear_action_buttons()
	
	if action_buttons:
		action_buttons.visible = true
		action_buttons.modulate = Color(1, 1, 1, 1)
	
	# ✅ FIX: Disable ALL main actions if main action taken
	if main_action_taken:
		_add_disabled_button("Attack (Already Acted)")
		_add_disabled_button("Defend (Already Acted)")
		_add_disabled_button("View Enemy Equipment (Already Acted)")
		# Skills also disabled
		for skill_name in player.skills:
			var skill = player.get_skill_instance(skill_name)
			if skill:
				_add_disabled_button("%s (Already Acted)" % skill.name)
	else:
		# Normal buttons
		_add_action_button("Attack", func(): emit_signal("action_selected", BattleAction.attack(player, enemy)))
		_add_action_button("Defend", func(): emit_signal("action_selected", BattleAction.defend(player)))
		_add_action_button("View Enemy Equipment", func(): _show_enemy_equipment())
		_add_skill_buttons()
	
	# ✅ FIX: Items button shows state clearly
	var item_text = "Items (Used)" if item_action_used else "Items (Bonus Action)"
	var item_button = Button.new()
	item_button.text = item_text
	item_button.custom_minimum_size = Vector2(180, 40)
	item_button.visible = true
	
	if item_action_used:
		item_button.disabled = true
	else:
		item_button.pressed.connect(func():
			if is_ui_locked():
				print("BattleUIController: Button press ignored - UI locked")
				return
			_show_inventory()
		)
	
	action_buttons.add_child(item_button)
	
	if action_buttons:
		action_buttons.queue_redraw()

func _add_skill_buttons():
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
	if not action_buttons:
		return
	
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(180, 40)
	button.visible = true
	
	button.pressed.connect(func():
		if is_ui_locked():
			print("BattleUIController: Button press ignored - UI locked")
			return
		
		lock_ui()
		callback.call()
	)
	
	action_buttons.add_child(button)

func _add_disabled_button(text: String):
	if not action_buttons:
		return
	
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(180, 40)
	button.visible = true
	button.disabled = true
	action_buttons.add_child(button)

func clear_action_buttons():
	if action_buttons:
		for child in action_buttons.get_children():
			child.queue_free()

func enable_actions():
	if action_buttons:
		for button in action_buttons.get_children():
			if button is Button:
				var button_text = button.text
				
				if "(CD:" in button_text or "(Already Acted)" in button_text:
					button.disabled = true
				else:
					if button_text.contains("[") and button_text.contains("MP]"):
						var mp_cost = _extract_cost_from_text(button_text)
						button.disabled = (player.current_mp < mp_cost)
					elif button_text.contains("[") and button_text.contains("SP]"):
						var sp_cost = _extract_cost_from_text(button_text)
						button.disabled = (player.current_sp < sp_cost)
					else:
						button.disabled = false
				
				print("BattleUIController: Button '%s' disabled = %s" % [button.text, button.disabled])

func disable_actions():
	if action_buttons:
		for button in action_buttons.get_children():
			if button is Button:
				button.disabled = true

func _extract_cost_from_text(text: String) -> int:
	var start = text.find("[")
	var end = text.find(" ", start)
	if start != -1 and end != -1:
		var cost_str = text.substr(start + 1, end - start - 1)
		return int(cost_str)
	return 0

# === HELPER METHODS ===

func _get_skill_targets(skill: Skill) -> Array[CharacterData]:
	var result: Array[CharacterData] = []
	
	match skill.target:
		Skill.TargetType.SELF, Skill.TargetType.ALLY, Skill.TargetType.ALL_ALLIES:
			result.append(player)
		Skill.TargetType.ENEMY, Skill.TargetType.ALL_ENEMIES:
			result.append(enemy)
	
	return result

func _show_inventory():
	if inventory_menu and inventory_menu.has_method("show_inventory"):
		lock_ui()
		inventory_menu.show_inventory(player.inventory, player.currency)

func _on_inventory_item_selected(item: Item):
	var targets = []
	match item.consumable_type:
		Item.ConsumableType.DAMAGE, Item.ConsumableType.DEBUFF:
			targets = [enemy]
		_:
			targets = [player]
	
	emit_signal("action_selected", BattleAction.item(player, item, targets))

func _on_inventory_closed():
	print("BattleUIController: _on_inventory_closed() called!")
	print("BattleUIController: UI locked state before unlock: %s" % ui_locked)
	unlock_ui()
	enable_actions()
	print("BattleUIController: UI should now be unlocked and enabled")

func _show_enemy_equipment():
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

	unlock_ui()
	enable_actions()

func _get_enemy_equipment_text() -> String:
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

func update_character_info(p_player: CharacterData, p_enemy: CharacterData):
	if player_info_label and p_player:
		var status_str = _get_clean_status_string(p_player)
		
		player_info_label.text = "Player: %s\nHP: %d/%d\nMP: %d/%d\nSP: %d/%d\n%s" % [
			p_player.name, p_player.current_hp, p_player.max_hp,
			p_player.current_mp, p_player.max_mp,
			p_player.current_sp, p_player.max_sp,
			status_str
		]
		player_info_label.queue_redraw()
	
	if enemy_info_label and p_enemy:
		var status_str = _get_clean_status_string(p_enemy)
		
		enemy_info_label.text = "Enemy: %s\nHP: %d/%d\nMP: %d/%d\nSP: %d/%d\n%s" % [
			p_enemy.name, p_enemy.current_hp, p_enemy.max_hp,
			p_enemy.current_mp, p_enemy.max_mp,
			p_enemy.current_sp, p_enemy.max_sp,
			status_str
		]
		enemy_info_label.queue_redraw()
	
	if debug_log:
		update_debug_display()

func _get_clean_status_string(character: CharacterData) -> String:
	var effects = []
	
	var status_mgr = character.status_manager
	if status_mgr:
		for effect in status_mgr.active_effects:
			var effect_name = Skill.StatusEffect.keys()[effect]
			var duration = status_mgr.active_effects[effect]
			effects.append("%s (%d)" % [effect_name, duration])
	
	var buff_mgr = character.buff_manager
	if buff_mgr and buff_mgr.has_buffs():
		for attr in buff_mgr.buffs:
			var attr_name = Skill.AttributeTarget.keys()[attr]
			var value = buff_mgr.buffs[attr].value
			var duration = buff_mgr.buffs[attr].duration
			effects.append("%s +%d (%d)" % [attr_name, value, duration])
	
	if buff_mgr and buff_mgr.has_debuffs():
		for attr in buff_mgr.debuffs:
			var attr_name = Skill.AttributeTarget.keys()[attr]
			var value = buff_mgr.debuffs[attr].value
			var duration = buff_mgr.debuffs[attr].duration
			effects.append("%s -%d (%d)" % [attr_name, value, duration])
	
	return "Status: " + (", ".join(effects) if not effects.is_empty() else "Normal")

func update_debug_display():
	if not debug_log:
		return
	
	debug_log.clear()
	
	# === PLAYER STATS ===
	debug_log.append_text("[b][color=cyan]PLAYER STATS[/color][/b]\n")
	debug_log.append_text("ATK Power: %.1f | Spell Power: %.1f\n" % [player.get_attack_power(), player.spell_power])
	debug_log.append_text("Defense: %d | Armor Pen: %.1f%%\n" % [
		player.get_defense(), player.armor_penetration * 100
	])
	debug_log.append_text("Toughness: %.1f | Spell Ward: %.1f\n" % [player.toughness, player.spell_ward])
	debug_log.append_text("Accuracy: %.1f%% | Dodge: %.1f%% | Crit: %.1f%%\n\n" % [
		player.accuracy * 100, player.dodge * 100, player.critical_hit_rate * 100
	])
	
	# === PLAYER ELEMENTAL AFFINITIES ===
	if player.elemental_resistances:
		debug_log.append_text("[b][color=yellow]PLAYER ELEMENTAL DAMAGE:[/color][/b]\n")
		for element in ElementalDamage.Element.values():
			if element == ElementalDamage.Element.NONE:
				continue
			var bonus = player.get_elemental_damage_bonus(element)
			if bonus > 0.0:
				var elem_name = ElementalDamage.get_element_name(element)
				var color = ElementalDamage.get_element_color(element)
				debug_log.append_text("[color=%s]%s: +%d%%[/color]\n" % [color, elem_name, int(bonus * 100)])
		
		debug_log.append_text("\n[b][color=cyan]PLAYER RESISTANCES:[/color][/b]\n")
		for element in ElementalDamage.Element.values():
			if element == ElementalDamage.Element.NONE:
				continue
			var resist = player.get_elemental_resistance(element)
			var weak = player.get_elemental_weakness(element)
			
			if resist > 0.0 or weak > 0.0:
				var elem_name = ElementalDamage.get_element_name(element)
				var color = ElementalDamage.get_element_color(element)
				
				if resist > 0.0:
					debug_log.append_text("[color=%s]%s: -%d%% taken[/color]\n" % [color, elem_name, int(resist * 100)])
				elif weak > 0.0:
					debug_log.append_text("[color=%s]%s: +%d%% taken[/color]\n" % [color, elem_name, int(weak * 100)])
		
		debug_log.append_text("\n")
	
	# === ENEMY STATS ===
	debug_log.append_text("[b][color=red]ENEMY STATS[/color][/b]\n")
	debug_log.append_text("ATK Power: %.1f | Spell Power: %.1f\n" % [enemy.get_attack_power(), enemy.spell_power])
	debug_log.append_text("Defense: %d | Armor Pen: %.1f%%\n" % [
		enemy.get_defense(), enemy.armor_penetration * 100
	])
	debug_log.append_text("Toughness: %.1f | Spell Ward: %.1f\n" % [enemy.toughness, enemy.spell_ward])
	debug_log.append_text("Accuracy: %.1f%% | Dodge: %.1f%% | Crit: %.1f%%\n\n" % [
		enemy.accuracy * 100, enemy.dodge * 100, enemy.critical_hit_rate * 100
	])
	
	# === ENEMY ELEMENTAL AFFINITIES ===
	if enemy.elemental_resistances:
		debug_log.append_text("[b][color=yellow]ENEMY ELEMENTAL DAMAGE:[/color][/b]\n")
		for element in ElementalDamage.Element.values():
			if element == ElementalDamage.Element.NONE:
				continue
			var bonus = enemy.get_elemental_damage_bonus(element)
			if bonus > 0.0:
				var elem_name = ElementalDamage.get_element_name(element)
				var color = ElementalDamage.get_element_color(element)
				debug_log.append_text("[color=%s]%s: +%d%%[/color]\n" % [color, elem_name, int(bonus * 100)])
		
		debug_log.append_text("\n[b][color=orange]ENEMY WEAKNESSES:[/color][/b]\n")
		var has_weakness = false
		for element in ElementalDamage.Element.values():
			if element == ElementalDamage.Element.NONE:
				continue
			var weak = enemy.get_elemental_weakness(element)
			
			if weak > 0.0:
				var elem_name = ElementalDamage.get_element_name(element)
				var color = ElementalDamage.get_element_color(element)
				debug_log.append_text("[color=%s]%s: +%d%% taken[/color]\n" % [color, elem_name, int(weak * 100)])
				has_weakness = true
		
		if not has_weakness:
			debug_log.append_text("[color=gray]None[/color]\n")
		
		debug_log.append_text("\n[b][color=cyan]ENEMY RESISTANCES:[/color][/b]\n")
		var has_resistance = false
		for element in ElementalDamage.Element.values():
			if element == ElementalDamage.Element.NONE:
				continue
			var resist = enemy.get_elemental_resistance(element)
			
			if resist > 0.0:
				var elem_name = ElementalDamage.get_element_name(element)
				var color = ElementalDamage.get_element_color(element)
				debug_log.append_text("[color=%s]%s: -%d%% taken[/color]\n" % [color, elem_name, int(resist * 100)])
				has_resistance = true
		
		if not has_resistance:
			debug_log.append_text("[color=gray]None[/color]\n")
	
	debug_log.queue_redraw()

func display_result(result: ActionResult):
	var color = result.get_log_color()
	
	if result.actor and result.message.find("used") == -1:
		var prefix = ""
		if result.actor == player:
			prefix = "[color=yellow]Player:[/color] "
		else:
			prefix = "[color=red]Enemy:[/color] "
		add_combat_log(prefix + result.message, color)
	else:
		add_combat_log(result.message, color)
	
	update_character_info(player,enemy)
	update_xp_display()
	update_debug_display()

func hide_dungeon_info():
	"""Hide wave/floor/description labels for PvP battles"""
	if wave_label:
		wave_label.visible = false
	if floor_label:
		floor_label.visible = false
	if dungeon_description_label:
		dungeon_description_label.visible = false
	
	print("BattleUIController: Dungeon info hidden (PvP mode)")
