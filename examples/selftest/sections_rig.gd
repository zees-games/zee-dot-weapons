extends "res://examples/selftest/sections_content.gd"

## Selftest sections: replication, the rig, tick rates, aiming rules, input, profiles.


func _net() -> void:
	_begin("replication")

	var specs := ZeeWeaponNet.all_specs()
	_check("seven replicated properties", specs.size() == 7)

	var names := ZeeWeaponNet.properties()
	_check("the slot comes from dot-weapon", names.has(&"net_slot"))
	_check("the fire counter is this pack's", names.has(&"net_fire_seq"))

	var public := 0
	for spec in specs:
		if not bool(spec["owner_only"]):
			public += 1

	_check(
		"the magazine and the reserve stay owner-only",
		public == 5 and specs.size() - public == 2
	)

	_check("a carrier costs under 40 bits", ZeeWeaponNet.estimated_bits() < 40)

	# The wrap is the whole reason `uses_between` exists: a plain subtraction goes
	# negative every sixteen shots and a weapon goes silent for a snapshot.
	_check("nothing happened", ZeeWeaponNet.uses_between(4, 4) == 0)
	_check("three shots", ZeeWeaponNet.uses_between(4, 7) == 3)
	_check(
		"and three more across the wrap",
		ZeeWeaponNet.uses_between(14, 1) == 3
	)
	_check(
		"a full lap reads as no shots, which is the honest answer",
		ZeeWeaponNet.uses_between(5, 5) == 0
	)

	# Kinds round-trip, and an unknown one becomes a shot rather than nothing: a watcher
	# seeing the wrong animation beats a watcher seeing none.
	for kind in [
		DotWeaponOutcome.KIND_SHOT, DotWeaponOutcome.KIND_SWING,
		DotWeaponOutcome.KIND_SPAWN, DotWeaponOutcome.KIND_BEAM,
		DotWeaponOutcome.KIND_THROW,
	]:
		_check_quiet(
			"%s survives the wire" % String(kind),
			ZeeWeaponNet.kind_name(ZeeWeaponNet.kind_number(kind)) == kind
		)

	_check(
		"a kind this pack has never heard of travels as a shot",
		ZeeWeaponNet.kind_number(&"grappling_hook") == ZeeWeaponNet.KIND_SHOT
	)

	_check(
		"every kind number fits the field",
		ZeeWeaponNet.KIND_THROW < (1 << ZeeWeaponNet.FIRE_KIND_BITS)
	)

	_end()


func _rig() -> void:
	_begin("the rig")

	var rig := _make_rig()
	var res := rig.setup()
	_check("a headless rig sets up: %s" % _why(res), res.ok)

	var given := rig.give_everything()
	_check("every weapon in the pack can be given", given == 27)
	# Twenty-seven given, five carried: a slot holds one weapon, so each `give` in a
	# slot replaces the last. That is dot-weapon's rule and not a bug here, but it is
	# exactly the sort of thing a reader assumes the other way round.
	_check(
		"and five are carried, because a slot holds one weapon",
		rig.arsenal.slots().size() == 5
	)

	_check("something is in hand", rig.current_def() != null)
	_check("and it has art", rig.current_art() != null)

	# A use goes through the arsenal and comes back out.
	rig.arsenal.select(ZeeWeaponIds.SLOT_PRIMARY, 0)
	_run_rig(rig, 0, 60, 0)

	var before := rig.fire_seq
	_run_rig(rig, 60, 90, DotWeaponCommand.BUTTON_ATTACK)
	_check("firing advances the replication counter", rig.fire_seq > before)

	# A bash is the alt-fire the arsenal has no path for. An Array, not an int: a lambda captures locals by value,
	# so a counter bumped in a handler stays zero outside it.
	var bashes: Array[int] = []
	rig.bashed.connect(func(_outcome: DotWeaponOutcome) -> void: bashes.append(1))
	_run_rig(rig, 200, 204, DotWeaponCommand.BUTTON_ALT)
	_check("the alt-fire bashes", bashes.size() == 1)

	# And it has its own cooldown, so holding it does not swing every tick.
	_run_rig(rig, 204, 240, DotWeaponCommand.BUTTON_ALT)
	_check("holding it does not swing every tick", bashes.size() < 4)

	# A reload is heard: out when it starts, in when it ends — on the player's own machine,
	# never on a server, never in a replay. An Array for the reason the bash count is one.
	var local: Array[StringName] = _heard_reloads(ZeeWeaponRig.Role.LOCAL, false)
	_check(
		"a reload is heard, out then in (%s)" % ", ".join(local),
		local == [ZeeWeaponSound.RELOAD_OUT, ZeeWeaponSound.RELOAD_IN]
	)
	_check("but not on a server", (_heard_reloads(ZeeWeaponRig.Role.SERVER, false) as Array).is_empty())
	_check("and not in a replay", (_heard_reloads(ZeeWeaponRig.Role.LOCAL, true) as Array).is_empty())

	_rig_art_override(rig)
	_rig_reload_motion()
	_rig_world_attachments()

	_cleanup(rig)
	_end()


## A rig hands its world model the arsenal's attachment catalogue, so a replicated code can be decoded.
func _rig_world_attachments() -> void:
	var world := ZeeWorldModel.new()
	add_child(world)
	var rig := ZeeWeaponRig.new()
	rig.role = ZeeWeaponRig.Role.LOCAL
	rig.tick_rate = ZeeWeaponPack.TICK_RATE
	rig.world_model_ref = DotNodeRef.of_path(world.get_path())
	add_child(rig)
	rig.setup()
	var catalogue := DotWeaponAttachments.new()
	rig.arsenal.attachments = catalogue
	rig.give(ZeeWeaponIds.PISTOL)
	rig.arsenal.select(rig.arsenal.catalogue.get_def(ZeeWeaponIds.PISTOL).slot, 0)
	_run_rig(rig, 1, 3, 0)
	_check("the rig's world model decodes against the arsenal's attachments", world.attachments == catalogue)
	_cleanup(rig)
	_cleanup(world)


