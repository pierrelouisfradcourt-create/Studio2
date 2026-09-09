"""Gouvernance de `content_additive` : l'oracle est-il EFFECTIVEMENT consomme ?

`test_content_additive.py` prouve que l'oracle MESURE juste. Ce fichier-ci prouve autre
chose, et c'est la difference entre « outil disponible » et « outil gouverne » : que
`forge/oracles.json` le declare, que `forge.oracle` sache le resoudre, et que le code de
retour de LA COMMANDE CONFIGUREE bloque ou ne bloque pas conformement a la graduation.

Sans ces tests, l'inscription dans `oracles.json` serait une declaration que rien ne
verifie — exactement le mode de panne que l'oracle lui-meme sert a detecter ailleurs.

REGLE GOUVERNEE, ratifiee le 2026-09-09 :
    P4/P5  INVARIANT  -> BLOQUANT           (le coeur est atteint)
    P1-P3  HYGIENE    -> reserve            (cout borne : un fichier d'adaptateur)
    P6     INTEGRITE  -> reserve, axe distinct (correction du contenu)
Mode normal gradue ; `--strict` disponible pour une campagne qui veut tout bloquer.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from forge import content_additive as ca
from forge.oracle import resolve_oracle

RACINE = Path(__file__).resolve().parents[2]
PROVIDER = "06_RUNTIME/adapters/content_provider/content_provider.gd"


def _ecrire(chemin: Path, texte: str) -> None:
    chemin.parent.mkdir(parents=True, exist_ok=True)
    chemin.write_text(texte, encoding="utf-8")


@pytest.fixture()
def jeu(tmp_path: Path) -> Path:
    """Jeu synthetique CONFORME, jumeau de celui de test_content_additive.py."""
    j = tmp_path / "jeu_gate"
    _ecrire(j / "project.godot", "[application]\n")
    for unite in ("zone_a", "zone_b"):
        _ecrire(j / "03_WORLD/levels" / unite / "level.json", json.dumps({"plan": []}))
    _ecrire(j / "03_WORLD/rules/catalog.json",
            json.dumps({"niveaux": [{"dossier": "zone_a"}, {"dossier": "zone_b"}]}))
    _ecrire(j / "05_SYSTEMS/regle/regle.gd", "extends RefCounted\nstatic func pas(x): return x + 1\n")
    _ecrire(j / PROVIDER,
            "extends RefCounted\n"
            'const DOSSIER := "res://03_WORLD/levels/"\n'
            'const CLE_DOSSIER := "dossier"\n')
    return j


def _lancer_la_commande_configuree(racine: Path, *extra: str) -> subprocess.CompletedProcess:
    """Lance LA COMMANDE DE `oracles.json`, avec la racine remplacee.

    Le test porte ainsi sur la commande REELLEMENT configuree — pas sur un appel Python
    equivalent qui pourrait diverger d'elle sans que personne ne le voie.
    """
    spec = resolve_oracle("content_additive")
    commande = list(spec.command)
    assert commande[-1] == "GAMES", (
        "la commande configuree ne finit plus par la racine des jeux : ce test remplace le "
        f"dernier argument et deviendrait faux -> {commande}")
    commande[-1] = str(racine)
    commande.extend(extra)
    return subprocess.run(commande, cwd=spec.cwd, capture_output=True, text=True, timeout=300)


# --- 1. consommation reelle par oracles.json ------------------------------------------

def test_oracles_json_declare_content_additive() -> None:
    entrees = json.loads((RACINE / "forge/oracles.json").read_text(encoding="utf-8"))
    assert "content_additive" in entrees, "l'oracle n'est pas gouverne : absent de oracles.json"
    e = entrees["content_additive"]
    assert e["cwd"] == "."
    assert e["command"][1:] == ["-m", "forge.content_additive", "GAMES"], e["command"]


def test_forge_oracle_sait_le_resoudre() -> None:
    spec = resolve_oracle("content_additive")
    assert spec.project == "content_additive"
    assert spec.cwd == RACINE
    assert Path(spec.command[0]).name.lower().startswith("python"), spec.command[0]


def test_la_commande_configuree_tourne_sur_le_depot_reel() -> None:
    """RUN REEL : la commande declaree s'execute vraiment, sur les vrais jeux, et sort 0.

    Elle sort 0 parce qu'aucun INVARIANT n'est rompu aujourd'hui — bomberman_3d est en
    RESERVES (P2 hygiene + P6 integrite), ce qui ne bloque pas. Le test n'AFFIRME PAS que
    bomberman est conforme : il affirme qu'aucun coeur n'est atteint.
    """
    spec = resolve_oracle("content_additive")
    r = subprocess.run(spec.command, cwd=spec.cwd, capture_output=True, text=True, timeout=300)
    assert r.returncode == 0, r.stdout + r.stderr
    assert "ORACLE CONTENT-ADDITIF" in r.stdout
    assert "BILAN" in r.stdout


# --- 2. P4/P5 PEUVENT bloquer ---------------------------------------------------------

def test_p4_rompu_fait_bloquer_la_commande_configuree(jeu: Path, tmp_path: Path) -> None:
    """La logique pure nomme une unite : le coeur est atteint -> la commande sort 1."""
    with (jeu / "05_SYSTEMS/regle/regle.gd").open("a", encoding="utf-8") as f:
        f.write('const SPECIALE := "zone_b"\n')
    r = _lancer_la_commande_configuree(tmp_path)
    assert r.returncode == 1, r.stdout
    assert ca.NON_CONFORME in r.stdout
    assert "INVARIANT" in r.stdout


def test_p5_rompu_fait_bloquer_la_commande_configuree(jeu: Path, tmp_path: Path) -> None:
    """Un adaptateur runtime hors fournisseur nomme une unite : meme niveau, meme blocage."""
    _ecrire(jeu / "06_RUNTIME/adapters/shell/shell.gd", 'extends RefCounted\nconst D := "zone_a"\n')
    r = _lancer_la_commande_configuree(tmp_path)
    assert r.returncode == 1, r.stdout
    assert ca.NON_CONFORME in r.stdout


# --- 3. P1-P3 et P6 NE bloquent PAS en mode normal ------------------------------------

def test_p2_rompu_ne_bloque_pas_en_mode_normal(jeu: Path, tmp_path: Path) -> None:
    """Le cas mesure de bomberman_3d : cout borne a un fichier d'adaptateur."""
    with (jeu / PROVIDER).open("a", encoding="utf-8") as f:
        f.write('const REPLI := "zone_a"\n')
    r = _lancer_la_commande_configuree(tmp_path)
    assert r.returncode == 0, r.stdout
    assert ca.RESERVES in r.stdout
    assert "HYGIENE" in r.stdout, "la reserve doit rester DITE, jamais tue"


