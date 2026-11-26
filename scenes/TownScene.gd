# TownScene.gd
extends Node2D

var current_character: CharacterData

@onready var name_label = $UI/NameLabel
@onready var shop_button = $UI/ShopButton
@onready var dungeon_button = $UI/DungeonButton
@onready var equipment_button = $UI/EquipmentButton
@onready var status_button = $UI/StatusButton
@onready var inventory_button = $UI/InventoryButton
@onready var stash_button = $UI/StashButton
@onready var character_select_button = $UI/CharacterSelectButton
@onready var quit_button = $UI/QuitButton
@onready var arena_button = $UI/ArenaButton
@onready var alchemist_button = $UI/AlchemistButton
@onready var blacksmith_button = $UI/BlacksmithButton
@onready var guild_button = $UI/GuildButton


const TOWER := "the_dungeon"   # the Tower of Nexus (location id)

var chrome: ScreenChrome
var news_text: RichTextLabel
var inn_dialog: ConfirmationDialog
var inn_message := ""

func _ready():
	# Town keeps its art undimmed; the header carries name and money.
	chrome = ScreenChrome.attach(self, Regions.town_name(), Callable(), "", false)
	if name_label:
		name_label.visible = false
	if shop_button:
		shop_button.pressed.connect(_on_shop_pressed)
	if dungeon_button:
		dungeon_button.pressed.connect(_on_dungeon_pressed)
	if equipment_button:
		equipment_button.pressed.connect(_on_equipment_pressed)
	if status_button:
		status_button.pressed.connect(_on_status_pressed)
	if inventory_button:
		inventory_button.pressed.connect(_on_inventory_pressed)
	if stash_button:
		stash_button.pressed.connect(_on_stash_pressed)
	if character_select_button:
		character_select_button.pressed.connect(_on_charselect_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)
	if arena_button:
		arena_button.pressed.connect(_on_arena_pressed)
	if alchemist_button:
		alchemist_button.pressed.connect(func(): SceneManager.change_to_alchemist(current_character))
	if blacksmith_button:
		blacksmith_button.pressed.connect(func(): SceneManager.change_to_blacksmith(current_character))
	if guild_button:
		guild_button.pressed.connect(func(): SceneManager.change_to_guild(current_character))
	# Talents (built in code; same size as the other town buttons)
	# The old button grid (scene file) gives way to the districts.
	for child in $UI.get_children():
		if child is Button:
			child.visible = false
	_build_hub()
	# Town news: date, current event, the news ledger
	var news_panel := Panel.new()
	news_panel.position = Vector2(704, 72)
	news_panel.size = Vector2(464, 552)
	$UI.add_child(news_panel)
	news_text = RichTextLabel.new()
	news_text.bbcode_enabled = true
	news_text.position = Vector2(14, 10)
	news_text.size = Vector2(436, 532)
	news_panel.add_child(news_text)
	inn_dialog = ConfirmationDialog.new()
	inn_dialog.title = "The Wayfarer's Rest"
	inn_dialog.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD
	inn_dialog.confirmed.connect(func(): _rest(1))
	inn_dialog.add_button("Rest 3 nights", true, "three")
	inn_dialog.custom_action.connect(func(action):
		if action == "three":
			inn_dialog.hide()
			_rest(3))
	$UI.add_child(inn_dialog)
		
	update_ui()

func set_player(character: CharacterData):
	current_character = character
	if _needs_world(character):
		# generate before anything reads the world (the first refresh would
		# otherwise build an empty roster and the history would be skipped)
		call_deferred("_maybe_generate_world")
		return
	Log.debug("town", "TownScene: Character set - ", character.name)
	Log.debug("town", "TownScene: Inventory items - ", character.inventory.items)
	update_ui()

