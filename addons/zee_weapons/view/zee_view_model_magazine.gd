@tool
extends "zee_view_model_aim.gd"

## Reload-magazine layer of ZeeViewModel: where the separate magazine is drawn through a reload, split out for file size.

## Draws a reload sequence's frame; ZeeViewModel overrides it (the sequence's props live there).
func _animate_sequence(_f: float) -> void:
	pass


## Drops the magazine out and slides a fresh one in, if there is one to animate.
func _animate_magazine(fraction: float) -> void:
	if _seq != null:
		_animate_sequence(clampf(fraction, 0.0, 1.0))
		return
	if _magazine == null or _art == null:
		return

	var f := clampf(fraction, 0.0, 1.0)
	var rest := _art.magazine_transform()

	# The gun's own magazine node is out of the gun from the drop (0.10) to the seat, and the
	# separate one stands in for it only then: drawn at rest as well, it doubled or floated.
	var own := _own_magazine()
	var own_out := f >= 0.10 and f < 0.58
	if own != null:
		own.visible = not own_out

	# Timed to the reload keys (ZeeWeaponPose.RELOAD_KEYS_*) and `_support_hand`: out while the gun rolls onto its side (0.10-0.28),
	# in the hand from 0.36, seated with the jolt at 0.58. Visible throughout it reads as the gun shaking; rising from nothing, as a hand reaching for air.
	var shown := true
	var at := rest.origin
	var basis := rest.basis

	if _feeds:
		# Fetched, carried to where its push starts and pushed home (_build_feed_keys).
		var fed := _fed_round(f)
		shown = not fed.is_empty()
		if shown:
			at = fed.at
	elif _art.magazine_loose:
		# A round fed by hand: in sight only while it is carried in.
		shown = f >= 0.36 and f < 0.58
		if shown and _holder != null:
			# Held up between the fingertips, higher than a magazine: a round inside the fist
			# is a hand that fetched nothing.
			var carried := _holder.transform.affine_inverse() * (_support_hand() + Vector3(0.0, 0.065, 0.0))
			at = carried if carried.is_finite() else rest.origin
	elif f >= 0.10 and f < 0.28:
		var drop := (f - 0.10) / 0.18
		# Falls, faster as it goes, and tips forward off the hand's line.
		at = rest.origin + Vector3(0.0, -0.40 * drop * drop - 0.04 * drop, 0.02 * drop)
		basis = rest.basis * Basis(Vector3.RIGHT, deg_to_rad(-35.0 * drop))
	elif f >= 0.28 and f < 0.36:
		shown = false
	elif f >= 0.36 and f < 0.58 and _holder != null:
		# Where the support hand is, a little above the palm, in the holder's (model) space.
		var settle := clampf((f - 0.36) / 0.22, 0.0, 1.0)
		var carry := _art.magazine_carry.lerp(Vector3(0.0, 0.035, 0.0), settle * settle * settle)
		var hand := _support_hand() + carry
		var held := _holder.transform.affine_inverse() * hand
		at = held if held.is_finite() else rest.origin
		basis = rest.basis * Basis(Vector3.RIGHT, deg_to_rad(-20.0 * (1.0 - settle)))

	_magazine.visible = shown and (own == null or own_out)
	_magazine.transform = Transform3D(basis, at)


## The gun model's own magazine node ([member ZeeWeaponArt.hide_during_reload]), or null.
func _own_magazine() -> Node3D:
	if _art == null or _art.hide_during_reload == &"" or _weapon == null:
		return null
	return _weapon.find_child(String(_art.hide_during_reload), true, false) as Node3D


## Whether the separate magazine is drawn seated at rest: not where the gun carries its own (it
## only stands in while that one is out), and not a loose round (in sight only while carried in).
func _magazine_at_rest() -> bool:
	return _art != null and not _art.magazine_loose and _own_magazine() == null
