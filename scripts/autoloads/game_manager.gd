extends Node

# Signaux pour le système de combat
signal player_hit(damage_amount: float)
signal enemy_hit(enemy_id: int, damage_amount: float)

# Variables globales du jeu
var player_health: float = 100.0
var player_max_health: float = 100.0
var player_attack_power: float = 10.0
var player_defense: float = 5.0

# Constantes de physique
const GRAVITY: float = 9.8
const IMPACT_FORCE_MULTIPLIER: float = 2.0  # Pour les reculs lors des impacts

# Liste des ennemis actifs
var active_enemies: Dictionary = {}

# Système de score
var score: int = 0
var combo_multiplier: int = 1

func _ready() -> void:
	# Initialiser tout ce dont vous avez besoin au démarrage
	print("Gestionnaire de jeu initialisé")

func get_gravity() -> Vector3:
	return Vector3(0, -GRAVITY, 0)

func damage_player(amount: float) -> void:
	var actual_damage = max(1, amount - (player_defense * 0.5))
	player_health -= actual_damage
	emit_signal("player_hit", actual_damage)
	
	if player_health <= 0:
		game_over()

func damage_enemy(enemy_id: int, amount: float) -> void:
	if enemy_id in active_enemies:
		# Récupère l'ennemi et lui applique des dégâts
		var enemy = active_enemies[enemy_id]
		var actual_damage = max(1, amount)
		
		# Déclencher le signal pour que l'ennemi puisse réagir
		emit_signal("enemy_hit", enemy_id, actual_damage)
		
		# Augmenter le combo
		increase_combo()

func register_enemy(enemy_node: Node, enemy_id: int) -> void:
	active_enemies[enemy_id] = enemy_node

func unregister_enemy(enemy_id: int) -> void:
	if enemy_id in active_enemies:
		active_enemies.erase(enemy_id)

func increase_combo() -> void:
	combo_multiplier += 1
	score += 10 * combo_multiplier
	
	# Réinitialiser le combo après un certain temps
	reset_combo_after_delay(3.0)

func reset_combo_after_delay(delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	combo_multiplier = 1

func game_over() -> void:
	print("Game Over!")
	# Implémenter la logique de fin de jeu ici
	
func restart_game() -> void:
	# Réinitialiser les valeurs
	player_health = player_max_health
	score = 0
	combo_multiplier = 1
	active_enemies.clear()
	
	# Redémarrer la scène ou charger le niveau initial
	# get_tree().reload_current_scene()
