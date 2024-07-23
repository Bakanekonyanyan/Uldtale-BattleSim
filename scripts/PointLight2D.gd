extends PointLight2D

@export var min_energy: float = 0.5
@export var max_energy: float = 1.5
@export var base_pulse_duration: float = 2.0
@export var randomness: float = 0.2  # How much to randomize the pulse duration
@export var auto_start: bool = true  # Should it start pulsing automatically?

var tween: Tween
var is_pulsing: bool = false

func _ready():
	if auto_start:
		start_pulsing()

func start_pulsing():
	if is_pulsing:
		return
	
	is_pulsing = true
	_create_new_tween()

func stop_pulsing():
	if tween:
		tween.kill()
	is_pulsing = false
	# Optional: reset to mid-point energy when stopping
	energy = (min_energy + max_energy) / 2

func _create_new_tween():
	if tween:
		tween.kill()
	
	tween = create_tween()
	tween.connect("finished", Callable(self, "_on_tween_completed"))
	
	var random_duration = base_pulse_duration * (1 + randf_range(-randomness, randomness))
	tween.tween_property(self, "energy", max_energy, random_duration / 2).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "energy", min_energy, random_duration / 2).set_trans(Tween.TRANS_SINE)

func _on_tween_completed():
	if is_pulsing:
		_create_new_tween()

# Optional: Methods to control pulsing from other scripts
func toggle_pulsing():
	if is_pulsing:
		stop_pulsing()
	else:
		start_pulsing()

func set_energy_range(new_min: float, new_max: float):
	min_energy = new_min
	max_energy = new_max
	if is_pulsing:
		_create_new_tween()  # Restart the tween with new values
