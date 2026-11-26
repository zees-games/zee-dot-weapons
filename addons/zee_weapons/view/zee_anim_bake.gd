class_name ZeeAnimBake
extends RefCounted

## Samples a weapon's procedural first-person motion into keyframed tracks, from the code the game runs: a real ZeeViewModel is driven through each clip (fire or swing, reload, draw,
## holster, inspect, aim, idle sway) at a fixed 60 fps and every drawn part's transform is read back each frame; no number is copied. Used by tools/export_anim_tracks.gd (Nightly's viewer) and the suite.
## Space: the view model's own (no hands lens, hands_fov 0), metres, -Z forward; the viewer applies the lens itself.
## The sidecar format is Nightly's version 1 (see the pack's docs/testing.md). The magazine's own model gets a sidecar of its own: [method split].

const Sidecar := preload("res://addons/gs_weapon/view/gs_weapon_anim_sidecar.gd")
const FPS := Sidecar.FPS
const STEP := Sidecar.STEP
const PACK := "zee-gs-weapons"
## The menu's viewmodel_fov default and field_of_view default, horizontal degrees on 4:3.
const VIEWMODEL_FOV_H := 54.0
const WORLD_FOV_H := 90.0
## Frames the rig is settled for before a clip is recorded.
const SETTLE := 90
## The sway clip's look sweep: a slow turn of this many degrees either way over [constant SWAY_SECONDS].
const SWAY_DEGREES := 3.0
const SWAY_SECONDS := 4.0

var _view: ZeeViewModel = null
## The shared recorder: tracks and frame count of the clip being baked.
var _rec := Sidecar.new()
## The magazine model's transform in view space, one transform per frame (7 floats), while a clip is recorded.
var _mag_view: Array = []
## The reload parts built in code (ammo box, casing, cell ...) the clip drew: index -> {part, shapes}; their tracks are prop.<index>, .scale and .visible.
var _props: Dictionary = {}


## Nightly's asset name for a model path: the pack, then the path under res:// with "/" as "__".
static func asset_of(model_path: String) -> String:
	return Sidecar.asset_of(PACK, model_path)


## The lens block every sidecar carries.
static func lens() -> Dictionary:
	return Sidecar.lens(VIEWMODEL_FOV_H, WORLD_FOV_H)


## The clips a weapon has, in play order, each {name, loop}.
static func clip_names(art: ZeeWeaponArt, def: GSWeaponDef) -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"name": "fire", "loop": false}]
	if def != null and def.magazine > 0:
		out.append({"name": "reload", "loop": false})
		out.append({"name": "reload_empty", "loop": false})
	out.append({"name": "draw", "loop": false})
	out.append({"name": "holster", "loop": false})
	out.append({"name": "inspect", "loop": false})
	if art.aim_enabled:
		out.append({"name": "ads", "loop": false})
	out.append({"name": "idle", "loop": true})
	return out


## Bakes every clip of weapon [param id] under [param host] (a node in the tree). Returns the sidecar dictionary, or {} for an unknown id or a weapon with no model.
## A weapon with a separate magazine model carries its clips under "magazine_clips" for [method split].
func bake(host: Node, id: StringName) -> Dictionary:
	var art := ZeeWeaponArtTable.get_art(id)
	var def := ZeeWeaponPack.catalogue().get_def(id)
	if art == null or def == null or not art.has_model():
		return {}
	var clips: Array = []
	var mag_clips: Array = []
	for c in clip_names(art, def):
		var view := ZeeViewModel.new()
		view.show_arms = true
		view.wall_overlay = false
		view.hands_fov = 0.0
		view.fire_interval = float(def.use_interval_ticks) / float(ZeeWeaponPack.TICK_RATE)
		host.add_child(view)
		view.set_kick_params(def.params)
		view.equip(art)
		_view = view
		var baked := _clip(String(c.name), bool(c.loop), art, def)
		baked["props"] = _props
		if not _mag_view.is_empty() and art.magazine_path != "":
			mag_clips.append({
				"name": baked.name, "length": baked.length, "frames": baked.frames, "loop": baked.loop,
				"tracks": [Sidecar.track("weapon", "transform", _mag_view)],
			})
		clips.append(baked)
		host.remove_child(view)
		view.free()
	var magazine_node := String(art.hide_during_reload) if art.hide_during_reload != &"" else ("magazine" if art.magazine_path != "" else "")
	var out := Sidecar.sidecar(String(id), art.model_path.get_file().get_basename(), asset_of(art.model_path), lens(), "", magazine_node, clips, {"third_person": _third_person(art)})
	if not mag_clips.is_empty():
		out["magazine_clips"] = mag_clips
		out["magazine_asset"] = asset_of(art.magazine_path)
		out["magazine_model"] = art.magazine_path.get_file().get_basename()
	return out


