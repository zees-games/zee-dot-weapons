class_name ZeeWeaponProfiles
extends RefCounted

## Shim over [DotWeaponProfiles]' overlay (profiles laid over code-built defs); kept for the old name.
## zed-dot-weapons and other packs may call [DotWeaponProfiles] directly.


static func profile_set(addon: String, game: String = "", pack_root: String = "", base_roots: PackedStringArray = PackedStringArray(), layer: Variant = null) -> DotProfileSet:
	return DotWeaponProfiles.overlay_set(addon, game, pack_root, base_roots, layer)


static func tune(defs: Array[DotWeaponDef], set: DotProfileSet) -> PackedStringArray:
	return DotWeaponProfiles.tune(defs, set)


static func file_flat(p: DotProfile) -> Dictionary:
	return DotWeaponProfiles.file_flat(p)


static func apply_flat(def: DotWeaponDef, flat: Dictionary) -> void:
	DotWeaponProfiles.apply_flat(def, flat)


static func flat_of(def: DotWeaponDef) -> Dictionary:
	return DotWeaponProfiles.flat_of(def)


static func to_yaml(def: DotWeaponDef, addon_title: String) -> String:
	return DotWeaponProfiles.to_yaml(def, addon_title)


static func profile_path(addon: String, id: String, root: String = "res://cfg") -> String:
	return DotWeaponProfiles.profile_path(addon, id, root)


static func upgraded(def: DotWeaponDef, ids: Array, set: DotProfileSet) -> DotResult:
	return DotWeaponProfiles.upgraded(def, ids, set)
