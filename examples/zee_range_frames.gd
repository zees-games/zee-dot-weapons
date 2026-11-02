extends RefCounted

## The frame lists of the range's contact sheet (`--sheet`), and the flags that swap them.

## The frames of one weapon's contact sheet, in order: a label and what to do before it.
## A view model is motion; one frame at rest says nothing about the reload, the kick or the sway.
const SHEET_FRAMES := [
	["hip", "rest"], ["aimed", "aim"],
	["fire 1", "fire:1"], ["fire 2", "fire:2"], ["fire 4", "fire:4"],
	["fire 8", "fire:8"], ["fire 14", "fire:14"],
	["reload 0%", "reload:0.0"], ["reload 25%", "reload:0.25"],
	["reload 50%", "reload:0.5"], ["reload 75%", "reload:0.75"],
	["reload 90%", "reload:0.9"],
	["walking", "walk"], ["turning right", "turn"],
	["draw 30%", "deploy:0.3"], ["draw 70%", "deploy:0.7"],
	["in shade", "shade"], ["aimed, fire 4", "aimfire:4"],
]

## `--moves`: how the weapon moves with its carrier, hip and aimed. Review on this after
## touching sway, tilt, bob or the landing.
const MOVE_FRAMES := [
	["hip", "rest"], ["aimed", "aim"],
	["strafe right", "strafe:5"], ["strafe left", "strafe:-5"],
	["aimed, strafe right", "aimstrafe:5"], ["aimed, strafe left", "aimstrafe:-5"],
	["turning right", "turn"], ["aimed, turning right", "aimturn"],
	["walking", "walk"], ["aimed, walking", "aimwalk"],
	["landing", "land"], ["aimed, landing", "aimland"],
	["sprint, stride low", "sprint:30"], ["sprint, stride high", "sprint:45"],
]


## The frames for the command-line [param args]; [param reloads] and [param aimin] are `--reloads` and `--aimin`.
static func frames(args: PackedStringArray, reloads: String, aimin: String) -> Array:
	var frames: Array = SHEET_FRAMES
	if args.has("--moves"):
		frames = MOVE_FRAMES
	# Five wall distances in four directions (head-on, wall only below, only above, only on the right).
	if args.has("--wallsheet"):
		frames = []
		for kind: String in ["full", "below", "above", "right"]:
			for d: float in [0.9, 0.7, 0.55, 0.4, 0.28]:
				frames.append(["wall %s %.0f%%" % [kind, d * 100.0], "wall:%f:%s" % [d, kind]])
	# A whole reload on one sheet, which the five reload frames cannot show for a gun fed a round at a time.
	if reloads != "":
		frames = []
		for fraction in reloads.split_floats(","):
			frames.append(["reload %d%%" % roundi(fraction * 100.0), "reload:%f" % fraction])
	# The charge ball at 10-100% (the swirl's phase differs by time), a fizzle, and the beam after release.
	if args.has("--charges"):
		frames = []
		for f: float in [0.1, 0.3, 0.6, 0.9, 1.0]:
			frames.append(["charge %d%%" % roundi(f * 100.0), "charge:%f" % f])
		frames.append(["fizzle +3", "fizzle:3"])
		frames.append(["fizzle +9", "fizzle:9"])
		for n2: int in [0, 6, 14, 24]:
			frames.append(["beam +%d" % n2, "rail:%d" % n2])
	# The sights coming up after that many 60 fps steps: the quick scope's transition.
	if aimin != "":
		frames = []
		for steps in aimin.split_floats(","):
			frames.append(["aim-in %d" % int(steps), "aimin:%f" % steps])
	return frames
