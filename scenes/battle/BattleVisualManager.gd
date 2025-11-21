# res://scenes/battle/BattleVisualManager.gd
# Manages all visual effects in battle: sprites, animations, camera shake, hit effects

class_name BattleVisualManager
extends Node2D

# Sprite scenes
const GOBLIN_SPRITE = preload("res://scenes/sprites/goblin_sprite.tscn")
const ORC_SPRITE = preload("res://scenes/sprites/orc_sprite.tscn")
const TROLL_SPRITE = preload("res://scenes/sprites/troll_sprite.tscn")
const FAIRY_SPRITE = preload("res://scenes/sprites/fairy_sprite.tscn")

# Animation scenes
const ATTACK_ANIM = preload("res://scenes/animations/attack_animation.tscn")
const MAGIC_ANIM = preload("res://scenes/animations/magic_attack_animation.tscn")

# References
var camera: Camera2D
var player_sprite_container: Node2D
var enemy_sprite_container: Node2D

# Sprite tracking
var player_sprite: Node2D
var enemy_sprites: Dictionary = {}  # CharacterData -> Node2D
var tracked_enemies: Array[CharacterData] = []  # Track which characters are enemies

# Camera shake
var shake_trauma: float = 0.0
var max_trauma: float = 1.0
var trauma_decay: float = 1.0
var shake_power: float = 8.0
var shake_speed: float = 30.0
var camera_offset: Vector2 = Vector2.ZERO

func _ready():
	set_process(true)

func initialize(p_camera: Camera2D, p_player_container: Node2D, p_enemy_container: Node2D):
	"""Initialize with references from battle scene"""
	camera = p_camera
	player_sprite_container = p_player_container
	enemy_sprite_container = p_enemy_container
	print("BattleVisualManager: Initialized")

func setup_player_sprite(player: CharacterData):
	"""Setup player sprite (future: load based on player race/class)"""
	# For now, placeholder - you can add player sprite later
	print("BattleVisualManager: Player sprite setup (placeholder)")

func setup_enemy_sprites(enemies: Array[CharacterData]):
	"""Create and position enemy sprites"""
	# Clear existing sprites
	for child in enemy_sprite_container.get_children():
		child.queue_free()
	enemy_sprites.clear()
	tracked_enemies.clear()
	
	var enemy_count = enemies.size()
	var positions = _calculate_enemy_positions(enemy_count)
	
	for i in range(enemy_count):
		var enemy = enemies[i]
		var sprite = _create_enemy_sprite(enemy)
		
		if sprite:
			enemy_sprite_container.add_child(sprite)
			sprite.position = positions[i]
			sprite.scale = Vector2(2.0, 2.0)  # Scale up 16x16 sprites
			enemy_sprites[enemy] = sprite
			tracked_enemies.append(enemy)  # Track this as an enemy
			print("BattleVisualManager: Created sprite for %s at %v" % [enemy.name, positions[i]])

func _create_enemy_sprite(enemy: CharacterData) -> Node2D:
	"""Instantiate sprite based on enemy race"""
	var race = enemy.race.to_lower()
	
	match race:
		"goblin":
			return GOBLIN_SPRITE.instantiate()
		"orc":
			return ORC_SPRITE.instantiate()
		"troll":
			return TROLL_SPRITE.instantiate()
		"fairy":
			return FAIRY_SPRITE.instantiate()
		_:
			# Default to goblin if unknown
			print("BattleVisualManager: Unknown race '%s', using goblin sprite" % race)
			return GOBLIN_SPRITE.instantiate()

func _calculate_enemy_positions(count: int) -> Array:
	"""Calculate sprite positions based on enemy count"""
	var positions = []
	var base_x = 800.0  # Moved left from 850 by 20px
	var base_y = 200.0  # Vertical center
	
	match count:
		1:
			# Single enemy - center
			positions.append(Vector2(base_x, base_y))
		2:
			# Two enemies - stacked vertically
			positions.append(Vector2(base_x, base_y - 60))
			positions.append(Vector2(base_x, base_y + 60))
		3:
			# Three enemies - triangle formation
			positions.append(Vector2(base_x - 40, base_y - 80))
			positions.append(Vector2(base_x + 40, base_y - 80))
			positions.append(Vector2(base_x, base_y + 40))
		4:
			# Four enemies - square formation
			positions.append(Vector2(base_x - 50, base_y - 70))
			positions.append(Vector2(base_x + 50, base_y - 70))
			positions.append(Vector2(base_x - 50, base_y + 30))
			positions.append(Vector2(base_x + 50, base_y + 30))
		_:
			# Fallback for more enemies
			for i in range(count):
				var offset_y = (i - count / 2.0) * 50
				positions.append(Vector2(base_x, base_y + offset_y))
	
	return positions

