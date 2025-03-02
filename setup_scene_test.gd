extends RigidBody3D

@export var impact_threshold: float = 2.0  # Seuil de vitesse pour déclencher des sons d'impact
@export var damage_threshold: float = 8.0  # Seuil de vitesse pour infliger des dégâts
@export var damage_amount: float = 5.0     # Montant des dégâts à infliger
@export var max_health: float = 20.0       # Santé de l'objet
@export var destructible: bool = true      # Si l'objet peut être détruit

var health: float = max_health
var last_collision_velocity: float = 0.0
var last_collision_position: Vector3 = Vector3.ZERO
var last_sound_time: float = 0.0
var sound_cooldown: float = 0.2  # Éviter de jouer des sons trop fréquemment

# Paramètres visuels pour les fractures
@export var original_material: Material
@export var damaged_material: Material
@export var num_fragments: int = 5  # Nombre de fragments à créer lors de la destruction

func _ready() -> void:
	if original_material == null:
		var mesh_instance = get_node_or_null("MeshInstance3D")
		if mesh_instance and mesh_instance.material_override:
			original_material = mesh_instance.material_override
	
	# Configurer les collisions
	contact_monitor = true
	max_contacts_reported = 5  # Nombre max de contacts à surveiller
	can_sleep = true
	
	# Connecter les signaux
	body_entered.connect(_on_body_entered)
	sleeping_state_changed.connect(_on_sleeping_state_changed)

func _physics_process(delta: float) -> void:
	pass

func _on_body_entered(body: Node) -> void:
	# Calculer la vitesse relative approximative de l'impact
	var impact_velocity = linear_velocity.length()
	
	if impact_velocity > last_collision_velocity:
		last_collision_velocity = impact_velocity
		last_collision_position = global_position
		
		# Jouer un son d'impact si le seuil est dépassé et si le cooldown est passé
		var current_time = Time.get_ticks_msec() / 1000.0
		if impact_velocity > impact_threshold and current_time - last_sound_time > sound_cooldown:
			AudioManager.play_physics_impact(last_collision_position, impact_velocity)
			last_sound_time = current_time
		
		# Vérifier si l'impact dépasse le seuil de dommage
		if impact_velocity > damage_threshold:
			take_damage(impact_velocity * 0.5)  # Dégâts proportionnels à la vitesse
			
			# Si c'est le joueur, lui infliger des dégâts
			if body.is_in_group("player") and impact_velocity > damage_threshold * 1.2:
				GameManager.damage_player(damage_amount * (impact_velocity / damage_threshold))
				
				# Appliquer un recul au joueur
				if body.has_method("apply_knockback"):
					var knockback_dir = (body.global_position - global_position).normalized()
					body.apply_knockback(knockback_dir * (impact_velocity * 0.3))

func take_damage(amount: float) -> void:
	if not destructible:
		return
	
	health -= amount
	
	# Effet visuel de dommage
	_update_damage_appearance()
	
	if health <= 0:
		_break_apart()

func _update_damage_appearance() -> void:
	var mesh_instance = get_node_or_null("MeshInstance3D")
	if mesh_instance:
		# Calculer un matériau intermédiaire ou appliquer un matériau endommagé
		var damage_ratio = 1.0 - (health / max_health)
		
		if damaged_material and damage_ratio > 0.5:
			mesh_instance.material_override = damaged_material
		elif original_material:
			# Créer une version plus sombre du matériau
			var material = original_material.duplicate()
			if material is StandardMaterial3D:
				var darkened_color = material.albedo_color.darkened(damage_ratio * 0.5)
				material.albedo_color = darkened_color
				mesh_instance.material_override = material

