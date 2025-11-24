extends Node3D

var ammo_on_pack: int = 12

func _on_area_3d_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		print("Area triggered by: ", body.name)
		body.rpc("ammo_pack_picked", ammo_on_pack)
		queue_free()

# respawn function
