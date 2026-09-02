# -*- coding: utf-8 -*-
"""Le binaire Blender cesse d'etre code en dur sur un poste (GO Pierre 2026-08-19).

DEFAUT MESURE PAR LE PREFLIGHT DE PUBLICATION. Deux fichiers de PRODUCTION portaient le
chemin absolu d'une machine :

    asset_dispatch.py:63          BLENDER_WSL = "<home d un compte>/3d-pipeline/..."
    asset_geometry/oracle.py:173  le MEME chemin, recopie en litteral dans la commande

Deux consequences, pas une :
  · FUITE — le nom d'utilisateur part au depot public. C'est ce qui a fait remonter le
    defaut : le preflight cherchait des chemins locaux, il a trouve du CODE ACTIF ;
  · PORTABILITE — ce code ne peut tourner que sur ce poste. Le chemin est en dur ET
    DUPLIQUE : deux sources d'autorite qui peuvent deja diverger.

LE MOTIF N'EST PAS INVENTE ICI, IL EST DEJA RATIFIE DANS CE DEPOT. `godot_bin.mjs` resout
exactement le meme probleme — un binaire local, propre a chaque poste :

    « Ordre : env GODOT_BIN -> forge/godot.config.json -> erreur. »
    godot.config.json         gitignore (.gitignore:181), JAMAIS versionne
    godot.config.example.json versionne, sert de gabarit

Ce lot applique ce motif au binaire Blender. Meme ordre, meme separation config/exemple,
meme refus de deviner : sans configuration, une ERREUR QUI DIT QUOI FAIRE, jamais un
chemin invente qui echouerait plus loin sans expliquer pourquoi.

`sources.py` porte deja la regle du studio en toutes lettres : « TOUT module qui a besoin
d'une racine par defaut doit appeler `default_repo_root()` / `default_transcripts_root()`
— jamais recopier un chemin litteral ». Le producteur d'assets ne l'appliquait pas.
"""
from __future__ import annotations

import json
import re

import pytest

from forge.blender_bin import (
    BlenderNonConfigure,
    CHEMIN_CONFIG_DEFAUT,
    DISTRO_DEFAUT,
    resolve_blender,
)


BIN = "/home/quelquun/blender/blender"


def _config(tmp_path, **champs):
    p = tmp_path / "blender.config.json"
    p.write_text(json.dumps(champs), encoding="utf-8")
    return p


# --- l'ordre de resolution, identique a godot_bin ------------------------------------------


def test_l_ENVIRONNEMENT_gagne_sur_la_config(tmp_path):
    """Meme priorite que `GODOT_BIN` : un poste peut surcharger sans toucher au fichier."""
    cfg = _config(tmp_path, blender_bin="/depuis/config", wsl_distro="Debian")
    r = resolve_blender(env={"BLENDER_BIN": BIN, "WSL_DISTRO": "Ubuntu-22.04"},
                        chemin_config=cfg)
    assert r.binaire == BIN
    assert r.distro == "Ubuntu-22.04"
    assert r.source == "env"


def test_la_CONFIG_prend_le_relais_quand_l_env_est_muet(tmp_path):
    r = resolve_blender(env={}, chemin_config=_config(tmp_path, blender_bin=BIN))
    assert r.binaire == BIN
    assert r.source == "config"


def test_la_DISTRO_a_un_defaut_mais_le_BINAIRE_n_en_a_PAS(tmp_path):
    """Asymetrie VOULUE. La distro est un choix d'installation partage et sans risque —
    `Ubuntu-24.04` reste un defaut raisonnable. Le CHEMIN du binaire, lui, depend du nom
    d'utilisateur : en inventer un serait exactement le defaut qu'on ferme."""
    r = resolve_blender(env={}, chemin_config=_config(tmp_path, blender_bin=BIN))
    assert r.distro == DISTRO_DEFAUT == "Ubuntu-24.04"


# --- l'absence de configuration est une ERREUR EXPLICITE, jamais une supposition -----------


