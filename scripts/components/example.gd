extends Node

#region Public
# Public variables
@export var m_example_variable: int = 0
const EXAMPLE_CONSTANT: float = 1.0
#endregion


#region Godot API
func _ready() -> void:
	pass

func _process(delta: float) -> void:
	pass
#endregion


#region Main API
func example_public_function() -> void:
	pass
#endregion


#region Private
# Private variables
@onready var _example_child_node: Node = $Node
var _example_variable: String = ""
#endregion


#region Private API
func _example_private_function() -> void:
	pass
#endregion