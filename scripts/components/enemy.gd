extends CharacterBody3D

# Identification unique de l'ennemi
@export var enemy_id: int = 0
@export var enemy_type: String = "basic"

# Statistiques
@export var max_health: float = 50.0
@export var attack_power: float = 5.0
@export var movement_speed: float = 3.0
@export var detection_range: float = 10.0
@export var attack_range: float = 1.5
@export var attack_cooldown: float = 1.2

# Physique
@export var mass: float = 2.0
@export var knockback_resistance: float = 0.3

# Nœuds enfants
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var detection_area: Area3D = $DetectionArea
@onready var attack_area: Area3D = $AttackArea
@onready var ragdoll: Node3D = $Ragdoll  # Optionnel pour les effets physiques avancés

# Variables d'état
var health: float
var player_detected: bool = false
var player_node: Node3D = null
var can_attack: bool = true
var is_attacking: bool = false
var is_stunned: bool = false
var knockback_vector: Vector3 = Vector3.ZERO
var initial_position: Vector3
var patrol_points: Array = []
var current_patrol_index: int = 0

func _ready() -> void:
	# Initialiser la santé
	health = max_health
	initial_position = global_position
	
	# S'enregistrer auprès du gestionnaire de jeu
	GameManager.register_enemy(self, enemy_id)
	GameManager.enemy_hit.connect(_on_enemy_hit)
	
	# Configurer les zones de détection
	if detection_area:
		detection_area.body_entered.connect(_on_detection_area_body_entered)
		detection_area.body_exited.connect(_on_detection_area_body_exited)
	
	if attack_area:
		attack_area.body_entered.connect(_on_attack_area_body_entered)

func _physics_process(delta: float) -> void:
	# Appliquer la gravité
	if not is_on_floor():
		velocity += GameManager.get_gravity() * delta
	
	# Appliquer le recul (knockback)
	if knockback_vector.length() > 0.1:
		velocity += knockback_vector * delta
		knockback_vector = knockback_vector.lerp(Vector3.ZERO, delta * 5)
	
	# Logique de mouvement basée sur l'état
	if is_stunned:
		# Lorsque l'ennemi est étourdi, il ne peut que subir des effets physiques
		pass
	elif player_detected and player_node:
		_follow_player(delta)
	else:
		_patrol(delta)
	
	move_and_slide()

func _follow_player(delta: float) -> void:
	if player_node:
		var direction_to_player = (player_node.global_position - global_position).normalized()
		direction_to_player.y = 0  # Garder l'ennemi au sol
		
		var distance_to_player = global_position.distance_to(player_node.global_position)
		
		# Si suffisamment proche pour attaquer
		if distance_to_player <= attack_range:
			if can_attack and not is_attacking:
				attack()
			# S'arrêter à la portée d'attaque
			velocity.x = move_toward(velocity.x, 0, movement_speed)
			velocity.z = move_toward(velocity.z, 0, movement_speed)
		else:
			# Se déplacer vers le joueur
			velocity.x = direction_to_player.x * movement_speed
			velocity.z = direction_to_player.z * movement_speed
			
			# Rotation vers le joueur
			look_at(Vector3(player_node.global_position.x, global_position.y, player_node.global_position.z), Vector3.UP)

