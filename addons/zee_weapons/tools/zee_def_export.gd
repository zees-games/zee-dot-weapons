class_name ZeeDefExport
extends RefCounted

## Writes the pack's weapons as Workshop files: one [DotWeaponDef] `.tres` per weapon and the
## `provides.json` that lists them (the contract is dot-cloud's docs/workshop.md).
##
## [b]The code table stays the source of truth.[/b] The `.tres` files are generated from
## [method ZeeWeaponPack.weapons], never hand-edited, so the two cannot drift by an author
## forgetting one; the suite loads every file back and compares it with the code row, which is
## what notices when somebody changes a builder and forgets to run this. Run it with
## `tools/export-defs.sh`.
##
## Only this pack's own rows are written (not a second pack's added through [code]add_source[/code]):
## a pack ships the weapons it owns.

## Where the pack's art sits relative to the pack root. The art tree is `assets/`, so the root
## is the pack itself.
const ASSET_ROOT := "."

const CATEGORIES: Array[Dictionary] = [
	{"slot": 1, "id": "melee", "name": "Melee"},
	{"slot": 2, "id": "sidearm", "name": "Sidearms"},
	{"slot": 3, "id": "primary", "name": "Primary"},
	{"slot": 4, "id": "heavy", "name": "Heavy"},
	{"slot": 5, "id": "thrown", "name": "Thrown"},
]


## This pack's own weapons, built from code with no second pack mixed in.
static func own_weapons() -> Array[DotWeaponDef]:
	var types := ZeeWeaponDamage.table()
	var out: Array[DotWeaponDef] = []

	for def in ZeeWeaponPack.weapons(types, false):
		if ZeeWeaponIds.all().has(def.id):
			out.append(def)

	return out


static func category_for(slot: int) -> String:
	for c in CATEGORIES:
		if c["slot"] == slot:
			return c["id"]

	return ""


## The `provides.json` document for [param defs].
static func provides(defs: Array[DotWeaponDef]) -> Dictionary:
	var cats: Array = []
	for c in CATEGORIES:
		cats.append({"id": c["id"], "name": c["name"]})

	var entries: Array = []
	for def in defs:
		entries.append({
			"kind": "weapon",
			"id": String(def.id),
			"name": def.name_or_id(),
			"def": "weapons/%s.tres" % String(def.id),
			"slot": def.slot,
			"category": category_for(def.slot),
			"tags": Array(def.tags).map(func(t: StringName) -> String: return String(t)),
			"meta": {"asset_root": ASSET_ROOT},
		})

	return {
		"schema": 1,
		"title": "Zee Weapons",
		"kinds": ["weapon"],
		"games": "*",
		"categories": cats,
		"entries": entries,
	}


## Writes everything under [param root] (a filesystem or `res://` directory). Returns a
## [DotResult] whose value is the number of definitions written.
static func export_to(root: String) -> DotResult:
	var dir := root.path_join("weapons")
	var made := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(dir)
	)
	if made != OK:
		return DotResult.fail(DotError.CODE_IO, "Cannot create %s (error %d)." % [dir, made])

	var defs := own_weapons()

	for def in defs:
		var path := dir.path_join("%s.tres" % String(def.id))
		var saved := ResourceSaver.save(def, path)
		if saved != OK:
			return DotResult.fail(DotError.CODE_IO, "Cannot save %s (error %d)." % [path, saved])

	var cfg := write_cfg(root, ZeeWeaponPack.ADDON, "Zee Weapons", defs)
	if not cfg.ok:
		return cfg

	var json_path := root.path_join("provides.json")
	var f := FileAccess.open(json_path, FileAccess.WRITE)
	if f == null:
		return DotResult.fail(DotError.CODE_IO, "Cannot write %s." % json_path)

	f.store_string(JSON.stringify(provides(defs), "\t", false) + "\n")
	f.close()
	return DotResult.success(defs.size())


## Writes `cfg/addons/<addon>/weapon/<id>.yml` for [param defs] under [param root] from the builders'
## numbers (never from a server's cfg), and copies the hand-written upgrade folders along when
## [param root] is not the project. A weapon that has a folder in the project's cfg keeps its folder form.
static func write_cfg(root: String, addon: String, title: String, defs: Array[DotWeaponDef]) -> DotResult:
	var rel := "cfg/addons/%s/weapon" % addon
	var from := "res://".path_join(rel)
	var to := root.path_join(rel)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(to))
	for def in defs:
		var id := String(def.id)
		var folder := DirAccess.dir_exists_absolute(from.path_join(id))
		var dir := to.path_join(id) if folder else to
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var f := FileAccess.open(dir.path_join("%s.yml" % id), FileAccess.WRITE)
		if f == null:
			return DotResult.fail(DotError.CODE_IO, "Cannot write %s profile." % id)
		f.store_string(DotWeaponProfiles.to_yaml(def, title))
		f.close()
		if folder and to != from and DirAccess.dir_exists_absolute(from.path_join(id).path_join("upgrades")):
			var ups := to.path_join(id).path_join("upgrades")
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ups))
			for u in DirAccess.get_files_at(from.path_join(id).path_join("upgrades")):
				if u.get_extension() == "yml":
					var o := FileAccess.open(ups.path_join(u), FileAccess.WRITE)
					if o == null:
						return DotResult.fail(DotError.CODE_IO, "Cannot write upgrade %s." % u)
					o.store_string(FileAccess.get_file_as_string(from.path_join(id).path_join("upgrades").path_join(u)))
					o.close()
	return DotResult.success(defs.size())