## Takes the magazine model's sidecar out of a baked weapon sidecar: [weapon sidecar, magazine sidecar or {}].
## The magazine's one track is its transform in view space, so the viewer shows it travelling through the reload.
static func split(sidecar: Dictionary) -> Array[Dictionary]:
	var weapon := sidecar.duplicate()
	var mag := {}
	if weapon.has("magazine_clips"):
		mag = {
			"version": Sidecar.VERSION, "weapon": "%s_magazine" % sidecar.weapon, "model": sidecar.magazine_model, "asset": sidecar.magazine_asset,
			"fps": FPS, "lens": sidecar.lens, "nodes": {"bolt": "", "magazine": ""}, "clips": sidecar.magazine_clips,
		}
	for k in ["magazine_clips", "magazine_asset", "magazine_model"]:
		weapon.erase(k)
	return [weapon, mag]


func _clip(name: String, loop: bool, art: ZeeWeaponArt, def: GSWeaponDef) -> Dictionary:
	_rec.begin()
	_props = {}
	_mag_view = []
	_view.on_reload(0.0)
	_view.on_deploy(1.0)
	for _i in SETTLE:
		_view.advance(STEP)
	match name:
		"fire":
			_fire(maxf(0.8, _view.fire_interval + 0.2), art, def)
		"reload", "reload_empty":
			_reload(def, name == "reload_empty")
		"draw":
			_deploy(float(def.deploy_ticks) / float(ZeeWeaponPack.TICK_RATE), false)
		"holster":
			_deploy(float(def.holster_ticks) / float(ZeeWeaponPack.TICK_RATE), true)
		"inspect":
			_inspect()
		"ads":
			_ads()
		"idle":
			_idle()
	return _rec.finish(name, loop)


func _fire(seconds: float, art: ZeeWeaponArt, def: GSWeaponDef) -> void:
	var shot := GSWeaponOutcome.new()
	shot.used = true
	match art.pose:
		&"melee", &"fists":
			shot.kind = GSWeaponOutcome.KIND_SWING
		&"thrown":
			shot.kind = GSWeaponOutcome.KIND_THROW
		_:
			shot.kind = GSWeaponOutcome.KIND_SHOT
	var b := def.tuning as GSWeaponBallistics
	if b != null and shot.kind == GSWeaponOutcome.KIND_SHOT:
		shot.recoil = Vector2(b.recoil_pitch, b.recoil_yaw)
		shot.recoil_signed = true
	_snap()
	_view.on_used(shot)
	_run(seconds if shot.kind != GSWeaponOutcome.KIND_THROW else maxf(seconds, 1.2))


func _reload(def: GSWeaponDef, empty: bool) -> void:
	var seconds := maxf(float(def.reload_ticks) / float(ZeeWeaponPack.TICK_RATE), 0.5)
	_view.on_reload_begin(0 if empty else int(def.magazine / 2), def.magazine, 0.0)
	var frames := int(ceil(seconds * FPS))
	for i in frames:
		_view.on_reload(clampf(float(i + 1) / float(frames), 0.0001, 0.9999))
		_view.advance(STEP)
		_snap()
	_view.on_reload(0.0)
	_run(0.25)


## A draw (deploy fraction 0 to 1) or a holster (1 to 0), as the rig drives it through a switch.
func _deploy(seconds: float, holster: bool) -> void:
	var frames := int(ceil(maxf(seconds, 0.4) * FPS))
	for i in frames:
		var f := clampf(float(i) / float(frames), 0.0, 0.9999)
		_view.on_deploy(1.0 - f if holster else f)
		_view.advance(STEP)
		_snap()
	_view.on_deploy(0.0 if holster else 1.0)
	_run(0.2)


func _inspect() -> void:
	_snap()
	_view.inspect()
	for _i in 8 * FPS:
		_view.advance(STEP)
		_snap()
		if _view.inspect_fraction() >= 1.0:
			break
	_run(0.2)


func _ads() -> void:
	_snap()
	_view.aim(true)
	_run(0.9)
	_view.aim(false)
	_run(0.9)


func _idle() -> void:
	_snap()
	_run(SWAY_SECONDS)


