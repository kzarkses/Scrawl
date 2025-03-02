extends CharacterBody3D

#region Public
# Unique enemy identification
@export var m_enemy_id: int = 0
@export var m_enemy_type: String = "basic"

# Statistics
@export var m_max_health: float = 50.0
@export var m_attack_power: float = 5.0
@export var m_movement_speed: float = 3.0
@export var m_detection_range: float = 10.0
@export var m_attack_range: float = 1.5
@export var m_attack_cooldown: float = 1.2

# Physics
@export var m_mass: float = 2.0
@export var m_knockback_resistance: float = 0.3
#endregion

#region Godot API
func _ready() -> void:
	# Initialize health
	_health = m_max_health
	_initial_position = global_position
	
	# Register with the game manager
	GameManager.register_enemy(self, m_enemy_id)
	GameManager.enemy_hit.connect(_on_enemy_hit)
	
	# Configure detection zones
	if _detection_area:
		_detection_area.body_entered.connect(_on_detection_area_body_entered)
		_detection_area.body_exited.connect(_on_detection_area_body_exited)
	
	if _attack_area:
		_attack_area.body_entered.connect(_on_attack_area_body_entered)

func _physics_process(delta: float) -> void:
	# Apply gravity
	if not is_on_floor():
		velocity += GameManager.get_gravity() * delta
	
	# Apply knockback
	if _knockback_vector.length() > 0.1:
		velocity += _knockback_vector * delta
		_knockback_vector = _knockback_vector.lerp(Vector3.ZERO, delta * 5)
	
	# Movement logic based on state
	if _is_stunned:
		# When stunned, enemy can only be affected by physics
		pass
	elif _player_detected and _player_node:
		_follow_player(delta)
	else:
		_patrol(delta)
	
	move_and_slide()
#endregion

#region Main API
func take_damage(amount: float) -> void:
	_health -= amount
	
	# Visual feedback
	if _animation_player and _animation_player.has_animation("hit"):
		_animation_player.play("hit")
	
	if _health <= 0:
		die()
	else:
		# Brief stun
		_is_stunned = true
		await get_tree().create_timer(0.5).timeout
		_is_stunned = false

func apply_knockback(direction: Vector3, force: float = 5.0) -> void:
	# Reduce force based on knockback resistance
	_knockback_vector = direction * force * (1.0 - m_knockback_resistance)

func die() -> void:
	# Death animation
	if _animation_player and _animation_player.has_animation("die"):
		_animation_player.play("die")
		await _animation_player.animation_finished
	
	# Activate ragdoll if available
	if _ragdoll:
		_activate_ragdoll()
		
		# Wait a bit before unregistering
		await get_tree().create_timer(3.0).timeout
	
	# Unregister from game manager
	GameManager.unregister_enemy(m_enemy_id)
	
	# Destruction
	queue_free()
#endregion

#region Private
# Child nodes
@onready var _animation_player: AnimationPlayer = $AnimationPlayer
@onready var _detection_area: Area3D = $DetectionArea
@onready var _attack_area: Area3D = $AttackArea
@onready var _ragdoll: Node3D = $Ragdoll  # Optional for advanced physics effects

# State variables
var _health: float
var _player_detected: bool = false
var _player_node: Node3D = null
var _can_attack: bool = true
var _is_attacking: bool = false
var _is_stunned: bool = false
var _knockback_vector: Vector3 = Vector3.ZERO
var _initial_position: Vector3
var _patrol_points: Array = []
var _current_patrol_index: int = 0

func _follow_player(delta: float) -> void:
	if _player_node:
		var direction_to_player = (_player_node.global_position - global_position).normalized()
		direction_to_player.y = 0  # Keep enemy on ground
		
		var distance_to_player = global_position.distance_to(_player_node.global_position)
		
		# If close enough to attack
		if distance_to_player <= m_attack_range:
			if _can_attack and not _is_attacking:
				attack()
			# Stop at attack range
			velocity.x = move_toward(velocity.x, 0, m_movement_speed)
			velocity.z = move_toward(velocity.z, 0, m_movement_speed)
		else:
			# Move toward player
			velocity.x = direction_to_player.x * m_movement_speed
			velocity.z = direction_to_player.z * m_movement_speed
			
			# Rotate toward player
			look_at(Vector3(_player_node.global_position.x, global_position.y, _player_node.global_position.z), Vector3.UP)

func _patrol(delta: float) -> void:
	if _patrol_points.size() > 0:
		# Follow patrol points
		var target = _patrol_points[_current_patrol_index]
		var direction = (target - global_position).normalized()
		direction.y = 0
		
		velocity.x = direction.x * (m_movement_speed * 0.7)  # Reduced speed when patrolling
		velocity.z = direction.z * (m_movement_speed * 0.7)
		
		# Rotate toward movement direction
		if direction.length() > 0.1:
			look_at(Vector3(global_position.x + direction.x, global_position.y, global_position.z + direction.z), Vector3.UP)
		
		# Check if patrol point reached
		if global_position.distance_to(Vector3(target.x, global_position.y, target.z)) < 0.5:
			_current_patrol_index = (_current_patrol_index + 1) % _patrol_points.size()
	else:
		# Return to initial position if no patrol points
		var direction = (_initial_position - global_position).normalized()
		direction.y = 0
		
		if global_position.distance_to(Vector3(_initial_position.x, global_position.y, _initial_position.z)) > 0.5:
			velocity.x = direction.x * (m_movement_speed * 0.5)
			velocity.z = direction.z * (m_movement_speed * 0.5)
			
			# Rotate toward movement direction
			if direction.length() > 0.1:
				look_at(Vector3(global_position.x + direction.x, global_position.y, global_position.z + direction.z), Vector3.UP)
		else:
			velocity.x = move_toward(velocity.x, 0, m_movement_speed)
			velocity.z = move_toward(velocity.z, 0, m_movement_speed)

func attack() -> void:
	_is_attacking = true
	_can_attack = false
	
	# Play attack animation
	if _animation_player and _animation_player.has_animation("attack"):
		_animation_player.play("attack")
	
	# Wait for animation to reach impact moment
	await get_tree().create_timer(0.3).timeout
	
	# Check if player is still in range
	var bodies = _attack_area.get_overlapping_bodies()
	for body in bodies:
		if body == _player_node:
			GameManager.damage_player(m_attack_power)
			
			# Apply knockback to player
			if _player_node.has_method("apply_knockback"):
				var knockback_dir = (_player_node.global_position - global_position).normalized()
				_player_node.apply_knockback(knockback_dir * 3.0)
	
	# Recovery after attack
	await get_tree().create_timer(m_attack_cooldown).timeout
	_is_attacking = false
	_can_attack = true

func _activate_ragdoll() -> void:
	# If you have a ragdoll system
	if _ragdoll:
		# Disable main collider
		$CollisionShape3D.disabled = true
		
		# Activate ragdoll physics bodies
		for child in _ragdoll.get_children():
			if child is RigidBody3D:
				child.freeze = false
				
				# Apply last movement force
				if child.has_method("apply_central_impulse"):
					child.apply_central_impulse(velocity * m_mass)

func _on_detection_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_detected = true
		_player_node = body

func _on_detection_area_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_detected = false
		# Keep reference to player to be able to pursue
		# but stop following after a certain time
		await get_tree().create_timer(5.0).timeout
		if not _player_detected:
			_player_node = null

func _on_attack_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and _can_attack:
		attack()

func _on_enemy_hit(hit_enemy_id: int, damage_amount: float) -> void:
	if hit_enemy_id == m_enemy_id:
		take_damage(damage_amount)
#endregion
