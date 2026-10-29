class_name ZeeWallSlam
extends RefCounted

## The view model against a wall: how far the muzzle is inside it, smoothed, and the retract and pitch-up that brings it out. Presentation only; a shot still leaves the eye.

## The gap kept between the muzzle and the wall once retracted.
const MARGIN := 0.06
const MAX_RETRACT := 0.34
const MAX_TILT_DEG := 40.0
## Pitch up per metre retracted, before the cvar multiplier.
const TILT_DEG_PER_M := 120.0
const RATE_IN := 26.0
const RATE_OUT := 9.0

## Smoothed obstruction in metres (0 in open air).
var amount: float = 0.0


## Metres the muzzle ([param muzzle_distance] from the eye) is past the wall hit at [param hit_distance] (INF for none), including [constant MARGIN].
static func obstruction(muzzle_distance: float, hit_distance: float) -> float:
	if not is_finite(hit_distance) or not is_finite(muzzle_distance):
		return 0.0
	return clampf(muzzle_distance + MARGIN - hit_distance, 0.0, MAX_RETRACT)


## Moves [member amount] toward [param target]: quick in, slower out, frame-rate independent.
func step(target: float, delta: float) -> void:
	var rate := RATE_IN if target > amount else RATE_OUT
	amount = lerpf(amount, target, 1.0 - exp(-rate * maxf(delta, 0.0)))
	if absf(amount - target) < 0.0005:
		amount = target


## Metres the un-retracted [param muzzle] (world space) is past the nearest wall, probed from [param host]'s camera; [param exclude] is the carrier's body.
static func target(host: Node3D, muzzle: Vector3, mask: int, ignore_characters: bool, exclude: Array[RID]) -> float:
	var space := host.get_world_3d().direct_space_state if host.get_world_3d() != null else null
	if space == null:
		return 0.0
	var camera := host.get_parent() as Node3D
	var from: Vector3 = (camera if camera != null else host).global_position
	var to_muzzle := muzzle - from
	var distance := to_muzzle.length()
	if distance < 0.01:
		return 0.0
	var forward: Vector3 = -(camera if camera != null else host).global_basis.z.normalized()
	var reach := distance + MARGIN
	var nearest := INF
	for dir: Vector3 in [to_muzzle / distance, forward]:
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * reach, mask, exclude.duplicate())
		query.collide_with_areas = false
		for _hop in range(8):
			var found := space.intersect_ray(query)
			if found.is_empty():
				break
			if ignore_characters and found["collider"] is CharacterBody3D:
				query.exclude.append(found["rid"])
				continue
			nearest = minf(nearest, from.distance_to(found["position"]))
			break
	return obstruction(distance, nearest)


## The pose offset: back by the amount and pitched up, scaled by the two cvar multipliers. Identity at rest.
func offset(retract_scale: float, tilt_scale: float) -> Transform3D:
	var back := amount * maxf(retract_scale, 0.0)
	var pitch := minf(deg_to_rad(amount * TILT_DEG_PER_M * maxf(tilt_scale, 0.0)), deg_to_rad(MAX_TILT_DEG))
	return Transform3D(Basis(Vector3.RIGHT, pitch), Vector3(0.0, 0.0, back))


func reset() -> void:
	amount = 0.0
