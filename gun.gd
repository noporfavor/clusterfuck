extends Node3D

var camera: Camera3D

@export var bullet_scene: PackedScene
@export var shoot_force := 35.0
@onready var muzzle: Node3D = $Muzzle
@export var holder_id: int = 0

func _ready() -> void:
	if multiplayer.is_server():
		var synchronizer = get_node_or_null("MultiplayerSynchronizer")
		if synchronizer:
			synchronizer.set_multiplayer_authority(multiplayer.get_unique_id())

func shoot():
	if not is_inside_tree() or not multiplayer.is_server():
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
	bullet.launch(shoot_direction * shoot_force)
	# RPC to client to spawn bullet
	rpc_spawn_bullet.rpc(muzzle.global_transform, shoot_direction * shoot_force)

@rpc("any_peer", "reliable")
func request_shoot():
	if multiplayer.is_server():
		shoot()

@rpc("authority", "call_local", "reliable")
func attach_to_player(player_id: int):
	holder_id = player_id
	if player_id == 0:
		return # No player, stay at spawn
	var player = get_player_node(player_id) # to find player
	if player:
		call_deferred("_deferred_reparent", player)

func _deferred_reparent(player: Node):
	reparent(player.get_node_or_null("HandSocket"))
	transform = Transform3D.IDENTITY
	camera = player.get_node_or_null("CameraOrigin/SpringArm3D/Camera3D")
@rpc("any_peer", "reliable")
func rpc_spawn_bullet(transform: Transform3D, velocity: Vector3):
	if not multiplayer.is_server():
		var bullet = bullet_scene.instantiate()
		bullet.global_transform = transform
		get_tree().current_scene.add_child(bullet)
		bullet.launch(velocity)

func get_player_node(player_id: int) -> Node:
	for node in get_tree().get_nodes_in_group("player"):
		if node.get_multiplayer_authority() == player_id:
			return node
	return null
func _on_area_3d_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and multiplayer.get_unique_id() == body.get_multiplayer_authority():
		body.call("equip_gun", self)

func _physics_process(_delta):
	pass