def test_p1_rompu_ne_bloque_pas_en_mode_normal(jeu: Path, tmp_path: Path) -> None:
    _ecrire(jeu / "06_RUNTIME/adapters/lecteur_bis.gd",
            'extends RefCounted\nconst C := "res://03_WORLD/levels/"\n')
    r = _lancer_la_commande_configuree(tmp_path)
    assert r.returncode == 0, r.stdout
    assert ca.RESERVES in r.stdout


def test_p6_rompu_ne_bloque_pas_en_mode_normal(jeu: Path, tmp_path: Path) -> None:
    _ecrire(jeu / "03_WORLD/levels/zone_orpheline/level.json", json.dumps({"plan": []}))
    r = _lancer_la_commande_configuree(tmp_path)
    assert r.returncode == 0, r.stdout
    assert "INTEGRITE" in r.stdout


def test_strict_transforme_toute_reserve_en_blocage(jeu: Path, tmp_path: Path) -> None:
    """`--strict` reste disponible pour une campagne : MEME commande, MEME mesure, autre seuil."""
    with (jeu / PROVIDER).open("a", encoding="utf-8") as f:
        f.write('const REPLI := "zone_a"\n')
    assert _lancer_la_commande_configuree(tmp_path).returncode == 0
    assert _lancer_la_commande_configuree(tmp_path, "--strict").returncode == 1


# --- garde de gouvernance -------------------------------------------------------------

def test_le_mode_par_defaut_reste_gradue() -> None:
    """La commande gouvernee ne doit PAS porter --strict : le mode normal est gradue, et
    `--strict` est une decision de campagne, jamais le defaut silencieux."""
    assert "--strict" not in resolve_oracle("content_additive").command
