"""Builds assets/arms/arms-rigged.glb: one rigged first-person arm, from a CC0 base.

Base: "fps arms (rigged only)" by para, https://opengameart.org/content/fps-arms-rigged-only,
licence CC0 (verified on the page, 2026-10-19). The author built the mesh with MakeHuman.

What is changed, so it is not the pack's model:
  * Only the right arm is kept (the left hand is this one mirrored in code, like the glove).
  * The author's IK / copy-rotation control bones and constraints are dropped: the game poses
    the bones itself (ZeeViewArms), so the file carries the 25 deform bones and nothing else.
  * clavicle and deltoid weights are merged into upper_arm; bones are renamed to plain names.
  * The skin texture is dropped. The mesh is split into two surfaces by what it covers, Glove
    (hand, fingers, thumb) and Sleeve (forearm and above), so the game paints both in its own
    colours, as the code-built gloves are painted.
  * The wrist gets a flared cuff and the sleeve is thickened slightly, and the whole arm is
    scaled to a 0.52 m shoulder-to-wrist reach and put at the origin (shoulder at 0,0,0).

Run (staging02 or dev02; Blender 4.3):
    blender -b <FPS ARMS RIG 1.blend> --python build_arms.py -- <out.glb>
The .blend is not in the repo: download it from the page above (its licence is CC0).
"""
import sys
import math
import bpy
import bmesh
from mathutils import Vector

out_path = sys.argv[sys.argv.index("--") + 1]
REACH = 0.52          # shoulder to wrist, metres
CUFF_LENGTH = 0.045   # metres up the forearm that flares
CUFF_FLARE = 0.16     # fraction the forearm widens at the wrist
SLEEVE_BULK = 1.06    # forearm and upper arm widening

for ob in list(bpy.data.objects):
    if ob.type not in {"ARMATURE", "MESH"}:
        bpy.data.objects.remove(ob, do_unlink=True)

arm_ob = next(o for o in bpy.data.objects if o.type == "ARMATURE")
body = next(o for o in bpy.data.objects if o.type == "MESH")

for ob in (arm_ob, body):
    for coll in ob.users_collection:
        coll.hide_viewport = False
        coll.hide_select = False
    ob.hide_viewport = False
    ob.hide_select = False
    ob.hide_set(False)
    if ob.name not in bpy.context.view_layer.objects:
        bpy.context.scene.collection.objects.link(ob)
print("ARMS: in view layer", [(o.name, o.visible_get(), o.hide_select) for o in (arm_ob, body)])

bpy.context.view_layer.objects.active = arm_ob
if arm_ob.mode != "OBJECT":
    bpy.ops.object.mode_set(mode="OBJECT")
print("ARMS: mode", arm_ob.mode, body.mode, "anim", arm_ob.animation_data)

# --- rest pose, free of the author's constraints ---------------------------------------------
arm_ob.data.pose_position = "REST"
for pb in arm_ob.pose.bones:
    for c in list(pb.constraints):
        pb.constraints.remove(c)

bpy.context.view_layer.objects.active = body
for ob in bpy.data.objects:
    ob.select_set(False)
body.select_set(True)
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
for ob in (body, arm_ob):
    ob.select_set(True)
bpy.context.view_layer.objects.active = arm_ob
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# --- keep the right side only ----------------------------------------------------------------
bm = bmesh.new()
bm.from_mesh(body.data)
dl = bm.verts.layers.deform.verify()
names = {vg.index: vg.name for vg in body.vertex_groups}
doomed = []
for v in bm.verts:
    w = v[dl]
    if not w:
        doomed.append(v)
        continue
    top = max(w.items(), key=lambda kv: kv[1])[0]
    if names[top].endswith(".L"):
        doomed.append(v)
bmesh.ops.delete(bm, geom=doomed, context="VERTS")
bm.to_mesh(body.data)
bm.free()

# merge clavicle/deltoid weights into upper_arm
vg_up = body.vertex_groups["upper_arm.R"]
for src in ("clavicle.R", "deltoid.R"):
    vg = body.vertex_groups.get(src)
    if vg is None:
        continue
    for v in body.data.vertices:
        for g in v.groups:
            if g.group == vg.index and g.weight > 0:
                vg_up.add([v.index], g.weight, "ADD")
    body.vertex_groups.remove(vg)
for vg in list(body.vertex_groups):
    if vg.name.endswith(".L") or "control" in vg.name:
        body.vertex_groups.remove(vg)

# --- skeleton: delete everything but the right deform chain, rename ---------------------------
keep_root = "upper_arm.R"
bpy.ops.object.mode_set(mode="EDIT")
eb = arm_ob.data.edit_bones
for b in list(eb):
    if b.name in {"clavicle.R", "deltoid.R"} or b.name.endswith(".L") or "control" in b.name:
        eb.remove(b)
