# Awake app icon -- full scene build + render, headless.
# Usage:
#   Blender -b --factory-startup -P awake_icon.py -- --variant A --samples 64 --out /path/a.png [--passes DIR]
import bpy, sys, math, time, argparse
from mathutils import Vector, Quaternion

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ap = argparse.ArgumentParser()
ap.add_argument("--variant", default="A")
ap.add_argument("--samples", type=int, default=64)
ap.add_argument("--pass-samples", type=int, default=128)
ap.add_argument("--out", required=True)
ap.add_argument("--passes", default=None, help="dir: also render bg/fg/light passes")
ap.add_argument("--res", type=int, default=1024)
ap.add_argument("--passes-only", action="store_true", help="skip the beauty render")
args = ap.parse_args(argv)
V = args.variant

# ---------------------------------------------------------------- scene reset
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scn_coll = scene.collection

def coll(name):
    c = bpy.data.collections.new(name)
    scn_coll.children.link(c)
    return c

C_ENV, C_LAMP, C_BEAM, C_LIGHTS = coll("Env"), coll("Lamp"), coll("Beam"), coll("Lights")

def link(obj, c):
    for uc in obj.users_collection:
        uc.objects.unlink(obj)
    c.objects.link(obj)
    return obj

# ---------------------------------------------------------------- materials
def principled(name, color, rough=0.4, coat=0.0, metallic=0.0, emit=None, emit_strength=0.0, spec=0.5):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Coat Weight"].default_value = coat
    b.inputs["Coat Roughness"].default_value = 0.25
    b.inputs["Specular IOR Level"].default_value = spec
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = emit_strength
    return m

WARM = (1.0, 0.62, 0.30)          # ~2700K amber
PAINT = principled("LampPaint", (0.80, 0.78, 0.74), rough=0.38, coat=0.35)        # cream satin
INNER = principled("ShadeInner", (0.92, 0.88, 0.80), rough=0.6)                    # bright interior
DARKM = principled("JointMetal", (0.20, 0.21, 0.25), rough=0.3, metallic=0.85)     # hubs / springs
BULB = principled("Bulb", (1, 0.9, 0.75), rough=0.2, emit=(1.0, 0.66, 0.34), emit_strength=6.0)
DESK = principled("Desk", (0.36, 0.23, 0.14), rough=0.40, coat=0.20)               # walnut satin
WALL = principled("Wall", (0.06, 0.08, 0.20), rough=0.9, spec=0.2)
UNDER = principled("Under", (0.03, 0.04, 0.10), rough=0.9, spec=0.2)

def wall_gradient(m, z0, z1, lo=(0.006, 0.009, 0.035), hi=(0.040, 0.050, 0.200)):
    """Self-lit navy->indigo vertical gradient so the night backdrop reads blue, not black."""
    nt = m.node_tree
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value, mr.inputs["From Max"].default_value = z0, z1
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*lo, 1)
    ramp.color_ramp.elements[1].color = (*hi, 1)
    nt.links.new(geo.outputs["Position"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], mr.inputs["Value"])
    nt.links.new(mr.outputs["Result"], ramp.inputs["Fac"])
    b = nt.nodes["Principled BSDF"]
    nt.links.new(ramp.outputs["Color"], b.inputs["Emission Color"])
    b.inputs["Emission Strength"].default_value = 1.0
NOTE = principled("Notebook", (0.62, 0.20, 0.16), rough=0.55)                      # muted red cover
PAGES = principled("Pages", (0.85, 0.82, 0.76), rough=0.8)

# ---------------------------------------------------------------- geometry helpers
def smooth(obj, bevel=0.0, seg=3, angle=40):
    if bevel > 0:
        m = obj.modifiers.new("Bevel", "BEVEL")
        m.width = bevel
        m.segments = seg
        m.limit_method = "ANGLE"
    for p in obj.data.polygons:
        p.use_smooth = True
    obj.modifiers.new("WN", "WEIGHTED_NORMAL").keep_sharp = True
    return obj

def mat(obj, *ms):
    obj.data.materials.clear()
    for m in ms:
        obj.data.materials.append(m)
    return obj

def align_z_to(obj, direction):
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.normalized().to_track_quat("Z", "Y")

def cyl(p1, p2, r, m, c, verts=32, bevel=0.0):
    p1, p2 = Vector(p1), Vector(p2)
    d = p2 - p1
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=d.length, location=(p1 + p2) / 2)
    o = bpy.context.object
    align_z_to(o, d)
    mat(o, m); smooth(o, bevel)
    return link(o, c)

