"""content_additive.py — ORACLE de la frontière contenu ↔ logique.

UNE question, mesurée sur le SOURCE : *ajouter une unité de contenu oblige-t-il à ouvrir
un fichier de logique ?* Si oui, la frontière contenu/cœur n'existe pas, quelle que soit
l'arborescence.

Généralisé depuis `GAMES/pacman/07_TESTS/oracle/v2_content_additive_third_map.gd`, qui
mesurait la propriété sur un seul jeu. L'oracle pacman n'est pas modifié : celui-ci porte
la MÊME propriété, rendue indépendante du jeu, et l'applique à tous les projets Godot.

POURQUOI UN ORACLE ARCHITECTURAL, ET PAS UN TEST DE COMPORTEMENT — mesure du 2026-09-09 :
pacman et bomberman_3d ont les mêmes dossiers (`05_SYSTEMS`, `06_RUNTIME/adapters/
content_provider`, `map_schema`, `map_validator`) et la propriété OPPOSÉE. Chez pacman
aucune carte n'est nommée hors `07_TESTS` ; chez bomberman les trois arènes sont en dur
dans `content_provider.gd:15-17`. Les dossiers ne constituent donc pas la frontière — les
invariants de dépendance la constituent, et seul un oracle exécuté les tient.

LIMITES, dites franchement :
  - ANALYSE STATIQUE. Ce module ne lance ni Godot ni le jeu : il mesure une propriété du
    source, jamais un comportement à l'exécution.
  - DÉTECTION PAR SOUS-CHAÎNE, comme l'oracle d'origine. Un identifiant de contenu court
    et générique produirait un faux positif ; les identifiants mesurés (`maze_classic`,
    `arena_couloirs`) n'en produisent aucun.
  - COMMENTAIRES RETIRÉS PAR RÈGLE NAÏVE (`code_seul`), reprise telle quelle de
    `harness_purity_counts.gd:53` : tout ce qui suit un `#` est coupé, y compris dans une
    chaîne. Fidélité volontaire — mesurer autrement ne mesurerait plus la même propriété.
  - Un projet SANS couche de contenu rend SANS_OBJET, jamais CONFORME : la propriété ne
    s'applique pas, et un vert y serait un faux vert.
  - P6 INFÈRE de la preuve la clé du catalogue qui porte l'identifiant de contenu (celle
    dont au moins une valeur nomme une unité réelle). Un catalogue ne déclarant QUE des
    unités inexistantes ne livre donc aucune clé — mais la propriété échoue quand même,
    par l'autre bout : aucune unité du disque n'y est déclarée.
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass, field
from pathlib import Path

from forge.verify_run import _harden_streams

# --- convention Studio2 (voir GAMES/<jeu>/) ------------------------------------------
RACINE_CONTENU = "03_WORLD/levels"
COUCHE_LOGIQUE = "05_SYSTEMS"
COUCHE_RUNTIME = "06_RUNTIME"
COUCHES_TEST = ("07_TESTS", "tests")

# Vocabulaire FERMÉ des verdicts.
CONFORME = "CONFORME"
NON_CONFORME = "NON_CONFORME"
SANS_OBJET = "SANS_OBJET"
VERDICTS = (CONFORME, NON_CONFORME, SANS_OBJET)


def code_seul(texte: str) -> str:
    """Retire les commentaires, ligne à ligne (règle naïve — voir docstring du module)."""
    return "\n".join(ligne.split("#", 1)[0] for ligne in texte.splitlines())


def _lire(chemin: Path) -> str:
    return chemin.read_text(encoding="utf-8", errors="replace")


def _fichiers_gd(racine: Path) -> list[Path]:
    return sorted(racine.rglob("*.gd")) if racine.is_dir() else []


def _est_test(chemin: Path, jeu: Path) -> bool:
    parties = chemin.relative_to(jeu).parts
    return bool(parties) and parties[0] in COUCHES_TEST


def _rel(chemin: Path, jeu: Path) -> str:
    return chemin.relative_to(jeu).as_posix()


@dataclass
class Constat:
    """Une propriété mesurée : son nom, si elle tient, et les FAITS qui la fondent.

    `fautifs` porte les fichiers nommés : un échec qui rend un booléen nu n'est pas
    diagnosticable, et un constat non diagnosticable finit par être ignoré.
    """

    nom: str
    tenue: bool
    detail: str
    fautifs: list[str] = field(default_factory=list)


@dataclass
class Rapport:
    jeu: str
    verdict: str
    unites: list[str] = field(default_factory=list)
    constats: list[Constat] = field(default_factory=list)
    motif: str = ""


def unites_de_contenu(jeu: Path) -> list[str]:
    """Identifiants de contenu = sous-dossiers de la racine de contenu, triés."""
    racine = jeu / RACINE_CONTENU
    if not racine.is_dir():
        return []
    return sorted(d.name for d in racine.iterdir() if d.is_dir())


def fournisseurs(jeu: Path) -> list[Path]:
    """Fichiers .gd HORS TESTS dont le code cite la racine de contenu.

    C'est la définition opératoire du « point de passage » : ce qui lit la donnée inerte.
    """
    trouves: list[Path] = []
    for f in _fichiers_gd(jeu):
        if _est_test(f, jeu):
            continue
        if RACINE_CONTENU in code_seul(_lire(f)):
            trouves.append(f)
    return trouves


def _cite(texte: str, unites: list[str]) -> list[str]:
    return [u for u in unites if u in texte]


def analyser(jeu: Path) -> Rapport:
    """Verdict d'un projet Godot. Le refus est une VALEUR DE RETOUR, jamais une exception."""
    unites = unites_de_contenu(jeu)
    if not unites:
        return Rapport(
            jeu=jeu.name,
            verdict=SANS_OBJET,
            motif=f"aucune couche de contenu ({RACINE_CONTENU} absent ou vide)",
        )

    rap = Rapport(jeu=jeu.name, verdict=CONFORME, unites=unites)
    prov = fournisseurs(jeu)

    # P1 — un SEUL point de passage entre la donnée inerte et le reste du jeu.
    rap.constats.append(Constat(
        nom="P1 point de passage unique",
        tenue=len(prov) == 1,
        detail=f"{len(prov)} fichier(s) de code lisent la racine de contenu",
        fautifs=[_rel(p, jeu) for p in prov],
    ))

    # P2 — le fournisseur ne NOMME aucune unité : c'est ce qui fait tomber à 0 le nombre
    # de fichiers de logique touchés par l'ajout d'une unité.
    p2: list[str] = []
    for p in prov:
        cites = _cite(code_seul(_lire(p)), unites)
        if cites:
            p2.append(f"{_rel(p, jeu)} cite {', '.join(cites)}")
    rap.constats.append(Constat(
        nom="P2 fournisseur ne nomme aucun contenu",
        tenue=not p2,
        detail="aucune unité citée" if not p2 else f"{len(p2)} fournisseur(s) citent du contenu",
        fautifs=p2,
    ))

    # P3 — aucun aiguillage par nom : un `match` sur un identifiant de contenu ramène
    # l'énumération en dur par une autre porte.
    p3 = [_rel(p, jeu) for p in prov if "match " in code_seul(_lire(p))]
    rap.constats.append(Constat(
        nom="P3 aucun aiguillage par nom",
        tenue=not p3,
        detail="aucun `match` dans le fournisseur" if not p3 else "aiguillage présent",
        fautifs=p3,
    ))

    # P4 / P5 — la logique pure, puis le runtime hors fournisseur, ne nomment rien.
    for nom, racine, exclus in (
        ("P4 logique pure ne nomme aucun contenu", jeu / COUCHE_LOGIQUE, set()),
        ("P5 runtime hors fournisseur ne nomme rien", jeu / COUCHE_RUNTIME, set(prov)),
    ):
        fautifs: list[str] = []
        for f in _fichiers_gd(racine):
            if f in exclus:
                continue
            cites = _cite(code_seul(_lire(f)), unites)
            if cites:
                fautifs.append(f"{_rel(f, jeu)} cite {', '.join(cites)}")
        rap.constats.append(Constat(
            nom=nom,
            tenue=not fautifs,
            detail=f"{racine.name} propre" if not fautifs else f"{len(fautifs)} fichier(s) fautifs",
            fautifs=fautifs,
        ))

    # P6 — INTÉGRITÉ RÉFÉRENTIELLE catalogue ↔ disque. « Data-driven » ne veut pas dire
    # « un fichier » : sans contrôle croisé, le fan-out entre manifestes dérive.
    declarees: list[str] = []
    lisible = False
    racine_monde = jeu / "03_WORLD"
    catalogues = [c for c in sorted(racine_monde.rglob("*.json"))
                  if c.parent.name not in unites] if racine_monde.is_dir() else []
    for c in catalogues:
        try:
            data = json.loads(_lire(c))
        except (json.JSONDecodeError, OSError):
            continue
        for valeur in (data.values() if isinstance(data, dict) else []):
            if not isinstance(valeur, list):
                continue
            entrees = [e for e in valeur if isinstance(e, dict)]
            # La CLÉ qui porte l'identifiant de contenu est INFÉRÉE de la preuve : c'est
            # celle dont au moins une valeur nomme une unité réelle. Sans cette étape on ne
            # collecterait que les valeurs déjà connues, et une unité déclarée mais ABSENTE
            # du disque resterait invisible — la branche « fantôme » serait inatteignable.
            cles = {k for e in entrees for k, v in e.items()
                    if isinstance(v, str) and v in unites}
            for e in entrees:
                for k in cles:
                    v = e.get(k)
                    if isinstance(v, str):
                        declarees.append(v)
                        lisible = True
    manquantes = [u for u in unites if u not in declarees]
    fantomes = [d for d in declarees if d not in unites]
    rap.constats.append(Constat(
        nom="P6 catalogue et disque s'accordent",
        tenue=lisible and not manquantes and not fantomes,
        detail=("aucun catalogue ne déclare les unités" if not lisible
                else f"{len(set(declarees))}/{len(unites)} unité(s) déclarée(s)"),
        fautifs=([f"non déclarée au catalogue : {u}" for u in manquantes]
                 + [f"déclarée mais absente du disque : {d}" for d in fantomes]),
    ))

    if any(not c.tenue for c in rap.constats):
        rap.verdict = NON_CONFORME
    return rap


