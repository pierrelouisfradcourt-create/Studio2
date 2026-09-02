"""Cycle de vie complet d'une lecon (P1) + porte de ratification commune (P3) + Qwen (P2).

CANDIDATE -> VALIDATED -> contrainte -> mesure de l'effet -> APPLIED | REFUTED

Tous les tests operent sur un LESSONS_DIR JETABLE. Aucune ratification n'est ecrite
dans l'etat reel du depot, et les signataires sont explicitement fictifs.
"""
from __future__ import annotations

import json
from pathlib import Path

import pytest

from forge.asset_producer import analyze_batch as AB
from forge.asset_producer import qwen_spec as QS

REPO = Path(__file__).resolve().parents[2]

LID = "asset.chest_exige_declaration_variantes"


def _lecon(**over):
    base = {
        "schema_version": "1.0", "lesson_id": LID, "batch_id": "lot-test",
        "asset_type": "chest", "generation": 1,
        "defauts_detectes": [{"oracle": "oracle.py", "check": "all_meshes_declared",
                              "verdict": "BLOCKED", "assets": ["gen_chest_01"]}],
        "cause_racine": {"couche": "spec", "enonce": "variantes non declarees en amont"},
        "correction_recommandee": {"cible": "spec", "action": "exiger variants"},
        "impact_prochain_lot": {"change": "refus", "verification": "dispatcher",
                                "attendu": "BLOCKED · SPEC_VIOLATES_BATCH_CONSTRAINT"},
        "verification_mecanique": {"kind": "dispatch_blocked", "archetype": "chest",
                                   "expected_reason": "SPEC_VIOLATES_BATCH_CONSTRAINT"},
        "status": AB.STATUS_CANDIDATE,
    }
    base.update(over)
    return base


@pytest.fixture
def bac_a_sable(tmp_path, monkeypatch):
    d = tmp_path / "lessons"
    d.mkdir()
    monkeypatch.setattr(AB, "LESSONS_DIR", d)
    monkeypatch.setattr(AB, "CONSTRAINTS_PATH", d / "batch_constraints.json")
    monkeypatch.setattr(AB, "RESULTS_PATH", tmp_path / "asset_results.jsonl")
    (d / f"{LID}.json").write_text(json.dumps(_lecon()), encoding="utf-8")
    return tmp_path


# ------------------------------------------------- la signature : reel vs bac a sable

def test_simulation_autorisee_en_bac_a_sable(bac_a_sable):
    """Simuler une signature est la MANIERE CORRECTE de tester la boucle."""
    l = AB.valider(LID, "operateur-fictif-1")
    assert l["status"] == AB.STATUS_VALIDATED
    assert l["validated_at_ts"] > 0, "sans horodatage, l'effet se mesurerait retroactivement"


def test_simulation_refusee_dans_l_etat_reel(monkeypatch):
    """La regle porte sur l'etat REEL du depot, pas sur le geste en soi."""
    monkeypatch.setattr(AB, "LESSONS_DIR", AB.LESSONS_DIR_REEL)
    assert AB._dans_l_etat_reel() is True
    with pytest.raises(ValueError, match="etat reel"):
        AB.valider("asset.peu_importe", "utilisateur-de-test")


# ------------------------------------------------- P1 : mesure de l'effet

def test_sans_run_posterieur_on_ne_conclut_pas(bac_a_sable):
    """INSUFFICIENT_DATA est un verdict a part entiere : ni APPLIED, ni REFUTED."""
    l = AB.valider(LID, "operateur-fictif-2")
    m = AB.verify_lesson(l, [])
    assert m["verdict"] == "INSUFFICIENT_DATA"
    assert m["n_runs"] == 0


def test_effet_observe_donne_APPLIED(bac_a_sable):
    l = AB.valider(LID, "operateur-fictif-3")
    ts = l["validated_at_ts"]
    runs = [{"archetype": "chest", "reason": "SPEC_VIOLATES_BATCH_CONSTRAINT", "ts": ts + 10}]
    assert AB.verify_lesson(l, runs)["verdict"] == AB.STATUS_APPLIED


def test_effet_absent_donne_REFUTED(bac_a_sable):
    """Contre-epreuve : une lecon qui ne peut pas etre refutee n'apprend rien."""
    l = AB.valider(LID, "operateur-fictif-4")
    ts = l["validated_at_ts"]
    runs = [{"archetype": "chest", "oracle_verdict": "OK", "reason": None, "ts": ts + 10}]
    assert AB.verify_lesson(l, runs)["verdict"] == AB.STATUS_REFUTED


def test_les_runs_ANTERIEURS_ne_comptent_pas(bac_a_sable):
    """Sinon une lecon se confirmerait retroactivement avec les runs qui l'ont motivee."""
    l = AB.valider(LID, "operateur-fictif-5")
    ts = l["validated_at_ts"]
    runs = [{"archetype": "chest", "reason": "SPEC_VIOLATES_BATCH_CONSTRAINT", "ts": ts - 100}]
    assert AB.verify_lesson(l, runs)["verdict"] == "INSUFFICIENT_DATA"


def test_une_lecon_non_ratifiee_ne_peut_pas_etre_classee(bac_a_sable):
    with pytest.raises(ValueError, match="VALIDATED"):
        AB.classer(LID)


