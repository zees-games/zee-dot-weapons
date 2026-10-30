class_name ZeeViewFeel
extends RefCounted

## How much the first-person weapon moves with its carrier, as the server owner sets it: the
## `mp_vm_*` cvars. Every one is a multiplier on the amount [ZeeWeaponPose] was tuned to, so 1
## is the pack's own feel, 0 switches that motion off and a number above 1 exaggerates it.
##
## [codeblock]
## # server module
## weapons.feel_rules().bind_cvars(add_cvar, DotConVar.FLAG_NOTIFY | DotConVar.FLAG_REPLICATED)
## # client, once it has a link
## weapons.feel_rules().follow_cvars(link)
## [/codeblock]
##
## [b]Presentation, decided by the server.[/b] Nothing here is simulated or replicated state of
## a weapon: the pose reads these every frame, so a change applies at once, and a server that
## wants a sober, competitive view model sets them to 0 for everyone. A solo game sets the
## fields directly. The shape (specs, bind, follow, set) is the one `DotPlayerViewRules` uses.

const CHANNEL := "zee.feel"

signal changed

const CVAR_SWAY := "mp_vm_sway"
const CVAR_TILT := "mp_vm_strafe_tilt"
const CVAR_BOB := "mp_vm_bob"
const CVAR_LANDING := "mp_vm_landing"
const CVAR_AIM_STEADY := "mp_vm_aim_steadiness"
const CVAR_KICK := "cl_vm_kick"
const CVAR_WALL := "cl_vm_wall"
const CVAR_WALL_TILT := "cl_vm_wall_tilt"
const CVAR_RELOAD := "cl_vm_reload_detail"

## Look lag and inertia: the weapon trails a turn, and rolls into it.
var sway: float = 1.0

## The lean and trail when strafing: the weapon rolls and slides against the sideways motion.
var strafe_tilt: float = 1.0

## The walk bob.
var bob: float = 1.0

## The dip on a landing.
var landing: float = 1.0

## How much of the sway, tilt and bob full aim takes away, 0 to 1. At 1 the sight picture is
## dead still; the default leaves a quarter of it, so the weapon is held rather than pinned.
var aim_steadiness: float = 0.75

## The per-shot kick of the weapon and arms, drawn only: 0 off. Never moves the camera or a bullet.
var kick: float = 1.0

## How far the weapon pulls back from a wall it would poke into, a multiplier: 0 off.
var wall_retract: float = 1.0

## How far it also pitches up against a wall, a multiplier: 0 off.
var wall_tilt: float = 1.0

## Each weapon's own reload phases (magazine out, cases thrown, rounds fed), 1; 0 plays one generic reload for every gun.
var reload_detail: float = 1.0


func cvar_specs() -> Array[Dictionary]:
	return [
		{"name": CVAR_SWAY, "value": str(sway), "min": 0.0, "max": 3.0,
			"description": "View model look lag and inertia, a multiplier: 0 off, 1 default"},
		{"name": CVAR_TILT, "value": str(strafe_tilt), "min": 0.0, "max": 3.0,
			"description": "View model tilt and trail when strafing, a multiplier: 0 off, 1 default"},
		{"name": CVAR_BOB, "value": str(bob), "min": 0.0, "max": 3.0,
			"description": "View model walk bob, a multiplier: 0 off, 1 default"},
		{"name": CVAR_LANDING, "value": str(landing), "min": 0.0, "max": 3.0,
			"description": "View model dip on landing, a multiplier: 0 off, 1 default"},
		{"name": CVAR_AIM_STEADY, "value": str(aim_steadiness), "min": 0.0, "max": 1.0,
			"description": "How much of the view model's sway, tilt and bob aiming removes: 0 none, 1 all"},
		{"name": CVAR_KICK, "value": str(kick), "min": 0.0, "max": 3.0,
			"description": "View model kick per shot (weapon and arms), a multiplier: 0 off, 1 default"},
		{"name": CVAR_WALL, "value": str(wall_retract), "min": 0.0, "max": 3.0,
			"description": "How far the view model pulls back from a wall, a multiplier: 0 off, 1 default"},
		{"name": CVAR_WALL_TILT, "value": str(wall_tilt), "min": 0.0, "max": 3.0,
			"description": "How far the view model pitches up against a wall, a multiplier: 0 off, 1 default"},
		{"name": CVAR_RELOAD, "value": str(reload_detail), "min": 0.0, "max": 1.0,
			"description": "Each weapon's own reload (magazine, cases, rounds in sight): 1 on, 0 one generic reload"},
	]