def test_sans_configuration_l_erreur_DIT_QUOI_FAIRE(tmp_path):
    with pytest.raises(BlenderNonConfigure) as exc:
        resolve_blender(env={}, chemin_config=tmp_path / "absent.json")
    msg = str(exc.value)
    assert "BLENDER_BIN" in msg, "la variable d'environnement doit etre nommee"
    assert "blender.config.json" in msg, "le fichier de config doit etre nomme"
    assert "example" in msg, "le gabarit doit etre nomme — sinon on cherche a l'aveugle"


def test_une_config_ILLISIBLE_ne_devient_pas_silencieusement_une_absence(tmp_path):
    """Un JSON casse et un fichier absent sont deux faits DIFFERENTS. Les confondre
    ferait chercher une configuration manquante alors qu'elle existe et qu'elle est
    malformee."""
    p = tmp_path / "blender.config.json"
    p.write_text("{ceci n est pas du json", encoding="utf-8")
    with pytest.raises(BlenderNonConfigure, match="illisible"):
        resolve_blender(env={}, chemin_config=p)


@pytest.mark.parametrize("vide", ["", "   "])
def test_une_valeur_VIDE_est_traitee_comme_ABSENTE(tmp_path, vide):
    with pytest.raises(BlenderNonConfigure):
        resolve_blender(env={"BLENDER_BIN": vide}, chemin_config=tmp_path / "absent.json")


# --- plus AUCUN chemin de poste dans le code -----------------------------------------------


# Un compte NOMME serait deux fautes : la garde ne protegerait que CE poste, et le
# fichier publierait le nom qu il interdit. Le motif generique attrape n importe quel
# compte ; le gabarit `/home/<utilisateur>/` NE matche PAS (`<` `>` hors de la classe),
# ce qui est exactement la discrimination voulue.
_CHEMIN_DE_POSTE = re.compile(r"/home/[\w.-]+/")


@pytest.mark.parametrize("module", [
    "forge/asset_producer/asset_dispatch.py",
    "forge/asset_geometry/oracle.py",
    "forge/blender_bin.py",
])
def test_AUCUN_chemin_de_poste_ne_subsiste_dans_le_code(module):
    """LE test du lot. Il rougira si quelqu'un recolle un chemin absolu « juste pour
    depanner » — c'est exactement ainsi que celui-ci est arrive."""
    from pathlib import Path
    src = (Path(__file__).resolve().parents[2] / module).read_text(encoding="utf-8")
    trouve = _CHEMIN_DE_POSTE.search(src)
    assert not trouve, f"{module} porte encore un chemin de poste : {trouve.group(0)}"


def test_les_DEUX_appelants_partagent_la_MEME_resolution(tmp_path):
    """Le chemin etait DUPLIQUE dans deux fichiers : deux autorites qui pouvaient deja
    diverger. Une seule fonction, importee des deux cotes."""
    import inspect

    from forge.asset_geometry import oracle as O
    from forge.asset_producer import asset_dispatch as AD
    for mod in (AD, O):
        src = inspect.getsource(mod)
        assert "resolve_blender" in src, \
            f"{mod.__name__} ne passe pas par la resolution partagee"


# --- le gabarit est versionne, la config REELLE ne l'est pas -------------------------------


def test_le_GABARIT_existe_et_ne_contient_aucun_chemin_reel():
    from pathlib import Path
    ex = Path(__file__).resolve().parents[1] / "blender.config.example.json"
    assert ex.is_file(), "sans gabarit, un nouveau poste devine la forme du fichier"
    d = json.loads(ex.read_text(encoding="utf-8"))
    assert "blender_bin" in d
    assert not _CHEMIN_DE_POSTE.search(json.dumps(d)), "le gabarit publierait un chemin de poste REEL au lieu d un gabarit"


def test_la_config_REELLE_est_ignoree_par_git():
    """Meme regle que `godot.config.json` (.gitignore:181) : le fichier qui porte le
    chemin d'un poste ne doit JAMAIS pouvoir etre commite par inadvertance."""
    from pathlib import Path
    gi = (Path(__file__).resolve().parents[2] / ".gitignore").read_text(encoding="utf-8")
    assert "forge/blender.config.json" in gi
    assert CHEMIN_CONFIG_DEFAUT.name == "blender.config.json"
