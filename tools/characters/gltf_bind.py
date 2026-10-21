"""Minimal GLB reader/writer + "rest pose = bind pose" rewrite (numpy only).

Why this exists
---------------
Sketchfab re-exports every upload to glTF. The joint nodes then carry whatever
pose the source file was saved in (often an animation frame: a walk cycle, a
fighting stance), while the skin's inverse bind matrices (IBMs) still describe
the pose the mesh was actually modelled/skinned in (usually a clean T/A pose).
Blender's importer either
  * uses the node pose as rest (``guess_original_bind_pose=False``) - robust,
    but the character's rest pose is then that random animation frame, or
  * guesses the bind pose from the IBMs - which breaks on rigs whose control
    bones carry degenerate IBMs (IK targets, poles, 0.01-scaled helpers).

``rewrite_rest_to_bind`` writes a copy of the GLB in which every *valid*
joint node's TRS is replaced by its bind transform (inverse IBM), re-expressed
in its parent's space. Imported with ``guess_original_bind_pose=False`` the
result has rest pose == bind pose and the mesh is reproduced exactly (the
importer's re-skinning becomes a single global transform). Animations are
untouched: they key absolute node TRS, so they still play correctly.

Validity: a joint's bind transform is trusted when its IBM has a sane scale
and the bind position lies in (or near) the bounding box of the vertices
weighted to it; otherwise the joint keeps its original local TRS (it simply
follows its parent).

All functions take/return plain Python / numpy data; nothing here imports
Blender, so the module also runs under a normal ``python3 -I``.
"""
import json
import struct

import numpy as np

_COMP = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
_NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}


def read_glb(path):
    """Return (json_dict, bin_bytes) of a binary glTF file."""
    with open(path, "rb") as f:
        data = f.read()
    magic, _version, length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67:
        raise ValueError("not a GLB file: " + path)
    off, js, binc = 12, None, b""
    while off < length:
        clen, ctype = struct.unpack_from("<II", data, off)
        off += 8
        chunk = data[off:off + clen]
        off += clen
        if ctype == 0x4E4F534A:
            js = json.loads(chunk.decode("utf-8"))
        elif ctype == 0x004E4942:
            binc = bytes(chunk)
    return js, binc


def write_glb(path, js, binc):
    jb = json.dumps(js, separators=(",", ":")).encode("utf-8")
    jb += b" " * ((4 - len(jb) % 4) % 4)
    bb = binc + b"\0" * ((4 - len(binc) % 4) % 4)
    total = 12 + 8 + len(jb) + (8 + len(bb) if bb else 0)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(jb), 0x4E4F534A))
        f.write(jb)
        if bb:
            f.write(struct.pack("<II", len(bb), 0x004E4942))
            f.write(bb)


def accessor(js, binc, index):
    """Decode an accessor to a float64 array of shape (count, ncomp)."""
    a = js["accessors"][index]
    if "sparse" in a:
        raise NotImplementedError("sparse accessors are not supported")
    n = _NCOMP[a["type"]]
    dt = np.dtype(_COMP[a["componentType"]])
    out = np.zeros((a["count"], n))
    if "bufferView" not in a:
        return out
    bv = js["bufferViews"][a["bufferView"]]
    base = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride") or dt.itemsize * n
    raw = np.frombuffer(binc, dtype=np.uint8, count=stride * (a["count"] - 1) + dt.itemsize * n, offset=base)
    for c in range(n):
        idx = np.arange(a["count"]) * stride + c * dt.itemsize
        col = raw[idx[:, None] + np.arange(dt.itemsize)].copy().view(dt).ravel()
        out[:, c] = col
    if a.get("normalized"):
        out /= float(np.iinfo(dt).max)
    return out


def trs_matrix(node):
    if "matrix" in node:
        return np.array(node["matrix"], dtype=float).reshape(4, 4).T
    t = node.get("translation", [0.0, 0.0, 0.0])
    x, y, z, w = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
    s = node.get("scale", [1.0, 1.0, 1.0])
    R = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    M = np.eye(4)
    M[:3, :3] = R * np.array(s, dtype=float)
    M[:3, 3] = t
    return M


