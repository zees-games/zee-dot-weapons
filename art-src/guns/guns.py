# One recipe per real-world gun: which donor parts it keeps, what of ours replaces the rest,
# and its colours. Each returns (gun object, magazine object or None, length in metres).
#
# The length is the one the current hold in ZeeWeaponArtTable was tuned for, so a new model
# lands where the old one sat; the magazine's offset is measured on export.
#
# u / v below are fractions of the donor's own side view (u from the butt to the muzzle, v
# from the bottom up), read off a side render; part numbers are in the donor's dump order.
import bpy
from mathutils import Vector

from zee_kit import (at, bevel, box, cut, cyl, donor, join, kenney, lowest, move, paint,
                     place, rail, rotate, scale, shear, taper, top_at, u2y, v2z)

# Metres per source unit: the Quaternius pack shares one scale, so parts of different
# donors pulled at this unit fit each other.
U = 0.174

# The donors' own material names, mapped to ours per gun.
AR2 = ("Main", "MainDark", "MainLight", "Metal", "DarkMetal", "DarkWood", "Black", "Grey", "Wood")


def _all(name):
    return {m: name for m in AR2 + ("LightMetal", "Green", "Glass", "Black2")}


def _ports(y0, z, x, n, step, size, material="polymer", side="both"):
    """A row of small dark blocks standing proud of a side face: slots, vents, ports."""
    out = []
    for i in range(n):
        for sx in ((-1, 1) if side == "both" else ((1,) if side == "right" else (-1,))):
            out.append(box(size, "ccc", (sx * x, y0 + i * step, z), material, 0.1))
    return out


# --- Rifle: a flat-top with a long octagonal free-float handguard ---------------------------
#
# Receiver and grip: Quaternius AssaultRifle2_2, cut off at the front of the upper.
# Stock: AssaultRifle2_1's, stretched taller, with a cheek riser of ours.
# Ours: the octagonal handguard with its slots and top rail, barrel, flash hider, front sight.

def rifle():
    keep = lambda p: 0.24 < p.uc < 0.6 and not (p.mat == "Main" and p.v1 < 0.61 and p.u0 > 0.44)
    m = {"Main": "graphite", "MainDark": "polymer", "MainLight": "graphite", "Metal": "steel",
         "DarkMetal": "blued", "DarkWood": "walnut"}
    recv = donor("AssaultRifle2_2", keep=keep, unit=U, mats=m)
    front = u2y(recv, 0.555)
    cut(recv, front, "back")
    bevel(recv, 0.0012)
    zc = v2z(recv, 0.735)
    r = 0.031
    hg = cyl(r, 0.31, "cbc", (0, front - 0.004, zc), material="tan", sides=8, chamfer=0.05)
    rotate(hg, 22.5, "Y")
    flat = r * 0.924
    parts = [recv, hg]
    parts += _ports(front + 0.05, zc - 0.004, flat + 0.001, 5, 0.05, (0.004, 0.026, 0.008))
    parts.append(rail(0.30, "cbd", (0, front, zc + flat - 0.002), width=0.02))
    parts.append(cyl(0.0085, 0.12, "cbc", (0, front + 0.30, zc), material="steel"))
    hider = cyl(0.0125, 0.05, "cbc", (0, front + 0.41, zc), material="polymer", sides=6)
    parts.append(hider)
    parts += _ports(front + 0.425, zc, 0.0115, 3, 0.012, (0.003, 0.008, 0.016), "blued")
    parts.append(box((0.012, 0.018, 0.03), "cfd", (0, front + 0.30, zc + flat + 0.008), "polymer"))
    stock = donor("AssaultRifle2_1", keep=lambda p: p.uc < 0.2,
                  unit=U, default_mat="tan")
    scale(stock, (1.0, 1.08, 1.12))
    back = at(recv, "cbu")
    place(stock, "cfu", (0, back.y + 0.006, v2z(recv, 0.84)))
    bevel(stock, 0.0015)
    riser = box((0.03, 0.10, 0.018), "cbd", (0, at(stock, "cbu").y + 0.03, at(stock, "cbu").z - 0.004), "polymer")
    parts += [stock, riser]
    # A signal-orange bolt catch on the left: the pack's own accent.
    parts.append(box((0.004, 0.016, 0.01), "ccc", (at(recv, "lcc").x, at(recv, "ccc").y, v2z(recv, 0.6)), "signal"))
    mag = donor("AssaultRifle2_2", keep=lambda p: p.mat == "Main" and p.v1 < 0.61 and p.u0 > 0.44,
                unit=U, default_mat="polymer")
    bevel(mag, 0.001)
    plate = box((at(mag, "rcc").x * 2 + 0.004, 0.05, 0.008), "ccu", at(mag, "ccd") + Vector((0, -0.006, 0.002)), "tan")
    mag = join([mag, plate], "rifle_magazine")
    return join(parts, "rifle"), mag, 0.80


