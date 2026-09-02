#!/usr/bin/env python
"""oracle.py — juge geometrique d'un asset, a partir d'un measurement deja produit.

Couche PREUVE, moitie « jugement » (cf. docs/forge/ASSET_GEOMETRY_ORACLE_V1_DESIGN.md).
Ce module NE MESURE JAMAIS : il ne lit aucun .glb, il consomme le dict produit par
`measure.py`. C'est ce qui le rend testable sur des measurements figes, sans asset.

Il ne lit jamais non plus une metadonnee ecrite par Blender comme preuve : une telle
donnee est une DECLARATION, confrontee a la mesure par le check `declaration_mismatch`.

Vocabulaire de verdict du studio, ferme : OK | FAIL | BLOCKED.
  OK      -- tous les checks declares passent
  FAIL    -- defaut geometrique MESURE (enterre, flottant, pivot faux, echelle aberrante)
  BLOCKED -- bien forme, mais aucune decision automatique possible -> HumanGate
`REVIEW_REQUIRED` n'existe pas : la nuance vit dans `reason` (ratifie Pierre 2026-08-06).

Usage :
  python -m scripts.forge.asset_geometry.oracle <asset.glb> [--rules R] [--json]
                                                [--require-producer]
Exit 0 = OK · 1 = BLOCKED · 2 = FAIL · 3 = erreur interne.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Any

REPORT_SCHEMA_VERSION = "1.0"
DEFAULT_RULES = Path(__file__).with_name("rules.yaml")

VERDICT_OK = "OK"
VERDICT_FAIL = "FAIL"
VERDICT_BLOCKED = "BLOCKED"

CLASS_MAIN = "MAIN"
CLASS_SECONDARY = "SECONDARY"
CLASS_UNKNOWN = "UNKNOWN"


@dataclass
class Check:
    name: str
    verdict: str                      # OK | FAIL | BLOCKED
    detail: str
    measured: Any = None
    threshold: Any = None
    threshold_source: str | None = None
    # Persistence lineage : ancre la preuve sur une EXPRESSION, pas sur un numero de ligne.
    expression: str | None = None


@dataclass
class Report:
    schema_version: str
    asset_file: str
    sha256: str
    verdict: str
    reason: str | None
    checks: list[dict[str, Any]] = field(default_factory=list)
    census: list[dict[str, Any]] = field(default_factory=list)
    anchor_basis: str = ""
    main_geometry_undetermined: bool = False
    measurement_space: str = ""
    skin_evaluated: bool = False
    up_axis: str = "Y"
    fog: str | None = None


def load_rules(path: str | Path | None = None) -> dict:
    import yaml
    p = Path(path) if path else DEFAULT_RULES
    with open(p, "r", encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def load_manifest(asset_path: str | Path) -> dict | None:
    """Charge le sidecar <asset>.geometry.json s'il existe. Absent != invalide.

    Le manifeste est le RECENSEMENT (quelle geometrie existe, quel role) : il est ecrit
    par un humain au HumanGate, pas par le producteur.
    """
    p = Path(str(asset_path) + ".geometry.json")
    if not p.is_file():
        return None
    with open(p, "r", encoding="utf-8") as fh:
        return json.load(fh)


def load_declaration(asset_path: str | Path) -> dict | None:
    """Charge le sidecar <asset>.metadata.json s'il existe.

    C'est la DECLARATION du producteur (Blender/Qwen). Elle ne fait JAMAIS foi : elle
    est confrontee a la mesure independante par le check `declaration_mismatch`.
    """
    p = Path(str(asset_path) + ".metadata.json")
    if not p.is_file():
        return None
    with open(p, "r", encoding="utf-8") as fh:
        return json.load(fh)


def _effective(rules: dict, overrides: dict | None, *keys: str) -> tuple[Any, str]:
    """Resout un seuil : override du run s'il existe, sinon rules.yaml. Jamais implicite."""
    if overrides:
        cur: Any = overrides
        ok = True
        for k in keys:
            if isinstance(cur, dict) and k in cur:
                cur = cur[k]
            else:
                ok = False
                break
        if ok and not isinstance(cur, dict):
            return cur, "asset_request"
    cur = rules
    for k in keys:
        cur = cur[k]
    return cur, "rules.yaml"