def sphere(p, r, m, c):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, radius=r, location=p)
    o = bpy.context.object
    mat(o, m); smooth(o)
    return link(o, c)

def rbox(loc, size, m, c, bevel=0.05, seg=4):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.object
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    mat(o, m); smooth(o, bevel, seg)
    return link(o, c)

# ---------------------------------------------------------------- the lamp
# Built in a local profile plane (XZ, shade pointing +X / down), then the whole
# rig is yawed so the shade swings toward the camera and the pool reaches the desk edge.
lamp_root = bpy.data.objects.new("LampRoot", None)
C_LAMP.objects.link(lamp_root)
parts = []
def P(o):
    parts.append(o); return o

Y = Vector((0, 1, 0))
base_r = 0.58
base_parts = [P(cyl((0, 0, 0.0), (0, 0, 0.12), base_r, PAINT, C_LAMP, 64, bevel=0.045))]
base_parts.append(P(cyl((0, 0, 0.10), (0, 0, 0.14), 0.22, PAINT, C_LAMP, 48, bevel=0.015)))
J1 = Vector((0.0, 0, 0.36))
P(cyl((0, 0, 0.12), J1, 0.08, PAINT, C_LAMP))                       # post
J2 = Vector((-0.55, 0, 1.00))                                         # elbow
J3 = Vector((0.30, 0, 1.62))                                          # head joint
for j, r in ((J1, 0.13), (J2, 0.14), (J3, 0.12)):                     # hubs (axis along Y)
    P(cyl(j - Y * 0.09, j + Y * 0.09, r, PAINT, C_LAMP, 48, bevel=0.02))
    P(cyl(j - Y * 0.11, j + Y * 0.11, r * 0.45, DARKM, C_LAMP, 32, bevel=0.01))
for s in (-0.055, 0.055):                                              # twin rods per arm
    off = Y * s
    P(cyl(J1 + off, J2 + off, 0.048, PAINT, C_LAMP))
    P(cyl(J2 + off, J3 + off, 0.046, PAINT, C_LAMP))

def spring(a, b, radius=0.028, wire=0.007, turns=16, m=DARKM):
    a, b = Vector(a), Vector(b)
    axis = (b - a)
    q = axis.normalized().to_track_quat("Z", "Y")
    cu = bpy.data.curves.new("spring", "CURVE"); cu.dimensions = "3D"
    cu.bevel_depth = wire; cu.bevel_resolution = 3
    sp = cu.splines.new("POLY")
    n = turns * 16
    sp.points.add(n)
    for i in range(n + 1):
        t = i / n
        ang = t * turns * 2 * math.pi
        local = Vector((radius * math.cos(ang), radius * math.sin(ang), t * axis.length))
        w = a + q @ local
        sp.points[i].co = (*w, 1)
    o = bpy.data.objects.new("Spring", cu)
    cu.materials.append(m)
    C_LAMP.objects.link(o)
    return o
# springs on the camera-facing (-Y) side: base -> lower arm, elbow -> upper arm
P(spring((0.12, -0.13, 0.18), J1.lerp(J2, 0.62) + Vector((0.06, -0.13, 0.02))))
P(spring(J2.lerp(J3, 0.18) + Vector((0, -0.13, -0.06)), J2.lerp(J3, 0.72) + Vector((0, -0.13, -0.06)), radius=0.024, turns=13))
for s in (-0.13, 0.13):
    pass

# shade: open cone, solidified, inner surface its own bright material
d = Vector((1.0, 0, -1.55)).normalized()          # shade axis (out of the opening), ~57 deg down
if V == "C":
    d = Vector((1.0, 0, -1.05)).normalized()      # shallower aim: the beam sweeps a long diagonal
neck = J3 + d * 0.10
shade_len, r_open, r_neck = 0.76, 0.44, 0.15
if V == "C":
    r_open = 0.30                                  # narrower mouth -> a defined cone rather than a wall of light
bpy.ops.mesh.primitive_cone_add(vertices=96, radius1=r_open, radius2=r_neck, depth=shade_len,
                                end_fill_type="NOTHING", location=neck + d * (shade_len / 2))
