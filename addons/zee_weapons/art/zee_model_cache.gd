class_name ZeeModelCache
extends RefCounted

## Loads a weapon mesh once, measures it once, and hands out copies.
##
## [b]Why a cache at all.[/b] Thirty players holding the same rifle is thirty
## instances of one [PackedScene], not thirty loads of one file. `load()` is cached by
## the engine, so the loading half of this is a convenience; the measuring half is not,
## and that is the part that earns the file. Walking a scene tree to merge mesh bounding
## boxes costs an instantiate, and doing it every time somebody switches weapons is a
## hitch on every switch.
##
## [b]Measuring is how the muzzle is found.[/b] The alternative is a hand-authored
## offset per weapon, and eighteen hand-authored offsets are eighteen chances to be
## quietly wrong — including on `blaster-e`, whose mesh origin is at the stock rather
## than at the centre, so the offset that is correct for the other seventeen puts its
## muzzle somewhere behind the player's ear. A measurement cannot drift from the model
## it measured.
##
## [b]Nothing here is called on a dedicated server.[/b] A server resolves weapons,
## damage and hit registration without ever asking what a weapon looks like; if this
## file is reached in a headless build, something has asked a simulation question of
## the art layer.

const CHANNEL := "zee.models"

## Path -> PackedScene.
static var _scenes: Dictionary = {}

## Path -> AABB in the model's own space.
static var _bounds: Dictionary = {}

## Paths already reported as missing, so a model that is not there is logged once
## rather than once per frame for as long as somebody is holding it.
static var _complained: Dictionary = {}

## Where `res://assets/` is on this machine. `res://` everywhere but inside a mounted pack.
static var _asset_root: String = "res://"


## Puts the art somewhere other than `res://assets/`, for a game delivered as a pack.
##
## [b]Every path in [ZeeWeaponArtTable] and [ZeeViewArms] says `res://assets/…`, and in a
## delivered game that is the one place the art is not.[/b] The pack vendors it beside its
## own files and gs-cloud mounts those under `res://gs_cloud/<id>/<version>/`, so a
## client shell — which carries this addon and no art — resolves every weapon to nothing
## and the WARN below says "the weapon will be invisible" for all twenty-seven. The table
## is not rewritten because it is the one file that names art and must keep reading the same
## in a game that builds the art in. Called by the game when it loads, with its mount root;
## `res://` puts it back, and a game that sets it clears it when it goes, because a static
## outlives the game in a shell that switches to another one.
static func set_asset_root(root: String) -> void:
	_asset_root = root if root.ends_with("/") else root + "/"
	_scenes.clear()
	_bounds.clear()
	_complained.clear()


## [param path], under [method set_asset_root] when it names the shipped art. A path that
## is already under the root, or names anything else, comes back unchanged.
static func resolve(path: String) -> String:
	if _asset_root == "res://" or not path.begins_with("res://assets/"):
		return path

	return _asset_root + path.trim_prefix("res://")


## The scene at [param path], loaded at most once.
static func scene(path: String) -> GSResult:
	if path == "":
		return GSResult.fail(GSError.CODE_INVALID, "No model path.")

	if _scenes.has(path):
		return GSResult.success(_scenes[path])

	var real := resolve(path)

	if not real.begins_with("res://") and not ResourceLoader.exists(real) and real.get_extension().to_lower() in ["glb", "gltf"] and FileAccess.file_exists(real):
		return _scene_from_file(path, real)

	if not ResourceLoader.exists(real):
		return GSResult.fail(
			GSError.CODE_IO,
			"No model at %s. A weapon delivered in a content pack needs that pack " % real
			+ "mounted before it can be drawn."
		)

	# `.deps` (a CI runner's clones of the packs) is `.gdignore`d, so the engine never imported the glb and
	# `load` has nothing to open; read the file itself.
	var loaded: Variant = _pack_glb(ProjectSettings.globalize_path(real)) if _unimported(real) else load(real)

	if not (loaded is PackedScene):
		return GSResult.fail(
			GSError.CODE_INVALID, "%s is not a scene." % path
		)

	_scenes[path] = loaded
	return GSResult.success(loaded)


## A glb that lives outside the project (a weapon pack only linked into `addons/`, its art in its own checkout), read at run time
## and packed, so the rest of the cache treats it like any other scene. There is no import step, so a stale `.godot` cache cannot
## show an old model; an exported game never reaches this, a mounted pack's art is under `res://`.
static func _scene_from_file(path: String, file: String) -> GSResult:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()

	if doc.append_from_file(file, state) != OK:
		return GSResult.fail(GSError.CODE_INVALID, "%s is not a readable glb." % file)

	var root := doc.generate_scene(state)

	if root == null:
		return GSResult.fail(GSError.CODE_INVALID, "%s has no scene." % file)

	var packed := PackedScene.new()
	_own_children(root, root)

	if packed.pack(root) != OK:
		root.free()
		return GSResult.fail(GSError.CODE_INVALID, "%s could not be packed." % file)

	root.free()
	_scenes[path] = packed
	return GSResult.success(packed)