func _rig_reload_motion() -> void:
	# The reload motion spans the profile's whole reload (a per-round one is the start plus a round
	# time per missing round) and its keys end at the rest pose.
	var timing := ZeeWeaponRig.new()
	timing.tick_rate = ZeeWeaponPack.TICK_RATE
	add_child(timing)
	timing.setup()
	var drift: PackedStringArray = []
	var unrested: PackedStringArray = []
	for def in ZeeWeaponPack.weapons():
		if not def.uses_magazine() or def.reload_ticks <= 0:
			continue
		var want := def.reload_ticks
		if def.reload_per_round:
			want = def.reload_start_ticks + def.reload_ticks * def.magazine
		if absi(timing.reload_motion_ticks(def, def.magazine) - want) > 1:
			drift.append(str(def.id))
	for art: ZeeWeaponArt in ZeeWeaponArtTable.all():
		var keys: Array = art.reload_keys if not art.reload_keys.is_empty() else ZeeWeaponArtTable.reload_keys(art.pose)
		if keys.is_empty():
			continue
		var last: Array = keys[keys.size() - 1]
		if absf(float(last[0]) - 1.0) > 0.0001 or (last[1] as Vector3).length() > 0.0001 or (last[2] as Vector3).length() > 0.0001:
			unrested.append(str(art.id))
	_cleanup(timing)
	_check("every reload motion lasts the profile's reload time (%s)" % ", ".join(drift), drift.is_empty())
	_check("every reload motion ends at the rest pose (%s)" % ", ".join(unrested), unrested.is_empty())


## A SERVER rig has to know who is carrying it: with no player the bridge falls back to defaults and every shot comes out of (0, 0, 0).
## Nothing else reports it (the weapon fires and the counters move), so this checks the origin directly.
## The carrier is a bare [Node3D], the weakest of the bridge's three answers and the one every game has.
func _rig_carrier() -> void:
	_begin("the rig knows who is carrying it")

	var carrier := Node3D.new()
	carrier.name = "Carrier"
	add_child(carrier)
	carrier.global_position = Vector3(12.0, 3.0, -45.0)
	carrier.rotation = Vector3(0.0, deg_to_rad(90.0), 0.0)

	var rig := ZeeWeaponRig.new()
	rig.role = ZeeWeaponRig.Role.SERVER
	rig.authority = true
	rig.tick_rate = ZeeWeaponPack.TICK_RATE
	rig.player_ref = DotNodeRef.of_path(^"..")
	carrier.add_child(rig)

	var res := rig.setup()
	_check("a server rig with a carrier sets up: %s" % _why(res), res.ok)

	var _given := rig.give_everything()
	rig.arsenal.select(ZeeWeaponIds.SLOT_PRIMARY, 0)
	_run_rig(rig, 0, 60, 0)

	var shots: Array = []

	for tick in range(60, 120):
		var command := DotWeaponCommand.new()
		command.buttons = DotWeaponCommand.BUTTON_ATTACK
		var outcome := rig.simulate_tick(command, tick)

		if outcome != null and not outcome.shots.is_empty():
			shots.append(outcome.shots[0])
			break

	_check("it fires", not shots.is_empty())

	if shots.is_empty():
		carrier.queue_free()
		_end()
		return

	var shot: DotShot = shots[0]

	# Armed: with the resolution back inside `_resolve_presentation`, this is
	# `(0, 0, 0)` and the next one is `(0, 0, -1)`.
	_check(
		"and the shot leaves the carrier rather than the world origin (%v)" % shot.origin,
		shot.origin.distance_to(carrier.global_position) < 2.5
	)
	_check(
		"and goes where the carrier is facing (%v)" % shot.direction,
		shot.direction.dot(-carrier.global_transform.basis.z) > 0.9
	)

	carrier.queue_free()
	_end()


func _rig_rollback() -> void:
	_begin("rollback")

	var rig := _make_rig()
	rig.setup()
	rig.give(ZeeWeaponIds.RIFLE)
	rig.arsenal.select(ZeeWeaponIds.SLOT_PRIMARY, 0)
	_run_rig(rig, 0, 60, 0)

	var saved := rig.snapshot()
	var magazine := rig.arsenal.slot_at(ZeeWeaponIds.SLOT_PRIMARY).magazine

	_check("a snapshot carries the arsenal", saved.has("arsenal"))
	_check(
		"and the bash cooldown, which lives in the rig rather than the arsenal",
		saved.has("bash_ready")
	)

	# Spend some rounds and bash, then roll back.
	_run_rig(rig, 60, 120, DotWeaponCommand.BUTTON_ATTACK)
	_run_rig(rig, 200, 204, DotWeaponCommand.BUTTON_ALT)

	var spent := rig.arsenal.slot_at(ZeeWeaponIds.SLOT_PRIMARY).magazine
	_check("firing spent rounds", spent < magazine)

	var restored := rig.restore(saved)
	_check("the snapshot restores: %s" % _why(restored), restored.ok)
	_check(
		"the magazine is back where it was",
		rig.arsenal.slot_at(ZeeWeaponIds.SLOT_PRIMARY).magazine == magazine
	)

	# The bug this guards: a snapshot that carried only the arsenal's half hands the
	# player a free bash on every correction, because the cooldown lives in the rig.
	var after: Array[int] = []
	rig.bashed.connect(func(_o: DotWeaponOutcome) -> void: after.append(1))

	# The cooldown was saved before any bash happened, so a bash must now be allowed —
	# proving the restore put a usable number back rather than leaving the spent one.
	_run_rig(rig, 300, 304, DotWeaponCommand.BUTTON_ALT)
	_check("a restored rig can bash again", after.size() == 1)

	# And immediately afterwards it cannot, which is the cooldown actually running.
	_run_rig(rig, 304, 308, DotWeaponCommand.BUTTON_ALT)
	_check("but not twice in four ticks", after.size() == 1)

	_cleanup(rig)
	_end()


