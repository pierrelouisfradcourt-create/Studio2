#!/usr/bin/env python
"""measure.py — mesure geometrique INDEPENDANTE d'un .glb/.gltf.

Couche PREUVE de l'architecture (cf. docs/forge/ASSET_GEOMETRY_ORACLE_V1_DESIGN.md §3) :
Blender PRODUIT, ce module MESURE. Aucune metadonnee ecrite par le producteur n'est lue
ici -- la mesure est refaite depuis les octets du fichier. Zero reseau, zero LLM.

Ce module NE JUGE JAMAIS : il ne connait ni tolerance, ni verdict, ni regle. Il produit un
`measurement` que `oracle.py` consomme. Cette separation rend l'oracle testable sur des
measurements figes, sans aucun .glb sur disque.

AXE VERTICAL : glTF est **Y-up** par specification (et Godot aussi). Blender affiche du
Z-up parce que son importeur convertit -- ne jamais confondre. Ici, l'axe sol est **Y**.

Usage :
  python -m scripts.forge.asset_geometry.measure <asset.glb> [--json]
Exit 0 = mesure produite · 2 = fichier illisible/malforme.
"""
from __future__ import annotations

import hashlib
import json
import sys
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Any

import numpy as np

MEASUREMENT_SCHEMA_VERSION = "1.0"

# La mesure porte sur la pose de liaison (bind pose) declaree dans les accesseurs glTF,
# pas sur une evaluation du skinning. Limite mesuree et assumee, cf. design §4 : sur le
# corpus de reference elle est EXACTE pour min_y (le contact au sol) et diverge de <=9%
# sur max_y. Le champ voyage dans le rapport pour que personne ne l'oublie.
MEASUREMENT_SPACE = "gltf_bind_pose"


@dataclass
class MeshNode:
    """Un noeud glTF portant une geometrie, mesure dans l'espace monde du fichier."""

    node_index: int
    name: str
    mesh_name: str
    parent: str | None
    vertices: int
    primitives: int
    has_material: bool
    is_skinned: bool
    # bbox monde, axe vertical = Y (glTF)
    min: list[float]
    max: list[float]

    @property
    def min_y(self) -> float:
        return self.min[1]

    @property
    def max_y(self) -> float:
        return self.max[1]


@dataclass
class Measurement:
    """Sortie complete de la mesure. Aucune notion de verdict, de seuil ou de regle."""

    schema_version: str
    asset_file: str
    sha256: str
    size_bytes: int
    up_axis: str
    measurement_space: str
    skin_evaluated: bool
    mesh_nodes: list[dict[str, Any]] = field(default_factory=list)
    total_vertices: int = 0
    # bbox de l'union de TOUS les noeuds mesh (utile au cas degrade de l'oracle)
    union_min: list[float] | None = None
    union_max: list[float] | None = None
    # origine du/des noeud(s) racine -- sert au check pivot
    root_origin: list[float] | None = None
    errors: list[str] = field(default_factory=list)


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _node_local_matrix(node) -> np.ndarray:
    """Compose la matrice locale d'un noeud glTF (matrix OU TRS, jamais les deux)."""
    if getattr(node, "matrix", None):
        # glTF stocke les matrices en COLUMN-major -> reshape puis transpose.
        return np.array(node.matrix, dtype=float).reshape(4, 4).T

    m = np.eye(4)
    scale = getattr(node, "scale", None) or [1.0, 1.0, 1.0]
    rot = getattr(node, "rotation", None) or [0.0, 0.0, 0.0, 1.0]  # quaternion xyzw
    trans = getattr(node, "translation", None) or [0.0, 0.0, 0.0]

    x, y, z, w = rot
    rm = np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ], dtype=float)

    m[:3, :3] = rm @ np.diag(np.array(scale, dtype=float))
    m[:3, 3] = trans
    return m


