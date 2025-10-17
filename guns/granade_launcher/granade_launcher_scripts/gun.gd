extends Node3D

var camera: Camera3D
@export var bullet_scene: PackedScene
@export var shoot_force := 35.0
@onready var muzzle: Node3D = $Muzzle
@export var holder_id: int = 0
@export var max_ammo := 6
@export var shoot_cd := 0.4
@onready var cooldown_timer: Timer = $Cooldown_Timer
@onready var reload_timer: Timer = $Reload_Timer
var current_ammo: int

func _ready() -> void:
	if multiplayer.is_server():
		var synchronizer = get_node_or_null("MultiplayerSynchronizer")
		if synchronizer:
			synchronizer.set_multiplayer_authority(multiplayer.get_unique_id())
		current_ammo = max_ammo
		rpc_update_ammo.rpc(current_ammo, max_ammo)
	reload_timer.timeout.connect(_on_reload_timer_timeout)

@rpc("any_peer", "call_local", "reliable")
func rpc_update_ammo(new_ammo: int, max_ammo: int):
	current_ammo = new_ammo
	if holder_id != 0:
		var player = get_player_node(holder_id)
		if player and player.get_multiplayer_authority() == multiplayer.get_unique_id():
			player.rpc_on_gun_ammo_changed(new_ammo, max_ammo)

func _process(delta: float) -> void:
	if multiplayer.is_server() and current_ammo < max_ammo and reload_timer.is_stopped() and cooldown_timer.is_stopped():
		reload_timer.start()

func shoot():
	if not is_inside_tree() or not multiplayer.is_server() or current_ammo <= 0 or not cooldown_timer.is_stopped():
		return
	if not reload_timer.is_stopped():
		reload_timer.stop()
	current_ammo -= 1
	cooldown_timer.start()
	rpc_update_ammo.rpc(current_ammo, max_ammo)
	print("Granade Launcher ammo = ", current_ammo)
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

func _on_reload_timer_timeout() -> void:
	if multiplayer.is_server():
		current_ammo += 1
		rpc_update_ammo.rpc(current_ammo, max_ammo)
		print("Granade Launcher ammo = ", current_ammo)
		if current_ammo >= max_ammo:
			reload_timer.stop()

func _set_transform(player: Node):
	transform = Transform3D.IDENTITY
	camera = player.get_node_or_null("CameraOrigin/SpringArm3D/Camera3D")

@rpc("any_peer", "reliable")
func request_shoot():
	if multiplayer.is_server():
		shoot()

func _deferred_reparent(player: Node):
	var bone_attachment = player.get_node_or_null("Avatar1/Armature/Skeleton3D/BoneAttachment3D")
	if bone_attachment:
		bone_attachment.transform = Transform3D(
			Basis()
				.rotated(Vector3(1, 1, 1), deg_to_rad(-90))
				.rotated(Vector3(0, 1, 0), deg_to_rad(90)),
			Vector3(-0.4, 0.6, 0.5)
		)
		reparent(bone_attachment)
		transform = Transform3D.IDENTITY
		camera = player.get_node_or_null("CameraOrigin/SpringArm3D/Camera3D")
		rpc("sync_reparent", bone_attachment.get_path())
	else:
		print("Error: BoneAttachment not found !")

@rpc("any_peer", "call_local", "reliable")
func sync_reparent(bone_attachment_path: NodePath):
	var bone_attachment = get_node_or_null(bone_attachment_path)
	if bone_attachment:
		reparent(bone_attachment)
		transform = Transform3D.IDENTITY

@rpc("any_peer", "reliable")
func rpc_spawn_bullet(bullet_transform: Transform3D, velocity: Vector3):
	if not multiplayer.is_server():		
		var bullet = bullet_scene.instantiate()
		bullet.global_transform = bullet_transform
		get_tree().current_scene.add_child(bullet)
		bullet.launch(velocity)

func get_player_node(player_id: int) -> Node:
	for node in get_tree().get_nodes_in_group("player"):
		if node.get_multiplayer_authority() == player_id:
			return node
	return null
func _on_area_3d_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and holder_id == 0:
		if multiplayer.is_server():
			if body.get_multiplayer_authority() == multiplayer.get_unique_id():
				body.call("equip_gun", self)
		else:
			print("Client requesting pickup for gun: ", get_path())
			request_pickup.rpc_id(1, get_path())
@rpc("any_peer", "reliable")
func request_pickup(gun_path: NodePath):
	if multiplayer.is_server():
		print("Server received pickup request for: ", gun_path)
		var gun = get_node_or_null(gun_path)
		if gun and gun.holder_id == 0:
			var player_id = multiplayer.get_remote_sender_id()
			var player = get_player_node(player_id)
			print("Player found: ", player, " for ID: ", player_id)
			if player:
				player.call("equip_gun", gun, player_id)
		else:
			print("Gun not available or invalid: ", gun)

@rpc("authority", "call_local", "reliable")
func attach_to_player(player_id: int):
	print("Attaching gun to player ID: ", player_id)
	holder_id = player_id
	rpc_update_ammo.rpc(current_ammo, max_ammo)
	if player_id == 0:
		print("No player, gun stays at spawn")
		return # No player, stay at spawn
	var player = get_player_node(player_id) # to find player
	if player:
		print("Reparenting gun to player: ", player)
		call_deferred("_deferred_reparent", player)
		player.current_gun = self
	else:
		print("Player not found for ID: ", player_id)
func _physics_process(_delta):
	pass