## The pack is written at 64 Hz; on a 128 Hz server it must take the same wall-clock time.
## These compare a second at each rate.
func _tick_rate() -> void:
	_begin("the pack keeps its timing at 128 Hz")

	var unstamped := 0
	for def in ZeeWeaponPack.weapons():
		if def.authored_tick_rate != ZeeWeaponPack.TICK_RATE:
			unstamped += 1
	_check("every row says it was written at %d Hz" % ZeeWeaponPack.TICK_RATE, unstamped == 0)

	var shots: Array[int] = []
	var bashes: Array[int] = []
	var reload_seconds: Array[float] = []
	var deploy_fraction: Array[float] = []

	for rate: int in [64, 128]:
		var rig := _make_rig()
		rig.tick_rate = rate
		rig.setup()
		rig.give(ZeeWeaponIds.SMG)
		_check_quiet("the arsenal runs at the rig's rate", rig.arsenal.tick_rate == rate)

		# Two seconds idle, so nothing is still deploying, then one second on the trigger.
		_run_rig(rig, 0, rate * 2, 0)
		shots.append(_run_rig(rig, rate * 2, rate * 3, DotWeaponCommand.BUTTON_ATTACK))

		var def := rig.current_def()
		reload_seconds.append(float(rig.arsenal.ticks_for(def, def.reload_ticks)) / float(rate))

		# The alt-fire pressed on every other tick for two seconds: the rig's own cooldown,
		# which the arsenal never sees, decides how many land.
		var count: Array[int] = [0]
		rig.bashed.connect(func(_o: DotWeaponOutcome) -> void: count[0] += 1)
		var from := rate * 4
		for tick in range(from, from + rate * 2):
			var command := DotWeaponCommand.new()
			command.buttons = DotWeaponCommand.BUTTON_ALT if (tick - from) % 2 == 0 else 0
			var ctx := DotWeaponContext.make(1, tick, Vector3.ZERO, Vector3.FORWARD)
			ctx.authority = true
			rig.simulate_tick(command, tick, ctx)
		bashes.append(count[0])

		# A quarter of a second into a switch, the drawn picture is as far along at either rate.
		rig.give(ZeeWeaponIds.PISTOL)
		var at := rate * 7
		var cmd := DotWeaponCommand.new()
		cmd.slot = ZeeWeaponIds.SLOT_SIDEARM
		rig.simulate_tick(cmd, at, DotWeaponContext.make(1, at, Vector3.ZERO, Vector3.FORWARD))
		_run_rig(rig, at + 1, at + rate / 8, 0)
		deploy_fraction.append(rig._deploy_fraction(at + rate / 8 - 1))

		_cleanup(rig)

	_check("a second of fire is as many shots at 128 Hz as at 64 (%d, %d)" % [shots[0], shots[1]],
		shots[0] > 1 and shots[0] == shots[1])
	_check("a reload takes the same time (%.3f s, %.3f s)" % [reload_seconds[0], reload_seconds[1]],
		absf(reload_seconds[0] - reload_seconds[1]) < 1.0 / 64.0)
	_check("the bash cools down in the same time (%d, %d bashes)" % [bashes[0], bashes[1]],
		bashes[0] > 1 and bashes[0] == bashes[1])
	_check("the holster is drawn as far along after the same time (%.2f, %.2f)" % [deploy_fraction[0], deploy_fraction[1]],
		absf(deploy_fraction[0] - deploy_fraction[1]) < 0.1)

	_end()


func _rig_idle() -> void:
	_begin("an idle rig skips the context and changes nothing")

	# A given context takes the full path; none takes the idle one when nothing is pressed.
	var full := _make_rig()
	var quick := _make_rig()

	for rig: ZeeWeaponRig in [full, quick]:
		var _setup: DotResult = rig.setup()
		var _given: Variant = rig.give_everything()
		rig.arsenal.select(ZeeWeaponIds.SLOT_PRIMARY, 0)

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var same := true

	for tick in range(900):
		var command := DotWeaponCommand.new()

		if (tick / 40) % 3 == 0:
			command.set_button(DotWeaponCommand.BUTTON_ATTACK, rng.randf() < 0.7)
			command.set_button(DotWeaponCommand.BUTTON_RELOAD, rng.randf() < 0.03)
			command.set_button(DotWeaponCommand.BUTTON_ALT, rng.randf() < 0.05)
			command.slot = rng.randi_range(1, 4) if rng.randf() < 0.04 else 0

		var ctx := DotWeaponContext.new()
		ctx.authority = true
		var want := full.simulate_tick(command, tick, ctx)
		var got := quick.simulate_tick(command.duplicate_command(), tick)

		if want.used != got.used or want.kind != got.kind or want.shots.size() != got.shots.size() \
				or var_to_str(full.snapshot()) != var_to_str(quick.snapshot()) \
				or full.ads_move_scale() != quick.ads_move_scale():
			same = false
			break

	_check("outcomes and snapshots agree on every tick of a mixed stream", same)

	_cleanup(full)
	_cleanup(quick)
	_end()


