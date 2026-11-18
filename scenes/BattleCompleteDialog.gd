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
	
	# Spell out what each choice does
	var next_level = mini(momentum_level + 1, MomentumSystem.MAX_MOMENTUM)
	var banked_gold = int(MomentumSystem.momentum_loot_accumulated.currency)
	var banked_items = MomentumSystem.momentum_loot_accumulated.equipment_instances.size() + MomentumSystem.momentum_loot_accumulated.items.size()
	press_on_button.text = "Press On\nMomentum x%d: +%d%% damage, next Breather pays +%d%%. No rest - and banked loot is lost if you fall." % [
		next_level, int(round(next_level * MomentumSystem.DAMAGE_BONUS_PER_LEVEL * 100)), int(round(MomentumSystem.get_reward_bonus(next_level) * 100))]
	var payout = "this wave"
	if banked_gold > 0 or banked_items > 0:
		payout = "this wave + %s and %d item stack%s banked" % [Currency.format_copper(banked_gold), banked_items, "" if banked_items == 1 else "s"]
	breather_button.text = "Take a Breather\nCollect %s%s. Rest and recover; momentum resets." % [
		payout, " (+%d%% bonus)" % int(round(MomentumSystem.get_reward_bonus() * 100)) if MomentumSystem.has_momentum_bonus() else ""]
	for b in [press_on_button, breather_button]:
		b.autowrap_mode = TextServer.AUTOWRAP_WORD
	
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
	
	# Notify once when the reward bonus hits its cap
	if MomentumSystem.should_show_bonus_notification():
		var bonus_popup = AcceptDialog.new()
		bonus_popup.dialog_text = "Maximum Momentum Bonus!\n\nMomentum x%d: your next Breather pays out everything you've banked with +%d%% rewards.\nPressing on still raises your damage - and the danger." % [
			MomentumSystem.get_momentum(), int(MomentumSystem.MAX_REWARD_BONUS * 100)]
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
