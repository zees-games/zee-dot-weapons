class_name ZeeAttachmentArt
extends RefCounted

## How a pack draws its attachments: a lookup each pack fills, as [ZeeWeaponArtTable.add_source] does for guns.
## An entry is `{path, hides, aim, zoom}`: the model put on the gun's `socket_<mount>` node with no offset, the gun's nodes it replaces,
## and for an optic `aim` of `&"glass"` (look through its `*_glass` mesh) or `&"scoped"` (the same, with the scope overlay) and the `zoom` it gives.

## name -> Callable(id: StringName) -> Dictionary. A static method's Callable, never a lambda, or the process aborts at exit.
static var _sources: Dictionary = {}
## name -> Callable() -> Array of model paths, for a pack that says which files its attachments draw.
static var _listings: Dictionary = {}


## [param listing], when valid, names every model file the pack's attachments use, so [ZeeWeaponArtTable.model_paths] (and so a game's art sync) carries them.
static func add_source(name: StringName, source: Callable, listing: Callable = Callable()) -> void:
	_sources[name] = source
	if listing.is_valid():
		_listings[name] = listing


static func remove_source(name: StringName) -> void:
	_sources.erase(name)
	_listings.erase(name)


## Every attachment model path the packs name through their listing, sorted and unique.
static func listed_paths() -> Array[String]:
	var seen := {}
	for name: StringName in _listings:
		var listing: Callable = _listings[name]
		if listing.is_valid():
			for path in listing.call():
				seen[String(path)] = true
	var out: Array[String] = []
	for path: String in seen.keys():
		out.append(path)
	out.sort()
	return out


## The first pack's entry for [param id], then this pack's own ([method ZeeWeaponArtTable.attachment_art]), or empty when none draws it.
static func of(id: StringName) -> Dictionary:
	for name: StringName in _sources:
		var source: Callable = _sources[name]
		if source.is_valid():
			var entry: Dictionary = source.call(id)
			if not entry.is_empty():
				return entry
	return ZeeWeaponArtTable.attachment_art(id)


## The node of a gun's model an attachment on [param mount] is parented to.
static func socket_name(mount: StringName) -> StringName:
	return StringName("socket_" + String(mount))
