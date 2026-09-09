"""Tests de `forge.content_additive`.

Un oracle qu'on n'a pas vu ÉCHOUER ne mesure rien. Ces tests ne se contentent donc pas de
vérifier qu'un jeu conforme passe : ils injectent une violation par propriété et exigent
qu'elle soit attrapée par CETTE propriété et par elle seule, avec le fichier fautif nommé.

Les jeux sont SYNTHÉTIQUES, construits en tmp_path. Faire porter ces tests sur `GAMES/`
figerait un instantané — le jour où un jeu réel change de conformité, le test rougirait
pour une raison sans rapport avec l'oracle. Un seul test touche le dépôt réel, et il
n'affirme rien sur la conformité : seulement que chaque projet reçoit un verdict du
vocabulaire fermé.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from forge import content_additive as ca

PROVIDER = "06_RUNTIME/adapters/content_provider/content_provider.gd"


def _ecrire(chemin: Path, texte: str) -> None:
    chemin.parent.mkdir(parents=True, exist_ok=True)
    chemin.write_text(texte, encoding="utf-8")


@pytest.fixture()
def jeu(tmp_path: Path) -> Path:
    """Jeu SYNTHÉTIQUE conforme : deux unités, un catalogue, un seul point de passage."""
    j = tmp_path / "jeu_temoin"
    _ecrire(j / "project.godot", "[application]\n")
    for unite in ("zone_a", "zone_b"):
        _ecrire(j / "03_WORLD/levels" / unite / "level.json", json.dumps({"plan": []}))
    _ecrire(j / "03_WORLD/rules/catalog.json",
            json.dumps({"niveaux": [{"dossier": "zone_a"}, {"dossier": "zone_b"}]}))
    _ecrire(j / "05_SYSTEMS/regle/regle.gd",
            "extends RefCounted\nstatic func pas(x): return x + 1\n")
    _ecrire(j / PROVIDER,
            "extends RefCounted\n"
            'const DOSSIER := "res://03_WORLD/levels/"\n'
            'const CLE_DOSSIER := "dossier"\n'
            "static func descripteur_du_dossier(nom): return nom\n")
    # Le TEST, lui, a le droit de nommer le contenu : c'est la propriété mesurée chez
    # pacman, où les 8 citations de `maze_classic` sont toutes dans 07_TESTS.
    _ecrire(j / "07_TESTS/unit/x.test.gd", "extends RefCounted\n# zone_a zone_b\nvar a = \"zone_a\"\n")
    return j


def _verdict(jeu: Path) -> ca.Rapport:
    return ca.analyser(jeu)


# --- témoin ---------------------------------------------------------------------------

def test_temoin_conforme_six_proprietes(jeu: Path) -> None:
    r = _verdict(jeu)
    assert r.verdict == ca.CONFORME, [c.fautifs for c in r.constats if not c.tenue]
    assert len(r.constats) == 6
    assert all(c.tenue for c in r.constats)
    assert r.unites == ["zone_a", "zone_b"]


def test_le_test_peut_nommer_le_contenu_sans_faire_echouer(jeu: Path) -> None:
    """`07_TESTS` est hors frontière : y nommer une unité n'est pas une violation."""
    _ecrire(jeu / "07_TESTS/oracle/autre.gd", 'var x = "zone_a"\nconst Y := "zone_b"\n')
    assert _verdict(jeu).verdict == ca.CONFORME


# --- une mutation par propriété -------------------------------------------------------

def test_p1_deux_points_de_passage(jeu: Path) -> None:
    _ecrire(jeu / "06_RUNTIME/adapters/lecteur_bis.gd",
            'extends RefCounted\nconst C := "res://03_WORLD/levels/"\n')
    r = _verdict(jeu)
    assert r.verdict == ca.NON_CONFORME
    echecs = [c for c in r.constats if not c.tenue]
    assert [c.nom for c in echecs] == ["P1 point de passage unique"]
    assert any("lecteur_bis.gd" in f for f in echecs[0].fautifs)


def test_p2_fournisseur_nomme_une_unite(jeu: Path) -> None:
    with (jeu / PROVIDER).open("a", encoding="utf-8") as f:
        f.write('const REPLI := "zone_a"\n')
    echecs = [c for c in _verdict(jeu).constats if not c.tenue]
    assert [c.nom for c in echecs] == ["P2 fournisseur ne nomme aucun contenu"]
    assert any("zone_a" in x for x in echecs[0].fautifs)


def test_p3_aiguillage_par_nom(jeu: Path) -> None:
    with (jeu / PROVIDER).open("a", encoding="utf-8") as f:
        f.write("static func choix(n):\n\tmatch n:\n\t\t_: return 0\n")
    echecs = [c for c in _verdict(jeu).constats if not c.tenue]
    assert [c.nom for c in echecs] == ["P3 aucun aiguillage par nom"]