shade = bpy.context.object
align_z_to(shade, -d)                              # local -Z (radius1, wide end) -> along d
mat(shade, PAINT, INNER)
so = shade.modifiers.new("Solid", "SOLIDIFY"); so.thickness = 0.022; so.offset = -1
so.material_offset = 1; so.use_even_offset = True
smooth(shade)
lip = shade.modifiers.new("Sub", "SUBSURF"); lip.levels = 1; lip.render_levels = 2
link(shade, C_LAMP); P(shade)
# rounded back cap + knob (the little handle on the symbol's shade)
P(sphere(neck, r_neck * 1.02, PAINT, C_LAMP))
back = neck - d * 0.12
knob_dir = Vector((-0.75, 0, 1.0)).normalized()
P(cyl(neck, neck + knob_dir * 0.30, 0.03, PAINT, C_LAMP))
P(sphere(neck + knob_dir * 0.30, 0.055, PAINT, C_LAMP))

opening = neck + d * shade_len
bulb_c = opening - d * 0.10
bulb = P(sphere(bulb_c, 0.165, BULB, C_LAMP))
bulb.name = "Bulb"
socket = P(cyl(neck + d * 0.02, neck + d * 0.26, 0.07, DARKM, C_LAMP, 32))  # socket (kept behind the spot)

for o in parts:
    o.parent = lamp_root

# ---------------------------------------------------------------- lights inside the shade
spot_d = bpy.data.lights.new("ShadeSpot", "SPOT")
spot_d.color = WARM
spot_d.spot_size = math.radians(72)      # a touch wider than the shade lip: the shade itself cuts the edge
spot_d.spot_blend = 0.35
spot_d.shadow_soft_size = 0.10
spot = bpy.data.objects.new("ShadeSpot", spot_d)
C_LIGHTS.objects.link(spot)
spot.location = neck + d * 0.30
align_z_to(spot, -d)                      # lights shine along local -Z
spot.parent = lamp_root

bulbpt_d = bpy.data.lights.new("BulbPoint", "POINT")
bulbpt_d.color = (1.0, 0.72, 0.45)
bulbpt_d.shadow_soft_size = 0.12
bulbpt = bpy.data.objects.new("BulbPoint", bulbpt_d)
C_LIGHTS.objects.link(bulbpt)
bulbpt.location = neck + d * 0.22
bulbpt.parent = lamp_root
bulb.visible_shadow = False               # point light sits inside the glass

# ---------------------------------------------------------------- per-variant setup
# cam: azimuth (deg, + = camera swings left), elevation (deg), distance; target offset from the lamp/pool midpoint
cfg = dict(
    A=dict(yaw=-40, spot_w=650, bulb_w=25, vol=0.10, az=16, el=24, dist=9.6, lens=70, tgt=(0.30, 0, -0.12),
           world=0.55, rim=60, prop=False, edge=0.30),
    B=dict(yaw=-50, spot_w=540, bulb_w=25, vol=0.09, az=14, el=13, dist=6.4, lens=70, tgt=(-0.05, 0, 0.08),
           world=0.45, rim=55, prop=True, edge=0.30),
    # C: the draft-C close crop, camera/framing exactly as drafted (designer's pick); bounce adds warm fill
    C=dict(yaw=-44, spot_w=650, bulb_w=25, vol=0.12, az=4, el=9, dist=4.6, lens=70, tgt=(0.50, 0, -0.10),
           world=0.40, rim=45, prop=True, edge=0.25, nb=(0.42, 0.70, 1.0), bounce=True,
           # cone-as-hero lighting: spot deeper + wider than the lip so the lip cuts a crisp edge
           hero=dict(spot_at=0.17, spot_size=56, blend=0.10, soft=0.03, aniso=0.55, roll=14,
                     spot_w=380, vol=0.22, world=0.28, rim=30, yaw=-20, el=12, dist=5.4, tgt=(0, 0, 0.30))),
    # Cdraft: draft C exactly as drafted (drafts/draft-C.png) -- the chosen app icon. Do not tune.
    Cdraft=dict(yaw=-44, spot_w=650, bulb_w=25, vol=0.12, az=4, el=9, dist=4.6, lens=70, tgt=(0.50, 0, -0.10),
           world=0.40, rim=45, prop=True, edge=0.25, nb=(0.42, 0.70, 1.0)),
    # Cwide: pulled-back C (produced final/awake-final.png); kept for reproducibility
    Cwide=dict(yaw=-50, spot_w=540, bulb_w=25, vol=0.10, az=8, el=16, dist=5.9, lens=70, tgt=(0.14, 0, -0.14),
           world=0.40, rim=45, prop=True, edge=0.02),
)[V]

