extends Node

## The suite's counters, the check helpers, and the rig builders every section shares.

var _sections_entered: int = 0
var _sections_finished: int = 0
var _checks: int = 0
var _failures: int = 0
var _section: String = ""


## True when [param a] and [param b] hold the same stored values, resources compared by value.
func _same(a: Variant, b: Variant, what: String) -> bool:
	if a is Resource and b is Resource:
		var ra := a as Resource
		var rb := b as Resource
		if ra.get_script() != rb.get_script():
			print("   differs: %s script" % what)
			return false

		for p: Dictionary in ra.get_property_list():
			if not (int(p["usage"]) & PROPERTY_USAGE_STORAGE) or p["name"] == "resource_path":
				continue
			if not _same(ra.get(p["name"]), rb.get(p["name"]), "%s.%s" % [what, p["name"]]):
				return false

		return true

	if a is Dictionary and b is Dictionary:
		var da := a as Dictionary
		var db := b as Dictionary
		if da.size() != db.size():
			print("   differs: %s size" % what)
			return false
		for k: Variant in da:
			if not db.has(k) or not _same(da[k], db[k], "%s[%s]" % [what, k]):
				return false
		return true

	if a is Array and b is Array:
		var aa := a as Array
		var ab := b as Array
		if aa.size() != ab.size():
			print("   differs: %s size" % what)
			return false
		for i in aa.size():
			if not _same(aa[i], ab[i], "%s[%d]" % [what, i]):
				return false
		return true

	if typeof(a) != typeof(b) or a != b:
		print("   differs: %s (%s vs %s)" % [what, str(a), str(b)])
		return false

	return true


func _heard_reloads(role: ZeeWeaponRig.Role, replay: bool) -> Array[StringName]:
	var heard: Array[StringName] = []
	var r := ZeeWeaponRig.new()
	r.role = role
	r.authority = true
	r.tick_rate = ZeeWeaponPack.TICK_RATE
	add_child(r)
	r.setup()
	r.give_everything()
	r.arsenal.select(ZeeWeaponIds.SLOT_PRIMARY, 0)
	r.reload_sound.connect(func(stage: StringName) -> void: heard.append(stage))
	_run_rig(r, 0, 60, 0)
	_run_rig(r, 60, 75, DotWeaponCommand.BUTTON_ATTACK)
	if replay:
		r.begin_replay()
	_run_rig(r, 75, 77, DotWeaponCommand.BUTTON_RELOAD)
	_run_rig(r, 77, 500, 0)
	if replay:
		r.end_replay()
	_cleanup(r)
	return heard


func _make_arsenal() -> DotWeaponArsenal:
	var arsenal := DotWeaponArsenal.new()
	arsenal.catalogue = ZeeWeaponPack.catalogue()
	arsenal.tick_rate = ZeeWeaponPack.TICK_RATE
	arsenal.authority = true
	add_child(arsenal)
	return arsenal


func _make_rig() -> ZeeWeaponRig:
	var rig := ZeeWeaponRig.new()
	rig.role = ZeeWeaponRig.Role.SERVER
	rig.authority = true
	rig.tick_rate = ZeeWeaponPack.TICK_RATE
	add_child(rig)
	return rig


## Runs an arsenal for a range of ticks with one button held, counting the uses.
func _run(arsenal: DotWeaponArsenal, from: int, to: int, buttons: int) -> int:
	var used := 0
	var previous: DotWeaponCommand = null

	for tick in range(from, to):
		var command := DotWeaponCommand.new()
		command.buttons = buttons

		var ctx := DotWeaponContext.make(1, tick, Vector3.ZERO, Vector3.FORWARD)
		ctx.authority = true

		var out := arsenal.simulate_tick(command, ctx, previous)

		if out.used:
			used += 1

		previous = command

	return used


func _first_spread(rig: ZeeWeaponRig, from: int, buttons: int) -> float:
	for tick in range(from, from + 120):
		var command := DotWeaponCommand.new()
		command.buttons = (DotWeaponCommand.BUTTON_ATTACK if tick % 2 == 0 else 0) | buttons
		var outcome := rig.simulate_tick(command, tick)
		if outcome != null and not outcome.shots.is_empty():
			return (outcome.shots[0] as DotShot).spread
	return -1.0


func _run_rig(rig: ZeeWeaponRig, from: int, to: int, buttons: int) -> int:
	var used := 0

	for tick in range(from, to):
		var command := DotWeaponCommand.new()
		command.buttons = buttons

		var ctx := DotWeaponContext.make(1, tick, Vector3.ZERO, Vector3.FORWARD)
		ctx.authority = true

		if rig.simulate_tick(command, tick, ctx).used:
			used += 1

	return used


func _cleanup(node: Node) -> void:
	remove_child(node)
	node.queue_free()


func _why(res: DotResult) -> String:
	return "" if res.ok else res.error.message


func _profile_file(root: String, rel: String, text: String) -> void:
	var path := root.path_join("addons/zee_weapons/weapon").path_join(rel)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _by_id(defs: Array[DotWeaponDef]) -> Dictionary:
	var out := {}
	for d in defs:
		out[String(d.id)] = d
	return out


func _begin(name: String) -> void:
	_section = name
	_sections_entered += 1
	print("")
	print("-- %s" % name)


func _end() -> void:
	_sections_finished += 1


func _check(label: String, passed: bool) -> void:
	_checks += 1

	if passed:
		print("   ok    %s" % label)
		return

	_failures += 1
	print("   FAIL  %s" % label)


## A check that only prints when it fails. For the ones run in a loop, where twenty-seven
## lines of "ok" buries the one line anybody needs to read.
func _check_quiet(label: String, passed: bool) -> void:
	_checks += 1

	if passed:
		return

	_failures += 1
	print("   FAIL  %s" % label)