## Every descendant owned by [param root], which [method PackedScene.pack] keeps only for owned nodes.
static func _own_children(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_own_children(child, root)


## A [PackedScene] of the glb at the absolute [param file], read at run time, or null.
## A glb whose import the engine never made (a `.deps` clone, or a link into one): the imported scene its
## `.import` names is not on disk.
static func _unimported(real: String) -> bool:
	if real.begins_with("res://.deps/"):
		return true

	if real.get_extension().to_lower() not in ["glb", "gltf"]:
		return false

	var cfg := ConfigFile.new()

	if cfg.load(real + ".import") != OK:
		return false

	return not FileAccess.file_exists(String(cfg.get_value("remap", "path", "")))


static func _pack_glb(file: String) -> PackedScene:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(file, state)
	if err != OK:
		GSLog.warn(CHANNEL, "could not read a glb from disk", {"path": file, "error": err})
		return null
	var root := doc.generate_scene(state)
	if root == null:
		GSLog.warn(CHANNEL, "a glb read from disk made no scene", {"path": file})
		return null
	_own_all(root, root)
	var packed := PackedScene.new()
	var ok := packed.pack(root) == OK
	root.free()
	return packed if ok else null


static func _own_all(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_own_all(child, root)


## Loads every scene in [param paths] into the cache, so the first equip of each does not read
## its file (90-110 ms in the middle of a fight). Returns how many are cached.
static func warm(paths: Array) -> int:
	var cached := 0
	for path: Variant in paths:
		if scene(str(path)).ok:
			cached += 1
	return cached


## A fresh instance of the model at [param path], or null.
##
## [b]Returns null rather than failing loudly for a missing model[/b], because a missing
## mesh must not stop a weapon from working. The gun still fires, still costs
## ammunition and still kills; it is invisible, which is a visual bug and not a
## simulation one. It is logged once per path, at WARN, because somebody should
## eventually look.
static func instantiate(path: String) -> Node3D:
	var res := scene(path)

	if not res.ok:
		if not _complained.has(path):
			_complained[path] = true
			GSLog.warn(
				CHANNEL,
				"could not load a weapon model; the weapon will be invisible",
				{"path": path, "why": res.error.message}
			)
		return null

	var made: Node = (res.value as PackedScene).instantiate()

	if made is Node3D:
		return made

	# A .glb always instantiates as a Node3D. A .tscn a game substituted might not, and
	# adding a Control to a 3D rig is a crash several frames later rather than here.
	made.queue_free()
	GSLog.warn(
		CHANNEL, "a weapon model is not a Node3D and was discarded", {"path": path}
	)
	return null


## The merged bounding box of every mesh in the model, in the model's own space.
##
## Measured once per path. An empty box for a model that could not be loaded, which is
## the right answer: no mesh, no bounds, and a muzzle at the origin.
static func bounds(path: String) -> AABB:
	if _bounds.has(path):
		return _bounds[path]

	var box := AABB()
	var node := instantiate(path)

	if node != null:
		var boxes: Array[AABB] = []
		_collect_bounds(node, Transform3D.IDENTITY, boxes)
		for i in range(boxes.size()):
			box = boxes[i] if i == 0 else box.merge(boxes[i])
		node.queue_free()

	_bounds[path] = box
	return box


## Metres from the model origin to the far end of the mesh along [param forward].
##
## The end of the barrel on every model in this kit. Uses the bounding box corner that
## is furthest along the axis, so it is correct for a mesh centred on its origin and for
## one whose origin sits at the stock — which this kit contains one of.
static func muzzle_distance(path: String, forward: Vector3) -> float:
	var box := bounds(path)

	if box.size.length_squared() <= 0.0:
		return 0.0

	var axis := forward.normalized()
	var best := -INF

	for i in range(8):
		var corner := box.get_endpoint(i)
		best = maxf(best, corner.dot(axis))

	return maxf(0.0, best)


## Drops everything. For a test, and for a game unmounting content it will not remount.
static func clear() -> void:
	_scenes.clear()
	_bounds.clear()
	_complained.clear()


## How many models are held. For a console command and the self-test.
static func describe() -> Dictionary:
	return {
		"scenes": _scenes.keys().size(),
		"measured": _bounds.keys().size(),
		"missing": _complained.keys().size(),
	}


## Every mesh's bounding box, each already in the root's space.
##
## [b]Collected into a list and merged by the caller rather than merged as it goes.[/b]
## [method AABB.merge] with a default-constructed box does not give the other box back —
## it gives a box stretched to include the origin — so a model sitting entirely to one
## side of its origin measures as reaching the origin, and its muzzle comes out at the
## wrong end. Starting from the first real box instead is the whole fix, and it needs
## the boxes in hand to know which one is first.
static func _collect_bounds(node: Node, at: Transform3D, into: Array[AABB]) -> void:
	var here := at

	if node is Node3D:
		here = at * (node as Node3D).transform

	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			into.append(here * mesh.get_aabb())

	for child in node.get_children():
		_collect_bounds(child, here, into)
