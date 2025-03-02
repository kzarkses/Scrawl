extends Node

#region Public
# Sound banks
@export var m_main_bank: WwiseBank
@export var m_combat_bank: WwiseBank

# Sound events
@export var m_attack_swing_event: WwiseEvent
@export var m_enemy_hit_event: WwiseEvent
@export var m_player_hit_event: WwiseEvent
#endregion


#region Godot API
func _ready() -> void:
	_initialize_wwise()
	
	# Connect to required signals
	GameManager.player_hit.connect(_on_player_hit)
	GameManager.enemy_hit.connect(_on_enemy_hit)

func _exit_tree() -> void:
	_shutdown_wwise()
#endregion


#region Main API
func play_attack_swing(position: Vector3) -> void:
	if m_attack_swing_event:
		m_attack_swing_event.post(get_tree().get_nodes_in_group("player")[0])
	else:
		print("Attack swing event not set")

func play_enemy_hit(position: Vector3) -> void:
	if m_enemy_hit_event:
		m_enemy_hit_event.post(get_tree().get_nodes_in_group("enemies")[0])
	else:
		print("Enemy hit event not set")

func play_player_hit(position: Vector3) -> void:
	if m_player_hit_event:
		m_player_hit_event.post(get_tree().get_nodes_in_group("player")[0])
	else:
		print("Player hit event not set")

func play_event(event: WwiseEvent, game_object) -> void:
	if event:
		event.post(game_object)
	else:
		print("Event not set")

func set_rtpc_value(rtpc: WwiseRTPC, game_object, value: float) -> void:
	if rtpc:
		rtpc.set_value(game_object, value)

func set_switch(switch: WwiseSwitch, game_object) -> void:
	if switch:
		switch.set_value(game_object)

func set_state(state: WwiseState) -> void:
	if state:
		state.set_value()
#endregion


#region Private
# Sound objects
var _is_initialized: bool = false
#endregion


#region Private API
func _initialize_wwise() -> void:
	print("Initializing Wwise Audio System")
	
	await get_tree().process_frame
	
	# Load banks if available
	if m_main_bank:
		m_main_bank.load()
		print("Main SoundBank loaded")
	
	if m_combat_bank:
		m_combat_bank.load()
		print("Combat SoundBank loaded")
	
	_is_initialized = true

func _shutdown_wwise() -> void:
	print("Shutting down Wwise Audio System")
	
	# Unload banks in reverse order
	if m_combat_bank:
		m_combat_bank.unload()
	
	if m_main_bank:
		m_main_bank.unload()

func _on_player_hit(damage_amount: float) -> void:
	if GameManager.player_health > 0:
		var player_nodes = get_tree().get_nodes_in_group("player")
		if player_nodes.size() > 0:
			if m_player_hit_event:
				m_player_hit_event.post(player_nodes[0])

func _on_enemy_hit(enemy_id: int, damage_amount: float) -> void:
	var nodes = get_tree().get_nodes_in_group("enemies")
	for enemy in nodes:
		if enemy.m_enemy_id == enemy_id:
			if m_enemy_hit_event:
				m_enemy_hit_event.post(enemy)
			break
#endregion