def parents(js):
    p = {}
    for i, n in enumerate(js.get("nodes", [])):
        for c in n.get("children", []):
            p[c] = i
    return p


def world_matrices(js):
    """World matrix of every node in its file pose."""
    nodes = js.get("nodes", [])
    par = parents(js)
    cache = {}

    def w(i):
        if i not in cache:
            L = trs_matrix(nodes[i])
            cache[i] = w(par[i]) @ L if i in par else L
        return cache[i]

    return [w(i) for i in range(len(nodes))]


def decompose(M):
    """4x4 -> (translation, quaternion xyzw, scale); shear is discarded."""
    t = M[:3, 3].copy()
    A = M[:3, :3]
    s = np.linalg.norm(A, axis=0)
    s[s < 1e-12] = 1e-12
    R = A / s
    U, _, Vt = np.linalg.svd(R)
    R = U @ Vt
    if np.linalg.det(R) < 0:
        s[0] = -s[0]
        R[:, 0] = -R[:, 0]
    tr = np.trace(R)
    if tr > 0:
        k = np.sqrt(tr + 1.0) * 2
        q = [(R[2, 1] - R[1, 2]) / k, (R[0, 2] - R[2, 0]) / k, (R[1, 0] - R[0, 1]) / k, 0.25 * k]
    elif R[0, 0] > R[1, 1] and R[0, 0] > R[2, 2]:
        k = np.sqrt(1.0 + R[0, 0] - R[1, 1] - R[2, 2]) * 2
        q = [0.25 * k, (R[0, 1] + R[1, 0]) / k, (R[0, 2] + R[2, 0]) / k, (R[2, 1] - R[1, 2]) / k]
    elif R[1, 1] > R[2, 2]:
        k = np.sqrt(1.0 + R[1, 1] - R[0, 0] - R[2, 2]) * 2
        q = [(R[0, 1] + R[1, 0]) / k, 0.25 * k, (R[1, 2] + R[2, 1]) / k, (R[0, 2] - R[2, 0]) / k]
    else:
        k = np.sqrt(1.0 + R[2, 2] - R[0, 0] - R[1, 1]) * 2
        q = [(R[0, 2] + R[2, 0]) / k, (R[1, 2] + R[2, 1]) / k, 0.25 * k, (R[1, 0] - R[0, 1]) / k]
    q = np.array(q)
    return t, q / np.linalg.norm(q), s


def skinned_vertices(js, binc, skin_index):
    """Raw (bind-space) positions + per-vertex joint indices/weights of every
    primitive skinned with ``skin_index``."""
    P, J, W = [], [], []
    for n in js.get("nodes", []):
        if n.get("skin") != skin_index or "mesh" not in n:
            continue
        for prim in js["meshes"][n["mesh"]]["primitives"]:
            at = prim["attributes"]
            if "JOINTS_0" not in at:
                continue
            P.append(accessor(js, binc, at["POSITION"]))
            # all influence sets (JOINTS_0/1/..., WEIGHTS_0/1/...) side by side
            k = 0
            js_sets, ws_sets = [], []
            while "JOINTS_%d" % k in at:
                js_sets.append(accessor(js, binc, at["JOINTS_%d" % k]).astype(int))
                ws_sets.append(accessor(js, binc, at["WEIGHTS_%d" % k]))
                k += 1
            J.append(np.concatenate(js_sets, axis=1))
            W.append(np.concatenate(ws_sets, axis=1))
    if not P:
        return np.zeros((0, 3)), np.zeros((0, 4), int), np.zeros((0, 4))
    width = max(j.shape[1] for j in J)
    J = [np.pad(j, ((0, 0), (0, width - j.shape[1]))) for j in J]
    W = [np.pad(w, ((0, 0), (0, width - w.shape[1]))) for w in W]
    return np.concatenate(P), np.concatenate(J), np.concatenate(W)


