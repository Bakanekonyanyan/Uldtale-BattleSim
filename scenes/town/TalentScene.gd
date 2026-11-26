# res://scenes/town/TalentScene.gd
# Talents screen: the class's three branches, node details with Learn, the
# 6-skill battle loadout, and Respec. Rules live in TalentManager.
extends Control

var player_character: CharacterData
var chrome: ScreenChrome
var branch_index := 0
var selected_key := ""

var branch_buttons: Array[Button] = []
var branch_desc: Label
var node_buttons: Array[Button] = []
var node_keys: Array = []
var details: RichTextLabel
var learn_button: Button
var respec_button: Button
var status_label: Label
var loadout_box: GridContainer
var loadout_label: Label

const MUTED := "#a99f90"
const ACCENT := "#e5c34a"
const GOOD := "#8fd46a"

func _ready():
	if player_character == null:
		player_character = CharacterManager.get_current_character()
	_build_ui()
	_refresh()

func set_player(character: CharacterData) -> void:
	player_character = character
	_attach_tabs()
	if is_node_ready() and chrome:
		_refresh()

# === UI ===

func _build_ui() -> void:
	chrome = ScreenChrome.attach(self, "Talents", _on_back_pressed, "Back")
	_attach_tabs()
	var ui: CanvasLayer = $UI
	for i in 3:
		var b := Button.new()
		b.toggle_mode = true
		ScreenChrome.place(b, Rect2(32 + i * 150, 72, 142, 36))
		b.pressed.connect(func(): _set_branch(i))
		ui.add_child(b)
		branch_buttons.append(b)
	branch_desc = Label.new()
	branch_desc.add_theme_color_override("font_color", Color(MUTED))
	branch_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	ScreenChrome.place(branch_desc, Rect2(32, 112, 440, 40))
	ui.add_child(branch_desc)
	# up to 12 nodes per branch, laid out in rows by _refresh (forks side by side)
	for i in 12:
		var nb := Button.new()
		nb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		nb.clip_text = true
		nb.add_theme_font_size_override("font_size", 14)
		nb.pressed.connect(func(): _select(i))
		ui.add_child(nb)
		node_buttons.append(nb)
	
	var panel := Panel.new()
	ScreenChrome.place(panel, Rect2(496, 72, 672, 330))
	ui.add_child(panel)
	details = RichTextLabel.new()
	details.bbcode_enabled = true
	details.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	ScreenChrome.place(details, Rect2(14, 10, 644, 260))
	panel.add_child(details)
	learn_button = Button.new()
	learn_button.text = "Learn"
	ScreenChrome.place(learn_button, Rect2(14, 276, 160, 42))
	learn_button.pressed.connect(_on_learn)
	panel.add_child(learn_button)
	
	var lp := Panel.new()
	ScreenChrome.place(lp, Rect2(496, 412, 672, 212))
	ui.add_child(lp)
	loadout_label = Label.new()
	loadout_label.add_theme_color_override("font_color", Color(ACCENT))
	ScreenChrome.place(loadout_label, Rect2(14, 8, 644, 24))
	lp.add_child(loadout_label)
	loadout_box = GridContainer.new()
	loadout_box.columns = 3
	ScreenChrome.place(loadout_box, Rect2(14, 38, 644, 166))
	lp.add_child(loadout_box)
	
	respec_button = Button.new()
	ScreenChrome.place(respec_button, Rect2(32, 640, 260, 48))
	respec_button.pressed.connect(_on_respec)
	ui.add_child(respec_button)
	var thr := Button.new()
	thr.text = "Attribute passives"
	ScreenChrome.place(thr, Rect2(304, 640, 200, 48))   # beside Respec, clear of Back to Town
	thr.pressed.connect(_on_thresholds)
	ui.add_child(thr)
	status_label = Label.new()
	ScreenChrome.place(status_label, Rect2(520, 648, 420, 32))
	ui.add_child(status_label)

# === REFRESH ===

func _branches() -> Array:
	return TalentManager.branches_for(player_character.character_class)

func _set_branch(i: int) -> void:
	branch_index = i
	selected_key = ""
	_refresh()

func _select(i: int) -> void:
	if i < node_keys.size():
		selected_key = node_keys[i]
		_refresh()

