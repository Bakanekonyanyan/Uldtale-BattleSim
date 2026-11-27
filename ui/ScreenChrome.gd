# res://ui/ScreenChrome.gd
# Shared frame for menu/town screens so they all look and behave the same:
#   - a dim layer over the background art (text stays readable)
#   - a header bar: screen title on the left, info (money etc.) on the right
#   - a "Back" button bottom-right, also triggered by Esc
# Plus small shared formatting helpers (item rows, rarity colors, slot names).
#
# Usage (in a screen's _ready):
#   chrome = ScreenChrome.attach(self, "Blacksmith", _on_back_pressed)
#   chrome.set_info("Money: 1g 20s")
#   ScreenChrome.place($UI/ItemList, ScreenChrome.LIST_RECT)
#
# Standard 1200x720 grid (keep new screens on it):
#   header 0-56 | content 72-624 | footer 640-688
#   left column x 32-472, right column x 496-1168
class_name ScreenChrome
extends CanvasLayer

const HEADER_H := 56
const CONTENT_TOP := 72
const CONTENT_BOTTOM := 624
const FOOTER_Y := 640
const LEFT_X := 32
const LEFT_W := 440
const RIGHT_X := 496
const RIGHT_W := 672
const BACK_RECT := Rect2(1008, 640, 160, 48)
const LIST_RECT := Rect2(32, 116, 440, 508)       # list under a tab row
const DETAIL_RECT := Rect2(496, 72, 672, 552)     # full-height detail panel
const DIM_COLOR := Color(0.03, 0.025, 0.04, 0.55)
const ACCENT := Color("e5c34a")
const MUTED := Color("a99f90")

const SLOT_NAMES := {
	"main_hand": "Main Hand", "off_hand": "Off Hand", "head": "Head",
	"chest": "Chest", "hands": "Hands", "legs": "Legs", "feet": "Feet"
}

var title_label: Label
var info_label: Label
var back_button: Button
var _back: Callable

## Build the frame on `screen`. `back` may be an empty Callable for screens
## with no single way out (e.g. rewards); the Back button is then hidden.
static func attach(screen: Node, title: String, back: Callable = Callable(), back_text := "Back to Town", dim := true) -> ScreenChrome:
	var chrome := ScreenChrome.new()
	chrome.name = "ScreenChrome"
	chrome.layer = 2  # above the scenes' own UI layer (1), below popups
	chrome._back = back
	chrome._build(title, back_text)
	if dim:
		_add_dim(screen)
	screen.add_child(chrome)
	return chrome

func _build(title: String, back_text: String) -> void:
	var bar := Panel.new()
	bar.theme_type_variation = "HeaderBar"
	bar.position = Vector2.ZERO
	bar.size = Vector2(1200, HEADER_H)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)

	title_label = Label.new()
	title_label.theme_type_variation = "ScreenTitle"
	title_label.text = title
	title_label.position = Vector2(LEFT_X, 4)
	title_label.size = Vector2(640, HEADER_H - 8)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(title_label)

	info_label = Label.new()
	info_label.theme_type_variation = "HeaderInfo"
	info_label.position = Vector2(560, 4)
	info_label.size = Vector2(608, HEADER_H - 8)
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(info_label)

	back_button = Button.new()
	back_button.text = back_text
	back_button.position = BACK_RECT.position
	back_button.size = BACK_RECT.size
	back_button.visible = _back.is_valid()
	back_button.pressed.connect(_go_back)
	add_child(back_button)

func set_title(text: String) -> void:
	title_label.text = text

func set_info(text: String) -> void:
	info_label.text = text

func _go_back() -> void:
	if _back.is_valid():
		_back.call()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and back_button.visible and not back_button.disabled:
		get_viewport().set_input_as_handled()
		_go_back()

## Darken the background art: a full-screen rect placed right after the
## background sprites/lights so every widget still draws above it.
static func _add_dim(screen: Node) -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = DIM_COLOR
	dim.size = Vector2(1200, 720)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var index := screen.get_child_count()
	for child in screen.get_children():
		if child is Control or child is CanvasLayer:
			index = child.get_index()
			break
	screen.add_child(dim)
	screen.move_child(dim, index)

# === LAYOUT / WIDGET HELPERS ===

## Put a Control at an absolute rect (works for tscn nodes with offsets).
static func place(node: Control, rect: Rect2) -> void:
	if node == null:
		return
	node.set_anchors_preset(Control.PRESET_TOP_LEFT)
	node.position = rect.position
	node.size = rect.size
	node.custom_minimum_size = Vector2.ZERO

## Category filter row: buttons sized to their text, small gap, at `rect`.
static func tab_row(row: HBoxContainer, rect: Rect2) -> void:
	place(row, rect)
	row.add_theme_constant_override("separation", 4)
	for b in row.get_children():
		if b is Control:
			b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			b.custom_minimum_size = Vector2(0, 34)

## Small muted caption above a list ("Pack", "For Sale", ...).
static func caption(parent: Node, text: String, pos: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_color_override("font_color", MUTED)
	parent.add_child(l)
	return l

## Tab-style filter buttons: the active one shows the theme's pressed style.
static func set_active_tab(tabs: Array, active: int) -> void:
	for i in range(tabs.size()):
		var b: Button = tabs[i]
		if b == null:
			continue
		for state in ["normal", "hover", "pressed"]:
			b.remove_theme_stylebox_override(state)
		b.modulate = Color.WHITE
		b.toggle_mode = true
		b.set_pressed_no_signal(i == active)

# === FORMATTING HELPERS ===

## Rarity color lightened so dark ones (uncommon blue) stay readable on dark panels.
static func rarity_color(item) -> Color:
	if item is Equipment and item.get_rarity_color() != "":
		return Color(item.get_rarity_color()).lerp(Color.WHITE, 0.35)
	return Color("e6dccb")

static func slot_name(slot: String) -> String:
	return SLOT_NAMES.get(slot, slot.capitalize())

## One list row: "Name  (ilvl 12)  x3  -  1s 20c". Same format on every screen.
static func item_row(item, quantity := 1, price := -1) -> String:
	var t: String = item.display_name
	if item is Equipment:
		t += "  (ilvl %d)" % item.item_level
	if quantity > 1:
		t += "  ×%d" % quantity
	if price >= 0:
		t += "  —  %s" % Currency.format_copper(price)
	return t

## Add a row to `list` with the standard text and rarity color. Returns the index.
static func add_item_row(list: ItemList, item, quantity := 1, price := -1) -> int:
	var idx := list.add_item(item_row(item, quantity, price))
	list.set_item_custom_fg_color(idx, rarity_color(item))
	return idx

static func money_text(character) -> String:
	return "Money: %s" % character.currency.get_formatted() if character else ""
