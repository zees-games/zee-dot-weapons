extends RefCounted

## The model files a set of art entries names, and whether they resolve. No `class_name`: [ZeeWeaponArtTable] preloads it by path.

const Consts := preload("zee_weapon_art_table_paths.gd")


static func model_paths(arts: Array, with_arms: bool) -> Array[String]:
	var seen := {}

	for art: ZeeWeaponArt in arts:
		for path in paths_of(art):
			if path != "":
				seen[path] = true

	if with_arms:
		seen[Consts.ARMS_MODEL] = true
		seen[Consts.RIGGED_ARMS_MODEL] = true

	var out: Array[String] = []

	for path: String in seen.keys():
		out.append(path)

	out.sort()
	return out


## Fails naming every path in [param paths] that does not resolve, because the usual cause is a whole directory that did not ship.
static func missing_result(paths: Array[String]) -> DotResult:
	var missing: Array[String] = []

	for path in paths:
		if not ResourceLoader.exists(ZeeModelCache.resolve(path)):
			missing.append(path)

	if missing.is_empty():
		return DotResult.success(null)

	return DotResult.fail(
		DotError.CODE_IO,
		"%d model(s) are missing: %s" % [missing.size(), ", ".join(missing)]
	)


## Every path one entry refers to: the weapon, its magazine and its attachments.
static func paths_of(art: ZeeWeaponArt) -> Array[String]:
	var out: Array[String] = []

	if art.has_model():
		out.append(art.model_path)

	if art.magazine_path != "":
		out.append(art.magazine_path)

	for entry in art.attachments:
		out.append(str(entry.get("path", "")))

	return out
