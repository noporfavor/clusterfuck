extends Node3D
var camera: Camera3D
@export var bullet_scene: PackedScene
@export var shoot_force := 35.0
@onready var muzzle: Node3D = $Muzzle
var player_near := false
var player_ref: Node = null
func shoot():
	if not is_inside_tree():
		return
	var camera_origin = camera.global_transform.origin
	var ray_direction = -camera.global_transform.basis.z
	var ray_end = camera_origin + ray_direction * 1000.0

	var query = PhysicsRayQueryParameters3D.create(camera_origin, ray_end)
	var space_state = get_world_3d().direct_space_state
	var result = space_state.intersect_ray(query)

	var target_pos = result.get("position", ray_end)
	var shoot_direction = (target_pos - muzzle.global_transform.origin).normalized()

	var bullet = bullet_scene.instantiate()
	bullet.global_transform = muzzle.global_transform
	get_tree().current_scene.add_child(bullet)

	if bullet.has_method("launch"):
		bullet.launch(shoot_direction * shoot_force)

func _on_area_3d_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_near = true
		player_ref = body
		print("Player near gun")
func _physics_process(_delta):
	if player_near and Input.is_action_just_pressed("interact"):
		player_ref.call("equip_gun", self)
