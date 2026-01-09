extends Node3D

@export var weapon_scene: PackedScene
@export var respawn_time := 3.0

@onready var area: Area3D = $Area3D
@onready var col: CollisionShape3D = $Area3D/CollisionShape3D
@onready var mesh: MeshInstance3D = $Cylinder_001

var is_active := true

func _on_area_3d_body_entered(body: Node3D) -> void:
	if not is_active:
		return

	if body is CharacterBody3D:
		is_active = false


		# spawn the REAL weapon
		var weapon = preload("uid://dq6ti10p6fkm").instantiate()
		get_tree().current_scene.add_child(weapon)
		weapon.global_transform = global_transform
		weapon.set_multiplayer_authority(body.get_multiplayer_authority())

		body.equip_gun(weapon, body.get_multiplayer_authority())

		call_deferred("disable_pickup") 

func disable_pickup():
	area.set_deferred("monitoring", false)      
	area.set_deferred("monitorable", false)    
	col.set_deferred("disabled", true)   
	mesh.visible = false
	respawn_later()

func respawn_later():
	await get_tree().create_timer(respawn_time).timeout
	respawn()

func respawn():
	area.set_deferred("monitoring", true)      
	area.set_deferred("monitorable", true)    
	col.set_deferred("disabled", false) 
	mesh.visible = true
	is_active = true
