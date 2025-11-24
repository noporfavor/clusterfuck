extends RigidBody3D

@export var explosion_radius := 5.0
@export var explosion_force := 20.0
@export var explosion_delay := 2
@export var explosion_damage: int = 40
@export var direct_hit_damage: int = 100
@onready var grenade_bounce_sfx: AudioStreamPlayer3D = $Grenade_Bounce_SFX
@onready var grenade_explosion: AudioStreamPlayer3D = $Grenade_Explosion
@onready var debris: GPUParticles3D = $Debris
@onready var smoke: GPUParticles3D = $Smoke
@onready var fire: GPUParticles3D = $Fire
@onready var m_4: MeshInstance3D = $M4

var queue_free_timer = 2.8
var bounce_count := 0
var exploded := false
var direct_hit_target: CharacterBody3D = null
func _ready():
	await get_tree().create_timer(explosion_delay).timeout
	debris.emitting = true
	smoke.emitting = true
	fire.emitting = true
	if not exploded:
		explode()
		await get_tree().create_timer(queue_free_timer).timeout
func _integrate_forces(state):
	if exploded:
		return
	for i in range (state.get_contact_count()):
		var collider = state.get_contact_collider_object(i)
		if collider:
			grenade_bounce_sfx.play()
			#print("Hit: ", collider.name, " | Groups: ", collider.get_groups())
			if collider.is_in_group("enemy"):
				explode()
				return
			linear_velocity *= 0.9

func explode():
	grenade_explosion.play()
	if exploded:
		return
	exploded = true
	if multiplayer.is_server():
		var shape := SphereShape3D.new()
		shape.radius = explosion_radius
		var _space_state = get_world_3d().direct_space_state
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis(), global_transform.origin)
		query.collision_mask = 1
	
		var results = get_world_3d().direct_space_state.intersect_shape(query, 32)
		for result in results:
			var body = result.get("collider")
			if body and body != self:
				var direction = (body.global_transform.origin - global_transform.origin).normalized()
				var force = direction * explosion_force
			
				if body is RigidBody3D:
					body.apply_central_impulse(force)
			
				elif body is CharacterBody3D:
					body.rpc("apply_knockback", force)
					var distance = global_transform.origin.distance_to(body.global_transform.origin)
					var damage := 0
					
					if body == direct_hit_target:
						damage = direct_hit_damage
					else:
						var t = clamp(distance / explosion_radius, 0.0, 1.0)
						damage = int(lerp(direct_hit_damage, explosion_damage, t))
					body.rpc("apply_damage", damage)
	debris.emitting = true
	smoke.emitting = true
	fire.emitting = true
	m_4.visible = false
	await get_tree().create_timer(queue_free_timer).timeout
	if queue_free_timer >= 0.0:
		queue_free()

func launch(impulse: Vector3):
	linear_velocity = impulse

func _on_body_entered(body: Node) -> void:
	if exploded:
		return
	if body is CharacterBody3D:
		direct_hit_target = body
		explode()
