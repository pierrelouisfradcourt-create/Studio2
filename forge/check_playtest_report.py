#!/usr/bin/env python
"""check_playtest_report.py — HUMAN PLAYTEST LINEAGE (chantier 1, gate Pierre 2026-08-06).

POURQUOI CE FICHIER EXISTE — cout mesure sur 3 runs.
V2, V3 et V4 de pacman ont tous rendu un oracle VERT (1012, puis 2212, puis 2389
assertions) pendant que le playtest humain trouvait 10 defauts reels : aucun son, ecran
de fin illisible, touches en keycode brut, carte 2 rendue plus petite, fin de catalogue
sans sortie, comportement des fantomes non transmis, progression inconnue, placeholders
visuels, pas de reglage de volume, pas de musique. Ces retours vivaient dans une
CONVERSATION. Ils n'etaient ni traces, ni comptables, ni relisibles par un run suivant.

CE QU'IL FAIT : valide la forme d'un PLAYTEST_REPORT pour qu'un retour humain devienne
une preuve TRACEE, au meme titre qu'un recu d'oracle.

SEPARATION EXPLICITE, ratifiee ce jour :

    MECHANICAL_PROOF          !=          HUMAN_PERCEPTION_PROOF

Ce fichier ne touche PAS `upstream_schema.PROOF_KINDS` — le vocabulaire ferme
(`bot_action|oracle|mutation|visual|file_write`) reste inchange. Ouvrir ce vocabulaire
serait une modification d'un artefact partage ; on cree ici un CANAL SEPARE, ce qui
n'ajoute aucune valeur a une enumeration existante.

CE QU'IL NE FAIT PAS, dit franchement : il ne juge NI la verite NI l'importance d'un
retour. Un humain peut se tromper. Cet oracle verifie qu'un retour est EXPLOITABLE
(attribue, situe, falsifiable), jamais qu'il a raison.

Usage :
  python -m forge.check_playtest_report <playtest_report.json> [--json]
Exit 0 = OK · 1 = FAIL · 2 = usage.

claim_posture: NO_CLAIM_ALLOWED
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

# Vocabulaire FERME des categories (spec Pierre 2026-08-06). Une categorie hors liste
# est un finding, jamais un vert silencieux — meme discipline que PROOF_KINDS.
CATEGORIES = (
    "AUDIO_PERCEPTION",
    "VISUAL_DIRECTION",
    "UX",
    "GAME_FEEL",
    "BALANCE",
    "CONFUSION_PLAYER",
)

# Confiance declaree par l'observateur. « je crois » et « j'ai verifie » ne sont pas
# la meme preuve, et un run aval doit pouvoir les distinguer.
CONFIANCES = ("CERTAIN", "PROBABLE", "IMPRESSION")

CHAMPS = ("symptom", "observed_by", "expected", "actual", "confidence", "category")


def _non_vide(v) -> bool:
    return isinstance(v, str) and bool(v.strip())


def valider_entree(e, i: int) -> list[str]:
    loc = f"entries[{i}]"
    if not isinstance(e, dict):
        return [f"{loc}: doit etre un objet {{{', '.join(CHAMPS)}}}"]
    f: list[str] = []
    for champ in CHAMPS:
        if champ not in e:
            f.append(f"{loc}.{champ}: absent")
        elif not _non_vide(e[champ]):
            f.append(f"{loc}.{champ}: vide")
    if e.get("category") not in CATEGORIES and "category" in e:
        f.append(f"{loc}.category: invalide (attendu: {'|'.join(CATEGORIES)})")
    if e.get("confidence") not in CONFIANCES and "confidence" in e:
        f.append(f"{loc}.confidence: invalide (attendu: {'|'.join(CONFIANCES)})")
    # expected != actual : sinon le retour ne decrit aucun ecart, donc rien a corriger.
    if _non_vide(e.get("expected")) and _non_vide(e.get("actual")):
        if e["expected"].strip().lower() == e["actual"].strip().lower():
            f.append(f"{loc}: `expected` et `actual` identiques — aucun ecart decrit")
    return f


def valider(doc) -> dict:
    """Retourne {passed, problems[], stats{}}."""
    if not isinstance(doc, dict):
        return {"passed": False, "problems": ["le rapport doit etre un objet {game, entries}"],
                "stats": {}}
    problems: list[str] = []
    if not _non_vide(doc.get("game")):
        problems.append("game: absent ou vide")
    entries = doc.get("entries")
    if not isinstance(entries, list) or not entries:
        problems.append("entries: doit etre un tableau NON VIDE "
                        "(un rapport sans retour n'est pas un rapport)")
        return {"passed": False, "problems": problems, "stats": {}}
    for i, e in enumerate(entries):
        problems.extend(valider_entree(e, i))

    par_cat: dict[str, int] = {}
    par_conf: dict[str, int] = {}
    for e in entries:
        if isinstance(e, dict):
            par_cat[str(e.get("category"))] = par_cat.get(str(e.get("category")), 0) + 1
            par_conf[str(e.get("confidence"))] = par_conf.get(str(e.get("confidence")), 0) + 1
    return {
        "passed": not problems,
        "problems": problems,
        "stats": {"entries": len(entries), "par_categorie": par_cat, "par_confiance": par_conf,
                  "proof_kind": "HUMAN_PERCEPTION_PROOF"},
    }


def main(argv: list[str]) -> int:
    args = [a for a in argv if a != "--json"]
    en_json = "--json" in argv
    if len(args) != 1:
        print("usage: python -m forge.check_playtest_report <rapport.json> [--json]",
              file=sys.stderr)
        return 2
    p = Path(args[0])
    if not p.exists():
        print(f"rapport introuvable : {p}", file=sys.stderr)
        return 2
    res = valider(json.loads(p.read_text(encoding="utf-8")))
    print(f"VERDICT PLAYTEST: {'OK' if res['passed'] else 'FAIL'}")
    if en_json:
        print(json.dumps(res, ensure_ascii=False, indent=1))
    else:
        for x in res["problems"]:
            print("  ", x)
        if res["stats"]:
            print("  stats:", json.dumps(res["stats"], ensure_ascii=False))
    return 0 if res["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