# --- Carbine: a short stamped-receiver rifle with a box handguard and a skeleton stock ---------
#
# Receiver, cover, grip, trigger: Quaternius AssaultRifle_3. Magazine: its curved one.
# Stock: Quaternius's Stock accessory (side-folding skeleton).
# Ours: the square handguard and its rail, the short barrel, the big ported brake, the front post,
# the side optic mount.

def carbine():
    m = {"DarkMetal": "blued", "Metal": "steel", "Black": "polymer", "Wood": "olive", "DarkWood": "olive"}
    is_grip = lambda p: p.u1 < 0.15 and p.v0 > 0.25 and p.v1 < 0.7
    recv = donor("AssaultRifle_3", keep=lambda p: p.u1 < 0.53 and not (p.mat == "Black" and p.v0 < 0.05)
                 and not is_grip(p), unit=U, mats=m)
    paint_grip = donor("AssaultRifle_3", keep=is_grip, unit=U, default_mat="rubber")
    bevel(recv, 0.0012)
    lo_top = at(recv, "cfu")
    zc = v2z(recv, 0.80)
    front = u2y(recv, 0.485)
    hg = box((0.036, 0.17, 0.05), "cbc", (0, front, zc - 0.004), "olive", 0.22)
    parts = [recv, hg]
    parts.append(rail(0.15, "cbd", (0, front + 0.01, at(hg, "ccu").z - 0.002), width=0.018))
    parts += _ports(front + 0.03, zc - 0.006, 0.0185, 4, 0.035, (0.003, 0.02, 0.012))
    parts.append(cyl(0.0085, 0.075, "cbc", (0, front + 0.165, zc), material="steel"))
    brake = box((0.036, 0.065, 0.03), "cbc", (0, front + 0.235, zc), "blued", 0.2)
    parts.append(brake)
    parts += _ports(front + 0.25, zc, 0.0185, 3, 0.017, (0.003, 0.009, 0.02), "polymer")
    parts.append(box((0.006, 0.01, 0.03), "cfd", (0, front + 0.165, at(hg, "ccu").z), "blued"))
    parts.append(box((0.006, 0.07, 0.022), "ccc", (-0.019, at(recv, "ccc").y + 0.01, zc - 0.002), "blued"))
    stock = donor("Stock", unit=U * 1.05, default_mat="steel")
    back = at(recv, "cbu")
    place(stock, "cfu", (0, back.y + 0.004, back.z - 0.006))
    bevel(stock, 0.001)
    pad = box((0.03, 0.016, at(stock, "ccu").z - at(stock, "ccd").z), "cfc", at(stock, "cbc"), "rubber")
    parts += [stock, pad, paint_grip]
    mag = donor("AssaultRifle_3", keep=lambda p: p.mat == "Black" and p.v0 < 0.05, unit=U, default_mat="laminate")
    bevel(mag, 0.001)
    return join(parts, "carbine"), mag, 0.66


# --- SMG: a boxy receiver with a full-length integral suppressor ----------------------------
#
# Receiver and grip: Quaternius SubmachineGun_1, its barrel and handguard taken off.
# Stock: SubmachineGun_5's folding stock. Foregrip: Quaternius's Grip accessory.
# Suppressor: Kenney Blaster Kit silencer-larger, stretched; the bands and front post ours.

def smg():
    m = {"Metal": "graphite", "DarkMetal": "slate", "Black": "polymer", "Grey": "polymer"}
    recv = donor("SubmachineGun_1", keep=lambda p: p.uc < 0.88 and not (p.mat == "Black" and p.u0 > 0.55)
                 and not (p.u0 > 0.42 and p.v0 < 0.02) and not (p.u0 > 0.78 and p.v0 > 0.95), unit=U, mats=m)
    bevel(recv, 0.0012)
    front = at(recv, "cfc").y
    zc = v2z(recv, 0.805)
    sup = kenney("silencer-larger", "polymer")
    lo = at(sup, "ccd")
    hi = at(sup, "ccu")
    k = 0.05 / (hi.z - lo.z)
    scale(sup, (k, 0.25 / (at(sup, "cfc").y - at(sup, "cbc").y), k))
    place(sup, "cbc", (0, front - 0.06, zc))
    parts = [recv, sup]
    for i in range(3):
        parts.append(cyl(0.0262, 0.008, "cbc", (0, front + 0.01 + i * 0.05, zc), material="graphite", sides=12))
    parts.append(box((0.006, 0.01, 0.022), "cfd", (0, front + 0.18, zc + 0.022), "graphite"))
    stock = donor("SubmachineGun_5", keep=lambda p: p.u1 < 0.31 and p.mat == "Metal", unit=U, default_mat="steel")
    back = at(recv, "cbu")
    place(stock, "cfu", (0, back.y + 0.004, back.z - 0.004))
    bevel(stock, 0.001)
    grip = donor("Grip", unit=U * 0.9, default_mat="tan")
    place(grip, "cbu", (0, front - 0.10, v2z(recv, 0.75)))
    bevel(grip, 0.001)
    parts += [stock, grip]
    mag = donor("SubmachineGun_1", keep=lambda p: p.u0 > 0.42 and p.v0 < 0.02, unit=U, default_mat="polymer")
    scale(mag, (1.0, 1.0, 1.18), about=at(mag, "ccu"))
    bevel(mag, 0.001)
    return join(parts, "smg"), mag, 0.60