## Date, current world event and recent news (WorldClock).
func _refresh_news() -> void:
	if news_text == null or current_character == null:
		return
	var c = current_character
	var t = "[b][font_size=18]%s[/font_size][/b]\n" % WorldClock.date_text(c)
	var ev = WorldClock.current_event(c)
	if not ev.is_empty():
		var where = " in %s" % LocationManager.get_display_name(String(ev.location)) if String(ev.get("location", "")) != "" else ""
		t += "[color=gold]%s%s[/color] [color=gray](until day %d)[/color]\n" % [ev.get("name", ev.id), where, int(ev.ends_day)]
	t += "[color=#ffd166]%s[/color]  [color=#c9b8ff](Crowning in %d days)[/color]\n" % [LedgerManager.summary(c), LedgerManager.days_to_crowning(c)]
	if inn_message != "":
		t += "[color=lime]%s[/color]\n" % inn_message
	t += "\n[b]Town news[/b]\n"
	var news = WorldClock.get_news(c, 12)
	if news.is_empty():
		t += "[i][color=gray]Nothing of note yet.[/color][/i]"
	for n in news:
		var col = {"event": "#e9c46a", "guild": "#e07a5f", "rank": "#90e0ef", "rival": "#f4a261", "death": "#c77dff", "adventurer": "#b8c0ff"}.get(String(n.get("kind", "")), "#d8d0c0")
		t += "[color=gray]Day %d[/color]  [color=%s]%s[/color]\n" % [int(n.day), col, n.text]
	news_text.text = t

func _on_inn_pressed() -> void:
	var c = current_character
	if c == null:
		return
	var inj = DefeatManager.get_injuries(c)
	var t = "A warm bed and a hot meal. Resting passes time: injuries heal, the bounty board changes and the shop restocks each week.\n\n"
	t += "One night: %s   Three nights: %s\n" % [Currency.format_copper(WorldClock.inn_price(c, 1)), Currency.format_copper(WorldClock.inn_price(c, 3))]
	if not inj.is_empty():
		t += "Injuries: %s\n" % ", ".join(inj.map(func(x): return "%s (%d day(s))" % [DefeatManager.injury_info(String(x.id)).get("name", x.id), int(x.remaining)]))
	var due = GuildManager.get_active(c).filter(func(b): return not b.get("trial", false) and not GuildManager.is_complete(c, b))
	if not due.is_empty():
		t += "[!] Unfinished bounties keep their deadlines while you rest (soonest: %d day(s))." % due.map(func(b): return int(b.deadline)).min()
	inn_dialog.dialog_text = t
	inn_dialog.ok_button_text = "Rest 1 night"
	inn_dialog.popup_centered(Vector2i(620, 260))

func _rest(nights: int) -> void:
	var r = WorldClock.rest(current_character, nights)
	inn_message = r.reason
	update_ui()

func update_ui():
	_refresh_news()
	_refresh_hub()
	if name_label:
		if current_character:
			name_label.text = "Character: " + current_character.name
			if chrome:
				chrome.set_info("%s  -  Lv %d %s %s  -  %s-Rank    %s" % [current_character.name, current_character.level, current_character.race, current_character.character_class, RankManager.get_rank(current_character), ScreenChrome.money_text(current_character)])
		else:
			name_label.text = "No character loaded"
	else:
		Log.debug("town", current_character.name)
		Log.debug("town", "Warning: CharacterNameLabel not found in TownScene")

func _on_shop_pressed():
	SceneManager.change_to_shop(current_character)

# Update the _on_dungeon_pressed function in TownScene.gd:

func _on_dungeon_pressed():
	set_player(current_character)
	current_character.current_floor = 1
	show_location_selection_dialog()

# === EXPEDITION: pick a location, then a floor ===