func _ads_rules() -> void:
	_begin("aiming rules")

	var rules := ZeeAdsRules.new()
	_check("defaults: every weapon may aim, hold, by its art", rules.enabled_for(&"rifle") and not rules.toggle_for(&"rifle")
		and is_equal_approx(rules.zoom_for(&"rifle", 0.8), 0.8) and is_equal_approx(rules.aim_time_for(&"rifle", 0.16), 0.16))
	rules.apply_tree({
		"default": {"spread_multiplier": 0.5, "zoom": 0.7},
		"weapons": {"pistol": {"enabled": false}, "sniper": {"zoom": 0.25, "toggle": true}, "rifle": {"spread_multiplier": 5.0}},
	})
	_check("a default applies to every weapon", is_equal_approx(rules.spread_for(&"rifle_x"), 0.5)
		and is_equal_approx(rules.zoom_for(&"smg", 0.8), 0.7))
	_check("a weapon override beats the default", is_equal_approx(rules.zoom_for(&"sniper", 0.3), 0.25) and rules.toggle_for(&"sniper"))
	_check("a disabled weapon does not aim and is not slowed or tightened",
		not rules.enabled_for(&"pistol") and is_equal_approx(rules.move_speed_for(&"pistol"), 1.0)
		and is_equal_approx(rules.spread_for(&"pistol"), 1.0))
	_check("an out-of-range value is refused and the old one stands", is_equal_approx(rules.spread_for(&"rifle"), 0.5))
	_check("an unknown key and a wrong type are refused", not rules.set_value(&"", "bogus", 1.0) and not rules.set_value(&"", "enabled", 1.0))

	var loaded := ZeeAdsRules.load_config()
	_check("the shipped file loads to the defaults", loaded.enabled_for(&"rifle")
		and is_equal_approx(float(loaded.base["move_speed_multiplier"]), 0.8))

	_ads_view(rules)
	_ads_quickscope()

	var carrier := Node3D.new()
	add_child(carrier)
	var rig := ZeeWeaponRig.new()
	rig.role = ZeeWeaponRig.Role.SERVER
	rig.authority = true
	rig.tick_rate = ZeeWeaponPack.TICK_RATE
	rig.player_ref = DotNodeRef.of_path(^"..")
	carrier.add_child(rig)
	var _setup := rig.setup()
	var _given := rig.give_everything()
	rig.arsenal.select(ZeeWeaponIds.SLOT_PRIMARY, 0)
	_run_rig(rig, 0, 60, 0)
	(rig.arsenal.current_def().tuning as DotWeaponBallistics).bloom = 0.0
	var plain := _first_spread(rig, 60, 0)
	rig.ads_rules = rules
	var fresh := _first_spread(rig, 240, DotWeaponCommand.BUTTON_USER_0)
	_run_rig(rig, 300, 360, DotWeaponCommand.BUTTON_USER_0)
	var held := _first_spread(rig, 360, DotWeaponCommand.BUTTON_USER_0)
	_check("the aim bit is a ramp: a first tick of aiming is still nearly the hip spread (%.3f)" % fresh, fresh > plain * 0.8)
	_check("a shot while aiming is tighter by the multiplier (%.3f -> %.3f)" % [plain, held],
		plain > 0.0 and is_equal_approx(held, plain * 0.5))
	_check("walk speed drops while the aim button is held", is_equal_approx(rig.ads_move_scale(), 0.8))
	var after := _first_spread(rig, 600, 0)
	var wire := rules.to_wire()
	var clone := ZeeAdsRules.new()
	_check("the rules cross the wire: a client adopting the server's text predicts the same", clone.adopt_wire(wire) and clone.to_wire() == wire and clone.wire_hash() == rules.wire_hash())
	var tweaked := ZeeAdsRules.new()
	var _s := tweaked.set_value(&"", "spread_multiplier", 0.1)
	var _p := tweaked.set_value(&"pistol", "enabled", false)
	_check("and a changed server value replaces the client's (%s)" % tweaked.wire_hash(), clone.adopt_wire(tweaked.to_wire()) and is_equal_approx(float(clone.value_for(&"rifle", "spread_multiplier")), 0.1) and not clone.enabled_for(&"pistol"))
	_check("while garbage is refused and changes nothing", not clone.adopt_wire("nope") and not clone.enabled_for(&"pistol"))
	_check("the def is put back after: a hip shot is as wide as before", is_equal_approx(after, plain))
	_check("and the hip walks at full speed", is_equal_approx(rig.ads_move_scale(), 1.0))
	_ads_sprint(rig)
	_ads_wire_warning()
	carrier.queue_free()
	_end()


## A sniper rig, drawn and ready, its aim-in as long as the rules say.
func _sniper_rig(rules: ZeeAdsRules, carrier: Node3D) -> ZeeWeaponRig:
	var rig := ZeeWeaponRig.new()
	rig.role = ZeeWeaponRig.Role.SERVER
	rig.authority = true
	rig.tick_rate = ZeeWeaponPack.TICK_RATE
	rig.player_ref = DotNodeRef.of_path(^"..")
	rig.ads_rules = rules
	carrier.add_child(rig)
	var _setup := rig.setup()
	var _given := rig.arsenal.give(ZeeWeaponIds.SNIPER)
	_run_rig(rig, 0, 400, 0)
	return rig


