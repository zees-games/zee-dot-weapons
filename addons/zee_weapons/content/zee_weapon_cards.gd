class_name ZeeWeaponCards
extends RefCounted

## What a loadout screen says about each weapon: a line, a kind, and statistics as bars.
##
## [codeblock]
## var card := ZeeWeaponCards.card(ZeeWeaponPack.table()[&"rifle"])
## # {"detail": "The all-rounder ...", "kind": "Primary", "stats": [{"label": "Damage",
## #  "value": 0.15, "text": "23"}, ...]}
## menu.use_loadout(offer_fn, choose_fn, func(_slot, choice): return ZeeWeaponCards.card(table[choice.id]))
## [/codeblock]
##
## [b]Derived from the documents, never written down twice.[/b] Every number is read off the
## weapon's own [DotWeaponDef] and its ballistics at [constant ZeeWeaponPack.TICK_RATE], so a
## retune shows on the card the day it lands; a second table of "card numbers" would be the one
## that is wrong. The bars are scaled against fixed ceilings rather than the pack's own maxima, so
## a second pack (zed-dot-weapons) with a bigger gun does not shrink every bar here.
##
## Content only: a dedicated server never calls this, and nothing here touches art.

# No CHANNEL: a table of answers built by static functions; it logs nothing.

## Where a bar is full.
const MAX_DAMAGE := 150.0
const MAX_RATE := 1200.0
const MAX_RANGE := 200.0
const MAX_MAGAZINE := 100.0
const MAX_REACH := 3.0
const MAX_RADIUS := 6.0
const MAX_CARRY := 4.0

## The line under a weapon's name: what it is for, from the reasoning beside its row in
## [ZeeWeaponPack]. A weapon not here (another pack's) gets none.
const BLURB := {
	&"fists": "Always carried, so you are never holding nothing.",
	&"knife": "The fastest weapon there is, and the only one that out-trades a sidearm inside two metres.",
	&"shiv": "Faster still and weaker: for finishing rather than starting.",
	&"hatchet": "A heavier swing than the knife with a little more reach.",
	&"mallet": "The hardest single hit, and the slowest. A miss costs a second.",
	&"pickaxe": "The longest reach of anything without a barrel.",
	&"spade": "The widest arc: it catches somebody strafing past.",
	&"pistol": "Never runs out of reach, always loses a fair fight.",
	&"revolver": "Six shots that each hurt, and a long reload. For somebody who expects to hit.",
	&"machine_pistol": "Quiet, and the only automatic that fits in the sidearm slot.",
	&"derringer": "Two enormous shots and nothing at range. The last resort.",
	&"smg": "Fast, light, and out of its depth past thirty metres.",
	&"carbine": "The rifle for when you do not know what the fight will be.",
	&"rifle": "The all-rounder every other primary is balanced against.",
	&"bullpup": "Accurate on the move, where nothing else is.",
	&"battle_rifle": "Semi-automatic and hard-hitting: two taps at any range.",
	&"burst_rifle": "Three rounds a press, tight enough that all three land at range.",
	&"shotgun": "Nine pellets in a fixed ring, so its range can be learned.",
	&"drum_shotgun": "Automatic and fed from a drum: volume instead of one answer.",
	&"marksman": "Semi-automatic and scoped: the answer to a rooftop.",
	&"sniper": "One shot takes most of a player, then a second and a half to the next.",
	&"minigun": "Belt-fed: it never reloads, it simply runs out.",
	&"launcher": "Low direct damage, high splash. Aim at the floor.",
	&"beamer": "Damage while held on a target: rewards tracking, not flicks.",
	&"charge_rifle": "Hold to charge, release to fire; the shot is worth the draw.",
	&"frag": "Explodes on a fuse, wherever it has rolled to.",
	&"sticky": "Sticks where it lands, on a shorter fuse.",
}

const KIND := {
	ZeeWeaponIds.SLOT_MELEE: "Melee",
	ZeeWeaponIds.SLOT_SIDEARM: "Sidearm",
	ZeeWeaponIds.SLOT_PRIMARY: "Primary",
	ZeeWeaponIds.SLOT_HEAVY: "Heavy",
	ZeeWeaponIds.SLOT_THROWN: "Grenade",
}


## Everything a card shows for [param def]: `detail`, `kind`, `stats` (`[{label, value, text}]`).
## Empty for null.
static func card(def: DotWeaponDef) -> Dictionary:
	if def == null:
		return {}
	return {"detail": str(BLURB.get(def.id, def.description)), "kind": str(KIND.get(def.slot, "")), "stats": stats(def)}


## The bars for [param def]: what matters for its kind. A gun: damage per trigger pull, fire rate,
## range, accuracy, magazine. Melee: damage, swings a minute, reach. A grenade: blast, radius,
## carried.
static func stats(def: DotWeaponDef) -> Array:
	if def == null:
		return []
	var b := def.tuning as DotWeaponBallistics
	var per_min := 60.0 * float(ZeeWeaponPack.TICK_RATE) / float(maxi(def.use_interval_ticks, 1))
	if def.fire_mode == DotWeaponDef.Fire.BURST:
		# A press fires burst_count rounds; the interval is between presses.
		per_min *= float(maxi(def.burst_count, 1))
	if def.slot == ZeeWeaponIds.SLOT_THROWN:
		var blast := b.splash_damage if b != null else 0.0
		var radius := b.splash_radius if b != null else 0.0
		return [
			_bar("Blast", blast / MAX_DAMAGE, "%d" % roundi(blast)),
			_bar("Radius", radius / MAX_RADIUS, "%.1f m" % radius),
			_bar("Carried", float(def.reserve) / MAX_CARRY, "%d" % def.reserve),
		]
	var hit := 0.0
	if b != null:
		hit = b.damage * float(maxi(b.pellets, 1))
		hit = maxf(hit, b.splash_damage)
	if def.has_tag(ZeeWeaponIds.TAG_MELEE) or def.slot == ZeeWeaponIds.SLOT_MELEE:
		var reach := b.max_range if b != null else 0.0
		return [
			_bar("Damage", hit / MAX_DAMAGE, "%d" % roundi(hit)),
			_bar("Speed", per_min / 200.0, "%d/min" % roundi(per_min)),
			_bar("Reach", reach / MAX_REACH, "%.1f m" % reach),
		]
	var out: Array = [_bar("Damage", hit / MAX_DAMAGE, "%d" % roundi(hit))]
	if def.is_charged():
		out.append(_bar("Fire rate", per_min / MAX_RATE, "charged"))
	else:
		out.append(_bar("Fire rate", per_min / MAX_RATE, "%d/min" % roundi(per_min)))
	var reach_m := b.max_range if b != null else 0.0
	out.append(_bar("Range", reach_m / MAX_RANGE, "%d m" % roundi(reach_m)))
	var spread := b.spread if b != null else 0.0
	out.append(_bar("Accuracy", 1.0 - clampf(spread / 4.5, 0.0, 1.0), "%.1f°" % spread))
	if def.magazine > 0:
		out.append(_bar("Magazine", float(def.magazine) / MAX_MAGAZINE, "%d" % def.magazine))
	elif def.uses_ammo():
		out.append(_bar("Belt", float(def.reserve) / (MAX_MAGAZINE * 3.0), "%d" % def.reserve))
	return out


static func _bar(label: String, value: float, text: String) -> Dictionary:
	return {"label": label, "value": clampf(value if is_finite(value) else 0.0, 0.0, 1.0), "text": text}
