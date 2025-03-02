extends CharacterBody3D

#region Public
# Movement constants
@export var m_speed: float = 5.0
@export var m_jump_velocity: float = 4.5
@export var m_attack_range: float = 2.0
@export var m_attack_cooldown: float = 0.4
@export var m_mouse_sensitivity: float = 0.002
#endregion


#region Godot API
func _ready() -> void:
	GameManager.player_hit.connect(_on_player_hit)
	
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_player_rotation_y -= event.relative.x * m_mouse_sensitivity
		rotate_y(-event.relative.x * m_mouse_sensitivity)
		
		_camera_rotation_x -= event.relative.y * m_mouse_sensitivity
		_camera_rotation_x = clamp(_camera_rotation_x, -PI/2, PI/2)
		_camera_pivot.rotation.x = _camera_rotation_x
	
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta: float) -> void:
	if _knockback_vector.length() > 0.1:
		velocity += _knockback_vector * delta
		_knockback_vector = _knockback_vector.lerp(Vector3.ZERO, delta * 5)
	
	if not is_on_floor():
		velocity += GameManager.get_gravity() * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = m_jump_velocity

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	
	var direction = Vector3.ZERO
	var forward = global_transform.basis.z
	forward.y = 0
	forward = forward.normalized()
	
	var right = global_transform.basis.x.normalized()
	
	direction = (forward * -input_dir.y + right * input_dir.x).normalized()
	
	if _is_attacking:
		direction = direction * 0.3
	
	if direction:
		velocity.x = direction.x * m_speed
		velocity.z = direction.z * m_speed
	else:
		velocity.x = move_toward(velocity.x, 0, m_speed)
		velocity.z = move_toward(velocity.z, 0, m_speed)

	if Input.is_action_just_pressed("attack") and _can_attack:
		attack()

	move_and_slide()
#endregion


#region Main API
func attack() -> void:
	_can_attack = false
	_is_attacking = true
	
	if _animation_player.has_animation("attack"):
		_animation_player.play("attack")
	
	if AudioManager.has_method("play_attack_swing"):
		AudioManager.play_attack_swing(global_position)
	
	var enemies_in_range = _get_enemies_in_attack_range()
	for enemy in enemies_in_range:
		if enemy.has_method("take_damage"):
			enemy.take_damage(GameManager.player_attack_power)
			
			var knockback_direction = (enemy.global_position - global_position).normalized()
			knockback_direction.y = 0.5
			
			if enemy.has_method("apply_knockback"):
				enemy.apply_knockback(knockback_direction * 10.0)
	
	await get_tree().create_timer(m_attack_cooldown).timeout
	_is_attacking = false
	_can_attack = true

func apply_knockback(direction: Vector3, force: float = 5.0) -> void:
	_knockback_vector = direction * force * (1.0 - _knockback_resistance)
#endregion


#region Private
# Child nodes
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
#endregion


#region Private API
func _get_enemies_in_attack_range() -> Array:
	var enemies = []
	
	var attack_direction = -_camera_pivot.global_transform.basis.z.normalized()
	
	if _attack_area:
		_attack_area.global_position = global_position + attack_direction * 2.0
		
		var bodies = _attack_area.get_overlapping_bodies()
		for body in bodies:
			if body.is_in_group("enemies"):
				enemies.append(body)
	else:
		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.new()
		
		query.from = global_position + Vector3(0, 1.0, 0)
		query.to = query.from + attack_direction * m_attack_range
		query.exclude = [self]
		query.collision_mask = 0b00000010
		
		var result = space_state.intersect_ray(query)
		if result and result.collider.is_in_group("enemies"):
			enemies.append(result.collider)
	
	return enemies

func _on_player_hit(damage_amount: float) -> void:
	if _animation_player.has_animation("take_hit"):
		_animation_player.play("take_hit")
	
	if _camera:
		var shake_intensity = min(damage_amount / 10.0, 0.5)
		_shake_camera(shake_intensity)

func _shake_camera(intensity: float, duration: float = 0.2) -> void:
	if _camera:
		var initial_position = _camera.position
		
		for i in range(10):
			var rand_offset = Vector3(
				randf_range(-intensity, intensity),
				randf_range(-intensity, intensity),
				0
			)
			_camera.position = initial_position + rand_offset
			await get_tree().create_timer(duration / 10.0).timeout
		
		_camera.position = initial_position
#endregion
