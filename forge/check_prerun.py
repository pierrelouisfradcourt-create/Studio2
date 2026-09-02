#!/usr/bin/env python
"""check_prerun.py — ORACLE AMONT du PRE_RUN_REPORT.

POURQUOI CE FICHIER EXISTE — coût mesuré, pas hypothèse.
Run `pacman-v2-20260805`, étape s4-archi : une décision d'architecture tenant en une
ligne (« créer une racine 04_CONTENT/ ») a été prise sans confrontation à la table
figée `standard/repo_map.yaml`, qui portait DÉJÀ la catégorie voulue
(`level` -> 03_WORLD/levels/{id}/). Coût : 205 896 tokens de première passe puis
232 019 tokens de reprise, soit 53 % du coût de l'étape en refait.
`check_blueprint_contract.mjs` était VERT sur ce blueprint : il vérifie la couverture,
les cycles et les contradictions de dépendances, JAMAIS les adresses. Le rouge ne
serait tombé qu'à s5 (`check_placement`), une étape plus loin.

CE QU'IL FAIT : confronte la section STRUCTURE d'un pré-run aux racines et au mapping
de `repo_map.yaml`. Rien d'autre.

CE QU'IL NE FAIT PAS, dit franchement : il ne juge NI la qualité du plan, NI la
pertinence du découpage, NI la faisabilité. Un pré-run vert n'est pas un bon plan —
c'est un plan qui ne viole aucune adresse connue. Aucun score, aucune pondération,
aucun LLM.

SOURCE DE VÉRITÉ : `forge/standard/repo_map.yaml`, lue à chaque appel. Aucune
table recopiée ici — recopier serait créer une seconde source qui dérive.

Usage :
  python -m forge.check_prerun <prerun.yaml|prerun.json> [--json]
Exit 0 = OK · 1 = FAIL · 2 = usage.

claim_posture: NO_CLAIM_ALLOWED
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import yaml

_ICI = Path(__file__).resolve().parent
REPO_MAP = _ICI / "standard" / "repo_map.yaml"

# Les 8 champs du format ratifié (Pierre, 2026-08-05). Un champ absent est un défaut
# de forme, pas une opinion : le pré-run existe pour rendre une intention lisible.
CHAMPS_REQUIS = (
    "MISSION", "INPUTS", "PLAN", "STRUCTURE",
    "DEPENDENCIES", "RISKS", "VALIDATION", "ESCALATION",
)


def charger_repo_map(chemin: Path | None = None) -> dict:
    return yaml.safe_load((chemin or REPO_MAP).read_text(encoding="utf-8"))


def racines_autorisees(repo_map: dict) -> list[str]:
    return [str(v).rstrip("/") for v in (repo_map.get("roots") or {}).values()]


def _racine_de(chemin: str) -> str:
    return str(chemin).replace("\\", "/").lstrip("/").split("/")[0]


def verifier(prerun: dict, repo_map: dict) -> dict:
    """Retourne {passed, champs_manquants[], racines_inconnues[], categories_inconnues[],
    adresses_incoherentes[], racines_vues[]}."""
    findings_champs = [c for c in CHAMPS_REQUIS if c not in prerun]

    racines_ok = racines_autorisees(repo_map)
    mapping = repo_map.get("mapping") or {}

    structure = prerun.get("STRUCTURE") or []
    if isinstance(structure, dict):          # tolère {path: category}
        structure = [{"path": k, "category": v} for k, v in structure.items()]

    racines_inconnues: list[dict] = []
    categories_inconnues: list[dict] = []
    adresses_incoherentes: list[dict] = []
    racines_vues: set[str] = set()

    for item in structure:
        if isinstance(item, str):
            item = {"path": item}
        chemin = str(item.get("path", "")).strip()
        if not chemin:
            continue
        racine = _racine_de(chemin)
        racines_vues.add(racine)

        if racine not in racines_ok:
            # Une racine inconnue est le défaut le plus coûteux : on nomme la
            # catégorie existante qui aurait pu convenir, quand il y en a une.
            racines_inconnues.append({
                "path": chemin,
                "racine": racine,
                "racines_autorisees": racines_ok,
            })

        cat = item.get("category")
        if cat is not None:
            if cat not in mapping:
                categories_inconnues.append({"path": chemin, "category": cat,
                                             "categories_connues": sorted(mapping)})
            else:
                gabarit = str(mapping[cat])
                prefixe = gabarit.split("{")[0].rstrip("/")
                if prefixe and not chemin.replace("\\", "/").startswith(prefixe):
                    adresses_incoherentes.append({
                        "path": chemin, "category": cat, "gabarit": gabarit,
                    })

    passed = not (findings_champs or racines_inconnues
                  or categories_inconnues or adresses_incoherentes)
    return {
        "passed": passed,
        "champs_manquants": findings_champs,
        "racines_inconnues": racines_inconnues,
        "categories_inconnues": categories_inconnues,
        "adresses_incoherentes": adresses_incoherentes,
        "racines_vues": sorted(racines_vues),
    }


def _charger(chemin: Path) -> dict:
    texte = chemin.read_text(encoding="utf-8")
    if chemin.suffix.lower() == ".json":
        return json.loads(texte)
    return yaml.safe_load(texte)


def main(argv: list[str]) -> int:
    args = [a for a in argv if a != "--json"]
    en_json = "--json" in argv
    if len(args) != 1:
        print("usage: python -m forge.check_prerun <prerun.yaml|prerun.json> [--json]",
              file=sys.stderr)
        return 2
    chemin = Path(args[0])
    if not chemin.exists():
        print(f"PRE-RUN introuvable : {chemin}", file=sys.stderr)
        return 2

    res = verifier(_charger(chemin), charger_repo_map())
    print(f"VERDICT PRE-RUN: {'OK' if res['passed'] else 'FAIL'}")
    if en_json:
        print(json.dumps(res, ensure_ascii=False, indent=1))
    else:
        for cle in ("champs_manquants", "racines_inconnues",
                    "categories_inconnues", "adresses_incoherentes"):
            for x in res[cle]:
                print(f"  {cle}: {x}")
    return 0 if res["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