def test_APPLIED_conserve_la_contrainte_REFUTED_la_retire(bac_a_sable):
    """Retirer la contrainte d'une lecon qui a MARCHE reintroduirait le defaut."""
    l = AB.valider(LID, "operateur-fictif-6")
    assert AB.load_constraints()["require_variants_declared"] == ["chest"]

    p = AB.LESSONS_DIR / f"{LID}.json"
    l["status"] = AB.STATUS_APPLIED
    p.write_text(json.dumps(l), encoding="utf-8")
    AB.refresh_constraints()
    assert AB.load_constraints()["require_variants_declared"] == ["chest"]

    l["status"] = AB.STATUS_REFUTED
    p.write_text(json.dumps(l), encoding="utf-8")
    AB.refresh_constraints()
    assert AB.load_constraints()["require_variants_declared"] == []


def test_classer_fige_le_verdict_dans_la_lecon(bac_a_sable):
    l = AB.valider(LID, "operateur-fictif-7")
    ts = l["validated_at_ts"]
    AB.RESULTS_PATH.write_text(json.dumps({
        "archetype": "chest", "reason": "SPEC_VIOLATES_BATCH_CONSTRAINT", "ts": ts + 5,
    }) + "\n", encoding="utf-8")
    out = AB.classer(LID)
    assert out["status"] == AB.STATUS_APPLIED
    assert out["verification_result"]["n_runs"] == 1


# ------------------------------------------------- P3 : porte de ratification commune

def test_une_lecon_devient_une_proposition_du_meme_schema(bac_a_sable, tmp_path, monkeypatch):
    yaml = pytest.importorskip("yaml")
    monkeypatch.setattr(AB, "PROPOSALS_DIR", tmp_path / "proposals")
    out = AB.propose_lesson(LID)
    rec = yaml.safe_load(out.read_text(encoding="utf-8"))

    assert rec["schema"] == "kb.proposal.v1", "meme artefact que toute autre proposition"
    assert rec["status"] == "PROPOSED"
    assert rec["ratification"]["decideur"] is None
    assert rec["entree_catalogue_proposee"]["entry_type"] == "brick"
    assert rec["entree_catalogue_proposee"]["brick_id"].startswith("pat-")
    assert rec["preuve"]["verification_mecanique"]["kind"] == "dispatch_blocked"
    assert "--ratifie-par" in rec["ratification"]["commande"]


# ------------------------------------------------- P2 : gardes du worker Qwen

@pytest.mark.parametrize("spec,motif", [
    ({"asset_id": "gen_x", "archetype": "spaceship", "category": "prop",
      "size": {"w": 1, "d": 1, "h": 1}, "variants": [], "consumer": ["x"]},
     "archetype hors liste"),
    ({"asset_id": "gen_x", "archetype": "crate", "category": "truc",
      "size": {"w": 1, "d": 1, "h": 1}, "variants": [], "consumer": ["x"]},
     "category hors liste"),
    ({"asset_id": "gen_x", "archetype": "crate", "category": "prop",
      "size": {"w": 1, "d": 1, "h": 1}, "variants": [], "consumer": []},
     "consumer"),
    ({"asset_id": "gen_x", "archetype": "crate", "category": "prop",
      "size": {"w": 40, "d": 1, "h": 1}, "variants": [], "consumer": ["x"]},
     "hors bornes"),
    ({"asset_id": "gen_x", "archetype": "crate", "category": "prop",
      "size": {"w": 1, "d": 1, "h": 1}, "consumer": ["x"]},
     "variants absent"),
])
def test_qwen_ne_decide_jamais_seul(spec, motif):
    """Le modele propose ; les enumerations fermees disposent. Aucun repli silencieux."""
    errs = QS.validate_spec(spec)
    assert errs, f"cette spec aurait du etre rejetee ({motif})"
    assert any(motif.split()[0] in e for e in errs), errs


def test_une_spec_conforme_passe():
    assert QS.validate_spec({
        "asset_id": "gen_crate_01", "archetype": "crate", "category": "prop",
        "size": {"w": 0.8, "d": 0.8, "h": 0.8}, "variants": [],
        "consumer": ["obstacle destructible"], "color": [0.5, 0.4, 0.2, 1],
    }) == []


def test_extraction_json_tolere_l_encadrement_du_modele():
    """Qwen encadre parfois sa reponse ; on isole le JSON sans rien reecrire d'autre."""
    d = QS.extract_json('```json\n{"a": 1}\n```')
    assert d == {"a": 1}
    with pytest.raises(QS.QwenError):
        QS.extract_json("je ne sais pas repondre")


def test_le_worker_qwen_est_declare_dans_le_registry():
    """Un worker resolu par le registry, jamais un modele en dur dans le code."""
    yaml = pytest.importorskip("yaml")
    roles = yaml.safe_load((REPO / "forge/contracts/roles.yaml")
                           .read_text(encoding="utf-8"))
    rc = roles["runtime_contracts"]["asset_spec_author"]
    assert rc["implementation"]["entrypoint"].endswith("qwen_spec.py")
    assert rc["limits"]["production_ready"] is False
    assert "no_semantic_check" in rc["limits"], \
        "la limite mesuree (archetype non verifie semantiquement) doit rester ecrite"
    assert any("asset_spec_author" in (m.get("roles") or [])
               for m in roles["models"]), "le role doit etre resolvable par le registry"