## Shots fired while the sights come up: allowed or held back by the threshold, tagged for the stats, and the scope shows progressively.
func _ads_quickscope() -> void:
	var carrier := Node3D.new()
	add_child(carrier)
	var rules := ZeeAdsRules.new()
	var _t := rules.set_value(&"", "aim_time", 0.5)
	var rig := _sniper_rig(rules, carrier)
	_check("the test rig holds the sniper", rig.arsenal.current_def().id == ZeeWeaponIds.SNIPER)
	var both := DotWeaponCommand.BUTTON_USER_0 | DotWeaponCommand.BUTTON_ATTACK

	# Threshold 0: the first aimed tick may fire, as a quick scope.
	var shot := _fire_at(rig, 1000, both)
	_check("with threshold 0 a shot lands during the aim-in", shot != null)
	if shot != null:
		_check("and carries its ads_progress (%.2f)" % float(shot.get_meta(&"ads_progress", -1.0)),
			float(shot.get_meta(&"ads_progress", -1.0)) < 0.2 and float(shot.get_meta(&"ads_progress", -1.0)) > 0.0)
		_check("and is flagged a quickscope", bool(shot.get_meta(&"quickscope", false)))

	# Threshold 1 is the old rule: nothing before the sights are up.
	var late := ZeeAdsRules.new()
	var _t2 := late.set_value(&"", "aim_time", 0.5)
	var _t3 := late.set_value(&"", "quickscope_fire_min", 1.0)
	var rig2 := _sniper_rig(late, carrier)
	var held := 0
	var first_progress := -1.0
	var qs_late := false
	for tick in range(1000, 1000 + 120):
		var cmd := DotWeaponCommand.new()
		cmd.buttons = both if tick % 2 == 0 else DotWeaponCommand.BUTTON_USER_0
		var out := rig2.simulate_tick(cmd, tick)
		if out != null and not out.shots.is_empty():
			first_progress = float((out.shots[0] as DotShot).get_meta(&"ads_progress", -1.0))
			qs_late = bool((out.shots[0] as DotShot).get_meta(&"quickscope", false))
			break
		held += 1
	_check("with threshold 1 the shot waits for the sights (%d ticks held)" % held, held >= int(0.5 * ZeeWeaponPack.TICK_RATE) - 1)
	_check("and then is no quickscope (progress %.2f)" % first_progress, is_equal_approx(first_progress, 1.0) and not qs_late)

	# A mid threshold fires once the progress passes it.
	var mid := ZeeAdsRules.new()
	var _t4 := mid.set_value(&"", "aim_time", 0.5)
	var _t5 := mid.set_value(&"", "quickscope_fire_min", 0.5)
	var rig3 := _sniper_rig(mid, carrier)
	var mid_shot := _fire_at(rig3, 1000, both)
	var p := float(mid_shot.get_meta(&"ads_progress", -1.0)) if mid_shot != null else -1.0
	_check("a mid threshold lets it fire just past half (%.2f)" % p, p >= 0.5 and p < 0.6 and bool(mid_shot.get_meta(&"quickscope", false)))

	# The threshold is predicted: it crosses the wire.
	var clone := ZeeAdsRules.new()
	_check("the threshold crosses the wire", clone.adopt_wire(mid.to_wire()) and is_equal_approx(clone.quickscope_fire_min_for(&"sniper"), 0.5))

	var facts := ZeeWeaponRig.aim_facts(shot)
	_check("aim_facts reads the shot meta for a stat rule", bool(facts["quickscope"]) and float(facts["ads_progress"]) > 0.0 and float(ZeeWeaponRig.aim_facts(null)["ads_progress"]) < 0.0)

	# A weapon's own profile sets it, under the server's override.
	var own := ZeeAdsRules.new()
	own.set_def_row(&"sniper", {"quickscope_fire_min": 1.0, "scope_lens_min": 0.5, "bogus": 1, "scope_fade_start": 5.0})
	var _t6 := own.set_value(&"pistol", "scope_lens_min", 0.2)
	own.set_def_row(&"pistol", {"scope_lens_min": 0.9})
	_check("a def's ads params apply to its weapon, bad keys dropped",
		is_equal_approx(own.quickscope_fire_min_for(&"sniper"), 1.0) and is_equal_approx(own.scope_lens_min_for(&"sniper"), 0.5)
		and is_equal_approx(own.scope_fade_start_for(&"sniper"), 0.6) and is_equal_approx(own.quickscope_fire_min_for(&"rifle"), 0.0))
	_check("and the server's per-weapon override wins", is_equal_approx(own.scope_lens_min_for(&"pistol"), 0.2))

	_ads_scope_view(rules)
	carrier.queue_free()


func _fire_at(rig: ZeeWeaponRig, from: int, buttons: int) -> DotShot:
	for tick in range(from, from + 120):
		var cmd := DotWeaponCommand.new()
		cmd.buttons = buttons if tick % 2 == 0 else buttons & ~DotWeaponCommand.BUTTON_ATTACK
		var out := rig.simulate_tick(cmd, tick)
		if out != null and not out.shots.is_empty():
			return out.shots[0] as DotShot
	return null


## The scope is not a pop: part-way up the surround is part visible and the lens is smaller than at the end.
func _ads_scope_view(rules: ZeeAdsRules) -> void:
	var view := ZeeViewModel.new()
	view.show_arms = false
	add_child(view)
	var _eq := view.equip(ZeeWeaponArtTable.get_art(&"sniper"))
	view.ads_rules = rules
	view.aim(true)
	var seen: Array[float] = []
	var lens: Array[float] = []
	for _i in range(40):
		view._advance_aim(0.5 / 30.0)
		seen.append(view.scope_fraction())
		lens.append(view.scope_lens_scale())
		if view.aim_fraction() >= 1.0:
			break
	var steps := 0
	for v in seen:
		if v > 0.02 and v < 0.98:
			steps += 1
	_check("the scope fades in over several frames, not at the end (%d part-visible frames)" % steps, steps >= 3)
	_check("the surround is dark only late: at a third of the aim-in it is nil", seen[4] < 0.01)
	_check("the lens grows over the aim-in (%.2f -> %.2f)" % [lens[0], lens[lens.size() - 1]], lens[0] < 0.5 and is_equal_approx(lens[lens.size() - 1], 1.0))
	var pistol := view.equip(ZeeWeaponArtTable.get_art(&"pistol"))
	_check("a weapon without a scope has none at any progress", view.scope_fraction() == 0.0 and not pistol == null)
	view.queue_free()


func _ads_view(rules: ZeeAdsRules) -> void:
	var view := ZeeViewModel.new()
	view.show_arms = false
	add_child(view)
	var _eq := view.equip(ZeeWeaponArtTable.get_art(&"pistol"))
	view.ads_rules = rules
	view.aim(true)
	view._advance_aim(1.0)
	_check("the view model of a disabled weapon cannot aim", not view.can_aim() and view.aim_fraction() == 0.0)
	var _eq2 := view.equip(ZeeWeaponArtTable.get_art(&"sniper"))
	view.aim_input(true)
	view.aim_input(false)
	view._advance_aim(1.0)
	_check("a toggle weapon stays aimed after the button is released", view.aim_fraction() > 0.99)
	_check("its zoom is the profile's", is_equal_approx(view.aim_fov_scale(), 0.25))
	view.aim_input(true)
	view.aim_input(false)
	view._advance_aim(1.0)
	_check("a second press lowers it", view.aim_fraction() < 0.01)
	view.queue_free()


