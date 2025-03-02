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
	_health = m_max_health
	_initial_position = global_position
	
	GameManager.register_enemy(self, m_enemy_id)
	GameManager.enemy_hit.connect(_on_enemy_hit)
	
	if _detection_area:
		_detection_area.body_entered.connect(_on_detection_area_body_entered)
		_detection_area.body_exited.connect(_on_detection_area_body_exited)
	
	if _attack_area:
		_attack_area.body_entered.connect(_on_attack_area_body_entered)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += GameManager.get_gravity() * delta
	
	if _knockback_vector.length() > 0.1:
		velocity += _knockback_vector * delta
		_knockback_vector = _knockback_vector.lerp(Vector3.ZERO, delta * 5)
	
	if _is_stunned:
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
	
	if _animation_player and _animation_player.has_animation("hit"):
		_animation_player.play("hit")
	
	if _health <= 0:
		die()
	else:
		_is_stunned = true
		await get_tree().create_timer(0.5).timeout
		_is_stunned = false

func apply_knockback(direction: Vector3, force: float = 5.0) -> void:
	_knockback_vector = direction * force * (1.0 - m_knockback_resistance)

func die() -> void:
	if _animation_player and _animation_player.has_animation("die"):
		_animation_player.play("die")
		await _animation_player.animation_finished
	
	if _ragdoll:
		_activate_ragdoll()
		
		await get_tree().create_timer(3.0).timeout
	
	GameManager.unregister_enemy(m_enemy_id)
	
	queue_free()
#endregion


#region Private
# Child nodes
@onready var _animation_player: AnimationPlayer = $AnimationPlayer
@onready var _detection_area: Area3D = $DetectionArea
@onready var _attack_area: Area3D = $AttackArea
@onready var _ragdoll: Node3D = $Ragdoll

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
#endregion


#region Private API
func _follow_player(delta: float) -> void:
	if _player_node:
		var direction_to_player = (_player_node.global_position - global_position).normalized()
		direction_to_player.y = 0
		
		var distance_to_player = global_position.distance_to(_player_node.global_position)
		
		if distance_to_player <= m_attack_range:
			if _can_attack and not _is_attacking:
				attack()
			velocity.x = move_toward(velocity.x, 0, m_movement_speed)
			velocity.z = move_toward(velocity.z, 0, m_movement_speed)
		else:
			velocity.x = direction_to_player.x * m_movement_speed
			velocity.z = direction_to_player.z * m_movement_speed
			
			look_at(Vector3(_player_node.global_position.x, global_position.y, _player_node.global_position.z), Vector3.UP)

func _patrol(delta: float) -> void:
	if _patrol_points.size() > 0:
		var target = _patrol_points[_current_patrol_index]
		var direction = (target - global_position).normalized()
		direction.y = 0
		
		velocity.x = direction.x * (m_movement_speed * 0.7)
		velocity.z = direction.z * (m_movement_speed * 0.7)
		
		if direction.length() > 0.1:
			look_at(Vector3(global_position.x + direction.x, global_position.y, global_position.z + direction.z), Vector3.UP)
		
		if global_position.distance_to(Vector3(target.x, global_position.y, target.z)) < 0.5:
			_current_patrol_index = (_current_patrol_index + 1) % _patrol_points.size()
	else:
		var direction = (_initial_position - global_position).normalized()
		direction.y = 0
		
		if global_position.distance_to(Vector3(_initial_position.x, global_position.y, _initial_position.z)) > 0.5:
			velocity.x = direction.x * (m_movement_speed * 0.5)
			velocity.z = direction.z * (m_movement_speed * 0.5)
			
			if direction.length() > 0.1:
				look_at(Vector3(global_position.x + direction.x, global_position.y, global_position.z + direction.z), Vector3.UP)
		else:
			velocity.x = move_toward(velocity.x, 0, m_movement_speed)
			velocity.z = move_toward(velocity.z, 0, m_movement_speed)

func attack() -> void:
	_is_attacking = true
	_can_attack = false
	
	if _animation_player and _animation_player.has_animation("attack"):
		_animation_player.play("attack")
	
	await get_tree().create_timer(0.3).timeout
	
	var bodies = _attack_area.get_overlapping_bodies()
	for body in bodies:
		if body == _player_node:
			GameManager.damage_player(m_attack_power)
			
			if _player_node.has_method("apply_knockback"):
				var knockback_dir = (_player_node.global_position - global_position).normalized()
				_player_node.apply_knockback(knockback_dir * 3.0)
	
	await get_tree().create_timer(m_attack_cooldown).timeout
	_is_attacking = false
	_can_attack = true

func _activate_ragdoll() -> void:
	if _ragdoll:
		$CollisionShape3D.disabled = true
		
		for child in _ragdoll.get_children():
			if child is RigidBody3D:
				child.freeze = false
				
				if child.has_method("apply_central_impulse"):
					child.apply_central_impulse(velocity * m_mass)

func _on_detection_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_detected = true
		_player_node = body

func _on_detection_area_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_detected = false
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
