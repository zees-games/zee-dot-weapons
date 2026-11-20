extends RefCounted

## The ray behind ZeeWorldModel's wall response; split out for file size.

var _query: PhysicsRayQueryParameters3D


## Distance from the ray's start (WALL_ARM behind [param hand], flat along [param forward]) to the first wall, or -1.0 for none.
## Characters are looked through; [param carrier] is excluded.
func hit_distance(world: World3D, forward: Vector3, hand: Vector3, length: float, mask: int, carrier: RID) -> float:
	if world == null:
		return -1.0
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return -1.0
	forward = forward.normalized()
	var arm: float = ZeeWorldModel.WALL_ARM
	var from := hand - forward * arm
	if _query == null:
		_query = PhysicsRayQueryParameters3D.new()
		_query.collide_with_areas = false
	var query := _query
	query.from = from
	query.to = from + forward * (arm + length + ZeeWorldModel.WALL_MARGIN)
	query.collision_mask = mask
	query.exclude.clear()
	if carrier.is_valid():
		query.exclude.append(carrier)
	for _hop in range(6):
		var found := world.direct_space_state.intersect_ray(query)
		if found.is_empty():
			return -1.0
		if found["collider"] is CharacterBody3D:
			query.exclude.append(found["rid"])
			continue
		return from.distance_to(found["position"])
	return -1.0