def classify(node: dict, rules: dict, manifest: dict | None) -> tuple[str, str | None, str | None]:
    """Classe un noeud mesh. Retourne (classe, role_declare, raison_si_UNKNOWN).

    Purement mecanique. Une geometrie UNKNOWN n'est JAMAIS supprimee ni ignoree : elle
    porte une RAISON obligatoire disant pourquoi elle n'a pas pu etre expliquee. Sans
    cette raison, l'operateur ne saurait pas quoi corriger -- un blocage muet est un
    blocage inexploitable.
    """
    declared: dict[str, str] = {}
    if manifest:
        for m in manifest.get("meshes", []):
            if m.get("role"):
                declared[m.get("name", "")] = m["role"]

    role = declared.get(node["name"])
    if role and role != "main":
        return CLASS_SECONDARY, role, None
    if role == "main":
        return CLASS_MAIN, role, None

    if not node.get("has_material"):
        return CLASS_UNKNOWN, None, (
            "aucun materiau : ni geometrie de rendu identifiable, ni role declare dans "
            "le manifeste"
        )

    rig_names = [s.lower() for s in rules["classification"]["rig_parent_names"]]
    parent = (node.get("parent") or "").lower()
    parented_to_rig = any(r in parent for r in rig_names)

    if node.get("is_skinned") or parented_to_rig:
        return CLASS_MAIN, None, None

    return CLASS_UNKNOWN, None, (
        "non skinne, non parente a un rig, et aucun role declare dans le manifeste "
        f"(parent={node.get('parent') or 'aucun'})"
    )


def probe_producer_environment() -> tuple[bool, str]:
    """Le producteur Blender (WSL) est-il joignable ? N'est JAMAIS une source de mesure."""
    if not shutil.which("wsl.exe") and not shutil.which("wsl"):
        return False, "wsl introuvable sur ce poste"
    exe = shutil.which("wsl.exe") or shutil.which("wsl")
    # Chemin RESOLU, plus recopie. Il etait ici en LITTERAL, dupliquant celui
    # d'`asset_dispatch` : deux autorites pour un meme fait, qui pouvaient deja diverger.
    from forge.blender_bin import BlenderNonConfigure, resolve_blender
    try:
        blender = resolve_blender()
    except BlenderNonConfigure as exc:
        return False, f"Blender non configure sur ce poste: {exc}"
    try:
        r = subprocess.run(
            [exe, "-d", blender.distro, "--", "test", "-x", blender.binaire],
            capture_output=True, timeout=120,
        )
    except Exception as exc:  # noqa: BLE001
        return False, f"appel wsl impossible: {exc}"
    if r.returncode != 0:
        return False, f"binaire Blender absent dans {blender.distro}"
    return True, "Blender 5.1.1 joignable"


