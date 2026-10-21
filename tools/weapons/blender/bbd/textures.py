"""Small textures generated from code (numpy): crate stencil, dandelion pappus bristle.

Written into tools/_cache/weapons/derived/ and consumed by mats.py; they only
end up in a glb after being baked (stencil) or as the alpha-card texture of
the pappus parachutes. Original work of the project.
"""
from __future__ import annotations

import math

import bpy
import numpy as np

from .util import DERIVED


def _save_rgba(name, rgba, path):
    h, w = rgba.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=True)
    img.alpha_mode = "STRAIGHT"
    img.colorspace_settings.name = "sRGB"
    img.pixels.foreach_set(np.clip(rgba, 0, 1).astype(np.float32).ravel())
    img.file_format = "PNG"
    img.filepath_raw = str(path)
    img.save(filepath=str(path))
    bpy.data.images.remove(img)
    return str(path)


def _inside(poly, X, Y):
    """Even-odd point-in-polygon for pixel grids (vectorised ray casting)."""
    inside = np.zeros(X.shape, bool)
    n = len(poly)
    for i in range(n):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % n]
        cond = (y0 > Y) != (y1 > Y)
        xint = x0 + (Y - y0) * (x1 - x0) / ((y1 - y0) + 1e-12)
        inside ^= cond & (X < xint)
    return inside


def _ellipse_leaf(cx, cy, ang, length, width, n=24):
    pts = []
    for k in range(n):
        t = 2 * math.pi * k / n
        x = math.cos(t) * length * 0.5
        y = math.sin(t) * width * 0.5 * (1.0 - 0.35 * math.cos(t))  # teardrop
        ca, sa = math.cos(ang), math.sin(ang)
        pts.append((cx + x * ca - y * sa, cy + x * sa + y * ca))
    return pts


def stencil_carrot(size=512, ss=2):
    """Spray-paint stencil of a carrot with three leaves (white = paint).

    Real stencils need bridges, so the carrot body is cut by two thin gaps
    (they also read as the carrot's growth rings).
    """
    path = DERIVED / "stencil_carrot.png"
    if path.exists():
        return str(path)
    DERIVED.mkdir(parents=True, exist_ok=True)
    N = size * ss
    Y, X = np.mgrid[0:N, 0:N].astype(np.float32) / N
    body_poly = [(0.5, 0.06), (0.62, 0.55)] + [(0.5 + 0.12 * math.cos(math.pi * k / 10),
                                                0.60 + 0.08 * math.sin(math.pi * k / 10)) for k in range(11)] \
        + [(0.38, 0.55)]
    m = _inside(body_poly, X, Y)
    for gy in (0.30, 0.45):  # stencil bridges
        m &= ~((Y > gy) & (Y < gy + 0.022) & (np.abs(X - 0.5) < 0.2))
    for (cx, cy, ang, ln, wd) in ((0.5, 0.83, math.pi / 2, 0.24, 0.10),
                                  (0.37, 0.79, math.pi / 2 + 0.6, 0.22, 0.09),
                                  (0.63, 0.79, math.pi / 2 - 0.6, 0.22, 0.09)):
        m |= _inside(_ellipse_leaf(cx, cy, ang, ln, wd), X, Y)
    m &= ~((Y > 0.685) & (Y < 0.705))  # bridge between leaves and body
    a = m.astype(np.float32).reshape(size, ss, size, ss).mean((1, 3))
    rgba = np.stack([a, a, a, np.ones_like(a)], -1)
    return _save_rgba("stencil_carrot", rgba, path)


def pappus_bristle(w=128, h=512, seed=7):
    """One dandelion pappus bristle: a shaft with fine barbs fanning toward the tip.

    v=0 at the attachment point (beak), v=1 at the bristle tip. Alpha-tested.
    """
    path = DERIVED / "pappus_bristle.png"
    if path.exists():
        return str(path)
    DERIVED.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(seed)
    ss = 2
    W, H = w * ss, h * ss
    acc = np.zeros((H, W), np.float32)

    def line(x0, y0, x1, y1, val, thick=1):
        n = int(max(abs(x1 - x0), abs(y1 - y0)) * 1.5) + 2
        xs = np.linspace(x0, x1, n).round().astype(int)
        ys = np.linspace(y0, y1, n).round().astype(int)
        for dx in range(-thick + 1, thick):
            ok = (xs + dx >= 0) & (xs + dx < W) & (ys >= 0) & (ys < H)
            np.maximum.at(acc, (ys[ok], xs[ok] + dx), val)

    cx = W / 2
    line(cx, 0, cx, H - 1, 1.0, thick=2)                      # shaft
    for k in range(420):                                       # barbs
        t = rng.uniform(0.08, 0.98)
        y = t * H
        side = rng.choice((-1, 1))
        ln = (0.18 + 0.82 * t ** 0.7) * (W * 0.48) * rng.uniform(0.6, 1.0)
        ang = math.radians(rng.uniform(18, 34))
        line(cx, y, cx + side * ln * math.sin(ang), y + ln * math.cos(ang), rng.uniform(0.55, 0.95))
    a = acc.reshape(h, ss, w, ss).mean((1, 3))
    a = np.clip(a * 1.6, 0, 1)
    col = np.ones((h, w, 3), np.float32) * np.array([0.96, 0.95, 0.90], np.float32)
    rgba = np.concatenate([col, a[..., None]], -1)
    return _save_rgba("pappus_bristle", rgba, path)