func show_location_selection_dialog():
	"""Step 1 (The Gate): choose a location beyond Nexus. The Tower has its own district."""
	var dialog = ConfirmationDialog.new()
	dialog.title = "Choose Expedition"
	dialog.ok_button_text = "Next: Choose Floor"
	dialog.cancel_button_text = "Cancel"
	
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(460, 320)
	
	var ids: Array = LocationManager.get_ids().filter(func(i): return i != TOWER)
	var selected = [current_character.last_location if ids.has(current_character.last_location) else ids[0]]
	var buttons: Array[Button] = []
	
	var description = RichTextLabel.new()
	description.bbcode_enabled = true
	description.fit_content = true
	description.custom_minimum_size = Vector2(440, 90)
	
	var update_description = func():
		var loc = LocationManager.get_location(selected[0])
		var races = LocationManager.get_races(selected[0], EnemyFactory.races["non_playable"].keys())
		description.text = "[b]%s[/b]\n%s\n[color=#e5c34a]%s[/color]\n[color=gray]Enemies: %s  |  Highest floor unlocked: %d[/color]" % [
			loc.get("name", selected[0]),
			loc.get("description", ""),
			LocationManager.where_text(selected[0]),
			"Mixed (" + ", ".join(races) + ")" if LocationManager.is_mixed(selected[0]) else ", ".join(races),
			RankManager.start_floor_limit(current_character, selected[0])
		]
	
	for location_id in ids:
		var btn = Button.new()
		btn.text = "%s  (Floor %d)" % [LocationManager.get_display_name(location_id), RankManager.start_floor_limit(current_character, location_id)]
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(440, 36)
		btn.button_pressed = location_id == selected[0]
		buttons.append(btn)
		btn.pressed.connect(func():
			selected[0] = location_id
			for other in buttons:
				other.button_pressed = other == btn
			update_description.call()
		)
		vbox.add_child(btn)
	
	vbox.add_child(description)
	update_description.call()
	
	dialog.add_child(vbox)
	add_child(dialog)
	dialog.popup_centered()
	
	dialog.confirmed.connect(func():
		current_character.last_location = selected[0]
		dialog.queue_free()
		show_floor_selection_dialog(selected[0])
	)
	dialog.canceled.connect(func(): dialog.queue_free())

func show_floor_selection_dialog(location_id: String = "the_dungeon"):
	"""Step 2: choose a starting floor. Progress is tracked per location."""
	var max_selectable = RankManager.start_floor_limit(current_character, location_id)
	Log.debug("town", "TownScene: Floor selection for %s - max unlocked floor %d" % [location_id, max_selectable])
	
	var dialog = ConfirmationDialog.new()
	dialog.title = "%s - Select Starting Floor" % LocationManager.get_display_name(location_id)
	dialog.ok_button_text = "Start Expedition"
	dialog.cancel_button_text = "Back"
	
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(300, 200)
	
	var info_label = Label.new()
	info_label.text = "Choose which floor to start from:"
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(info_label)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer)
	
	var grid = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	
	var floor_buttons: Array[Button] = []
	current_character.current_floor = 1
	
	for floor_num in range(1, DungeonStateManager.max_floor + 1):
		var btn = Button.new()
		btn.text = str(floor_num)
		btn.custom_minimum_size = Vector2(50, 40)
		btn.toggle_mode = true
		btn.disabled = floor_num > max_selectable
		btn.button_pressed = floor_num == 1
		floor_buttons.append(btn)
		btn.pressed.connect(func():
			for other in floor_buttons:
				other.button_pressed = other == btn
			current_character.current_floor = floor_num
		)
		grid.add_child(btn)
	
	vbox.add_child(grid)
	
	var progress_label = Label.new()
	progress_label.text = "\nYou can start from floors 1-%d here." % max_selectable
	if RankManager.floor_cap(current_character) > 0:
		progress_label.text += "\n%s: floors up to %d. Get promoted at the Guild to go deeper." % [
			RankManager.display(RankManager.get_rank(current_character)), RankManager.floor_cap(current_character)]
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(progress_label)
	
	dialog.add_child(vbox)
	add_child(dialog)
	dialog.popup_centered()
	
	dialog.confirmed.connect(func():
		var final_floor = current_character.current_floor
		dialog.queue_free()
		show_omen_dialog(location_id, final_floor)
	)
	
	# "Back" returns to the location picker (the Tower has none)
	dialog.canceled.connect(func():
		dialog.queue_free()
		if location_id != TOWER:
			show_location_selection_dialog()
	)

