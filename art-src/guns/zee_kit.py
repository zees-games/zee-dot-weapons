# The kitbash toolkit the gun recipes (guns.py) are written in.
#
# Space: Blender's, in metres, the muzzle along +Y, up +Z, the gun's right side +X. glTF's
# exporter turns +Y into -Z, which is the forward ZeeWeaponArtTable expects of every gun
# (docs/view-model.md, "Orientation"), so a recipe never thinks about Godot's axes.
#
# Three kinds of part:
#   donor(...)  loose parts picked out of a Quaternius gun (src/quaternius_donors.blend), by
#               where they sit in the donor's side view: u along its length (0 the butt,
#               1 the muzzle) and v up its height (0 the bottom), both from the donor's bounds.
#   kenney(...) a Kenney Blaster Kit part, from this repo's assets/blaster-kit/.
#   box/cyl/... our own, beveled.
# Every part is given one of our palette's materials: nothing keeps the source's colours.
import bmesh
import bpy
import math
import os
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
DONORS = os.path.join(HERE, "src", "quaternius_donors.blend")
KENNEY = os.path.join(REPO, "assets", "blaster-kit")

# --- Palette ----------------------------------------------------------------
#
# sRGB colour, metallic, roughness. Kept out of the near-black: the 2026-10-16 pass found
# authored near-black albedos turned every gun into one dark stick on screen, and a metallic
# surface with no reflection probe renders darker still, so metals are mostly rough dielectric.
PALETTE = {
    "blued": ((0.20, 0.21, 0.24), 0.25, 0.45),
    "gunmetal": ((0.27, 0.28, 0.30), 0.2, 0.5),
    "steel": ((0.52, 0.53, 0.55), 0.35, 0.38),
    "stainless": ((0.70, 0.71, 0.72), 0.4, 0.3),
    "polymer": ((0.17, 0.17, 0.18), 0.0, 0.75),
    "graphite": ((0.32, 0.33, 0.34), 0.0, 0.7),
    "tan": ((0.62, 0.52, 0.38), 0.0, 0.7),
    "sand": ((0.74, 0.67, 0.54), 0.0, 0.75),
    "olive": ((0.33, 0.37, 0.24), 0.0, 0.7),
    "ranger": ((0.24, 0.30, 0.25), 0.0, 0.7),
    "slate": ((0.36, 0.42, 0.48), 0.05, 0.6),
    "walnut": ((0.42, 0.25, 0.14), 0.0, 0.6),
    "ash": ((0.66, 0.50, 0.32), 0.0, 0.6),
    "laminate": ((0.48, 0.24, 0.16), 0.0, 0.5),
    "rubber": ((0.13, 0.13, 0.13), 0.0, 0.9),
    "brass": ((0.78, 0.62, 0.30), 0.6, 0.35),
    "lens": ((0.10, 0.18, 0.26), 0.1, 0.1),
    "signal": ((0.92, 0.46, 0.12), 0.0, 0.5),
    "teal": ((0.12, 0.55, 0.55), 0.0, 0.5),
    "red": ((0.75, 0.12, 0.10), 0.0, 0.5),
}


def _linear(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def mat(name):
    key = "zee_" + name
    m = bpy.data.materials.get(key)
    if m is not None:
        return m
    rgb, metal, rough = PALETTE[name]
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*_linear(rgb), 1.0)
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rough
    m.diffuse_color = (*_linear(rgb), 1.0)
    return m


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# --- Mesh helpers -------------------------------------------------------------

