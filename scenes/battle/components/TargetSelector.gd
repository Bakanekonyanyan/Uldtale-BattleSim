# res://scenes/battle/components/TargetSelector.gd
# UI component for selecting battle targets

class_name TargetSelector
extends Control

signal target_selected(target: CharacterData)
signal target_cancelled()

var available_targets: Array[CharacterData] = []
var selected_index: int = 0

@onready var target_list: VBoxContainer = $Panel/VBoxContainer/TargetList
@onready var confirm_button: Button = $Panel/VBoxContainer/ButtonContainer/ConfirmButton
@onready var cancel_button: Button = $Panel/VBoxContainer/ButtonContainer/CancelButton
@onready var title_label: Label = $Panel/VBoxContainer/TitleLabel

func _ready():
	hide()
	
	if confirm_button:
		confirm_button.pressed.connect(_on_confirm_pressed)
	if cancel_button:
		cancel_button.pressed.connect(_on_cancel_pressed)

func show_target_selection(targets: Array[CharacterData], title: String = "Select Target", auto_confirm: bool = true):
	"""Display target selection UI"""
	available_targets = targets
	selected_index = 0
	
	if title_label:
		title_label.text = title
	
	_populate_target_list()
	show()
	
	#  Only auto-confirm if flag is true AND single target
	if auto_confirm and targets.size() == 1:
		await get_tree().create_timer(0.1).timeout
		_on_confirm_pressed()

func _populate_target_list():
	"""Create target selection buttons"""
	# Clear existing
	if not target_list:
		return
	
	for child in target_list.get_children():
		child.queue_free()
	
	# Create buttons for each target
	for i in range(available_targets.size()):
		var target = available_targets[i]
		var button = Button.new()
		
		var hp_percent = float(target.current_hp) / float(target.max_hp) * 100
		var status_text = ""
		if target.status_manager:
			var effects = target.status_manager.get_effects_string()
			if effects != "Normal":
				status_text = " [%s]" % effects
		
		button.text = "%s - HP: %d/%d (%.0f%%)%s" % [
			target.name,
			target.current_hp,
			target.max_hp,
			hp_percent,
			status_text
		]
		
		button.custom_minimum_size = Vector2(300, 40)
		
		# Color code by HP
		if hp_percent < 25:
			button.modulate = Color(1.0, 0.3, 0.3)
		elif hp_percent < 50:
			button.modulate = Color(1.0, 0.7, 0.3)
		else:
			button.modulate = Color(1.0, 1.0, 1.0)
		
		var target_index = i
		button.pressed.connect(func(): _on_target_button_pressed(target_index))
		
		target_list.add_child(button)
		
		if i == selected_index:
			button.grab_focus()

func _on_target_button_pressed(index: int):
	"""Target button clicked"""
	selected_index = index
	_on_confirm_pressed()

func _on_confirm_pressed():
	"""Confirm target selection"""
	if selected_index >= 0 and selected_index < available_targets.size():
		var target = available_targets[selected_index]
		hide()
		emit_signal("target_selected", target)

func _on_cancel_pressed():
	"""Cancel target selection"""
	hide()
	emit_signal("target_cancelled")

func _input(event):
	"""Keyboard navigation"""
	if not visible:
		return
	
	if event.is_action_pressed("ui_up"):
		selected_index = max(0, selected_index - 1)
		_populate_target_list()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		selected_index = min(available_targets.size() - 1, selected_index + 1)
		_populate_target_list()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_on_confirm_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()