# --- Machine pistol: a long-slide pistol with a compensator, foregrip and extended magazine ------
#
# Frame, slide, rail: Quaternius Pistol_6, its barrel tip taken off.
# Foregrip: Quaternius's Grip accessory, small. Ours: the ported compensator, the magazine.

def machine_pistol():
    m = {"Metal": "tan", "LightMetal": "graphite", "Black": "polymer"}
    gun = donor("Pistol_6", keep=lambda p: not (p.u0 > 0.84 and 0.75 < p.v0 < 0.8), unit=U, mats=m)
    bevel(gun, 0.001)
    slide_front = u2y(gun, 0.98)
    zc = v2z(gun, 0.84)
    comp = box((0.028, 0.05, 0.036), "cbc", (0, slide_front - 0.002, zc), "polymer", 0.2)
    parts = [gun, comp]
    for i in range(2):
        parts.append(box((0.016, 0.008, 0.004), "ccd", (0, slide_front + 0.016 + i * 0.016, at(comp, "ccu").z - 0.001), "signal"))
    grip = donor("Grip", unit=U * 0.62, default_mat="polymer")
    place(grip, "cbu", (0, u2y(gun, 0.78), v2z(gun, 0.56)))
    parts.append(grip)
    base = lowest(gun)
    mag = box((0.02, 0.034, 0.12), "ccu", (0, base.y + 0.004, base.z + 0.02), "polymer", 0.18)
    shear(mag, 1, 2, 0.32)
    plate = box((0.024, 0.042, 0.01), "ccu", (0, at(mag, "cbd").y + 0.017, at(mag, "ccd").z + 0.002), "signal")
    mag = join([mag, plate], "machine_pistol_magazine")
    return join(parts, "machine_pistol"), mag, 0.40


def _discard(ob):
    bpy.data.objects.remove(ob)


# --- Revolver: a full-lug, vent-rib revolver in stainless with a rubber grip -------------------
#
# Frame, cylinder, hammer, trigger, guard and grip: Quaternius Revolver_3, its barrel and sight
# taken off, the grip stretched and in rubber. Ours: the full-length under-lug, the longer
# barrel, the vent rib with its cuts, the orange-insert front ramp.

def revolver():
    # Revolver_3 was saved at 5.6 times the pack's scale (Revolver_2, its twin, is not).
    ru = U * 1.982 / 11.142
    m = {"Metal": "stainless", "LightMetal": "blued", "Grey": "rubber", "DarkWood": "rubber"}
    grip = donor("Revolver_3", keep=lambda p: p.u1 < 0.26 and p.v1 < 0.66, unit=ru, mats=m)
    frame_only = donor("Revolver_3", keep=lambda p: p.u0 < 0.5 and not (p.v0 > 0.89 and p.u0 > 0.38)
                       and not (p.u1 < 0.26 and p.v1 < 0.66), unit=ru, mats=m)
    bevel(frame_only, 0.0008)
    # A longer grip: a bigger hand, and a different line from the donor's.
    scale(grip, (1.08, 1.0, 1.14), about=at(grip, "ccu"))
    bevel(grip, 0.0008)
    front = u2y(frame_only, 0.515)
    zc = v2z(frame_only, 0.77)
    L = 0.21
    parts = [frame_only, grip]
    parts.append(cyl(0.0125, L, "cbc", (0, front - 0.004, zc), material="stainless", sides=12, chamfer=0.1))
    parts.append(box((0.021, L, 0.024), "cbu", (0, front - 0.004, zc + 0.002), "stainless", 0.2))
    rib = box((0.011, L - 0.01, 0.012), "cbd", (0, front - 0.004, zc + 0.006), "blued", 0.15)
    parts.append(rib)
    top = at(rib, "ccu").z
    for i in range(8):
        parts.append(box((0.012, 0.007, 0.004), "ccc", (0, front + 0.02 + i * 0.022, top - 0.0015), "polymer", 0.1))
    ramp = box((0.005, 0.022, 0.012), "cfd", (0, front + L - 0.012, top - 0.001), "stainless", 0.1)
    shear(ramp, 2, 1, 0.35)
    parts.append(ramp)
    parts.append(box((0.0055, 0.004, 0.004), "cfu", (0, front + L - 0.014, at(ramp, "ccu").z - 0.001), "signal", 0.0))
    # Flutes on the cylinder: dark strips round its middle.
    cy = donor("Revolver_3", keep=lambda p: p.mat == "LightMetal" and p.u0 > 0.28, unit=ru)
    c = at(cy, "ccc")
    half = (at(cy, "ccu").z - at(cy, "ccd").z) / 2
    _discard(cy)
    for sx in (-1, 1):
        for dz in (-0.45, 0.0, 0.45):
            parts.append(box((0.003, 0.034, 0.008), "ccc", (sx * (half * 0.93), c.y, c.z + dz * half), "polymer", 0.1))
    return join(parts, "revolver"), None, 0.40