def _new_object(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def bounds(*obs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for ob in obs:
        for v in ob.data.vertices:
            w = ob.matrix_world @ v.co
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    if lo.x > hi.x:
        raise ValueError("bounds of an empty part: %s" % [o.name for o in obs])
    return lo, hi


def _bake(ob):
    """Applies the object's transform to its mesh."""
    ob.data.transform(ob.matrix_world)
    ob.matrix_world = Matrix.Identity(4)
    return ob


def move(ob, d):
    ob.data.transform(Matrix.Translation(Vector(d)))
    return ob


def scale(ob, s, about=None):
    """Scales a part about a point (default its bounds' centre); s is a number or (x, y, z)."""
    if isinstance(s, (int, float)):
        s = (s, s, s)
    lo, hi = bounds(ob)
    c = Vector(about) if about is not None else (lo + hi) / 2
    m = Matrix.Translation(c) @ Matrix.Diagonal((*s, 1.0)) @ Matrix.Translation(-c)
    ob.data.transform(m)
    if (s[0] * s[1] * s[2]) < 0:
        ob.data.flip_normals()
    return ob


def rotate(ob, deg, axis="X", about=None):
    lo, hi = bounds(ob)
    c = Vector(about) if about is not None else (lo + hi) / 2
    m = Matrix.Translation(c) @ Matrix.Rotation(math.radians(deg), 4, axis) @ Matrix.Translation(-c)
    ob.data.transform(m)
    return ob


def place(ob, anchor, to):
    """Moves a part so the named point of its bounds lands on `to`.

    anchor is three letters, one per axis: x in l/c/r (left -X, centre, right +X), y in b/c/f
    (back, centre, front/muzzle), z in d/c/u (down, centre, up). "cbu" is the top of its back end.
    """
    lo, hi = bounds(ob)
    pick = []
    for i, ch in enumerate(anchor):
        if ch in "lbd":
            pick.append(lo[i])
        elif ch in "rfu":
            pick.append(hi[i])
        else:
            pick.append((lo[i] + hi[i]) / 2)
    return move(ob, Vector(to) - Vector(pick))


def at(ob, anchor):
    lo, hi = bounds(ob)
    out = []
    for i, ch in enumerate(anchor):
        out.append(lo[i] if ch in "lbd" else hi[i] if ch in "rfu" else (lo[i] + hi[i]) / 2)
    return Vector(out)


def paint(ob, name):
    ob.data.materials.clear()
    ob.data.materials.append(mat(name))
    for p in ob.data.polygons:
        p.material_index = 0
    return ob


def repaint(ob, mapping, default=None):
    """Swaps a donor's material slots for palette ones: {donor material name: palette name}."""
    for i, slot in enumerate(ob.data.materials):
        src = slot.name.split(".")[0] if slot else ""
        name = mapping.get(src, default)
        if name is None:
            raise KeyError("no palette entry for donor material %r in %s" % (src, ob.name))
        ob.data.materials[i] = mat(name)
    return ob


def bevel(ob, width, angle=35.0, segments=1):
    """Chamfers every edge sharper than `angle` degrees: the facet that catches a highlight."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    lim = math.radians(angle)
    edges = [e for e in bm.edges if e.is_manifold and len(e.link_faces) == 2 and e.calc_face_angle(0.0) > lim]
    if edges:
        bmesh.ops.bevel(bm, geom=edges, offset=width, segments=segments, profile=0.5,
                        affect="EDGES", clamp_overlap=True)
    bm.to_mesh(ob.data)
    bm.free()
    return ob


def taper(ob, axis, amount, along, keep="d"):
    """Narrows a part along one axis: `axis` (0 x, 1 y, 2 z) shrinks by `amount` (0..1) toward the
    far end of `along`. Turns a box into a wedge, a grip into a raked grip."""
    lo, hi = bounds(ob)
    for v in ob.data.vertices:
        t = (v.co[along] - lo[along]) / max(hi[along] - lo[along], 1e-6)
        k = 1.0 - amount * t
        if keep == "c":
            mid = (lo[axis] + hi[axis]) / 2
        elif keep == "d":
            mid = lo[axis]
        else:
            mid = hi[axis]
        v.co[axis] = mid + (v.co[axis] - mid) * k
    return ob


def shear(ob, axis, along, amount):
    """Slides `axis` by amount × (position along `along` from its low end): a rake."""
    lo, hi = bounds(ob)
    for v in ob.data.vertices:
        v.co[axis] += amount * (v.co[along] - lo[along])
    return ob


# --- Our own parts ------------------------------------------------------------

def box(size, anchor="ccc", to=(0, 0, 0), material="gunmetal", chamfer=0.15, name="box"):
    """A box `size` (x wide, y long, z tall) with its edges chamfered by `chamfer` × its smallest side."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    if chamfer > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(size) * chamfer, segments=1,
                        profile=0.5, affect="EDGES", clamp_overlap=True)
    ob = _new_object(name, bm)
    paint(ob, material)
    return place(ob, anchor, to)


def cyl(radius, length, anchor="ccc", to=(0, 0, 0), axis="Y", material="steel", sides=10,
        chamfer=0.12, radius2=None, name="cyl"):
    """A cylinder (or a cone, with radius2 at the far end) along an axis; chamfered rims."""
    bm = bmesh.new()
    r2 = radius if radius2 is None else radius2
    bmesh.ops.create_cone(bm, cap_ends=True, segments=sides, radius1=radius, radius2=r2, depth=length)
    if chamfer > 0:
        rims = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > math.radians(50)]
        bmesh.ops.bevel(bm, geom=rims, offset=min(radius, r2, length) * chamfer, segments=1,
                        profile=0.5, affect="EDGES", clamp_overlap=True)
    if axis == "Y":
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(-90), 3, "X"), verts=bm.verts)
    elif axis == "X":
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "Y"), verts=bm.verts)
    ob = _new_object(name, bm)
    paint(ob, material)
    return place(ob, anchor, to)


