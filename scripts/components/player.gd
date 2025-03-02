extends CharacterBody3D

#region Public
# Movement constants
const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const ATTACK_RANGE = 2.0
const ATTACK_COOLDOWN = 0.4
const MOUSE_SENSITIVITY = 0.002
#endregion

#region Godot API
func _ready() -> void:
	# Connect to game manager
	GameManager.player_hit.connect(_on_player_hit)
	
	# Capture mouse
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event: InputEvent) -> void:
	# Handle camera rotation with mouse
	if event is InputEventMouseMotion:
		# Horizontal player rotation
		_player_rotation_y -= event.relative.x * MOUSE_SENSITIVITY
		rotate_y(event.relative.x * MOUSE_SENSITIVITY)
		
		# Vertical camera rotation (limited)
		_camera_rotation_x -= event.relative.y * MOUSE_SENSITIVITY
		_camera_rotation_x = clamp(_camera_rotation_x, -PI/2, PI/2)
		_camera_pivot.rotation.x = _camera_rotation_x
	
	# Exit mouse capture mode with Escape
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta: float) -> void:
	# Apply knockback
	if _knockback_vector.length() > 0.1:
		velocity += _knockback_vector * delta
		_knockback_vector = _knockback_vector.lerp(Vector3.ZERO, delta * 5)
	
	# Add gravity
	if not is_on_floor():
		velocity += GameManager.get_gravity() * delta

	# Handle jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get input direction for strafing
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	
	# Create direction vector relative to player orientation (strafing)
	var direction = Vector3.ZERO
	direction = Vector3(input_dir.x, 0, input_dir.y).rotated(Vector3.UP, _player_rotation_y).normalized()
	
	# Don't allow movement during attack
	if _is_attacking:
		direction = direction * 0.3  # Reduce speed during attack
	
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	# Handle attack
	if Input.is_action_just_pressed("attack") and _can_attack:
		attack()

	move_and_slide()
#endregion

#region Main API
func attack() -> void:
	_can_attack = false
	_is_attacking = true
	
	# Play attack animation
	if _animation_player.has_animation("attack"):
		_animation_player.play("attack")
	
	# Play attack sound
	if AudioManager.has_method("play_attack_swing"):
		AudioManager.play_attack_swing(global_position)
	
	# Check enemies in attack area
	var enemies_in_range = _get_enemies_in_attack_range()
	for enemy in enemies_in_range:
		if enemy.has_method("take_damage"):
			# Apply damage to enemy
			enemy.take_damage(GameManager.player_attack_power)
			
			# Apply knockback force to enemy
			var knockback_direction = (enemy.global_position - global_position).normalized()
			knockback_direction.y = 0.5  # Add small vertical component to knockback
			
			if enemy.has_method("apply_knockback"):
				enemy.apply_knockback(knockback_direction * 10.0)
	
	# Reset state after delay
	await get_tree().create_timer(ATTACK_COOLDOWN).timeout
	_is_attacking = false
	_can_attack = true

func apply_knockback(direction: Vector3, force: float = 5.0) -> void:
	# Reduce force based on knockback resistance
	_knockback_vector = direction * force * (1.0 - _knockback_resistance)
#endregion

#region Private
# Child nodes (to be added in editor)
@onready var _attack_area: Area3D = $AttackArea
@onready var _animation_player: AnimationPlayer = $AnimationPlayer
@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _camera: Camera3D = $CameraPivot/Camera3D
@onready var _weapon_pivot: Node3D = $WeaponPivot

# State variables
var _can_attack: bool = true
var _is_attacking: bool = false
var _knockback_vector: Vector3 = Vector3.ZERO
var _knockback_resistance: float = 0.8
var _camera_rotation_x: float = 0.0
var _player_rotation_y: float = 0.0

func _get_enemies_in_attack_range() -> Array:
	var enemies = []
	
	# Attack direction based on camera orientation
	var attack_direction = -_camera_pivot.global_transform.basis.z.normalized()
	
	# If using Area3D for detection
	if _attack_area:
		# Reposition attack area in front of player, in camera direction
		_attack_area.global_position = global_position + attack_direction * 2.0
		
		var bodies = _attack_area.get_overlapping_bodies()
		for body in bodies:
			if body.is_in_group("enemies"):
				enemies.append(body)
	else:
		# Ray-based detection
		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.new()
		
		query.from = global_position + Vector3(0, 1.0, 0)  # Start at eye level
		query.to = query.from + attack_direction * ATTACK_RANGE
		query.exclude = [self]
		query.collision_mask = 0b00000010  # Enemy collision layer
		
		var result = space_state.intersect_ray(query)
		if result and result.collider.is_in_group("enemies"):
			enemies.append(result.collider)
	
	return enemies

func _on_player_hit(damage_amount: float) -> void:
	# Damage animation or visual effect
	if _animation_player.has_animation("take_hit"):
		_animation_player.play("take_hit")
	
	# Visual feedback (flash, camera shake, etc.)
	if _camera:
		var shake_intensity = min(damage_amount / 10.0, 0.5)
		_shake_camera(shake_intensity)

func _shake_camera(intensity: float, duration: float = 0.2) -> void:
	if _camera:
		var initial_position = _camera.position
		
		# Simple shake animation
		for i in range(10):
			var rand_offset = Vector3(
				randf_range(-intensity, intensity),
				randf_range(-intensity, intensity),
				0
			)
			_camera.position = initial_position + rand_offset
			await get_tree().create_timer(duration / 10.0).timeout
		
		# Return to initial position
		_camera.position = initial_position
#endregion
