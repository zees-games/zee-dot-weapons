class_name ZeeArtProvider
extends RefCounted

## What the view classes ask of a weapon pack's art, so a second pack can reuse them: they call this instead of naming
## [ZeeModelCache], [ZeeWeaponArtTable] and [ZeeWeaponPack] directly. The default answers from zee's own art and catalogue; a
## pack subclasses it and assigns it to [member ZeeWorldModel.art_provider]. Everything here is a pure lookup by art row or
## weapon id, so a provider needs no node and no tree.


## A fresh model for [param path], or null when it is missing.
func instantiate(path: String) -> Node3D:
	return ZeeModelCache.instantiate(path)


## How far along [param forward] the model's muzzle is, in metres, measured from the mesh.
func muzzle_distance(path: String, forward: Vector3) -> float:
	return ZeeModelCache.muzzle_distance(path, forward)


## The third-person size of [param pose]'s weapon relative to the figure's hand scale.
func pose_world_factor(pose: StringName) -> float:
	return ZeeWeaponArtTable.pose_world_factor(pose)


## Whether [param pose] is held with both hands.
func pose_two_handed(pose: StringName) -> bool:
	return ZeeWeaponArtTable.pose_two_handed(pose)


## [offset, rotation in degrees] of [param pose]'s sprint carry, third person.
func sprint_world(pose: StringName) -> Array:
	return ZeeWeaponArtTable.sprint_world(pose)


## The document for weapon [param id], or null.
func def_of(id: StringName) -> DotWeaponDef:
	return ZeeWeaponPack.catalogue().get_def(id)


## Ticks per second the pack's durations are authored in.
func tick_rate() -> int:
	return ZeeWeaponPack.TICK_RATE