# --- Battle rifle: a long, heavy rifle in walnut and steel with a straight magazine and a bipod ---
#
# Receiver, trigger and guard: Quaternius Shotgun_3. Stock: Shotgun_3's straight-wristed one,
# in walnut. Top cover: Quaternius AssaultRifle_2's. Bipod: Quaternius's, folded back.
# Ours: the magazine well and straight box magazine, the walnut handguard with its steel vented
# cover, the long barrel, the pronged flash hider, both sights.

def battle_rifle():
    m = {"Metal": "steel", "DarkMetal": "gunmetal", "Black": "blued", "Wood": "walnut", "DarkWood": "walnut"}
    recv = donor("Shotgun_3", keep=lambda p: 0.28 < p.uc < 0.47 and p.mat != "DarkMetal", unit=U, mats=m)
    bevel(recv, 0.0012)
    stock = donor("Shotgun_3", keep=lambda p: p.u1 < 0.32 and p.mat == "Wood", unit=U, mats=m)
    scale(stock, (1.1, 1.0, 1.08), about=at(stock, "cfu"))
    bevel(stock, 0.0015)
    front = at(recv, "cfc").y
    top = at(recv, "ccu").z
    zc = top - 0.024
    parts = [recv, stock]
    cover = donor("AssaultRifle_2", keep=lambda p: p.mat == "Metal" and p.u1 < 0.55, unit=U, default_mat="gunmetal")
    s = (at(recv, "cfc").y - at(recv, "cbc").y) / (at(cover, "cfc").y - at(cover, "cbc").y)
    scale(cover, (1.0, s * 0.96, 0.8))
    place(cover, "cfd", (0, front - 0.004, top - 0.004))
    bevel(cover, 0.001)
    parts.append(cover)
    # Magazine well under the front of the receiver.
    bottom = v2z(recv, 0.47)
    well = box((0.03, 0.06, 0.03), "cfu", (0, front - 0.006, bottom + 0.004), "steel", 0.15)
    parts.append(well)
    hg = box((0.04, 0.27, 0.046), "cbc", (0, front - 0.004, zc - 0.006), "walnut", 0.25)
    taper(hg, 2, 0.12, 1, keep="u")
    parts.append(hg)
    vent = box((0.03, 0.25, 0.012), "cbd", (0, front + 0.006, at(hg, "ccu").z - 0.004), "steel", 0.2)
    parts.append(vent)
    for i in range(7):
        parts.append(box((0.022, 0.012, 0.004), "ccc", (0, front + 0.03 + i * 0.033, at(vent, "ccu").z), "polymer", 0.1))
    bf = at(hg, "cfc").y
    parts.append(cyl(0.009, 0.16, "cbc", (0, bf - 0.004, zc), material="blued"))
    # A pronged hider: four bars round the muzzle.
    for dx, dz in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
        parts.append(box((0.005, 0.045, 0.005), "cbc", (dx * 0.008, bf + 0.15, zc + dz * 0.008), "blued", 0.1))
    parts.append(cyl(0.012, 0.012, "cbc", (0, bf + 0.145, zc), material="blued", sides=8))
    # Front sight: a post between two ears on a band.
    band = box((0.022, 0.016, 0.03), "cbd", (0, bf + 0.06, zc - 0.012), "blued", 0.15)
    parts.append(band)
    for sx in (-1, 1):
        parts.append(box((0.004, 0.012, 0.022), "cbd", (sx * 0.009, bf + 0.062, at(band, "ccu").z - 0.002), "blued", 0.1))
    parts.append(box((0.003, 0.008, 0.016), "cbd", (0, bf + 0.064, at(band, "ccu").z - 0.002), "blued", 0.0))
    # Rear aperture on the back of the cover.
    rear = box((0.016, 0.014, 0.016), "cbd", (0, at(cover, "cbc").y + 0.004, at(cover, "ccu").z - 0.002), "blued", 0.15)
    parts.append(rear)
    bip = donor("Bipod", unit=U * 0.75, default_mat="blued")
    rotate(bip, -90, "X")
    scale(bip, (0.28, 1.0, 1.0))
    place(bip, "cfu", (0, bf - 0.03, at(hg, "ccd").z + 0.006))
    parts.append(bip)
    # Our magazine: straight, ribbed, in steel with a walnut-dark baseplate.
    mag = box((0.026, 0.05, 0.10), "ccu", (0, at(well, "ccc").y, at(well, "ccd").z + 0.008), "steel", 0.12)
    shear(mag, 1, 2, -0.12)
    mc = at(mag, "ccc")
    ribs = [box((0.002, 0.034, 0.05), "ccc", (sx * 0.0135, mc.y, mc.z), "gunmetal", 0.0) for sx in (-1, 1)]
    plate = box((0.03, 0.056, 0.008), "ccu", at(mag, "ccd") + Vector((0, -0.006, 0.002)), "polymer", 0.2)
    mag = join([mag, plate] + ribs, "battle_rifle_magazine")
    return join(parts, "battle_rifle"), mag, 0.86


