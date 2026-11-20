# res://scenes/battle/ui/BattleUIController.gd
# Everything the player SEES and CLICKS during a battle: info panels, combat log,
# action buttons, skill menu, target selection, inspect dialogs.
#
# Output: emits `action_selected(BattleAction)` when the player has fully chosen
# an action (incl. target). It never executes actions or changes game state.

class_name BattleUIController
extends Node

signal action_selected(action: BattleAction)

## The hero whose turn it is (the player, or a party member you control)
var player: CharacterData
## Everyone on your side: the player first, then the party
var heroes: Array[CharacterData] = []
var enemies: Array[CharacterData] = []
## Emitted when you flip a party member's Auto toggle
signal ally_auto_toggled(ally: CharacterData, auto: bool)
var party_strip: VBoxContainer
## Set by BattleOrchestrator (PvE): combat rules, turn order and battle state
var rules: BattleRules
var turn_queue: TurnQueue
var battle_context: BattleContext
var timeline_label: RichTextLabel
var link_label: RichTextLabel
var challenge_label: RichTextLabel

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
	# Guild bounty progress lines ("Bounty: Cull the Brutes 4/7")
	GuildManager.progress_message.connect(func(text): add_combat_log(text, "gold"))
	
# === INITIALIZATION ===

func initialize_multi(p_player: CharacterData, p_enemies: Array[CharacterData], p_allies: Array[CharacterData] = []):
	player = p_player
	heroes.clear()
	heroes.append(p_player)
	heroes.append_array(p_allies)
	enemies = p_enemies
	_create_enemy_panels()
	_create_party_strip()
	_create_rules_hud()
	update_all_character_info()

## Turn-order timeline (top) and the party Link gauge (by the XP line).
func _create_rules_hud() -> void:
	for n in [timeline_label, link_label, challenge_label]:
		if n:
			n.queue_free()
	timeline_label = null
	link_label = null
	challenge_label = null
	if rules == null:
		return
	timeline_label = RichTextLabel.new()
	timeline_label.bbcode_enabled = true
	timeline_label.scroll_active = false
	timeline_label.position = Vector2(192, 54)   # right under the dungeon banner
	timeline_label.size = Vector2(768, 21)
	timeline_label.add_theme_stylebox_override("normal", _slim_box())
	timeline_label.add_theme_font_size_override("normal_font_size", 14)
	timeline_label.add_theme_font_size_override("bold_font_size", 14)
	timeline_label.tooltip_text = "Turn order. After | is next round (re-rolled, so it's a preview)."
	add_child(timeline_label)
	link_label = RichTextLabel.new()
	link_label.bbcode_enabled = true
	link_label.scroll_active = false
	link_label.position = Vector2(64, 258)      # right under the player panel
	link_label.size = Vector2(304, 21)
	link_label.add_theme_stylebox_override("normal", _slim_box())
	link_label.add_theme_font_size_override("normal_font_size", 14)
	link_label.tooltip_text = "Party Link gauge: fills from hits, combos and Breaks. Ultimates cost %d; Unison Strike at full." % int(BattleRules.cfg().get("link", {}).get("ultimate_cost", 50))
	add_child(link_label)
	challenge_label = RichTextLabel.new()
	challenge_label.bbcode_enabled = true
	challenge_label.scroll_active = false
	challenge_label.position = Vector2(384, 78)   # under the timeline, clear of the enemy sprites
	challenge_label.size = Vector2(340, 21)
	challenge_label.add_theme_font_size_override("normal_font_size", 13)
	challenge_label.add_theme_stylebox_override("normal", _slim_box())
	challenge_label.visible = false
	add_child(challenge_label)
	# make room: turn label below the timeline, XP line below the Link bar
	if turn_label:
		turn_label.position.y = 76
	if xp_label:
		xp_label.position.y = 284

## Thin dark strip: the theme's padded panel is too tall for a one-line HUD row.
func _slim_box() -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.08, 0.75)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	return sb

