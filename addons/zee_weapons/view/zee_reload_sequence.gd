extends RefCounted

## A reload as phases, built from an art's `reload` row and the rounds actually left: where each hand goes, how the
## gun turns, and what is in sight (magazine, cases, rounds, belt) at every point from 0 to 1 of the rig's reload time.
## Row keys: `style` (STYLES), `eject` ("spent", "all" or "none"), `part`, `round`, `case` (zee_reload_parts.gd names), `clip` (rounds per stripper clip), `loader` ("speedloader" or
## "single"), `weights` {phase: weight}, `hands` {phase: {left|right: [anchor, [x, y, z]]}}, `anchors` {name: [x, y, z]} in
## model metres, `prop_scale`. Preloaded by path (no class_name), as zee_reload_parts.gd is. Positions are in Aim space.

const STYLES: Array[StringName] = [&"magazine", &"pistol", &"revolver", &"tube", &"bolt", &"belt", &"launcher", &"cell", &"generic"]

## Gun offsets per pose, [position, rotation degrees], turned about the grip as ZeeWeaponPose's reload keys are.
const GUN := {
	&"rest": [Vector3.ZERO, Vector3.ZERO],
	&"tilt": [Vector3(-0.07, 0.055, 0.015), Vector3(12.0, 14.0, -42.0)],
	&"lift": [Vector3(-0.065, 0.08, 0.0), Vector3(32.0, 18.0, -22.0)],
	&"cant": [Vector3(-0.03, 0.025, 0.0), Vector3(4.0, 10.0, -16.0)],
	&"open": [Vector3(-0.075, 0.085, 0.0), Vector3(30.0, 20.0, -48.0)],
	&"dump": [Vector3(-0.05, 0.10, 0.02), Vector3(62.0, 12.0, -26.0)],
	&"roll": [Vector3(-0.08, 0.07, 0.015), Vector3(14.0, 15.0, -62.0)],
	&"port": [Vector3(-0.10, 0.095, 0.05), Vector3(10.0, 21.0, -6.0)],
	&"heavy": [Vector3(-0.10, 0.09, 0.03), Vector3(11.0, 16.0, -32.0)],
	&"break": [Vector3(-0.09, 0.09, 0.02), Vector3(-26.0, 28.0, -18.0)],
	&"settle": [Vector3(0.0, -0.004, 0.02), Vector3(-2.0, 2.0, 0.0)],
}

## A prop's height above the hand that carries it, so it reads as held between the fingers.
const CARRY := Vector3(0.0, 0.035, 0.0)
## Gun length per style the parts are sized for; a model drawn at another size scales them with it.
const REAL_LENGTH := {&"pistol": 0.22, &"revolver": 0.28, &"magazine": 0.85, &"cell": 0.8, &"tube": 1.0, &"bolt": 1.1, &"belt": 1.1, &"launcher": 0.75}
## Which part each style reloads with.
const PART := {&"magazine": &"box_magazine", &"pistol": &"box_magazine", &"cell": &"cell", &"belt": &"ammo_box", &"tube": &"shell", &"launcher": &"grenade", &"bolt": &"clip", &"revolver": &"speedloader"}

var style: StringName = &"generic"
var empty := false
var ejected := 0
var loaded := 0
var prop_scale := 1.0
## [{name, t0, t1, gun, left: Vector3, right: Vector3 offset from the grip}]
var phases: Array = []
var left_keys: Array = []
var right_keys: Array = []
var gun_keys: Array = []
## [{part, segments: [[t0, t1, mode, a: Vector3, i]]}]; mode "hand" (follows the left hand), "rhand", "at" (fixed), "fall", "eject".
var props: Array = []
## While the gun's own magazine is out of it: [t0, t1], or empty.
var own_out: Array = []

var _anchors: Dictionary = {}
var _grip := Vector3.ZERO
var _spec: Dictionary = {}


