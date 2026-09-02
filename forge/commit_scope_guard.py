#!/usr/bin/env python
"""commit_scope_guard.py — l'index correspond-il au perimetre annonce ?

NE PAS LIRE COMME UNE PRECAUTION THEORIQUE. Le 2026-08-06, un `git add` multi-chemins a
echoue sur un chemin ignore ; l'index s'est retrouve avec 382 fichiers (tout un chantier
voisin + studio_brain) au lieu du perimetre voulu, et un commit concurrent l'a emporte.
Le travail etait intact, mais l'historique du depot annoncait un contenu qu'il n'avait
pas. Aucun mecanisme ne comparait l'INTENTION du commit a son CONTENU reel.

Ce module compare `git diff --cached --name-only` a un perimetre DECLARE. Il ne commite
rien, ne stage rien, ne desindexe rien : il rend un verdict.

    perimetre attendu  +  git diff --cached  ->  commit autorise / refuse

Trois regles :
  1. un fichier indexe HORS perimetre  -> REFUSE (c'est la panne observee) ;
  2. un index VIDE                     -> REFUSE (un commit vide n'a pas de perimetre) ;
  3. un perimetre inconnu              -> REFUSE (jamais un perimetre devine).

Ce qu'il ne fait PAS : verifier que le message de commit decrit le contenu. Un scope
correct avec un message trompeur passe — la garde ferme le contenu, pas la prose.

Usage :
  python -m scripts.forge.commit_scope_guard --scope asset_library
  python -m scripts.forge.commit_scope_guard --allow forge/ --allow docs/forge/
  python -m scripts.forge.commit_scope_guard --list
Exit 0 = index conforme · 1 = index hors perimetre ou vide · 2 = usage/erreur.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SCOPES_PATH = Path(__file__).with_name("commit_scopes.json")


def load_scopes() -> dict[str, list[str]]:
    if not SCOPES_PATH.is_file():
        return {}
    data = json.loads(SCOPES_PATH.read_text(encoding="utf-8"))
    return data.get("scopes", {})


def staged_files() -> list[str]:
    """Fichiers REELLEMENT indexes. Source unique du jugement."""
    r = subprocess.run(["git", "diff", "--cached", "--name-only"],
                       cwd=str(REPO), capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    if r.returncode != 0:
        raise SystemExit(f"git indisponible : {(r.stderr or '').strip()}")
    return [l.strip().replace("\\", "/") for l in (r.stdout or "").splitlines() if l.strip()]


def check(files: list[str], allowed: list[str]) -> tuple[bool, list[str]]:
    """(conforme, hors_perimetre). Un prefixe vaut pour tout ce qu'il contient."""
    prefixes = [p.rstrip("/").replace("\\", "/") for p in allowed]
    dehors = [f for f in files
              if not any(f == p or f.startswith(p + "/") for p in prefixes)]
    return (not dehors, dehors)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--scope", default=None, help="nom d'un perimetre declare")
    ap.add_argument("--allow", action="append", default=[],
                    help="prefixe autorise (repetable) — s'ajoute a --scope")
    ap.add_argument("--list", action="store_true", help="liste les perimetres declares")
    ns = ap.parse_args(argv)

    scopes = load_scopes()

    if ns.list:
        if not scopes:
            print(f"aucun perimetre declare ({SCOPES_PATH.name} absent)")
        for nom, prefixes in scopes.items():
            print(f"{nom} :")
            for p in prefixes:
                print(f"    {p}")
        return 0

    allowed = list(ns.allow)
    if ns.scope:
        if ns.scope not in scopes:
            print(f"perimetre inconnu : {ns.scope!r} (declares : "
                  f"{sorted(scopes) or 'aucun'})", file=sys.stderr)
            return 2
        allowed += scopes[ns.scope]

    if not allowed:
        print("aucun perimetre fourni : utiliser --scope ou --allow. "
              "Un perimetre n'est jamais devine.", file=sys.stderr)
        return 2

    fichiers = staged_files()
    if not fichiers:
        print("REFUSE : index VIDE — un commit sans contenu n'a pas de perimetre.",
              file=sys.stderr)
        return 1

    conforme, dehors = check(fichiers, allowed)

    print(f"perimetre  : {ns.scope or '(--allow)'}  ({len(allowed)} prefixe(s))")
    print(f"indexes    : {len(fichiers)} fichier(s)")

    if conforme:
        print("VERDICT    : OK — l'index correspond au perimetre annonce")
        return 0

    print(f"VERDICT    : REFUSE — {len(dehors)} fichier(s) HORS perimetre", file=sys.stderr)
    for f in dehors[:20]:
        print(f"   hors perimetre : {f}", file=sys.stderr)
    if len(dehors) > 20:
        print(f"   ... et {len(dehors) - 20} autre(s)", file=sys.stderr)
    print("\nDesindexer avant de commiter : git restore --staged <fichier>", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
