# res://ui/CharacterTabs.gd
# The Character screen's tabs: Status, Equipment, Inventory and Talents are
# separate scenes that share this tab row in the header, so switching between
# them is one click (SceneManager.swap_to keeps the way back intact).
#   CharacterTabs.attach(chrome, "status", character)
class_name CharacterTabs
extends RefCounted

const TABS := [
	["status", "Status", SceneManager.ScenePath.STATUS],
	["equipment", "Equipment", SceneManager.ScenePath.EQUIPMENT],
	["inventory", "Inventory", SceneManager.ScenePath.INVENTORY],
	["talents", "Talents", SceneManager.ScenePath.TALENTS],
]

## Replace the chrome's title with the tab row. Talents is hidden during an
## expedition (talents are trained in town).
static func attach(chrome: ScreenChrome, active: String, character: CharacterData) -> HBoxContainer:
	if chrome == null:
		return null
	chrome.title_label.visible = false
	chrome.info_label.position.x = 640
	chrome.info_label.size.x = 528
	var row := HBoxContainer.new()
	row.name = "CharacterTabs"
	row.position = Vector2(ScreenChrome.LEFT_X, 8)
	row.size = Vector2(600, ScreenChrome.HEADER_H - 16)
	row.add_theme_constant_override("separation", 4)
	chrome.title_label.get_parent().add_child(row)
	var in_run := DungeonStateManager.dungeon_active
	var tabs: Array = []
	var index := 0
	for i in range(TABS.size()):
		var t = TABS[i]
		if t[0] == "talents" and in_run:
			continue
		var b := Button.new()
		b.text = t[1] + _badge(t[0], character)
		b.custom_minimum_size = Vector2(140, 40)
		b.focus_mode = Control.FOCUS_NONE
		if t[0] == active:
			index = tabs.size()
		else:
			var path = t[2]
			b.pressed.connect(func(): SceneManager.swap_to(path, character))
		row.add_child(b)
		tabs.append(b)
	ScreenChrome.set_active_tab(tabs, index)
	return row

## "(3)" when there are points to spend.
static func _badge(tab: String, c: CharacterData) -> String:
	if c == null:
		return ""
	var n := 0
	match tab:
		"status":
			n = c.attribute_points
		"talents":
			n = c.talents.available_points() if c.talents else 0
	return "  (%d)" % n if n > 0 else ""

## Points to spend across the Character screens (for the hub's badge).
static func pending(c: CharacterData) -> int:
	if c == null:
		return 0
	return c.attribute_points + (c.talents.available_points() if c.talents else 0)
