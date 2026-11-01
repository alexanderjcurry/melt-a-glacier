"""Tiny modelling kit for the game's Blender scripts.

Everything is written in *Godot* coordinates (x right, y up, -z forward) and
converted to Blender's z-up space here, so numbers can be copied straight from
the GDScript that places the models. Colours are given the way they should
look on screen (sRGB, like the Color() values in the game) and converted to
linear for glTF.

Run a model script with the bpy Python module, e.g.
    python art/blender/build_village.py
(`pip install bpy` gives Blender as a Python module; see art/README.md).
"""
import math
import os

import bpy  # noqa: I001  (bpy must be imported before bmesh)
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "models")


def to_b(v):
    """Godot (x, y, z) -> Blender (x, -z, y)."""
    return Vector((v[0], -v[2], v[1]))


def _lin(c):
    c = max(0.0, min(1.0, c))
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mats.clear()


_mats = {}


def mat(name, rgb, rough=0.85, metal=0.0, emit=None):
    """A flat-colour material. `rgb` is the on-screen (sRGB) colour."""
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (_lin(rgb[0]), _lin(rgb[1]), _lin(rgb[2]), 1.0)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if emit is not None:
        p.inputs["Emission Color"].default_value = (_lin(emit[0]), _lin(emit[1]), _lin(emit[2]), 1.0)
        p.inputs["Emission Strength"].default_value = 1.0
    _mats[name] = m
    return m


def _obj(name, bm, material, bevel=0.0, segments=2, smooth=False):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if material is not None:
        me.materials.append(material)
    if bevel > 0.0:
        mod = ob.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segments if bevel >= 0.025 else 1   # small bevels: one chamfer is enough
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(40)
        mod.harden_normals = False
    for poly in me.polygons:
        poly.use_smooth = smooth
    return ob