def rewrite_rest_to_bind(src, dst, anchor_name=None, max_dist_frac=0.15, log=print):
    """Write ``dst``: a copy of ``src`` whose joint nodes are posed in the bind
    pose (see module docstring). ``anchor_name`` is the joint whose file-pose
    world transform is kept (the hips); the whole bind pose is moved onto it.
    Returns the list of joint names that kept their file pose."""
    js, binc = read_glb(src)
    nodes = js["nodes"]
    par = parents(js)
    Wf = world_matrices(js)
    bind = {}                       # node index -> bind world matrix (file bind space)
    for si, skin in enumerate(js.get("skins", [])):
        if "inverseBindMatrices" not in skin:
            continue
        ibm = accessor(js, binc, skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
        P, J, W = skinned_vertices(js, binc, si)
        height = float(np.ptp(P[:, 1])) if len(P) else 1.0
        for j, ni in enumerate(skin["joints"]):
            B = np.linalg.inv(ibm[j])
            sc = np.linalg.norm(B[:3, :3], axis=0)
            ok = np.all(sc > 1e-6) and sc.max() / sc.min() < 1.05
            if ok and len(P):
                mask = ((J == j) & (W > 0.05)).any(axis=1)
                if mask.any():
                    # the joint must sit in (or near) the box of the vertices it moves
                    lo = P[mask].min(axis=0) - max_dist_frac * height
                    hi = P[mask].max(axis=0) + max_dist_frac * height
                    ok = bool(np.all(B[:3, 3] >= lo) and np.all(B[:3, 3] <= hi))
                else:
                    ok = False      # unweighted control/helper bone: leave it alone
            if ok:
                bind[ni] = B
    if not bind:
        raise ValueError("no usable inverse bind matrices in " + src)
    names = {i: n.get("name", "") for i, n in enumerate(nodes)}
    anchor = None
    if anchor_name:
        anchor = next((i for i in bind if names[i] == anchor_name), None)
        if anchor is None:
            raise ValueError("anchor joint %r has no usable bind matrix" % anchor_name)
    else:
        anchor = min(bind, key=lambda i: len([1 for _ in _ancestors(i, par)]))
    # Global frame: move the bind pose onto the anchor joint. Its rotation is
    # snapped to the nearest axis-aligned frame so that file-frame conversions
    # (Z-up vs Y-up, cm vs m) survive but the anchor's own pose (a twisted or
    # tilted hip in an idle frame) does not leak into the whole character.
    G = Wf[anchor] @ np.linalg.inv(bind[anchor])
    sc = np.cbrt(abs(np.linalg.det(G[:3, :3])))
    R = G[:3, :3] / sc
    P = np.zeros((3, 3))
    for c in range(3):
        r = int(np.argmax(np.abs(R[:, c])))
        P[r, c] = np.sign(R[r, c])
    if abs(abs(np.linalg.det(P)) - 1.0) < 1e-6:
        Gs = np.eye(4)
        Gs[:3, :3] = sc * P
        Gs[:3, 3] = Wf[anchor][:3, 3] - Gs[:3, :3] @ bind[anchor][:3, 3]
        G = Gs
    # new world matrices, parents before children
    order = sorted(range(len(nodes)), key=lambda i: len(list(_ancestors(i, par))))
    Wn = {}
    kept = []
    for i in order:
        p = par.get(i)
        Wp_new = Wn[p] if p is not None else np.eye(4)
        if i in bind:
            Wn[i] = G @ bind[i]
            L = (np.linalg.inv(Wp_new) if p is not None else np.eye(4)) @ Wn[i]
            t, q, s = decompose(L)
            n = nodes[i]
            n.pop("matrix", None)
            n["translation"] = [float(v) for v in t]
            n["rotation"] = [float(v) for v in q]
            n["scale"] = [float(v) for v in s]
        else:
            Wn[i] = Wp_new @ trs_matrix(nodes[i])
            if any(i in sk["joints"] for sk in js.get("skins", [])):
                kept.append(names[i])
    write_glb(dst, js, binc)
    log("BIND rewrote %d joints (anchor %s); %d joints kept their file pose" % (len(bind), names[anchor], len(kept)))
    return kept


def _ancestors(i, par):
    while i in par:
        i = par[i]
        yield i
