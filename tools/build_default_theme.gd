# res://tools/build_default_theme.gd
# Generates res://ui/default_theme.tres - the project-wide default UI theme
# (set in project.godot under [gui] theme/custom). Edit the constants below and
# re-run:   godot --headless --script res://tools/build_default_theme.gd
# This is the "default" look; a future art-directed theme can replace the file.
extends SceneTree

const BG := Color(0.07, 0.065, 0.085, 0.92)        # panels / lists
const BG_SOFT := Color(0.09, 0.08, 0.11, 0.85)     # detail text panels
const BUTTON := Color(0.14, 0.12, 0.16)
const BUTTON_HOVER := Color(0.19, 0.16, 0.21)
const BORDER := Color(0.29, 0.26, 0.31)
const ACCENT := Color("e5c34a")                    # dirty yellow
const TEXT := Color("e6dccb")                      # bone
const TEXT_MUTED := Color("a99f90")
const TEXT_DARK := Color("0b0a0d")
const SELECT_BG := Color(0.23, 0.19, 0.09)
const FONT_SIZE := 16
const TITLE_SIZE := 30

func _init():
	var t := Theme.new()
	t.default_font_size = FONT_SIZE
	
	# --- Buttons (also OptionButton / MenuButton / CheckButton) ---
	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, _box(BUTTON, BORDER, 2, 10, 6))
		t.set_stylebox("hover", type, _box(BUTTON_HOVER, ACCENT, 2, 10, 6))
		t.set_stylebox("pressed", type, _box(ACCENT, ACCENT, 2, 10, 6))
		t.set_stylebox("hover_pressed", type, _box(ACCENT.lightened(0.1), ACCENT, 2, 10, 6))
		t.set_stylebox("disabled", type, _box(BUTTON.darkened(0.3), BORDER.darkened(0.4), 2, 10, 6))
		t.set_stylebox("focus", type, _box(Color(0, 0, 0, 0), ACCENT, 2, 10, 6))
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, TEXT)
		t.set_color("font_pressed_color", type, TEXT_DARK)
		t.set_color("font_hover_pressed_color", type, TEXT_DARK)
		t.set_color("font_focus_color", type, TEXT)
		t.set_color("font_disabled_color", type, TEXT_MUTED.darkened(0.35))
	
	# --- Panels, lists, rich text (readable over any background art) ---
	t.set_stylebox("panel", "Panel", _box(BG, BORDER, 2, 12, 10))
	t.set_stylebox("panel", "PanelContainer", _box(BG, BORDER, 2, 12, 10))
	t.set_stylebox("panel", "ItemList", _box(BG, BORDER, 2, 8, 8))
	t.set_stylebox("focus", "ItemList", _box(Color(0, 0, 0, 0), BORDER, 2, 8, 8))
	t.set_stylebox("selected", "ItemList", _box(SELECT_BG, ACCENT, 1, 4, 2))
	t.set_stylebox("selected_focus", "ItemList", _box(SELECT_BG, ACCENT, 1, 4, 2))
	t.set_stylebox("hovered", "ItemList", _box(BUTTON_HOVER, Color(0, 0, 0, 0), 0, 4, 2))
	t.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", ACCENT)
	t.set_color("guide_color", "ItemList", Color(1, 1, 1, 0.05))
	t.set_constant("v_separation", "ItemList", 6)
	t.set_stylebox("normal", "RichTextLabel", _box(BG_SOFT, Color(0, 0, 0, 0), 0, 12, 10))
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_color("font_color", "Label", TEXT)
	
	# --- Inputs ---
	for type in ["LineEdit", "SpinBox"]:
		t.set_stylebox("normal", type, _box(BUTTON, BORDER, 2, 8, 4))
		t.set_stylebox("focus", type, _box(BUTTON, ACCENT, 2, 8, 4))
		t.set_color("font_color", type, TEXT)
	
	# --- Tabs, popups, dialogs, scrollbars ---
	t.set_stylebox("tab_selected", "TabBar", _box(ACCENT, ACCENT, 2, 12, 6))
	t.set_stylebox("tab_unselected", "TabBar", _box(BUTTON, BORDER, 2, 12, 6))
	t.set_stylebox("tab_hovered", "TabBar", _box(BUTTON_HOVER, ACCENT, 2, 12, 6))
	t.set_color("font_selected_color", "TabBar", TEXT_DARK)
	t.set_color("font_unselected_color", "TabBar", TEXT)
	t.set_stylebox("panel", "PopupMenu", _box(BG, BORDER, 2, 8, 6))
	t.set_stylebox("hover", "PopupMenu", _box(SELECT_BG, ACCENT, 1, 6, 2))
	t.set_stylebox("panel", "AcceptDialog", _box(Color(0.07, 0.065, 0.085, 1), BORDER, 2, 14, 12))
	t.set_stylebox("embedded_border", "Window", _box(Color(0.07, 0.065, 0.085, 1), ACCENT, 2, 4, 30))
	t.set_color("title_color", "Window", ACCENT)
	t.set_stylebox("scroll", "VScrollBar", _box(Color(0, 0, 0, 0.3), Color(0, 0, 0, 0), 0, 4, 4))
	t.set_stylebox("grabber", "VScrollBar", _box(BORDER, Color(0, 0, 0, 0), 0, 4, 4))
	t.set_stylebox("grabber_highlight", "VScrollBar", _box(ACCENT, Color(0, 0, 0, 0), 0, 4, 4))
	
	# --- Type variations used by ScreenChrome ---
	var marker = load("res://assets/fonts/PermanentMarker.woff2")
	t.set_type_variation("ScreenTitle", "Label")
	if marker:
		t.set_font("font", "ScreenTitle", marker)
	t.set_font_size("font_size", "ScreenTitle", TITLE_SIZE)
	t.set_color("font_color", "ScreenTitle", TEXT)
	t.set_type_variation("HeaderInfo", "Label")
	t.set_color("font_color", "HeaderInfo", ACCENT)
	t.set_type_variation("HeaderBar", "Panel")
	t.set_stylebox("panel", "HeaderBar", _box(Color(0.05, 0.045, 0.06, 0.95), ACCENT, 0, 0, 0, 3))
	
	var err = ResourceSaver.save(t, "res://ui/default_theme.tres")
	print("default theme saved: ", error_string(err))
	quit()

## Flat box: square-ish corners, solid border (bottom_border overrides for header bars).
func _box(bg: Color, border: Color, border_w: int, pad_x: int, pad_y: int, bottom_border := -1) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(border_w)
	if bottom_border >= 0:
		b.border_width_bottom = bottom_border
	b.set_corner_radius_all(2)
	b.content_margin_left = pad_x
	b.content_margin_right = pad_x
	b.content_margin_top = pad_y
	b.content_margin_bottom = pad_y
	return b