func _refresh() -> void:
	if player_character == null or chrome == null:
		return
	var t: TalentManager = player_character.talents
	chrome.set_info("Talent points: %d   (Level %d)" % [t.available_points(), player_character.level])
	var branches = _branches()
	for i in branch_buttons.size():
		var b = branch_buttons[i]
		b.visible = i < branches.size()
		if i < branches.size():
			b.text = "%s (%d)" % [branches[i].name, t.spent_in_branch(branches[i].id)]
			b.set_pressed_no_signal(i == branch_index)
	if branches.is_empty():
		details.text = "[i]No talents for this class yet.[/i]"
		return
	var br = branches[clamp(branch_index, 0, branches.size() - 1)]
	branch_desc.text = br.get("description", "")
	var nodes = TalentManager.nodes_for(player_character.character_class, br.id)
	# rows: each plain node on its own row, each fork's options side by side
	var rows: Array = []
	var fork_rows := {}
	for n in nodes:
		if n.has("choice"):
			if not fork_rows.has(n.choice):
				fork_rows[n.choice] = []
				rows.append(fork_rows[n.choice])
			fork_rows[n.choice].append(n)
		else:
			rows.append([n])
	nodes = []
	var rects: Array = []
	var row_h = min(80, int(480 / max(1, rows.size())))
	for ri in range(rows.size()):
		var row: Array = rows[ri]
		var w = int((440 - 8 * (row.size() - 1)) / row.size())
		for ci in range(row.size()):
			nodes.append(row[ci])
			rects.append(Rect2(32 + ci * (w + 8), 156 + ri * row_h, w, row_h - 6))
	node_keys = nodes.map(func(n): return n.key)
	if selected_key == "" and not nodes.is_empty():
		selected_key = nodes[0].key
	for i in node_buttons.size():
		var nb = node_buttons[i]
		nb.visible = i < nodes.size()
		if i >= nodes.size():
			continue
		var n = nodes[i]
		ScreenChrome.place(nb, rects[i])
		var r = t.rank(n.key)
		var kind = _kind(n)
		var locked = t.locked_by(n.key) != ""
		nb.text = "  T%d  %s\n  %s   %s" % [n.tier, n.name, kind, "locked" if locked else "%d / %d" % [r, int(n.max_rank)]]
		var color = Color(ACCENT) if r > 0 else (Color("e6dccb") if t.can_learn(n.key) else Color(MUTED))
		if locked:
			color = Color(0.45, 0.4, 0.42)
		nb.add_theme_color_override("font_color", color)
		nb.add_theme_color_override("font_hover_color", color)
		nb.set_pressed_no_signal(false)
		nb.toggle_mode = true
		nb.set_pressed_no_signal(n.key == selected_key)
	_update_details()
	_update_loadout()
	respec_button.text = "Respec (%s)" % Currency.format_copper(t.respec_cost())
	respec_button.disabled = t.spent_points() == 0

static func _kind(n: Dictionary) -> String:
	if String(n.get("choice", "")) in ["mut2", "mut5"]:
		return "Mutation (choose 1)"
	if n.has("choice"):
		return "Passive (choose 1)"
	if n.has("skill"):
		return "Ultimate" if int(n.tier) == 5 else "Skill"
	return "Passive"

func _update_details() -> void:
	var t: TalentManager = player_character.talents
	var n = t.node(selected_key)
	if n.is_empty():
		details.text = ""
		learn_button.disabled = true
		return
	var r = t.rank(selected_key)
	var txt = "[b][font_size=20]%s[/font_size][/b]   [color=%s]Tier %d  -  rank %d / %d[/color]\n" % [n.name, MUTED, n.tier, r, int(n.max_rank)]
	txt += "[i]%s[/i]\n\n" % n.get("description", "")
	if n.has("choice"):
		var mates = TalentManager.nodes_for(player_character.character_class, n.branch).filter(func(o): return o.get("choice", "") == n.choice and o.key != n.key).map(func(o): return o.name)
		txt += "[color=%s]A fork: choose this or %s. The other locks until you respec.[/color]\n" % [GOOD, " / ".join(mates)]
	if n.has("skill"):
		var s = SkillManager.get_skill(n.skill)
		if s:
			txt += "[color=%s]Unlocks skill[/color] [b]%s[/b]  (%s)\n" % [ACCENT, s.name, s.category.capitalize() if s.category != "" else "Skill"]
			var bits: Array = []
			if s.power > 0: bits.append("power %d" % s.power)
			bits.append(s.cost_text())
			if s.cooldown > 0: bits.append("%d turn cooldown" % s.cooldown)
			if s.duration > 0: bits.append("%d turns" % s.duration)
			txt += "[color=%s]%s[/color]\n" % [MUTED, "  -  ".join(bits)]
			if s.weapon_bonus_text() != "":
				txt += "[color=%s]Weapon bonus: %s[/color]\n" % [MUTED, s.weapon_bonus_text()]
	else:
		var now = TalentManager.describe_effects(n, r) if r > 0 else []
		var nxt = TalentManager.describe_effects(n, r + 1) if r < int(n.max_rank) else []
		if not now.is_empty():
			txt += "[b]Now:[/b] %s\n" % "; ".join(now)
		if not nxt.is_empty():
			txt += "[b]Next rank:[/b] [color=%s]%s[/color]\n" % [GOOD, "; ".join(nxt)]
	var why = t.why_not(selected_key)
	learn_button.disabled = why != ""
	learn_button.text = "Learn" if r == 0 else "Rank up"
	if why != "" and r < int(n.max_rank):
		txt += "\n[color=%s]%s[/color]" % [MUTED, why]
	details.text = txt