def evaluate(
    measurement: dict,
    rules: dict,
    manifest: dict | None = None,
    overrides: dict | None = None,
    declaration: dict | None = None,
    producer_required: bool = False,
    producer_state: tuple[bool, str] | None = None,
) -> Report:
    """Fonction pure : measurement + regles -> rapport. Aucune E/S, aucun .glb lu."""
    rep = Report(
        schema_version=REPORT_SCHEMA_VERSION,
        asset_file=measurement.get("asset_file", ""),
        sha256=measurement.get("sha256", ""),
        verdict=VERDICT_OK,
        reason=None,
        measurement_space=measurement.get("measurement_space", ""),
        skin_evaluated=bool(measurement.get("skin_evaluated", False)),
        up_axis=measurement.get("up_axis", "Y"),
    )

    # --- Environnement producteur : absent => BLOCKED, jamais OK, jamais skip silencieux.
    if producer_required:
        avail, detail = producer_state if producer_state is not None else probe_producer_environment()
        rep.checks.append(Check(
            name="producer_environment",
            verdict=VERDICT_OK if avail else VERDICT_BLOCKED,
            detail=detail,
            expression="probe_producer_environment()",
        ).__dict__)
        if not avail:
            rep.verdict = VERDICT_BLOCKED
            rep.reason = "BLENDER_EXECUTOR_UNAVAILABLE"
            return rep

    nodes = measurement.get("mesh_nodes") or []
    if not nodes:
        rep.verdict = VERDICT_FAIL
        rep.reason = "NO_MEASURABLE_GEOMETRY"
        rep.checks.append(Check(
            name="asset_readable", verdict=VERDICT_FAIL,
            detail="; ".join(measurement.get("errors") or ["aucun noeud mesh"]),
            expression="measurement.mesh_nodes",
        ).__dict__)
        return rep

    # --- Manifeste : present ? a jour ? (sha256 lie le manifeste a l'octet pres)
    # `manifest_present` est INFORMATIF et ne bloque jamais a lui seul : un asset dont
    # toute la geometrie se classe MAIN mecaniquement n'a rien a expliquer. Exiger un
    # manifeste malgre tout rendrait BLOCKED a vie chaque prop statique propre -- et
    # les props sont precisement le cas d'usage des 100 assets a venir.
    # Le blocage vient uniquement de `all_meshes_declared` (geometrie UNKNOWN).
    if manifest is None:
        rep.checks.append(Check(
            name="manifest_present", verdict=VERDICT_OK,
            detail=(f"aucun sidecar {rep.asset_file}.geometry.json -- non requis tant "
                    "qu'aucune geometrie n'est UNKNOWN"),
            expression="load_manifest(asset)",
        ).__dict__)
    else:
        stale = manifest.get("sha256") not in (None, "", rep.sha256)
        rep.checks.append(Check(
            name="manifest_stale",
            verdict=VERDICT_BLOCKED if stale else VERDICT_OK,
            detail=("sha256 du manifeste != asset reel -- declaration perimee"
                    if stale else "manifeste lie au bon asset"),
            measured=rep.sha256[:16], threshold=str(manifest.get("sha256"))[:16],
            expression="manifest.sha256 == measurement.sha256",
        ).__dict__)

    # --- Recensement + classification
    total_v = max(1, measurement.get("total_vertices") or 1)
    share_thr, share_src = _effective(rules, overrides, "classification", "main_share_threshold")
    census: list[dict[str, Any]] = []
    # ASYMETRIE DE LA DECLARATION : une declaration du producteur peut seulement rendre
    # l'oracle PLUS strict, jamais plus permissif. Ici, annoncer des `variants` retire a
    # ces meshes le droit d'etre classes MAIN automatiquement par part de sommets --
    # ils devront etre declares au manifeste par un humain.
    # Sans cette regle, un asset genere a 3 meshes voyait ses 2 etats exclusifs peser
    # ~33% chacun, donc passer MAIN, et la question de la variante disparaissait
    # silencieusement (constate sur gen_chest_01, 2026-08-06).
    annonces = [str(v) for v in (declaration or {}).get("variants", []) if v]

    def _est_variante_annoncee(nom: str) -> bool:
        return any(v == nom or nom.endswith(v) for v in annonces)

    for n in nodes:
        klass, role, why = classify(n, rules, manifest)
        share = n["vertices"] / total_v
        variante_annoncee = _est_variante_annoncee(n["name"])
        if klass == CLASS_UNKNOWN and n.get("has_material") and variante_annoncee:
            why = ("annonce comme variante par le producteur (metadata.json) mais aucun "
                   "role declare au manifeste — une variante exclusive doit etre declaree")
        elif klass == CLASS_UNKNOWN and n.get("has_material") and share >= share_thr:
            klass, why = CLASS_MAIN, None  # branche « part de sommets » : props statiques
        elif klass == CLASS_UNKNOWN and n.get("has_material"):
            why = f"{why} ; part de sommets {share:.1%} < seuil {share_thr:.0%}"
        census.append({
            "name": n["name"], "vertices": n["vertices"], "share": round(share, 4),
            "has_material": n["has_material"], "is_skinned": n["is_skinned"],
            "parent": n.get("parent"), "min_y": n["min"][1], "max_y": n["max"][1],
            "classification": klass, "declared_role": role, "unknown_reason": why,
        })
    rep.census = census

    # --- Sur quelle geometrie portent les checks d'ancrage
    excluded = set(rules.get("roles_excluded_from_anchor", []))
    basis = [c for c in census
             if c["classification"] in (CLASS_MAIN, CLASS_SECONDARY)
             and (c["declared_role"] or "") not in excluded]
    if not any(c["classification"] == CLASS_MAIN for c in census):
        # Cas degrade JAMAIS silencieux : sans MAIN, on retombe sur tous les noeuds.
        basis = census
        rep.main_geometry_undetermined = True
        rep.anchor_basis = "ALL_NODES (aucun MAIN identifie)"
    else:
        rep.anchor_basis = f"MAIN+SECONDARY hors {sorted(excluded)} ({len(basis)} noeuds)"

    min_y = min(c["min_y"] for c in basis)
    max_y = max(c["max_y"] for c in basis)
    height = max_y - min_y

    plane, plane_src = _effective(rules, overrides, "ground", "plane")
    float_tol, float_src = _effective(rules, overrides, "ground", "float_tolerance")
    buried_tol, buried_src = _effective(rules, overrides, "ground", "buried_tolerance")

    # --- ground_contact : l'asset ne doit pas flotter
    floating = min_y > plane + float_tol
    rep.checks.append(Check(
        name="ground_contact",
        verdict=VERDICT_FAIL if floating else VERDICT_OK,
        detail=(f"min_y={min_y:.4f} > plan {plane}+{float_tol} -- l'asset flotte"
                if floating else f"min_y={min_y:.4f} -- ne flotte pas au-dessus du plan {plane}"),
        measured=round(min_y, 6), threshold=plane + float_tol, threshold_source=float_src,
        expression="min_y <= ground.plane + ground.float_tolerance",
    ).__dict__)

    # --- no_buried_geometry : l'asset ne doit pas etre enterre
    buried = min_y < plane - buried_tol
    rep.checks.append(Check(
        name="no_buried_geometry",
        verdict=VERDICT_FAIL if buried else VERDICT_OK,
        detail=(f"min_y={min_y:.4f} < plan {plane}-{buried_tol} -- geometrie sous le sol"
                if buried else f"min_y={min_y:.4f} au-dessus du plan {plane}"),
        measured=round(min_y, 6), threshold=plane - buried_tol, threshold_source=buried_src,
        expression="min_y >= ground.plane - ground.buried_tolerance",
    ).__dict__)

    # --- pivot_at_base : l'origine doit etre au pied, pas au centre
    rule_name, _ = _effective(rules, overrides, "pivot", "origin_rule")
    max_off, off_src = _effective(rules, overrides, "pivot", "max_offset")
    manifest_rule = (manifest or {}).get("origin_rule", rule_name)
    origin_y = (measurement.get("root_origin") or [0.0, 0.0, 0.0])[1]
    offset = min_y - origin_y
    allowed_rules = rules["pivot"]["allowed_origin_rules"]
    if manifest_rule not in allowed_rules:
        # Trou d'echappement ferme : une valeur inconnue ne fait pas taire le check.
        rep.checks.append(Check(
            name="pivot_at_base", verdict=VERDICT_BLOCKED,
            detail=(f"origin_rule='{manifest_rule}' hors enumeration fermee "
                    f"{allowed_rules} -- check non evaluable"),
            measured=manifest_rule, threshold=allowed_rules, threshold_source="rules.yaml",
            expression="manifest.origin_rule in pivot.allowed_origin_rules",
        ).__dict__)
    elif manifest_rule != "base_center":
        rep.checks.append(Check(
            name="pivot_at_base", verdict=VERDICT_OK,
            detail=f"origin_rule='{manifest_rule}' declare par le manifeste -- check non applicable",
            measured=round(offset, 6), threshold=max_off, threshold_source="manifest",
            expression="manifest.origin_rule != 'base_center'",
        ).__dict__)
    else:
        bad_pivot = abs(offset) > max_off
        rep.checks.append(Check(
            name="pivot_at_base",
            verdict=VERDICT_FAIL if bad_pivot else VERDICT_OK,
            detail=(f"bas de la geometrie a {offset:.4f} de l'origine (tolere {max_off}) "
                    f"-- origine probablement au centre"
                    if bad_pivot else f"origine au pied (ecart {offset:.4f})"),
            measured=round(offset, 6), threshold=max_off, threshold_source=off_src,
            expression="abs(min_y - root_origin_y) <= pivot.max_offset",
        ).__dict__)

    # --- scale_within_band : hauteur plausible
    hmin, hmin_src = _effective(rules, overrides, "scale", "min_height")
    hmax, hmax_src = _effective(rules, overrides, "scale", "max_height")
    bad_scale = not (hmin <= height <= hmax)
    rep.checks.append(Check(
        name="scale_within_band",
        verdict=VERDICT_FAIL if bad_scale else VERDICT_OK,
        detail=f"hauteur={height:.4f} bande=[{hmin}, {hmax}]",
        measured=round(height, 6), threshold=[hmin, hmax],
        threshold_source=hmin_src if height < hmin else hmax_src,
        expression="scale.min_height <= (max_y - min_y) <= scale.max_height",
    ).__dict__)

    # --- all_meshes_declared : chaque morceau doit avoir un consommateur ou un role
    unknown = [c["name"] for c in census if c["classification"] == CLASS_UNKNOWN]
    policy = rules.get("secondary_mesh_policy", "declaration_required")
    if unknown and policy == "declaration_required":
        v = VERDICT_BLOCKED
        d = (f"{len(unknown)} geometrie(s) presente(s) non expliquee(s): "
             f"{', '.join(unknown[:8])}{' ...' if len(unknown) > 8 else ''}")
    elif unknown:
        v, d = VERDICT_OK, f"{len(unknown)} non declaree(s), policy={policy} -- non bloquant"
    else:
        v, d = VERDICT_OK, "tout noeud mesh est MAIN ou porte un role declare"
    rep.checks.append(Check(
        name="all_meshes_declared", verdict=v, detail=d,
        measured=len(unknown), threshold=0, threshold_source=share_src,
        expression="every mesh_node.classification != UNKNOWN",
    ).__dict__)

    # --- variants_match_geometry : une variante declaree doit EXISTER dans le fichier.
    # Trouve en vivo le 2026-08-06 : Qwen a declare `variants: ["intact","broken"]` pour
    # un tonneau dont l'archetype ne produit qu'un seul mesh. Sans ce check, une
    # declaration de variante purement verbale passait, et la contrainte de lot fondee
    # dessus devenait decorative. Le sens de l'asymetrie est preserve : declarer des
    # variantes ne peut que DURCIR — ici, cela cree une obligation de correspondance.
    if annonces:
        noms_meshes = [c["name"] for c in census]
        orphelines = [v for v in annonces
                      if not any(v == n or n.endswith(v) for n in noms_meshes)]
        rep.checks.append(Check(
            name="variants_match_geometry",
            verdict=VERDICT_FAIL if orphelines else VERDICT_OK,
            detail=(f"variante(s) declaree(s) sans mesh correspondant: {orphelines} "
                    f"(meshes presents: {noms_meshes})"
                    if orphelines else
                    f"les {len(annonces)} variante(s) declaree(s) existent dans le fichier"),
            measured=len(orphelines), threshold=0, threshold_source="declaration",
            expression="every declaration.variants[i] matches a mesh_node name",
        ).__dict__)

    # --- declaration_mismatch : la declaration du producteur confrontee a la mesure
    if declaration is not None:
        decl_min = declaration.get("lowest_point_y", declaration.get("min_y"))
        if decl_min is None:
            rep.checks.append(Check(
                name="declaration_mismatch", verdict=VERDICT_BLOCKED,
                detail="declaration fournie sans champ lowest_point_y/min_y",
                expression="declaration.lowest_point_y",
            ).__dict__)
        else:
            delta = abs(float(decl_min) - min_y)
            mism = delta > float_tol
            rep.checks.append(Check(
                name="declaration_mismatch",
                verdict=VERDICT_FAIL if mism else VERDICT_OK,
                detail=(f"le producteur declare min_y={float(decl_min):.4f}, "
                        f"la mesure independante donne {min_y:.4f} (ecart {delta:.4f})"),
                measured=round(delta, 6), threshold=float_tol, threshold_source=float_src,
                expression="abs(declaration.lowest_point_y - measured min_y) <= tolerance",
            ).__dict__)

    # --- Agregation : un defaut MESURE prime sur une declaration manquante.
    if any(c["verdict"] == VERDICT_FAIL for c in rep.checks):
        rep.verdict = VERDICT_FAIL
        rep.reason = next(c["name"] for c in rep.checks if c["verdict"] == VERDICT_FAIL).upper()
    elif any(c["verdict"] == VERDICT_BLOCKED for c in rep.checks):
        rep.verdict = VERDICT_BLOCKED
        blocked = [c["name"] for c in rep.checks if c["verdict"] == VERDICT_BLOCKED]
        rep.reason = ("SECONDARY_GEOMETRY_WITHOUT_CONTRACT"
                      if "all_meshes_declared" in blocked else blocked[0].upper())
    else:
        rep.verdict = VERDICT_OK
        rep.reason = None

    rep.fog = ("conformite esthetique et adequation visuelle non evaluees -- jugement Pierre "
               "requis. Mesure en pose de liaison (skin non evalue).")
    return rep


