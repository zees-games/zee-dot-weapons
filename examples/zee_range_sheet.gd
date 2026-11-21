extends "res://examples/zee_range_world.gd"

## The `--sheet` renderer of the range (frames stepped by hand, walls, roof, shots), split out of
## zee_range.gd for file size.

const Frames := preload("res://examples/zee_range_frames.gd")
const ReloadShots := preload("res://addons/dot_weapon/view/dot_weapon_reload_shots.gd")

## The fixed step the sheet advances the view model by: 60 frames a second, so "fire 4"
## is 67 ms after the shot on any machine and under any renderer.
const SHEET_STEP := 1.0 / 60.0

@onready var _controller: GSFpsController = $Player/Controller
@onready var _camera: Camera3D = $Player/Head/Camera
@onready var _readout: Label = $UI/Readout
@onready var _crosshair: Label = $UI/Crosshair

var _rig: ZeeWeaponRig = null
var _view: ZeeViewModel = null

## The scope drawn over the screen at full aim with a scoped weapon.
var _scope: ZeeScopeOverlay = null

## Whether `--sheet` is running: the range stops simulating and driving the view itself,
## and [method _run_sheet] steps the view model by hand.
var _sheet: bool = false

## The frames the `--reloads` sheet is made of.
var _reload_tiles: Array[Image] = []

## The simulation tick the sheet's own shots are fired on, clear of the range's.
var _sheet_tick: int = 100000

var _sheet_wall_body: StaticBody3D = null


## Renders sheet frames to `<prefix>_NN.png` and quits. The view model is stepped by hand: its `_process` is off and [method ZeeViewModel.advance] is
## called with [constant SHEET_STEP], so a frame depends on the number of steps, not on how fast a software renderer draws. The range stops simulating too,
## or the rig would push its own reload and deploy fractions over the ones the sheet sets.
func _run_sheet(prefix: String) -> void:
	_sheet_setup()

	var def := _rig.current_def()
	var recoil := Vector2(0.5, 0.1)
	if def != null and def.tuning != null and "recoil_pitch" in def.tuning:
		recoil = Vector2(def.tuning.get("recoil_pitch"), def.tuning.get("recoil_yaw"))
	_sheet_hold(def)

	# `--frames 0,2,9` renders only those frames of the sheet.
	var only := _argument("--frames").split_floats(",") if _argument("--frames") != "" else PackedFloat64Array()

	# A second to let the art load and the first frames settle.
	for i in range(30):
		await RenderingServer.frame_post_draw

	var frames: Array = Frames.frames(OS.get_cmdline_user_args(), _argument("--reloads"), _argument("--aimin"))
	var roof: Node3D = null
	for n in range(frames.size()):
		if not only.is_empty() and not only.has(float(n)):
			continue
		var label: String = frames[n][0]
		var step: String = frames[n][1]
		_sheet_reset()
		var parts := step.split(":")
		var arg := parts[1].to_float() if parts.size() > 1 else 0.0

		var made := await _sheet_step(parts, arg, recoil)
		if made != null:
			roof = made

		var weapon := String(def.id) if def != null else "?"
		_readout.text = "%s  ·  %s" % [weapon, label]
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var path := "%s_%02d.png" % [prefix, n]
		var shot := get_viewport().get_texture().get_image()
		_reload_tiles.append(shot)
		var err := shot.save_png(path)
		if err != OK:
			printerr("could not save %s: %s" % [path, error_string(err)])
		if roof != null:
			roof.queue_free()
			roof = null
		if _sheet_wall_body != null:
			_sheet_wall_body.queue_free()
			_sheet_wall_body = null

	# A reload sheet is dot-weapon's contact sheet (three across), which the shell script uses in place of its own tiling.
	if _argument("--reloads") != "":
		var sheet := ReloadShots.sheet(_reload_tiles, 3, Vector2i(640, 360))
		if sheet != null:
			var _saved := sheet.save_png("%s_sheet.png" % prefix)
	print("sheet: %d frames at %s_NN.png" % [frames.size(), prefix])
	get_tree().quit()


