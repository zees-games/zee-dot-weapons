## Authored motion keys of ZeeWeaponPose, split out for file size.
## Keys, not springs, for what a hand does on purpose: a draw and a reload have a shape somebody chose, which a spring cannot make.
## Each key is [t, position in metres, rotation in degrees (pitch up, yaw muzzle-left, roll counter-clockwise)], applied about the grip on top of the hip hold.
extends RefCounted

## Out of the holster: up from below, rolled away, settling just past the mark.
const DRAW_KEYS := [
	[0.0, Vector3(0.03, -0.30, 0.06), Vector3(-35.0, -12.0, 50.0)],
	[0.35, Vector3(0.015, -0.10, 0.03), Vector3(-12.0, -6.0, 18.0)],
	[0.70, Vector3(0.0, 0.006, 0.0), Vector3(3.0, 0.0, -4.0)],
	[0.86, Vector3(0.0, -0.002, 0.0), Vector3(-0.8, 0.0, 1.0)],
	[1.0, Vector3.ZERO, Vector3.ZERO],
]

## A melee swing: drawn back and up to the right (0-0.18), cut down and across to the left
## through the middle of the screen (0.18-0.5), held a moment at the end of the cut, and
## brought back.
##
## [b]Keys, because a swing is an action.[/b] A swing used to be the recoil spring alone, and
## a melee weapon has no recoil: the knife, the hatchet and the fists did nothing on screen when
## they struck, which reads as the weapon being broken.
const SWING_KEYS := [
	[0.0, Vector3.ZERO, Vector3.ZERO],
	[0.18, Vector3(0.04, 0.035, 0.03), Vector3(22.0, -16.0, -14.0)],
	[0.40, Vector3(-0.11, -0.05, -0.10), Vector3(-40.0, 38.0, 24.0)],
	[0.52, Vector3(-0.14, -0.08, -0.08), Vector3(-52.0, 46.0, 30.0)],
	[0.78, Vector3(-0.04, -0.03, -0.02), Vector3(-14.0, 12.0, 8.0)],
	[1.0, Vector3.ZERO, Vector3.ZERO],
]

## A throw: drawn back over the shoulder, then forward and down past the middle of the screen,
## and back up into the hand.
const THROW_KEYS := [
	[0.0, Vector3.ZERO, Vector3.ZERO],
	[0.25, Vector3(0.03, 0.08, 0.10), Vector3(35.0, -8.0, -10.0)],
	[0.50, Vector3(-0.06, -0.04, -0.16), Vector3(-30.0, 14.0, 8.0)],
	[0.62, Vector3(-0.07, -0.16, -0.10), Vector3(-45.0, 16.0, 10.0)],
	[0.85, Vector3(0.0, -0.10, 0.0), Vector3(-12.0, 4.0, 0.0)],
	[1.0, Vector3.ZERO, Vector3.ZERO],
]

## A long gun: lifted in toward the middle of the screen and rolled onto its side, so the
## magazine well is in sight while the old magazine drops (0.10-0.28); held there while the hand
## fetches the next and brings it up (0.36-0.55); a jolt up as it seats (0.55-0.60); rolled back
## down to the hip, and a rack (0.84-0.90).
##
## [b]Lifted, because at the hip the well is below the bottom of the screen.[/b] The first keys
## rolled and dipped the gun where it sat: every magazine fell, and every hand fetched one, out
## of frame, and what a player saw was the gun tilting and coming back. The play test called
## that "no proper reload animations"; the contact sheet showed the same.
const RELOAD_KEYS_RIFLE := [
	[0.0, Vector3.ZERO, Vector3.ZERO],
	[0.10, Vector3(-0.045, 0.035, 0.01), Vector3(8.0, 10.0, -30.0)],
	[0.20, Vector3(-0.07, 0.055, 0.015), Vector3(12.0, 14.0, -42.0)],
	[0.42, Vector3(-0.075, 0.06, 0.015), Vector3(10.0, 15.0, -44.0)],
	[0.55, Vector3(-0.07, 0.05, 0.01), Vector3(14.0, 14.0, -40.0)],
	[0.60, Vector3(-0.07, 0.066, 0.01), Vector3(8.0, 14.0, -38.0)],
	[0.74, Vector3(-0.035, 0.03, 0.0), Vector3(4.0, 6.0, -16.0)],
	[0.84, Vector3(0.0, -0.004, 0.025), Vector3(-3.0, 2.0, -4.0)],
	[0.90, Vector3(0.0, -0.004, -0.006), Vector3(2.0, 0.0, 0.0)],
	[1.0, Vector3.ZERO, Vector3.ZERO],
]

