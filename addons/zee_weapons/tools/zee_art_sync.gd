extends SceneTree
## Copies the weapon art a game needs into the game, exactly the models
## [method ZeeWeaponArtTable.model_paths] names, or checks that it is all there.
##
## Run through `zee-dot-weapons/tools/sync-art.sh <game-dir>`, which finds the source
## directories from the game's own `addons/` links. By hand:
##
##   godot --headless --path <game> --script res://addons/zee_weapons/tools/zee_art_sync.gd \
##       -- --from <repo-with-assets> [--from <another>] [--check] [--arms]
##
## [b]Why a game vendors the art at all[/b]: a pack is the game's tracked tree with `addons/`
## left out, and its imported outputs come from the game's own import, while the art lives in
## the addon's repository root (`assets/`), outside `addons/zee_weapons/`. So a game that
## does not copy it ships none, and the failure is one WARN per model in production. The
## copy stays, and this tool makes it a derived thing instead of a hand-made one: the list is
## the table's, a second pack's art (zed) is in it once registered, and `--check` is the CI form.
##
## Exits 1 when a named model is in no source, or (with `--check`) is missing or differs from
## its source. The folders' licences and textures come along, because a model is no use
## without its texture and the art may not travel without its licence.

const SIDECAR_SKIP := [".glb", ".glb.import"]

var _sources: Array[String] = []
var _check_only := false
var _with_arms := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0

	while i < args.size():
		match args[i]:
			"--from":
				i += 1
				_sources.append(args[i].rstrip("/"))
			"--check":
				_check_only = true
			"--arms":
				_with_arms = true
		i += 1

	_install_second_pack()

	if _sources.is_empty():
		printerr("zee_art_sync: at least one --from <dir containing assets/> is needed")
		quit(2)
		return

	quit(_run())


## zed's art is in the table only once it registers; named by the class list, never by identifier,
## because a game without zed must still parse this script.
func _install_second_pack() -> void:
	for entry in ProjectSettings.get_global_class_list():
		if entry["class"] == &"ZedWeaponPack":
			(load(entry["path"]) as GDScript).call(&"install")


func _run() -> int:
	var problems := 0
	var copied := 0
	var dirs := {}

	for path in ZeeWeaponArtTable.model_paths(_with_arms):
		var rel := path.trim_prefix("res://")
		var src := _find(rel)

		if src == "":
			printerr("no source has %s" % rel)
			problems += 1
			continue

		dirs[rel.get_base_dir()] = src.trim_suffix("/" + rel)

		for suffix in ["", ".import"]:
			var result := _sync_file(src + suffix, "res://" + rel + suffix)
			problems += 1 if result < 0 else 0
			copied += 1 if result > 0 else 0

	# Textures and licences beside the models: everything in a folder but the models themselves.
	for dir: String in dirs:
		var top := dir.split("/")[0] + "/" + dir.split("/")[1]
		var root: String = dirs[dir]

		for file in _files_under(root + "/" + top):
			if SIDECAR_SKIP.any(func(ext: String) -> bool: return file.ends_with(ext)):
				continue

			var rel_file := file.trim_prefix(root + "/")
			var result := _sync_file(file, "res://" + rel_file)
			problems += 1 if result < 0 else 0
			copied += 1 if result > 0 else 0

	var verb := "differ or are missing" if _check_only else "copied"
	print("zee_art_sync: %d file(s) %s, %d problem(s), %d model(s) named" % [
		copied, verb, problems, ZeeWeaponArtTable.model_paths(_with_arms).size(),
	])
	return 0 if problems == 0 and (not _check_only or copied == 0) else 1


## The first source holding [param rel] (a path under the project root), or "".
func _find(rel: String) -> String:
	for root in _sources:
		if FileAccess.file_exists(root + "/" + rel):
			return root + "/" + rel
	return ""


## 1 when [param to] was written (or, in check mode, found different), 0 when already
## identical, -1 when the source cannot be read.
func _sync_file(from: String, to: String) -> int:
	if not FileAccess.file_exists(from):
		# A model with no .import sidecar in the source is a model that will not load.
		printerr("source file missing: %s" % from)
		return -1

	if FileAccess.file_exists(to) and _same(from, to):
		return 0

	if _check_only:
		printerr("%s %s" % ["differs:" if FileAccess.file_exists(to) else "missing:", to])
		return 1

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(to.get_base_dir()))

	if DirAccess.copy_absolute(from, ProjectSettings.globalize_path(to)) != OK:
		printerr("could not copy %s" % from)
		return -1

	print("  %s" % to)
	return 1


## Equal bytes; for a `.import` marker, equal but for its `uid=` line. Each project's editor
## mints its own uid for a file it imported first, and overwriting it would churn every
## scene that references the file by uid for no change anyone can see.
func _same(a: String, b: String) -> bool:
	if FileAccess.get_md5(a) == FileAccess.get_md5(b):
		return true

	if not a.ends_with(".import"):
		return false

	return _without_uid(a) == _without_uid(b)


func _without_uid(path: String) -> String:
	var kept := PackedStringArray()

	for line in FileAccess.get_file_as_string(path).split("\n"):
		if not line.begins_with("uid="):
			kept.append(line)

	return "\n".join(kept)


func _files_under(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)

	if d == null:
		return out

	for sub in d.get_directories():
		out.append_array(_files_under(dir + "/" + sub))

	for f in d.get_files():
		out.append(dir + "/" + f)

	return out
