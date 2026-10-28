"""Asset registry: id -> builder + metadata (output folder, atlas size, intended use)."""
from __future__ import annotations

import importlib

REGISTRY: dict[str, dict] = {}
for _mod in ("weapons", "arsenal", "projectiles", "helmet", "props", "balloon", "chests", "gliders", "melee"):
    try:
        REGISTRY.update(importlib.import_module(f"assets.{_mod}").ASSETS)
    except ModuleNotFoundError as e:  # props may be absent while bootstrapping
        if e.name != f"assets.{_mod}":
            raise