## A pistol: brought up and in, tipped muzzle-up and turned in, so the grip's foot (the magazine
## well) is in sight for the other hand; a smaller roll; the slide racked at the end.
const RELOAD_KEYS_PISTOL := [
	[0.0, Vector3.ZERO, Vector3.ZERO],
	[0.12, Vector3(-0.065, 0.075, 0.0), Vector3(30.0, 18.0, -20.0)],
	[0.45, Vector3(-0.075, 0.085, 0.0), Vector3(34.0, 20.0, -24.0)],
	[0.56, Vector3(-0.07, 0.075, 0.0), Vector3(36.0, 18.0, -22.0)],
	[0.62, Vector3(-0.07, 0.09, 0.0), Vector3(28.0, 18.0, -20.0)],
	[0.78, Vector3(-0.02, 0.02, 0.0), Vector3(7.0, 6.0, -6.0)],
	[0.87, Vector3(0.0, -0.004, 0.02), Vector3(-2.0, 2.0, 0.0)],
	[0.93, Vector3(0.0, -0.003, -0.004), Vector3(1.5, 0.0, 0.0)],
	[1.0, Vector3.ZERO, Vector3.ZERO],
]

## A heavy weapon with a box or a cell: lifted up and in like a rifle and rolled to show the
## well, a little less (it is longer and the roll swings more of it across the screen), the new
## box or cell carried up from 0.36 and seated at 0.58, heaved back to the hip and racked.
##
## [b]Lifted as far as a rifle.[/b] The first heavy keys lifted half as much, and the box, the
## cell and every round the hand fetched stayed below the bottom of the screen: the contact
## sheet showed a gun tilting, which is what the play test said.
const RELOAD_KEYS_HEAVY := [
	[0.0, Vector3.ZERO, Vector3.ZERO],
	[0.10, Vector3(-0.06, 0.05, 0.015), Vector3(7.0, 10.0, -22.0)],
	[0.20, Vector3(-0.10, 0.09, 0.03), Vector3(11.0, 16.0, -32.0)],
	[0.42, Vector3(-0.105, 0.095, 0.03), Vector3(10.0, 17.0, -34.0)],
	[0.55, Vector3(-0.10, 0.085, 0.025), Vector3(13.0, 16.0, -31.0)],
	[0.60, Vector3(-0.10, 0.10, 0.025), Vector3(8.0, 16.0, -29.0)],
	[0.74, Vector3(-0.05, 0.045, 0.01), Vector3(4.0, 7.0, -13.0)],
	[0.84, Vector3(0.0, -0.004, 0.028), Vector3(-3.0, 2.0, -4.0)],
	[0.91, Vector3(0.0, -0.004, -0.006), Vector3(2.0, 0.0, 0.0)],
	[1.0, Vector3.ZERO, Vector3.ZERO],
]

## A bolt gun fed a round at a time: brought up and in with its top and right side to the eye,
## the bolt yanked back (0.12-0.20, a jolt back), held still while the rounds are pressed in
## (ZeeViewModel `FEED_START`-`FEED_END`), the bolt shoved home (0.75-0.82, a jolt forward), down
## to the hip.
const RELOAD_KEYS_BOLT := [
	[0.0, Vector3.ZERO, Vector3.ZERO],
	[0.08, Vector3(-0.06, 0.06, 0.02), Vector3(8.0, 14.0, -4.0)],
	[0.14, Vector3(-0.10, 0.095, 0.04), Vector3(10.0, 20.0, -6.0)],
	[0.20, Vector3(-0.10, 0.09, 0.06), Vector3(8.0, 20.0, -8.0)],
	[0.26, Vector3(-0.105, 0.10, 0.05), Vector3(10.0, 21.0, -6.0)],
	[0.48, Vector3(-0.107, 0.102, 0.05), Vector3(10.0, 21.0, -6.0)],
	[0.70, Vector3(-0.105, 0.10, 0.05), Vector3(10.0, 21.0, -6.0)],
	[0.75, Vector3(-0.102, 0.098, 0.06), Vector3(9.0, 20.0, -7.0)],
	[0.82, Vector3(-0.10, 0.094, 0.025), Vector3(8.0, 20.0, -4.0)],
	[0.90, Vector3(-0.035, 0.03, 0.005), Vector3(3.0, 7.0, -2.0)],
	[1.0, Vector3.ZERO, Vector3.ZERO],
]

