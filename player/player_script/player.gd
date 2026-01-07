extends CharacterBody3D

@onready var camera: Camera3D = $CameraOrigin/SpringArm3D/Camera3D
@onready var pivot: Node3D = $CameraOrigin
@onready var animation_player: AnimationPlayer = $YBotRPacked/AnimationPlayer
@onready var anim_tree: AnimationTree = $YBotRPacked/AnimationTree
@onready var footstep_l: AudioStreamPlayer3D = $YBotRPacked/Armature/GeneralSkeleton/LeftFoot/LeftFootArea/CollisionShape3D/footstep
@onready var left_foot_area: Area3D = $YBotRPacked/Armature/GeneralSkeleton/LeftFoot/LeftFootArea
@onready var right_foot_area: Area3D = $YBotRPacked/Armature/GeneralSkeleton/RightFoot/RightFootArea
@onready var footstep_r: AudioStreamPlayer3D = $YBotRPacked/Armature/GeneralSkeleton/RightFoot/RightFootArea/CollisionShape3D/footstepR
@onready var pause_menu: Control = $PauseMenu
@onready var skeleton: Skeleton3D = %GeneralSkeleton
@onready var physical_bone: PhysicalBoneSimulator3D = $YBotRPacked/Armature/GeneralSkeleton/PhysicalBoneSimulator3D

@export var mouse_sensitivity = 0.5
@export var move_speed = 5.5
@export var jump_velocity = 5.0
@export var default_fov := 75.0
@export var zoomed_fov := 30.0
@export var zoom_speed := 10.0
@export var coyote_time := 0.15
@export var jump_buffer_time := 0.2

const BASE_MAX_HEALTH := 100
const OVERHEAL_LIMIT := 200

var is_overhealed = false
var player_last_hit: int = 0
var kill_count: int = 0
var is_paused = false
var player_health: int = BASE_MAX_HEALTH
var input_enabled := true
var current_gun: Node = null
var back_gun: Node = null
var jump_buffer_timer := 0.0
var coyote_timer := 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var current_anim_state := ""
var idle_timer := 0.0
var rifle_state_playback = null
var local_hud: CanvasLayer = null

func _ready():
	anim_tree.active = true
	_setup_camera()
	_setup_crosshair()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if is_multiplayer_authority():
		var hud_scene := preload("res://gui_hud/hud.tscn")
		local_hud = hud_scene.instantiate()
		get_tree().get_current_scene().add_child(local_hud)
		local_hud.set_health(player_health)

func _setup_camera() -> void:
	camera.current = is_multiplayer_authority() and input_enabled

func _setup_crosshair() -> void:
	pass # HACER UN CROSSHAIR UN PCO MAS DECENTE? O VOLVER A PONER UNA X (?)#
# PROBABLY THE HUD SHOULD HANDLE THE CROSSHAIR SO IT CAN BE PROPERLY SWAP   #
# DEPENDING ON WHICH WEAPON IS ON USE                                       #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

func _input(event):
	if Input.is_action_just_pressed("ui_cancel"):
		_pause_menu()
		return
	if not input_enabled or not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion:
		_handle_mouse_motion(event)

	if Input.is_action_pressed("toggle_score_board") and local_hud:
		local_hud.toggle_scoreboard()
	elif Input.is_action_just_released("toggle_score_board") and local_hud:
		local_hud.troggle_scoreboard()

func _pause_menu():
	is_paused = not is_paused
	if is_paused:
		input_enabled = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE 
		pause_menu.visible = true
	else:
		input_enabled = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		pause_menu.visible = false

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity))
	pivot.rotate_x(deg_to_rad(event.relative.y * mouse_sensitivity))
	pivot.rotation.x = clamp(pivot.rotation.x, deg_to_rad(-50), deg_to_rad(65))

func _update_animation_state():
	var move_input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var has_rifle = current_gun != null
	var sprinting = input_enabled and Input.is_action_pressed("sprint")

	var blend_pos = Vector2(move_input.x, move_input.y)
	anim_tree["parameters/Run no weapon/blend_position"] = blend_pos
	anim_tree["parameters/Run aiming rifle/blend_position"] = blend_pos
	anim_tree["parameters/Sprint holding rifle/blend_position"] = blend_pos

	anim_tree["parameters/RunBlend/blend_amount"] = 1.0 if has_rifle else 0.0
	anim_tree["parameters/RifleBlend/blend_amount"] = 1.0 if sprinting else 0.0
	if is_multiplayer_authority():
		_sync_animation.rpc(
			{
				"parameters/Run no weapon/blend_position": anim_tree["parameters/Run no weapon/blend_position"],
				"parameters/Run aiming rifle/blend_position": anim_tree["parameters/Run aiming rifle/blend_position"],
				"parameters/Sprint holding rifle/blend_position": anim_tree["parameters/Sprint holding rifle/blend_position"],
				"parameters/RunBlend/blend_amount": anim_tree["parameters/RunBlend/blend_amount"],
				"parameters/RifleBlend/blend_amount": anim_tree["parameters/RifleBlend/blend_amount"],
			},
			"",
		)

