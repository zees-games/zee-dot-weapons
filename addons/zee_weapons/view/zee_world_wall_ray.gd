extends RefCounted

## The ray behind ZeeWorldModel's wall response; split out for file size.

var _query: PhysicsRayQueryParameters3D
## [member _query]'s exclude list (the carrier's body), the carrier it was made for, and whether the last probe grew
## the query's copy past it by stepping over a character. A query's `exclude` getter returns a copy, so the list is
## kept here and assigned back.
var _exclude: Array[RID] = []
var _carrier := RID()
var _grown := false


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
		_grown = true  # a fresh query has no list yet
	var query := _query
	query.from = from
	query.to = from + forward * (arm + length + ZeeWorldModel.WALL_MARGIN)
	query.collision_mask = mask
	# The query keeps its exclude list between probes; it is set again only when the carrier changes or the last probe grew it.
	if carrier != _carrier or _grown:
		_carrier = carrier
		_exclude.clear()
		if carrier.is_valid():
			_exclude.append(carrier)
		query.exclude = _exclude
		_grown = false
	var skips := 0
	for _hop in range(6):
		var found := world.direct_space_state.intersect_ray(query)
		if found.is_empty():
			return -1.0
		if found["collider"] is CharacterBody3D:
			skips = ZeeWallSlam.skip_body(query, _exclude, skips, found["rid"])
			_grown = true
			continue
		return from.distance_to(found["position"])
	return -1.0