H = cfg.get("hero")
if H:
    for k in ("spot_w", "vol", "world", "rim", "yaw", "el", "dist", "tgt"):
        if k in H:
            cfg[k] = H[k]
    for k in ():
        cfg[k] = H[k]
    spot.location = neck + d * H["spot_at"]       # local coords; parent transform applies on top
    spot_d.spot_size = math.radians(H["spot_size"])
    spot_d.spot_blend = H["blend"]
    spot_d.shadow_soft_size = H["soft"]
    socket.visible_shadow = False                  # spot sits inside the socket now
    for o in (bulb, bulbpt):                       # only the cone lights the medium: no haze outside it
        o.visible_volume_scatter = False
yaw = math.radians(cfg["yaw"])
lamp_root.rotation_euler = (0, 0, yaw)
spot_d.energy = cfg["spot_w"]
bulbpt_d.energy = cfg["bulb_w"]
Rz = lamp_root.rotation_euler.to_matrix()
hit_local = J3 + d * (J3.z / -d.z)                # where the shade axis meets the desk
pool = Rz @ hit_local
head = Rz @ (J3 + d * 0.4)
print("POOL", tuple(round(x, 2) for x in pool), "HEAD", tuple(round(x, 2) for x in head))
desk_front_y = pool.y - cfg["edge"]               # front edge just past the pool centre: pool spills over it

if V == "A":
    # floating tile; lamp near its back-left, pool spills over the front edge
    x0, x1 = -1.0, pool.x + 1.0
    y1 = 1.0
    desk = rbox(((x0 + x1) / 2, (desk_front_y + y1) / 2, -0.22), (x1 - x0, y1 - desk_front_y, 0.44), DESK, C_ENV, bevel=0.09, seg=8)
    wall = rbox((0, 9, 0), (40, 0.2, 40), WALL, C_ENV, bevel=0)
    wall_gradient(WALL, -5.0, 5.0)
else:
    wall_gradient(WALL, 0.0, 4.5)
    y1 = 3.0
    desk = rbox((0.4, (desk_front_y + y1) / 2, -0.15), (14, y1 - desk_front_y, 0.30), DESK, C_ENV, bevel=0.08, seg=8)
    wall = rbox((0, y1 + 0.1, 3), (30, 0.2, 12), WALL, C_ENV, bevel=0)
    under = rbox((0.4, desk_front_y + 0.35, -2.2), (14, 0.2, 4.0), UNDER, C_ENV, bevel=0)
desk.name = "Desk"

if cfg["prop"]:
    # one closed notebook, half in the pool, half out, near the front edge
    nbx, nby, nbs = cfg.get("nb", (0.30, 0.72, 0.84))
    nb_loc = Vector((pool.x + nbx, desk_front_y + nby, 0.0))
    nb = rbox(nb_loc + Vector((0, 0, 0.035)), (0.62 * nbs, 0.86 * nbs, 0.07), PAGES, C_ENV, bevel=0.012, seg=3)
    cov = rbox(nb_loc + Vector((0, 0, 0.075)), (0.66 * nbs, 0.90 * nbs, 0.012), NOTE, C_ENV, bevel=0.005, seg=2)
    for o in (nb, cov):
        o.rotation_euler = (0, 0, math.radians(18))

mid = (Vector((0, 0, 0.9)) + Vector((pool.x, pool.y, 0.9))) / 2 + Vector(cfg["tgt"])
if H:   # frame the cone itself: halfway between the shade mouth and the pool
    mid = (Rz @ opening + pool) / 2 + Vector(cfg["tgt"])

# ---------------------------------------------------------------- volume (beam medium) -- box only around the beam region
VOL = bpy.data.materials.new("BeamVolume")
VOL.use_nodes = True
nt = VOL.node_tree
nt.nodes.remove(nt.nodes["Principled BSDF"])
pv = nt.nodes.new("ShaderNodeVolumePrincipled")
pv.inputs["Color"].default_value = (1, 1, 1, 1)
pv.inputs["Density"].default_value = cfg["vol"]
pv.inputs["Anisotropy"].default_value = H["aniso"] if H else 0.35
nt.links.new(pv.outputs[0], nt.nodes["Material Output"].inputs["Volume"])
bpy.ops.mesh.primitive_cube_add(size=1, location=(mid.x, mid.y, 1.0))
vb = bpy.context.object
vb.name = "BeamVolumeBox"
vb.scale = (6.0, 5.0, 3.2)
if V == "A":                                       # floating tile: let the beam run only a short way past the edge
    vb.location.z, vb.scale.z = 1.3, 2.6