# === ATTACK ANIMATIONS ===

func play_attack_animation(attacker: CharacterData, target: CharacterData, is_magic: bool = false):
	"""Play attack animation at single target position"""
	var target_sprite = enemy_sprites.get(target)
	
	# If target has no sprite (player currently), just do attacker lunge
	if not target_sprite:
		print("BattleVisualManager: No sprite for target %s, skipping attack animation" % target.name)
		
		# But if attacker has sprite, make them lunge forward
		var attacker_sprite = enemy_sprites.get(attacker)
		if attacker_sprite:
			await play_lunge_animation(attacker)
		return
	
	# Both have sprites - play full animation
	var anim_scene = MAGIC_ANIM if is_magic else ATTACK_ANIM
	var anim_instance = anim_scene.instantiate()
	
	# Position at target sprite
	target_sprite.add_child(anim_instance)
	anim_instance.position = Vector2.ZERO
	
	# Attacker lunges forward while animation plays
	var attacker_sprite = enemy_sprites.get(attacker)
	if attacker_sprite:
		play_lunge_animation(attacker)
	
	# Play animation
	var animated_sprite = anim_instance.get_node("AnimatedSprite2D")
	if animated_sprite:
		animated_sprite.play("default")
		# Auto-cleanup after animation
		await animated_sprite.animation_finished
		anim_instance.queue_free()

func play_aoe_attack_animation(attacker: CharacterData, targets: Array[CharacterData], is_magic: bool = true):
	"""Play magic animation on multiple targets simultaneously"""
	var anim_scene = MAGIC_ANIM if is_magic else ATTACK_ANIM
	var anim_instances = []
	
	# Create animation on each target that has a sprite
	for target in targets:
		var target_sprite = enemy_sprites.get(target)
		if target_sprite:
			var anim_instance = anim_scene.instantiate()
			target_sprite.add_child(anim_instance)
			anim_instance.position = Vector2.ZERO
			anim_instances.append(anim_instance)
	
	# If no sprites, just return
	if anim_instances.is_empty():
		print("BattleVisualManager: No sprites for AOE targets, skipping animations")
		return
	
	# Play all animations simultaneously
	for anim_instance in anim_instances:
		var animated_sprite = anim_instance.get_node("AnimatedSprite2D")
		if animated_sprite:
			animated_sprite.play("default")
	
	# Wait for first animation to finish (they all finish together)
	if anim_instances.size() > 0:
		var first_anim = anim_instances[0].get_node("AnimatedSprite2D")
		if first_anim:
			await first_anim.animation_finished
	
	# Cleanup all instances
	for anim_instance in anim_instances:
		anim_instance.queue_free()

