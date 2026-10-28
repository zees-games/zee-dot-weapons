class_name ZeeAttachmentArt
extends RefCounted

## How a pack draws its attachments: a lookup each pack fills, as [ZeeWeaponArtTable.add_source] does for guns.
## An entry is `{path, hides, aim, zoom}`: the model put on the gun's `socket_<mount>` node with no offset, the gun's nodes it replaces,
## and for an optic `aim` of `&"glass"` (look through its `*_glass` mesh) or `&"scoped"` (the same, with the scope overlay) and the `zoom` it gives.

## name -> Callable(id: StringName) -> Dictionary. A static method's Callable, never a lambda, or the process aborts at exit.
static var _sources: Dictionary = {}


static func add_source(name: StringName, source: Callable) -> void:
	_sources[name] = source


static func remove_source(name: StringName) -> void:
	_sources.erase(name)


## The first pack's entry for [param id], or empty when no pack draws it.
static func of(id: StringName) -> Dictionary:
	for name: StringName in _sources:
		var source: Callable = _sources[name]
		if source.is_valid():
			var entry: Dictionary = source.call(id)
			if not entry.is_empty():
				return entry
	return {}


## The node of a gun's model an attachment on [param mount] is parented to.
static func socket_name(mount: StringName) -> StringName:
	return StringName("socket_" + String(mount))