## The style a row names, else the one its art implies; "generic" only for an art with nothing to say.
static func style_of(art: ZeeWeaponArt) -> StringName:
	var named := StringName(str(art.reload.get("style", ""))) if art != null else &""
	if named in STYLES:
		return named
	if art == null or art.pose in [&"melee", &"thrown", &"fists"]:
		return &"generic"
	if art.magazine_part == &"cell":
		return &"cell"
	if art.magazine_part == &"ammo_box":
		return &"belt"
	if art.reload_keys == ZeeWeaponPose.RELOAD_KEYS_REVOLVER:
		return &"revolver"
	if art.magazine_loose and art.bolt_pull.length_squared() > 0.000001:
		return &"bolt"
	if art.magazine_loose and art.reload_keys == ZeeWeaponPose.RELOAD_KEYS_BREAK:
		return &"launcher"
	if art.magazine_loose:
		return &"tube"
	return &"pistol" if art.pose == &"pistol" else &"magazine"


## Where the hands go, from the grip and fore-end (30% and 62% along the gun, under the bore), in Aim space;
## [param overrides] are model-space points through [param to_aim].
static func anchors_for(grip: Vector3, fore: Vector3, muzzle: Vector3, well: Variant, overrides: Dictionary, to_aim: Transform3D) -> Dictionary:
	var axis := fore - grip
	var dir := axis.normalized() if axis.length() > 0.001 else Vector3.FORWARD
	var length := maxf(axis.length() / 0.32, 0.1)
	var up := (Vector3.UP - dir * dir.dot(Vector3.UP)).normalized()
	var right := dir.cross(up).normalized()
	var rear := grip - dir * 0.30 * length
	var rise := 0.07 * length
	var at := func(a: float) -> Vector3: return rear + dir * a * length
	var out := {
		&"grip": grip, &"fore": fore, &"muzzle": muzzle,
		&"well": well if well is Vector3 else (at.call(0.40) as Vector3) - up * 0.01 * length,
		&"port": (at.call(0.42) as Vector3) + up * rise + right * 0.025 * length,
		&"bolt": (at.call(0.34) as Vector3) + up * rise + right * 0.07 * length,
		&"cover": (at.call(0.40) as Vector3) + up * (rise + 0.045 * length),
		&"cylinder": (at.call(0.42) as Vector3) + up * rise * 0.7 - right * 0.03 * length,
		&"breech": (at.call(0.40) as Vector3) + up * rise,
		&"under": (at.call(0.50) as Vector3) - up * 0.01 * length,
		&"length": length, &"right": right, &"up": up, &"dir": dir,
	}
	out[&"below"] = (out[&"well"] as Vector3) + Vector3(0.0, -0.22, 0.08)
	out[&"pouch"] = fore + Vector3(-0.12, -0.34, 0.14)
	out[&"near"] = (out[&"well"] as Vector3) + Vector3(-0.07, -0.13, 0.07)
	for key: Variant in overrides:
		var v: Variant = overrides[key]
		if v is Array and (v as Array).size() == 3:
			out[StringName(str(key))] = to_aim * Vector3(float(v[0]), float(v[1]), float(v[2]))
		elif v is Vector3:
			out[StringName(str(key))] = to_aim * (v as Vector3)
	return out


## Builds the sequence for [param art] with [param left] of [param magazine] rounds in it. [param start_share] is the part
## of the reload before the first round arrives, for a reload by the round (the arsenal's own timing); 0 otherwise.
func compose(art: ZeeWeaponArt, anchors: Dictionary, magazine: int, left: int, start_share: float = 0.0) -> void:
	_spec = art.reload if art != null else {}
	_anchors = anchors
	_grip = anchors.get(&"grip", Vector3.ZERO)
	style = style_of(art)
	magazine = maxi(magazine, 1)
	left = clampi(left, 0, magazine)
	empty = left == 0
	var missing := maxi(magazine - left, 1)
	var spent := magazine - left
	var length: float = anchors.get(&"length", 0.5)
	prop_scale = clampf(length / float(REAL_LENGTH.get(style, 0.8)), 0.3, 3.0) * float(_spec.get("prop_scale", 1.0))
	var part: StringName = PART.get(style, &"box_magazine")
	if art != null and art.magazine_part != &"":
		part = art.magazine_part
	part = StringName(str(_spec.get("part", part)))
	var eject := str(_spec.get("eject", "spent"))
	match style:
		&"magazine", &"pistol", &"cell":
			_magazine(part, style == &"pistol")
		&"revolver":
			ejected = {"none": 0, "all": magazine}.get(eject, spent)
			_revolver(ejected, missing)
		&"launcher":
			ejected = {"none": 0, "all": magazine}.get(eject, spent)
			loaded = magazine if eject == "all" else missing
			_launcher(ejected, loaded)
		&"tube":
			loaded = missing
			_tube(loaded, start_share)
		&"bolt":
			ejected = 1 if empty else 0
			loaded = missing
			_bolt(maxi(1, ceili(float(missing) / float(maxi(1, int(_spec.get("clip", 5)))))))
		&"belt":
			_belt(left > 0)
		_:
			return
	_finish()