## Registers the cvars through [param add] (a server module's `add_cvar`, or anything shaped
## `(name, default, description, flags) -> cvar` with a `changed` signal and `get_string()`),
## and keeps these fields in step with them. Duck-typed, because dot-server is not a dependency
## here; a value a cvar already holds (argv, a config file) is read back after registering.
func bind_cvars(add: Callable, flags: int = 0) -> Array:
	var made: Array = []
	for spec in cvar_specs():
		var cvar_name: String = spec["name"]
		var made_cvar: Variant = add.call(cvar_name, String(spec["value"]), String(spec["description"]), flags)
		if not (made_cvar is Object) or made_cvar == null:
			continue
		var cv := made_cvar as Object
		if cv.has_method(&"with_range"):
			cv.call(&"with_range", float(spec["min"]), float(spec["max"]))
		if cv.has_signal(&"changed"):
			cv.connect(&"changed", _on_cvar_changed.bind(cvar_name))
		if cv.has_method(&"get_string"):
			var _applied := set_cvar(cvar_name, String(cv.call(&"get_string")))
		made.append(cv)
	return made


## Follows a server's values through [param source] (dot-server's `DotClientLink`, or anything
## with `replicated_cvar(name, fallback)` and a `replicated_cvar_changed(name, value)` signal).
## False when it cannot (an older shell's link); the fields keep their own.
func follow_cvars(source: Object) -> bool:
	if source == null or not is_instance_valid(source):
		return false
	if not source.has_method(&"replicated_cvar") or not source.has_signal(&"replicated_cvar_changed"):
		return false
	for spec in cvar_specs():
		var held := String(source.call(&"replicated_cvar", spec["name"], ""))
		if held != "":
			var _applied := set_cvar(spec["name"], held)
	if not source.is_connected(&"replicated_cvar_changed", _on_replicated_cvar):
		source.connect(&"replicated_cvar_changed", _on_replicated_cvar)
	return true


## Applies one cvar by name. False for another name or a value that is not a finite number in
## the cvar's range (a value out of range is refused, never clamped, so a typo is visible).
func set_cvar(cvar_name: String, value: String) -> bool:
	var text := value.strip_edges()
	if not text.is_valid_float():
		DotLog.debug(CHANNEL, "refused a value", {"cvar": cvar_name, "value": value})
		return false
	var number := text.to_float()
	for spec in cvar_specs():
		if spec["name"] != cvar_name:
			continue
		if not is_finite(number) or number < float(spec["min"]) or number > float(spec["max"]):
			DotLog.debug(CHANNEL, "refused a value out of range", {"cvar": cvar_name, "value": value})
			return false
		match cvar_name:
			CVAR_SWAY: sway = number
			CVAR_TILT: strafe_tilt = number
			CVAR_BOB: bob = number
			CVAR_LANDING: landing = number
			CVAR_AIM_STEADY: aim_steadiness = number
			CVAR_KICK: kick = number
			CVAR_WALL: wall_retract = number
			CVAR_WALL_TILT: wall_tilt = number
			CVAR_RELOAD: reload_detail = number
		changed.emit()
		return true
	return false


func _on_cvar_changed(_old: Variant, new_value: Variant, cvar_name: String) -> void:
	var _applied := set_cvar(cvar_name, str(new_value))


func _on_replicated_cvar(cvar_name: String, value: String) -> void:
	var _applied := set_cvar(cvar_name, value)


func describe() -> Dictionary:
	return {"sway": sway, "strafe_tilt": strafe_tilt, "bob": bob, "landing": landing,
		"aim_steadiness": aim_steadiness, "kick": kick,
		"wall_retract": wall_retract, "wall_tilt": wall_tilt, "reload_detail": reload_detail}


func describe_lines() -> PackedStringArray:
	return PackedStringArray([
		"view model feel: sway %.2f, strafe tilt %.2f, bob %.2f, landing %.2f, aim steadiness %.2f, kick %.2f"
		% [sway, strafe_tilt, bob, landing, aim_steadiness, kick]
	])
