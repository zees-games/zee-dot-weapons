extends Node

## Renders and measures every weapon's hip and aimed view for review. Not headless for PNGs.
##   godot --path . res://tools/view_check.tscn -- --out DIR [--ids pistol,smg] [--rules] [--fov 90] [--sprint]
##     [--rot "pitch,yaw,roll"] [--off "x,y,z"]   (tuning: replace the hip rotation, add to the hip offset)
## Prints one line per weapon and view; with --out saves DIR/<id>_hip.png and <id>_aim.png.

const Measure := preload("res://tools/view_measure.gd")


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := _arg(args, "--out")
	var fov := _arg(args, "--fov", "90").to_float()
	var ids: Array = ZeeWeaponIds.all() if _arg(args, "--ids") == "" else Array(_arg(args, "--ids").split(","))
	var rules := ZeeAdsRules.load_config() if args.has("--rules") else null
	var hold := {}
	if _arg(args, "--rot") != "":
		hold["rotation"] = _vec(_arg(args, "--rot"))
	if _arg(args, "--off") != "":
		hold["offset"] = _vec(_arg(args, "--off"))
	var sprint := args.has("--sprint")
	var m := Measure.new()
	add_child(m)
	m.build(rules, fov)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	ground.position = Vector3(0, -1.6, 0)
	add_child(ground)
	for id in ids:
		for aimed in ([false] if sprint else [false, true]):
			var r: Dictionary = m.measure(StringName(id), aimed, hold, sprint)
			if r.is_empty():
				continue
			print("%-14s %-4s off=%5.1f lean=%6.1f cant=%6.1f deg  width=%4.0f%%  centre=%s  sight_off=%s  top=%3.0f%%" % [
				id, "aim" if aimed else "hip", r.degrees_off, r.screen_lean, r.screen_cant, r.width * 100.0,
				str((r.centre_px as Vector2).round()), str(snappedf(r.get("sight_off_px", -1.0), 0.1)), (r.bbox as Rect2).position.y / get_viewport().get_visible_rect().size.y * 100.0])
			if out != "":
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				DirAccess.make_dir_recursive_absolute(out)
				get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out, id, "aim" if aimed else "hip"])
	get_tree().quit()


func _arg(args: PackedStringArray, key: String, fallback: String = "") -> String:
	var i := args.find(key)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback


func _vec(text: String) -> Vector3:
	var p := text.split(",")
	return Vector3(p[0].to_float(), p[1].to_float(), p[2].to_float()) if p.size() == 3 else Vector3.ZERO