# --- Burst rifle: a long-railed modern rifle with a wedge handguard -------------------------
#
# Receiver, grip and trigger: Quaternius SubmachineGun_3, its wire stock, foregrip, magazine and
# muzzle taken off, pulled at a larger unit so it is a rifle. Stock: AssaultRifle2_1's.
# Magazine: AssaultRifle2_1's, seated where SubmachineGun_3's was. Ours: the tapered handguard,
# barrel, three-port brake, front sight.

def burst_rifle():
    k = U * 1.15
    m = {"Metal": "gunmetal", "DarkMetal": "graphite", "Black": "polymer", "Grey": "signal"}
    recv = donor("SubmachineGun_3", keep=lambda p: p.u0 > 0.37 and p.u1 < 0.95 and not (0.61 < p.u0 < 0.63 and p.v0 < 0.01)
                 and not (0.8 < p.u0 < 0.82) and not (p.u0 > 0.72 and p.mat == "Black"), unit=k, mats=m)
    bevel(recv, 0.0012)
    old = donor("SubmachineGun_3", keep=lambda p: 0.61 < p.u0 < 0.63 and p.v0 < 0.01, unit=k)
    seat = at(old, "ccu")
    _discard(old)
    front = at(recv, "cfc").y
    zc = v2z(recv, 0.80)
    parts = [recv]
    hg = box((0.04, 0.17, 0.05), "cbc", (0, front - 0.004, zc + 0.004), "ranger", 0.25)
    taper(hg, 2, 0.35, 1, keep="u")
    parts.append(hg)
    parts += _ports(front + 0.03, zc + 0.012, 0.0195, 3, 0.045, (0.003, 0.03, 0.008), "graphite")
    parts.append(cyl(0.0085, 0.08, "cbc", (0, at(hg, "cfc").y - 0.004, zc), material="steel"))
    brake = cyl(0.0125, 0.045, "cbc", (0, at(hg, "cfc").y + 0.07, zc), material="graphite", sides=8)
    parts.append(brake)
    parts += _ports(at(hg, "cfc").y + 0.077, zc, 0.012, 3, 0.012, (0.003, 0.007, 0.014), "polymer")
    rtop = at(recv, "ccu").z
    hg_top = at(hg, "ccu").z
    parts.append(box((0.006, 0.012, rtop - hg_top + 0.02), "cfd", (0, at(hg, "cfc").y - 0.004, hg_top - 0.002), "graphite"))
    stock = donor("AssaultRifle2_1", keep=lambda p: p.u1 < 0.27, unit=k * 0.95, default_mat="ranger")
    back = at(recv, "cbu")
    place(stock, "cfu", (0, back.y + 0.045, rtop - 0.004))
    bevel(stock, 0.0015)
    parts.append(stock)
    parts.append(box((0.034, 0.014, at(stock, "ccu").z - at(stock, "ccd").z - 0.01), "cfc",
                     at(stock, "cbc") + Vector((0, 0.004, 0)), "polymer", 0.2))
    mag = donor("AssaultRifle2_1", keep=lambda p: p.mat == "Main" and p.v0 < 0.01, unit=k, default_mat="sand")
    place(mag, "ccu", seat + Vector((0, 0, 0.006)))
    bevel(mag, 0.001)
    return join(parts, "burst_rifle"), mag, 0.80


# --- Shotgun: a pump gun with a pistol-grip stock, a vented heat shield and a full-length tube ---
#
# Receiver, trigger, guard: Quaternius Shotgun_3. Stock: Quaternius Shotgun_ShortStock's pistol
# grip stock, smaller and in polymer. Ours: the barrel, the vented heat shield, the magazine tube run out to the
# muzzle with its clamp, the ribbed pump, the bead and the side saddle.