def projets_godot(racine: Path) -> list[Path]:
    return sorted(p.parent for p in racine.glob("*/project.godot"))


def auditer(racine: Path) -> list[Rapport]:
    return [analyser(j) for j in projets_godot(racine)]


def _imprimer(rapports: list[Rapport]) -> None:
    largeur = max((len(r.jeu) for r in rapports), default=10)
    print(f"ORACLE CONTENT-ADDITIF — {len(rapports)} projet(s) Godot\n")
    for r in rapports:
        if r.verdict == SANS_OBJET:
            print(f"{r.jeu:<{largeur}}  {r.verdict:<13}  {r.motif}")
            continue
        tenues = sum(1 for c in r.constats if c.tenue)
        print(f"{r.jeu:<{largeur}}  {r.verdict:<13}  {tenues}/{len(r.constats)} propriétés "
              f"(contenu : {', '.join(r.unites)})")
        for c in r.constats:
            if c.tenue:
                continue
            print(f"    ÉCHEC {c.nom} — {c.detail}")
            for f in c.fautifs:
                print(f"          {f}")
    applicables = [r for r in rapports if r.verdict != SANS_OBJET]
    conformes = [r for r in applicables if r.verdict == CONFORME]
    print(f"\nBILAN : {len(conformes)} conforme(s) / {len(applicables)} applicable(s) / "
          f"{len(rapports) - len(applicables)} sans objet")


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="CLI forge.content_additive : mesure, sur le source, si ajouter une "
                    "unité de contenu oblige à ouvrir un fichier de logique.")
    parser.add_argument("racine", nargs="?", default="GAMES", type=Path,
                        help="dossier contenant les projets Godot (défaut : GAMES)")
    parser.add_argument("--json", action="store_true",
                        help="sortie machine au lieu du rapport lisible")
    return parser


def main(argv: "list[str] | None" = None) -> int:
    """Contrat des CLI forge : `_harden_streams()` en premier, jamais de trace nue,
    toujours un int. 0 si tout applicable est conforme, 1 sinon, 2 si rien à mesurer."""
    _harden_streams()
    args = _build_parser().parse_args(argv)
    racine = Path(args.racine)
    rapports = auditer(racine)
    if not rapports:
        print(f"aucun projet Godot sous {racine}")
        return 2

    if args.json:
        print(json.dumps({
            "racine": racine.as_posix(),
            "projets": [{
                "jeu": r.jeu, "verdict": r.verdict, "unites": r.unites, "motif": r.motif,
                "constats": [{"nom": c.nom, "tenue": c.tenue, "detail": c.detail,
                              "fautifs": c.fautifs} for c in r.constats],
            } for r in rapports],
        }, ensure_ascii=False, indent=2))
    else:
        _imprimer(rapports)

    applicables = [r for r in rapports if r.verdict != SANS_OBJET]
    return 0 if all(r.verdict == CONFORME for r in applicables) else 1


if __name__ == "__main__":
    raise SystemExit(main())
