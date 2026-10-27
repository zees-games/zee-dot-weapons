class_name ZeePackScan
extends RefCounted

## The scan loop every game repeats to find other addons' weapon packs: which folders have a provider, does it load, which defs are kept.
## Games decide which packs they want and what to do with a pack's other rows; this only finds, validates and filters.

## The folders under [param base] that hold [param file], sorted so two ends register in one order.
static func provider_dirs(base: String, file: String) -> PackedStringArray:
	var out := PackedStringArray()

	if not DirAccess.dir_exists_absolute(base):
		return out

	var dirs := DirAccess.get_directories_at(base)
	dirs.sort()

	for dir in dirs:
		var path := base.path_join(dir).path_join(file)

		if ResourceLoader.exists(path) or FileAccess.file_exists(path):
			out.append(dir)

	return out


## The provider script at [param path], or null (and a warning on [param channel]) when it does not load,
## cannot be instantiated or, with [param needs_defs], has no static `weapon_defs()`.
static func load_provider(channel: String, dir: String, path: String, needs_defs: bool = false) -> GDScript:
	var script := load(path) as GDScript

	if script == null or not script.can_instantiate():
		DotLog.warn(channel, "a pack's provider does not load", {"pack": dir, "path": path})
		return null

	if needs_defs and not script.has_method(&"weapon_defs"):
		DotLog.warn(channel, "a weapon pack has no weapon_defs", {"pack": dir})
		return null

	return script


## The defs of [param defs] a game keeps: not in [param excluded] and not in [param taken] (ids already in the catalogue).
static func kept(defs: Array, excluded: Array, taken: Array = []) -> Array[DotWeaponDef]:
	var out: Array[DotWeaponDef] = []

	for def: Variant in defs:
		if def is DotWeaponDef and not excluded.has(String(def.id)) and not taken.has(def.id) and not taken.has(String(def.id)):
			out.append(def)

	return out


## A defs source that hands a provider's own `weapon_defs` through; a source Callable must be a static method, never a lambda.
static func defs_of(types: Dictionary, provider: GDScript) -> Array[DotWeaponDef]:
	return provider.call(&"weapon_defs", types)
