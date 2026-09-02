# -*- coding: utf-8 -*-
"""ADR-003 lot 1 — tests des 5 P0, un bloc par sous-lot, causalement attribués.

Source : docs/adr/ADR-003-forge-workflow-coherence-audit.md (GO Pierre 2026-08-15).
Nouveau fichier : n'altère aucun test existant (zone protégée respectée).
"""
from __future__ import annotations

from pathlib import Path
# ---------------------------------------------------------------------------
# P0-4 — la directive de mode GPU devient un champ VÉRIFIÉ (« aucune décision
# dans un commentaire », ratifié 2026-07-23). Avant : les .gd de breakout_v2
# exigeaient la fenêtre GPU en prose seule → routés --headless → rouges
# FABRIQUÉS (« --headless rend une texture nulle »). check_gpu_window_directive
# refuse (BLOCKED, jamais FAIL — réparer l'instrument, pas le jeu).
# ---------------------------------------------------------------------------

from forge.standard_oracles import check_gpu_window_directive

# RÉFÉRENT REPOINTÉ (2026-08-16, GO Pierre — restriction de périmètre de l'oracle).
#
# Ces deux fixtures citaient `GAMES/breakout_v2/07_TESTS/oracle/core_render_frame.gd`
# comme « cas réel ». Mesure : ce fichier ne porte PAS le marqueur `FORGE_ORACLE`, donc le
# collecteur ne le LANCE jamais (`product_oracle_godot.discover_oracle_files`). Il n'est
# pas un volet ; les règles testées ici ne valaient pas pour lui. Les tests passaient parce
# que l'oracle partageait l'erreur de périmètre — il jugeait des fichiers non routés.
#
# La croyance d'origine est traçable et elle était fausse : la docstring du collecteur
# (product_oracle_godot.py:70-76) affirme que le marqueur est « observé dans TOUS les
# oracles .gd du studio (core_render_frame.gd ligne 1…) ». Ce nom existe dans QUATRE jeux ;
# snake et bomberman_3d le portent, breakout_v2 et pacman non. L'exemple cité par la
# docstring pour justifier la règle est précisément un des deux qui l'enfreignent.
#
# NOUVEAU RÉFÉRENT : `GAMES/snake/07_TESTS/oracle/core_render_frame.gd` — volet RÉEL et
# lancé (marqueur l.4 et l.80, directive l.6). Aucune assertion n'est relâchée : les deux
# tests gardent leurs verdicts, leurs listes et leur exigence de motif.
from forge.product_oracle_godot import _ORACLE_MARKER

# En-tête DÉRIVÉ du référent réel (snake, l.1-6), condensé. Le marqueur y figure comme dans
# l'original : dans la ligne « Sortie : » de l'en-tête.
_SNAKE_ENTETE = (
    "# core_render_frame.gd — oracle de la ligne core.render. FENETRE GPU REELLE (jamais\n"
    "# --headless : le driver dummy rend une texture nulle).\n"
    f'# Sortie : "{_ORACLE_MARKER} core_render_frame {{json}}".\n')
_SNAKE_DIRECTIVE = "#\n# forge:run_mode = gpu_window\n"
_SNAKE_CORPS = "extends SceneTree\n"


def test_p0_4_prose_sans_directive_est_bloquee(tmp_path: Path):
    """Cas NÉGATIF CONSTRUIT, et c'est dit : snake porte sa directive depuis toujours (il
    ne figure pas dans les 7 volets de e02b010), donc aucun état réel « snake sans
    directive » n'existe. On retire donc la directive du référent réel — c'est exactement
    le défaut que l'oracle doit attraper, sur un fichier qui EST un volet lancé."""
    (tmp_path / "core_render_frame.gd").write_text(
        _SNAKE_ENTETE + _SNAKE_CORPS, encoding="utf-8")
    r = check_gpu_window_directive(tmp_path)
    assert r["passed"] is False
    assert r["verdict"] == "BLOCKED", "instrument à réparer — jamais FAIL, jamais OK"
    assert r["fichiers_en_defaut"] == ["core_render_frame.gd"]
    assert any("rouge fabriqué" in x for x in r["raisons"])


def test_p0_4_directive_structuree_passe(tmp_path: Path):
    """Cas POSITIF fidèle : c'est l'état réel du volet snake au dépôt."""
    (tmp_path / "core_render_frame.gd").write_text(
        _SNAKE_ENTETE + _SNAKE_DIRECTIVE + _SNAKE_CORPS, encoding="utf-8")
    r = check_gpu_window_directive(tmp_path)
    assert r["passed"] is True and r["verdict"] == "OK"
    assert r["fichiers_avec_directive"] == 1


def test_p0_4_sans_exigence_gpu_rien_a_signaler(tmp_path: Path):
    (tmp_path / "solvability.gd").write_text(
        "extends SceneTree\n# bot deterministe qui doit gagner\n", encoding="utf-8")
    r = check_gpu_window_directive(tmp_path)
    assert r["passed"] is True and r["fichiers_en_defaut"] == []


def test_p0_4_repertoire_absent_ne_fabrique_pas_d_exigence(tmp_path: Path):
    r = check_gpu_window_directive(tmp_path / "n_existe_pas")
    assert r["passed"] is True and r["fichiers_examines"] == 0


def test_p0_4_meme_autorite_que_le_routeur(tmp_path: Path):
    """La détection de la directive doit être LA regex du routeur (source unique) :
    une variante d'espacement acceptée par le routeur doit l'être ici aussi."""
    (tmp_path / "v.gd").write_text(
        "# forge : run_mode=gpu_window\n# fenetre GPU obligatoire\n", encoding="utf-8")
    from forge.product_oracle_godot import _gpu_window_declared
    assert _gpu_window_declared(tmp_path / "v.gd") is True
    r = check_gpu_window_directive(tmp_path)
    assert r["passed"] is True, "désaccord routeur/contrôle = deux vérités, interdit"