func _patrol(delta: float) -> void:
	if patrol_points.size() > 0:
		# Suivre les points de patrouille
		var target = patrol_points[current_patrol_index]
		var direction = (target - global_position).normalized()
		direction.y = 0
		
		velocity.x = direction.x * (movement_speed * 0.7)  # Vitesse réduite en patrouille
		velocity.z = direction.z * (movement_speed * 0.7)
		
		# Rotation vers la direction de déplacement
		if direction.length() > 0.1:
			look_at(Vector3(global_position.x + direction.x, global_position.y, global_position.z + direction.z), Vector3.UP)
		
		# Vérifier si on a atteint le point de patrouille
		if global_position.distance_to(Vector3(target.x, global_position.y, target.z)) < 0.5:
			current_patrol_index = (current_patrol_index + 1) % patrol_points.size()
	else:
		# Revenir à la position initiale s'il n'y a pas de points de patrouille
		var direction = (initial_position - global_position).normalized()
		direction.y = 0
		
		if global_position.distance_to(Vector3(initial_position.x, global_position.y, initial_position.z)) > 0.5:
			velocity.x = direction.x * (movement_speed * 0.5)
			velocity.z = direction.z * (movement_speed * 0.5)
			
			# Rotation vers la direction de déplacement
			if direction.length() > 0.1:
				look_at(Vector3(global_position.x + direction.x, global_position.y, global_position.z + direction.z), Vector3.UP)
		else:
			velocity.x = move_toward(velocity.x, 0, movement_speed)
			velocity.z = move_toward(velocity.z, 0, movement_speed)

func attack() -> void:
	is_attacking = true
	can_attack = false
	
	# Jouer l'animation d'attaque
	if animation_player and animation_player.has_animation("attack"):
		animation_player.play("attack")
	
	# Attendre que l'animation atteigne le moment de l'impact
	await get_tree().create_timer(0.3).timeout
	
	# Vérifier si le joueur est toujours à portée
	var bodies = attack_area.get_overlapping_bodies()
	for body in bodies:
		if body == player_node:
			GameManager.damage_player(attack_power)
			
			# Appliquer un recul au joueur
			if player_node.has_method("apply_knockback"):
				var knockback_dir = (player_node.global_position - global_position).normalized()
				player_node.apply_knockback(knockback_dir * 3.0)
	
	# Récupération après l'attaque
	await get_tree().create_timer(attack_cooldown).timeout
	is_attacking = false
	can_attack = true

func take_damage(amount: float) -> void:
	health -= amount
	
	# Feedback visuel
	if animation_player and animation_player.has_animation("hit"):
		animation_player.play("hit")
	
	if health <= 0:
		die()
	else:
		# Être brièvement étourdi
		is_stunned = true
		await get_tree().create_timer(0.5).timeout
		is_stunned = false

func apply_knockback(direction: Vector3, force: float = 5.0) -> void:
	# Réduire la force en fonction de la résistance au recul
	knockback_vector = direction * force * (1.0 - knockback_resistance)

func die() -> void:
	# Animation de mort
	if animation_player and animation_player.has_animation("die"):
		animation_player.play("die")
		await animation_player.animation_finished
	
	# Activer le ragdoll si disponible
	if ragdoll:
		_activate_ragdoll()
		
		# Attendre un peu avant de se désenregistrer
		await get_tree().create_timer(3.0).timeout
	
	# Se désenregistrer auprès du gestionnaire de jeu
	GameManager.unregister_enemy(enemy_id)
	
	# Destruction
	queue_free()

func _activate_ragdoll() -> void:
	# Si vous avez un système de ragdoll
	if ragdoll:
		# Désactiver le collisionneur principal
		$CollisionShape3D.disabled = true
		
		# Activer les corps physiques du ragdoll
		for child in ragdoll.get_children():
			if child is RigidBody3D:
				child.freeze = false
				
				# Appliquer la dernière force de mouvement
				if child.has_method("apply_central_impulse"):
					child.apply_central_impulse(velocity * mass)

func _on_detection_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_detected = true
		player_node = body

func _on_detection_area_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_detected = false
		# Garder une référence au joueur pour pouvoir le poursuivre
		# mais arrêter de le suivre après un certain temps
		await get_tree().create_timer(5.0).timeout
		if not player_detected:
			player_node = null

func _on_attack_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and can_attack:
		attack()

func _on_enemy_hit(hit_enemy_id: int, damage_amount: float) -> void:
	if hit_enemy_id == enemy_id:
		take_damage(damage_amount)
