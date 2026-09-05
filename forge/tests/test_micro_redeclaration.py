"""SAS CORRECTIF R3/freeze (C2, ratifié Pierre 2026-08-30, finding pilote L1
p1_beta) — micro-re-déclaration déterministe : après gm-r2, un pilier dont la
déclaration sur disque est ANTÉRIEURE aux réponses reçues À SES PROPRES
questions (topologie art-r2 -> gm-r2, aucun créneau de re-déclaration) obtient
UNE VRAIE micro-exécution (spawn réel via `prepare_dispatch`/`self.executor`,
JAMAIS une mutation de state.json qui ferait croire qu'une étape a tourné).

Fixture obligatoire : `EVIDENCE/_V1_FIXTURES/runs/p1_beta/` (artefact d'un run V1,
migré 2026-09-05, DONNÉE D'ENTRÉE et non preuve V2 — ART s'est déclarée round 2
AVANT que GM ne réponde, au round 2, à ses propres questions — cf.
CLOSURE_PILOTE_20260830.md dans ce dossier, finding 2)."""
from __future__ import annotations

import json
import shutil
from pathlib import Path

import pytest

from forge.driver import ForgeDriver

REPO_ROOT = Path(__file__).resolve().parents[2]
# Fixture V1 migrée le 2026-09-05 sous `EVIDENCE/_V1_FIXTURES/` (GO Pierre) : ces
# artefacts viennent de runs V1 jamais rejoués, ils ne sont PAS des preuves V2 et
# vivent donc à l'écart de `EVIDENCE/runs/`. Voir le README de ce dossier.
P1_BETA = REPO_ROOT / "EVIDENCE" / "_V1_FIXTURES" / "runs" / "p1_beta"


def _copy_p1_beta(tmp_path: Path) -> Path:
    dst = tmp_path / "p1_beta"
    shutil.copytree(P1_BETA, dst)
    return dst


def _load_dq(run_dir: Path) -> dict:
    return json.loads((run_dir / "design_questions.json").read_text(encoding="utf-8"))


def _driver(run_dir: Path, tmp_path: Path, executor=None) -> ForgeDriver:
    d = ForgeDriver.__new__(ForgeDriver)  # patron établi (test_driver_design_freeze.py)
    d.run_id = "p1_beta-20260830-run1"
    d.project = "p1_beta"
    d.profile = "full_content"
    d.run_dir = run_dir
    d.order = ["s2.5-artbible", "s2.7-gm-worldscan", "s2.5-artbible-r2",
               "s2.7-gm-worldscan-r2", "s1-prisme"]
    d.state_path = run_dir / "state.json"
    d.executor = executor
    d.caps_path = None
    d.audit_path = tmp_path / "audit.jsonl"
    return d


# =====================================================================================
# Détection des cibles — méthodes pures
# =====================================================================================

def test_p1_beta_cible_art_uniquement(tmp_path):
    run_dir = _copy_p1_beta(tmp_path)
    dq = _load_dq(run_dir)
    d = _driver(run_dir, tmp_path)
    targets = d._micro_redeclaration_targets(dq)
    assert targets == ["ART"]


def test_declaration_deja_posterieure_pas_de_cible(tmp_path):
    """(2) : la déclaration d'ART est postérieure (round 3) aux réponses reçues
    (round 2) -- pas de re-déclaration."""
    run_dir = _copy_p1_beta(tmp_path)
    dq = _load_dq(run_dir)
    dq["declarations"]["ART"]["round"] = 3
    d = _driver(run_dir, tmp_path)
    targets = d._micro_redeclaration_targets(dq)
    assert "ART" not in targets


def test_questions_bloquantes_non_repondues_pas_de_cible(tmp_path):
    """(1) : une question bloquante impliquant ART reste sans réponse -- pas de
    re-déclaration tant qu'elle n'est pas fermée."""
    run_dir = _copy_p1_beta(tmp_path)
    dq = _load_dq(run_dir)
    for q in dq["questions"]:
        if q["id"] == "q_art_001":
            q["answer"] = None
    d = _driver(run_dir, tmp_path)
    targets = d._micro_redeclaration_targets(dq)
    assert "ART" not in targets


def test_gm_jamais_cible_dans_p1_beta(tmp_path):
    """GM répond toujours EN DERNIER dans le round (topologie fixe) -- une
    réponse round N à une question de GM est nécessairement déjà visible
    quand GM déclare round N. p1_beta n'a d'ailleurs aucune question FROM=GM."""
    run_dir = _copy_p1_beta(tmp_path)
    dq = _load_dq(run_dir)
    d = _driver(run_dir, tmp_path)
    targets = d._micro_redeclaration_targets(dq)
    assert "GM" not in targets


def test_helpers_purs_p1_beta(tmp_path):
    run_dir = _copy_p1_beta(tmp_path)
    dq = _load_dq(run_dir)
    questions = dq["questions"]
    assert ForgeDriver._pillar_blocking_involved_all_answered(questions, "ART") is True
    assert ForgeDriver._max_answer_round_from(questions, "ART") == 2
    assert ForgeDriver._max_answer_round_from(questions, "GM") is None
    assert ForgeDriver._declaration_round(dq["declarations"], "ART") == 2


# =====================================================================================
# C2 — spawn RÉEL (exécuteur mocké, prepare_dispatch/spawn/reçu authentiques)
# =====================================================================================

def _stub_executor_ok(calls):
    def executor(payload, decision, context):
        calls.append({"etape": payload.etape, "context": context, "payload": payload})
        return {
            "ok": True,
            "output": "```design_questions\n{\"schema_version\": 1}\n```",
            "tokens": 42, "duration_s": 1.0, "cost_usd": 0.0,
            "cache_creation_tokens": 0, "cache_read_tokens": 0,
        }
    return executor


