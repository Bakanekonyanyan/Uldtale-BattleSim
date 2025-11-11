# BattleCompleteDialog.gd
# This replaces immediate transition to RewardScene
extends Control

signal press_on_selected
signal take_breather_selected

@onready var victory_label = $Panel/VBoxContainer/VictoryLabel
@onready var xp_label = $Panel/VBoxContainer/XPLabel
@onready var momentum_label = $Panel/VBoxContainer/MomentumLabel
@onready var press_on_button = $Panel/VBoxContainer/PressOnButton
@onready var breather_button = $Panel/VBoxContainer/TakeBreatherButton
@onready var status_label = $Panel/VBoxContainer/StatusLabel
@onready var warning_label = $Panel/VBoxContainer/WarningLabel

var xp_gained: int = 0
var player_character: CharacterData

func _ready():
	press_on_button.connect("pressed", Callable(self, "_on_press_on"))
	breather_button.connect("pressed", Callable(self, "_on_breather"))
	
	# Hide by default
	hide()

func show_dialog(character: CharacterData, xp: int):
	player_character = character
	xp_gained = xp
	
	# Update labels
	victory_label.text = "Victory!"
	xp_label.text = "+%d XP" % xp_gained
	
	var momentum_level = MomentumSystem.get_momentum()
	var momentum_text = MomentumSystem.get_momentum_status()
	momentum_label.text = momentum_text
	
	# Show status warnings
	var warnings = []
	if character.current_hp < character.max_hp * 0.5:
		warnings.append("Low HP: %d/%d" % [character.current_hp, character.max_hp])
	if character.current_mp < character.max_mp * 0.3:
		warnings.append("Low MP: %d/%d" % [character.current_mp, character.max_mp])
	if character.current_sp < character.max_sp * 0.3:
		warnings.append("Low SP: %d/%d" % [character.current_sp, character.max_sp])
	if not character.status_effects.is_empty():
		warnings.append("Active Status Effects: %s" % character.get_status_effects_string())
	
	if warnings.is_empty():
		status_label.text = "You're in good condition!"
		warning_label.text = ""
	else:
		status_label.text = "Current Status:"
		warning_label.text = "\n".join(warnings)
	
	# Show bonus notification for momentum 3
	if MomentumSystem.should_show_bonus_notification():
		var bonus_popup = AcceptDialog.new()
		bonus_popup.dialog_text = "Momentum Bonus Unlocked!\n\nYou've reached Momentum x3!\nIncreased drop rates and rarity chances are now active."
		bonus_popup.title = "Momentum Bonus!"
		add_child(bonus_popup)
		bonus_popup.popup_centered()
	
	show()

func _on_press_on():
	# Player gains momentum, no reward screen, no recovery
	emit_signal("press_on_selected")
	queue_free()

func _on_breather():
	# Reset momentum, show rewards, full recovery
	emit_signal("take_breather_selected")
	queue_free()
