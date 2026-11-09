@tool
extends "zee_view_model_materials.gd"

## The aim, scope-lens and sight-fit half of ZeeViewModel, and the look and strafe it is driven by.


## Holds or releases the aim. Call every frame with the button's state, or on its edges.
func aim(held: bool) -> void:
	_aim_held = held


## The aim button's raw state every frame; held follows it, or a press flips it under toggle rules.
func aim_input(pressed: bool) -> void:
	if _toggles():
		if pressed and not _aim_button_was:
			_aim_held = not _aim_held
	else:
		_aim_held = pressed
	_aim_button_was = pressed


## Whether the sights are being held up (the key, or the toggle's state): what a game sends as its aim button.
func is_aim_held() -> bool:
	return _aim_held


## The range at which the hip barrel crosses the screen's centre (metres), 0 when it is stood up by `hip_lean` instead.
func hip_zero() -> float:
	var id := _art.id if _art != null else &""
	return ads_rules.hip_zero_for(id) if ads_rules != null else float(ZeeAdsRules.SPECS["hip_zero"]["default"])


func _toggles() -> bool:
	return ads_rules != null and _art != null and ads_rules.toggle_for(_art.id)


## Whether the weapon in hand can be aimed at all (melee and throwables cannot).
func can_aim() -> bool:
	return _art != null and _art.aim_enabled and (ads_rules == null or ads_rules.enabled_for(_art.id))


## How big a muzzle flash is drawn: 1 at the hip, the scope's own zoom through a scope, which cancels the magnification.
func flash_scale() -> float:
	return clampf(aim_fov_scale(), 0.1, 1.0) if is_scoped() else 1.0


## The scope views: the scope as a lens on a normal screen, and the scope filling it.
const SCOPE_LENS := 1
const SCOPE_FULL := 2

## The scope view the player chose (a game sets it from its cvar, through [method resolve_scope_mode]).
var scope_mode: int = SCOPE_LENS

## How much of the scope's picture goes clear at a walk (0 keeps it solid at any speed), and the speed in m/s that clears all of it.
var scope_walk_clear: float = 0.55
var scope_walk_speed: float = 5.0


## The scope view the player [param wanted], or the one the server's ADS rules pin for this weapon.
func resolve_scope_mode(wanted: int) -> int:
	if ads_rules == null or _art == null:
		return clampi(wanted, 1, 2)
	return ads_rules.resolve_scope_mode(_art.id, wanted)


## The scope as a lens: the camera stays at the hip's field of view and the overlay's own camera shows the zoom.
func scope_is_lens() -> bool:
	return scope_mode == SCOPE_LENS and has_scope()


## The field-of-view multiplier the main camera takes: [method aim_fov_scale], or 1 with the scope as a lens, which zooms itself.
func view_fov_scale() -> float:
	return 1.0 if scope_is_lens() else aim_fov_scale()


## How much of the scope's picture is clear because the player is moving: 0 standing, up to [member scope_walk_clear].
func scope_clear() -> float:
	if not has_scope() or scope_walk_speed <= 0.0:
		return 0.0
	return scope_walk_clear * smoothstep(0.3, scope_walk_speed, _speed)


## The field-of-view multiplier this frame: 1 at the hip, the zoom at full aim; the game applies it (`DotFpsView.external_fov_scale`).
func aim_fov_scale() -> float:
	if _art == null:
		return 1.0
	var base := float(_dressed.get("zoom", 0.0))
	base = base if base > 0.0 else _art.aim_zoom
	var zoom := base if ads_rules == null else ads_rules.zoom_for(_art.id, base)
	return lerpf(1.0, zoom, _ease(_aim_fraction))


## Whether the view is through a scope right now: a scoped weapon at (nearly) full aim.
func is_scoped() -> bool:
	return _art != null and (_art.aim_scoped or _dressed.get("scoped", false)) and _aim_fraction >= 0.95


## Whether the weapon in hand is looked through (a scope), at any point of the aim-in.
func has_scope() -> bool:
	return _art != null and (_art.aim_scoped or _dressed.get("scoped", false))


## The weapon's overrides of the default scope look, applied by [method ZeeScopeOverlay.follow].
func scope_style() -> Dictionary:
	return _art.scope_style if _art != null else {}


## How visible the scope's surround is, 0 to 1: it fades in over the last of the aim-in, not at the end.
func scope_fraction() -> float:
	if not has_scope():
		return 0.0
	var start := 0.6 if ads_rules == null else ads_rules.scope_fade_start_for(_art.id)
	return smoothstep(start, 1.0, _aim_fraction)


## The scope lens's size, a share of its full size: small at the start of the aim-in, growing toward the eye.
func scope_lens_scale() -> float:
	if not has_scope():
		return 1.0
	var least := 0.3 if ads_rules == null else ads_rules.scope_lens_min_for(_art.id)
	return lerpf(least, 1.0, _ease(_aim_fraction))


func _advance_aim(delta: float) -> void:
	# A reload lowers the aim: the keys turn the gun about the rear sight, centimetres from the eye, and swing it out of view.
	var reloading := _reload_fraction > 0.0 and _reload_fraction < 1.0
	var target := 1.0 if (_aim_held and can_aim() and not reloading) else 0.0
	var time := _art.aim_time if _art != null else 0.16
	if ads_rules != null and _art != null:
		time = ads_rules.aim_time_for(_art.id, time)
		_pose.aim_sway_scale = ads_rules.sway_for(_art.id)
		_pose.gun_strafe = ads_rules.strafe_for(_art.id)
	if not can_aim():
		_aim_held = false
	_aim_fraction = move_toward(_aim_fraction, target, delta / maxf(time, 0.01))
	_pose.set_aim(_ease(_aim_fraction))
	_apply_aim(_ease(_aim_fraction))


