extends Node3D

## Somebody else's weapon, as everybody else sees it: one of the family's people holding a
## [ZeeWorldModel], using it, eighteen frames at a fixed 60 fps step, from the side and in front.
##
## [codeblock]
## tools/screenshot.sh --world knife hatchet frag     # screenshots/world_<id>.png
## godot --path . res://tools/world_sheet.tscn -- --weapon knife --sheet /tmp/knife
## [/codeblock]
##
## [b]Why a sheet of its own.[/b] The range's sheet is the first-person view, and a remote
## player's swing is drawn by another file ([ZeeWorldModel]) on another node (the person's hand)
## from another signal (the replicated counter's kind). The first-person swing had keys for a
## week while everybody watching somebody else's knife saw it ride the arm's slash, rigid in the
## hand; nothing but a picture of the third-person model showed it.
##
## The person is driven the way every game drives one: [method DotHumanoidFigure.set_hold] from
## the art's pose, [method DotHumanoidFigure.swing] on a swing, and [method ZeeWorldModel.on_fired]
## with the [ZeeWeaponNet] kind, as a game does when the counter moves. Both are stepped by hand
## ([method DotHumanoidFigure.animate], [method ZeeWorldModel.advance]), so frame 6 is 100 ms
## after the use on any machine.

const CHANNEL := "zee.world_sheet"

const STEP := 1.0 / 60.0

## Steps after the use for each frame: 0 is the instant it is used.
const FRAMES := [0, 3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 33, 36, 40, 44, 48, 54, 60]

var _figure: DotHumanoidFigure = null
var _model: ZeeWorldModel = null
var _label: Label = null


func _ready() -> void:
	_build_world()
	var id := StringName(_argument("--weapon", "knife"))
	var prefix := _argument("--sheet", "")
	if prefix == "":
		printerr("world_sheet: --sheet <prefix> is required")
		get_tree().quit(2)
		return
	_run(id, prefix)


func _build_world() -> void:
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20.0, 20.0)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.32, 0.34, 0.37)
	floor_mesh.material_override = floor_material
	add_child(floor_mesh)

	_figure = DotHumanoidFigure.new()
	_figure.name = "Person"
	add_child(_figure)
	_figure.build(DotHumanoidLook.stock(1))
	# Turned a quarter to the camera's left: the swing crosses the frame instead of coming at it.
	_figure.rotation = Vector3(0.0, deg_to_rad(-60.0), 0.0)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)
	sun.look_at_from_position(Vector3(3.0, 6.0, -2.0), Vector3.ZERO)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.1, 0.11, 0.14)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7, 0.74, 0.82)
	environment.ambient_light_energy = 0.7
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	# In front of the person and to their right, at chest height: a cut from the right shoulder
	# across to the left hip crosses the frame.
	var camera := Camera3D.new()
	camera.fov = 50.0
	add_child(camera)
	camera.look_at_from_position(Vector3(0.35, 1.3, -1.9), Vector3(0.0, 1.0, 0.0))
	camera.current = true

	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(24.0, 16.0)
	_label.add_theme_font_size_override("font_size", 48)
	layer.add_child(_label)


func _run(id: StringName, prefix: String) -> void:
	var art := ZeeWeaponArtTable.get_art(id)
	if art == null:
		printerr("world_sheet: no weapon %s" % id)
		get_tree().quit(2)
		return

	var hold := DotHumanoidFigure.Hold.GUN
	var kind := ZeeWeaponNet.KIND_SHOT
	match art.pose:
		ZeeWeaponArtTable.POSE_MELEE:
			hold = DotHumanoidFigure.Hold.MELEE
			kind = ZeeWeaponNet.KIND_SWING
		ZeeWeaponArtTable.POSE_THROWN:
			hold = DotHumanoidFigure.Hold.NONE
			kind = ZeeWeaponNet.KIND_THROW
	_figure.set_hold(hold)

	_model = ZeeWorldModel.new()
	_model.effects = false
	if not _model.attach_to(_figure):
		printerr("world_sheet: the person has no hand")
		get_tree().quit(1)
		return
	var _equipped := _model.equip(art)
	_model.set_process(false)

	# A second for the art to load and the idle to settle.
	for i in range(30):
		_step()
		await RenderingServer.frame_post_draw

	var stepped := 0
	for n in range(FRAMES.size()):
		if n == 0:
			_use(kind)
		var wanted: int = FRAMES[n]
		while stepped < wanted:
			_step()
			stepped += 1
		_label.text = "%s  ·  %d ms" % [String(id), roundi(float(wanted) * STEP * 1000.0)]
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var path := "%s_%02d.png" % [prefix, n]
		var err := get_viewport().get_texture().get_image().save_png(path)
		if err != OK:
			printerr("could not save %s: %s" % [path, error_string(err)])

	print("world sheet: %d frames at %s_NN.png" % [FRAMES.size(), prefix])
	get_tree().quit()


## What a game does when somebody's fire counter moves: the arm's overlay, and the hand's model.
func _use(kind: int) -> void:
	if kind == ZeeWeaponNet.KIND_SWING:
		_figure.swing()
	_model.on_fired(Vector2(1.2, 0.0), kind, false)


func _step() -> void:
	_figure.animate(0.0, STEP)
	_model.advance(STEP)


func _argument(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var i := args.find(name)
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	return fallback