func _run(seconds: float) -> void:
	for _i in int(ceil(seconds * FPS)):
		_view.advance(STEP)
		_snap()


## Reads every drawn part's transform now, one value per track. A track that starts late is backfilled with its first value.
func _snap() -> void:
	var weapon := _view.weapon_node()
	if weapon == null:
		return
	# The camera's frame, not the rig's own: a shot kicks the rig itself, and that motion is the clip.
	var parent := _view.get_parent() as Node3D
	var to_view := parent.global_transform.affine_inverse() if parent != null else Transform3D.IDENTITY
	var to_weapon := weapon.global_transform.affine_inverse()
	_rec.put("weapon", "transform", Sidecar.t7(to_view * weapon.global_transform))
	# The separate magazine model when the gun has one, else the gun's own magazine node.
	var sep: Node3D = _view.get(&"_magazine")
	var mag: Node3D = sep if sep != null else _view._own_magazine()
	if mag != null:
		_rec.put("magazine", "transform", Sidecar.t7(to_weapon * mag.global_transform))
		_rec.put("magazine.visible", "visible", [1.0 if mag.is_visible_in_tree() else 0.0])
		if sep != null:
			_mag_view.append_array(Sidecar.t7(to_view * sep.global_transform))
	var props: Node3D = _view._props
	if props != null:
		for k: Variant in props._nodes:
			var n: Node3D = props._nodes[k]
			if not _props.has(k):
				_props[k] = {"part": String(n.get_meta(&"part", &"")), "shapes": _shapes(n)}
			var at := to_view * n.global_transform
			_rec.put("prop.%d" % k, "transform", Sidecar.t7(at.orthonormalized()))
			_rec.put("prop.%d.scale" % k, "position", [at.basis.get_scale().x, at.basis.get_scale().y, at.basis.get_scale().z])
			_rec.put("prop.%d.visible" % k, "visible", [1.0 if n.is_visible_in_tree() else 0.0], [0.0])
	var arms: ZeeViewArms = _view._arms
	if arms != null and not arms.last_hands.is_empty():
		var to_arms: Transform3D = to_view * arms.global_transform
		for k: String in ["right", "left", "right_shoulder", "left_shoulder"]:
			if arms.last_hands.has(k):
				var p: Vector3 = to_arms * (arms.last_hands[k] as Vector3)
				_rec.put("hand.%s" % k, "position", [p.x, p.y, p.z])
	var punch := _view.view_punch()
	_rec.put("view_punch", "position", [punch.x, punch.y, 0.0])
	_rec.frame_done()


## Where the weapon sits in the hand mount, as ZeeWorldModel's holder places it (the art's world transform, its basis scaled by the pose's share of the hand scale): 12 floats, basis columns then origin.
static func _third_person(art: ZeeWeaponArt) -> Dictionary:
	var rest := art.world_transform()
	rest = Transform3D(rest.basis.scaled(Vector3.ONE * ZeeWeaponArtTable.pose_world_factor(art.pose)), rest.origin)
	var b := rest.basis
	return {"pose": String(art.pose), "rest": [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, rest.origin.x, rest.origin.y, rest.origin.z]}


## The primitive meshes under a built reload part, in the part's space: {kind, size (box x y z; cylinder top, bottom, height; sphere radius, height), at (12 floats), colour, metal, rough, glow}.
static func _shapes(part: Node3D) -> Array:
	var out: Array = []
	var inv := part.global_transform.affine_inverse()
	for m: Node in part.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var shape := {}
		if mi.mesh is BoxMesh:
			var sz := (mi.mesh as BoxMesh).size
			shape = {"kind": "box", "size": [sz.x, sz.y, sz.z]}
		elif mi.mesh is CylinderMesh:
			var c := mi.mesh as CylinderMesh
			shape = {"kind": "cylinder", "size": [c.top_radius, c.bottom_radius, c.height]}
		elif mi.mesh is SphereMesh:
			var sp := mi.mesh as SphereMesh
			shape = {"kind": "sphere", "size": [sp.radius, sp.height]}
		else:
			continue
		var t := inv * mi.global_transform
		var b := t.basis
		shape["at"] = [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, t.origin.x, t.origin.y, t.origin.z]
		var mat := mi.get_active_material(0) as StandardMaterial3D
		if mat != null:
			shape["colour"] = mat.albedo_color.to_html(false)
			shape["metal"] = mat.metallic
			shape["rough"] = mat.roughness
			shape["glow"] = mat.emission.to_html(false) if mat.emission_enabled else ""
		out.append(shape)
	return out
