"""Lot 1 (plan V2 2026-09-03, GO Pierre) — GAME_BLUEPRINT v0 + importeur déterministe + couverture.

Contrat du lot, en tests, sur la FORME DE PRODUCTION RÉELLE (règle « un test exerce la forme de
production ») : l'entrée est la baseline M ter `EVIDENCE/runs/runm_breakout/` telle qu'elle est
sur disque, jamais un objet fabriqué à la main.

Ce que ces tests prouvent :
  - chaque section importée porte le sha256 EXACT de son fichier source ;
  - la couverture recalculée sur la wiremap de DESIGN (artefact agent s5) reproduit, compteur par
    compteur, le reçu `join_check` SIGNÉ dans state.json (EMPTY_FORM · 10 capacités · 0 couverte) ;
  - la couverture recalculée sur la wiremap CONSTRUITE (wiremap.json, réécrite par le builder)
    rend JOINED 10/10 — un fait que le verdict de la baseline ne porte pas ;
  - le reçu `join_check_apres_reparation` (VOID · 0 couverte · 9 fantômes) est importé comme
    évidence NON RECALCULABLE : sa source a été écrasée en place par s9. C'est le défaut que le
    versionnement de sections du Blueprint existe pour empêcher ;
  - un non-propriétaire n'écrit pas dans une section ; feature_map et wiremap ne se saisissent
    jamais à la main ; questions est append-only ;
  - deux imports rendent le même Blueprint (déterminisme, horodatage exclu).

Ce qu'ils ne prouvent PAS : la valeur du jeu, un Director, une capacité convoquée. NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path

import pytest

from forge import blueprint as bp
from forge.blueprint_import import import_run_dir
from forge.coverage import coverage_of

_REPO_ROOT = Path(__file__).resolve().parents[2]
_RUN_DIR = _REPO_ROOT / "EVIDENCE" / "runs" / "runm_breakout"
_BRIEF = _REPO_ROOT / "EVIDENCE" / "briefs" / "runm_breakout" / "project_brief.yaml"

pytestmark = pytest.mark.skipif(
    not (_RUN_DIR / "state.json").exists() or not _BRIEF.exists(),
    reason="baseline M ter absente — ce lot se prouve sur la forme de production réelle",
)


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


@pytest.fixture(scope="module")
def imported():
    return import_run_dir(_RUN_DIR, brief_path=_BRIEF, project="runm_breakout")


# --- import : sections et provenance --------------------------------------------------------


def test_import_rend_un_blueprint_valide_avec_toutes_les_sections_k1(imported):
    assert bp.validate(imported) == []
    assert set(bp.SECTIONS) <= set(imported["sections"])
    assert imported["schema"] == bp.SCHEMA_ID


def test_chaque_section_importee_porte_le_sha256_exact_de_sa_source(imported):
    attendus = {
        "gameplay": _RUN_DIR / "charter.yaml",
        "feature_map": _RUN_DIR / "featuremap.json",
        "architecture_contract": _RUN_DIR / "blueprint.json",
        "identity": _BRIEF,
        "vision": _BRIEF,
        "constraints": _BRIEF,
    }
    for section, src in attendus.items():
        meta = imported["sections"][section]
        assert meta["source"]["sha256"] == _sha(src), section
        assert meta["source"]["path"].replace("\\", "/").endswith(src.name), section
    und = imported["sections"]["understanding"]["content"]
    assert und["prisme"]["source"]["sha256"] == _sha(_RUN_DIR / "prisme.json")
    assert und["worldscan"]["source"]["sha256"] == _sha(_RUN_DIR / "worldscan.json")
    wm = imported["sections"]["wiremap"]["content"]
    assert wm["built"]["source"]["sha256"] == _sha(_RUN_DIR / "wiremap.json")
    assert wm["design"]["source"]["sha256"] == _sha(_RUN_DIR / "artifacts" / "s5-wiremap.txt")


def test_les_reçus_de_jointure_signes_sont_importes_comme_evidence(imported):
    state = json.loads((_RUN_DIR / "state.json").read_text(encoding="utf-8"))
    detail = state["steps"]["s5-wiremap"]["detail"]
    ev = imported["sections"]["provenance"]["content"]["join_receipts"]
    assert ev["join_check"] == detail["join_check"]
    assert ev["join_check_apres_reparation"] == detail["join_check_apres_reparation"]
    # la source du reçu « après réparation » a été écrasée par s9 : dit, jamais tu
    assert ev["recomputable"] == {"join_check": True, "join_check_apres_reparation": False}


def test_questions_absentes_dans_la_baseline_donnent_une_liste_vide_declaree(imported):
    q = imported["sections"]["questions"]
    assert q["content"] == []
    # le chemin CHERCHÉ est conservé (on sait où l'on a regardé), le statut dit l'absence
    assert q["source"]["status"] == "ABSENT" and q["source"]["sha256"] is None
    assert q["source"]["path"].endswith("design_questions.json")


def test_l_import_est_deterministe_hors_horodatage():
    a = import_run_dir(_RUN_DIR, brief_path=_BRIEF, project="runm_breakout")
    b = import_run_dir(_RUN_DIR, brief_path=_BRIEF, project="runm_breakout")
    for x in (a, b):
        x["imported_at"] = None
    assert json.dumps(a, sort_keys=True) == json.dumps(b, sort_keys=True)


# --- couverture : recalcul par l'oracle de production ---------------------------------------


@pytest.mark.skipif(shutil.which("node") is None, reason="node absent : couverture NOT_MEASURED")
def test_couverture_design_reproduit_le_recu_join_check_signe(imported):
    state = json.loads((_RUN_DIR / "state.json").read_text(encoding="utf-8"))
    recu = state["steps"]["s5-wiremap"]["detail"]["join_check"]
    cov = coverage_of(imported, which="design")
    for k in ("regime", "status", "capacites", "capacites_couvertes", "lignes",
              "lignes_sans_couvre", "capacites_non_couvertes", "couverture_fantome",
              "forme_satisfaite"):
        assert cov[k] == recu[k], k
    assert cov["regime"] == "EMPTY_FORM"


@pytest.mark.skipif(shutil.which("node") is None, reason="node absent : couverture NOT_MEASURED")
def test_couverture_construite_est_jointe_ce_que_le_verdict_ne_dit_pas(imported):
    cov = coverage_of(imported, which="built")
    assert (cov["regime"], cov["capacites"], cov["capacites_couvertes"],
            cov["couverture_fantome"]) == ("JOINED", 10, 10, 0)


def test_la_regle_de_regime_est_celle_de_la_production():
    """Garde anti-divergence : coverage n'a pas sa propre table de régimes."""
    from forge import coverage, run_real
    assert coverage.check_wiremap_join is run_real.check_wiremap_join


