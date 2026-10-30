class_name ZeeWallSlam
extends RefCounted

## The view model against a wall: a spring that settles on how far the gun's real reach is inside the surface, pushed back
## by approach speed and nudged up or sideways by a slow, angled approach. Presentation only; a shot still leaves the eye.

const MAX_TILT_DEG := 40.0
## Pitch up per metre of depth, before the cvar multiplier.
const TILT_DEG_PER_M := 120.0
## Approach speed (m/s) at which the response is all push-back and no nudge.
const FAST_SPEED := 5.0

## Smoothed depth in metres (0 in open air).
var amount: float = 0.0
var velocity: float = 0.0
## Surface normal in view space of the last hit, and how squarely the gun faces it (1 head-on).
var normal_local := Vector3.ZERO
var facing: float = 1.0
var closing: float = 0.0


## Metres the muzzle at [param reach] from the eye is past a surface at [param hit_distance] (INF for none).
static func obstruction(reach: float, hit_distance: float, margin: float = 0.03, cap: float = 0.34) -> float:
	if not is_finite(hit_distance) or not is_finite(reach):
		return 0.0
	return clampf(reach + margin - hit_distance, 0.0, cap)


## The drawn gun is [param view_scale] times life size: the reach that counts is the muzzle distance over it, times [code]wall_reach[/code].
static func reach_of(muzzle_distance: float, view_scale: float, reach_share: float) -> float:
	return muzzle_distance / maxf(view_scale, 0.1) * maxf(reach_share, 0.0)


## Spring toward [param target] (damped, frame-rate independent via sub-steps).
func step(target: float, delta: float, stiffness: float = 160.0, damping: float = 20.0) -> void:
	var left := clampf(delta, 0.0, 0.25)
	while left > 0.0:
		var h := minf(left, 1.0 / 120.0)
		velocity += (stiffness * (target - amount) - damping * velocity) * h
		amount += velocity * h
		left -= h
	if amount < 0.0:
		amount = 0.0
		velocity = maxf(velocity, 0.0)
	if target == 0.0 and amount < 0.0005 and absf(velocity) < 0.005:
		amount = 0.0
		velocity = 0.0


## Probes from [param host]'s camera toward the muzzle and forward, [param reach] long. Floors and ceilings are skipped
## unless the view looks down (or up) past [param floor_look] degrees. Returns `{depth, normal}` (normal in view space).
static func probe(host: Node3D, reach: float, mask: int, ignore_characters: bool, exclude: Array[RID],
		muzzle_dir: Vector3, margin: float, cap: float, floor_look: float) -> Dictionary:
	var out := {"depth": 0.0, "normal": Vector3.ZERO}
	var space := host.get_world_3d().direct_space_state if host.get_world_3d() != null else null
	var camera := host.get_parent() as Node3D
	var cam: Node3D = camera if camera != null else host
	if space == null or reach <= 0.01:
		return out
	var from := cam.global_position
	var forward: Vector3 = -cam.global_basis.z.normalized()
	var pitch_down := rad_to_deg(asin(clampf(-forward.y, -1.0, 1.0)))
	var best := INF
	var best_normal := Vector3.ZERO
	for dir: Vector3 in [muzzle_dir, forward]:
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * (reach + margin), mask, exclude.duplicate())
		query.collide_with_areas = false
		for _hop in range(8):
			var found := space.intersect_ray(query)
			if found.is_empty():
				break
			if ignore_characters and found["collider"] is CharacterBody3D:
				query.exclude.append(found["rid"])
				continue
			var n: Vector3 = found["normal"]
			var floor_like := n.y > 0.7 and pitch_down < floor_look
			var ceiling_like := n.y < -0.7 and -pitch_down < floor_look
			if floor_like or ceiling_like:
				break
			var d := from.distance_to(found["position"])
			if d < best:
				best = d
				best_normal = n
			break
	out["depth"] = obstruction(reach, best, margin, cap)
	out["normal"] = cam.global_basis.inverse() * best_normal
	return out


## Fills [member facing] and the response from the probe's normal, the approach [param speed] and the look direction.
func aim_at(normal: Vector3, speed: float) -> void:
	normal_local = normal
	facing = clampf(normal.z, 0.0, 1.0) if normal != Vector3.ZERO else 1.0
	closing = speed * facing


## The pose offset: back by the depth (more when approaching fast), nudged up and sideways when slow or angled, pitched up.
## [param guard] (0 to 1) fades everything out while aiming down sights so the gun stays on the sight line.
func offset(retract_scale: float, tilt_scale: float, push: float = 1.0, nudge: float = 0.6, guard: float = 0.0) -> Transform3D:
	var keep := 1.0 - clampf(guard, 0.0, 1.0)
	var fast := clampf(closing / FAST_SPEED, 0.0, 1.0)
	var depth := amount * maxf(retract_scale, 0.0) * keep
	var back := depth * push * lerpf(0.7, 1.4, fast)
	var up := depth * nudge * (1.0 - fast) * 0.5
	var side := -signf(normal_local.x) * depth * nudge * (1.0 - facing) * 0.8
	var pitch := minf(deg_to_rad(depth * TILT_DEG_PER_M * maxf(tilt_scale, 0.0) * lerpf(1.0, 0.5, fast)), deg_to_rad(MAX_TILT_DEG))
	return Transform3D(Basis(Vector3.RIGHT, pitch), Vector3(side, up, back))


func reset() -> void:
	amount = 0.0
	velocity = 0.0
	facing = 1.0
	closing = 0.0
	normal_local = Vector3.ZERO
