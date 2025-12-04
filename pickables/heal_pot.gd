extends Node3D

@onready var col: CollisionShape3D = $Area3D/CollisionShape3D
@onready var area_3d: Area3D = $Area3D
@onready var sphere: MeshInstance3D = $"Area3D/CollisionShape3D/heal-pot1/Sphere"

var heal : int = 5
var is_active := true

func _on_area_3d_body_entered(body: Node3D) -> void:
	if not is_active:
		return

	if body is CharacterBody3D:
		is_active = false
		body.rpc("heal_from_pack", heal)

		call_deferred("disable_pickup")

func disable_pickup():
	area_3d.set_deferred("monitoring", false)
	area_3d.set_deferred("monitorable", false)
	col.set_deferred("disabled", true)
	sphere.visible = false
	time_to_respawn()

func time_to_respawn():
	await get_tree().create_timer(10.0).timeout
	respawn()

func respawn():
	area_3d.set_deferred("monitoring", true)
	area_3d.set_deferred("monitorable", true)
	col.set_deferred("disabled", false)
	sphere.visible = true
	is_active = true