func _break_apart() -> void:
	# Créer des fragments
	if num_fragments > 0:
		_spawn_fragments()
	
	# Jouer un son de destruction
	AudioManager.play_physics_impact(global_position, damage_threshold * 2)
	
	# Désactiver les collisions
	collision_layer = 0
	collision_mask = 0
	
	# Cacher le modèle original
	var mesh_instance = get_node_or_null("MeshInstance3D")
	if mesh_instance:
		mesh_instance.visible = false
	
	# Ajouter une particule d'explosion ou de poussière
	_spawn_destruction_particles()
	
	# Supprimer après un délai
	await get_tree().create_timer(2.0).timeout
	queue_free()

func _spawn_fragments() -> void:
	var mesh_instance = get_node_or_null("MeshInstance3D")
	if not mesh_instance or not mesh_instance.mesh:
		return
	
	var original_size = Vector3.ONE
	if mesh_instance.mesh is BoxMesh:
		original_size = mesh_instance.mesh.size
	
	for i in range(num_fragments):
		var fragment = RigidBody3D.new()
		fragment.mass = mass / num_fragments
		
		# Configurer la physique du fragment
		fragment.collision_layer = collision_layer
		fragment.collision_mask = collision_mask
		fragment.can_sleep = true
		
		# Créer un maillage plus petit pour le fragment
		var fragment_mesh = MeshInstance3D.new()
		fragment_mesh.mesh = BoxMesh.new()
		fragment_mesh.mesh.size = original_size * (0.4 + randf() * 0.3)
		
		# Appliquer le matériau
		if damaged_material:
			fragment_mesh.material_override = damaged_material
		elif mesh_instance.material_override:
			fragment_mesh.material_override = mesh_instance.material_override
			
		# Ajouter une forme de collision
		var collision_shape = CollisionShape3D.new()
		collision_shape.shape = BoxShape3D.new()
		collision_shape.shape.size = fragment_mesh.mesh.size
		
		fragment.add_child(fragment_mesh)
		fragment.add_child(collision_shape)
		
		# Positionner aléatoirement autour de l'objet d'origine
		var random_offset = Vector3(
			randf_range(-0.5, 0.5),
			randf_range(0, 1.0),
			randf_range(-0.5, 0.5)
		) * original_size * 0.5
		
		fragment.global_position = global_position + random_offset
		
		# Appliquer une impulsion aléatoire
		fragment.linear_velocity = (random_offset.normalized() + Vector3.UP * 0.5) * randf_range(2.0, 5.0)
		fragment.angular_velocity = Vector3(
			randf_range(-5, 5),
			randf_range(-5, 5),
			randf_range(-5, 5)
		)
		
		# Ajouter le fragment à la scène
		get_parent().add_child(fragment)
		
		# Supprimer le fragment après un certain temps
		var timer = get_tree().create_timer(randf_range(3.0, 5.0))
		timer.timeout.connect(func(): fragment.queue_free())

func _spawn_destruction_particles() -> void:
	# Créer un système de particules simple pour la destruction
	var particles = GPUParticles3D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.lifetime = 1.0
	particles.amount = 30
	
	# Configurer le matériau des particules
	var particle_material = ParticleProcessMaterial.new()
	particle_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	particle_material.emission_sphere_radius = 0.2
	particle_material.direction = Vector3(0, 1, 0)
	particle_material.spread = 45.0
	particle_material.gravity = Vector3(0, -9.8, 0)
	particle_material.initial_velocity_min = 2.0
	particle_material.initial_velocity_max = 5.0
	particle_material.scale_min = 0.1
	particle_material.scale_max = 0.3
	particle_material.color = Color(0.7, 0.7, 0.7)
	particles.process_material = particle_material
	
	# Créer un matériau pour les particules
	var mesh = SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	particles.draw_pass_1 = mesh
	
	# Ajouter les particules à la scène
	particles.global_position = global_position
	get_parent().add_child(particles)
	
	# Supprimer les particules après leur émission
	await get_tree().create_timer(particles.lifetime * 1.2).timeout
	particles.queue_free()

func _on_sleeping_state_changed() -> void:
	# Réinitialiser la vitesse de collision lorsque l'objet s'arrête
	if sleeping:
		last_collision_velocity = 0.0
