extends RefCounted

## The hip hold a view model draws a weapon at under the ADS rules: its size, its place, and the turn that
## points the barrel at the screen's centre. By path, like the iron sight: no global name for a helper.


## A copy of [param art] at [param rules]' size and place (the table's own is never changed); [param depth] is the
## view model's own Z, the lens's pull-in. Null rules keep the art's size and place but still turn the barrel.
static func sized(art: ZeeWeaponArt, rules: ZeeAdsRules, depth: float) -> ZeeWeaponArt:
	# A knife or a grenade sized like a rifle is a fist round a log: a grenade has its own span, a knife none.
	if art.pose == ZeeWeaponArtTable.POSE_THROWN:
		return sized_thrown(art, rules)
	if not art.model_forward.is_equal_approx(Vector3.FORWARD):
		return art
	var out := art.duplicate() as ZeeWeaponArt
	var lean: float = ZeeAdsRules.SPECS["hip_lean"]["default"]
	var cant: float = ZeeAdsRules.SPECS["hip_cant"]["default"]
	var zero: float = ZeeAdsRules.SPECS["hip_zero"]["default"]
	if rules != null:
		out.view_scale = art.view_scale * rules.view_scale_for(art.id)
		out.view_offset = art.view_offset + rules.view_shift_for(art.id)
		# A written aim hold grows about the eye with the gun, or the sight drops below the line of sight.
		out.aim_offset = art.aim_offset * rules.view_scale_for(art.id)
		lean = rules.hip_lean_for(art.id)
		cant = rules.hip_cant_for(art.id)
		zero = rules.hip_zero_for(art.id)
	var roll := art.view_rotation.z * cant
	if zero > 0.0:
		out.view_rotation = converged(out, roll, zero, depth)
	else:
		out.view_rotation = Vector3(art.view_rotation.x, hip_yaw(out.view_offset + Vector3(0.0, 0.0, depth), lean), roll)
	return out


## A grenade drawn so its longest side is the rules' `thrown_span`, whatever model the table or a pack gives it.
static func sized_thrown(art: ZeeWeaponArt, rules: ZeeAdsRules) -> ZeeWeaponArt:
	if rules == null or art.model_path == "":
		return art
	var size := ZeeModelCache.bounds(art.model_path).size
	var extent := maxf(size.x, maxf(size.y, size.z))
	if extent <= 0.0:
		return art
	var out := art.duplicate() as ZeeWeaponArt
	out.view_scale = rules.thrown_span_for(art.id) / extent
	return out


## The hip rotation (degrees: pitch, yaw muzzle-in, [param roll]) whose bore, from [param art]'s muzzle, passes through
## the point [param zero] metres down the view axis. The lens scales X and Y about that axis, so the point is lens-free.
static func converged(art: ZeeWeaponArt, roll: float, zero: float, depth: float = 0.0) -> Vector3:
	var reach := art.muzzle_distance
	if reach <= 0.0 and art.model_path != "":
		reach = ZeeModelCache.muzzle_distance(art.model_path, art.model_forward)
	var muzzle := art.model_forward.normalized() * reach + art.muzzle_offset
	var target := Vector3(0.0, 0.0, -zero - depth)
	var rot := Vector3(0.0, 0.0, roll)
	# The muzzle moves as the gun turns about the grip; a few rounds settle it to well under a hundredth of a degree.
	for _i in 4:
		var basis := Basis.from_euler(rot * (PI / 180.0)).scaled(Vector3.ONE * art.view_scale)
		var to := (target - (art.view_offset + basis * muzzle)).normalized()
		rot.x = rad_to_deg(asin(clampf(to.y, -1.0, 1.0)))
		rot.y = rad_to_deg(atan2(-to.x, -to.z))
	return rot


## The hip yaw (degrees, positive muzzle-in) that draws a barrel held at [param hold] leaning [param lean] degrees
## toward the screen's middle: the `hip_zero` 0 hold, which stands the barrel up instead of pointing it at the centre.
static func hip_yaw(hold: Vector3, lean: float) -> float:
	var depth := maxf(-hold.z, 0.05)
	var below := maxf(-hold.y, 0.0)
	return -rad_to_deg(atan((hold.x - below * tan(deg_to_rad(lean))) / depth))