func _ads_sprint(rig: ZeeWeaponRig) -> void:
	var sprint_ctx := DotWeaponContext.new()
	var aim_cmd := DotWeaponCommand.new()
	aim_cmd.buttons = DotWeaponCommand.BUTTON_USER_0
	var cur := rig.arsenal.current_def()
	var open_aim := rig._can_aim(aim_cmd, cur, sprint_ctx)
	sprint_ctx.sprinting = true
	var free_sprint := rig._can_aim(aim_cmd, cur, sprint_ctx)
	sprint_ctx.sprint_blocks_aim = true
	_check("sprinting refuses the aim bit only under sv_sprint_noaim", open_aim and free_sprint and not rig._can_aim(aim_cmd, cur, sprint_ctx))
	var barrel_ctx := DotWeaponContext.new()
	barrel_ctx.direction = Vector3.FORWARD
	barrel_ctx.sprinting = true
	rig._aim_along_sprint_barrel(barrel_ctx)
	_check("a sprint shot keeps the crosshair line without sv_sprint_barrel", barrel_ctx.direction.is_equal_approx(Vector3.FORWARD))
	barrel_ctx.sprint_shot_follows_barrel = true
	rig._aim_along_sprint_barrel(barrel_ctx)
	var turned := rad_to_deg(barrel_ctx.direction.angle_to(Vector3.FORWARD))
	_check("with it the shot follows the lowered barrel (%.1f degrees off)" % turned, turned > 1.0 and is_equal_approx(barrel_ctx.direction.length(), 1.0))
	barrel_ctx.sprinting = false
	barrel_ctx.direction = Vector3.FORWARD
	rig._aim_along_sprint_barrel(barrel_ctx)
	_check("and a walking shot is untouched", barrel_ctx.direction.is_equal_approx(Vector3.FORWARD))


func _ads_wire_warning() -> void:
	var warned: Array = []
	var catch := func(rec: Dictionary) -> void: warned.append(rec)
	DotLog.signals().record.connect(catch)
	var fat := ZeeAdsRules.new()
	for n in 60:
		var _f := fat.set_value(StringName("some_long_weapon_id_%d" % n), "move_speed_multiplier", 0.5)
	var _b := fat.bind_cvars(func(_n: String, _v: String, _d: String, _f2: int) -> Variant: return null)
	var _b2 := ZeeAdsRules.new().bind_cvars(func(_n: String, _v: String, _d: String, _f2: int) -> Variant: return null)
	DotLog.signals().record.disconnect(catch)
	var long_warns := warned.filter(func(r: Dictionary) -> bool: return str(r.get("message", r.get("msg", ""))).contains("too long to replicate"))
	_check("a wire over 1000 bytes warns once at bind and a short one does not (%d, %d bytes)" % [long_warns.size(), fat.to_wire().length()], long_warns.size() == 1 and fat.to_wire().length() > 1000)


func _input_bindings() -> void:
	_begin("input bindings")

	# Every action this could add, removed first so the suite starts from a project
	# that bound none of them, and removed again after so no later scene inherits them.
	var ours: Array[StringName] = []
	for action: StringName in ZeeWeaponInput.DEFAULT_ACTIONS.keys():
		ours.append(action)
	for slot in range(1, 6):
		ours.append(StringName(ZeeWeaponInput.SLOT_ACTION_PREFIX + str(slot)))
	for action in ours:
		if InputMap.has_action(action):
			InputMap.erase_action(action)

	# An Array, not a counter: a lambda captures a scalar by value.
	var heard: Array[Dictionary] = []
	var listen := func(rec: Dictionary) -> void:
		if str(rec.get("channel", "")) == ZeeWeaponInput.CHANNEL:
			heard.append(rec)
	DotLog.signals().record.connect(listen)

	var first := ZeeWeaponInput.register_default_actions()
	_check("registering the defaults adds all fourteen", first == 14)
	_check(
		"and says so once, on zee.input, at INFO (heard %d)" % heard.size(),
		heard.size() == 1 and int(heard[0].get("level", -1)) == DotLog.Level.INFO
	)

	var second := ZeeWeaponInput.register_default_actions()
	_check("a second call adds nothing", second == 0)
	_check("and logs nothing: an edge, not a line per call", heard.size() == 1)

	DotLog.signals().record.disconnect(listen)
	for action in ours:
		if InputMap.has_action(action):
			InputMap.erase_action(action)

	_end()


