# -*- coding: utf-8 -*-
"""Résolution du binaire Blender (WSL) — source UNIQUE, jamais un chemin de poste.

    Ordre : env `BLENDER_BIN` → `forge/blender.config.json` → ERREUR explicite.

MOTIF DÉJÀ RATIFIÉ DANS CE DÉPÔT, repris à l'identique : `godot_bin.mjs` résout le même
problème — un binaire local, propre à chaque poste — avec la même chaîne
(`env GODOT_BIN → forge/godot.config.json → erreur`), le `.json` **gitignoré** et
un `.example.json` **versionné** comme gabarit. Rien n'est inventé ici.

DÉFAUT FERMÉ (2026-08-19), remonté par le préflight de publication. Deux fichiers de
PRODUCTION portaient le chemin absolu d'une machine — `asset_dispatch.py` dans une
constante `BLENDER_WSL`, `asset_geometry/oracle.py` en littéral inline. Le chemin lui-même
n'est **pas reproduit ici** : un fichier publié qui cite la fuite qu'il corrige la publie
quand même. Un test l'interdit désormais dans les trois modules, celui-ci compris.

Deux conséquences distinctes : une **fuite** (le nom d'utilisateur serait parti au dépôt) et
un défaut de **portabilité** (le code ne pouvait tourner que sur ce poste) — aggravé par la
DUPLICATION, deux autorités pouvant déjà diverger.

`sources.py` porte la règle du studio en toutes lettres : « TOUT module qui a besoin d'une
racine par défaut doit appeler [le résolveur] — jamais recopier un chemin littéral ». Le
producteur d'assets ne l'appliquait pas ; ce module l'y ramène.

ON NE DEVINE PAS. Sans configuration, une erreur qui NOMME la variable, le fichier et son
gabarit — jamais un chemin par défaut qui échouerait plus loin sans expliquer pourquoi.
"""
from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path

_ICI = Path(__file__).resolve().parent

#: Config RÉELLE d'un poste — gitignorée, comme `godot.config.json`.
CHEMIN_CONFIG_DEFAUT = _ICI / "blender.config.json"

#: Distribution WSL par défaut. ASYMÉTRIE VOULUE avec le binaire : une distro est un choix
#: d'installation partagé et sans donnée personnelle, un chemin de binaire contient le nom
#: d'utilisateur. L'une peut avoir un défaut, l'autre non.
DISTRO_DEFAUT = "Ubuntu-24.04"

_AIDE = (
    "Blender (WSL) n'est pas configuré sur ce poste. Renseigner SOIT la variable "
    "d'environnement `BLENDER_BIN`, SOIT le champ \"blender_bin\" dans "
    "`forge/blender.config.json` (gabarit : `blender.config.example.json`). "
    "La distro se règle par `WSL_DISTRO` ou \"wsl_distro\" "
    f"(défaut : {DISTRO_DEFAUT})."
)


class BlenderNonConfigure(RuntimeError):
    """Levée quand aucune source ne fournit le chemin du binaire Blender.

    C'est une erreur de CONFIGURATION, pas de produit : elle ne dit rien de la qualité
    d'un asset. Les appelants la traitent comme « producteur injoignable », jamais comme
    un défaut de ce qu'ils mesurent.
    """


@dataclass(frozen=True)
class Blender:
    binaire: str
    distro: str
    #: `env` | `config` — d'où vient la valeur. Un diagnostic qui ne dit pas SA source
    #: oblige à relire trois endroits pour savoir lequel a gagné.
    source: str


def _texte(valeur) -> str | None:
    """Chaîne non vide après strip, sinon None. `""` et `"   "` sont des ABSENCES
    déguisées en valeurs — les accepter produirait une commande vide, plus difficile à
    diagnostiquer qu'une configuration manquante."""
    if not isinstance(valeur, str):
        return None
    return valeur.strip() or None


def resolve_blender(env: dict | None = None,
                    chemin_config: Path | str | None = None) -> Blender:
    """Binaire + distro, ou `BlenderNonConfigure` nommant les trois voies de réparation."""
    env = os.environ if env is None else env
    chemin = Path(chemin_config) if chemin_config is not None else CHEMIN_CONFIG_DEFAUT

    depuis_env = _texte(env.get("BLENDER_BIN"))
    if depuis_env:
        return Blender(binaire=depuis_env,
                       distro=_texte(env.get("WSL_DISTRO")) or DISTRO_DEFAUT,
                       source="env")

    if chemin.exists():
        try:
            data = json.loads(chemin.read_text(encoding="utf-8"))
        except (ValueError, OSError) as exc:
            # ILLISIBLE n'est PAS ABSENT : confondre les deux ferait chercher une
            # configuration manquante alors qu'elle existe et qu'elle est malformée.
            raise BlenderNonConfigure(f"{chemin} illisible : {exc}\n{_AIDE}") from None
        if isinstance(data, dict):
            depuis_config = _texte(data.get("blender_bin"))
            if depuis_config:
                return Blender(binaire=depuis_config,
                               distro=_texte(data.get("wsl_distro")) or DISTRO_DEFAUT,
                               source="config")

    raise BlenderNonConfigure(_AIDE)