def rail(length, anchor="cbd", to=(0, 0, 0), width=0.022, material="polymer", pitch=0.01, name="rail"):
    """A toothed accessory rail: a base and a row of cross-slots."""
    parts = [box((width * 0.75, length, width * 0.28), "cbd", (0, 0, 0), material, 0.2)]
    n = max(2, int(length / pitch / 2))
    step = length / n
    for i in range(n):
        parts.append(box((width, step * 0.55, width * 0.3), "cbd", (0, step * (i + 0.5) - step * 0.275, width * 0.25), material, 0.15))
    ob = join(parts, name)
    return place(ob, anchor, to)


def ring_of(count, radius, size, centre, axis_len, material, anchor_y, length):
    """Small boxes in a ring round a barrel: the ports of a brake or a shroud."""
    out = []
    for i in range(count):
        a = 2 * math.pi * i / count
        p = Vector((centre[0] + math.cos(a) * radius, anchor_y, centre[2] + math.sin(a) * radius))
        b = box(size, "cbc", p, material, 0.1)
        rotate(b, math.degrees(a) - 90, "Y", about=p)
        out.append(b)
    return out


def join(obs, name="part"):
    obs = [o for o in obs if o is not None]
    if len(obs) == 1:
        obs[0].name = name
        return obs[0]
    ctx = bpy.context
    for o in ctx.scene.objects:
        o.select_set(False)
    for o in obs:
        o.select_set(True)
    ctx.view_layer.objects.active = obs[0]
    bpy.ops.object.join()
    ob = ctx.view_layer.objects.active
    ob.name = name
    return ob


# --- Donor parts ---------------------------------------------------------------

def _load_donor(name):
    with bpy.data.libraries.load(DONORS, link=False) as (src, dst):
        if name not in src.objects:
            raise KeyError("donor %s is not in %s; add it to extract_donors.py" % (name, DONORS))
        dst.objects = [name]
    ob = dst.objects[0]
    bpy.context.scene.collection.objects.link(ob)
    ob.data = ob.data.copy()
    return ob


def donor(name, keep=None, drop=None, unit=1.0, mats=None, default_mat=None):
    """Loose parts of a Quaternius gun, turned to point +Y and scaled by `unit` metres per
    source unit (the pack's guns share one scale, so donors pulled at the same unit fit
    together; parts of one donor pulled twice keep their places relative to each other).

    keep / drop are predicates on a part's box in the donor's side view: p.u0, p.u1, p.v0, p.v1
    (fractions of the donor's length and height), p.uc, p.vc (centres), p.mat (its material).
    """
    ob = _load_donor(name)
    ob.name = name + "_part"
    me = ob.data
    # Muzzle +X -> +Y: a quarter turn about Z.
    me.transform(Matrix.Rotation(math.radians(90), 4, "Z"))
    lo, hi = bounds(ob)
    size = hi - lo
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    seen = set()
    remove = []

    class P:
        pass

    for v in bm.verts:
        if v.index in seen:
            continue
        comp = []
        stack = [v]
        while stack:
            x = stack.pop()
            if x.index in seen:
                continue
            seen.add(x.index)
            comp.append(x)
            for e in x.link_edges:
                stack.append(e.other_vert(x))
        p = P()
        ys = [c.co.y for c in comp]
        zs = [c.co.z for c in comp]
        p.u0 = (min(ys) - lo.y) / size.y
        p.u1 = (max(ys) - lo.y) / size.y
        p.v0 = (min(zs) - lo.z) / size.z
        p.v1 = (max(zs) - lo.z) / size.z
        p.uc = (p.u0 + p.u1) / 2
        p.vc = (p.v0 + p.v1) / 2
        # The part's material is the one most of its faces carry (a set's order is not stable).
        faces = {f.index: f.material_index for c in comp for f in c.link_faces}
        counts = {}
        for mi in faces.values():
            counts[mi] = counts.get(mi, 0) + 1
        idx = max(sorted(counts), key=lambda m: counts[m]) if counts else 0
        p.mat = me.materials[idx].name.split(".")[0] if me.materials else ""
        ok = keep(p) if keep else True
        if ok and drop and drop(p):
            ok = False
        if not ok:
            remove.extend(comp)
    bmesh.ops.delete(bm, geom=remove, context="VERTS")
    bm.to_mesh(me)
    bm.free()
    me.transform(Matrix.Scale(unit, 4))
    # The donor's whole box, so a recipe can name a place in it after parts are gone (u2y).
    ob["dlo"] = list(lo * unit)
    ob["dsize"] = list(size * unit)
    if mats is not None or default_mat is not None:
        repaint(ob, mats or {}, default_mat)
    return ob


def u2y(ob, u):
    """The y of a fraction along the donor's original length."""
    return ob["dlo"][1] + u * ob["dsize"][1]