func _profiles() -> void:
	_begin("weapon profiles overlay only the keys a file sets")
	var saved_roots := ZeeWeaponPack.base_roots
	var vanilla := _by_id(ZeeWeaponPack.weapons({}, false))
	ZeeWeaponPack.base_roots = PackedStringArray(["res://cfg"])
	var set := ZeeWeaponPack.profile_set()
	_check("one shipped profile per weapon", set.list_ids().size() == vanilla.size() and vanilla.size() == 27)
	set.clear_cache()
	var stale := PackedStringArray()
	for id in vanilla:
		var path := ZeeWeaponProfiles.profile_path("zee_weapons", id)
		if FileAccess.get_file_as_string(path) != ZeeWeaponProfiles.to_yaml(vanilla[id], "Zee Weapons"):
			stale.append(id)
	_check("shipped profiles are what the exporter writes (run tools/export-defs.sh): %s" % ", ".join(stale), stale.is_empty())
	var tuned := _by_id(ZeeWeaponPack.weapons())
	var drift := PackedStringArray()
	for id in vanilla:
		if str(ZeeWeaponProfiles.flat_of(tuned[id])) != str(ZeeWeaponProfiles.flat_of(vanilla[id])):
			drift.append(id)
	_check("loading every shipped profile changes no number: %s" % ", ".join(drift), drift.is_empty())
	_check("no shipped profile fails", ZeeWeaponPack.errors.is_empty())

	var tmp := "user://zee_profiles_cfg"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(tmp))
	_profile_file(tmp, "rifle.yml", "magazine: 12\nname: \"Test Rifle\"\nextra:\n  tuning:\n    damage: 99\n    nonsense: 1\n  params:\n    bash_damage: 7\n    fresh: 3\n")
	_profile_file(tmp, "pistol.yml", "magazine: -5\n")
	_profile_file(tmp, "ghost.yml", "magazine: 3\n")
	ZeeWeaponPack.base_roots = PackedStringArray([tmp])
	var set2 := ZeeWeaponPack.profile_set()
	_check("a file's keys are file keys, a schema default is not", set2.load_profile("rifle").value.file_keys == PackedStringArray(["extra.params.bash_damage", "extra.params.fresh", "extra.tuning.damage", "extra.tuning.nonsense", "magazine", "name"]))
	set2.clear_cache()
	var t2 := _by_id(ZeeWeaponPack.weapons())
	var r: DotWeaponDef = t2["rifle"]
	var rv: DotWeaponDef = vanilla["rifle"]
	_check("a common key, tuning and params key land", r.magazine == 12 and r.display_name == "Test Rifle" and is_equal_approx((r.tuning as DotWeaponBallistics).damage, 99.0) and is_equal_approx(float(r.params[&"bash_damage"]), 7.0))
	_check("a new params key is taken as written", int(r.params[&"fresh"]) == 3)
	_check("every key the file does not set keeps the builder's value", r.reload_ticks == rv.reload_ticks and r.deploy_ticks == rv.deploy_ticks and is_equal_approx((r.tuning as DotWeaponBallistics).spread, 0.45) and is_equal_approx((r.tuning as DotWeaponBallistics).bloom_recovery, 8.5 / 64.0))
	_check("other weapons are untouched", str(ZeeWeaponProfiles.flat_of(t2["smg"])) == str(ZeeWeaponProfiles.flat_of(vanilla["smg"])))
	_check("an out-of-range profile is reported and its weapon keeps the builder's numbers", ZeeWeaponPack.errors.size() == 1 and t2["pistol"].magazine == vanilla["pistol"].magazine)
	_check("the exporter's list ignores the profiles", ZeeDefExport.own_weapons()[13].magazine == rv.magazine)

	var pack_root := "user://zee_profiles_pack"
	_profile_file(pack_root, "smg.yml", "extra:\n  tuning:\n    damage: 55\n")
	ZeeWeaponPack.pack_cfg_root = pack_root
	ZeeWeaponPack.base_roots = PackedStringArray([tmp.path_join("none")])
	_check("a delivered pack's cfg root is read", is_equal_approx((_by_id(ZeeWeaponPack.weapons())["smg"].tuning as DotWeaponBallistics).damage, 55.0))
	_profile_file(tmp.path_join("over"), "smg.yml", "extra:\n  tuning:\n    damage: 66\n")
	ZeeWeaponPack.base_roots = PackedStringArray([tmp.path_join("over")])
	_check("and is the weakest root", is_equal_approx((_by_id(ZeeWeaponPack.weapons())["smg"].tuning as DotWeaponBallistics).damage, 66.0))
	ZeeWeaponPack.pack_cfg_root = ""

	ZeeWeaponPack.base_roots = PackedStringArray(["res://cfg"])
	var up := ZeeWeaponPack.upgraded(&"rifle", ["extended_mag"])
	_check("an upgrade is applied to a copy", up.ok and up.value["def"].magazine == 40 and up.value["def"].reload_ticks == int(round(141.0 * 1.15)) and up.value["cost"] == 100 and vanilla["rifle"].magazine == 30)
	var both := ZeeWeaponPack.upgraded(&"rifle", ["extended_mag", "hot_loads"])
	_check("upgrades stack and reach the tuning", both.ok and is_equal_approx((both.value["def"].tuning as DotWeaponBallistics).damage, 23.0 * 1.2) and both.value["cost"] == 250)
	_check("an upgrade whose requirement is missing is refused", not ZeeWeaponPack.upgraded(&"rifle", ["hot_loads"]).ok)
	var choke := ZeeWeaponPack.upgraded(&"shotgun", ["choke"])
	_check("a set upgrade changes an int field", choke.ok and (choke.value["def"].tuning as DotWeaponBallistics).pellets == 8)
	_check("an unknown weapon is refused", not ZeeWeaponPack.upgraded(&"ghost", []).ok)

	var out := "user://zee_profiles_export"
	var wrote := ZeeDefExport.write_cfg(out, "zee_weapons", "Zee Weapons", ZeeDefExport.own_weapons())
	_check("the export writes every profile and the upgrade folders", wrote.ok and FileAccess.file_exists(out.path_join("cfg/addons/zee_weapons/weapon/rifle/rifle.yml")) and FileAccess.file_exists(out.path_join("cfg/addons/zee_weapons/weapon/rifle/upgrades/hot_loads.yml")) and FileAccess.file_exists(out.path_join("cfg/addons/zee_weapons/weapon/pistol.yml")))
	ZeeWeaponPack.base_roots = saved_roots
	_end()


func _stock_path(stream: AudioStream, sound: String) -> bool:
	return stream is AudioStreamOggVorbis and stream.resource_path.begins_with(
		"%s%s_" % [DotWeaponSound.DIR, sound]
	)