def test_run_micro_redeclaration_appelle_un_vrai_spawn(tmp_path):
    run_dir = _copy_p1_beta(tmp_path)
    calls: list = []
    d = _driver(run_dir, tmp_path, executor=_stub_executor_ok(calls))
    state = {"steps": {}, "model_override": None}

    result = d._run_micro_redeclaration(state, "ART")

    assert result["ok"] is True
    assert result["etape"] == "s2.5-artbible-r3"  # round doc (2) + 1, jamais une 3e ronde générale
    # (a) prepare_dispatch a RÉELLEMENT tourné : la ligne dispatch du Context
    # Manifest existe sur disque (écrite par forge.dispatch.prepare_dispatch,
    # jamais par le driver lui-même).
    manifest_path = run_dir / "context" / "s2.5-artbible-r3.manifest.jsonl"
    assert manifest_path.is_file()
    lignes = [json.loads(l) for l in manifest_path.read_text(encoding="utf-8").splitlines()]
    assert any(l.get("kind") == "dispatch" for l in lignes)
    # (b) l'exécuteur (mocké) a bien été appelé, UNE fois, sur l'alias r3.
    assert len(calls) == 1
    assert calls[0]["etape"] == "s2.5-artbible-r3"
    # (c) son propre reçu (spawn_link) existe, distinct de toute autre étape.
    links_path = run_dir / "context" / "spawn_links.jsonl"
    assert links_path.is_file()
    links = [json.loads(l) for l in links_path.read_text(encoding="utf-8").splitlines()]
    mine = [l for l in links if l["etape"] == "s2.5-artbible-r3"]
    assert len(mine) == 1
    assert mine[0]["status"] == "OK"
    assert mine[0]["run_id"] == "p1_beta-20260830-run1"
    # (d) son propre artefact texte, distinct des artefacts existants.
    artifact_path = run_dir / "artifacts" / "s2.5-artbible-r3.txt"
    assert artifact_path.is_file()


def _links_for_etape(run_dir: Path, etape: str) -> list[dict]:
    path = run_dir / "context" / "spawn_links.jsonl"
    if not path.exists():
        return []
    lignes = [json.loads(l) for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]
    return [l for l in lignes if l.get("etape") == etape]


def test_run_micro_redeclaration_executeur_absent_jamais_de_faux_succes(tmp_path):
    run_dir = _copy_p1_beta(tmp_path)
    d = _driver(run_dir, tmp_path, executor=None)
    result = d._run_micro_redeclaration({"steps": {}}, "ART")
    assert result["ok"] is False
    # AUCUN reçu de spawn n'a pu être écrit pour CETTE micro-étape -- rien n'a
    # tourné (aucun exécuteur), rien ne le prétend. Le fichier peut déjà
    # contenir des lignes HISTORIQUES du run réel copié (p1_beta) — seule
    # compte l'ABSENCE d'une ligne pour l'alias r3 qui n'a jamais tourné.
    assert _links_for_etape(run_dir, "s2.5-artbible-r3") == []
    assert not (run_dir / "artifacts" / "s2.5-artbible-r3.txt").exists()


def test_run_micro_redeclaration_executeur_en_echec_reste_honnete(tmp_path):
    run_dir = _copy_p1_beta(tmp_path)

    def executor(payload, decision, context):
        return {"ok": False, "reason": "timeout"}

    d = _driver(run_dir, tmp_path, executor=executor)
    result = d._run_micro_redeclaration({"steps": {}}, "ART")
    assert result["ok"] is False
    assert result["reason"] == "timeout"
    mine = _links_for_etape(run_dir, "s2.5-artbible-r3")
    assert len(mine) == 1
    assert mine[0]["status"] == "HALTED"
    # spawn_authorized/spawn_executed ont quand même été écrits (preuve d'action
    # AVANT jugement, même discipline que le run loop principal) -- mais jamais
    # d'artefact texte (l'exécuteur a échoué, aucune sortie à persister).
    assert not (run_dir / "artifacts" / "s2.5-artbible-r3.txt").exists()


# =====================================================================================
# Point d'appel `_maybe_run_micro_redeclarations` — no-op garanti
# =====================================================================================

def test_maybe_run_micro_redeclarations_noop_si_design_loop_inactif(tmp_path):
    run_dir = _copy_p1_beta(tmp_path)
    calls: list = []
    d = _driver(run_dir, tmp_path, executor=_stub_executor_ok(calls))
    d.order = ["s9-build", "s10a-oracle-code", "s12-verdict"]  # pas de boucle Art<->GM
    d._maybe_run_micro_redeclarations({"steps": {}})
    assert calls == []


def test_maybe_run_micro_redeclarations_noop_si_design_questions_absent(tmp_path):
    run_dir = tmp_path / "run_vide"
    run_dir.mkdir()
    calls: list = []
    d = _driver(run_dir, tmp_path, executor=_stub_executor_ok(calls))
    d._maybe_run_micro_redeclarations({"steps": {}})
    assert calls == []


def test_maybe_run_micro_redeclarations_declenche_pour_p1_beta(tmp_path):
    run_dir = _copy_p1_beta(tmp_path)
    calls: list = []
    d = _driver(run_dir, tmp_path, executor=_stub_executor_ok(calls))
    d._maybe_run_micro_redeclarations({"steps": {}, "model_override": None})
    assert len(calls) == 1
    assert calls[0]["etape"] == "s2.5-artbible-r3"