func _update_rules_hud() -> void:
	if timeline_label and turn_queue:
		var parts: Array = []
		var crossed := false
		for e in turn_queue.upcoming(9):
			var c: CharacterData = e.character
			if e.next_round and not crossed and not parts.is_empty():
				parts[-1] += " [color=#777777]|[/color]"
				crossed = true
			var nm = c.name.get_slice(" ", 0) if heroes.has(c) else c.name.replace("Goblin ", "Gob ").replace("Troll ", "").replace("Fairy ", "").replace("Orc ", "")
			var col = "#7bd389" if heroes.has(c) else ("#ffd166" if c.get_meta("broken", false) else "#ff8c69")
			parts.append("[color=%s]%s%s[/color]" % [col, "[b]" if parts.is_empty() else "", nm + ("[/b]" if parts.is_empty() else "")])
		timeline_label.text = "Next: " + " › ".join(parts)
	if challenge_label:
		var ch: Dictionary = rules.challenge
		challenge_label.visible = not ch.is_empty() and timeline_label and timeline_label.visible
		if not ch.is_empty():
			var st = rules.battle_stats()
			var ok = WaveChallenges.met(ch, st)
			challenge_label.text = "[color=%s]%s %s[/color]" % ["#7bd389" if ok else "#ffd166", "✔" if ok else "◎", WaveChallenges.progress(ch, st)]
	if link_label and battle_context:
		var g = battle_context.link_gauge
		var full = rules.link_max()
		var filled = int(round(10.0 * g / max(1, full)))
		var col = "#ffd166" if rules.unison_ready() else "#90e0ef"
		link_label.text = "Link [color=%s]%s[/color][color=#444444]%s[/color] %d" % [col, "▰".repeat(filled), "▱".repeat(10 - filled), g]

## Party members under your info panel: HP/MP/SP and an Auto toggle each.
func _create_party_strip() -> void:
	if party_strip:
		party_strip.queue_free()
		party_strip = null
	if heroes.size() <= 1:
		return
	party_strip = VBoxContainer.new()
	party_strip.position = Vector2(64, 310)
	party_strip.size = Vector2(300, 100)
	party_strip.add_theme_constant_override("separation", 0)
	add_child(party_strip)
	if action_buttons:
		action_buttons.position.y = 416   # make room for the party rows
	for h in heroes:
		var row = HBoxContainer.new()
		var lbl = Label.new()
		lbl.name = "Info"
		lbl.custom_minimum_size = Vector2(230, 30)
		lbl.add_theme_font_size_override("font_size", 13)
		row.add_child(lbl)
		if h != heroes[0]:   # companions only: you always play yourself
			var auto = CheckBox.new()
			auto.text = "Auto"
			auto.add_theme_font_size_override("font_size", 13)
			auto.tooltip_text = "Let %s act on their own." % h.name
			auto.button_pressed = bool(h.get_meta("auto", false))
			auto.toggled.connect(func(on): ally_auto_toggled.emit(h, on))
			row.add_child(auto)
		row.set_meta("hero", h)
		party_strip.add_child(row)

func _update_party_strip() -> void:
	if not party_strip:
		return
	for row in party_strip.get_children():
		var h: CharacterData = row.get_meta("hero")
		var lbl: Label = row.get_node("Info")
		var ko = not h.is_alive()
		lbl.text = "%s%s   HP %d/%d  MP %d  SP %d  %s" % ["> " if h == player else "", h.name.get_slice(" ", 0), h.current_hp, h.max_hp, h.current_mp, h.current_sp, _break_text(h, false)] if not ko else "%s   Knocked out" % h.name.get_slice(" ", 0)
		lbl.modulate = Color(0.55, 0.55, 0.55) if ko else (Color(1, 0.55, 0.5) if h.get_meta("broken", false) else (Color(1, 0.9, 0.5) if h == player else Color.WHITE))

## Point the action buttons and the info panel at the hero whose turn it is.
func set_active_hero(h: CharacterData) -> void:
	player = h
	update_all_character_info()

func _create_enemy_panels():
	enemy_panels.clear()
	if not enemy_info_container:
		return
	
	# Free the whole per-enemy VBox (panel + inspect button), not just the panel
	for child in enemy_info_container.get_children():
		child.queue_free()
	
	for i in range(enemies.size()):
		var vbox = VBoxContainer.new()
		
		var panel = Panel.new()
		panel.custom_minimum_size = Vector2(300, 128)
		
		var rich_label = RichTextLabel.new()
		rich_label.bbcode_enabled = true
		rich_label.fit_content = true
		rich_label.scroll_active = true
		rich_label.custom_minimum_size = Vector2(285, 112)
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
	_update_party_strip()
	_update_rules_hud()

func update_player_info():
	if not player or not player_info:
		return
	
	var status_text = player.get_status_effects_string()
	player_info.text = "[b]%s[/b]%s\nHP: %d/%d   %s\nMP: %d/%d   SP: %d/%d\nStatus: %s" % [
		player.name, ("  [color=gray](%s)[/color]" % player.character_class) if heroes.size() > 1 else "",
		player.current_hp, player.max_hp, _break_text(player, true),
		player.current_mp, player.max_mp,
		player.current_sp, player.max_sp,
		status_text
	]
	if rules:
		var weak = BattleRules.weaknesses(player)
		player_info.text += "\n[color=#a99f90]Weak:[/color] %s" % (", ".join(weak) if not weak.is_empty() else "[color=#666666]none[/color]")