func _magazine(part: StringName, pistol: bool) -> void:
	var gun := &"lift" if pistol else &"tilt"
	_add(&"tilt", 0.09, gun, &"fore")
	_add(&"grab", 0.07, gun, &"well", Vector3(0.0, -0.03, 0.0))
	_add(&"mag_out", 0.11, gun, &"below")
	_add(&"pouch", 0.15, gun, &"pouch")
	_add(&"rise", 0.12, gun, &"below", Vector3(0.0, 0.08, -0.04))
	_add(&"mag_in", 0.09, gun, &"well", Vector3(0.0, -0.035, 0.0))
	_add(&"seat", 0.05, gun, &"well", Vector3(0.0, -0.025, 0.0))
	if empty and style != &"cell":
		if pistol:
			_add(&"slide", 0.08, &"cant", &"bolt", Vector3(0.0, 0.02, 0.0))
			_add(&"slide_back", 0.07, &"cant", &"bolt", Vector3(0.0, 0.02, 0.07))
		else:
			_add(&"charge", 0.08, &"cant", &"fore", Vector3.ZERO, &"bolt")
			_add(&"charge_back", 0.07, &"cant", &"fore", Vector3.ZERO, &"bolt", Vector3(0.0, 0.0, 0.08))
	_add(&"return", 0.10, &"settle", &"fore")
	_add(&"rest", 0.06, &"rest", &"fore")
	own_out = [_t0(&"grab"), _t1(&"seat")]
	var old_track: Array = [[_t0(&"mag_out"), _t1(&"mag_out"), "hand", Vector3.ZERO, 0]]
	if empty:
		old_track = [[_t0(&"mag_out"), _t1(&"mag_out") + 0.08, "fall", _anchors[&"well"], 0]]
	else:
		old_track.append([_t0(&"pouch"), _mid(&"pouch"), "hand", Vector3.ZERO, 0])
	props.append({"part": part, "segments": old_track})
	props.append({"part": part, "segments": [[_mid(&"pouch") + 0.02, _t1(&"seat"), "hand", Vector3.ZERO, 0]]})


func _revolver(eject: int, missing: int) -> void:
	_add(&"open", 0.12, &"open", &"cylinder")
	_add(&"dump", 0.12, &"dump", &"cylinder", Vector3(0.0, 0.02, 0.0))
	var single := str(_spec.get("loader", "speedloader")) == "single"
	if single:
		loaded = missing
		for i in missing:
			_add(StringName("fetch_%d" % i), 0.30 / missing, &"open", &"near" if i > 0 else &"pouch")
			_add(StringName("load_%d" % i), 0.24 / missing, &"open", &"cylinder", Vector3(0.0, 0.02, 0.03))
	else:
		loaded = missing
		_add(&"fetch", 0.16, &"open", &"pouch")
		_add(&"load", 0.16, &"open", &"cylinder", Vector3(0.0, 0.03, 0.04))
		_add(&"twist", 0.06, &"open", &"cylinder", Vector3(0.0, 0.025, 0.035))
	_add(&"close", 0.10, &"cant", &"cylinder", Vector3(0.03, 0.0, 0.0))
	_add(&"return", 0.10, &"settle", &"fore")
	_add(&"rest", 0.05, &"rest", &"fore")
	_eject_cases(&"casing", eject, &"dump", &"cylinder")
	if single:
		for i in missing:
			props.append({"part": &"round", "segments": [[_mid(StringName("fetch_%d" % i)), _t1(StringName("load_%d" % i)), "hand", Vector3.ZERO, 0]]})
	else:
		props.append({"part": &"speedloader", "segments": [[_mid(&"fetch"), _t1(&"twist"), "hand", Vector3.ZERO, 0], [_t1(&"twist"), _t1(&"twist") + 0.07, "fall", _anchors[&"cylinder"], 0]]})