if H:
    # Hero cone: the medium fills only a cone a little wider than the light cone (apex at the spot).
    # A full-frame medium dims everything behind it -- reads as fog and can't be split into layers.
    WALL.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 0.6  # deeper navy
    bpy.data.objects.remove(vb)
    apex = Rz @ spot.location
    axis = (Rz @ d).normalized()
    L, half = 4.0, math.radians(H["spot_size"] / 2 + 5)
    bpy.ops.mesh.primitive_cone_add(vertices=96, radius1=math.tan(half) * L, radius2=0.0, depth=L,
                                    location=apex + axis * (L / 2))
    vb = bpy.context.object
    vb.name = "BeamVolumeCone"
    align_z_to(vb, -axis)                          # wide end (local -Z) along the beam
    vb.data.materials.append(VOL)
    link(vb, C_BEAM)
vb.data.materials.append(VOL)
link(vb, C_BEAM)
# the box must not trap the shade's back -- it covers the whole lamp; that's fine: unlit volume is near-invisible

# ---------------------------------------------------------------- night ambience
world = bpy.data.worlds.new("Night")
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
bg.inputs["Color"].default_value = (0.020, 0.032, 0.11, 1)
bg.inputs["Strength"].default_value = cfg["world"]

rim_d = bpy.data.lights.new("MoonRim", "AREA")
rim_d.shape = "DISK"; rim_d.size = 4.0
rim_d.color = (0.45, 0.58, 1.0)
rim_d.energy = cfg["rim"] * 10
rim = bpy.data.objects.new("MoonRim", rim_d)
C_LIGHTS.objects.link(rim)
rim.location = (-4.0, 4.5, 6.0)
align_z_to(rim, Vector(rim.location) - Vector((0.3, 0, 0.8)))

fill_d = bpy.data.lights.new("CoolFill", "AREA")
fill_d.shape = "DISK"; fill_d.size = 6.0
fill_d.color = (0.35, 0.45, 1.0)
fill_d.energy = 120
fill = bpy.data.objects.new("CoolFill", fill_d)
C_LIGHTS.objects.link(fill)
fill.location = (-5, -7, 4)
align_z_to(fill, Vector(fill.location) - Vector((0.3, 0, 0.6)))
if cfg.get("bounce"):
    # Warm bounce: the lit pool re-radiating upward. Path-traced bounce off walnut is real but faint at
    # icon scale, so a broad warm upward-facing panel just above the pool pushes amber onto the shade
    # exterior and the undersides of the arm. Invisible to camera, glossy and volume.
    bo_d = bpy.data.lights.new("PoolBounce", "AREA")
    bo_d.shape = "DISK"; bo_d.size = 1.6
    bo_d.color = (1.0, 0.58, 0.30)
    bo_d.energy = 140
    bo = bpy.data.objects.new("PoolBounce", bo_d)
    C_LIGHTS.objects.link(bo)
    bo.location = (pool.x * 0.6, pool.y * 0.6, 0.06)
    align_z_to(bo, Vector((0.30, -0.10, -1.0)))       # emits up and back toward the lamp (-local Z)
    bo.visible_camera = False
    bo.visible_glossy = False
    bo.visible_volume_scatter = False
for o in (rim, fill):
    o.visible_volume_scatter = False          # only the lamp lights the beam medium
world.cycles_visibility.scatter = False

