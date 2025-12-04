extends Node3D

@onready var area_3d: Area3D = $Area3D
@onready var col: CollisionShape3D = $Area3D/CollisionShape3D
@onready var cylinder: MeshInstance3D = $shotgun1/Cylinder
@onready var cylinder2: MeshInstance3D = $shotgun1/Cylinder_001

var ammo_on_pack: int = 12
var is_active := true

func _on_area_3d_body_entered(body: Node3D) -> void:
	if not is_active:
		return

	if body is CharacterBody3D:
		body.rpc("ammo_pack_picked", ammo_on_pack)

		call_deferred("disable_pickup")


# arreglar ocultasion del mesh =P
func disable_pickup():
	area_3d.set_deferred("monitoring", false)
	area_3d.set_deferred("monitorable", false)
	col.set_deferred("disabled", true)
	cylinder.visible = false
	cylinder2.visible = false
	time_to_respawn()

func time_to_respawn():
	await get_tree().create_timer(2.0).timeout
	respawn()


func respawn():
	area_3d.set_deferred("monitoring", true)
	area_3d.set_deferred("monitorable", true)
	col.set_deferred("disabled", false)
	cylinder.visible = true
	is_active = true
