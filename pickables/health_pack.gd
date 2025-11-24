extends Node3D

var heal : int = 100

func _on_area_3d_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		print("Area triggered by: ", body.name)
		body.rpc("heal_from_pack", heal)
		queue_free()
# create a respawn function~