## Step 3: optional Omens - harder rules for more loot (RunState, data/omens.json).
func show_omen_dialog(location_id: String, start_floor: int) -> void:
	var omens = RunState.all_omens()
	var cap = int(RunState.omen_data().get("max_omens", 3))
	var dialog = ConfirmationDialog.new()
	dialog.title = "Omens - tempt fate for better loot"
	dialog.ok_button_text = "Set Out"
	dialog.cancel_button_text = "Back"
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(520, 0)
	var info = Label.new()
	info.text = "Pick up to %d Omens. Each makes the expedition harder and adds to its gold and materials." % cap
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.custom_minimum_size = Vector2(520, 0)
	vbox.add_child(info)
	var total = Label.new()
	var boxes: Array = []
	var refresh = func():
		var picked = boxes.filter(func(b): return b.button_pressed)
		for b in boxes:
			b.disabled = not b.button_pressed and picked.size() >= cap
		var bonus := 0.0
		for b in picked:
			bonus += float(omens[b.get_meta("id")].get("reward", 0.0))
		total.text = "Loot bonus: +%d%%" % int(round(bonus * 100)) if not picked.is_empty() else "No Omens: a normal expedition."
	for id in omens:
		var o: Dictionary = omens[id]
		var cb = CheckBox.new()
		cb.text = "%s  (+%d%%)  -  %s" % [o.get("name", id), int(round(float(o.get("reward", 0)) * 100)), o.get("description", "")]
		cb.set_meta("id", id)
		cb.toggled.connect(func(_on): refresh.call())
		boxes.append(cb)
		vbox.add_child(cb)
	total.add_theme_color_override("font_color", Color("ffd166"))
	vbox.add_child(total)
	refresh.call()
	dialog.add_child(vbox)
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func():
		RunState.clear()
		RunState.set_omens(boxes.filter(func(b): return b.button_pressed).map(func(b): return b.get_meta("id")))
		BondManager.react_to_news(current_character, "omens", RunState.omens.size())
		Log.debug("town", "TownScene: Starting %s at floor %d, omens %s" % [location_id, start_floor, str(RunState.omens)])
		SceneManager.start_dungeon_from_floor(current_character, start_floor, location_id)
		dialog.queue_free())
	dialog.canceled.connect(func():
		dialog.queue_free()
		show_floor_selection_dialog(location_id))

func _on_equipment_pressed():
	SceneManager.change_to_equipment(current_character)

func _on_status_pressed():
	SceneManager.change_to_status(current_character)

func _on_inventory_pressed():
	SceneManager.change_to_inventory(current_character)

func _on_stash_pressed():
	SceneManager.change_to_stash(current_character)
	
func _on_quit_pressed():
	CharacterManager.save_character(current_character)
	get_tree().quit()

func _on_charselect_pressed():
	SceneManager.change_to_character_selection()

func _on_arena_pressed():
	SceneManager.change_to_arena(current_character)

## A new world: the Guild lives through its history before you arrive
## (WorldGen). Saves that already have a world are left alone.
## A new game whose world hasn't been made yet: world_pending is set at
## creation and on "new game"; saves from before the flag count if they have
## no Guild yet.
func _needs_world(c: CharacterData) -> bool:
	if c == null or c.town_state.get("world_ready", false):
		return false
	if c.town_state.get("world_pending", false):
		return true
	return not c.town_state.has("adventurers") and WorldClock.day(c) <= 1

func _maybe_generate_world() -> void:
	var c = current_character
	if not _needs_world(c):
		update_ui()
		return
	for k in WorldShare.WORLD_KEYS:
		c.town_state.erase(k)   # anything built before the history is thrown away
	c.town_state.erase("world_pending")
	if WorldGen.days() <= 0:
		WorldGen._finish(c)
		WorldShare.found(c)
		c.town_state["world_ready"] = true
		update_ui()
		return
	var layer := CanvasLayer.new()
	layer.layer = 80
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.035, 0.05, 0.96)
	dim.size = Vector2(1200, 720)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)
	var label := Label.new()
	label.position = Vector2(200, 300)
	label.size = Vector2(800, 120)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.add_theme_font_size_override("font_size", 22)
	label.text = "The Guild's history is being written..."
	layer.add_child(label)
	add_child(layer)
	await WorldGen.run(c, get_tree(), func(d, total, date):
		label.text = "The Guild's history is being written...\n%s\n(%d%%)" % [date, int(100.0 * d / total)])
	c.town_state["world_ready"] = true
	WorldShare.found(c)   # a world of its own, that other characters can join
	SaveManager.save_game(c)
	layer.queue_free()
	update_ui()

# === THE HUB: districts of Nexus (docs/design/UI_UX.md) ===
# Left: six districts, each with a live status line. A district with several
# places opens its list in the same panel ("<- Nexus" or Esc returns).
# Footer: Character [C], Book [B], Menu. Keys 1-6 open districts.

