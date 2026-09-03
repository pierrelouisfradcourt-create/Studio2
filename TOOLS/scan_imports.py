"""Détecteur de dépendances SORTANTES du Studio V2 — par IMPORT, pas par chemin.

POURQUOI CE MODULE EXISTE (défaut réel, RUN M, 2026-09-02) :
`scripts/council.py` avait été classé « hors périmètre V2 » sur la foi d'un balayage de
CHEMINS (`scripts/...`). Or `forge/runtime.py` l'appelle par un IMPORT NU :

    from council import QwenAdapter          # aucun chemin, invisible à un grep de chemins

Le run s'est arrêté à s6 sur `ModuleNotFoundError: No module named 'council'`.
C'est R8 appliqué à l'outillage : **un consommateur ne se trouve pas à la forme du nom**.

DEUX AGGRAVANTS, et ils dictent la forme du scan :

1. **L'import est PARESSEUX** — il vit dans le corps d'une fonction, pas en tête de module.
   Un contrôle « le paquet s'importe-t-il ? » (50/50 modules verts) ne le voit PAS : il ne
   casse qu'à l'appel. Ce scan lit donc l'AST **à toute profondeur**, jamais seulement le
   module level.

2. **L'échec est AVALÉ** — `qwen_available()` capture l'exception et rend False, puis la
   chaîne dégrade son runner en journalisant un motif FAUX (« :1234 down »). Un test
   d'exécution ne révèle donc rien ; seule une analyse STATIQUE le montre.

Ne modifie rien. Rend un compte-rendu, et un code de sortie non nul s'il reste une
dépendance sortante non déclarée.
"""
from __future__ import annotations

import ast
import importlib.util
import json
import sys
import sysconfig
from pathlib import Path

V2 = Path(__file__).resolve().parents[1]
PAQUETS = ("forge", "control_plane")

# Dépendances sortantes CONNUES et assumées : elles ne sont pas des défauts, mais elles
# doivent rester NOMMÉES — un motif ne dit pas qui il protège.
ATTENDUES: dict[str, str] = {
    "yaml": "PyYAML — dépendance tierce, présente dans le venv",
    "requests": "HTTP tiers — utilisé par les adaptateurs de runtime",
    "pytest": "harnais de test",
}


def _stdlib() -> set[str]:
    noms = set(sys.stdlib_module_names)  # py3.10+
    noms.discard("test")
    return noms


def _modules_locaux() -> set[str]:
    """Ce que V2 fournit lui-même : paquets et modules de premier niveau à la racine."""
    locaux = set()
    for p in V2.iterdir():
        if p.is_dir() and (p / "__init__.py").exists():
            locaux.add(p.name)
        elif p.suffix == ".py":
            locaux.add(p.stem)
    return locaux


def _installe(nom: str) -> bool:
    try:
        return importlib.util.find_spec(nom) is not None
    except (ImportError, ValueError, ModuleNotFoundError):
        return False


def _resoluble_sous_harnais(nom: str, importeur: Path) -> bool:
    """Le module est-il resoluble dans le contexte REEL de l'import, et non dans le mien ?

    CORRECTION 2026-09-02 (faux positif `conftest`, releve par Pierre) : `find_spec` interroge
    le `sys.path` du SCANNER. Or pytest insere le repertoire du test dans `sys.path` avant de
    l'executer : `import conftest` s'y resout parfaitement. Poser la question depuis le mauvais
    contexte rendait un faux positif credible -- meme famille d'erreur que d'interroger le depot
    V2 pour un objet de V1.

    Regle : un module dont le `.py` existe A COTE du fichier qui l'importe est resoluble dans le
    contexte de cet import. Ce n'est pas une dependance sortante.
    """
    return (importeur.parent / f"{nom}.py").is_file()