## Break meter as pips: "Break ◆◇◇" or "BROKEN" (BBCode, or plain for Labels).
func _break_text(c: CharacterData, bbcode: bool) -> String:
	if rules == null:
		return ""
	var hero = battle_context.is_hero(c) if battle_context else true
	if c.get_meta("broken", false):
		return "[color=#ff6b6b][b]BROKEN[/b][/color]" if bbcode else "BROKEN"
	var bm = BattleRules.break_max(c, hero)
	var bn = int(c.get_meta("break_meter", 0))
	if not bbcode:
		return "%s%s" % ["◆".repeat(bn), "◇".repeat(max(0, bm - bn))]
	return "Break [color=#ffd166]%s[/color][color=#555555]%s[/color]" % ["◆".repeat(bn), "◇".repeat(max(0, bm - bn))]

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
		if rules == null:   # PvP: plain panel
			rich_label.append_text("[b][color=%s]%s[/color][/b] %s\nHP: %d/%d (%.0f%%)\nMP: %d/%d | SP: %d/%d\nStatus: %s" % [
				color, enemy.name, alive_status,
				enemy.current_hp, enemy.max_hp, hp_percent,
				enemy.current_mp, enemy.max_mp,
				enemy.current_sp, enemy.max_sp,
				status_text
			])
			continue
		var name_col = "#ffd166" if enemy.has_meta("elite_affix") else color
		var t = "[b][color=%s]%s%s[/color][/b]\n" % [name_col, "★ " if enemy.has_meta("elite_affix") else "", enemy.name]
		if not enemy.is_alive():
			rich_label.append_text(t + "[color=red]DEFEATED[/color]")
			continue
		var barrier = int(enemy.get_meta("barrier", 0))
		t += "HP %d/%d%s   " % [enemy.current_hp, enemy.max_hp, ("  [color=#90e0ef]+%d shield[/color]" % barrier) if barrier > 0 else ""]
		if enemy.get_meta("broken", false):
			t += "[color=#ffd166][b]BROKEN[/b][/color]\n"
		else:
			var bm = BattleRules.break_max(enemy, false)
			var bn = int(enemy.get_meta("break_meter", 0))
			t += "Break [color=#ffd166]%s[/color][color=#555555]%s[/color]\n" % ["◆".repeat(bn), "◇".repeat(max(0, bm - bn))]
		var weak = Bestiary.shown_weaknesses(enemy)
		t += "[color=#a99f90]Weak:[/color] %s\n" % (", ".join(weak) if not weak.is_empty() else "[color=#666666]none[/color]")
		var intent = BattleRules.describe_intent(enemy, battle_context.intents if battle_context else {})
		t += "[color=#a99f90]Next:[/color] %s" % (intent if intent != "" else "[color=#666666]?[/color]")
		var tags: Array = []
		if enemy.status_manager:
			for k in enemy.status_manager.get_active_effects().keys():
				tags.append(String(Skill.StatusEffect.keys()[k] if k is int else k).capitalize())
		if enemy.buff_manager and enemy.buff_manager.has_buffs():
			tags.append("buffed")
		if enemy.buff_manager and enemy.buff_manager.has_debuffs():
			tags.append("debuffed")
		if not tags.is_empty():
			t += "\n[color=#c77dff]%s[/color]" % ", ".join(tags)
		rich_label.append_text(t)

func _get_hp_color(hp_percent: float) -> String:
	if hp_percent < 25: return "red"
	if hp_percent < 50: return "orange"
	if hp_percent < 75: return "yellow"
	return "white"

## Used by BattleNetworkSync (PvP)
func update_character_info(p_player: CharacterData, _single_enemy: CharacterData):
	player = p_player
	update_all_character_info()

func update_turn_display(text: String):
	if turn_label:
		turn_label.text = text