func _update_loadout() -> void:
	for c in loadout_box.get_children():
		c.queue_free()
	var equipped = player_character.get_battle_skills()
	loadout_label.text = "BATTLE LOADOUT  %d / %d   (skills you can use in battle)" % [equipped.size(), TalentManager.loadout_size()]
	for sn in player_character.skills:
		var cb := CheckBox.new()
		cb.text = sn
		cb.button_pressed = sn in equipped
		cb.clip_text = true
		cb.custom_minimum_size = Vector2(210, 26)
		var skill = player_character.get_skill_instance(sn)
		if skill and skill.category == "ULTIMATE":
			cb.add_theme_color_override("font_color", Color(ACCENT))
		cb.toggled.connect(func(on): _toggle_skill(sn, on))
		loadout_box.add_child(cb)

func _toggle_skill(skill_name: String, on: bool) -> void:
	var eq: Array = player_character.get_battle_skills().duplicate()
	if on and not skill_name in eq:
		if eq.size() >= TalentManager.loadout_size():
			status_label.text = "The loadout is full (%d). Untick a skill first." % TalentManager.loadout_size()
			_update_loadout()
			return
		eq.append(skill_name)
	elif not on:
		eq.erase(skill_name)
	player_character.set_equipped_skills(eq)
	status_label.text = ""
	_update_loadout()

# === ACTIONS ===

func _on_learn() -> void:
	var t: TalentManager = player_character.talents
	var n = t.node(selected_key)
	if t.learn(selected_key):
		status_label.text = "Learned %s (rank %d)." % [n.name, t.rank(selected_key)]
		if n.has("skill") and not n.skill in player_character.get_battle_skills():
			status_label.text += " Equip %s in the loadout to use it." % n.skill
	_refresh()

func _on_respec() -> void:
	var t: TalentManager = player_character.talents
	if t.respec():
		status_label.text = "All talent points refunded."
	else:
		status_label.text = "Respec costs %s - not enough money." % Currency.format_copper(t.respec_cost())
	selected_key = ""
	_refresh()

## Attribute thresholds (data/thresholds.json): what's on, and how far to the next.
func _on_thresholds() -> void:
	var t: TalentManager = player_character.talents
	t.refresh_thresholds()
	var txt := "[color=%s]Raw attribute = base + gear (buffs don't count). Passives switch on at the threshold and stay on while you're above it.[/color]\n\n" % MUTED
	var cur := ""
	for p in TalentManager.threshold_passives():
		if String(p.attribute) != cur:
			cur = String(p.attribute)
			txt += "[b]%s[/b]  [color=%s](%d)[/color]\n" % [cur.capitalize(), ACCENT, t.raw_attribute(cur)]
		var on = String(p.id) in t.thresholds_on
		txt += "  [color=%s]%s %d  %s[/color] - %s\n" % [GOOD if on else MUTED, "●" if on else "○", int(p.at), p.name,
			"; ".join(TalentManager.describe_effects(p, 1))]
	var d = AcceptDialog.new()
	d.title = "Attribute passives"
	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.custom_minimum_size = Vector2(760, 520)
	label.text = txt
	d.add_child(label)
	add_child(d)
	d.popup_centered(Vector2i(800, 0))
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)

func _on_back_pressed() -> void:
	SaveManager.save_game(player_character)
	SceneManager.leave_screen(player_character)

## Status / Equipment / Inventory / Talents tabs in the header.
var char_tabs: HBoxContainer
func _attach_tabs() -> void:
	if chrome != null and char_tabs == null and player_character != null:
		char_tabs = CharacterTabs.attach(chrome, "talents", player_character)