# --- propriété des sections -----------------------------------------------------------------


def test_un_non_proprietaire_n_ecrit_pas_dans_une_section(imported):
    with pytest.raises(bp.OwnershipViolation):
        bp.write_section(imported, "vision", {"fantasy": "x"}, writer="architect",
                         source={"path": None, "sha256": None})


def test_feature_map_et_wiremap_ne_se_saisissent_jamais_a_la_main(imported):
    for section in ("feature_map", "wiremap"):
        with pytest.raises(bp.OwnershipViolation):
            bp.write_section(imported, section, {"features": []}, writer="pierre",
                             source={"path": None, "sha256": None})


def test_questions_est_append_only(imported):
    b = json.loads(json.dumps(imported))
    bp.write_section(b, "questions", [{"id": "q1", "from": "ART", "to": "GM"}],
                     writer="art_director", source={"path": None, "sha256": None})
    with pytest.raises(bp.AppendOnlyViolation):
        bp.write_section(b, "questions", [], writer="game_master",
                         source={"path": None, "sha256": None})
    assert b["sections"]["questions"]["version"] == imported["sections"]["questions"]["version"] + 1


def test_ecrire_une_section_incremente_sa_version_et_journalise_l_ecrivain(imported):
    b = json.loads(json.dumps(imported))
    v0 = b["sections"]["gameplay"]["version"]
    bp.write_section(b, "gameplay", {"objectif": "x"}, writer="contract_author",
                     source={"path": None, "sha256": None})
    s = b["sections"]["gameplay"]
    assert s["version"] == v0 + 1 and s["writer"] == "contract_author"
    assert s["content_sha256"] == bp.content_sha256({"objectif": "x"})
