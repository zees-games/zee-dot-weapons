class_name ZeeArtDress
extends RefCounted

## Gives a stand-in [ZeeWeaponArt] another pack's model and hold from that pack's art row
## (`{model, muzzle, motion, view: {hold, rot, scale, aim, zoom, scoped, iron, sight}}`, `sight: "red_dot"` for an optic); aimed, the model's own sight is used. The hip hold is a layer of its own
## (`view_offset`, `view_rotation`, `view_scale`) that a sprint or lowered pose blends over in [ZeeWeaponPose]; nothing here animates.

const SIGHT_RELIEF := 0.32
## The depth the view model's poses are authored at ([constant ZeeViewModel.REFERENCE_DEPTH]): a hold written nearer is moved out to it
## with its offsets and size scaled by the same ratio, which looks identical on a 90-degree lens and keeps the place under a narrower hands lens.
const AUTHORED_DEPTH := 0.55

## Applies [param row] to [param art]; a row with no readable model changes nothing.
static func apply(art: ZeeWeaponArt, row: Dictionary) -> void:
	var model := str(row.get("model", ""))
	if model == "" or not ResourceLoader.exists(model):
		return
	var view: Dictionary = row.get("view", {})
	var motion := str(row.get("motion", "gun"))
	art.model_path = model
	art.magazine_path = ""
	art.attachments = []
	art.reload = (row.get("reload", {}) as Dictionary).duplicate(true)

	# A melee model stands along +Y and a thrown one has no front: the stand-in's carry stays.
	if motion != "gun":
		art.model_forward = Vector3.UP if motion == "melee" else art.model_forward
		return

	art.model_forward = Vector3.FORWARD
	art.muzzle_distance = float(row.get("muzzle", 0.0))
	art.muzzle_offset = Vector3.ZERO
	_sockets(art, row)
	art.ejects = false
	# The model's own sight is aimed down, nothing built over it; the built ring and post only when the row asks
	# (`iron: true`) or the model has neither a sight nor a written `aim`.
	art.sight_own = true
	art.iron_sight = bool(view.get("iron", not view.has("aim")))
	art.sight_red_dot = str(view.get("sight", "")) == "red_dot"
	art.aim_eye_relief = SIGHT_RELIEF
	art.world_offset = Vector3.ZERO
	art.world_rotation = Vector3.ZERO
	art.world_scale = 1.0
	art.aim_rotation = Vector3.ZERO
	art.view_scale = float(view.get("scale", 1.0))
	art.view_rotation = view.get("rot", Vector3.ZERO)

	if view.has("hold"):
		var hold: Vector3 = view["hold"]
		var ratio := AUTHORED_DEPTH / maxf(absf(hold.z), 0.1)
		art.view_offset = Vector3(hold.x * ratio, hold.y * ratio, -AUTHORED_DEPTH)
		art.view_scale *= ratio

	# The pack measures its aim hold at full size as `(0, 0, -relief) - sight`; a gun drawn smaller has its
	# sight proportionally nearer the grip, so the sight point is scaled and the hold derived again.
	if view.has("aim"):
		var aim: Vector3 = view["aim"]
		var sight := Vector3(-aim.x, -aim.y, -SIGHT_RELIEF - aim.z) * art.view_scale
		art.aim_offset = Vector3(-sight.x, -sight.y, -SIGHT_RELIEF - sight.z)

	if view.has("zoom"):
		art.aim_zoom = float(view["zoom"])

	art.aim_scoped = bool(view.get("scoped", false))


## A row's declared sockets (model space, 3-number arrays or vectors) and hand fractions, where the mesh bounds would be measured.
static func _sockets(art: ZeeWeaponArt, row: Dictionary) -> void:
	for key: String in ["grip_socket", "muzzle_socket", "support_grip"]:
		var v: Variant = row.get(key)
		if v is Array and (v as Array).size() == 3:
			art.set(key, Vector3(float(v[0]), float(v[1]), float(v[2])))
		elif v is Vector3:
			art.set(key, v)

	for key: String in ["fore_along", "fore_up", "grip_along", "grip_up", "hand_scale"]:
		if row.has(key):
			art.set(key, float(row[key]))