def test_p4_logique_pure_nomme_une_unite(jeu: Path) -> None:
    with (jeu / "05_SYSTEMS/regle/regle.gd").open("a", encoding="utf-8") as f:
        f.write('const SPECIALE := "zone_b"\n')
    echecs = [c for c in _verdict(jeu).constats if not c.tenue]
    assert [c.nom for c in echecs] == ["P4 logique pure ne nomme aucun contenu"]
    assert any("regle.gd" in x for x in echecs[0].fautifs)


def test_p5_runtime_hors_fournisseur_nomme_une_unite(jeu: Path) -> None:
    # Ne cite PAS la racine de contenu : sinon P1 échouerait aussi et la mutation ne
    # discriminerait plus P5 toute seule.
    _ecrire(jeu / "06_RUNTIME/adapters/shell/shell.gd", 'extends RefCounted\nconst D := "zone_a"\n')
    echecs = [c for c in _verdict(jeu).constats if not c.tenue]
    assert [c.nom for c in echecs] == ["P5 runtime hors fournisseur ne nomme rien"]


def test_p6_unite_hors_catalogue(jeu: Path) -> None:
    _ecrire(jeu / "03_WORLD/levels/zone_orpheline/level.json", json.dumps({"plan": []}))
    echecs = [c for c in _verdict(jeu).constats if not c.tenue]
    assert [c.nom for c in echecs] == ["P6 catalogue et disque s'accordent"]
    assert any("zone_orpheline" in x for x in echecs[0].fautifs)


def test_p6_catalogue_declare_une_unite_absente(jeu: Path) -> None:
    _ecrire(jeu / "03_WORLD/rules/catalog.json",
            json.dumps({"niveaux": [{"dossier": "zone_a"}, {"dossier": "zone_b"},
                                    {"dossier": "zone_fantome"}]}))
    echecs = [c for c in _verdict(jeu).constats if not c.tenue]
    assert [c.nom for c in echecs] == ["P6 catalogue et disque s'accordent"]


# --- absence de couche de contenu -----------------------------------------------------

def test_sans_couche_de_contenu_rend_sans_objet(tmp_path: Path) -> None:
    """SANS_OBJET, jamais CONFORME : la propriété ne s'applique pas, un vert serait faux."""
    j = tmp_path / "jeu_sans_contenu"
    _ecrire(j / "project.godot", "[application]\n")
    _ecrire(j / "05_SYSTEMS/regle/regle.gd", "extends RefCounted\n")
    r = _verdict(j)
    assert r.verdict == ca.SANS_OBJET
    assert r.constats == []
    assert "03_WORLD/levels" in r.motif


# --- commentaires : la règle naïve est celle de l'oracle d'origine ---------------------

def test_commentaire_retire_avant_comptage(jeu: Path) -> None:
    with (jeu / "05_SYSTEMS/regle/regle.gd").open("a", encoding="utf-8") as f:
        f.write("# cette regle ne s'applique pas a zone_a\n")
    assert _verdict(jeu).verdict == ca.CONFORME, "un commentaire n'est pas une référence"


def test_code_seul_coupe_bien_le_code_aussi() -> None:
    assert "zone_a" not in ca.code_seul('var x = 1 # "zone_a"')
    assert "zone_a" in ca.code_seul('var x = "zone_a"')


# --- CLI et dépôt réel ----------------------------------------------------------------

def test_racine_sans_projet_godot_rend_2(tmp_path: Path) -> None:
    assert ca.main([str(tmp_path)]) == 2


def test_cli_rend_1_quand_un_applicable_echoue(jeu: Path, tmp_path: Path) -> None:
    with (jeu / PROVIDER).open("a", encoding="utf-8") as f:
        f.write('const REPLI := "zone_a"\n')
    assert ca.main([str(tmp_path)]) == 1


def test_cli_rend_0_quand_tout_applicable_est_conforme(jeu: Path, tmp_path: Path) -> None:
    assert ca.main([str(tmp_path)]) == 0


def test_depot_reel_chaque_projet_recoit_un_verdict_du_vocabulaire() -> None:
    """N'AFFIRME RIEN sur la conformité des jeux réels — figer un instantané ici ferait
    rougir le test le jour où un jeu change, pour une raison étrangère à l'oracle."""
    racine = Path(__file__).resolve().parents[2] / "GAMES"
    if not racine.is_dir():
        pytest.skip("GAMES/ absent")
    rapports = ca.auditer(racine)
    assert rapports, "aucun projet Godot trouvé sous GAMES/"
    for r in rapports:
        assert r.verdict in ca.VERDICTS, f"{r.jeu} -> verdict hors vocabulaire : {r.verdict}"
        if r.verdict != ca.SANS_OBJET:
            assert len(r.constats) == 6
