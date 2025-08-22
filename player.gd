extends CharacterBody3D
@onready var camera: Camera3D = $CameraOrigin/SpringArm3D/Camera3D
@onready var pivot: Node3D = $CameraOrigin
@onready var crosshair_label: Label = $CanvasLayer/Crosshair/Label
@export var sens = 0.5
@export var speed = 5.5
@export var jump_velocity = 5.0
@export var default_fov := 75.0
@export var zoomed_fov := 30.0
@export var zoom_speed := 10.0
var input_enabled := true
#gun
var current_gun: Node = null
#bunnyhopping
var jump_buffer_timer := 0.0
var coyote_timer := 0.0
@export var coyote_time := 0.15 #secs after falling still allowed jump
@export var jump_buffer_time := 0.2 #secs jump input stays active

func _ready():
	camera.current = is_multiplayer_authority()
	#if not input_enabled:
		#camera.current = false
	crosshair_label.text = "X"
	crosshair_label.add_theme_color_override("font_color", Color.WHITE)
	print("Player %s initialized, authority: %d, peer: %d" % [name, get_multiplayer_authority(), multiplayer.get_unique_id()])
func _input(event):
	if not input_enabled:
		return
	if event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x * sens))
		pivot.rotate_x(deg_to_rad(event.relative.y * sens))
		pivot.rotation.x = clamp(pivot.rotation.x, deg_to_rad(-50), deg_to_rad(65))
func equip_gun(gun):
	if not input_enabled:
		return
	if current_gun:
		current_gun.queue_free()
	current_gun = gun
	gun.reparent($HandSocket) # attach to player
	gun.transform = Transform3D.IDENTITY
	gun.camera = $CameraOrigin/SpringArm3D/Camera3D
func _physics_process(_delta):
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * _delta
	if not is_multiplayer_authority():
		move_and_slide()
		return
	var direction = Vector3.ZERO
	var target_fov = default_fov
	if input_enabled:
		# AIM ZOOM
		if Input.is_action_pressed("aim"):
			target_fov = zoomed_fov
	# MOVEMENT INPUT
		if Input.is_action_pressed("move_forward"):
			direction.z += 1
		if Input.is_action_pressed("move_back"):
			direction.z -= 1
		if Input.is_action_pressed("move_left"):
			direction.x += 1
		if Input.is_action_pressed("move_right"):
			direction.x -= 1
	camera.fov = lerp(camera.fov, target_fov, zoom_speed * _delta)
	# MOVEMENT DIRECTION (RAN REGARDLESS OF INPUT_ENABLED)
	if direction != Vector3.ZERO:
		direction = direction.normalized()
		# Rotate direction to be relative to player's rotation on y axis
		direction = global_transform.basis * direction
		direction.y = 0  # WHAT THIS DOES EVEN XD?
		var horizontal_velocity = direction * speed
		if is_on_floor():
			velocity.x = horizontal_velocity.x
			velocity.z = horizontal_velocity.z
		else: 
			#AIR CONTROL, to not kill momentum
			velocity.x = lerp(velocity.x, horizontal_velocity.x, 0.05)
			velocity.z = lerp(velocity.z, horizontal_velocity.z, 0.05)
	else:
		if is_on_floor():
			#stop on floor if no input
			velocity.x = lerp(velocity.x, 0.0, 0.2)
			velocity.z = lerp(velocity.z, 0.0, 0.2)

	var ray_origin = camera.global_transform.origin
	var ray_target = ray_origin - camera.global_transform.basis.z * 2.0
	# PICKUP GUN/WEAPON
	if input_enabled:
		var query = PhysicsRayQueryParameters3D.new()
		query.from = ray_origin
		query.to = ray_target
		query.exclude = [self, camera]
	
		var space_state = get_world_3d().direct_space_state
		var result = space_state.intersect_ray(query)

		if result and result.has("collider") and result.collider and result.collider.is_in_group("gun"):
			if Input.is_action_just_pressed("interact"):
				equip_gun(result.collider)
	# SHOOT
	if input_enabled and Input.is_action_just_pressed("shoot") and current_gun:
		current_gun.shoot()
# jump ''logic''
	if is_on_floor():
		coyote_timer = coyote_time #reset when on floot
	else:
		coyote_timer -= _delta

	if input_enabled and Input.is_action_just_pressed("jump"):
			jump_buffer_timer = jump_buffer_time #record jump input
	else:
		jump_buffer_timer -= _delta
	#check if jump is allowed
	if jump_buffer_timer > 0 and coyote_timer > 0:
		velocity.y = jump_velocity
		jump_buffer_timer = 0 #consume buffered jump
		coyote_timer = 0 #consume coyote time
	move_and_slide()