func update_xp_display():
	var you: CharacterData = heroes[0] if not heroes.is_empty() else player   # companions don't earn XP
	if xp_label and you:
		var xp_required = LevelSystem.calculate_xp_for_level(you.level)
		xp_label.text = "XP: %d/%d (Level %d)" % [you.xp, xp_required, you.level]

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
	if not main_action_taken and rules and rules.unison_ready():
		var uni = _create_action_button("★ Unison Strike")
		uni.add_theme_color_override("font_color", Color("ffd166"))
		uni.tooltip_text = "Spend the full Link gauge: every standing hero strikes one enemy together (x%.1f)." % float(BattleRules.cfg().get("link", {}).get("unison_mult", 1.4))
		uni.pressed.connect(func():
			lock_ui()
			show_target_selection(_get_living_enemies(),
				func(target): action_selected.emit(BattleAction.unison(player, target)),
				func(): unlock_ui(); enable_actions()))
		action_buttons.add_child(uni)
	var combos = _create_action_button("Combos")
	combos.tooltip_text = "Combo guide (free - doesn't use your turn)"
	combos.pressed.connect(func(): ComboGuide.open(self, heroes if not heroes.is_empty() else [player], enemies))
	action_buttons.add_child(combos)

func _add_attack_button():
	var btn = _create_action_button("Attack")
	btn.pressed.connect(_on_attack_pressed)
	action_buttons.add_child(btn)

func _add_defend_button():
	var guard = rules != null and rules.is_threatened(player)
	var btn = _create_action_button("Defend  ⛨ Perfect Guard" if guard else "Defend")
	if guard:
		btn.add_theme_color_override("font_color", Color("90e0ef"))
		btn.tooltip_text = "An enemy is about to hit you: Defend now to take far less damage, gain no Break pips, stagger the attacker and counter a charged strike."
	btn.pressed.connect(_on_defend_pressed)
	action_buttons.add_child(btn)

func _add_skills_button():
	var btn = _create_action_button("Skills")
	btn.pressed.connect(_on_skills_pressed)
	action_buttons.add_child(btn)

func _add_items_button(item_used: bool):
	var btn = _create_action_button("Items" + (" (Used)" if item_used else ""))
	btn.disabled = item_used
	# Remember it so enable_actions() doesn't re-enable a used Items button
	btn.set_meta("stay_disabled", item_used)
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
		func(target): action_selected.emit(BattleAction.attack(player, target)),
		func(): unlock_ui(); enable_actions()
	)

func _on_defend_pressed():
	lock_ui()
	action_selected.emit(BattleAction.defend(player))

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
	for skill_name in player.get_battle_skills():   # the equipped loadout (max 6)
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
	if skill.type == Skill.SkillType.REVIVE and _fallen_heroes().is_empty():
		return false   # nobody to raise
	if rules and not rules.link_ok(player, skill):
		return false   # ultimates need the Link gauge
	return skill.can_afford(player)

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
	
	# Combo hint: this skill would pay off a set-up status on a current enemy
	var combo_hint = _combo_hint(skill)
	if combo_hint != "":
		btn.text += "  - COMBO: " + combo_hint
		btn.add_theme_color_override("font_color", Color("e5c34a"))
		btn.tooltip_text = "Hits a target with a set-up status for bonus damage (see data/combos.json)."
	
	if rules and rules.link_cost(skill) > 0:
		btn.text += "  [Link %d]" % rules.link_cost(skill)
		if not rules.link_ok(player, skill):
			btn.tooltip_text = "Ultimate: needs %d Link (you have %d). Hits, combos and Breaks fill it." % [rules.link_cost(skill), battle_context.link_gauge]
	if skill.turn_delay > 0:
		btn.tooltip_text += ("\n" if btn.tooltip_text != "" else "") + "Knocks the target back %d place(s) in the turn order." % skill.turn_delay
	elif skill.turn_delay < 0:
		btn.tooltip_text += ("\n" if btn.tooltip_text != "" else "") + "Pulls the ally forward to act next."
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

## "Shatter on Goblin" if `skill` triggers a combo on a living enemy now, else "".
func _combo_hint(skill: Skill) -> String:
	for e in _get_living_enemies():
		var c = Combos.preview(player, skill, e)
		if not c.is_empty():
			return "%s on %s" % [c.name, e.name]
	return ""

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
	
	# Attributes affected
	var attr_names: PackedStringArray = []
	for attr in skill.attribute_targets:
		if attr != Skill.AttributeTarget.NONE:
			attr_names.append(Skill.AttributeTarget.keys()[attr].capitalize())
	if not attr_names.is_empty():
		info_text += "\n[b][color=cyan]Affects:[/color][/b] %s\n" % ", ".join(attr_names)
	
	# Status effects (previously collected but never displayed)
	var status_names: PackedStringArray = []
	for effect in skill.status_effects:
		if effect != Skill.StatusEffect.NONE:
			status_names.append(Skill.StatusEffect.keys()[effect].capitalize())
	if not status_names.is_empty():
		info_text += "[b][color=purple]Inflicts:[/color][/b] %s\n" % ", ".join(status_names)
	
	skill_info_rich_label.clear()
	skill_info_rich_label.append_text(info_text)
	skill_info_dialog.popup_centered()