## One frame's scripted action. Returns the shade roof it built, or null.
func _sheet_step(parts: PackedStringArray, arg: float, recoil: Vector2) -> Node3D:
	var roof: Node3D = null
	match parts[0]:
		"rest":
			_sheet_steps(30)
		"aim":
			_view.aim(true)
			_sheet_steps(40)
		"aimin":
			_view.aim(true)
			_sheet_steps(int(arg))
		"fire":
			_sheet_steps(10)
			_sheet_fire(recoil)
			_sheet_steps(int(arg))
		"reload":
			# `--aimed` holds the aim button through the reload: a player reloading with
			# the button down, which the hip-only frames never showed.
			if OS.get_cmdline_user_args().has("--aimed"):
				_view.aim(true)
				_sheet_steps(40)
			_view.on_reload(arg)
			_sheet_steps(30 if OS.get_cmdline_user_args().has("--aimed") else 2)
		"walk", "sprint", "turn", "strafe", "aimstrafe", "aimturn", "aimwalk":
			_sheet_motion(parts[0], arg)
		"land", "aimland":
			_view.aim(parts[0] == "aimland")
			_sheet_steps(40)
			_view.on_landed(9.0)
			_sheet_steps(3)
		"charge":
			_view.on_charge(arg)
			_sheet_steps(18)
		"fizzle":
			_view.on_charge(0.6)
			_sheet_steps(20)
			_view.on_charge(0.0)
			_sheet_steps(int(arg))
		"rail":
			_view.on_charge(1.0)
			_sheet_steps(30)
			var mz := _view.muzzle_transform()
			_view.note_fired()
			_view.on_charge(0.0)
			_rig.shot_fx()._rail_beam(mz.origin, mz.origin + (-_controller.eye_transform().basis.z) * 18.0)
			_sheet_steps(int(arg))
		"deploy":
			_view.on_deploy(arg)
			_sheet_steps(2)
		"shade":
			# A roof between the sun and the player: the view model must look exactly as
			# it does in the open, because the world's shadow map is not its business.
			roof = _sheet_roof()
			_sheet_steps(30)
		"wall":
			_sheet_steps(60)
			await _sheet_wall(arg, parts[2])
		"aimfire":
			_view.aim(true)
			_sheet_steps(40)
			_sheet_fire(recoil)
			_sheet_steps(int(arg))
	return roof


func _sheet_motion(kind: String, arg: float) -> void:
	match kind:
		"walk":
			# A quarter of a stride past a footfall, where the bob is furthest out.
			for i in range(27):
				_view.drive(Vector2.ZERO, 5.0, true)
				_view.advance(SHEET_STEP)
		"sprint":
			_view.set_sprinting(true)
			for i in range(int(arg)):
				_view.drive(Vector2.ZERO, 8.0, true)
				_view.advance(SHEET_STEP)
			_view.set_sprinting(false)
		"turn":
			# 180 degrees a second to the right, for a fifth of a second.
			for i in range(12):
				_view.drive(Vector2(-3.0 * float(i + 1), 0.0), 0.0, true)
				_view.advance(SHEET_STEP)
		"strafe", "aimstrafe":
			_view.aim(kind == "aimstrafe")
			for i in range(40):
				_view.drive(Vector2.ZERO, absf(arg), true, false, arg)
				_view.advance(SHEET_STEP)
		"aimturn":
			_view.aim(true)
			_sheet_steps(40)
			for i in range(12):
				_view.drive(Vector2(-3.0 * float(i + 1), 0.0), 0.0, true)
				_view.advance(SHEET_STEP)
		"aimwalk":
			_view.aim(true)
			_sheet_steps(40)
			for i in range(27):
				_view.drive(Vector2.ZERO, 5.0, true)
				_view.advance(SHEET_STEP)


## A wall [param share] of the gun's real reach in front of the eye, covering all of the view or only a side of the muzzle's line.
func _sheet_wall(share: float, kind: String) -> void:
	var cam := _view.get_parent() as Node3D
	var to_muzzle := cam.global_transform.affine_inverse() * _view.muzzle_transform().origin
	var reach := ZeeWallSlam.reach_of(to_muzzle.length(), ZeeAdsRules.new().view_scale_for(&"rifle"), 1.0)
	var dist := reach * share
	var edge := Vector2(to_muzzle.x, to_muzzle.y) / maxf(-to_muzzle.z, 0.05) * dist
	var size := Vector3(40.0, 40.0, 1.0)
	var at := Vector3(0.0, 0.0, -(dist + 0.5))
	match kind:
		"below":
			at.y = edge.y - 20.0
		"above":
			at.y = edge.y + 20.0
		"right":
			at.x = edge.x + 20.0
	_sheet_wall_body = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	_sheet_wall_body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var quad := BoxMesh.new()
	quad.size = size
	mesh.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.5, 0.42)
	mesh.material_override = mat
	# `--wall-unseen`: the wall still pushes the gun but is not drawn. A sheet is read back from the root viewport, where the wall overlay's
	# SubViewport lags or is missing on the software renderer, so a drawn wall hides gun the player would see over it; unseen, the frame
	# shows the whole pose and any part cut by the near plane.
	mesh.visible = not OS.get_cmdline_user_args().has("--wall-unseen")
	_sheet_wall_body.add_child(mesh)
	cam.add_child(_sheet_wall_body)
	_sheet_wall_body.position = at
	await get_tree().physics_frame
	await get_tree().physics_frame
	_sheet_steps(90)


