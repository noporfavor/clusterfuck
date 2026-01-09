extends Node3D

const CLIP_SIZE: int = 2
var camera: Camera3D
@export var weapon_type := "shotgun"
@onready var muzzle: Marker3D = $Muzzle
@onready var reload_timer: Timer = $Reload_Timer
@onready var sfx_shotgun_shot: AudioStreamPlayer3D = $sfx_shotgun_shot
@onready var sfx_reload_shotgun: AudioStreamPlayer3D = $sfx_reload_shotgun
@export var holder_id: int = 0
var pellet_damage: int = 10
var max_ammo: int = 12
var current_ammo: int = CLIP_SIZE

func _ready() -> void:
	if multiplayer.is_server():
		var synchronizer = get_node_or_null("MultiplayerSynchronizer")
		if synchronizer:
			synchronizer.set_multiplayer_authority(multiplayer.get_unique_id())
		current_ammo = CLIP_SIZE
		rpc_update_ammo.rpc(current_ammo, max_ammo)
	reload_timer.timeout.connect(_on_reload_timer_timeout)

func shoot():
	if not multiplayer.is_server():
		return
	if current_ammo <= 0:
		return
	current_ammo -= 1
	rpc("_shot_sfx")
	try_start_reload()
	rpc_update_ammo.rpc(current_ammo, max_ammo)

	var pellets = 12
	var max_range = 1000.0

	var cam = camera
	var cam_origin = cam.global_transform.origin
	var cam_dir = -cam.global_transform.basis.z
	var cam_hit = get_world_3d().direct_space_state.intersect_ray(
	PhysicsRayQueryParameters3D.create(cam_origin, cam_origin + cam_dir * max_range)
	)

	var target_point = cam_hit.get("position", cam_origin + cam_dir * max_range)
	var muzzle_origin = muzzle.global_transform.origin

	for i in range(pellets):
		var direction = (target_point - muzzle_origin).normalized()
		direction = get_random_spread_direction(direction)

		var ray_end = muzzle_origin + direction * max_range
		var query = PhysicsRayQueryParameters3D.create(muzzle_origin, ray_end)
		var result = get_world_3d().direct_space_state.intersect_ray(query)

		if result:
			apply_shotgun_damage(result)

@rpc("any_peer", "call_local")
func _shot_sfx():
	sfx_shotgun_shot.play()

@rpc("any_peer", "call_local")
func _reload_sfx():
	sfx_reload_shotgun.play()

@rpc("any_peer", "reliable")
func request_shoot():
	if multiplayer.is_server():
		shoot()

func get_random_spread_direction(forward: Vector3) -> Vector3:
	var spread_deg = 3.0
	var random_x = randf_range(-spread_deg, spread_deg)
	var random_y = randf_range(-spread_deg, spread_deg)
	return forward.rotated(Vector3.UP, deg_to_rad(random_x)).rotated(Vector3.RIGHT, deg_to_rad(random_y)).normalized()

func apply_shotgun_damage(hit: Dictionary):
	var body = hit["collider"]

	if not body.is_in_group("player"):
		return

	if holder_id == 0:
		return

	body.rpc(
		"apply_damage",
		pellet_damage,
		holder_id
	)

func get_player_node(player_id: int) -> Node:
	for node in get_tree().get_nodes_in_group("player"):
		if node.get_multiplayer_authority() == player_id:
			return node
	return null

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
	if max_ammo >= 0:
		try_start_reload()

func try_start_reload():
	if multiplayer.is_server():
		if reload_timer.is_stopped() and current_ammo < CLIP_SIZE: 
			reload_timer.start()      

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

func _deferred_reparent(player: Node):
	var handsocket = player.get_node_or_null("YBotRPacked/Armature/GeneralSkeleton/BoneAttachment3D/HandSocket")
	if handsocket: 
		reparent(handsocket)
		transform = Transform3D.IDENTITY
		camera = player.get_node_or_null("CameraOrigin/SpringArm3D/Camera3D")
		rpc("sync_reparent_hand", handsocket.get_path())
	else:
		print("Error: handsocket not found !")

@rpc("any_peer", "call_local", "reliable")
func sync_reparent_hand(handsocket_path: NodePath):
	var handsocket = get_node_or_null(handsocket_path)
	if handsocket:
		reparent(handsocket)
		transform = Transform3D.IDENTITY

func _deferred_reparent_to_back(player: Node):
	var backsocket = player.get_node_or_null("YBotRPacked/Armature/GeneralSkeleton/BoneAttachment3D2/BackSocket")
	if backsocket: 
		reparent(backsocket)
		transform = Transform3D.IDENTITY
		rpc("sync_reparent_back", backsocket.get_path())

@rpc("any_peer", "call_local", "reliable")
func sync_reparent_back(backsocket_path: NodePath):
	var backsocket = get_node_or_null(backsocket_path)
	if backsocket:
		reparent(backsocket)
		transform = Transform3D.IDENTITY

@rpc("any_peer", "call_local", "reliable")
func attach_to_player(player_id: int):
	print("Attaching gun to player ID: ", player_id)
	set_multiplayer_authority(player_id)
	holder_id = player_id
	rpc_update_ammo.rpc(current_ammo, max_ammo)
	if player_id == 0:
		return
	var player = get_player_node(player_id) # to find player
	if player:
		print("Reparenting gun to player: ", player)
		call_deferred("_deferred_reparent", player)
		player.current_gun = self
	else:
		print("Player not found for ID: ", player_id)

@rpc("any_peer", "call_local","reliable")
func attach_to_back(player_id: int):
	set_multiplayer_authority(player_id)
	holder_id = player_id
	if player_id == 0:
		return
	var player = get_player_node(player_id)
	if player:
		call_deferred("_deferred_reparent_to_back", player)
		player.back_gun = self
