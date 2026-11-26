# res://tests/ui_sweep.gd
# UI sweep: opens every screen the way SceneManager does (add, wait a frame,
# set_player), then its overlays and tabs, with a character in a generated
# world. Reports:
#   UI OVERLAP|<screen>|<a>|<b>   two visible buttons/inputs overlapping
#   UI SHOT|<file>                a screenshot (when not headless)
#   UI DONE|<screens>|<overlaps>
# Script errors show in the output as usual ("SCRIPT ERROR"); run it with
#   godot res://tests/ui_sweep.tscn            (screenshots: needs a display)
#   godot --headless res://tests/ui_sweep.tscn (errors and overlaps only)
extends Node

const SCREENS := {
	"town": "res://scenes/TownScene.tscn",
	"guild": "res://scenes/town/GuildScene.tscn",
	"tavern": "res://scenes/town/TavernScene.tscn",
	"talents": "res://scenes/town/TalentScene.tscn",
	"blacksmith": "res://scenes/town/BlacksmithScene.tscn",
	"alchemist": "res://scenes/town/AlchemistScene.tscn",
	"enchanter": "res://scenes/town/EnchanterScene.tscn",
	"shop": "res://scenes/ShopScene.tscn",
	"equipment": "res://scenes/EquipmentScene.tscn",
	"status": "res://scenes/StatusScene.tscn",
	"inventory": "res://scenes/InventoryScene.tscn",
	"stash": "res://scenes/StashScene.tscn",
	"main_menu": "res://scenes/ui/MainMenu.tscn",
	"character_select": "res://scenes/ui/CharacterSelection.tscn",
	"character_creation": "res://scenes/ui/CharacterCreation.tscn",
}

var player: CharacterData
var overlaps := 0
var screens := 0
var shots := false

func _ready() -> void:
	await get_tree().process_frame   # the root is still setting up its children
	shots = DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://sweep"))
	player = CharacterFactory.create_character("Sweep", "Hume", "Paladin", true)
	player.town_state["birthplace"] = "Sunvale"
	Backgrounds.apply_creation(player, "orphan")
	CharacterManager.set_current_character(player)
	WorldGen.run(player, null, Callable(), 60)
	player.town_state["world_ready"] = true
	player.currency.copper = 50000
	for id in ["short_sword", "plate_armor", "buckler"]:
		var it = ItemManager.create_equipment_for_floor(id, 3)
		player.inventory.add_item(it, 1)
		player.equip_item(it)
	await _sweep()
	print("UI DONE|%d|%d" % [screens, overlaps])
	get_tree().quit()

func _sweep() -> void:
	for key in SCREENS:
		var res = load(SCREENS[key])
		if res == null:
			print("UI MISSING|", key)
			continue
		var scene = res.instantiate()
		get_tree().root.add_child(scene)
		await get_tree().process_frame
		if scene.has_method("set_player"):
			scene.set_player(player)
		elif scene.has_method("set_player_character"):
			scene.set_player_character(player)
		await _settle()
		screens += 1
		await _check(key, scene)
		# tabs and overlays
		if scene.has_method("_set_tab"):
			for t in range(8):
				if "TAB_NAMES" in scene and t >= scene.TAB_NAMES.size():
					break
				scene._set_tab(t)
				await _settle()
				await _check("%s_tab%d" % [key, t], scene)
		if scene.has_method("_set_branch"):
			for b in range(3):
				scene._set_branch(b)
				await _settle()
				await _check("%s_branch%d" % [key, b], scene)
		if key == "town":
			for v in ["guild", "market", "tavern", "book", "menu"]:
				scene._show_list(v)
				await _settle()
				await _check("town_list_" + v, scene)
			scene._show_districts()
			for o in [JournalScreen.open(scene, player), CompendiumScreen.open(scene), LedgerBoard.open(scene, player), CommissionBoard.open(scene, player), BestiaryGuide.open(scene)]:
				await _settle()
				await _check("town_%s" % o.get_class() if o.get_script() == null else "town_" + String(o.get_script().resource_path.get_file().get_basename()), o)
				o.queue_free()
			var c = ChronicleScreen.open(scene, player)
			for t in range(ChronicleScreen.TABS.size()):
				c._set_tab(t)
				await _settle()
				await _check("town_chronicle_%d" % t, c)
			c.queue_free()
		scene.queue_free()
		await _settle()

func _settle() -> void:
	for i in range(3):
		await get_tree().process_frame

## Overlapping visible controls (buttons, inputs, lists) and a screenshot.
func _check(label: String, root: Node) -> void:
	var ctrls: Array = []
	_collect(root, ctrls)
	for i in range(ctrls.size()):
		for j in range(i + 1, ctrls.size()):
			var a: Control = ctrls[i]
			var b: Control = ctrls[j]
			if a.is_ancestor_of(b) or b.is_ancestor_of(a):
				continue
			var inter = a.get_global_rect().intersection(b.get_global_rect())
			if min(inter.size.x, inter.size.y) >= 6.0:   # edges touching don't count
				overlaps += 1
				print("UI OVERLAP|%s|%s '%s'|%s '%s'" % [label, a.name, _txt(a), b.name, _txt(b)])
	if shots:
		await RenderingServer.frame_post_draw
		var f = "user://sweep/%s.png" % label
		get_viewport().get_texture().get_image().save_png(f)
		print("UI SHOT|", f)

func _collect(n: Node, out: Array) -> void:
	if n is CanvasItem and not n.is_visible_in_tree():
		return
	if n is BaseButton or n is LineEdit or n is ItemList or n is OptionButton or n is Panel:
		var c: Control = n
		if c.size.x > 2 and c.size.y > 2:
			out.append(c)
	for ch in n.get_children():
		_collect(ch, out)

func _txt(c: Control) -> String:
	return String(c.get("text")) if c.get("text") != null else ""