def box(center, size, material, basis=None, bevel=0.02, segments=2, name="box"):
    """A box in Godot space. `basis` is a 3x3 Matrix (Godot space) rotating it."""
    bm = bmesh.new()
    h = Vector(size) * 0.5
    rot = basis if basis is not None else Matrix.Identity(3)
    c = Vector(center)
    vs = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                p = c + rot @ Vector((sx * h.x, sy * h.y, sz * h.z))
                vs.append(bm.verts.new(to_b(p)))
    idx = lambda sx, sy, sz: vs[(sx > 0) * 4 + (sy > 0) * 2 + (sz > 0)]
    faces = [
        [(-1, -1, -1), (-1, -1, 1), (-1, 1, 1), (-1, 1, -1)],
        [(1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1)],
        [(-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1)],
        [(-1, 1, -1), (-1, 1, 1), (1, 1, 1), (1, 1, -1)],
        [(-1, -1, -1), (-1, 1, -1), (1, 1, -1), (1, -1, -1)],
        [(-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)],
    ]
    for f in faces:
        bm.faces.new([idx(*k) for k in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _obj(name, bm, material, bevel, segments)


def boxlh(lo, hi, material, bevel=0.02, name="box"):
    lo, hi = Vector(lo), Vector(hi)
    return box((lo + hi) * 0.5, hi - lo, material, bevel=bevel, name=name)


def rot_x(a):
    return Matrix.Rotation(a, 3, "X")


def rot_y(a):
    return Matrix.Rotation(a, 3, "Y")


def rot_z(a):
    return Matrix.Rotation(a, 3, "Z")


def extrude(points, z0, z1, material, bevel=0.02, name="prism", axis="z"):
    """A polygon (in the xy plane, Godot space) extruded from z0 to z1.
    axis="x" puts the polygon in the zy plane (points are (z, y)) and extrudes along x."""
    bm = bmesh.new()

    def p3(pt, d):
        if axis == "z":
            return to_b((pt[0], pt[1], d))
        return to_b((d, pt[1], pt[0]))

    a = [bm.verts.new(p3(p, z0)) for p in points]
    b = [bm.verts.new(p3(p, z1)) for p in points]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    n = len(points)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([a[i], a[j], b[j], b[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _obj(name, bm, material, bevel)


def lathe(profile, material, segments=16, center=(0, 0, 0), smooth=True, name="lathe", scale_xz=(1.0, 1.0),
          phase=0.0):
    """Revolves [(radius, y), ...] (bottom to top) round the y axis."""
    bm = bmesh.new()
    c = Vector(center)
    rings = []
    for r, y in profile:
        if r <= 1e-5:
            rings.append([bm.verts.new(to_b(c + Vector((0, y, 0))))])
            continue
        ring = []
        for s in range(segments):
            t = math.tau * s / segments + phase
            ring.append(bm.verts.new(to_b(c + Vector((math.cos(t) * r * scale_xz[0], y, math.sin(t) * r * scale_xz[1])))))
        rings.append(ring)
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        if len(a) == 1 and len(b) == 1:
            continue
        if len(a) == 1:
            for s in range(segments):
                bm.faces.new([a[0], b[(s + 1) % segments], b[s]])
        elif len(b) == 1:
            for s in range(segments):
                bm.faces.new([a[s], a[(s + 1) % segments], b[0]])
        else:
            for s in range(segments):
                bm.faces.new([a[s], a[(s + 1) % segments], b[(s + 1) % segments], b[s]])
    if len(rings[0]) > 2:
        bm.faces.new(list(reversed(rings[0])))
    if len(rings[-1]) > 2:
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _obj(name, bm, material, 0.0, smooth=smooth)


def cyl(a, b, r1, r2, material, segments=10, smooth=True, bevel=0.0, name="cyl"):
    """A (tapered) cylinder from point a to point b (Godot space)."""
    a, b = Vector(a), Vector(b)
    d = b - a
    length = d.length
    ob = lathe([(0, 0), (r1, 0), (r2, length), (0, length)] if r2 > 0 else [(0, 0), (r1, 0), (0, length)],
               material, segments, smooth=False, name=name)
    # Orient: the lathe runs along Godot +y; rotate it onto d.
    up = Vector((0, 1, 0))
    q = up.rotation_difference(d.normalized())
    m = Matrix.Translation(to_b(a)) @ _g2b(q.to_matrix())
    ob.data.transform(m)
    if smooth:
        for poly in ob.data.polygons:
            poly.use_smooth = abs(poly.normal.dot(to_b(d.normalized()))) < 0.7
    if bevel > 0:
        mod = ob.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(50)
    return ob


def _g2b(m3):
    """A Godot-space 3x3 rotation as a Blender-space 4x4."""
    c = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))   # Godot -> Blender axes
    return (c @ m3 @ c.inverted()).to_4x4()


def sphere(center, radii, material, segments=12, rings=8, smooth=True, name="sphere", basis=None):
    prof = []
    for i in range(rings + 1):
        phi = math.pi * i / rings
        prof.append((math.sin(phi), -math.cos(phi)))
    ob = lathe([(r if 0 < i < rings else 0.0, y) for i, (r, y) in enumerate(prof)], material, segments,
               smooth=smooth, name=name)
    m = Matrix.Diagonal(to_b(radii).to_4d())
    m[1][1] = radii[2]
    m[0][0] = radii[0]
    m[2][2] = radii[1]
    m[3][3] = 1.0
    rot = _g2b(basis) if basis is not None else Matrix.Identity(4)
    ob.data.transform(Matrix.Translation(to_b(center)) @ rot @ m)
    return ob


def transform(ob, matrix_godot3=None, offset=(0, 0, 0)):
    m = _g2b(matrix_godot3) if matrix_godot3 is not None else Matrix.Identity(4)
    ob.data.transform(Matrix.Translation(to_b(offset)) @ m)
    return ob


def join(objs, name):
    """Applies modifiers and merges objects into one mesh named `name`."""
    dg = bpy.context.evaluated_depsgraph_get()
    bm = bmesh.new()
    mats = []
    for ob in objs:
        ev = ob.evaluated_get(dg)
        me = bpy.data.meshes.new_from_object(ev)
        remap = []
        for m in me.materials:
            if m not in mats:
                mats.append(m)
            remap.append(mats.index(m))
        for poly in me.polygons:
            poly.material_index = remap[poly.material_index] if remap else 0
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
    for ob in objs:
        bpy.data.objects.remove(ob)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def export(filename, objs=None):
    """Exports the given objects (default: the whole scene) as models/<filename>.glb."""
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    targets = objs if objs is not None else list(bpy.context.scene.objects)
    for ob in targets:
        ob.select_set(True)
    path = os.path.join(OUT, filename + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_normals=True, export_materials="EXPORT",
                              export_animations=False, export_extras=False)
    tris = sum(len(p.vertices) - 2 for ob in targets if ob.type == "MESH" for p in ob.data.polygons)
    print("wrote %s (%d triangles)" % (path, tris))


def to_g(v):
    """Blender (x, y, z) -> Godot (x, z, -y)."""
    return Vector((v[0], v[2], -v[1]))


def paint(ob, pick):
    """Gives each face the material pick(godot_face_centre) returns (None = keep)."""
    me = ob.data
    for poly in me.polygons:
        m = pick(to_g(poly.center))
        if m is None:
            continue
        if m.name not in [x.name for x in me.materials]:
            me.materials.append(m)
        poly.material_index = [x.name for x in me.materials].index(m.name)
    return ob


def deform(ob, fn):
    """Moves every vertex: fn(godot_pos) -> new godot_pos."""
    for v in ob.data.vertices:
        v.co = to_b(fn(to_g(v.co)))
    ob.data.update()
    return ob


def torus(center, radius, tube, material, segments=24, sides=8, name="torus", smooth=True):
    """A ring lying flat (round the y axis)."""
    bm = bmesh.new()
    c = Vector(center)
    rings = []
    for s in range(segments):
        t = math.tau * s / segments
        ring = []
        for k in range(sides):
            a = math.tau * k / sides
            r = radius + math.cos(a) * tube
            ring.append(bm.verts.new(to_b(c + Vector((math.cos(t) * r, math.sin(a) * tube, math.sin(t) * r)))))
        rings.append(ring)
    for s in range(segments):
        a, b = rings[s], rings[(s + 1) % segments]
        for k in range(sides):
            bm.faces.new([a[k], a[(k + 1) % sides], b[(k + 1) % sides], b[k]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _obj(name, bm, material, 0.0, smooth=smooth)


def smooth_profile(points, steps=3):
    """Catmull-Rom resampling of a lathe profile, for rounder silhouettes."""
    out = []
    n = len(points)
    for i in range(n - 1):
        p0 = Vector(points[max(i - 1, 0)])
        p1 = Vector(points[i])
        p2 = Vector(points[i + 1])
        p3 = Vector(points[min(i + 2, n - 1)])
        for s in range(steps):
            t = s / steps
            t2, t3 = t * t, t * t * t
            p = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
            out.append((max(p.x, 0.0) if 0 < i + s else p1.x, p.y))
    out.append(tuple(points[-1]))
    return out
