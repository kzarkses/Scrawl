extends Node

#region Public
# Combat system signals
signal player_hit(damage_amount: float)
signal enemy_hit(enemy_id: int, damage_amount: float)

# Global game variables
var player_health: float = 100.0
var player_max_health: float = 100.0
var player_attack_power: float = 10.0
var player_defense: float = 5.0

# Physics constants
const GRAVITY: float = 9.8
const IMPACT_FORCE_MULTIPLIER: float = 2.0  # For knockback on impacts
#endregion

#region Godot API
func _ready() -> void:
	# Initialize everything needed at startup
	print("Game Manager initialized")
#endregion

#region Main API
func get_gravity() -> Vector3:
	return Vector3(0, -GRAVITY, 0)

func damage_player(amount: float) -> void:
	var actual_damage = max(1, amount - (player_defense * 0.5))
	player_health -= actual_damage
	emit_signal("player_hit", actual_damage)
	
	if player_health <= 0:
		game_over()

func damage_enemy(enemy_id: int, amount: float) -> void:
	if enemy_id in _active_enemies:
		# Get enemy and apply damage
		var enemy = _active_enemies[enemy_id]
		var actual_damage = max(1, amount)
		
		# Trigger signal so enemy can react
		emit_signal("enemy_hit", enemy_id, actual_damage)
		
		# Increase combo
		increase_combo()

func register_enemy(enemy_node: Node, enemy_id: int) -> void:
	_active_enemies[enemy_id] = enemy_node

func unregister_enemy(enemy_id: int) -> void:
	if enemy_id in _active_enemies:
		_active_enemies.erase(enemy_id)

func increase_combo() -> void:
	_combo_multiplier += 1
	_score += 10 * _combo_multiplier
	
	# Reset combo after a certain time
	reset_combo_after_delay(3.0)

func reset_combo_after_delay(delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	_combo_multiplier = 1

func game_over() -> void:
	print("Game Over!")
	# Implement game over logic here
	
func restart_game() -> void:
	# Reset values
	player_health = player_max_health
	_score = 0
	_combo_multiplier = 1
	_active_enemies.clear()
	
	# Restart scene or load initial level
	# get_tree().reload_current_scene()
#endregion

#region Private
# List of active enemies
var _active_enemies: Dictionary = {}

# Score system
var _score: int = 0
var _combo_multiplier: int = 1
#endregion
