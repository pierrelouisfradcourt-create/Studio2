"""Lot D (GO Pierre 2026-08-23, ordre F -> D -> run 10) : fermeture de trois FUITES
DE MESURE, sans station/agent/profil/oracle LLM nouveau.

  FUITE 1 -- `replay_ref` ignore par la sonde quand le step ADVANTAGE ne porte pas
             sa propre `affordance` (mesure : run 9, step `j_advantage` sans
             affordance -> la sonde mesurait la production PASSIVE du wait_frames,
             jamais un vrai clic). Corrige dans
             forge/godot_probes/player_loop.gd (`_do_before`) + nomme dans
             forge/loop_spec.mjs (`checkLoopSpec`, regle J).
  FUITE 2 -- tri alphabetique des `id` au sein d'un role (loop_spec.mjs) cassait la
             precedence VOULUE par le Prisme. Corrige : tri = ROLE_ORDER puis ordre
             D'APPARITION dans `prisme.exigences` (index), plus jamais l'alphabet.
             Couvert par forge/loop_spec.test.mjs (fixture G2 avant G1).
  FUITE 3 -- `design_intent.md` et les contrats design/ n'etaient lus par PERSONNE
             (absents de toute table `_UPSTREAM_BY_STEP`). Corrige : entrees
             additives dans run_real._UPSTREAM_BY_STEP et
             context_manifest._UPSTREAM_BY_STEP (copie stricte, testee ici).

    PYTHONPATH=scripts .venv312/Scripts/python.exe -m pytest \
        forge/tests/test_lot_d_fuites_mesure.py -v
"""
from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

import pytest

from forge import context_manifest as cm
from forge import run_real
from forge import product_oracle_godot as pog

REPO_ROOT = Path(__file__).resolve().parents[2]
PROBE = REPO_ROOT / "forge" / "godot_probes" / "player_loop.gd"
RUN9_BUILD = (REPO_ROOT / "EVIDENCE" / "runs" / "kitten_clicker" / "_run9_20260823a"
              / "game_build9")
RUN9_LOOP_JSON = (REPO_ROOT / "EVIDENCE" / "runs" / "kitten_clicker" / "_run9_20260823a"
                   / "loop.json")


# =====================================================================================
# FUITE 3 -- design_intent.md et design/*.md injectes en amont (_UPSTREAM_BY_STEP)
# =====================================================================================


def test_tables_upstream_by_step_strictement_egales():
    """Copie STRICTEMENT identique entre run_real et context_manifest (anti import
    circulaire, cf. commentaire de tete de context_manifest.py) — toute divergence
    entre les deux Lot D casserait ce test."""
    assert run_real._UPSTREAM_BY_STEP == cm._UPSTREAM_BY_STEP


@pytest.mark.parametrize("etape,design_files", [
    ("s1-prisme", ("design/progression_contract.md", "design/calibration.md")),
    ("s2.5-artbible", ("design_intent.md", "design/gameplay_loop_content_contract.md",
                       "design/progression_contract.md")),
    ("s2.7-gm-worldscan", ("design_intent.md", "design/gameplay_loop_content_contract.md",
                           "design/progression_contract.md", "design/calibration.md")),
    ("s9-build-godot-standard", ("design/gameplay_loop_content_contract.md",)),
])
def test_fichiers_design_dans_upstream_by_step(etape, design_files):
    for f in design_files:
        assert f in run_real._UPSTREAM_BY_STEP[etape], f"'{f}' absent de _UPSTREAM_BY_STEP['{etape}']"


def test_section_amont_contient_les_fichiers_design_quand_presents(tmp_path):
    """run_dir tmp avec design_intent.md + design/*.md -> la section amont de s2.7
    les contient (chemin réel + contenu)."""
    (tmp_path / "design").mkdir()
    (tmp_path / "design_intent.md").write_text("Le jeu doit recompenser la patience.", encoding="utf-8")
    (tmp_path / "design" / "gameplay_loop_content_contract.md").write_text(
        "Contrat de contenu de boucle.", encoding="utf-8")
    (tmp_path / "design" / "progression_contract.md").write_text(
        "Contrat de progression.", encoding="utf-8")
    (tmp_path / "design" / "calibration.md").write_text(
        "cost_cursor = 15 chatons.", encoding="utf-8")

    section = run_real.upstream_artifacts_section("s2.7-gm-worldscan", tmp_path)
    assert "design_intent.md" in section
    assert "Le jeu doit recompenser la patience." in section
    assert "design/gameplay_loop_content_contract.md" in section
    assert "design/progression_contract.md" in section
    assert "design/calibration.md" in section
    assert "cost_cursor = 15 chatons." in section


def test_section_amont_omet_les_fichiers_design_absents_sans_exception(tmp_path):
    """run_dir tmp SANS design/ -> section amont omise pour ces entrées, aucune
    exception (comportement inchangé, même patron que le reste de la table)."""
    section = run_real.upstream_artifacts_section("s2.7-gm-worldscan", tmp_path)
    assert "design_intent.md" not in section
    assert "design/calibration.md" not in section


def test_manifeste_dispatch_s1_prisme_porte_les_2_entrees_design(tmp_path):
    from forge.contract import load_contract
    contract = load_contract("s1-prisme")
    sources = cm.resolve_dispatch_sources("s1-prisme", contract, run_dir=tmp_path)
    upstream_names = {s["path"].split("/")[-1] for s in sources if s["role"] == "upstream"}
    assert "progression_contract.md" in upstream_names
    assert "calibration.md" in upstream_names