func _stock_sounds() -> void:
	_begin("the stock recordings are what plays")

	_check("dot-audio's weapon stock is linked", DotWeaponSound.count(&"light_fire") == 5)

	var wrong := PackedStringArray()
	for sound_class: StringName in DotWeaponSound.FIRE:
		var stream := ZeeWeaponSound.stream(sound_class)
		if not _stock_path(stream, String(DotWeaponSound.FIRE[sound_class])):
			wrong.append(String(sound_class))
	_check("every class plays a recording, not the bake (%s)" % ", ".join(wrong), wrong.is_empty())

	var bake_ids := PackedStringArray()
	for def: DotWeaponDef in ZeeWeaponPack.weapons():
		for kind: StringName in [DotWeaponOutcome.KIND_SHOT, DotWeaponOutcome.KIND_SWING]:
			if not ZeeWeaponSound.stream_for(def.id, kind) is AudioStreamOggVorbis:
				bake_ids.append("%s/%s" % [def.id, kind])
	_check("every weapon's report is a recording (%s)" % ", ".join(bake_ids), bake_ids.is_empty())

	_check("a rifle heard from afar is the _far recording",
		_stock_path(ZeeWeaponSound.far_for(ZeeWeaponIds.RIFLE, DotWeaponOutcome.KIND_SHOT), "rifle_far"))
	_check("a melee class has no far recording", ZeeWeaponSound.far_for(ZeeWeaponIds.RIFLE, DotWeaponOutcome.KIND_SWING) == null)
	_check("a suppressed weapon plays its own report, not the pistol's",
		_stock_path(ZeeWeaponSound.stream(ZeeWeaponSound.SUPPRESSED), "suppressed_fire"))

	var fx := ZeeShotFx.new()
	add_child(fx)
	var heard: Array[AudioStream] = []
	fx.heard.connect(func(stream: AudioStream) -> void: heard.append(stream))
	fx.play_dry(Vector3.ZERO)
	fx.play_dry(Vector3.ZERO)
	_check("a dry fire clicks once, throttled", heard.size() == 1 and _stock_path(heard[0], "dry"))
	fx.play_equip(Vector3.ZERO)
	_check("an equip plays the stock equip", _stock_path(heard[-1], "equip"))
	fx.play_reload_shell(Vector3.ZERO)
	_check("a shell plays reload_shell", _stock_path(heard[-1], "reload_shell"))
	fx.play_reload(ZeeWeaponSound.RELOAD_OUT, Vector3.ZERO)
	_check("a magazine out plays reload_out", _stock_path(heard[-1], "reload_out"))
	fx.play_eject(Transform3D.IDENTITY, ZeeWeaponIds.RIFLE)
	fx.call(&"_play_casing", Vector3.ZERO)
	_check("a case lands with the stock casing", _stock_path(heard[-1], "casing"))
	var before := heard.size()
	fx.play_use(_fake_shot(), Transform3D.IDENTITY, ZeeWeaponIds.RIFLE)
	_check("a shot plays a stock report", heard.size() == before + 1 and _stock_path(heard[-1], "rifle_fire"))
	await get_tree().create_timer(DotWeaponSound.TAIL_DELAY + 0.1).timeout
	_check("outdoors a shot has no tail", heard.size() == before + 1)
	fx.roof = _FakeRoof.new()
	fx.play_use(_fake_shot(), Transform3D.IDENTITY, ZeeWeaponIds.RIFLE)
	_check("indoors the report is alone until the delay", heard.size() == before + 2)
	await get_tree().create_timer(DotWeaponSound.TAIL_DELAY + 0.1).timeout
	_check("indoors the _far tail follows the report", heard.size() == before + 3 and _stock_path(heard[-1], "rifle_far"))
	fx.roof = null
	fx.sounds = false
	fx.play_equip(Vector3.ZERO)
	_check("and with sounds off nothing plays", heard.size() == before + 3)
	fx.queue_free()

	_stock_rig_sounds()
	_end()


func _stock_rig_sounds() -> void:
	# The rig wires the arsenal's dry signal and a tube magazine's shells to the effects.
	var carrier := Node3D.new()
	add_child(carrier)
	var view := ZeeViewModel.new()
	view.show_arms = false
	carrier.add_child(view)
	var rig := ZeeWeaponRig.new()
	rig.role = ZeeWeaponRig.Role.LOCAL
	rig.authority = true
	rig.tick_rate = ZeeWeaponPack.TICK_RATE
	rig.player_ref = DotNodeRef.of_path(^"..")
	rig.view_model_ref = DotNodeRef.of_path(view.get_path())
	carrier.add_child(rig)
	rig.setup()
	var rig_fx := rig.shot_fx()
	var rig_heard: Array[AudioStream] = []
	rig_fx.heard.connect(func(stream: AudioStream) -> void: rig_heard.append(stream))
	rig.arsenal.dry_used.emit(0)
	_check("the rig plays the dry click when the arsenal reports one",
		rig_heard.size() == 1 and _stock_path(rig_heard[0], "dry"))

	rig.give(ZeeWeaponIds.SHOTGUN)
	var gun := rig.arsenal.catalogue.get_def(ZeeWeaponIds.SHOTGUN)
	rig.arsenal.select(gun.slot, 0)
	_run_rig(rig, 0, 60, 0)
	rig_heard.clear()
	_run_rig(rig, 60, 120, DotWeaponCommand.BUTTON_ATTACK)
	rig.arsenal.current().magazine = 3
	_run_rig(rig, 120, 124, DotWeaponCommand.BUTTON_RELOAD)
	rig_heard.clear()
	_run_rig(rig, 124, 700, 0)
	var shells := 0
	var outs := 0
	for stream in rig_heard:
		if _stock_path(stream, "reload_shell"):
			shells += 1
		if _stock_path(stream, "reload_out"):
			outs += 1
	_check("a shotgun reload plays a shell per round, not a magazine out (%d shells)" % shells, shells >= 2 and outs == 0)
	_cleanup(carrier)


func _fake_shot() -> DotWeaponOutcome:
	var outcome := DotWeaponOutcome.new()
	outcome.used = true
	outcome.kind = DotWeaponOutcome.KIND_SHOT
	return outcome


## A profile's `extra: art:` reaches the rig's equip, not only a figure's held gun.
func _rig_art_override(rig: ZeeWeaponRig) -> void:
	var def := rig.current_def()
	var old: Variant = def.params.get("art")
	def.params["art"] = {"world_scale": 2.5}
	var base := rig.current_art()
	var merged := base.with_overrides(def.params["art"])
	_check("an `extra: art:` row yields overridden art for the rig's equip", merged != base and is_equal_approx(merged.world_scale, 2.5))
	if old == null:
		def.params.erase("art")
	else:
		def.params["art"] = old


class _FakeRoof extends RefCounted:
	var roofed := true