def v2z(ob, v):
    return ob["dlo"][2] + v * ob["dsize"][2]


def cut(ob, y, keep="back", axis=1):
    """Slices a part at a plane across `axis` (default the length) and caps the hole."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    no = Vector((0, 0, 0))
    no[axis] = 1.0
    co = Vector((0, 0, 0))
    co[axis] = y
    geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
    res = bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-6, plane_co=co, plane_no=no,
                                 clear_outer=(keep in ("back", "below")), clear_inner=(keep in ("front", "above")))
    edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    if edges:
        bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    bm.to_mesh(ob.data)
    bm.free()
    return ob


def lowest(ob, tol=0.004):
    """The mean (x, y, z) of a part's lowest vertices: where a grip ends, for a magazine to come out."""
    zs = [v.co.z for v in ob.data.vertices]
    m = min(zs)
    pts = [v.co for v in ob.data.vertices if v.co.z < m + tol]
    return sum(pts, Vector()) / len(pts)


def top_at(ob, y, tol=0.01):
    """The highest z of a part within `tol` of a point along its length: where a riser sits on a
    stock whose comb slopes, which its bounds' top does not say."""
    zs = [v.co.z for v in ob.data.vertices if abs(v.co.y - y) < tol]
    if not zs:
        raise ValueError("no vertex of %s near y %.3f" % (ob.name, y))
    return max(zs)


def donor_size(name):
    ob = _load_donor(name)
    ob.data.transform(Matrix.Rotation(math.radians(90), 4, "Z"))
    lo, hi = bounds(ob)
    bpy.data.objects.remove(ob)
    return hi - lo


def kenney(name, material=None, mats=None):
    """A Kenney Blaster Kit part (glTF: -Z forward, so +Y here once imported), its texture
    replaced with one palette material (or a {source material: palette} mapping)."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(KENNEY, name + ".glb"))
    new = [o for o in bpy.data.objects if o not in before]
    meshes = []
    for o in new:
        if o.type == "MESH":
            o.data = o.data.copy()
            o.data.transform(o.matrix_world)
            o.parent = None
            o.matrix_world = Matrix.Identity(4)
            meshes.append(o)
    for o in new:
        if o.type != "MESH":
            bpy.data.objects.remove(o)
    ob = join(meshes, "kenney_" + name)
    if material:
        paint(ob, material)
    elif mats:
        repaint(ob, mats)
    return ob


# --- Finishing and export --------------------------------------------------------

def _uv(ob):
    """One box-projected UV map, so every face has UVs (the iron sight copies the UV of the face
    it stands on; our materials are flat colours, so the values themselves do not matter)."""
    me = ob.data
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    me.uv_layers.new(name="UVMap")
    bm = bmesh.new()
    bm.from_mesh(me)
    layer = bm.loops.layers.uv.active
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        a, b = [(1, 2), (0, 2), (0, 1)][ax]
        for loop in f.loops:
            loop[layer].uv = (loop.vert.co[a] * 4.0, loop.vert.co[b] * 4.0)
    bm.to_mesh(me)
    bm.free()


def _tidy(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    bm.free()
    for p in ob.data.polygons:
        p.use_smooth = False
    _uv(ob)


def godot(v):
    """Blender (x, y, z) -> Godot (x, z, -y)."""
    return (round(v[0], 4), round(v[2], 4), round(-v[1], 4))


def export(gun, path, magazine=None, mag_path=None, length=None):
    """Writes the gun (origin at its bounds' centre, like every model in the table) and, apart,
    its magazine (origin at its own centre). `length` scales both so the gun is that long (the
    length the table's hold was tuned for). Returns the magazine's offset in the gun's space,
    in Godot's axes (ZeeWeaponArt.magazine_offset), and the gun's size (Godot x, y, z)."""
    lo, hi = bounds(gun)
    centre = (lo + hi) / 2
    move(gun, -centre)
    if magazine is not None:
        move(magazine, -centre)
    if length:
        k = length / (hi.y - lo.y)
        for ob in (gun, magazine):
            if ob is not None:
                ob.data.transform(Matrix.Scale(k, 4))
    lo, hi = bounds(gun)
    centre = Vector((0, 0, 0))
    offset = None
    if magazine is not None:
        mlo, mhi = bounds(magazine)
        mc = (mlo + mhi) / 2
        move(magazine, -mc)
        offset = godot(mc - centre)
    for ob, out in ((gun, path), (magazine, mag_path)):
        if ob is None:
            continue
        _tidy(ob)
        for o in bpy.context.scene.objects:
            o.select_set(False)
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True,
                                  export_yup=True, export_apply=True, export_texcoords=True,
                                  export_normals=True, export_materials="EXPORT")
    size = hi - lo
    return offset, (round(size.x, 3), round(size.z, 3), round(size.y, 3))