func _handle_weapon_swap():
	if not input_enabled: 
		return

	if Input.is_action_just_pressed("swap_weapon"):
		if current_gun == null and back_gun == null:
			return

		if current_gun != null and back_gun != null:
			_swap_current_with_back_weapon()

# # # # # # # # # # # # 
#    REMATCH LOGIC    #
# # # # # # # # # # # # 

func reset_for_match(spawn_pos: Vector3):
	if not multiplayer.is_server():
		return

	# Reset core state
	player_health = BASE_MAX_HEALTH
	player_last_hit = 0
	velocity = Vector3.ZERO
	is_overhealed = false

	# Reset animation / physics
	physical_bone.active = false
	physical_bone.physical_bones_stop_simulation()
	animation_player.active = true
	anim_tree.active = true

	# Remove weapons
	if multiplayer.is_server():
		rpc("_clear_weapons")
	else:
		rpc("_clear_weapons")

	# Teleport
	global_position = spawn_pos

	# Sync to owner
	rpc("client_sync_match_reset", spawn_pos)

@rpc("any_peer", "call_local")
func _clear_weapons():
	if current_gun:
		current_gun.queue_free()
		current_gun = null

	if back_gun:
		back_gun.queue_free()
		back_gun = null

@rpc("any_peer", "call_local", "reliable")
func client_sync_match_reset(spawn_pos: Vector3):
	player_health = BASE_MAX_HEALTH
	velocity = Vector3.ZERO
	global_position = spawn_pos

# RESET THE AMMO LABEL TO SHOW NOTHING ? 
	#if local_hud:
		#local_hud.set_health(player_health)
		#local_hud.set_ammo()

func _physics_process(_delta):
	if not is_multiplayer_authority():
		return
	_apply_gravity(_delta)
	_handle_movement(_delta)
	_handle_zoom(_delta)
	_handle_jump(_delta)
	_handle_shooting()
	_handle_weapon_swap()
	move_and_slide()
	_update_animation_state()

func _apply_gravity(_delta) -> void:
	if not is_on_floor():
		velocity.y -= gravity * _delta

func _handle_movement(_delta) -> void:
	var direction := _get_input_direction()
	if direction != Vector3.ZERO:
		direction = (global_transform.basis * direction.normalized())
		direction.y = 0
		var horizontal_velocity = direction * move_speed
		if is_on_floor():
			velocity.x = horizontal_velocity.x
			velocity.z = horizontal_velocity.z
			
			if Input.is_action_pressed("sprint"):
				velocity.x = horizontal_velocity.x * 2.0
				velocity.z = horizontal_velocity.z * 2.0
		else:
			velocity.x = lerp(velocity.x, horizontal_velocity.x, 0.05)
			velocity.z = lerp(velocity.z, horizontal_velocity.z, 0.05)
	else:
		if is_on_floor():
			velocity.x = lerp(velocity.x, 0.0, 0.2)
			velocity.z = lerp(velocity.z, 0.0, 0.2)
	
func _get_input_direction() -> Vector3:
	if not input_enabled:
		return Vector3.ZERO
	var direction := Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		direction.z += 1
	if Input.is_action_pressed("move_back"):
		direction.z -= 1
	if Input.is_action_pressed("move_left"):
		direction.x += 1
	if Input.is_action_pressed("move_right"):
		direction.x -= 1
	return direction

func _handle_zoom(_delta) -> void:
	var target_fov: float = zoomed_fov if input_enabled and Input.is_action_pressed("aim") else default_fov
	camera.fov = lerp(camera.fov, target_fov, zoom_speed * _delta)

func _handle_jump(_delta) -> void:
	coyote_timer = coyote_time if is_on_floor() else max(0, coyote_timer - _delta)
	jump_buffer_timer = jump_buffer_time if input_enabled and Input.is_action_just_pressed("jump") else max(0, jump_buffer_timer - _delta)
	if jump_buffer_timer > 0 and coyote_timer > 0:
		velocity.y = jump_velocity
		jump_buffer_timer = 0
		coyote_timer = 0

func _cast_interaction_ray() -> Dictionary:
	var ray_origin := camera.global_transform.origin
	var ray_target = ray_origin - camera.global_transform.basis.z * 2.0
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_target)
	query.exclude = [self, camera]
	return get_world_3d().direct_space_state.intersect_ray(query)

func _handle_shooting() -> void:
	if Input.is_action_just_pressed("shoot") and input_enabled and current_gun and current_gun.holder_id == multiplayer.get_unique_id():
		if multiplayer.is_server():
			current_gun.shoot()
		else: current_gun.request_shoot.rpc_id(1)

@rpc("any_peer", "reliable")
func heal_from_pack(heal_ammount: int):
	player_health = clamp(player_health + heal_ammount, 0, OVERHEAL_LIMIT)
	if is_multiplayer_authority() and local_hud:
		local_hud.set_health(player_health)

	if player_health > BASE_MAX_HEALTH:
		health_decay()

