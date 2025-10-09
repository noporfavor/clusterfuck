extends RigidBody3D

@export var explosion_radius := 5.0
@export var explosion_force := 20.0
@export var explosion_delay := 1.5
@export var max_bounces := 3
@export var explosion_damage: int = 20
@export var direct_hit_damage: int = 40
var bounce_count := 0
var exploded := false
var direct_hit_target: CharacterBody3D = null
func _ready():
	await get_tree().create_timer(explosion_delay).timeout
	if not exploded:
		explode()

func _integrate_forces(state):
	if exploded:
		return
	for i in range (state.get_contact_count()):
		var collider = state.get_contact_collider_object(i)
		if collider:
			#print("Hit: ", collider.name, " | Groups: ", collider.get_groups())
			if collider.is_in_group("enemy"):
				explode()
				return
			if bounce_count >= max_bounces:
				explode()
				return
			linear_velocity *= 0.9

func explode():
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
	queue_free()

func launch(impulse: Vector3):
	linear_velocity = impulse

func _on_body_entered(body: Node) -> void:
	if exploded:
		return
	if body is CharacterBody3D:
		direct_hit_target = body
		explode()