def run(asset: str | Path, rules_path: str | Path | None = None,
        overrides: dict | None = None, declaration: dict | None = None,
        producer_required: bool = False) -> Report:
    """Chaine complete : mesure (module separe) -> jugement."""
    from .measure import measure
    m = measure(asset)
    return evaluate(
        asdict(m) if not isinstance(m, dict) else m,
        load_rules(rules_path),
        manifest=load_manifest(asset),
        overrides=overrides,
        # Sidecar du producteur s'il existe ; l'argument explicite reste prioritaire
        # (utile aux tests et a un appelant qui tient la declaration en memoire).
        declaration=declaration if declaration is not None else load_declaration(asset),
        producer_required=producer_required,
    )


def main(argv: list[str]) -> int:
    args = [a for a in argv if not a.startswith("--")]
    if not args:
        print("usage: python -m scripts.forge.asset_geometry.oracle <asset.glb> "
              "[--rules R] [--json] [--require-producer]", file=sys.stderr)
        return 3

    rules_path = None
    if "--rules" in argv:
        rules_path = argv[argv.index("--rules") + 1]

    try:
        rep = run(args[0], rules_path, producer_required="--require-producer" in argv)
    except Exception as exc:  # noqa: BLE001
        print(f"ERREUR INTERNE: {exc}", file=sys.stderr)
        return 3

    if "--json" in argv:
        print(json.dumps(asdict(rep), indent=2, ensure_ascii=False))
    else:
        print(f"ASSET_GEOMETRY_REPORT  {rep.asset_file}")
        print(f"  verdict : {rep.verdict}" + (f"  ({rep.reason})" if rep.reason else ""))
        print(f"  base    : {rep.anchor_basis}")
        for c in rep.checks:
            print(f"  [{c['verdict']:<7}] {c['name']}: {c['detail']}")
        print(f"  recensement ({len(rep.census)} noeuds):")
        for c in rep.census:
            print(f"    {c['classification']:<9} {c['name'][:30]:<30} "
                  f"v={c['vertices']:>7} min_y={c['min_y']:>8.4f}")
        if rep.fog:
            print(f"  FOG: {rep.fog}", file=sys.stderr)

    return {VERDICT_OK: 0, VERDICT_BLOCKED: 1, VERDICT_FAIL: 2}[rep.verdict]


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
