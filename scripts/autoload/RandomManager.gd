extends Node

@export var seed: int = 0:
	set(value):
		seed = value
		_init_rng(seed)

var rng: RandomNumberGenerator

func _ready():
	if seed == 0:
		seed = int(Time.get_unix_time_from_system())
	_init_rng(seed)

func new_game_seed() -> int:
	var s = int(Time.get_unix_time_from_system()) ^ Time.get_ticks_msec() ^ get_instance_id()
	seed = s
	_init_rng(seed)
	return s

func _init_rng(s: int) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = s

func _ensure_rng() -> void:
	"""Lazy initialize RNG if not ready"""
	if rng == null:
		if seed == 0:
			seed = int(Time.get_unix_time_from_system())
		_init_rng(seed)

# === Public Functions ===

func randf() -> float:
	_ensure_rng()
	return rng.randf()

func randf_range(a: float, b: float) -> float:
	_ensure_rng()
	return rng.randf_range(a, b)

func randi() -> int:
	_ensure_rng()
	return rng.randi()

func randi_range(a: int, b: int) -> int:
	_ensure_rng()
	return rng.randi_range(a, b)

func chance(p: float) -> bool:
	_ensure_rng()
	return rng.randf() < p

func pick_weighted(weights: Array) -> int:
	_ensure_rng()
	var total := 0.0
	for w in weights:
		total += float(w)
	
	var r = rng.randf() * total
	var accum := 0.0
	
	for i in weights.size():
		accum += weights[i]
		if r < accum:
			return i
	
	return weights.size() - 1