func _launcher(eject: int, count: int) -> void:
	_add(&"open", 0.10, &"break", &"breech")
	_add(&"eject", 0.08 + 0.02 * eject, &"break", &"breech", Vector3(0.0, 0.03, 0.03))
	for i in count:
		_add(StringName("fetch_%d" % i), 0.34 / count, &"break", &"pouch" if i == 0 else &"near")
		_add(StringName("load_%d" % i), 0.26 / count, &"break", &"breech", Vector3(0.0, 0.01, 0.02))
	_add(&"close", 0.10, &"cant", &"breech", Vector3(0.0, 0.05, 0.0))
	_add(&"return", 0.08, &"settle", &"fore")
	_add(&"rest", 0.04, &"rest", &"fore")
	_eject_cases(StringName(str(_spec.get("case", "grenade_case"))), eject, &"eject", &"breech")
	for i in count:
		props.append({"part": StringName(str(_spec.get("round", "grenade"))), "segments": [[_mid(StringName("fetch_%d" % i)), _t1(StringName("load_%d" % i)), "hand", Vector3.ZERO, 0]]})


func _tube(count: int, start_share: float) -> void:
	var per := (1.0 - start_share) / float(count) if start_share > 0.0 else 0.6 / float(count)
	_add(&"roll", start_share if start_share > 0.0 else 0.14, &"roll", &"under", Vector3(0.0, -0.04, 0.02))
	for i in count:
		var share := per * (0.55 if empty and i == count - 1 else 1.0)
		_add(StringName("fetch_%d" % i), share * 0.5, &"roll", &"pouch" if i == 0 else &"near")
		_add(StringName("push_%d" % i), share * 0.5, &"roll", &"under", Vector3(0.0, -0.01, -0.03))
	if empty:
		_add(&"pump_back", per * 0.2, &"cant", &"fore", Vector3(0.0, 0.0, 0.10))
		_add(&"pump", per * 0.15, &"cant", &"fore")
		_add(&"rest", per * 0.1, &"rest", &"fore")
	else:
		_add(&"rest", 0.001, &"rest", &"fore")
	for i in count:
		props.append({"part": StringName(str(_spec.get("round", "shell"))), "segments": [[_mid(StringName("fetch_%d" % i)), _t1(StringName("push_%d" % i)), "hand", Vector3.ZERO, 0]]})


func _bolt(clips: int) -> void:
	_add(&"lift", 0.08, &"port", &"fore", Vector3.ZERO, &"bolt")
	_add(&"bolt_up", 0.06, &"port", &"fore", Vector3.ZERO, &"bolt", Vector3(0.0, 0.03, 0.0))
	_add(&"bolt_back", 0.08, &"port", &"fore", Vector3.ZERO, &"bolt", Vector3(0.0, 0.03, 0.09))
	for c in clips:
		_add(StringName("fetch_%d" % c), 0.24 / clips, &"port", &"pouch" if c == 0 else &"near", Vector3.ZERO, &"bolt", Vector3(0.0, 0.03, 0.09))
		_add(StringName("clip_%d" % c), 0.10 / clips, &"port", &"port", Vector3(0.0, 0.07, 0.0), &"bolt", Vector3(0.0, 0.03, 0.09))
		_add(StringName("press_%d" % c), 0.12 / clips, &"port", &"port", Vector3(0.0, 0.02, 0.0), &"bolt", Vector3(0.0, 0.03, 0.09))
	_add(&"bolt_fwd", 0.08, &"port", &"fore", Vector3.ZERO, &"bolt", Vector3(0.0, 0.03, 0.0))
	_add(&"bolt_down", 0.05, &"port", &"fore", Vector3.ZERO, &"bolt")
	_add(&"return", 0.06, &"settle", &"fore")
	_add(&"rest", 0.05, &"rest", &"fore")
	_eject_cases(&"casing", ejected, &"bolt_back", &"port")
	for c in clips:
		props.append({"part": &"clip", "segments": [[_mid(StringName("fetch_%d" % c)), _t1(StringName("clip_%d" % c)), "hand", Vector3.ZERO, 0],
			[_t1(StringName("clip_%d" % c)), _t1(StringName("press_%d" % c)), "at", (_anchors[&"port"] as Vector3) + Vector3(0.0, 0.05, 0.0), 0]]})