## A pump gun fed shells through the port underneath: lifted in and rolled well over so the
## underside is to the eye (0.10-0.22), held still while the shells are pushed up into it
## (ZeeViewModel `FEED_START`-`FEED_END`), back down, and the pump worked (0.80-0.90: back, then
## forward). Held like the bolt gun, because each shell needs the port in the same place.
const RELOAD_KEYS_TUBE := [
	[0.0, Vector3.ZERO, Vector3.ZERO],
	[0.10, Vector3(-0.05, 0.045, 0.01), Vector3(9.0, 11.0, -30.0)],
	[0.22, Vector3(-0.08, 0.07, 0.015), Vector3(13.0, 15.0, -48.0)],
	[0.46, Vector3(-0.082, 0.072, 0.015), Vector3(13.0, 15.0, -49.0)],
	[0.68, Vector3(-0.08, 0.07, 0.015), Vector3(13.0, 15.0, -48.0)],
	[0.76, Vector3(-0.035, 0.03, 0.005), Vector3(5.0, 6.0, -18.0)],
	[0.83, Vector3(0.0, -0.004, 0.03), Vector3(-2.0, 2.0, -3.0)],
	[0.90, Vector3(0.0, -0.004, -0.008), Vector3(2.0, 0.0, 0.0)],
	[1.0, Vector3.ZERO, Vector3.ZERO],
]

## A break-open launcher: the muzzle drops (0.08-0.18) so the breech comes up toward the eye,
## held open while the grenade is pushed in, snapped shut with the muzzle flicking up (0.72-0.78),
## down to the hip.
const RELOAD_KEYS_BREAK := [
	[0.0, Vector3.ZERO, Vector3.ZERO],
	[0.10, Vector3(-0.05, 0.05, 0.0), Vector3(-6.0, 12.0, -6.0)],
	[0.18, Vector3(-0.08, 0.07, 0.0), Vector3(-14.0, 18.0, -8.0)],
	[0.26, Vector3(-0.08, 0.068, 0.0), Vector3(-13.0, 18.0, -8.0)],
	[0.48, Vector3(-0.082, 0.07, 0.0), Vector3(-13.0, 18.0, -8.0)],
	[0.70, Vector3(-0.08, 0.068, 0.0), Vector3(-13.0, 18.0, -8.0)],
	[0.76, Vector3(-0.075, 0.078, 0.0), Vector3(5.0, 15.0, -6.0)],
	[0.82, Vector3(-0.05, 0.05, 0.0), Vector3(2.0, 9.0, -4.0)],
	[0.92, Vector3(0.0, 0.004, 0.0), Vector3(-1.0, 1.0, 0.0)],
	[1.0, Vector3.ZERO, Vector3.ZERO],
]

## A launcher loaded down the muzzle: tipped muzzle-up and turned in so the mouth of the tube is
## in front of the eye, held while the rocket is pushed in, a jolt down as it seats (0.72-0.76),
## brought back down to the shoulder.
const RELOAD_KEYS_MUZZLE := [
	[0.0, Vector3.ZERO, Vector3.ZERO],
	[0.12, Vector3(-0.06, 0.03, 0.03), Vector3(20.0, 16.0, -6.0)],
	[0.24, Vector3(-0.09, 0.05, 0.05), Vector3(32.0, 22.0, -8.0)],
	[0.48, Vector3(-0.092, 0.052, 0.05), Vector3(32.0, 22.0, -8.0)],
	[0.70, Vector3(-0.09, 0.05, 0.05), Vector3(32.0, 22.0, -8.0)],
	[0.76, Vector3(-0.09, 0.04, 0.05), Vector3(28.0, 22.0, -8.0)],
	[0.86, Vector3(-0.03, 0.01, 0.015), Vector3(8.0, 7.0, -2.0)],
	[1.0, Vector3.ZERO, Vector3.ZERO],
]