func _sheet_setup() -> void:
	_sheet = true
	_view.set_process(false)
	# The shot's effects are stepped with the view model, or a flash that lives three frames
	# at 60 fps is gone before a software renderer has drawn one.
	if _rig.shot_fx() != null:
		_rig.shot_fx().set_process(false)
	# Read at a quarter of the size on the tiled sheet, so the label is drawn large.
	_readout.add_theme_font_size_override("font_size", 52)
	_crosshair.add_theme_font_size_override("font_size", 48)
	# Grown both ways from the centre: the scene's box is sized for 24 px, and a 48 px "+" grew
	# it downward only, drawing the crosshair 15 px under the screen's centre, below a sight
	# that was on it.
	_crosshair.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_crosshair.grow_vertical = Control.GROW_DIRECTION_BOTH


func _sheet_hold(def: GSWeaponDef) -> void:
	# `--hold "x,y,z,pitch,yaw,roll,scale"` re-equips the weapon with that first-person
	# placement instead of the table's: the knob for tuning a hold without an edit and a
	# re-import per guess. The numbers that look right then go into ZeeWeaponArtTable.
	var hold := _argument("--hold")
	if hold != "" and def != null:
		var art: ZeeWeaponArt = ZeeWeaponArtTable.get_art(def.id).duplicate(true)
		var v := hold.split_floats(",")
		if v.size() >= 3:
			art.view_offset = Vector3(v[0], v[1], v[2])
		if v.size() >= 6:
			art.view_rotation = Vector3(v[3], v[4], v[5])
		if v.size() >= 7:
			art.view_scale = v[6]
		_view.equip(art)


## A slab over the player on the sun's side, so the player stands in its shadow.
func _sheet_roof() -> Node3D:
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	var toward := sun.global_transform.basis.z.normalized() if sun != null else Vector3.UP
	var body := StaticBody3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(5.0, 0.2, 5.0)
	mesh.mesh = box
	mesh.material_override = _material(Color(0.3, 0.3, 0.32))
	body.add_child(mesh)
	$World.add_child(body)
	body.global_position = _camera.global_position + toward * 3.0
	return body


## Back to rest between frames, so each one shows only what its own step did.
func _sheet_reset() -> void:
	_view.on_reset()
	_view.aim(false)
	_view.on_reload(0.0)
	_view.on_deploy(1.0)
	_view.drive(Vector2.ZERO, 0.0, true)
	_sheet_steps(1)


## Pulls the trigger through the rig, as a game does: the use reaches the view model (kick, melee swing, throw) and the shot's effects (flash, tracer,
## impact and mark), so the fire frames show what a player sees. The magazine is topped up first, so a two-round gun has a round for each fire frame.
## A weapon that will not go off in half a second of held trigger and its release falls back to the kick.
func _sheet_fire(recoil: Vector2) -> void:
	var held := _rig.arsenal.current() if _rig.arsenal != null else null
	var def := _rig.current_def()
	if held != null and def != null and def.magazine > 0:
		held.magazine = def.magazine
	var eye := _controller.eye_transform()
	for i in range(64):
		_sheet_tick += 1
		var command := GSWeaponCommand.new()
		# Held for half a second and then let go: a grenade goes on the release.
		command.set_button(GSWeaponCommand.BUTTON_ATTACK, i < 32)
		var ctx := GSWeaponContext.make(1, _sheet_tick, eye.origin, -eye.basis.z)
		var outcome := _rig.simulate_tick(command, _sheet_tick, ctx)
		if outcome != null and outcome.used:
			break
		if i == 63:
			_view.on_fired(recoil)
	# Let go, and give the rig a quiet second, so the next frame's shot is not refused by this
	# one's cooldown.
	for i in range(64):
		_sheet_tick += 1
		var _idle := _rig.simulate_tick(GSWeaponCommand.new(), _sheet_tick,
			GSWeaponContext.make(1, _sheet_tick, eye.origin, -eye.basis.z))
	# The rig pushes its own deploy and reload fractions; the sheet's frame decides them.
	_view.on_reload(0.0)
	_view.on_deploy(1.0)


func _sheet_steps(count: int) -> void:
	for i in range(count):
		_view.advance(SHEET_STEP)
		if _rig.shot_fx() != null:
			_rig.shot_fx().advance(SHEET_STEP)
		if _view.charge_fx() != null:
			_view.charge_fx().advance(SHEET_STEP)
	# The HUD's half of aiming, as _process does it: without it a scoped weapon's aimed frame
	# was an empty range, the gun hidden and no scope drawn.
	_scope.follow(_view)


func _save_still() -> void:
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(_argument("--still"))
	print("captured %s (%s)" % [_argument("--still"), error_string(err)])
	get_tree().quit()


## One `--name value` argument from the command line, after the bare `--`: everything before it is Godot's, and an argument passed
## without it is swallowed by the engine, which presents as the flag being ignored with no error at all.
static func _argument(name: String) -> String:
	var args := OS.get_cmdline_user_args()

	for i in range(args.size()):
		if args[i] == name and i + 1 < args.size():
			return args[i + 1]

	return ""