def shotgun():
    m = {"Metal": "gunmetal", "DarkMetal": "blued", "Black": "polymer", "Wood": "ash", "DarkWood": "ash"}
    recv = donor("Shotgun_3", keep=lambda p: 0.28 < p.uc < 0.47 and p.mat != "DarkMetal" and p.mat != "Wood", unit=U, mats=m)
    bevel(recv, 0.0012)
    stock = donor("Shotgun_ShortStock", keep=lambda p: p.u1 < 0.23 and p.mat == "Wood", unit=U * 0.86,
                  default_mat="polymer")
    place(stock, "cfu", (0, at(recv, "cbc").y + 0.006, at(recv, "ccu").z - 0.012))
    bevel(stock, 0.0015)
    front = at(recv, "cfc").y
    top = at(recv, "ccu").z
    zb = v2z(recv, 0.82)
    zt = v2z(recv, 0.61)
    L = 0.47
    parts = [recv, stock]
    parts.append(cyl(0.011, L, "cbc", (0, front - 0.004, zb), material="blued", sides=12))
    shield = box((0.03, 0.26, 0.016), "cbd", (0, front + 0.01, zb + 0.002), "polymer", 0.2)
    parts.append(shield)
    for sx in (-1, 1):
        for i in range(6):
            parts.append(box((0.002, 0.024, 0.006), "ccc", (sx * 0.015, front + 0.04 + i * 0.038, zb + 0.008), "steel", 0.0))
    parts.append(cyl(0.010, L - 0.01, "cbc", (0, front - 0.004, zt), material="blued", sides=10))
    parts.append(box((0.026, 0.02, 0.05), "cfc", (0, front + L - 0.016, (zb + zt) / 2), "polymer", 0.25))
    pump = cyl(0.018, 0.14, "cbc", (0, front + 0.05, zt - 0.002), material="ash", sides=10, chamfer=0.15)
    parts.append(pump)
    for i in range(5):
        parts.append(cyl(0.0185, 0.008, "cbc", (0, front + 0.065 + i * 0.024, zt - 0.002), material="walnut", sides=10))
    parts.append(cyl(0.003, 0.004, "ccd", (0, front + L - 0.01, zb + 0.01), axis="Z", material="signal", sides=8))
    # A side saddle of four shells on the left of the receiver.
    rc = at(recv, "ccc")
    xl = at(recv, "lcc").x
    parts.append(box((0.006, 0.07, 0.03), "rcc", (xl + 0.001, rc.y, rc.z + 0.004), "polymer", 0.15))
    for i in range(4):
        parts.append(cyl(0.0055, 0.03, "ccc", (xl - 0.006, rc.y - 0.026 + i * 0.0175, rc.z + 0.004), axis="Z", material="red", sides=8))
    return join(parts, "shotgun"), None, 0.88


# --- Bullpup: a long-bodied bullpup with a raised top rail ----------------------------------
#
# Body, grip, trigger, butt and magazine: Quaternius Bullpup_1, its rail teeth, foregrip and
# muzzle taken off. Ours: the rail raised on two posts, the barrel and three-prong hider, the
# hand stop, the ejection deflector, the magazine's baseplate.

def bullpup():
    m = {"Main": "graphite", "MainDark": "polymer", "MainLight": "olive"}
    is_mag = lambda p: 0.24 < p.u0 < 0.26 and p.v1 < 0.5
    body = donor("Bullpup_1", keep=lambda p: not (p.v0 > 0.96 and p.u1 < 0.91) and not (0.83 < p.u0 < 0.85 and p.v0 < 0.31)
                 and not (p.u0 > 0.9 and 0.75 < p.v0 < 0.77) and not is_mag(p), unit=U, mats=m)
    bevel(body, 0.0012)
    front = u2y(body, 0.905)
    zc = v2z(body, 0.80)
    top = v2z(body, 0.97)
    parts = [body]
    r = rail(0.30, "cbd", (0, u2y(body, 0.40), top + 0.026), width=0.02, material="polymer")
    parts.append(r)
    for u in (0.44, 0.66):
        parts.append(box((0.016, 0.03, 0.03), "cbd", (0, u2y(body, u), top - 0.004), "graphite", 0.2))
    parts.append(cyl(0.0085, 0.09, "cbc", (0, front - 0.004, zc), material="steel"))
    for a in (0, 120, 240):
        prong = box((0.004, 0.04, 0.004), "cbc", (0, front + 0.085, zc + 0.009), "blued", 0.1)
        rotate(prong, a, "Y", about=Vector((0, front, zc)))
        parts.append(prong)
    parts.append(box((0.022, 0.012, 0.03), "cfu", (0, u2y(body, 0.86), v2z(body, 0.72)), "polymer", 0.2))
    parts.append(box((0.006, 0.05, 0.03), "lcc", (at(body, "rcc").x - 0.002, u2y(body, 0.20), v2z(body, 0.80)), "signal", 0.2))
    mag = donor("Bullpup_1", keep=is_mag, unit=U, default_mat="polymer")
    bevel(mag, 0.001)
    plate = box((at(mag, "rcc").x * 2 + 0.004, at(mag, "cfc").y - at(mag, "cbc").y + 0.008, 0.008), "ccu",
                at(mag, "ccd") + Vector((0, 0, 0.002)), "sand", 0.2)
    mag = join([mag, plate], "bullpup_magazine")
    return join(parts, "bullpup"), mag, 0.72


