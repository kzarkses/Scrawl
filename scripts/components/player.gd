extends CharacterBody3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const ATTACK_RANGE = 2.0
const ATTACK_COOLDOWN = 0.4
const MOUSE_SENSITIVITY = 0.002

# Nœuds enfants (à ajouter dans l'éditeur)
@onready var attack_area: Area3D = $AttackArea
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var weapon_pivot: Node3D = $WeaponPivot

# Variables d'état
var can_attack: bool = true
var is_attacking: bool = false
var knockback_vector: Vector3 = Vector3.ZERO
var knockback_resistance: float = 0.8
var camera_rotation_x: float = 0.0
var player_rotation_y: float = 0.0

func _ready() -> void:
	# Connexion au gestionnaire de jeu
	GameManager.player_hit.connect(_on_player_hit)
	
	# Capturer la souris
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event: InputEvent) -> void:
	# Gérer la rotation de la caméra avec la souris
	if event is InputEventMouseMotion:
		# Rotation horizontale du joueur
		player_rotation_y -= event.relative.x * MOUSE_SENSITIVITY
		rotate_y(event.relative.x * MOUSE_SENSITIVITY)
		
		# Rotation verticale de la caméra (limitée)
		camera_rotation_x -= event.relative.y * MOUSE_SENSITIVITY
		camera_rotation_x = clamp(camera_rotation_x, -PI/2, PI/2)
		camera_pivot.rotation.x = camera_rotation_x
	
	# Sortir du mode capture de souris avec Échap
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta: float) -> void:
	# Appliquer le recul (knockback)
	if knockback_vector.length() > 0.1:
		velocity += knockback_vector * delta
		knockback_vector = knockback_vector.lerp(Vector3.ZERO, delta * 5)
	
	# Ajouter la gravité
	if not is_on_floor():
		velocity += GameManager.get_gravity() * delta

	# Gérer le saut
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Obtenir la direction d'entrée pour le strafing
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	
	# Créer un vecteur de direction relatif à l'orientation du joueur (strafing)
	var direction = Vector3.ZERO
	direction = Vector3(input_dir.x, 0, input_dir.y).rotated(Vector3.UP, player_rotation_y).normalized()
	
	# Ne pas permettre le mouvement pendant l'attaque
	if is_attacking:
		direction = direction * 0.3  # Réduire la vitesse pendant l'attaque
	
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	# Gérer l'attaque
	if Input.is_action_just_pressed("attack") and can_attack:
		attack()

	move_and_slide()

# func get_gravity() -> Vector3:
# 	return GameManager.get_gravity()

func attack() -> void:
	can_attack = false
	is_attacking = true
	
	# Jouer l'animation d'attaque
	if animation_player.has_animation("attack"):
		animation_player.play("attack")
	
	# Jouer le son d'attaque
	if AudioManager.has_method("play_attack_swing"):
		AudioManager.play_attack_swing(global_position)
	
	# Vérifier les ennemis dans la zone d'attaque
	var enemies_in_range = _get_enemies_in_attack_range()
	for enemy in enemies_in_range:
		if enemy.has_method("take_damage"):
			# Appliquer les dégâts à l'ennemi
			enemy.take_damage(GameManager.player_attack_power)
			
			# Appliquer une force de recul à l'ennemi
			var knockback_direction = (enemy.global_position - global_position).normalized()
			knockback_direction.y = 0.5  # Ajouter une petite composante verticale au recul
			
			if enemy.has_method("apply_knockback"):
				enemy.apply_knockback(knockback_direction * 10.0)
	
	# Réinitialiser l'état après un délai
	await get_tree().create_timer(ATTACK_COOLDOWN).timeout
	is_attacking = false
	can_attack = true

func _get_enemies_in_attack_range() -> Array:
	var enemies = []
	
	# Direction d'attaque basée sur l'orientation de la caméra
	var attack_direction = -camera_pivot.global_transform.basis.z.normalized()
	
	# Si vous utilisez une Area3D pour la détection
	if attack_area:
		# Repositionner la zone d'attaque devant le joueur, dans la direction de la caméra
		attack_area.global_position = global_position + attack_direction * 2.0
		
		var bodies = attack_area.get_overlapping_bodies()
		for body in bodies:
			if body.is_in_group("enemies"):
				enemies.append(body)
	else:
		# Détection basée sur le rayon
		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.new()
		
		query.from = global_position + Vector3(0, 1.0, 0)  # Départ à hauteur d'yeux
		query.to = query.from + attack_direction * ATTACK_RANGE
		query.exclude = [self]
		query.collision_mask = 0b00000010  # Couche de collision des ennemis
		
		var result = space_state.intersect_ray(query)
		if result and result.collider.is_in_group("enemies"):
			enemies.append(result.collider)
	
	return enemies

func apply_knockback(direction: Vector3, force: float = 5.0) -> void:
	# Réduire la force en fonction de la résistance au recul
	knockback_vector = direction * force * (1.0 - knockback_resistance)

func _on_player_hit(damage_amount: float) -> void:
	# Animation ou effet visuel de dégâts
	if animation_player.has_animation("take_hit"):
		animation_player.play("take_hit")
	
	# Feedback visuel (clignotement, shake caméra, etc.)
	if camera:
		var shake_intensity = min(damage_amount / 10.0, 0.5)
		_shake_camera(shake_intensity)

func _shake_camera(intensity: float, duration: float = 0.2) -> void:
	if camera:
		var initial_position = camera.position
		
		# Animation simple de shake
		for i in range(10):
			var rand_offset = Vector3(
				randf_range(-intensity, intensity),
				randf_range(-intensity, intensity),
				0
			)
			camera.position = initial_position + rand_offset
			await get_tree().create_timer(duration / 10.0).timeout
		
		# Retour à la position initiale
		camera.position = initial_position
