"""Oracle des connecteurs studio de Forge (ADR-002 §3, connecteurs 3/4/5/6).

Tous PROPOSE-ONLY : télémétrie + journal d'erreurs + propositions ledger/projet
écrivent UNIQUEMENT sous EVIDENCE/bundles ou EVIDENCE/reports/forge_* — jamais dans
les mémoires de référence (IMPROVEMENT_LEDGER.yaml, studio_state/projects.json).
"""
import json
from pathlib import Path

from forge import studio_link as sl


def test_global_lesson_reaches_every_project(tmp_path):
    """#4b : une leçon GLOBALE circule vers TOUT projet (ferme le silo par projet)."""
    j = tmp_path / "journal.jsonl"
    sl.record_error("r1", "s10a", "bug spécifique à collect_runner", "collect_runner", journal_path=j)
    sl.record_global_lesson("s10a", "l'oracle DOIT tester la solvabilité", journal_path=j)
    # un AUTRE projet doit voir la leçon globale (mais pas l'erreur spécifique de l'autre)
    pm = sl.premortem("survival_arena", journal_path=j)
    assert any("solvabilité" in x for x in pm), "la leçon globale doit atteindre survival_arena"
    assert not any("spécifique à collect_runner" in x for x in pm)
    # le projet d'origine voit les deux
    pm2 = sl.premortem("collect_runner", journal_path=j)
    assert any("solvabilité" in x for x in pm2)
    assert any("spécifique à collect_runner" in x for x in pm2)


def test_telemetry_records_and_aggregates(tmp_path):
    t = tmp_path / "tel.jsonl"
    sl.record_telemetry("run1", "s0-contrat", "claude-opus-4-8", tokens=1200, duration_s=3.0, telemetry_path=t)
    sl.record_telemetry("run1", "s4-archi", "claude-opus-4-8", tokens=800, duration_s=2.0, telemetry_path=t)
    cost = sl.run_cost("run1", telemetry_path=t)
    assert cost["calls"] == 2
    assert cost["total_tokens"] == 2000
    assert cost["total_duration_s"] == 5.0


# --- M1 — télémétrie d'échec (MISSION_M1_TELEMETRIE_ECHEC.md) ---------------------

def test_telemetry_default_outcome_ok_et_cout_zero_retrocompat(tmp_path):
    """Design imposé M1 pt.1/2 : un appel qui ne précise ni `outcome` ni `cost_usd`
    (signature historique — seul appelant réel avant M1, driver.py) reste
    rétrocompatible : la ligne écrite porte quand même `outcome: "OK"` et
    `cost_usd: 0.0` par défaut, jamais un champ manquant qui ferait planter un
    lecteur qui les attend désormais."""
    t = tmp_path / "tel.jsonl"
    sl.record_telemetry("run1", "s0-contrat", "claude-opus-4-8", tokens=1200, duration_s=3.0, telemetry_path=t)
    rows = [json.loads(l) for l in t.read_text(encoding="utf-8").strip().splitlines()]
    assert rows[0]["outcome"] == "OK"
    assert rows[0]["cost_usd"] == 0.0


def test_telemetry_outcome_halt_et_cout_reel_sont_ecrits(tmp_path):
    """Un échec d'étape (M1, design imposé pt.1) écrit une ligne avec
    `outcome="HALT"` et le coût RÉEL mesuré — même à zéro : un halt AVANT tout
    appel LLM est un ZÉRO MESURÉ, pas une case vide (piège #1 du protocole)."""
    t = tmp_path / "tel.jsonl"
    sl.record_telemetry("run1", "s9-build", "opus", tokens=0, duration_s=0.0,
                        telemetry_path=t, outcome="HALT", cost_usd=0.0)
    rows = [json.loads(l) for l in t.read_text(encoding="utf-8").strip().splitlines()]
    assert rows[0]["outcome"] == "HALT"
    assert rows[0]["cost_usd"] == 0.0
    assert rows[0]["model"] == "opus"