# --- Marksman: a chassis rifle with a slim suppressor and a short scope ------------------------
#
# Chassis, skeleton stock, grip and trigger: Quaternius SniperRifle_5, its barrel, scope and
# bipod taken off. Suppressor: Quaternius's Silencer_2. Scope: Quaternius's Scope_1, shortened.
# Ours: the barrel, the scope rings, the flush ten-round magazine, the cheek pad, the side slots.

def marksman():
    m = {"LightMetal": "olive", "Metal": "gunmetal", "DarkMetal": "blued", "Black": "polymer", "Grey": "signal", "Glass": "lens"}
    body = donor("SniperRifle_5", keep=lambda p: not (p.u0 > 0.24 and p.u0 < 0.26 and p.mat == "DarkMetal" and p.u1 > 0.9)
                 and not (p.mat == "Black" and p.v0 > 0.79) and not (0.61 < p.u0 < 0.64), unit=U, mats=m)
    bevel(body, 0.0012)
    front = u2y(body, 0.64)
    zc = v2z(body, 0.775)
    parts = [body]
    parts.append(cyl(0.008, 0.12, "cbc", (0, front - 0.004, zc), material="blued"))
    sup = donor("Silencer_2", unit=U * 0.9, default_mat="graphite")
    place(sup, "cbc", (0, front + 0.11, zc))
    parts.append(sup)
    parts += _ports(u2y(body, 0.45), zc - 0.004, 0.0115, 4, 0.04, (0.003, 0.028, 0.008), "blued")
    sc = donor("Scope_1", unit=U * 0.8, default_mat="polymer")
    scale(sc, (1.0, 0.8, 1.0))
    rtop = v2z(body, 0.82)
    place(sc, "ccd", (0, u2y(body, 0.36), rtop + 0.014))
    parts.append(sc)
    # Rings up to the tube's middle: the bells' bounds are lower than the tube between them.
    tube = at(sc, "ccc").z
    for u in (0.31, 0.41):
        parts.append(box((0.016, 0.012, tube - rtop + 0.004), "ccd", (0, u2y(body, u), rtop - 0.004), "blued", 0.2))
    parts.append(box((0.03, 0.006, 0.006), "ccc", (0, at(sc, "cfc").y - 0.004, at(sc, "ccc").z), "lens", 0.0))
    mag = box((0.022, 0.05, 0.05), "ccu", (0, u2y(body, 0.42), v2z(body, 0.62)), "polymer", 0.15)
    parts.append(mag)
    parts.append(box((0.026, 0.056, 0.007), "ccu", at(mag, "ccd") + Vector((0, 0, 0.002)), "signal", 0.2))
    parts.append(box((0.03, 0.09, 0.02), "cbd", (0, u2y(body, 0.06), v2z(body, 0.72)), "rubber", 0.25))
    return join(parts, "marksman"), None, 1.0


# --- Sniper: a heavy bolt gun with a fluted barrel, a big brake, a long scope and a bipod -------
#
# Stock, trigger and bolt: Quaternius SniperRifle_1, its barrel and scope taken off. Scope:
# Quaternius's Scope_2, with a sunshade of ours. Bipod: Quaternius's, folded. Ours: the round
# receiver and its rail, the fluted barrel, the two-chamber brake, the rings, the cheek riser,
# the recoil pad, the orange bolt knob.

def sniper():
    m = {"Green": "sand", "Black": "polymer", "DarkMetal": "blued", "Grey": "steel", "Glass": "lens", "Metal": "steel", "LightMetal": "steel"}
    stock = donor("SniperRifle_1", keep=lambda p: not (p.mat == "DarkMetal" and p.u1 > 0.9)
                  and not (p.mat == "Black" and p.v0 > 0.72), unit=U, mats=m)
    bevel(stock, 0.0015)
    zc = v2z(stock, 0.715)
    rb = u2y(stock, 0.29)
    parts = [stock]
    recv = cyl(0.021, 0.26, "cbc", (0, rb, zc), material="blued", sides=12, chamfer=0.1)
    parts.append(recv)
    parts.append(rail(0.22, "cbd", (0, rb + 0.02, zc + 0.019), width=0.022))
    bf = rb + 0.26
    L = 0.44
    parts.append(cyl(0.0125, L, "cbc", (0, bf - 0.004, zc), material="gunmetal", sides=12, radius2=0.01))
    for a in range(0, 360, 60):
        f = box((0.003, L - 0.06, 0.006), "cbc", (0, bf + 0.02, zc + 0.0118), "blued", 0.0)
        rotate(f, a, "Y", about=Vector((0, bf, zc)))
        parts.append(f)
    brake = box((0.034, 0.08, 0.03), "cbc", (0, bf + L - 0.01, zc), "blued", 0.2)
    parts.append(brake)
    for i in range(2):
        parts.append(box((0.036, 0.014, 0.018), "ccc", (0, bf + L + 0.014 + i * 0.03, zc), "polymer", 0.1))
    sc = donor("Scope_2", unit=U * 1.05, default_mat="polymer")
    place(sc, "ccd", (0, rb + 0.13, zc + 0.05))
    parts.append(sc)
    lens_r = (at(sc, "ccu").z - at(sc, "ccd").z) * 0.42
    parts.append(cyl(lens_r * 1.05, 0.05, "cbc", (0, at(sc, "cfc").y - 0.004, at(sc, "cfc").z + 0.003), material="graphite", sides=12))
    tube = at(sc, "ccc").z
    for dy in (0.07, 0.19):
        parts.append(box((0.022, 0.014, tube - zc - 0.015), "cbd", (0, rb + dy, zc + 0.015), "blued", 0.2))
    ry = u2y(stock, 0.10)
    parts.append(box((0.03, 0.10, 0.022), "ccd", (0, ry, top_at(stock, ry, 0.07) - 0.004), "graphite", 0.25))
    parts.append(box((0.05, 0.016, (v2z(stock, 0.66) - v2z(stock, 0.02))), "cfd", (0, at(stock, "cbc").y + 0.006, v2z(stock, 0.02)), "rubber", 0.2))
    parts.append(cyl(0.009, 0.02, "lcc", (at(recv, "rcc").x + 0.03, rb + 0.21, zc - 0.006), axis="X", material="signal", sides=8))
    parts.append(cyl(0.0035, 0.032, "lcc", (at(recv, "rcc").x - 0.002, rb + 0.21, zc - 0.002), axis="X", material="blued", sides=6))
    bip = donor("Bipod", unit=U * 0.9, default_mat="blued")
    rotate(bip, -90, "X")
    scale(bip, (0.3, 1.0, 1.0))
    place(bip, "cfu", (0, u2y(stock, 0.68), v2z(stock, 0.55)))
    parts.append(bip)
    return join(parts, "sniper"), None, 1.30


