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


var chrome: ScreenChrome
var news_text: RichTextLabel
var inn_dialog: ConfirmationDialog
var inn_message := ""

func _ready():
	# Town keeps its art undimmed; the header carries name and money.
	chrome = ScreenChrome.attach(self, "Town", Callable(), "", false)
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
	var talents_button := Button.new()
	talents_button.name = "TalentsButton"
	talents_button.text = "Talents"
	talents_button.position = Vector2(472, 352)
	talents_button.size = Vector2(180, 60)
	talents_button.pressed.connect(func(): SceneManager.change_to_talents(current_character))
	$UI.add_child(talents_button)
	# Tavern: the Guild's adventurers (AdventurerManager)
	var tavern_button := Button.new()
	tavern_button.name = "TavernButton"
	tavern_button.text = "Tavern"
	tavern_button.position = Vector2(40, 352)
	tavern_button.size = Vector2(180, 60)
	tavern_button.pressed.connect(func(): SceneManager.change_to_tavern(current_character))
	$UI.add_child(tavern_button)
	# Combo guide
	var combo_button := Button.new()
	combo_button.name = "CombosButton"
	combo_button.text = "Combos"
	combo_button.position = Vector2(40, 440)
	combo_button.size = Vector2(180, 60)
	combo_button.pressed.connect(func():
		var party: Array = [current_character]
		for n in PartyManager.members(current_character):
			party.append(AutoBattler.build_hero(n))
		ComboGuide.open(self, party))
	$UI.add_child(combo_button)
	# Bestiary: enemy weaknesses you've found
	var bestiary_button := Button.new()
	bestiary_button.name = "BestiaryButton"
	bestiary_button.text = "Bestiary"
	bestiary_button.position = Vector2(256, 440)
	bestiary_button.size = Vector2(180, 60)
	bestiary_button.pressed.connect(func(): BestiaryGuide.open(self))
	$UI.add_child(bestiary_button)
	# Compendium: every system explained (CompendiumScreen, data/compendium.json)
	var compendium_button := Button.new()
	compendium_button.name = "CompendiumButton"
	compendium_button.text = "Compendium"
	compendium_button.position = Vector2(472, 528)
	compendium_button.size = Vector2(180, 60)
	compendium_button.pressed.connect(func(): CompendiumScreen.open(self))
	$UI.add_child(compendium_button)
	# Journal: everything you're working on (JournalScreen)
	var journal_button := Button.new()
	journal_button.name = "JournalButton"
	journal_button.text = "Journal"
	journal_button.position = Vector2(256, 528)
	journal_button.size = Vector2(180, 60)
	journal_button.pressed.connect(func(): JournalScreen.open(self, current_character))
	var chronicle_button := Button.new()
	chronicle_button.name = "ChronicleButton"
	chronicle_button.text = "Chronicle"
	chronicle_button.position = Vector2(40, 616)
	chronicle_button.size = Vector2(180, 60)
	chronicle_button.pressed.connect(func(): ChronicleScreen.open(self, current_character))
	journal_button.get_parent().add_child(chronicle_button)
	$UI.add_child(journal_button)
	# Commissions: the shops' material requests (CommissionManager)
	var commissions_button := Button.new()
	commissions_button.name = "CommissionsButton"
	commissions_button.text = "Commissions"
	commissions_button.position = Vector2(40, 528)
	commissions_button.size = Vector2(180, 60)
	commissions_button.pressed.connect(func(): CommissionBoard.open(self, current_character))
	$UI.add_child(commissions_button)
	# Enchanter: raise rarity with materials (EnchantManager)
	var enchanter_button := Button.new()
	enchanter_button.name = "EnchanterButton"
	enchanter_button.text = "Enchanter"
	enchanter_button.position = Vector2(472, 440)
	enchanter_button.size = Vector2(180, 60)
	enchanter_button.pressed.connect(func(): SceneManager.change_to_enchanter(current_character))
	$UI.add_child(enchanter_button)
	# Inn: rest to pass days (WorldClock)
	var inn_button := Button.new()
	inn_button.name = "InnButton"
	inn_button.text = "Inn"
	inn_button.position = Vector2(256, 352)
	inn_button.size = Vector2(180, 60)
	inn_button.pressed.connect(_on_inn_pressed)
	$UI.add_child(inn_button)
	# Town news: date, current event, the news ledger
	var news_panel := Panel.new()
	news_panel.position = Vector2(700, 72)
	news_panel.size = Vector2(460, 352)
	$UI.add_child(news_panel)
	news_text = RichTextLabel.new()
	news_text.bbcode_enabled = true
	news_text.position = Vector2(14, 10)
	news_text.size = Vector2(432, 332)
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
	call_deferred("_maybe_generate_world")
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
	"""Step 1: choose where to go (The Dungeon or a themed location)."""
	var dialog = ConfirmationDialog.new()
	dialog.title = "Choose Expedition"
	dialog.ok_button_text = "Next: Choose Floor"
	dialog.cancel_button_text = "Cancel"
	
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(460, 320)
	
	var selected = [current_character.last_location if LocationManager.has_location(current_character.last_location) else LocationManager.DEFAULT_LOCATION]
	var buttons: Array[Button] = []
	
	var description = RichTextLabel.new()
	description.bbcode_enabled = true
	description.fit_content = true
	description.custom_minimum_size = Vector2(440, 90)
	
	var update_description = func():
		var loc = LocationManager.get_location(selected[0])
		var races = LocationManager.get_races(selected[0], EnemyFactory.races["non_playable"].keys())
		description.text = "[b]%s[/b]\n%s\n[color=gray]Enemies: %s  |  Highest floor unlocked: %d[/color]" % [
			loc.get("name", selected[0]),
			loc.get("description", ""),
			"Mixed (" + ", ".join(races) + ")" if LocationManager.is_mixed(selected[0]) else ", ".join(races),
			RankManager.start_floor_limit(current_character, selected[0])
		]
	
	for location_id in LocationManager.get_ids():
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
	
	# "Back" returns to the location picker
	dialog.canceled.connect(func():
		dialog.queue_free()
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
func _maybe_generate_world() -> void:
	var c = current_character
	if c == null or c.town_state.get("world_ready", false):
		return
	if c.town_state.has("adventurers") or WorldClock.day(c) > 1 or WorldGen.days() <= 0:
		c.town_state["world_ready"] = true
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
	SaveManager.save_game(c)
	layer.queue_free()
	update_ui()