def test_tokens_by_successful_step_ignore_halt_et_normalise_lignes_historiques(tmp_path):
    """La SEULE métrique dérivée nouvelle autorisée par le design imposé (§4) :
    tokens par étape RÉUSSIE, par run — lecture seule. Une ligne HISTORIQUE sans
    `outcome` (toute la télémétrie antérieure à M1) se normalise en "OK" ; une
    ligne `outcome="HALT"` n'est JAMAIS agrégée dans cette métrique de succès."""
    t = tmp_path / "tel.jsonl"
    # ligne historique (pré-M1) : ni `outcome` ni `cost_usd` — format d'avant.
    with open(t, "a", encoding="utf-8") as fh:
        fh.write(json.dumps({"run_id": "run1", "etape": "s0-contrat", "model": "x",
                              "tokens": 100, "duration_s": 1.0, "ts": 0.0}) + "\n")
    sl.record_telemetry("run1", "s9-build", "haiku", tokens=50, duration_s=1.0, telemetry_path=t)
    sl.record_telemetry("run1", "s9-build", "opus", tokens=999, duration_s=1.0,
                        telemetry_path=t, outcome="HALT", cost_usd=0.02)
    out = sl.tokens_by_successful_step("run1", telemetry_path=t)
    assert out["s0-contrat"] == 100     # ligne historique comptée (normalisée OK)
    assert out["s9-build"] == 50        # SEUL le succès compte, jamais le HALT (999 exclu)


def test_error_journal_feeds_premortem(tmp_path):
    j = tmp_path / "err.jsonl"
    sl.record_error("leviathan-1", "s9-build", "oracle rouge : 2 tests échouent", project="leviathan", journal_path=j)
    sl.record_error("other-1", "s4-archi", "cycle de deps détecté", project="autre", journal_path=j)
    pm = sl.premortem("leviathan", journal_path=j)
    assert any("oracle rouge" in x for x in pm)
    assert all("cycle de deps" not in x for x in pm)  # projet différent filtré


def test_propose_ledger_entry_is_audit_required_and_no_claim(tmp_path):
    p = tmp_path / "ledger_prop.jsonl"
    verdict = {"software_verdict": "OK", "evidence_verdict": "MECHANICAL_VALIDATION_ONLY",
               "claim_verdict": "NO_CLAIM_ALLOWED"}
    rec = sl.propose_ledger_entry("leviathan-1", "leviathan", verdict, proposals_path=p)
    assert rec["lane"] == "AUDIT_REQUIRED"
    assert rec["status"] == "PROPOSED"
    assert rec["claim_verdict"] == "NO_CLAIM_ALLOWED"
    on_disk = json.loads(p.read_text(encoding="utf-8").strip())
    assert on_disk["run_id"] == "leviathan-1"


def test_propose_project_record(tmp_path):
    p = tmp_path / "proj_prop.jsonl"
    rec = sl.propose_project_record("leviathan", stage="build", folder="GAMES/leviathan", proposals_path=p)
    assert rec["status"] == "PROPOSED"
    assert rec["project"] == "leviathan"
    assert p.read_text(encoding="utf-8").strip()


# --- Le dépositaire : propose_brick (PROPOSE-ONLY, jamais catalog.json) -----------

def test_propose_brick_is_propose_only_and_never_writes_catalog(tmp_path):
    p = tmp_path / "brick_prop.jsonl"
    rec = sl.propose_brick(
        run_id="shmup_slice-1", project="shmup_slice", brick_id="sys-damage-floor-shield-m01",
        kind="system", function="plancher de degats + bouclier partage",
        path="GAMES/shmup_slice/logic/collisions.mjs", proposals_path=p,
    )
    assert rec["status"] == "PROPOSED"
    assert rec["type"] == "brick"
    assert rec["brick_id"] == "sys-damage-floor-shield-m01"
    assert rec["project"] == "shmup_slice"
    assert rec["path"] == "GAMES/shmup_slice/logic/collisions.mjs"
    on_disk = json.loads(p.read_text(encoding="utf-8").strip())
    assert on_disk["run_id"] == "shmup_slice-1"
    # jamais d'écriture ailleurs que le fichier de propositions explicite
    assert not (tmp_path / "catalog.json").exists()


def test_propose_brick_default_path_is_forge_reports_not_knowledge_base(monkeypatch, tmp_path):
    """La proposition part sous EVIDENCE/reports/ (DEFAULT_BRICK_PROPOSALS), jamais sous
    knowledge_base/ — vérifie le chemin par défaut sans dépendre du disque réel."""
    monkeypatch.setattr(sl, "DEFAULT_BRICK_PROPOSALS", tmp_path / "forge_brick_proposals.jsonl")
    sl.propose_brick(run_id="r1", project="p1", brick_id="b1", kind="system",
                     function="f", path="GAMES/p1/x.mjs")
    assert (tmp_path / "forge_brick_proposals.jsonl").exists()


# --- Tier 2.5 étape 2 : observabilité du pool de builders -------------------------

