# -*- coding: utf-8 -*-
"""RUN_IDENTITY_V1 — les quatre dimensions d'un run, chacune avec UNE sémantique.

NOT_WIRED — voir la section « État de câblage » plus bas. Ce module publie un contrat ;
aucun producteur ne l'applique encore. C'est délibéré et daté.

LE DÉFAUT QU'IL FERME. Un seul champ, `project`, portait quatre sens à la fois : nom de jeu
(`tetris`), identifiant d'exécution (`shmup_slice_patch2`), portée (`driver_smoke`), nature
(`story_probe`). Rien ne permettait de savoir lequel était voulu, et les consommateurs
devaient deviner d'après la FORME DU NOM — raisonnement qui a produit au moins une erreur
documentée (`probe2` pris pour légitime, `proj` pour parasite : c'était l'inverse).

    project = "shmup_slice_patch2"
        |
        +-- projet ?   non : le projet est `shmup_slice`
        +-- run ?      oui, c'est un RUN SUR ce projet
        +-- portée ?   PRODUCT, mais rien ne le dit
        +-- nature ?   un patch, mais rien ne le dit

MESURES QUI FONDENT CHAQUE DIMENSION (149 identifiants / 5179 enregistrements de
`EVIDENCE/bundles/*.jsonl`, 78 run_dirs, 28 projets observés, le 2026-08-19) :

  `project_id` ≠ `run_id`   `shmup_slice_patch2` déclare `is_game=True` sans être dans
                            `GAMES/` : c'est un run sur `shmup_slice`.
  `run_id` requis           27 % des enregistrements SIGNÉS n'ont aucun `run_id`, et
                            `_belongs_to_project` rend False sur vide — ils sont invisibles
                            à TOUS les rapports Observer. Rupture de traçabilité.
  `scope`                   le résidu inclassable contenait une nature entière : les runs
                            sur l'USINE (`driver_smoke`, `p1-injection`, `charte2`,
                            `amont-narratif`). PRODUCT | FACTORY est le socle DÉJÀ ratifié
                            (deux registres de capacités), appliqué ici aux runs.
  `mode`                    `dryrun` a failli entrer comme nature. C'est un MODE : un run
                            réel sans effet reste un run réel. `audit._is_dryrun` le traite
                            déjà comme une annotation, jamais comme une catégorie.
  `nature`                  OUVERTE. L'hypothèse `real|fixture|selftest|probe` couvrait 57 %
                            des enregistrements et laissait 71 identifiants sur 149 hors
                            classement : FALSIFIÉE avant d'être écrite.

RÈGLE CARDINALE (ratifiée Pierre 2026-08-19) :

    Une dimension inconnue reste EXPLICITEMENT inconnue. Elle n'est JAMAIS remplacée par une
    valeur inventée pour satisfaire un schéma.

D'où la distinction que ce module tient plus strictement qu'un schéma JSON ne le ferait :
`nature` ABSENTE devient `UNKNOWN` ; `nature` VIDE est REFUSÉE. Absent = « je n'ai pas cette
dimension ». Vide = une ignorance DÉGUISÉE en valeur, donc indétectable ensuite — exactement
le trou que `run_id` a creusé sur 27 % du flux.

CE MODULE NE JUGE PAS `project_id` CONTRE UNE LISTE, et ne doit jamais le faire. Mesure :
les deux sources canoniques candidates (`GAMES/`, `oracles.json`) rejettent 21 des 28 projets
réellement observés, dont `_selftest` — l'auto-test de l'Observer. Une appartenance ne
s'invente pas avant d'avoir mesuré sa population réelle.

ÉTAT DE CÂBLAGE — NOT_WIRED, délibérément (2026-08-19)
    Aucun producteur n'applique encore ce contrat. Le brancher sur
    `audit.append_spawn_event` demanderait une décision distincte : cette fonction est
    BEST-EFFORT ABSOLU par contrat (« ne lève JAMAIS », car une preuve d'audit ne doit jamais
    casser un run). Y faire lever `validate_run_identity` renverserait ce contrat-là. C'est
    pourquoi `check_run_identity` existe : une lecture qui RAPPORTE au lieu de casser, prête
    pour ce câblage sans le préjuger.
"""
from __future__ import annotations

from typing import Any

