class_name ZeeHandsFrame
extends RefCounted

## The frame [signal ZeeViewModel.hands_reached] hands its points in: the drawn weapon scaled about the eye down to
## life size, so a game's own life-size arms reach the drawn grip. The view lens and view_scale draw the weapon
## metres away and several times its size; a point scaled about the eye lands on the same pixel, so the hands still cover it.


## The weapon's drawn size over its size in a hand: the holder's scale across the view over the art's [member ZeeWeaponArt.world_scale].
static func life_scale(to_holder: Transform3D, art: ZeeWeaponArt) -> float:
	var across := to_holder.basis.x.length()
	var world := art.world_scale if art != null and art.world_scale > 0.0 else 1.0
	return maxf(across / world, 0.001)


## [param scale], lowered so a grip drawn [param drawn] metres from the eye lands no nearer than [param nearest].
static func keep_distance(scale: float, drawn: float, nearest: float) -> float:
	return minf(scale, drawn / nearest) if nearest > 0.0 and drawn > 0.0 else scale


## Places [param frame] (a child of [param view]) so its points are [param animated]'s, scaled about the eye by 1 / [param scale].
static func place(frame: Node3D, view: Node3D, animated: Node3D, scale: float) -> void:
	var shrink := Transform3D(Basis.from_scale(Vector3.ONE / scale), Vector3.ZERO)
	frame.transform = view.transform.affine_inverse() * shrink * view.transform * animated.transform