const DISTRICTS := [
	{"id": "tower", "name": "The Tower", "sub": "The dungeon at the heart of Nexus"},
	{"id": "gate", "name": "The Gate", "sub": "Expeditions across Nyxarys"},
	{"id": "guild", "name": "Guild Hall", "sub": "Bounties, trials, the Ledger, training"},
	{"id": "market", "name": "Market", "sub": "Shop, Blacksmith, Alchemist, Enchanter"},
	{"id": "tavern", "name": "Tavern & Inn", "sub": "Adventurers, rumours, a bed"},
	{"id": "bank", "name": "Bank", "sub": "Your vault"},
]

var hub_panel: Control
var hub_view := ""                  # "" = districts, else the open list
var district_buttons := {}
var footer_buttons := {}

func _build_hub() -> void:
	hub_panel = Control.new()
	hub_panel.name = "Hub"
	hub_panel.position = Vector2(ScreenChrome.LEFT_X, ScreenChrome.CONTENT_TOP)
	hub_panel.size = Vector2(648, 552)
	$UI.add_child(hub_panel)
	var footer := HBoxContainer.new()
	footer.name = "HubFooter"
	footer.position = Vector2(ScreenChrome.LEFT_X, ScreenChrome.FOOTER_Y)
	footer.size = Vector2(648, 48)
	footer.add_theme_constant_override("separation", 12)
	$UI.add_child(footer)
	for f in [["character", "Character  [C]", _open_character], ["book", "Book  [B]", func(): _show_list("book")], ["menu", "Menu", func(): _show_list("menu")]]:
		var b := Button.new()
		b.text = f[1]
		b.custom_minimum_size = Vector2(208, 48)
		b.pressed.connect(f[2])
		footer.add_child(b)
		footer_buttons[f[0]] = b
	_show_districts()

func _clear_hub() -> void:
	district_buttons.clear()
	for ch in hub_panel.get_children():
		hub_panel.remove_child(ch)
		ch.queue_free()

func _show_districts() -> void:
	_clear_hub()
	hub_view = ""
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size = hub_panel.size
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	hub_panel.add_child(grid)
	for i in range(DISTRICTS.size()):
		var d = DISTRICTS[i]
		var b := Button.new()
		b.name = "District_" + d.id
		b.custom_minimum_size = Vector2(316, 172)
		var card := VBoxContainer.new()
		card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 16)
		card.alignment = BoxContainer.ALIGNMENT_CENTER
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var title := Label.new()
		title.name = "Title"
		title.text = d.name
		title.theme_type_variation = "ScreenTitle"
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var status := Label.new()
		status.name = "Status"
		status.autowrap_mode = TextServer.AUTOWRAP_WORD
		status.add_theme_color_override("font_color", ScreenChrome.MUTED)
		status.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(title)
		card.add_child(status)
		b.add_child(card)
		b.tooltip_text = "%s  [%d]" % [d.sub, i + 1]
		b.pressed.connect(_open_district.bind(d.id))
		grid.add_child(b)
		district_buttons[d.id] = b
	_refresh_hub()

## Districts' live status lines and the footer badges.
func _refresh_hub() -> void:
	var c = current_character
	if c == null or hub_panel == null:
		return
	for d in DISTRICTS:
		var b: Button = district_buttons.get(d.id)
		if b != null:
			var st: Label = b.get_child(0).get_node("Status")
			st.text = _district_status(d.id)
	var pts := CharacterTabs.pending(c)
	if footer_buttons.has("character"):
		footer_buttons.character.text = "Character  [C]" + ("  (%d)" % pts if pts > 0 else "")

func _district_status(id: String) -> String:
	var c = current_character
	match id:
		"tower":
			return "Start from floor %d" % RankManager.start_floor_limit(c, TOWER)
		"gate":
			return "%d places beyond the walls" % (LocationManager.get_ids().size() - 1)
		"guild":
			var active = GuildManager.get_active(c)
			var done = active.filter(func(b): return GuildManager.is_complete(c, b)).size()
			if active.is_empty():
				return "No bounties taken"
			return "%d bounties%s" % [active.size(), ("  -  %d ready to turn in!" % done) if done > 0 else ""]
		"market":
			return "Shop, Smith, Alchemist, Enchanter"
		"tavern":
			var inj = DefeatManager.get_injuries(c)
			if not inj.is_empty():
				return "%d injur%s - rest at the inn" % [inj.size(), "y" if inj.size() == 1 else "ies"]
			var party = PartyManager.members(c).size()
			return "Your party: %d companion%s" % [party, "" if party == 1 else "s"] if party > 0 else "Find companions, rest"
		"bank":
			return "%d item stacks in the vault" % (c.stash.items.size() if c.stash else 0)
	return ""