def imports_du_fichier(chemin: Path) -> list[tuple[str, int, bool, str]]:
    """(module_racine, ligne, paresseux, forme) pour CHAQUE import, à toute profondeur.

    `paresseux` = l'import vit dans le corps d'une fonction/méthode. C'est la classe
    dangereuse : elle ne casse pas à l'import du paquet, seulement à l'appel.
    """
    try:
        arbre = ast.parse(chemin.read_text(encoding="utf-8", errors="surrogateescape"))
    except SyntaxError:
        return []

    profondeur_fonction: dict[int, bool] = {}

    def marquer(noeud: ast.AST, dans_fonction: bool) -> None:
        for enfant in ast.iter_child_nodes(noeud):
            interne = dans_fonction or isinstance(
                enfant, (ast.FunctionDef, ast.AsyncFunctionDef))
            if isinstance(enfant, (ast.Import, ast.ImportFrom)):
                profondeur_fonction[id(enfant)] = dans_fonction
            marquer(enfant, interne)

    marquer(arbre, False)

    trouves: list[tuple[str, int, bool, str]] = []
    for noeud in ast.walk(arbre):
        paresseux = profondeur_fonction.get(id(noeud), False)
        if isinstance(noeud, ast.Import):
            for alias in noeud.names:
                trouves.append((alias.name.split(".")[0], noeud.lineno, paresseux,
                                f"import {alias.name}"))
        elif isinstance(noeud, ast.ImportFrom):
            if noeud.level:            # import relatif : reste dans le paquet
                continue
            if noeud.module:
                cibles = ", ".join(a.name for a in noeud.names)
                trouves.append((noeud.module.split(".")[0], noeud.lineno, paresseux,
                                f"from {noeud.module} import {cibles}"))
    return trouves


def scanner() -> dict:
    stdlib, locaux = _stdlib(), _modules_locaux()
    sortantes: list[dict] = []
    harnais: list[dict] = []
    attendues_vues: set[str] = set()
    fichiers = 0

    for paquet in PAQUETS:
        racine = V2 / paquet
        if not racine.is_dir():
            continue
        for f in sorted(racine.rglob("*.py")):
            if "__pycache__" in str(f):
                continue
            fichiers += 1
            for module, ligne, paresseux, forme in imports_du_fichier(f):
                if module in stdlib or module in locaux:
                    continue
                if module in ATTENDUES:
                    attendues_vues.add(module)
                    continue
                if _resoluble_sous_harnais(module, f):
                    harnais.append({"module": module,
                                    "fichier": f.relative_to(V2).as_posix(), "ligne": ligne})
                    continue
                sortantes.append({
                    "module": module,
                    "fichier": f.relative_to(V2).as_posix(),
                    "ligne": ligne,
                    "paresseux": paresseux,
                    "forme": forme,
                    "resoluble": _installe(module),
                })
    return {"fichiers": fichiers, "sortantes": sortantes, "harnais": harnais,
            "attendues_vues": sorted(attendues_vues)}


def rapport(res: dict) -> int:
    print("=" * 78)
    print("DÉPENDANCES SORTANTES — détection par IMPORT (AST), pas par chemin")
    print("=" * 78)
    print(f"  fichiers .py analysés : {res['fichiers']}")
    print(f"  dépendances tierces attendues et vues : {', '.join(res['attendues_vues']) or '—'}")
    if res.get("harnais"):
        noms = sorted({h["module"] for h in res["harnais"]})
        print(f"  TEST-ONLY (résolubles sous le harnais, hors périmètre Studio) : {', '.join(noms)}")

    casse = [s for s in res["sortantes"] if not s["resoluble"]]
    autres = [s for s in res["sortantes"] if s["resoluble"]]

    print(f"\n  IMPORTS NON RÉSOLUBLES DEPUIS V2 : {len(casse)}")
    for s in sorted(casse, key=lambda x: (x["module"], x["fichier"])):
        marque = "PARESSEUX" if s["paresseux"] else "module-level"
        print(f"    X  {s['module']:<16} {s['fichier']}:{s['ligne']:<5} [{marque}]")
        print(f"        {s['forme']}")
        if s["paresseux"]:
            print("        ! n'echoue PAS à l'import du paquet — seulement à l'appel")

    if autres:
        print(f"\n  tiers résolubles non déclarés dans ATTENDUES : {len(autres)}")
        for s in sorted({(x['module'], x['fichier']) for x in autres}):
            print(f"    -  {s[0]:<16} {s[1]}")

    print("\n" + "-" * 78)
    print(f"  VERDICT : {'FAIL — dépendance sortante non résoluble' if casse else 'OK — aucune dépendance sortante non résoluble'}")
    return 1 if casse else 0


if __name__ == "__main__":
    res = scanner()
    if "--json" in sys.argv:
        print(json.dumps(res, ensure_ascii=False, indent=2))
        sys.exit(1 if any(not s["resoluble"] for s in res["sortantes"]) else 0)
    sys.exit(rapport(res))
