extends Node3D
## The energy ball a charging weapon builds at its muzzle: it grows, brightens and swirls with
## the draw, holds a clear "ready" pulse at 100%, collapses into the shot on a release and
## shrinks into a fizzle on an early one. Pooled by being one node per model, built on the
## first charge, and costing nothing while the draw is zero.

const READY := 0.98
const SWIRL := 6
const COLLAPSE := 0.22

## Where the ball sits, in world space; read every frame.
var follow: Callable = Callable()
## False for a watcher's copy, which gets no light of its own.
var with_light := true

var _charge := 0.0
var _shown := 0.0
var _peak := 0.0
var _time := 0.0
var _collapse := -1.0
var _fizzle := false
var _fired_ago := 99.0
var _ball: MeshInstance3D = null
var _halo: MeshInstance3D = null
var _light: OmniLight3D = null
var _motes: Array[MeshInstance3D] = []
var _was_ready := false

signal became_ready
signal fizzled


func _init() -> void:
	top_level = true
	visible = false


## The weapon's draw, 0 to 1. Called every frame while the weapon is held.
func set_charge(fraction: float) -> void:
	var f := clampf(fraction, 0.0, 1.0)
	if f <= 0.0 and _charge > 0.02 and _collapse < 0.0:
		_collapse = 0.0
		_peak = _charge
		_fizzle = _fired_ago > 0.25
		if _fizzle:
			fizzled.emit()
	_charge = f
	if f > 0.0:
		_collapse = -1.0
		_fizzle = false
		_build()
		visible = true


## Everything off, for a respawn or a switch.
func reset() -> void:
	_charge = 0.0
	_shown = 0.0
	_collapse = -1.0
	_was_ready = false
	visible = false


## The weapon fired: a collapse already under way is a shot, not a fizzle.
func note_fired() -> void:
	_fired_ago = 0.0
	if _collapse >= 0.0:
		_fizzle = false


## 0 to 1 as the ball is drawn now, for a suite.
func shown() -> float:
	return _shown


func is_ready() -> bool:
	return _charge >= READY


func is_fizzling() -> bool:
	return _collapse >= 0.0 and _fizzle


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	_fired_ago += delta
	_time += delta
	if not visible:
		return

	if follow.is_valid():
		global_position = (follow.call() as Transform3D).origin

	var level := _charge
	var punch := 1.0
	if _collapse >= 0.0:
		_collapse += delta
		var t := _collapse / COLLAPSE
		if t >= 1.0:
			visible = false
			_collapse = -1.0
			_shown = 0.0
			_peak = 0.0
			return
		level = _peak * (1.0 - t)
		punch = 1.0 + (1.4 * sin(t * PI) if not _fizzle else 0.0)
		if _fizzle:
			level *= 1.0 - t
	_shown = level

	var ready := _charge >= READY and _collapse < 0.0
	if ready and not _was_ready:
		became_ready.emit()
	_was_ready = ready
	var pulse := 1.0 + (0.18 * sin(_time * 22.0) if ready else 0.0)

	var radius := lerpf(0.008, 0.075, level) * punch * pulse
	_ball.scale = Vector3.ONE * radius
	_halo.scale = Vector3.ONE * radius * (2.2 + level)
	var mat := _ball.material_override as StandardMaterial3D
	mat.albedo_color = Color(0.6, 0.9, 1.0).lerp(Color(1, 1, 1), level)
	var halo := _halo.material_override as StandardMaterial3D
	halo.albedo_color = Color(0.25, 0.65, 1.0, 0.15 + 0.4 * level)

	if _light != null:
		_light.visible = with_light
		_light.light_energy = (0.2 + 3.5 * level) * punch * pulse
		_light.omni_range = 0.8 + 2.4 * level

	var spin := _time * (4.0 + 12.0 * level)
	for i in _motes.size():
		var a := spin + TAU * float(i) / float(SWIRL)
		var r := radius * (2.4 + 0.6 * sin(_time * 7.0 + i))
		var tilt := float(i % 3) * 0.9
		var local := Vector3(cos(a) * r, sin(a) * r * cos(tilt), sin(a) * r * sin(tilt))
		var mote := _motes[i]
		mote.position = local
		mote.scale = Vector3.ONE * radius * 0.22
		mote.visible = level > 0.12


func _build() -> void:
	if _ball != null:
		return
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	_ball = _glow_mesh(sphere, Color(0.6, 0.9, 1.0), false)
	_halo = _glow_mesh(sphere, Color(0.25, 0.65, 1.0, 0.3), true)
	for i in SWIRL:
		var mote := _glow_mesh(sphere, Color(0.8, 0.95, 1.0), false)
		_motes.append(mote)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.45, 0.8, 1.0)
	_light.shadow_enabled = false
	_light.visible = with_light
	add_child(_light)


func _glow_mesh(mesh: Mesh, colour: Color, soft: bool) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = colour
	if soft:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	node.material_override = m
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node
