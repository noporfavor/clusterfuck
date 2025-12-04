extends Node3D

@onready var area_3d: Area3D = $Area3D
@onready var col: CollisionShape3D = $Area3D/CollisionShape3D
@onready var cube: MeshInstance3D = $"Area3D/CollisionShape3D/health-pack1/Cube"

var heal : int = 100
var is_active := true

func _on_area_3d_body_entered(body: Node3D) -> void:
	if not is_active:
		return

	if body is CharacterBody3D:
		print("Area triggered by: ", body.name)
		body.rpc("heal_from_pack", heal)

		call_deferred("disable_pickup")

func disable_pickup():
	area_3d.set_deferred("monitoring", false)
	area_3d.set_deferred("monitorable", false)
	col.set_deferred("disabled", true)
	cube.visible = false
	time_to_respawn()

func time_to_respawn():
	await get_tree().create_timer(25.0).timeout
	respawn()

func respawn():
	area_3d.set_deferred("monitoring", true)
	area_3d.set_deferred("monitorable", true)
	col.set_deferred("disabled", false)
	cube.visible = true
	is_active = true
