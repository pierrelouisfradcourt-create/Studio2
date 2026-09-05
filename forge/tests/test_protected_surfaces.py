"""Dérivation `forge/test_surfaces.yaml` -> deny de `--disallowedTools` (gate 1-ter).

Fichier NEUF sous `forge/tests/**`, régime `create_allowed_modify_denied` : la CRÉATION est
permise, c'est la modification d'un test préexistant qui demande une dérogation.

Ce que ces tests prouvent : la dérivation est EXACTE en sortie de fonction, et le régime est
respecté (aucun `Write` émis). Ce qu'ils NE prouvent PAS, dit ici plutôt que sous-entendu :
l'effet réel des motifs à joker médian (`GAMES/*/tests/**`) sur l'interprétation du harnais —
seul un run réel montrerait le déni posé.
"""
from __future__ import annotations

import pytest

from forge import protected_surfaces as ps


def _ecrire(tmp_path, texte):
    p = tmp_path / "test_surfaces.yaml"
    p.write_text(texte, encoding="utf-8")
    return p


# --- lecture et validation ------------------------------------------------------------

def test_load_surfaces_lit_la_declaration_reelle_du_depot():
    """La déclaration versionnée est lisible et porte le régime ratifié."""
    config = ps.load_surfaces()
    assert config["regime"] == ps.REGIME_CREATE_ALLOWED_MODIFY_DENIED
    assert config["surfaces"] == [
        "forge/tests/**", "GAMES/*/tests/**", "GAMES/*/07_TESTS/**"]
    assert config["derogation_path"] == ".claude/HUMAN_GIT_OVERRIDE.json"


@pytest.mark.parametrize("contenu, motif", [
    ("schema: mauvais.schema.v1\nsurfaces: [a/**]\nregime: create_allowed_modify_denied\n",
     "schéma inattendu"),
    ("schema: forge.test_surfaces.v1\nsurfaces: []\nregime: create_allowed_modify_denied\n",
     "vide ou non-liste"),
    ("schema: forge.test_surfaces.v1\nsurfaces: [a/**]\nregime: n_importe_quoi\n",
     "régime inconnu"),
    ("schema: forge.test_surfaces.v1\nsurfaces: [42]\nregime: create_allowed_modify_denied\n",
     "non-texte"),
])
def test_load_surfaces_refuse_une_declaration_mal_formee(tmp_path, contenu, motif):
    """Une déclaration muette donnerait un bornage muet — donc un vert silencieux."""
    with pytest.raises(ps.ProtectedSurfacesError, match=motif):
        ps.load_surfaces(_ecrire(tmp_path, contenu))


def test_load_surfaces_refuse_un_fichier_absent(tmp_path):
    with pytest.raises(ps.ProtectedSurfacesError, match="introuvable"):
        ps.load_surfaces(tmp_path / "absent.yaml")


# --- dérivation -----------------------------------------------------------------------

def test_derivation_emet_un_Edit_par_surface_et_aucun_Write(tmp_path):
    """Le régime en une assertion : Edit refusé, Write jamais."""
    cfg = _ecrire(tmp_path, "schema: forge.test_surfaces.v1\n"
                            "surfaces:\n  - a/tests/**\n  - b/*/07_TESTS/**\n"
                            "regime: create_allowed_modify_denied\n")
    specs = ps.disallowed_specs(cfg)
    assert specs == ("Edit(a/tests/**)", "Edit(b/*/07_TESTS/**)")
    assert not any(s.startswith("Write(") for s in specs)


def test_fail_safe_denie_totalement_edit_sur_declaration_illisible(tmp_path, caplog):
    """Anomalie -> borne totale, JAMAIS un fail-open, et la trace le dit."""
    with caplog.at_level("WARNING"):
        specs = ps.disallowed_specs_fail_safe(tmp_path / "absent.yaml")
    assert specs == ps.FAIL_SAFE_SPECS == ("Edit",)
    assert "fail-safe" in caplog.text


# --- branchement effectif dans l'exécuteur --------------------------------------------

def test_step_disallowed_derive_de_la_declaration_et_non_ecrit_en_dur():
    """Le lien données -> bornage : ce que l'exécuteur pose vient bien du fichier."""
    from forge.run_real import _STEP_DISALLOWED, _STEP_DISALLOWED_BASE
    ajout = tuple(x for x in _STEP_DISALLOWED if x not in _STEP_DISALLOWED_BASE)
    assert ajout == ps.disallowed_specs()


def test_le_motif_racine_herite_de_v1_a_disparu():
    """`/tests/**` visait un dossier absent de V2 : la protection était inopérante."""
    from forge.run_real import _STEP_DISALLOWED
    assert not {"Write(/tests/**)", "Edit(/tests/**)"} & set(_STEP_DISALLOWED)


def test_le_builder_peut_toujours_creer_un_test_de_jeu():
    """Régression de l'incident snake-s9r (2026-07-28) : `run_tests.gd` reste déposable."""
    from forge.run_real import _STEP_DISALLOWED, _derive_disallowed
    deny = _derive_disallowed(("Write", "Edit", "Read", "Bash(node:*)"))
    assert not any(s.startswith("Write(") and "tests" in s.lower() for s in deny)
    assert "Edit(GAMES/*/tests/**)" in _STEP_DISALLOWED