## Moves and turns the Aim node so the holder sits [param f] of the way from the art's hip hold to its aim hold,
## and tells the pose where the grip now is so a kick turns about it.
func _apply_aim(f: float) -> void:
	if _art == null or _aim_node == null:
		return

	var hip := _art.view_transform()
	if _sight != null:
		SightFit.fade(_sight, f)
	if f <= 0.0:
		_aim_node.transform = Transform3D.IDENTITY
		_pose.pivot = hip.origin
		return

	var sight := _aim_target()
	var turn := hip.basis.get_rotation_quaternion().slerp(
		sight.basis.get_rotation_quaternion(), f
	)
	var now := Transform3D(
		Basis(turn).scaled(Vector3.ONE * _art.view_scale), hip.origin.lerp(sight.origin, f)
	)
	_aim_node.transform = now * hip.affine_inverse()
	# Aimed, the kick turns about the rear sight, not the grip, or the sight picture jumps up the screen.
	_pose.pivot = now.origin.lerp(now * _sight_line.rear, f) if not _sight_line.is_empty() \
		else now.origin


## The holder's transform at full aim: down the measured sight line, or the art's written
## aim hold when there is none.
func _aim_target() -> Transform3D:
	return _sight_aim if not _sight_line.is_empty() else _art.aim_transform()


## Fits [param art]'s sight on the mesh just built (see zee_sight_fit.gd) and keeps the aim hold that puts it through the eye.
func _fit_sight(art: ZeeWeaponArt) -> void:
	_sight_line = {}
	var camera := get_parent() as Camera3D
	var near := (camera.near if camera != null else 0.05) + NEAR_MARGIN
	var dot := ads_rules.sight_dot_for(art.id) if ads_rules != null else float(ZeeAdsRules.SPECS["sight_dot"]["default"])
	var fitted := SightFit.fit(art, _weapon, _holder, _dressed.get("line", {}), near, dot)
	if not fitted.is_empty():
		_sight_line = fitted.line
		_sight_aim = fitted.aim
		_sight = fitted.sight
	var roots: Array = [_weapon]
	roots.append_array(_dressed.get("parts", []))
	var red := SightFit.cut(art, ads_rules, roots, _holder, _aim_target(), _sight_line)
	if red != null and _sight != null:
		_sight.add_child(red)
	elif red != null:
		_sight = red
	if _sight != null:
		_holder.add_child(_sight)
		_set_on_top(_sight)


## The sight's rear and front points this frame in the camera's space (before the hands' lens), as `{rear, front}`; empty without a sight.
func sight_points() -> Dictionary:
	if _sight_line.is_empty() or _animated == null:
		return {}
	var to_view := _animated.transform * _aim_node.transform * _holder.transform
	return {"rear": to_view * (_sight_line.rear as Vector3), "front": to_view * (_sight_line.front as Vector3)}


## Smoothstep, so the weapon leaves the hip and arrives at the eye gently.
static func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


## Tells the rig how the holder is moving and looking this frame.
## [param look] is absolute yaw and pitch in degrees (the rig takes the difference itself, so sway is computed once);
## [param strafe] is sideways ground speed in m/s, positive right; left out, measured from this node's own movement.
func drive(look: Vector2, speed: float, on_floor: bool, crouched: bool = false, strafe: float = NAN) -> void:
	_strafe_given = strafe
	_look = look
	_speed = speed
	_on_floor = on_floor
	_crouched = crouched


## Sideways speed this frame, m/s, to the right of the view. Measured as the camera's world
## movement across its own right axis when the game did not say; a teleport (a jump of more
## than 30 m/s) is no strafe, and the first frame has nothing to compare with.
func _strafe_speed(delta: float) -> float:
	if not is_nan(_strafe_given):
		return _strafe_given
	if not is_inside_tree():
		return 0.0
	var origin := global_position
	var moved := origin - _last_origin
	var seen := _origin_seen
	_last_origin = origin
	_origin_seen = true
	if not seen or delta <= 0.0:
		return 0.0
	var side := moved.dot(global_transform.basis.x.normalized()) / delta
	return side if absf(side) < 30.0 else 0.0


func _look_delta() -> Vector2:
	if not _look_seen:
		_look_seen = true
		_last_look = _look
		return Vector2.ZERO

	# Yaw wraps, and the wrap is the bug: turning from 179 to -179 degrees is two
	# degrees of movement and reads as 358 without this, which throws the weapon clear
	# off the screen once per full turn.
	var delta := Vector2(
		wrapf(_look.x - _last_look.x, -180.0, 180.0), _look.y - _last_look.y
	)
	_last_look = _look
	return delta



## How much X and Y are scaled to draw at [param hands] degrees under a [param camera]-degree
## lens. 1 when either is not a usable field of view.
static func lens_scale(camera: float, hands: float) -> float:
	return DotViewLens.lens_scale(camera, hands)


## Whether the carrier is sprinting: the weapon lowers and swings to the side, blended over [constant SPRINT_SECONDS].
func set_sprinting(on: bool) -> void:
	_sprinting = on


## Where the sprint carry is, 0 (hip) to 1.
func sprint_fraction() -> float:
	return _sprint


## The held weapon art's first-person hand size, 0 when it keeps the arms' own.
func art_hand_scale() -> float:
	return _art.hand_scale if _art != null else 0.0


func art_forearm_scale() -> float:
	return _art.forearm_scale if _art != null else 0.0


## The weapon's arm-lean cap, or below 0 for the arms' own.
func art_max_lean() -> float:
	return _art.max_lean if _art != null else -1.0
