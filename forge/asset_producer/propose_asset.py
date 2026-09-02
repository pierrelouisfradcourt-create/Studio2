#!/usr/bin/env python
"""propose_asset.py — depose une PROPOSITION d'ingestion d'asset dans la KB.

P0 (2026-08-06) : corrige une violation reelle. Le premier lot d'assets avait ete
ecrit DIRECTEMENT dans knowledge_base/catalog.json, alors que toute memoire de
reference de ce depot est propose-only (ADR-002 ; cf. l'en-tete de
forge/kb_proposal.py : « la machine propose et prouve, l'humain tranche
et signe »). Le catalogue a ete restaure a l'identique, et ce module remplace
l'ecriture directe.

AUCUN NOUVEAU SYSTEME. Ce module ecrit exactement le meme artefact
`kb.proposal.v1` que `kb_proposal.py`, dans le meme repertoire, et la promotion
passe par la porte deja existante et deja testee :

    python -m scripts.forge.kb_proposal --apply <proposal_id> --ratifie-par "<humain>"

`kb_proposal.apply_proposal()` est deja generique (il resout
`brick_id or asset_id or role_id`) : rien a y modifier. Ce module ne fait que
produire l'entree que cette porte sait deja promouvoir.

CE QUE CE MODULE N'ECRIT JAMAIS :
  - catalog.json           (c'est --apply, geste humain explicite)
  - <asset>.glb.geometry.json  (c'est le HumanGate, jamais un producteur)

Il REFUSE de proposer un asset dont l'oracle geometrique ne rend pas OK : une
proposition n'est pas un moyen de contourner le verdict, c'est un moyen de le
transporter jusqu'a un humain.

Usage :
  python -m scripts.forge.asset_producer.propose_asset <asset.glb> [...] [--force]
  python -m scripts.forge.asset_producer.propose_asset --list
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
KB_ROOT = REPO / "knowledge_base"
PROPOSALS = KB_ROOT / "proposals"

PROPOSAL_SCHEMA = "kb.proposal.v1"
PROPOSAL_STATUS_PROPOSED = "PROPOSED"
ORIGINAL_MARKER = "ORIGINAL — aucune inspiration externe citee"

PROPOSAL_ID_PREFIX = "asset."


def _yaml():
    try:
        import yaml
    except ImportError as exc:  # pragma: no cover - environnement sans PyYAML
        raise SystemExit(f"PyYAML requis pour propose_asset.py : {exc}")
    return yaml


def proposal_id_for(asset_id: str) -> str:
    return PROPOSAL_ID_PREFIX + asset_id


def build_proposal(asset_path: str | Path, report, declaration: dict) -> dict:
    """Construit l'enregistrement kb.proposal.v1 pour UN asset deja juge OK.

    `report` est le rapport de scripts.forge.asset_geometry.oracle (jamais une
    promesse : son `verdict` est recopie tel quel, et l'appelant a deja refuse
    tout ce qui n'est pas OK).
    """
    p = Path(asset_path)
    asset_id = declaration["asset_id"]
    rel = os.path.relpath(p, REPO).replace("\\", "/")
    manifest = Path(str(p) + ".geometry.json")
    rel_manifest = (os.path.relpath(manifest, REPO).replace("\\", "/")
                    if manifest.is_file() else None)

    entry = {
        "entry_type": "asset",
        "asset_id": "asset-" + asset_id.replace("_", "-"),
        "source": declaration.get("source", ORIGINAL_MARKER),
        "license": declaration.get("license", "CC0-1.0"),
        "provenance_url": declaration.get("provenance_url"),
        "style": declaration.get("style", "lowpoly"),
        "genre": declaration.get("genre", ["generic"]),
        "biome": None,
        "format": "3D",
        "size_kb": max(1, round(p.stat().st_size / 1024)),
        "sha256": report.sha256,
        "runtime": "godot",
        "ingested": True,
        "path": rel,
        "usage_examples": [],
        "tier": "candidate",
        "category": declaration["category"],
        # Recopie du verdict REELLEMENT obtenu. kb-validate refuse != "OK" a
        # l'application : recopier un verdict flatteur ne sert a rien.
        "geometry_status": report.verdict,
        "geometry_manifest": rel_manifest,
        "consumer": declaration["consumer_examples"],
        "variants": declaration.get("variants", []),
    }

    return {
        "schema": PROPOSAL_SCHEMA,
        "status": PROPOSAL_STATUS_PROPOSED,
        "proposal_id": proposal_id_for(asset_id),
        "origine": "asset_library_v1 — forge/asset_producer/propose_asset.py",
        "statement": (
            f"Ingerer l'asset 3D '{asset_id}' ({declaration['category']}) dans la "
            "bibliotheque : geometrie mesuree independamment et jugee OK par "
            "l'Asset Geometry Oracle."
        ),
        "entree_catalogue_proposee": entry,
        "preuve": {
            "oracle": "forge/asset_geometry/oracle.py",
            "verdict": report.verdict,
            "measurement_space": report.measurement_space,
            "skin_evaluated": report.skin_evaluated,
            "anchor_basis": report.anchor_basis,
            "checks": {c["name"]: c["verdict"] for c in report.checks},
            "census": [
                {"name": c["name"], "classification": c["classification"],
                 "declared_role": c["declared_role"]}
                for c in report.census
            ],
            "declaration_producteur": (
                "<asset>.glb.metadata.json — DECLARATION, confrontee par "
                "declaration_mismatch, jamais une preuve"
            ),
            "generation_report": f"{asset_id}.generation_report.json",
        },
        "ratification": {
            "statut": "EN_ATTENTE",
            "decideur": None,
            "commande": (
                "python -m scripts.forge.kb_proposal --apply "
                f"{proposal_id_for(asset_id)} --ratifie-par \"<humain>\""
            ),
        },
    }


def propose(assets: list[str], *, force: bool = False) -> dict:
    """Genere une proposition par asset OK. Retourne un compte-rendu."""
    yaml = _yaml()
    sys.path.insert(0, str(REPO))
    from forge.asset_geometry import oracle as O  # import tardif : REPO doit etre en path

    PROPOSALS.mkdir(parents=True, exist_ok=True)
    proposes, refuses, ignores = [], [], []

    for a in assets:
        p = Path(a)
        decl_path = Path(str(p) + ".metadata.json")
        if not decl_path.is_file():
            refuses.append((p.name, "NO_DECLARATION",
                            "aucun <asset>.glb.metadata.json — asset non tracable"))
            continue
        declaration = json.loads(decl_path.read_text(encoding="utf-8"))

        report = O.run(p)
        if report.verdict != "OK":
            # Une proposition ne contourne jamais un verdict.
            refuses.append((p.name, report.verdict, report.reason or ""))
            continue

        pid = proposal_id_for(declaration["asset_id"])
        out = PROPOSALS / f"{pid}.yaml"
        if out.exists() and not force:
            ignores.append((p.name, f"proposition deja presente: {out.name}"))
            continue

        record = build_proposal(p, report, declaration)
        with open(out, "w", encoding="utf-8") as fh:
            yaml.safe_dump(record, fh, allow_unicode=True, sort_keys=False)
        proposes.append(pid)

    return {"proposes": proposes, "refuses": refuses, "ignores": ignores}


def list_asset_proposals() -> list[dict]:
    yaml = _yaml()
    out = []
    if not PROPOSALS.is_dir():
        return out
    for f in sorted(PROPOSALS.glob(f"{PROPOSAL_ID_PREFIX}*.yaml")):
        with open(f, encoding="utf-8") as fh:
            data = yaml.safe_load(fh) or {}
        out.append({"proposal_id": data.get("proposal_id", f.stem),
                    "status": data.get("status"),
                    "asset_id": (data.get("entree_catalogue_proposee") or {}).get("asset_id")})
    return out


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("assets", nargs="*", help="chemins de .glb a proposer")
    ap.add_argument("--list", action="store_true", help="liste les propositions d'asset")
    ap.add_argument("--force", action="store_true", help="recree une proposition existante")
    ns = ap.parse_args(argv)

    if ns.list:
        for p in list_asset_proposals():
            print(f"{p['status']:<10} {p['proposal_id']:<40} {p['asset_id']}")
        return 0

    if not ns.assets:
        ap.print_help()
        return 2

    res = propose(ns.assets, force=ns.force)
    for pid in res["proposes"]:
        print(f"PROPOSE   {pid}")
    for nom, verdict, raison in res["refuses"]:
        print(f"REFUSE    {nom}: {verdict} {raison}", file=sys.stderr)
    for nom, raison in res["ignores"]:
        print(f"IGNORE    {nom}: {raison}", file=sys.stderr)
    print(f"\n{len(res['proposes'])} proposition(s) deposee(s) dans {PROPOSALS}")
    print("Promotion (geste humain explicite) :")
    print('  python -m scripts.forge.kb_proposal --apply <proposal_id> --ratifie-par "<humain>"')
    return 0 if not res["refuses"] else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