func play_lunge_animation(character: CharacterData):
	"""Make character sprite lunge forward when attacking"""
	var sprite = enemy_sprites.get(character)
	
	if not sprite:
		return
	
	var original_pos = sprite.position
	var lunge_distance = 30.0  # pixels forward
	
	# Determine lunge direction (towards player = left, towards enemy = right)
	var is_enemy = character in tracked_enemies
	var lunge_offset = Vector2(-lunge_distance, 0) if is_enemy else Vector2(lunge_distance, 0)
	
	# Tween forward and back
	var tween = create_tween()
	tween.tween_property(sprite, "position", original_pos + lunge_offset, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "position", original_pos, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	await tween.finished

func play_dodge_animation(character: CharacterData):
	"""Make character sprite jump back when dodging"""
	var sprite = enemy_sprites.get(character)
	
	if not sprite:
		print("BattleVisualManager: No sprite for %s, skipping dodge animation" % character.name)
		return
	
	var original_pos = sprite.position
	var dodge_distance = 25.0  # pixels back
	
	# Determine dodge direction (enemies dodge right, player dodges left)
	var is_enemy = character in tracked_enemies
	var dodge_offset = Vector2(dodge_distance, 0) if is_enemy else Vector2(-dodge_distance, 0)
	
	# Quick jump back and return
	var tween = create_tween()
	tween.tween_property(sprite, "position", original_pos + dodge_offset, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "position", original_pos, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	await tween.finished

# === HIT EFFECTS ===

func flash_sprite_hit(character: CharacterData, is_critical: bool = false):
	"""Flash sprite red when hit (enemies only for now)"""
	var sprite = enemy_sprites.get(character)
	
	# If no sprite (player currently), just do screen shake
	if not sprite:
		print("BattleVisualManager: No sprite for %s, skipping hit flash" % character.name)
		return
	
	var sprite_node = sprite.get_node_or_null("Sprite2D")
	if not sprite_node:
		return
	
	# Flash red (brighter for crits)
	var flash_color = Color(2.0, 0.5, 0.5) if is_critical else Color(1.5, 0.5, 0.5)
	sprite_node.modulate = flash_color
	
	# Tween back to normal
	var tween = create_tween()
	tween.tween_property(sprite_node, "modulate", Color.WHITE, 0.3)

func play_death_animation(character: CharacterData):
	"""Fade out sprite on death"""
	var sprite = enemy_sprites.get(character)
	
	if not sprite:
		return
	
	var sprite_node = sprite.get_node_or_null("Sprite2D")
	if not sprite_node:
		return
	
	# Fade out and tint gray
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite_node, "modulate", Color(0.5, 0.5, 0.5, 0.0), 0.8)
	tween.tween_property(sprite, "scale", Vector2(2.5, 2.5), 0.8)
	
	await tween.finished
	
	# Hide sprite but keep node (for combat log reference)
	sprite.visible = false

# === CAMERA SHAKE ===

func add_trauma(amount: float):
	"""Add screen shake trauma (0.0 to 1.0)"""
	shake_trauma = min(shake_trauma + amount, max_trauma)

func shake_on_hit(damage: int, is_critical: bool = false):
	"""Trigger screen shake based on hit"""
	var base_trauma = min(damage / 100.0, 0.5)
	
	if is_critical:
		base_trauma *= 1.5
	
	add_trauma(base_trauma)

func shake_and_flash_screen(duration: float = 0.15):
	"""Screen shake + white flash overlay for player getting hit"""
	# Add significant trauma for player hit
	add_trauma(0.6)
	
	# Create full-screen white flash
	if not camera:
		return
	
	var flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0.4)  # White with 40% opacity
	flash.size = Vector2(1184, 624)  # Full screen size
	flash.position = Vector2.ZERO
	
	# Add to camera so it moves with camera offset
	camera.add_child(flash)
	
	# Fade out the flash
	var tween = create_tween()
	tween.tween_property(flash, "color:a", 0.0, duration)
	
	await tween.finished
	flash.queue_free()

func shake_on_death():
	"""Trigger screen shake on enemy death"""
	add_trauma(0.4)

func _process(delta: float):
	"""Update camera shake"""
	if shake_trauma > 0:
		shake_trauma = max(shake_trauma - trauma_decay * delta, 0)
		_apply_shake()
	elif camera and camera_offset != Vector2.ZERO:
		camera.offset = Vector2.ZERO
		camera_offset = Vector2.ZERO

func _apply_shake():
	"""Apply shake offset to camera"""
	if not camera:
		return
	
	var shake_amount = pow(shake_trauma, 2)
	
	var offset_x = shake_power * shake_amount * randf_range(-1, 1)
	var offset_y = shake_power * shake_amount * randf_range(-1, 1)
	
	camera_offset = Vector2(offset_x, offset_y)
	camera.offset = camera_offset

# === UTILITY ===

func get_sprite_position(character: CharacterData) -> Vector2:
	"""Get world position of character sprite"""
	var sprite = enemy_sprites.get(character)
	if sprite:
		return sprite.global_position
	return Vector2.ZERO

func cleanup():
	"""Clean up all visual effects"""
	for child in enemy_sprite_container.get_children():
		child.queue_free()
	enemy_sprites.clear()
	tracked_enemies.clear()
	shake_trauma = 0.0
	camera_offset = Vector2.ZERO