func _open_district(id: String) -> void:
	match id:
		"tower":
			current_character.current_floor = 1
			current_character.last_location = TOWER
			show_floor_selection_dialog(TOWER)
		"gate":
			current_character.current_floor = 1
			show_location_selection_dialog()
		"bank":
			SceneManager.change_to_stash(current_character)
		_:
			_show_list(id)

func _open_character() -> void:
	SceneManager.change_to_status(current_character)

## The places in a district (or the Book / Menu), as a list in the hub panel.
func _lists() -> Dictionary:
	var c = current_character
	return {
		"guild": ["Guild Hall", [
			["Guild Desk", "Bounties, rank trials, the Ledger, armour training, retiring", func(): SceneManager.change_to_guild(c)],
			["Commission Board", "Requests from the crafters - finish them for better prices", func(): CommissionBoard.open(self, c)],
		]],
		"market": ["Market", [
			["Shop", "Buy and sell", func(): SceneManager.change_to_shop(c)],
			["Blacksmith", "Upgrade, reinforce, salvage", func(): SceneManager.change_to_blacksmith(c)],
			["Alchemist", "Brew potions and tonics", func(): SceneManager.change_to_alchemist(c)],
			["Enchanter", "Add modifiers, raise rarity", func(): SceneManager.change_to_enchanter(c)],
		]],
		"tavern": ["Tavern & Inn", [
			["Tavern", "Talk, drink, invite companions, rumours, the bard", func(): SceneManager.change_to_tavern(c)],
			["Rest at the Inn", "Pass the days: heal injuries, restock the town", _on_inn_pressed],
		]],
		"book": ["The Book", [
			["Journal", "Your story so far, open threads", func(): JournalScreen.open(self, c)],
			["Chronicle", "The history of the Guild: people, places, the fallen, legends", func(): ChronicleScreen.open(self, c)],
			["Compendium", "How things work", func(): CompendiumScreen.open(self)],
			["Bestiary", "Enemy weaknesses you've found", func(): BestiaryGuide.open(self)],
			["Combos", "Set-ups and payoffs for your party", _open_combos],
		]],
		"menu": ["Menu", [
			["Character Selection", "Save and switch characters", _on_charselect_pressed],
			["Save and Quit", "Save and close the game", _on_quit_pressed],
		]],
	}

func _show_list(id: String) -> void:
	var spec = _lists().get(id)
	if spec == null:
		return
	_clear_hub()
	hub_view = id
	var box := VBoxContainer.new()
	box.size = hub_panel.size
	box.add_theme_constant_override("separation", 10)
	hub_panel.add_child(box)
	var title := Label.new()
	title.text = spec[0]
	title.theme_type_variation = "ScreenTitle"
	box.add_child(title)
	for e in spec[1]:
		var b := Button.new()
		b.text = "%s\n%s" % [e[0], e[1]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(648, 72)
		b.pressed.connect(e[2])
		box.add_child(b)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var back := Button.new()
	back.text = "<- Nexus  [Esc]"
	back.custom_minimum_size = Vector2(208, 48)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(_show_districts)
	box.add_child(back)

func _open_combos() -> void:
	var party: Array = [current_character]
	for n in PartyManager.members(current_character):
		party.append(AutoBattler.build_hero(n))
	ComboGuide.open(self, party)

func _unhandled_input(event: InputEvent) -> void:
	if current_character == null or hub_panel == null or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.is_action_pressed("ui_cancel"):
		if hub_view != "":
			_show_districts()
		else:
			_show_list("menu")
	elif event.keycode == KEY_C:
		_open_character()
	elif event.keycode == KEY_B:
		_show_list("book")
	elif event.keycode >= KEY_1 and event.keycode <= KEY_6:
		_open_district(DISTRICTS[event.keycode - KEY_1].id)
	else:
		return
	get_viewport().set_input_as_handled()