#: Portée du run — ratifiée Pierre 2026-08-19. Deux valeurs, pas une de plus : le studio
#: sépare déjà `capabilities.yaml` (produit) de `factory_capabilities.yaml` (usine). Cette
#: dimension applique aux RUNS une séparation qui existait déjà pour les CAPACITÉS.
SCOPES: tuple[str, ...] = ("PRODUCT", "FACTORY")

#: Mode d'exécution — ORTHOGONAL à la nature. `dryrun` est attesté (445 enregistrements,
#: prédicat `audit._is_dryrun`) ; `live` en est le complément exact. Aucune troisième valeur
#: n'a été observée, donc aucune n'est proposée.
MODES: tuple[str, ...] = ("live", "dryrun")

#: Valeur EXPLICITE d'une nature non déterminée. Il n'existe volontairement PAS de constante
#: `NATURES` : figer ce vocabulaire aujourd'hui reproduirait une hypothèse déjà falsifiée.
NATURE_UNKNOWN = "UNKNOWN"

_REQUIS: tuple[str, ...] = ("project_id", "run_id", "scope", "mode")


class RunIdentityViolation(ValueError):
    """Levée quand une identité de run ne satisfait pas RUN_IDENTITY_V1.

    Porte TOUTES les causes d'un coup, jamais la première seule : un appelant qui corrige un
    champ à la fois relance autant de fois qu'il a d'erreurs, et l'information était déjà
    disponible dès le premier passage.
    """


def _texte_utile(valeur: Any) -> str | None:
    """Chaîne non vide après strip, sinon None. `None`, `""` et `"   "` sont le MÊME cas :
    un champ présent qui ne porte aucune information."""
    if not isinstance(valeur, str):
        return None
    net = valeur.strip()
    return net or None


def check_run_identity(identite: Any) -> dict:
    """Rapport de conformité — NE LÈVE JAMAIS.

    Destinée aux chemins best-effort (audit, télémétrie) où une identité non conforme doit
    DÉGRADER la preuve, jamais casser l'appelant. Rend
    ``{"conforme": bool, "violations": [str, ...], "identite": dict | None}``.
    """
    violations: list[str] = []
    if not isinstance(identite, dict):
        return {"conforme": False, "identite": None,
                "violations": [f"identite: attendu un mapping, recu {type(identite).__name__}"]}

    normalise: dict[str, str] = {}
    for champ in _REQUIS:
        valeur = _texte_utile(identite.get(champ))
        if valeur is None:
            violations.append(f"{champ}: requis, absent ou vide")
        else:
            normalise[champ] = valeur

    if "scope" in normalise and normalise["scope"] not in SCOPES:
        violations.append(f"scope: {normalise['scope']!r} hors vocabulaire {SCOPES}")
    if "mode" in normalise and normalise["mode"] not in MODES:
        violations.append(
            f"mode: {normalise['mode']!r} hors vocabulaire {MODES} — une NATURE presumee "
            f"(`fixture`, `audit`) ne passe pas par ce champ")

    # `nature` : ABSENTE -> UNKNOWN explicite. PRESENTE MAIS VIDE -> refusee. La difference
    # est toute la regle cardinale : on ne convertit pas une ignorance deguisee en valeur.
    if "nature" not in identite:
        normalise["nature"] = NATURE_UNKNOWN
    else:
        nature = _texte_utile(identite.get("nature"))
        if nature is None:
            violations.append(
                f"nature: presente mais vide — utiliser {NATURE_UNKNOWN!r} explicitement, "
                f"ou omettre le champ")
        else:
            normalise["nature"] = nature

    if violations:
        return {"conforme": False, "identite": None, "violations": violations}
    return {"conforme": True, "identite": normalise, "violations": []}


def validate_run_identity(identite: Any) -> dict:
    """Identité normalisée, ou `RunIdentityViolation` portant TOUTES les causes.

    À utiliser là où l'identité se DÉCLARE (création d'un run), jamais là où elle se recopie :
    un consommateur qui reçoit une identité déjà invalide n'a rien à corriger.
    """
    rapport = check_run_identity(identite)
    if not rapport["conforme"]:
        raise RunIdentityViolation(
            "RUN_IDENTITY_V1 non satisfait :\n  - " + "\n  - ".join(rapport["violations"]))
    return rapport["identite"]
