@tool
extends "zee_view_model_hands.gd"

## Wall-retract layer of ZeeViewModel, split out for file size.

## Physics layers the wall probe stops on (the world and bodies; the carrier is skipped). The rig copies its shot effects' mask.
@export_flags_3d_physics var wall_mask: int = 0xFFFFFFFF

## When on, the probe passes through character bodies: a person crossing the muzzle is not a wall and must not slam the weapon.
@export var wall_ignore_characters: bool = true

var _strafe_now: float = 0.0

## Pulls the weapon back and up when its muzzle would be inside a wall. The probe is cast against the un-retracted pose, so the answer does not feed back into itself.
func _advance_wall(delta: float) -> void:
	var on := feel_rules.wall_retract > 0.0 and _weapon != null and is_inside_tree()
	var w := _wall_numbers()
	var target := 0.0
	if on:
		var muzzle := muzzle_transform().origin
		var cam: Node3D = (get_parent() as Node3D) if get_parent() is Node3D else self
		var to_muzzle := muzzle - cam.global_position
		var dist := to_muzzle.length()
		if dist > 0.01:
			var scale_now: float = ads_rules.view_scale_for(_art.id) if ads_rules != null and _art != null else 2.0
			var reach := ZeeWallSlam.reach_of(dist, scale_now, w["reach"])
			var hit := ZeeWallSlam.probe(self, reach, wall_mask, wall_ignore_characters, _wall_exclude(), to_muzzle / dist,
				w["margin"], w["max"], w["floor_look"], w["spread"] / maxf(scale_now, 0.1), w["cast"])
			target = hit["depth"]
			if target > 0.0:
				# Walking into the wall pushes the spring's rest point deeper: force decides how far the gun gives.
				target = minf(target + clampf(_speed * 0.012, 0.0, 0.1) * w["impulse"], w["max"])
			_wall.aim_at(hit["normal"], _speed, _strafe_now)
			_wall.set_lean(hit["sides"], _screen_offset(to_muzzle, cam), w["lean"])
	_wall.step(target, delta, w["stiffness"], w["damping"], w["lean_rate"])
	if _wall.amount > 0.0:
		_animated.transform = _wall.offset(feel_rules.wall_retract, feel_rules.wall_tilt, w["push"], w["nudge"], aim_fraction(), w["impulse"]) * _animated.transform
		_keep_off_near_plane()

## Slides the view model away from the eye until no part of the hands is nearer than the camera's near plane plus a margin: a hand through the lens shows its inside as flat colour filling the view.
func _keep_off_near_plane() -> void:
	var camera := get_parent() as Camera3D
	if camera == null or _arms == null or not _arms.has_method(&"nearest_hand_depth"):
		return
	var deficit := camera.near + NEAR_CLEAR - _arms.nearest_hand_depth(camera.global_transform)
	if deficit > 0.0 and deficit < 1.0:
		_animated.global_position -= camera.global_basis.z * deficit

## Where the muzzle sits on the screen relative to the crosshair, as a view-space slope (x right, y up).
func _screen_offset(to_muzzle: Vector3, cam: Node3D) -> Vector2:
	var local := cam.global_basis.inverse() * to_muzzle
	var depth := maxf(-local.z, 0.05)
	return Vector2(local.x, local.y) / depth

## The wall response's numbers for the held weapon (the profile's, or the defaults).
func _wall_numbers() -> Dictionary:
	if ads_rules != null and _art != null:
		return ads_rules.wall_for(_art.id)
	var out := {}
	for key: String in ["reach", "margin", "stiffness", "damping", "push", "nudge", "max", "floor_look", "lean", "spread", "lean_rate", "cast", "impulse"]:
		out[key] = float(ZeeAdsRules.SPECS["wall_" + key]["default"])
	return out

## The carrier's own body, so the probe never stops on the player it hangs from.
func _wall_exclude() -> Array[RID]:
	if _wall_excluded.is_empty():
		var node: Node = get_parent()
		while node != null and not (node is CollisionObject3D):
			node = node.get_parent()
		if node != null:
			_wall_excluded.append((node as CollisionObject3D).get_rid())
	return _wall_excluded

## The retract and pitch the wall asks of the weapon now, for a suite and a tool.
func wall_amount() -> float:
	return _wall.amount

## The wall's eased lean for a suite and a tool: x positive turns the barrel left, y positive tips it up.
func wall_lean() -> Vector2:
	return _wall.lean