func _belt(stub: bool) -> void:
	_add(&"lift", 0.07, &"heavy", &"cover")
	_add(&"cover_open", 0.07, &"heavy", &"cover", Vector3(0.0, 0.09, -0.02))
	_add(&"box_grab", 0.06, &"heavy", &"well", Vector3(0.0, -0.02, 0.0))
	_add(&"box_out", 0.09, &"heavy", &"below")
	_add(&"fetch", 0.13, &"heavy", &"pouch")
	_add(&"box_in", 0.11, &"heavy", &"well", Vector3(0.0, -0.03, 0.0))
	_add(&"belt_lay", 0.10, &"heavy", &"cover", Vector3(0.0, 0.02, 0.0))
	_add(&"cover_close", 0.08, &"heavy", &"cover", Vector3(0.0, 0.10, -0.02))
	_add(&"slap", 0.05, &"heavy", &"cover")
	if empty:
		_add(&"charge", 0.07, &"cant", &"fore", Vector3.ZERO, &"bolt")
		_add(&"charge_back", 0.06, &"cant", &"fore", Vector3.ZERO, &"bolt", Vector3(0.0, 0.0, 0.09))
	_add(&"return", 0.08, &"settle", &"fore")
	_add(&"rest", 0.05, &"rest", &"fore")
	own_out = [_t0(&"box_grab"), _t1(&"box_in")]
	props.append({"part": &"ammo_box", "segments": [[_t0(&"box_out"), _t1(&"box_out") + 0.06, "fall", _anchors[&"well"], 0]]})
	props.append({"part": &"ammo_box", "segments": [[_mid(&"fetch"), _t1(&"box_in"), "hand", Vector3.ZERO, 0]]})
	props.append({"part": &"belt", "segments": [[_t1(&"box_in"), _t1(&"belt_lay"), "hand", Vector3.ZERO, 0], [_t1(&"belt_lay"), _t1(&"slap"), "at", _anchors[&"cover"], 0]]})
	if stub:
		props.append({"part": &"belt", "segments": [[_t1(&"cover_open"), _t1(&"cover_open") + 0.08, "fall", _anchors[&"cover"], 0]]})


## [param count] cases thrown from [param from] through phase [param phase], each a little after the last.
func _eject_cases(part: StringName, count: int, phase: StringName, from: StringName) -> void:
	var t0 := _t0(phase)
	var span := maxf(_t1(phase) - t0, 0.02)
	for i in count:
		var start := t0 + span * 0.6 * float(i) / float(maxi(count, 1))
		props.append({"part": part, "segments": [[start, minf(start + 0.10, 1.0), "eject", _anchors.get(from, _grip), i]]})


func _add(name: StringName, weight: float, gun: StringName, left_at: StringName, left_off := Vector3.ZERO, right_at: StringName = &"grip", right_off := Vector3.ZERO) -> void:
	var w := float((_spec.get("weights", {}) as Dictionary).get(String(name), weight))
	var hands: Dictionary = (_spec.get("hands", {}) as Dictionary).get(String(name), {})
	var left := _point(hands.get("left", null), left_at, left_off)
	var right := _point(hands.get("right", null), right_at, right_off) - _grip
	phases.append({"name": name, "w": maxf(w, 0.0), "gun": gun, "left": left, "right": right})


func _point(row: Variant, anchor: StringName, offset: Vector3) -> Vector3:
	if row is Array and (row as Array).size() == 2 and row[1] is Array and (row[1] as Array).size() == 3:
		anchor = StringName(str(row[0]))
		offset = Vector3(float(row[1][0]), float(row[1][1]), float(row[1][2]))
	return (_anchors.get(anchor, _anchors.get(&"fore", Vector3.ZERO)) as Vector3) + offset


