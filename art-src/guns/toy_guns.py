# The pack's own primitive guns, in its orange-and-graphite toy look, for the types the donor
# kit has no part for: a pistol, a derringer, a drum shotgun and a multi-barrel minigun.
# Each is a type's proportions first (what a thumbnail shows): the pistol a slide over a short
# angled grip, the derringer a stubby stacked pair of barrels, the drum shotgun a long barrel
# and fore-end under a big drum, the minigun a bundle of barrels with rings and a carry handle.
from zee_kit import at, box, cyl, join, rotate, shear


def pistol():
    parts = [
        box((0.046, 0.44, 0.052), "cbd", (0, 0.0, 0.062), "signal", 0.15),
        box((0.036, 0.30, 0.034), "cbd", (0, 0.02, 0.03), "graphite", 0.15),
        cyl(0.011, 0.04, "cbc", (0, 0.43, 0.088), material="steel", sides=10),
        box((0.008, 0.012, 0.014), "ccd", (0, 0.425, 0.114), "polymer", 0.1),
        box((0.016, 0.012, 0.014), "ccd", (0, 0.025, 0.114), "polymer", 0.1),
        box((0.012, 0.075, 0.006), "ccd", (0, 0.285, 0.0), "graphite", 0.1),
        box((0.012, 0.006, 0.036), "ccd", (0, 0.322, 0.0), "graphite", 0.1),
        box((0.008, 0.012, 0.026), "ccd", (0, 0.255, 0.012), "steel", 0.1),
    ]
    grip = box((0.042, 0.075, 0.17), "cbu", (0, 0.005, 0.065), "graphite", 0.15)
    shear(grip, 1, 2, 0.3)
    parts.append(grip)
    mag = box((0.03, 0.05, 0.13), "ccu", (0, 0.06, 0.03), "polymer", 0.15)
    shear(mag, 1, 2, 0.3)
    plate = box((0.036, 0.06, 0.012), "ccu", (0, at(mag, "ccd").y - 0.012, at(mag, "ccd").z + 0.002), "signal", 0.15)
    mag = join([mag, plate], "pistol_magazine")
    return join(parts, "pistol"), mag, 0.46


def derringer():
    r = 0.016
    parts = [
        box((0.036, 0.20, 2 * r + 0.012), "cbd", (0, 0.0, 0.07), "signal", 0.15),
        cyl(r, 0.12, "cbc", (0, 0.2, 0.07 + r + 0.006), material="steel", sides=10),
        cyl(r, 0.12, "cbc", (0, 0.2, 0.07 + 3 * r + 0.006), material="steel", sides=10),
        box((0.038, 0.05, 0.03), "cbd", (0, 0.17, 0.07 + 2 * r + 0.012), "graphite", 0.15),
        box((0.012, 0.03, 0.03), "cbd", (0, 0.0, 0.07 + 2 * r + 0.012), "steel", 0.1),
        box((0.008, 0.04, 0.012), "ccd", (0, 0.1, 0.0), "graphite", 0.1),
    ]
    grip = box((0.034, 0.06, 0.1), "cbu", (0, -0.015, 0.082), "walnut", 0.2)
    shear(grip, 1, 2, 0.55)
    parts.append(grip)
    return join(parts, "derringer"), None, 0.26


def drum_shotgun():
    zb = 0.12
    parts = [
        box((0.05, 0.26, 0.085), "cbc", (0, 0.0, zb), "signal", 0.15),
        cyl(0.0125, 0.5, "cbc", (0, 0.26, zb + 0.022), material="steel", sides=12),
        cyl(0.011, 0.46, "cbc", (0, 0.26, zb - 0.014), material="graphite", sides=10),
        box((0.036, 0.20, 0.044), "cbc", (0, 0.31, zb - 0.014), "walnut", 0.2),
        box((0.012, 0.014, 0.022), "ccd", (0, 0.74, zb + 0.034), "polymer", 0.1),
        box((0.012, 0.03, 0.02), "ccd", (0, 0.03, zb + 0.042), "polymer", 0.1),
        box((0.036, 0.04, 0.026), "ccd", (0, 0.04, zb - 0.07), "graphite", 0.1),
    ]
    stock = box((0.04, 0.26, 0.11), "cfc", (0, 0.0, zb - 0.01), "walnut", 0.2)
    shear(stock, 2, 1, 0.12)
    pad = box((0.044, 0.016, 0.12), "cfc", (0, at(stock, "cbc").y, at(stock, "cbc").z), "rubber", 0.2)
    grip = box((0.036, 0.05, 0.1), "cbu", (0, 0.04, zb - 0.04), "graphite", 0.15)
    shear(grip, 1, 2, 0.25)
    # The drum: a drum on its side under the fore-end, with a hub cap and a rim band.
    cy, cz = 0.30, zb - 0.1
    drum = cyl(0.085, 0.07, "ccc", (0, cy, cz), axis="X", material="graphite", sides=16, chamfer=0.1)
    hubs = [cyl(0.03, 0.082, "ccc", (0, cy, cz), axis="X", material="signal", sides=10, chamfer=0.1),
            cyl(0.088, 0.02, "ccc", (0, cy, cz), axis="X", material="steel", sides=16, chamfer=0.1)]
    return join(parts + [stock, pad, grip, drum] + hubs, "drum_shotgun"), None, 0.80


def minigun():
    zc = 0.12
    parts = [
        box((0.11, 0.30, 0.12), "cbc", (0, 0.0, zc), "graphite", 0.15),
        cyl(0.055, 0.16, "cbc", (0, -0.14, zc), material="signal", sides=12),
        cyl(0.045, 0.06, "cbc", (0, 0.3, zc), material="steel", sides=12),
    ]
    for i in range(6):
        import math
        a = 2 * math.pi * i / 6
        parts.append(cyl(0.011, 0.62, "cbc", (math.cos(a) * 0.028, 0.3, zc + math.sin(a) * 0.028), material="steel", sides=8))
    parts.append(cyl(0.02, 0.62, "cbc", (0, 0.3, zc), material="gunmetal", sides=8))
    for y in (0.40, 0.66, 0.88):
        parts.append(cyl(0.044, 0.016, "cbc", (0, y, zc), material="signal", sides=12))
    # carry handle, two spade grips, trigger
    for y in (0.02, 0.26):
        parts.append(box((0.03, 0.03, 0.09), "ccd", (0, y, zc + 0.06), "polymer", 0.15))
    parts.append(box((0.03, 0.30, 0.025), "cbd", (0, 0.0, zc + 0.145), "polymer", 0.15))
    for sx in (-1, 1):
        parts.append(box((0.012, 0.025, 0.1), "ccu", (sx * 0.075, 0.0, zc - 0.03), "polymer", 0.15))
        parts.append(box((0.012, 0.09, 0.022), "ccc", (sx * 0.075, -0.03, zc - 0.13), "polymer", 0.15))
    return join(parts, "minigun"), None, 1.0