eb[keep_root].parent = None
# The author hung the hand off its IK control bone, not the forearm; the control is gone.
eb["hand.R"].parent = eb["forearm.R"]
eb["hand.R"].use_connect = False
bpy.ops.object.mode_set(mode="OBJECT")


def plain(name):
    n = name[:-2] if name.endswith(".R") else name
    return n.replace(".0", "_").replace(".", "_")


for b in arm_ob.data.bones:
    b.name = plain(b.name)
for vg in body.vertex_groups:
    vg.name = plain(vg.name)

# --- scale to metres, shoulder at the origin --------------------------------------------------
bones = arm_ob.data.bones
shoulder = bones["upper_arm"].head_local.copy()
wrist = bones["forearm"].tail_local.copy()
k = REACH / (wrist - shoulder).length
for ob in (arm_ob, body):
    ob.select_set(True)
bpy.context.view_layer.objects.active = arm_ob
arm_ob.location = -shoulder * k
arm_ob.scale = (k, k, k)
body.location = -shoulder * k
body.scale = (k, k, k)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
arm_ob.select_set(False)

# --- shape: flared cuff, slightly fuller sleeve ------------------------------------------------
bones = arm_ob.data.bones
w_head = bones["hand"].head_local.copy()
f_dir = (bones["forearm"].tail_local - bones["forearm"].head_local).normalized()
bm = bmesh.new()
bm.from_mesh(body.data)
dl = bm.verts.layers.deform.verify()
names = {vg.index: vg.name for vg in body.vertex_groups}
hand_groups = {n for n in names.values() if n in {"hand", "thumb_1", "thumb_2", "thumb_3"}
               or n.startswith("palm_") or n.startswith("f_")}
for v in bm.verts:
    wts = {names[i]: w for i, w in v[dl].items()}
    forearm_w = wts.get("forearm", 0.0) + wts.get("upper_arm", 0.0)
    if forearm_w < 0.5:
        continue
    along = (v.co - w_head).dot(f_dir)          # negative up the arm
    axis_pt = w_head + f_dir * along
    radial = v.co - axis_pt
    scale = SLEEVE_BULK
    if -CUFF_LENGTH < along <= 0.0:
        t = 1.0 + along / CUFF_LENGTH            # 0 at the cuff's top, 1 at the wrist
        scale += CUFF_FLARE * math.sin(t * math.pi * 0.5)
    v.co = axis_pt + radial * scale
bm.to_mesh(body.data)

# --- two surfaces: Glove (hand) and Sleeve ------------------------------------------------------
def make_mat(name, colour, rough):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    p.inputs["Base Color"].default_value = colour
    p.inputs["Roughness"].default_value = rough
    return m

body.data.materials.clear()
body.data.materials.append(make_mat("Glove", (0.27, 0.27, 0.30, 1.0), 0.85))
body.data.materials.append(make_mat("Sleeve", (0.22, 0.32, 0.44, 1.0), 0.9))
for f in bm.faces:
    hand_w = 0.0
    for v in f.verts:
        wts = {names[i]: w for i, w in v[dl].items()}
        hand_w += sum(w for n, w in wts.items() if n in hand_groups)
    hand_w /= len(f.verts)
    f.material_index = 0 if hand_w > 0.5 else 1
    f.smooth = True
bm.to_mesh(body.data)
bm.free()
body.data.uv_layers.clear() if hasattr(body.data.uv_layers, "clear") else None
body.name = "Arm"
arm_ob.name = "ArmRig"

# --- report and export --------------------------------------------------------------------------
tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
print("ARMS: tris", tris, "verts", len(body.data.vertices), "bones", len(arm_ob.data.bones))
print("ARMS: bounds", [tuple(round(c, 3) for c in (body.matrix_world @ Vector(c))) for c in body.bound_box][::7])
print("ARMS: bones", [b.name for b in arm_ob.data.bones])
body.parent = arm_ob
body.matrix_parent_inverse.identity()
arm_ob.animation_data_clear()
for ob in bpy.data.objects:
    ob.select_set(False)
body.select_set(True)
arm_ob.select_set(True)
bpy.context.view_layer.objects.active = arm_ob
bpy.ops.export_scene.gltf(
    filepath=out_path, export_format="GLB", use_selection=True, export_apply=False,
    export_animations=False, export_skins=True, export_yup=True, export_texcoords=False,
    export_image_format="NONE", export_materials="EXPORT",
)
print("ARMS: wrote", out_path)