## Weights to times, then the keys. Props were written against the cumulative weights, so they are rescaled too.
func _finish() -> void:
	var total := 0.0
	for p: Dictionary in phases:
		total += float(p.w)
	total = maxf(total, 0.0001)
	var t := 0.0
	var fore: Vector3 = _anchors.get(&"fore", Vector3.ZERO)
	left_keys = [[0.0, fore, Vector3.ZERO]]
	right_keys = [[0.0, Vector3.ZERO, Vector3.ZERO]]
	gun_keys = [[0.0, Vector3.ZERO, Vector3.ZERO]]
	for p: Dictionary in phases:
		p.t0 = t / total
		t += float(p.w)
		p.t1 = t / total
		if p.t1 - float(left_keys.back()[0]) < 0.004:
			continue
		var g: Array = GUN.get(p.gun, GUN[&"rest"])
		left_keys.append([p.t1, p.left, Vector3.ZERO])
		right_keys.append([p.t1, p.right, Vector3.ZERO])
		gun_keys.append([p.t1, g[0], g[1]])
	if float(left_keys.back()[0]) < 1.0:
		left_keys.append([1.0, fore, Vector3.ZERO])
		right_keys.append([1.0, Vector3.ZERO, Vector3.ZERO])
		gun_keys.append([1.0, Vector3.ZERO, Vector3.ZERO])
	for prop: Dictionary in props:
		for s: Array in prop.segments:
			s[0] = clampf(float(s[0]) / total, 0.0, 1.0)
			s[1] = clampf(float(s[1]) / total, 0.0, 1.0)
	if own_out.size() == 2:
		own_out = [float(own_out[0]) / total, float(own_out[1]) / total]


func _phase(name: StringName) -> Dictionary:
	for p: Dictionary in phases:
		if p.name == name:
			return p
	return {}


## Phase times in cumulative weight, before _finish turns them into fractions.
func _t0(name: StringName) -> float:
	var t := 0.0
	for p: Dictionary in phases:
		if p.name == name:
			return t
		t += float(p.w)
	return t


func _t1(name: StringName) -> float:
	return _t0(name) + float(_phase(name).get("w", 0.0))


func _mid(name: StringName) -> float:
	return (_t0(name) + _t1(name)) * 0.5


## The support hand at [param f], in Aim space.
func left_hand(f: float) -> Vector3:
	return ZeeWeaponPose.sample_keys(left_keys, f)[0]


## The firing hand's offset from its grip at [param f].
func right_offset(f: float) -> Vector3:
	return ZeeWeaponPose.sample_keys(right_keys, f)[0]


## The phase playing at [param f], or an empty name outside the reload.
func phase_at(f: float) -> StringName:
	for p: Dictionary in phases:
		if f >= float(p.t0) and f < float(p.t1):
			return p.name
	return &""


## Every prop at [param f]: [{part, index, shown, at (Aim space), turn (degrees)}], one entry per track.
func props_at(f: float) -> Array:
	var out: Array = []
	var right: Vector3 = _anchors.get(&"right", Vector3.RIGHT)
	for k in props.size():
		var prop: Dictionary = props[k]
		var entry := {"part": prop.part, "index": k, "shown": false, "at": Vector3.ZERO, "turn": Vector3.ZERO}
		for s: Array in prop.segments:
			var t0 := float(s[0])
			var t1 := float(s[1])
			if f < t0 or f >= t1 or t1 <= t0:
				continue
			var u := (f - t0) / (t1 - t0)
			var a: Vector3 = s[3]
			entry.shown = true
			match str(s[2]):
				"hand":
					entry.at = left_hand(f) + CARRY
				"rhand":
					entry.at = _grip + right_offset(f) + CARRY
				"at":
					entry.at = a
				"fall":
					entry.at = a + Vector3(0.0, -0.45 * u * u - 0.03 * u, 0.03 * u)
					entry.turn = Vector3(-40.0 * u, 0.0, 12.0 * u)
				"eject":
					var i := int(s[4])
					var spread := float(i % 3 - 1) * 0.015
					entry.at = a + right * (0.10 * u + spread) + Vector3(0.0, 0.07 * u - 0.40 * u * u, 0.02 * u + spread)
					entry.turn = Vector3(0.0, 300.0 * u, 540.0 * u + 37.0 * i)
			break
		out.append(entry)
	return out


## True while the gun's own magazine is out of it.
func own_magazine_out(f: float) -> bool:
	return own_out.size() == 2 and f >= float(own_out[0]) and f < float(own_out[1])


func describe() -> Dictionary:
	var names: Array = []
	for p: Dictionary in phases:
		names.append(String(p.name))
	return {"style": style, "empty": empty, "ejected": ejected, "loaded": loaded, "phases": names, "props": props.size()}
