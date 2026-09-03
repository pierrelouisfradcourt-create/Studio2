"""Rapport de couverture d'un GAME_BLUEPRINT (Lot 1, plan V2 2026-09-03, GO Pierre) — K5.

PREMIER CONSOMMATEUR du Blueprint : recalcule la jointure feature_map ↔ wiremap avec l'oracle de
PRODUCTION (`forge.run_real.check_wiremap_join`, qui appelle `check_wiremap_contract.mjs` et
applique `_join_regime`). Ce module n'a AUCUNE table de régimes à lui : il matérialise les deux
sections dans un répertoire temporaire, appelle l'oracle, et rend son reçu enrichi de la version
et du sha des sections lues. Déterministe, non-LLM, ADVISORY (ne lit ni ne modifie un verdict).

`which` : "design" (wiremap de l'artefact s5, avant build) ou "built" (wiremap.json après s9).
node absent → NOT_MEASURED (jamais un vert par défaut). NO_CLAIM_ALLOWED.

Usage : python -m forge.coverage <GAME_BLUEPRINT.json> [--which design|built]
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
import tempfile
from pathlib import Path

from forge import blueprint as bp
from forge.run_real import check_wiremap_join  # règle de régime UNIQUE : celle de la production

REPO_ROOT = Path(__file__).resolve().parents[1]
WHICH = ("design", "built")


def _not_measured(reason: str, which: str) -> dict:
    return {"status": "NOT_MEASURED", "regime": "NOT_MEASURED", "reason": reason,
            "which": which, "advisory": True}


def coverage_of(blueprint: dict, *, which: str = "built") -> dict:
    if which not in WHICH:
        raise ValueError(f"which={which!r} (attendu : {', '.join(WHICH)})")
    fm = blueprint["sections"]["feature_map"]
    wm = blueprint["sections"]["wiremap"]
    if fm.get("content") is None:
        return _not_measured("feature_map absente du Blueprint", which)
    entry = (wm.get("content") or {}).get(which) or {}
    if entry.get("content") is None:
        return _not_measured(f"wiremap.{which} absente du Blueprint", which)

    tmp = Path(tempfile.mkdtemp(prefix="bp_coverage_"))
    try:
        (tmp / "featuremap.json").write_text(json.dumps(fm["content"], ensure_ascii=False), encoding="utf-8")
        (tmp / "wiremap.json").write_text(json.dumps(entry["content"], ensure_ascii=False), encoding="utf-8")
        receipt = check_wiremap_join(tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if receipt is None:
        return _not_measured("oracle sans reçu (artefact manquant après matérialisation)", which)
    receipt = dict(receipt)
    receipt["which"] = which
    receipt["inputs"] = {
        "feature_map": {"version": fm["version"], "content_sha256": fm["content_sha256"],
                        "source_sha256": fm["source"].get("sha256")},
        "wiremap": {"version": wm["version"], "entry": which,
                    "source_sha256": (entry.get("source") or {}).get("sha256")},
    }
    return receipt


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Couverture feature_map <-> wiremap d'un GAME_BLUEPRINT")
    p.add_argument("blueprint")
    p.add_argument("--which", choices=WHICH, default="built")
    a = p.parse_args(argv)
    b = bp.load(REPO_ROOT / a.blueprint if not Path(a.blueprint).is_absolute() else Path(a.blueprint))
    print(json.dumps(coverage_of(b, which=a.which), ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