# ---------------------------------------------------------------- camera
cam_d = bpy.data.cameras.new("Cam")
cam_d.lens = cfg["lens"]
cam = bpy.data.objects.new("Cam", cam_d)
scn_coll.objects.link(cam)
az, el = math.radians(cfg["az"]), math.radians(cfg["el"])
cam.location = mid + cfg["dist"] * Vector((-math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
align_z_to(cam, cam.location - mid)
if H and H["roll"]:
    cam.rotation_quaternion = cam.rotation_quaternion @ Quaternion((0, 0, 1), math.radians(H["roll"]))
scene.camera = cam

# ---------------------------------------------------------------- render settings
scene.render.engine = "CYCLES"
prefs = bpy.context.preferences.addons["cycles"].preferences
prefs.compute_device_type = "METAL"
prefs.get_devices()
for dev in prefs.devices:
    dev.use = True
scene.cycles.device = "GPU"
scene.cycles.samples = args.samples
scene.cycles.use_adaptive_sampling = True
scene.cycles.use_denoising = True
scene.cycles.denoiser = "OPENIMAGEDENOISE"
scene.cycles.sample_clamp_indirect = 6.0
scene.cycles.volume_bounces = 0
scene.cycles.max_bounces = 8
scene.cycles.volume_step_rate = 1.0
scene.render.resolution_x = scene.render.resolution_y = args.res
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.image_settings.color_depth = "8"
vs = scene.view_settings
vs.view_transform = "AgX"
for lk in ("AgX - Medium High Contrast", "Medium High Contrast"):
    try:
        vs.look = lk; break
    except TypeError:
        pass
vs.exposure = 0.0

def render(path, samples=None, transparent=False):
    scene.render.film_transparent = transparent
    if samples:
        scene.cycles.samples = samples
    scene.render.filepath = path
    t = time.time()
    bpy.ops.render.render(write_still=True)
    print(f"RENDERED {path} in {time.time() - t:.1f}s", flush=True)

if not args.passes_only:
    render(args.out)

# ---------------------------------------------------------------- Icon Composer passes
if args.passes:
    import os
    os.makedirs(args.passes, exist_ok=True)
    vl = scene.view_layers[0]
    lc = {c.name: c for c in vl.layer_collection.children}
    lamp_objs = [o for o in C_LAMP.objects]

    # 1. background: desk + backdrop exactly as lit in the beauty render. The lamp stays in the scene as an
    #    invisible light-blocker (shade bounds the bulb, base casts its contact shadow), hidden from camera
    #    only. Camera rays then reach the never-lit desk patch under the base disc (a black hole), so a
    #    second render with the base disc's shadow off supplies the pixels wherever the foreground lamp
    #    is opaque; the contact shadow around the base is kept from the first render.
    import numpy as np
    lc["Beam"].exclude = True
    lamp_objs = list(C_LAMP.objects)
    for o in lamp_objs:
        o.visible_camera = False
    bgp = os.path.join(args.passes, "pass-background.png")
    bg2p = os.path.join(args.passes, "_bg-nobaseshadow.png")
    render(bgp, args.pass_samples, transparent=False)
    for o in base_parts:
        o.visible_shadow = False
    render(bg2p, args.pass_samples, transparent=False)
    for o in base_parts:
        o.visible_shadow = True

    # 2. foreground: lamp only on transparent film; env held out (still bounces warm light onto the lamp)
    for o in lamp_objs:
        o.visible_camera = True
    lc["Env"].holdout = True
    fgp = os.path.join(args.passes, "pass-foreground.png")
    render(fgp, args.pass_samples, transparent=True)

    def px(path):
        im = bpy.data.images.load(path)
        a = np.array(im.pixels[:], dtype=np.float32).reshape(-1, 4)
        return im, a
    im1, b1 = px(bgp)
    _, b2 = px(bg2p)
    _, fa = px(fgp)
    a = fa[:, 3:4]
    b1[:, :3] = b1[:, :3] * (1 - a) + b2[:, :3] * a
    im1.pixels[:] = b1.ravel()
    im1.filepath_raw = bgp
    im1.save()
    os.remove(bg2p)
    print("background hole filled", flush=True)

    # 3. light: volumetric beam + bulb halo only; env and lamp held out
    lc["Beam"].exclude = False
    lc["Lamp"].holdout = True
    lp = os.path.join(args.passes, "pass-light.png")
    render(lp, args.pass_samples, transparent=True)
    # The beam is additive light; unlit volume only adds extinction haze. Rebuild alpha from emitted
    # light (premultiplied max channel) so the layer composites cleanly over the others.
    import numpy as np
    img = bpy.data.images.load(lp)
    px = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4)
    pre = px[:, :3] * px[:, 3:4]
    na = np.clip(pre.max(axis=1, keepdims=True), 0, 1)
    px[:, :3] = np.where(na > 1e-4, pre / np.maximum(na, 1e-4), 0)
    px[:, 3:4] = na
    img.pixels[:] = px.ravel()
    img.filepath_raw = lp
    img.file_format = "PNG"
    img.save()
    print("light pass alpha rebuilt", flush=True)
