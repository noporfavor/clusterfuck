extends Node3D

const CLIP_SIZE := 6

var camera: Camera3D
@export var bullet_scene: PackedScene
@export var shoot_force := 30.0
@onready var muzzle: Node3D = $Muzzle
@export var holder_id: int = 0
@export var max_ammo := 6
@export var shoot_cd := 0.4
@onready var cooldown_timer: Timer = $Cooldown_Timer
@onready var reload_timer: Timer = $Reload_Timer
@onready var gl_shot: AudioStreamPlayer3D = $GL_shot
@onready var gl_reload: AudioStreamPlayer3D = $GL_reload

var current_ammo: int
var reserved_ammo: int
func _ready() -> void:
	if multiplayer.is_server():
		var synchronizer = get_node_or_null("MultiplayerSynchronizer")
		if synchronizer:
			synchronizer.set_multiplayer_authority(multiplayer.get_unique_id())
		current_ammo = max_ammo
		rpc_update_ammo.rpc(current_ammo, max_ammo)
	reload_timer.timeout.connect(_on_reload_timer_timeout)

@rpc("any_peer", "call_local", "reliable")
func rpc_update_ammo(new_ammo: int, _max_ammo: int):
	current_ammo = new_ammo
	if holder_id != 0:
		var player = get_player_node(holder_id)
		if player:
			player.play_shot_anim.rpc()
		if player and player.get_multiplayer_authority() == multiplayer.get_unique_id():
			player.rpc_on_gun_ammo_changed(new_ammo, _max_ammo)

func ammo_pickup(ammo_ammount):
	max_ammo += ammo_ammount
	rpc_update_ammo.rpc(current_ammo, max_ammo)

func try_start_reload():
	if multiplayer.is_server():
		if reload_timer.is_stopped() and current_ammo < CLIP_SIZE and max_ammo > 0: #and cooldown_timer.is_stopped()
			reload_timer.start()       

func shoot():
	if not is_inside_tree() or not multiplayer.is_server() or current_ammo <= 0 or not cooldown_timer.is_stopped():
		return
	if not reload_timer.is_stopped():
		reload_timer.stop()
	current_ammo -= 1
	rpc("_shot_sfx")
	cooldown_timer.start()
	try_start_reload()
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
		if current_ammo >= CLIP_SIZE or max_ammo <= 0:
			reload_timer.stop()
			return
		current_ammo += 1
		max_ammo -= 1
		rpc("_reload_sfx")
	if holder_id != 0:
		var player = get_player_node(holder_id)
		if player:
			player.play_reload_anim.rpc()
		rpc_update_ammo.rpc(current_ammo, max_ammo)
		print("Clip ammo =", current_ammo, " | Reserved ammo =", max_ammo)
		if current_ammo >= CLIP_SIZE:
			try_start_reload()

@rpc("any_peer", "call_local")
func _shot_sfx():
	gl_shot.play()

@rpc("any_peer", "call_local")
func _reload_sfx():
	gl_reload.play()

func _set_transform(player: Node):
	transform = Transform3D.IDENTITY
	camera = player.get_node_or_null("CameraOrigin/SpringArm3D/Camera3D")

@rpc("any_peer", "reliable")
func request_shoot():
	if multiplayer.is_server():
		shoot()

func _deferred_reparent(player: Node):
	var handsocket = player.get_node_or_null("YBotRPacked/Armature/GeneralSkeleton/BoneAttachment3D/HandSocket")
	if handsocket: 
		reparent(handsocket)
		transform = Transform3D.IDENTITY
		camera = player.get_node_or_null("CameraOrigin/SpringArm3D/Camera3D")
		rpc("sync_reparent", handsocket.get_path())
	else:
		print("Error: handsocket not found !")

@rpc("any_peer", "call_local", "reliable")
func sync_reparent(handsocket_path: NodePath):
	var handsocket = get_node_or_null(handsocket_path)
	if handsocket:
		reparent(handsocket)
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