def _transform_aabb(mn: list[float], mx: list[float], mat: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Transforme une AABB locale en AABB monde (via ses 8 coins -- exact, pas approche)."""
    corners = np.array([
        [mn[0], mn[1], mn[2]], [mn[0], mn[1], mx[2]],
        [mn[0], mx[1], mn[2]], [mn[0], mx[1], mx[2]],
        [mx[0], mn[1], mn[2]], [mx[0], mn[1], mx[2]],
        [mx[0], mx[1], mn[2]], [mx[0], mx[1], mx[2]],
    ], dtype=float)
    homo = np.hstack([corners, np.ones((8, 1))])
    world = (mat @ homo.T).T[:, :3]
    return world.min(axis=0), world.max(axis=0)


def measure(path: str | Path) -> Measurement:
    """Mesure un .glb/.gltf. Ne leve pas sur fichier invalide : remplit `errors`."""
    from pygltflib import GLTF2  # import tardif : le module reste importable sans la dep

    p = Path(path)
    out = Measurement(
        schema_version=MEASUREMENT_SCHEMA_VERSION,
        asset_file=p.name,
        sha256="",
        size_bytes=0,
        up_axis="Y",
        measurement_space=MEASUREMENT_SPACE,
        skin_evaluated=False,
    )

    if not p.is_file():
        out.errors.append(f"fichier introuvable: {p}")
        return out

    out.sha256 = sha256_of(p)
    out.size_bytes = p.stat().st_size

    try:
        gltf = GLTF2().load(str(p))
    except Exception as exc:  # noqa: BLE001 -- on veut TOUTE erreur de parsing comme donnee
        out.errors.append(f"parsing glTF impossible: {exc}")
        return out

    if gltf is None:
        out.errors.append("parsing glTF impossible: contenu vide")
        return out

    nodes = gltf.nodes or []
    meshes = gltf.meshes or []
    accessors = gltf.accessors or []

    parent_of: dict[int, int] = {}
    for i, n in enumerate(nodes):
        for c in (n.children or []):
            parent_of[c] = i

    scene_index = gltf.scene if gltf.scene is not None else 0
    roots: list[int] = []
    if gltf.scenes and 0 <= scene_index < len(gltf.scenes):
        roots = list(gltf.scenes[scene_index].nodes or [])
    if not roots:
        roots = [i for i in range(len(nodes)) if i not in parent_of]

    if roots:
        out.root_origin = list(_node_local_matrix(nodes[roots[0]])[:3, 3])

    found: list[MeshNode] = []

    def walk(idx: int, parent_mat: np.ndarray) -> None:
        node = nodes[idx]
        world = parent_mat @ _node_local_matrix(node)

        if node.mesh is not None and 0 <= node.mesh < len(meshes):
            mesh = meshes[node.mesh]
            nmin = np.array([np.inf] * 3)
            nmax = np.array([-np.inf] * 3)
            verts = 0
            has_mat = False
            prim_count = 0

            # Spec glTF 3.7.3 : le transform du noeud d'un mesh SKINNE doit etre ignore
            # (les matrices de jointures portent deja le placement). Appliquer le
            # transform ici doublerait la transformation.
            is_skinned = getattr(node, "skin", None) is not None
            mat = np.eye(4) if is_skinned else world

            for prim in (mesh.primitives or []):
                pos = getattr(prim.attributes, "POSITION", None)
                if pos is None or not (0 <= pos < len(accessors)):
                    continue
                acc = accessors[pos]
                if acc.min is None or acc.max is None:
                    # min/max sont OBLIGATOIRES sur POSITION par la spec glTF.
                    out.errors.append(
                        f"accesseur POSITION sans min/max (noeud '{node.name or idx}') "
                        "-- fichier hors spec glTF"
                    )
                    continue
                prim_count += 1
                verts += acc.count or 0
                if prim.material is not None:
                    has_mat = True
                wmin, wmax = _transform_aabb(list(acc.min)[:3], list(acc.max)[:3], mat)
                nmin = np.minimum(nmin, wmin)
                nmax = np.maximum(nmax, wmax)

            if prim_count > 0 and np.all(np.isfinite(nmin)):
                pidx = parent_of.get(idx)
                found.append(MeshNode(
                    node_index=idx,
                    name=node.name or f"node_{idx}",
                    mesh_name=mesh.name or f"mesh_{node.mesh}",
                    parent=(nodes[pidx].name or f"node_{pidx}") if pidx is not None else None,
                    vertices=verts,
                    primitives=prim_count,
                    has_material=has_mat,
                    is_skinned=is_skinned,
                    min=[float(v) for v in nmin],
                    max=[float(v) for v in nmax],
                ))

        for c in (node.children or []):
            walk(c, world)

    for r in roots:
        if 0 <= r < len(nodes):
            walk(r, np.eye(4))

    out.mesh_nodes = [asdict(m) for m in found]
    out.total_vertices = sum(m.vertices for m in found)

    if found:
        umin = np.min(np.array([m.min for m in found]), axis=0)
        umax = np.max(np.array([m.max for m in found]), axis=0)
        out.union_min = [float(v) for v in umin]
        out.union_max = [float(v) for v in umax]
    else:
        out.errors.append("aucun noeud mesh mesurable dans le fichier")

    return out


def main(argv: list[str]) -> int:
    args = [a for a in argv if not a.startswith("--")]
    if not args:
        print("usage: python -m scripts.forge.asset_geometry.measure <asset.glb> [--json]",
              file=sys.stderr)
        return 2

    m = measure(args[0])
    if "--json" in argv:
        print(json.dumps(asdict(m), indent=2))
    else:
        print(f"asset      : {m.asset_file}  ({m.size_bytes} o)")
        print(f"sha256     : {m.sha256[:16]}...")
        print(f"espace     : {m.measurement_space} (up={m.up_axis}, skin_evaluated={m.skin_evaluated})")
        print(f"noeuds mesh: {len(m.mesh_nodes)}  sommets: {m.total_vertices}")
        if m.union_min:
            print(f"union      : min_y={m.union_min[1]:.4f}  max_y={m.union_max[1]:.4f}")
        for n in m.mesh_nodes:
            print(f"  {n['name'][:30]:<30} v={n['vertices']:>7} "
                  f"min_y={n['min'][1]:>8.4f} max_y={n['max'][1]:>8.4f} "
                  f"mat={'Y' if n['has_material'] else 'N'} skin={'Y' if n['is_skinned'] else 'N'}")
        for e in m.errors:
            print(f"  ERREUR: {e}", file=sys.stderr)

    return 2 if m.errors and not m.mesh_nodes else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