func health_decay():
	if is_overhealed:
		return
	if player_health > BASE_MAX_HEALTH:
		is_overhealed = true
		while player_health > BASE_MAX_HEALTH:
			await get_tree().create_timer(1.0).timeout
			player_health -= 1
			if is_multiplayer_authority() and local_hud:
				local_hud.set_health(player_health)
		is_overhealed = false

@rpc("any_peer", "call_local", "reliable")
func apply_damage(damage_ammount: int, attacker_id: int = 0):
	if player_health <= 0:
		return

	player_last_hit = attacker_id

	player_health = max(player_health - damage_ammount, 0) # CLAMPS THE HP SO IT NOT GO BELOW 0

	if is_multiplayer_authority() and local_hud:
		local_hud.set_health(player_health)

	if player_health == 0:
		die()

func _ragdoll():
	#set_physics_process(false) # not sure about this one either xd
	physical_bone.active = true
	animation_player.active = false
	anim_tree.active = false
	physical_bone.physical_bones_start_simulation()

func die():
	var victim_id := get_multiplayer_authority()
	var killer_id := player_last_hit

	if multiplayer.is_server():
		MatchManager.report_death(victim_id, killer_id)
	else:
		MatchManager.rpc_id(
			1,
			"report_death",
			victim_id,
			killer_id
		)

	player_last_hit = 0
	_ragdoll()

	await get_tree().create_timer(2.0).timeout
	#set_physics_process(true) # not sure about this one
	physical_bone.active = false
	animation_player.active = true
	anim_tree.active = true
	physical_bone.physical_bones_stop_simulation()

	if multiplayer.is_server():
		var respawn_pos = Vector3(-22, 5, 20)
		rpc("respawn", respawn_pos)
	else:
		rpc_id(1, "respawn_request")

@rpc("any_peer", "call_local", "reliable")
func respawn(respawn_pos: Vector3):
	player_health = BASE_MAX_HEALTH
	if is_multiplayer_authority() and local_hud:
		local_hud.set_health(player_health)
	global_position = respawn_pos
	#print("Player %s respawned at %s" % [name, respawn_pos])

@rpc("any_peer", "call_local", "reliable")
func respawn_request():
	if multiplayer.is_server():
		var random_pos = Vector3(randf_range(-22, 3), 5, randf_range(-3, 20))
		rpc("respawn", random_pos)

@rpc("any_peer", "call_local", "reliable")
func apply_knockback(force: Vector3):
	velocity += force

func equip_gun(gun: Node, player_id: int = multiplayer.get_unique_id()):
	if gun.holder_id != 0:
		return

	var type = gun.weapon_type
	if has_weapon_type(type):
		var owned := get_weapon_of_type(type)
		if owned:
			owned.ammo_pickup(gun.max_ammo)
		if is_multiplayer_authority():
			gun.queue_free()
		return

	if current_gun == null:
		current_gun = gun
		gun.rpc("attach_to_player", player_id)
		return
	if back_gun == null:
		back_gun = gun
		gun.rpc("attach_to_back", player_id)
		return
	print("holder id:", gun.holder_id)

func _swap_current_with_back_weapon():
	var hand := current_gun
	var back := back_gun

	if hand == null or back == null:
		return

	current_gun = back
	back_gun = hand

	current_gun.rpc("attach_to_player", multiplayer.get_unique_id())
	back_gun.rpc("attach_to_back", multiplayer.get_unique_id())

func has_weapon_type(type: String) -> bool:
	if current_gun and current_gun.weapon_type == type:
		return true
	if back_gun and back_gun.weapon_type == type:
		return true
	return false

func get_weapon_of_type(type: String) -> Node:
	if current_gun and current_gun.weapon_type == type:
		return current_gun
	if back_gun and back_gun.weapon_type == type:
		return back_gun
	return null

@rpc("any_peer", "reliable")
func ammo_pack_picked(ammo_ammount: int):
	if current_gun:
		current_gun.ammo_pickup(ammo_ammount)

@rpc("any_peer", "call_local")
func rpc_on_gun_ammo_changed(new_ammo: int, max_ammo: int) -> void:
	if is_multiplayer_authority() and local_hud:
		local_hud.set_ammo(new_ammo, max_ammo)

@rpc("any_peer", "call_local", "unreliable")
func _sync_animation(blend_values: Dictionary, _rifle_state: String):
	if anim_tree == null:
		return
	# apply synced blend values
	for key in blend_values:
		anim_tree[key] = blend_values[key]

@rpc("any_peer", "call_local", "unreliable")
func play_shot_anim():
	if anim_tree:
		anim_tree["parameters/Shot/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE

@rpc("any_peer", "call_local", "unreliable")
func play_reload_anim():
	if anim_tree:
		anim_tree["parameters/Reload/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE

func _on_left_foot_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("ground"):
		footstep_l.playing = true

func _on_right_foot_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("ground"):
		footstep_r.playing = true