# --- Launcher: a shoulder-fired recoilless tube ------------------------------------------------
#
# Front grip and pistol grip: Quaternius's Grip accessory, twice. Sight: Kenney Blaster Kit
# scope-small. Ours: the tube, the flared venturi, the muzzle bell, the bands, the shoulder rest,
# the trigger housing, the folding iron sights.

def launcher():
    R = 0.042
    L = 0.82
    zc = 0.0
    parts = [cyl(R, L, "cbc", (0, 0, zc), material="olive", sides=14, chamfer=0.05)]
    parts.append(cyl(R * 1.4, 0.12, "cfc", (0, 0.004, zc), material="blued", sides=14, radius2=R * 0.9))
    parts.append(cyl(R * 1.18, 0.05, "cbc", (0, L - 0.03, zc), material="olive", sides=14, chamfer=0.1))
    parts.append(cyl(R * 0.9, 0.006, "cfc", (0, L + 0.021, zc), material="polymer", sides=14))
    for y in (0.16, 0.42, 0.64):
        parts.append(cyl(R * 1.06, 0.03, "cbc", (0, y, zc), material="sand", sides=14))
    parts.append(box((0.03, 0.16, 0.03), "ccu", (0, 0.14, zc - R + 0.006), "polymer", 0.25))
    hs = box((0.022, 0.06, 0.03), "ccu", (0, 0.36, zc - R + 0.004), "graphite", 0.2)
    parts.append(hs)
    pg = donor("Grip", unit=U * 0.85, default_mat="polymer")
    rotate(pg, -14, "X")
    place(pg, "ccu", (0, 0.36, at(hs, "ccd").z + 0.004))
    parts.append(pg)
    parts.append(box((0.004, 0.012, 0.016), "ccu", (0, 0.39, at(hs, "ccd").z + 0.002), "signal", 0.0))
    fg = donor("Grip", unit=U * 0.85, default_mat="rubber")
    place(fg, "ccu", (0, 0.56, zc - R + 0.006))
    parts.append(fg)
    sight = kenney("scope-small", "graphite")
    k = 0.15 / (at(sight, "cfc").y - at(sight, "cbc").y)
    scale(sight, k)
    place(sight, "rcc", (-R + 0.004, 0.40, zc + R * 0.55))
    parts.append(sight)
    parts.append(box((0.016, 0.012, 0.03), "ccd", (0, 0.30, zc + R - 0.004), "blued", 0.2))
    parts.append(box((0.016, 0.012, 0.034), "ccd", (0, 0.72, zc + R - 0.004), "blued", 0.2))
    return join(parts, "launcher"), None, 0.95


import toy_guns  # noqa: E402

RECIPES = {
    "pistol": toy_guns.pistol,
    "derringer": toy_guns.derringer,
    "drum_shotgun": toy_guns.drum_shotgun,
    "minigun": toy_guns.minigun,
    "rifle": rifle,
    "carbine": carbine,
    "smg": smg,
    "machine_pistol": machine_pistol,
    "revolver": revolver,
    "battle_rifle": battle_rifle,
    "burst_rifle": burst_rifle,
    "shotgun": shotgun,
    "bullpup": bullpup,
    "marksman": marksman,
    "sniper": sniper,
    "launcher": launcher,
}
