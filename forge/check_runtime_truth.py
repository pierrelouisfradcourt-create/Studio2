#!/usr/bin/env python
"""check_runtime_truth.py — RUNTIME TRUTH ORACLE (chantier 2, gate Pierre 2026-08-06).

LOI APPLIQUEE, ratifiee ce jour :

    « Une capacite declaree n'existe que si son DERNIER MAILLON OBSERVABLE est prouve. »

    synthese != emission · present != utilise · Etat existe != joueur voit

POURQUOI CE FICHIER EXISTE — cout mesure, pas hypothese.
Run pacman V3 : `godot_oracle` VERT a 2389 assertions, mutation settings a 1.0, et
AUCUN son ne sortait du jeu. `audio.jouer()` et `audio.jouer_musique()` synthetisaient
un buffer, l'ajoutaient a `_journal`, et retournaient. Le test `v3_p3_music_track`
PASSAIT en lisant ce journal : il mesurait la SYNTHESE, jamais l'EMISSION. Signature
mesurable du defaut : `push_frame`, `AudioStreamPlayer` et `get_stream_playback`
n'apparaissaient QUE dans 2 fichiers de test, jamais dans le runtime. Detecte par
playtest humain, apres 3 runs verts.

CE QU'IL FAIT : pour chaque domaine DECLARE par le jeu, verifie que le maillon de
plateforme qui le rend observable est appele depuis le CODE DE PRODUCTION, et pas
seulement depuis les tests. C'est un grep INVERSE, deterministe, sans LLM.

CE QU'IL NE FAIT PAS, dit franchement :
  * il ne prouve PAS que le son est entendu, ni que l'image est belle — il prouve que
    le chemin existe. La perception reste un HUMAN_PERCEPTION_PROOF (chantier 1) ;
  * il ne suit pas les appels dynamiques (`call("push_frame")`) — un jeu qui voudrait
    le tromper le pourrait. Ce n'est pas un garde anti-fraude, c'est un garde
    anti-OUBLI, et c'est l'oubli qui a coute 3 runs ;
  * il ne connait que les domaines de sa table figee ci-dessous. Un domaine absent de
    la table n'est PAS verifie — et il le DIT (`domaines_non_couverts`), jamais un
    vert silencieux.

Usage :
  python -m forge.check_runtime_truth <GAMES/xxx> [--json]
Exit 0 = OK · 1 = FAIL · 2 = usage.

claim_posture: NO_CLAIM_ALLOWED
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

# Dossiers de PREUVE : leur contenu ne compte jamais comme du code de production.
DOSSIERS_TEST = ("07_TESTS", "tests")

# --- TABLE FIGEE des derniers maillons ------------------------------------------
# Meme statut que `mutation.RULES` ou les constantes `_GODOT_*` de static_oracles :
# c'est la table de regles de CET oracle, pas un registre studio (aucun 8e registre).
#
# `declare_par` : ce qui prouve que le jeu PRETEND offrir la capacite.
# `dernier_maillon` : le mecanisme de plateforme sans lequel rien n'atteint le joueur.
MAILLONS: dict[str, dict] = {
    "audio": {
        "declare_par": ("AudioStreamGenerator", "jouer_musique", "sound_bank"),
        "dernier_maillon": ("push_frame",),
        "pourquoi": "synthetiser un buffer ne le fait pas entendre : il faut le pousser "
                    "dans un playback reel (defaut mesure pacman V3)",
    },
    "render": {
        "declare_par": ("CanvasItem", "maze_view", "_draw"),
        "dernier_maillon": ("draw_rect", "draw_circle", "draw_line", "draw_string"),
        "pourquoi": "calculer une geometrie ne l'affiche pas : il faut une primitive de "
                    "dessin reellement appelee",
    },
    "input": {
        "declare_par": ("input_adapter", "input_bindings", "Intention"),
        "dernier_maillon": ("_input", "_unhandled_input", "_process"),
        "pourquoi": "declarer une liaison ne la rend pas jouable : il faut un rappel "
                    "d'entree du moteur",
    },
}


def _fichiers(racine: Path) -> tuple[list[Path], list[Path]]:
    """(code de production, fichiers de preuve). Un dossier de test n'est jamais
    du code de production, quelle que soit sa profondeur."""
    prod: list[Path] = []
    test: list[Path] = []
    for f in sorted(racine.rglob("*.gd")):
        parts = set(f.relative_to(racine).parts)
        (test if parts & set(DOSSIERS_TEST) else prod).append(f)
    return prod, test


def _cherche(motifs: tuple[str, ...], fichiers: list[Path]) -> list[str]:
    """Chemins (relatifs, '/' normalise) contenant au moins un motif."""
    trouves: list[str] = []
    for f in fichiers:
        try:
            texte = f.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if any(m in texte for m in motifs):
            trouves.append(f.as_posix())
    return trouves


def verifier(racine: Path, maillons: dict | None = None) -> dict:
    """Retourne {passed, ruptures[], domaines_verifies[], domaines_non_declares[],
    domaines_non_couverts}."""
    table = maillons if maillons is not None else MAILLONS
    prod, test = _fichiers(Path(racine))

    ruptures: list[dict] = []
    verifies: list[str] = []
    non_declares: list[str] = []

    for domaine, regle in table.items():
        declare_prod = _cherche(regle["declare_par"], prod)
        if not declare_prod:
            non_declares.append(domaine)      # le jeu ne pretend pas l'offrir
            continue
        verifies.append(domaine)
        maillon_prod = _cherche(regle["dernier_maillon"], prod)
        if maillon_prod:
            continue
        maillon_test = _cherche(regle["dernier_maillon"], test)
        ruptures.append({
            "domaine": domaine,
            "declare_par": declare_prod[:4],
            "dernier_maillon": list(regle["dernier_maillon"]),
            "present_dans_le_runtime": False,
            "present_dans_les_tests": maillon_test[:4],
            "pourquoi": regle["pourquoi"],
            "lecture": ("le mecanisme n'existe QUE dans les fichiers de preuve"
                        if maillon_test else
                        "le mecanisme n'existe NULLE PART"),
        })

    return {
        "passed": not ruptures,
        "ruptures": ruptures,
        "domaines_verifies": sorted(verifies),
        "domaines_non_declares": sorted(non_declares),
        "domaines_non_couverts": ("cet oracle ne connait que "
                                  f"{sorted(table)} — tout autre domaine n'est PAS verifie"),
    }


def main(argv: list[str]) -> int:
    args = [a for a in argv if a != "--json"]
    en_json = "--json" in argv
    if len(args) != 1:
        print("usage: python -m forge.check_runtime_truth <GAMES/xxx> [--json]", file=sys.stderr)
        return 2
    racine = Path(args[0])
    if not racine.is_dir():
        print(f"dossier introuvable : {racine}", file=sys.stderr)
        return 2

    res = verifier(racine)
    print(f"VERDICT RUNTIME TRUTH: {'OK' if res['passed'] else 'FAIL'}")
    if en_json:
        print(json.dumps(res, ensure_ascii=False, indent=1))
    else:
        for r in res["ruptures"]:
            print(f"  RUPTURE {r['domaine']}: {r['lecture']}")
            print(f"     dernier maillon attendu : {r['dernier_maillon']}")
            print(f"     declare par             : {r['declare_par']}")
            if r["present_dans_les_tests"]:
                print(f"     present SEULEMENT dans  : {r['present_dans_les_tests']}")
            print(f"     pourquoi                : {r['pourquoi']}")
        print(f"  domaines verifies    : {res['domaines_verifies']}")
        print(f"  domaines non declares: {res['domaines_non_declares']}")
    return 0 if res["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