def test_record_builder_run_and_pool_stats(tmp_path):
    b = tmp_path / "builder_runs.jsonl"
    # 1er essai (haiku) échoue, pool retry (même tier) réussit — le pool sauve la tâche.
    sl.record_builder_run("run1", tier="haiku", builder_id="claude-haiku-4-5-20251001",
                          strategy="tier_attempt", duration_s=2.0, oracle_result="FAIL",
                          retry_number=0, tokens=500, cost_usd=0.01, telemetry_path=b)
    sl.record_builder_run("run1", tier="haiku", builder_id="claude-haiku-4-5-20251001",
                          strategy="pool_retry", duration_s=2.5, oracle_result="OK",
                          retry_number=1, tokens=520, cost_usd=0.012, telemetry_path=b)
    stats = sl.pool_stats("run1", telemetry_path=b)
    assert stats["attempts"] == 2
    assert stats["pool_saves"] == 1
    assert abs(stats["escalations_avoided_cost_usd"] - 0.012) < 1e-9
    assert stats["by_builder"]["claude-haiku-4-5-20251001"] == {"FAIL": 1, "OK": 1}


def test_pool_stats_pool_retry_qui_echoue_aussi_ne_compte_pas_comme_sauve(tmp_path):
    b = tmp_path / "builder_runs.jsonl"
    sl.record_builder_run("run1", tier="haiku", builder_id="haiku", strategy="tier_attempt",
                          duration_s=1.0, oracle_result="FAIL", retry_number=0,
                          tokens=1, cost_usd=0.001, telemetry_path=b)
    sl.record_builder_run("run1", tier="haiku", builder_id="haiku", strategy="pool_retry",
                          duration_s=1.0, oracle_result="FAIL", retry_number=1,
                          tokens=1, cost_usd=0.001, telemetry_path=b)
    stats = sl.pool_stats("run1", telemetry_path=b)
    assert stats["pool_saves"] == 0
    assert stats["escalations_avoided_cost_usd"] == 0.0


def test_pool_stats_by_tier_regroupe_ce_que_by_builder_eclate(tmp_path):
    """`builder_id` n'est PAS normalisé dans la donnée réelle : le driver y met
    `model_override or s9_detail["model"]`, donc l'identifiant COMPLET du registry à
    la 1re tentative et le nom COURT après escalade. Mesuré le 2026-07-23 sur
    `forge_builder_runs.jsonl` : `claude-haiku-4-5-20251001` ET `sonnet`/`opus` dans
    le même fichier. Conséquence : un même tier compte pour deux entités dans
    `by_builder` — statistique silencieusement fausse, pas un crash. `by_tier`
    s'appuie sur le champ `tier`, lui normalisé à l'écriture, et regroupe juste."""
    b = tmp_path / "builder_runs.jsonl"
    # deux tentatives du MÊME tier, écrites avec deux identifiants différents
    sl.record_builder_run("run1", tier="haiku", builder_id="claude-haiku-4-5-20251001",
                          strategy="tier_attempt", duration_s=1.0, oracle_result="FAIL",
                          retry_number=0, tokens=1, cost_usd=0.0, telemetry_path=b)
    sl.record_builder_run("run1", tier="haiku", builder_id="haiku",
                          strategy="pool_retry", duration_s=1.0, oracle_result="FAIL",
                          retry_number=1, tokens=1, cost_usd=0.0, telemetry_path=b)

    stats = sl.pool_stats("run1", telemetry_path=b)

    # by_builder éclate : deux clés pour un seul tier (constat, pas un souhait)
    assert len(stats["by_builder"]) == 2
    # by_tier regroupe : une seule clé, le compte est juste
    assert stats["by_tier"] == {"haiku": {"FAIL": 2}}


def test_pool_stats_filtre_par_run_id(tmp_path):
    b = tmp_path / "builder_runs.jsonl"
    sl.record_builder_run("run1", tier="haiku", builder_id="haiku", strategy="tier_attempt",
                          duration_s=1.0, oracle_result="OK", retry_number=0,
                          tokens=1, cost_usd=0.0, telemetry_path=b)
    sl.record_builder_run("run2", tier="opus", builder_id="opus", strategy="tier_attempt",
                          duration_s=1.0, oracle_result="OK", retry_number=0,
                          tokens=1, cost_usd=0.0, telemetry_path=b)
    assert sl.pool_stats("run1", telemetry_path=b)["attempts"] == 1
    assert sl.pool_stats("run2", telemetry_path=b)["attempts"] == 1


def test_connecteurs_necrivent_aucune_memoire_de_reference():
    """Garde propose-only : le module ne référence jamais en écriture le ledger ni projects.json."""
    src = Path(__file__).resolve().parents[1].joinpath("studio_link.py").read_text(encoding="utf-8")
    assert "IMPROVEMENT_LEDGER" not in src
    assert "projects.json" not in src
    for interdit in ("subprocess", "Popen", "os.system"):
        assert interdit not in src