func _on_skill_selected(skill: Skill):
	if skill_menu_panel:
		skill_menu_panel.hide()
	
	lock_ui()
	
	var needs_target = (skill.target == Skill.TargetType.ENEMY)
	
	# Revive: choose a knocked-out party member
	if skill.type == Skill.SkillType.REVIVE:
		var fallen = _fallen_heroes()
		if fallen.is_empty():
			add_combat_log("No one has fallen.", "gray")
			unlock_ui()
			enable_actions()
			return
		show_target_selection(fallen,
			func(target): action_selected.emit(BattleAction.skill(player, skill, [target])),
			func(): unlock_ui(); enable_actions()
		)
		return
	
	# Ally skills: choose which party member (alone, it's yourself)
	if skill.target == Skill.TargetType.ALLY and _living_heroes().size() > 1:
		show_target_selection(_living_heroes(),
			func(target): action_selected.emit(BattleAction.skill(player, skill, [target])),
			func(): unlock_ui(); enable_actions()
		)
		return
	
	if needs_target:
		var living_enemies = _get_living_enemies()
		if living_enemies.is_empty():
			add_combat_log("No valid targets for skill!", "red")
			unlock_ui()
			enable_actions()
			return
		
		show_target_selection(living_enemies,
			func(target): action_selected.emit(BattleAction.skill(player, skill, [target])),
			func(): unlock_ui(); enable_actions()
		)
	else:
		var targets = _get_skill_targets(skill)
		action_selected.emit(BattleAction.skill(player, skill, targets))

func _get_skill_targets(skill: Skill) -> Array[CharacterData]:
	var targets: Array[CharacterData] = []
	
	match skill.target:
		Skill.TargetType.SELF, Skill.TargetType.ALLY:
			targets.append(player)
		Skill.TargetType.ALL_ALLIES:
			targets = _living_heroes()
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
	
	if item.target_type == Item.TargetType.ALLY and _living_heroes().size() > 1:
		show_target_selection(_living_heroes(),
			func(t): action_selected.emit(BattleAction.item(player, item, [t])),
			func(): unlock_ui(); enable_actions()
		)
		return
	if not target:
		match item.target_type:
			Item.TargetType.ALL_ENEMIES:
				targets = _get_living_enemies()
			Item.TargetType.ALL_ALLIES:
				targets = _living_heroes()
			_:
				targets.append(player)
	elif item.target_type == Item.TargetType.ALL_ALLIES:
		targets = _living_heroes()
	else:
		targets.append(target)
	
	action_selected.emit(BattleAction.item(player, item, targets))

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
			if btn is Button and not btn.is_queued_for_deletion():
				btn.disabled = btn.get_meta("stay_disabled", false)

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

## Hide the battle HUD (used before the post-battle dialog)
func hide_battle_ui():
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
	# built in code: party rows, turn timeline, Link gauge
	for n in [party_strip, timeline_label, link_label, challenge_label]:
		if n:
			n.hide()

# === HELPERS ===

func _fallen_heroes() -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	for h in heroes:
		if not h.is_alive():
			out.append(h)
	return out

func _living_heroes() -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	for h in heroes:
		if h.is_alive():
			out.append(h)
	return out

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
	if enemy.has_meta("elite_affix"):
		info_text += "[color=#ffd166][b]Elite[/b] - %s[/color]\n\n" % EliteAffixes.describe(enemy)
	if rules:
		if Bestiary.tracks(battle_context) and Bestiary.party_can_study(heroes) and enemy.is_alive():
			var learned = Bestiary.study(enemy)
			if not learned.is_empty():
				add_combat_log("Your scholar studies %s: weak to %s." % [enemy.name, ", ".join(learned)], "purple")
				update_enemies_info()
		var shown = Bestiary.shown_weaknesses(enemy)
		info_text += "[b]Weak to:[/b] %s   [b]Break:[/b] %d weakness hits\n" % [", ".join(shown) if not shown.is_empty() else "none", BattleRules.break_max(enemy)]
		if shown.has("???"):
			info_text += "[color=gray]Find weaknesses by hitting them, Breaking the enemy, or bringing a scholar (%s, or a Scholarly companion).[/color]\n" % ", ".join(Bestiary.cfg().get("scholar_classes", []))
		info_text += "\n"
	
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