# =====================================================================================
# FUITE 2 -- ordre d'apparition dans prisme.exigences (plus jamais l'alphabet)
# =====================================================================================
# Couvert en detail cote Node (forge/loop_spec.test.mjs, fixture G2 avant
# G1) : le tri de deriveLoopSpec est PUR JS, aucune duplication Python ne mesure
# davantage. Un test miroir minimal ici verifie seulement que le fichier canonique
# ROLE_ORDER cite dans le contrat s1 (DECISION entre REWARD et UNLOCK) reste stable.


def test_role_order_stable_decision_entre_reward_et_unlock():
    import re
    src = (REPO_ROOT / "forge" / "loop_spec.mjs").read_text(encoding="utf-8")
    m = re.search(r"ROLE_ORDER\s*=\s*\[(.*?)\];", src, re.S)
    assert m is not None, "ROLE_ORDER introuvable dans loop_spec.mjs"
    roles = [r.strip().strip("'") for r in m.group(1).replace("\n", " ").split(",") if r.strip()]
    assert roles.index("REWARD") < roles.index("DECISION") < roles.index("UNLOCK")



def test_checklooLspec_source_nomme_le_replay_ref_sans_affordance():
    """FUITE 1 (volet statique) : checkLoopSpec doit désormais nommer un problème
    quand un J (ADVANTAGE) pointe, par `replay_ref`, un step PLAYER_ACTION SANS
    affordance (production passive non rejouable)."""
    src = (REPO_ROOT / "forge" / "loop_spec.mjs").read_text(encoding="utf-8")
    assert "production passive non rejouable" in src


# =====================================================================================
# FUITE 1 -- replay_ref rejoue affordance+repeat quand le step ADVANTAGE n'en porte pas
# =====================================================================================


def test_la_sonde_porte_le_mecanisme_replay_ref_sans_affordance():
    src = PROBE.read_text(encoding="utf-8")
    assert "_replayed_from" in src
    assert "replay_ref" in src
    assert "_find_step_by_ref" in src


def _godot_binary():
    try:
        return pog._default_binary_resolver()
    except Exception:
        return None


_SKIP_REASON = "binaire Godot non configuré sur ce poste" if _godot_binary() is None \
    else ("build run 9 absent (EVIDENCE/runs/kitten_clicker/_run9_20260823a/game_build9)"
          if not (RUN9_BUILD / "project.godot").exists() else
          ("loop.json du run 9 absent" if not RUN9_LOOP_JSON.is_file() else ""))


def _run_probe(game_dir: Path, loop_spec: dict, tmp_path: Path, *, timeout: int = 180) -> dict:
    binary = _godot_binary()
    loop_json_path = tmp_path / "loop.json"
    loop_json_path.write_text(json.dumps(loop_spec), encoding="utf-8")
    env = dict(os.environ)
    env["KC_LOOP_JSON_OVERRIDE"] = str(loop_json_path)
    proc = subprocess.run(
        [binary, *pog.GPU_WINDOW_FLAGS, "--path", str(game_dir), "--script", str(PROBE)],
        capture_output=True, text=True, timeout=timeout, encoding="utf-8", errors="replace", env=env,
    )
    line = next((l for l in proc.stdout.splitlines() if l.startswith("FORGE_ORACLE player_loop")), None)
    assert line is not None, f"sortie muette. stdout={proc.stdout!r} stderr={proc.stderr!r}"
    return json.loads(line.split(" ", 2)[2])


@pytest.mark.gpu_window  # lance le VRAI binaire Godot sur game_build9 (fenêtre) — c'était
                         # le trou de marqueur qui faisait ouvrir une fenêtre à CHAQUE T0
                         # standard depuis le Lot D (constaté Pierre 2026-08-30)
@pytest.mark.skipif(bool(_SKIP_REASON), reason=_SKIP_REASON)
def test_replay_ref_sans_affordance_rejoue_desormais_pelote_sur_run9(tmp_path):
    """MESURE (Lot D) : le loop.json RÉEL du run 9 (j_advantage sans `affordance`,
    replay_ref='b_click') tourne tel quel sur le build archivé du run 9 -- le step
    ADVANTAGE clique désormais `pelote` (l'affordance du step référencé) au lieu de
    ne mesurer que la production passive de `wait_frames`. `replayed_from` doit
    valoir 'b_click' et le delta `deltas.j_advantage` doit changer par rapport à
    l'ancien comportement passif (mesuré run 9 : 96.0)."""
    loop_spec = json.loads(RUN9_LOOP_JSON.read_text(encoding="utf-8"))
    payload = _run_probe(RUN9_BUILD, loop_spec, tmp_path)
    print("FORGE_ORACLE player_loop (Lot D, replay_ref sans affordance):",
          json.dumps(payload)[:1500])

    j_step = next((s for s in payload["data"]["steps"] if s["ref"] == "j_advantage"), None)
    assert j_step is not None, f"step j_advantage absent : {payload['data']['steps']}"
    assert j_step.get("replayed_from") == "b_click"

    deltas = payload["data"]["deltas"]
    assert "j_advantage" in deltas
    OLD_PASSIVE_DELTA = 96.0  # mesuré run 9 (comportement AVANT Lot D, production passive)
    new_delta = deltas["j_advantage"]
    print(f"Lot D delta j_advantage : ancien (passif, run 9)={OLD_PASSIVE_DELTA} "
          f"nouveau (rejeu du clic, apres fix)={new_delta}")
    assert new_delta != OLD_PASSIVE_DELTA, (
        "le delta j_advantage doit changer par rapport à la mesure passive du run 9")
