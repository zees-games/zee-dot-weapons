@tool
class_name ZeeScopeOverlay
extends "res://addons/dot_weapon/view/dot_weapon_scope_overlay.gd"

## What a player sees through a scope; the drawing and the exports live in dot-weapon's shared
## overlay (`view/dot_weapon_scope_overlay.gd`), which fc-weapons' AwScopeOverlay also
## extends. A game puts one of these in its HUD and calls [method follow] with its [ZeeViewModel]
## each frame.

var _own_style: Dictionary = {}


## Takes the view's state, then sets the lens camera so the glass magnifies: the shared overlay
## spreads the zoomed camera's whole frame over the lens, which on screen is barely bigger than the hip view.
func follow(view: Object) -> void:
	# A weapon's style keys go back to the overlay's own values first, so the next gun does not keep the last one's look.
	var style: Dictionary = view.scope_style()
	for key: Variant in style:
		if key is String and key in self and not _own_style.has(key):
			_own_style[key] = get(key)
	for key: String in _own_style:
		set(key, _own_style[key])
	super.follow(view)
	if is_instance_valid(_source) and size.y > 0.0:
		var share := minf(size.x, size.y) * lens_circle * lens_scale / size.y
		lens_zoom = lens_fov_share(_source.fov, view.aim_fov_scale(), share)


## The share of the main camera's [param fov] (vertical degrees) the lens camera takes so a lens
## [param share] of the screen's height tall shows the world [param zoom] times the hip view's size.
static func lens_fov_share(fov: float, zoom: float, share: float) -> float:
	if fov <= 0.0 or fov >= 179.0:
		return zoom
	var half := tan(deg_to_rad(fov) * 0.5) * zoom * share
	return rad_to_deg(2.0 * atan(half)) / fov
