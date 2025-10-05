extends CharacterBody3D
@onready var camera: Camera3D = $CameraOrigin/SpringArm3D/Camera3D
@onready var pivot: Node3D = $CameraOrigin
@onready var crosshair_label: Label = $CanvasLayer/Crosshair/Label
@onready var hand_socket: Node3D = $HandSocket

@export var mouse_sensitivity = 0.5
@export var move_speed = 5.5
@export var jump_velocity = 5.0
@export var default_fov := 75.0
@export var zoomed_fov := 30.0
@export var zoom_speed := 10.0
@export var coyote_time := 0.15
@export var jump_buffer_time := 0.2
@export var Velocity = velocity

var input_enabled := true
var current_gun: Node = null
var jump_buffer_timer := 0.0
var coyote_timer := 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready():
	_setup_camera()
	_setup_crosshair()
	if multiplayer.is_server():
		for gun in get_tree().get_nodes_in_group("gun"):
			if gun.holder_id != 0:
				var player = gun.get_player_node(gun.holder_id)
				if player:
					gun.reparent(player.get_node_or_null("HandSocket"))
					gun.call_deferred("_set_transform", player)

func _setup_camera() -> void:
	camera.current = is_multiplayer_authority() and input_enabled

func _setup_crosshair() -> void:
	crosshair_label.text = "X"
	crosshair_label.add_theme_color_override("font_color", Color.WHITE)
func _input(event):
	if not input_enabled or not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion:
		_handle_mouse_motion(event)
func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity))
	pivot.rotate_x(deg_to_rad(event.relative.y * mouse_sensitivity))
	pivot.rotation.x = clamp(pivot.rotation.x, deg_to_rad(-50), deg_to_rad(65))

func _physics_process(_delta):
	if not is_multiplayer_authority():
		#move_and_slide()
		return
	_apply_gravity(_delta)
	_handle_movement(_delta)
	_handle_zoom(_delta)
	_handle_jump(_delta)
	#_handle_interaction()
	_handle_shooting()
	move_and_slide()
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

@rpc("any_peer", "call_local", "reliable")
func apply_knockback(force: Vector3):
	velocity += force

#func _handle_interaction() -> void:
	#if not input_enabled or not Input.is_action_just_pressed("interact"):
	# 
	# FUNCION PARA DROPEAR ARMA EN MANO / INTERACCION CON WEAS, ETC
	#
func equip_gun(gun: Node, player_id: int = multiplayer.get_unique_id()):
	print("Equip attempt: input_enabled=", input_enabled, " gun.holder_id=", gun.holder_id, " player_id=", player_id)
	if gun.holder_id != 0:
		print("Cannot equip: input disabled or gun held", gun.holder_id)
		return
	current_gun = gun
	gun.rpc("attach_to_player", player_id)
