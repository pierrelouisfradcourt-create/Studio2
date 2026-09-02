"""Oracle de MISSION_M1_TELEMETRIE_ECHEC.md — télémétrie d'échec.

Aujourd'hui (avant ce fichier) un échec d'étape ne produit AUCUNE ligne de
télémétrie (`record_telemetry` n'est appelé qu'après `entry["status"] = "OK"`,
`_halt_step` retourne avant) : coût invisible, modèle jamais résolu vers
l'override d'escalade. Design imposé (non redessiné ici) :

  1. Télémétrie écrite AUSSI sur `_halt_step`, avec `outcome: "OK" | "HALT"`.
  2. `cost_usd` ajouté à `record_telemetry` (paramètre optionnel rétrocompatible).
  3. `model` porte le modèle RÉELLEMENT exécuté : `state.model_override or
     payload.model` — même résolution que le journal (driver.py ~l.480).
  4. Aucune métrique nouvelle au-delà de « tokens par étape réussie, par run »
     (studio_link.tokens_by_successful_step, testé dans test_studio_link.py).

ADVISORY STRICT : ces tests ne touchent qu'à l'OBSERVATION (télémétrie) —
aucun verdict, aucun gate, aucun comportement de run n'est vérifié différent
d'avant (les assertions sur `report["status"]`/`software_verdict` sont
IDENTIQUES aux tests homologues de test_driver.py, seule la télémétrie est
neuve). NO_CLAIM_ALLOWED.
"""
import json
import sys
from pathlib import Path

import pytest

from forge.driver import ForgeDriver
from forge.escalate import tier_of


# --- utilitaires (autonomes : ne dépendent d'aucun autre fichier de test, même
# convention que test_driver_journal_autowire.py / test_driver_mutation.py) -------

def _oracle_config(tmp_path, project, exit_code=0):
    """Config oracle témoin : une commande python qui sort avec exit_code."""
    cfg = tmp_path / "oracles_test.json"
    cfg.write_text(
        json.dumps({project: {
            "cwd": str(tmp_path),
            "command": [sys.executable, "-c", f"import sys; sys.exit({exit_code})"],
        }}),
        encoding="utf-8",
    )
    return cfg


def _kwargs(tmp_path, run_dir, project="proj", exit_code=0):
    """Paramètres communs — tout est redirigé sous tmp_path (zéro pollution repo)."""
    return dict(
        run_dir=run_dir,
        oracle_config=_oracle_config(tmp_path, project, exit_code),
        key_file=tmp_path / "forge_test.key",
        audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        builder_runs_path=tmp_path / "builder_runs.jsonl",
    )


def _rows(path: Path) -> list[dict]:
    if not path.exists():
        return []
    return [json.loads(l) for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]


class StubExecutor:
    """Exécuteur LLM factice : trace les appels, rend un artefact ok (même
    contrat que StubExecutor de test_driver.py, réimplémenté ici — convention
    des fichiers de test driver_* du dépôt : chaque fichier est autonome)."""

    def __init__(self, run_dir=None, fail_on=()):
        self.calls = []
        self.run_dir = run_dir
        self.fail_on = set(fail_on)

    def __call__(self, payload, decision, context):
        self.calls.append((payload.etape, context.get("model_override")))
        if payload.etape in self.fail_on:
            return {"ok": False, "output": "", "reason": "échec simulé"}
        return {"ok": True, "output": f"artefact {payload.etape}"}


@pytest.fixture
def offline(monkeypatch):
    """Offline strict : aucune sonde LM Studio pendant les tests du driver."""
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


# --- (a) un run avec >=1 échec produit >=1 ligne outcome:HALT --------------------

def test_halt_sans_executeur_ecrit_telemetrie_outcome_halt_tokens_zero_mesure(tmp_path, offline):
    """Cas limite du protocole : halt AVANT tout appel LLM (aucun exécuteur
    fourni) — tokens=0 est un ZÉRO MESURÉ (aucun appel n'a eu lieu), pas une
    case vide : la ligne existe quand même."""
    run_dir = tmp_path / "run"
    kw = _kwargs(tmp_path, run_dir)
    report = ForgeDriver("proj", "proj-1", profile="micro", executor=None, **kw).run()
    assert report["status"] == "HALTED"  # comportement de run INCHANGÉ

    rows = _rows(kw["telemetry_path"])
    halt_rows = [r for r in rows if r["outcome"] == "HALT"]
    assert len(halt_rows) == 1
    row = halt_rows[0]
    assert row["etape"] == "s9-build"
    assert row["tokens"] == 0
    assert row["cost_usd"] == 0.0
    assert row["model"]  # résolu depuis payload.model (contrat connu, model_override absent)


def test_halt_executeur_en_echec_ecrit_telemetrie_outcome_halt(tmp_path, offline):
    """L'exécuteur a tourné et rendu `ok: False` (sans rapporter de tokens) —
    la ligne HALT existe quand même, tokens=0 (rien de rapporté)."""
    run_dir = tmp_path / "run"
    ex = StubExecutor(run_dir=run_dir, fail_on={"s9-build"})
    kw = _kwargs(tmp_path, run_dir)
    report = ForgeDriver("proj", "proj-1", profile="micro", executor=ex, **kw).run()
    assert report["status"] == "HALTED"

    rows = _rows(kw["telemetry_path"])
    halt_rows = [r for r in rows if r["outcome"] == "HALT"]
    assert len(halt_rows) == 1
    assert halt_rows[0]["etape"] == "s9-build"
    assert halt_rows[0]["tokens"] == 0


def test_halt_avec_cout_partiel_mesure_avant_l_echec_est_conserve(tmp_path, offline):
    """Cas limite : l'exécuteur a RÉELLEMENT tourné avant d'échouer (timeout
    claude -p, FIR-01 — run_real.py) : `duration_s` est connu, `tokens`/
    `cost_usd` non rapportés (l'usage n'est jamais parsé sur un timeout). La
    ligne HALT porte ce qui a été MESURÉ, jamais un silence total."""

    class TimeoutExecutor:
        def __call__(self, payload, decision, context):
            return {"ok": False, "timeout": True, "duration_s": 42.5,
                    "reason": "claude -p timeout (600s) — arbre tué (FIR-01)"}

    run_dir = tmp_path / "run"
    kw = _kwargs(tmp_path, run_dir)
    report = ForgeDriver("proj", "proj-1", profile="micro",
                         executor=TimeoutExecutor(), **kw).run()
    assert report["status"] == "HALTED"

    rows = _rows(kw["telemetry_path"])
    halt_rows = [r for r in rows if r["outcome"] == "HALT"]
    assert len(halt_rows) == 1
    assert halt_rows[0]["duration_s"] == 42.5
    assert halt_rows[0]["tokens"] == 0  # non rapporté par l'exécuteur -> zéro


def test_double_halt_ecrit_deux_lignes_independantes(tmp_path, offline):
    """Cas limite « double halt » : deux invocations de .run() sur le MÊME run
    interrompu (reprise) écrivent chacune leur ligne — jamais de déduplication
    ni d'écrasement (append-only)."""
    run_dir = tmp_path / "run"
    kw = _kwargs(tmp_path, run_dir)
    ForgeDriver("proj", "proj-1", profile="micro", executor=None, **kw).run()
    ForgeDriver("proj", "proj-1", profile="micro", executor=None, **kw).run()

    rows = _rows(kw["telemetry_path"])
    halt_rows = [r for r in rows if r["outcome"] == "HALT"]
    assert len(halt_rows) == 2


# --- (b) somme tokens d'un run >= valeur pré-patch --------------------------------

def test_somme_tokens_dun_run_avec_echec_est_superieure_ou_egale_au_seul_succes(tmp_path, offline):
    """(b) RUN_INDEX M1 : un run avec un échec MESURÉ (500 tokens consommés
    avant le halt, cas FIR-01 réel) puis repris avec succès. AVANT ce
    correctif, ces 500 tokens auraient été invisibles (comme les 187 267
    tokens shmup cités par la mission) : `run_cost` les inclut désormais."""
    run_dir = tmp_path / "run"
    kw = _kwargs(tmp_path, run_dir)

    class FailingExecutor:
        def __call__(self, payload, decision, context):
            return {"ok": False, "tokens": 500, "duration_s": 10.0,
                    "cost_usd": 0.01, "reason": "échec simulé mesuré"}

    report1 = ForgeDriver("proj", "proj-1", profile="micro",
                          executor=FailingExecutor(), **kw).run()
    assert report1["status"] == "HALTED"

    ex2 = StubExecutor(run_dir=run_dir)
    report2 = ForgeDriver("proj", "proj-1", profile="micro", executor=ex2, **kw).run()
    assert report2["status"] == "DONE"

    from forge.studio_link import run_cost
    cost = run_cost("proj-1", telemetry_path=kw["telemetry_path"])
    assert cost["total_tokens"] >= 500

    rows = _rows(kw["telemetry_path"])
    outcomes = {r["outcome"] for r in rows}
    assert "HALT" in outcomes
    assert "OK" in outcomes


# --- (c) résolution du modèle RÉELLEMENT exécuté (design imposé pt.3) ------------

def test_escalade_le_champ_model_de_la_telemetrie_suit_le_modele_reellement_execute(tmp_path, offline):
    """Même scénario que test_escalade_bornee_sur_oracle_rouge (test_driver.py) :
    oracle rouge -> pool épuisé (pool_size=2 par défaut) -> sonnet -> opus. Le
    champ `model` des lignes de télémétrie s9-build suit state.model_override,
    JAMAIS le seul payload.model (constant, celui du contrat) — preuve EN
    DIRECT (pas seulement rétroactive) du design imposé pt.3."""
    run_dir = tmp_path / "run"
    ex = StubExecutor(run_dir=run_dir)
    kw = _kwargs(tmp_path, run_dir, exit_code=1)  # oracle toujours rouge
    report = ForgeDriver("proj", "proj-1", profile="micro", executor=ex, **kw).run()
    assert report["software_verdict"] == "FAIL"  # échec signé, comportement inchangé

    rows = _rows(kw["telemetry_path"])
    s9_rows = [r for r in rows if r["etape"] == "s9-build"]
    models = [r["model"] for r in s9_rows]
    assert len(models) == 6  # 2 essais x 3 tiers (contrat, sonnet, opus)
    assert models[0] == models[1]
    assert models[0] not in ("sonnet", "opus")  # jamais confondu avec l'override
    assert models[2:4] == ["sonnet", "sonnet"]
    assert models[4:6] == ["opus", "opus"]
    assert tier_of(models[4]) == "opus"


def test_retroactif_shmup_resolution_modele_aurait_dit_opus_pas_haiku():
    """(c) RUN_INDEX M1 — test rétroactif à COÛT NUL sur les données RÉELLEMENT
    archivées du run shmup_slice (EVIDENCE/runs/shmup_slice/state.json, run
    réel avec escalade jusqu'à opus). Rejoue la MÊME formule de résolution que
    le driver (`state.model_override or payload.model`, driver.py ~l.480 et
    l'appel corrigé de record_telemetry) sur le detail ARCHIVÉ de s9-build :
    AVANT ce correctif la télémétrie aurait porté "claude-haiku-4-5-20251001"
    (payload.model, le contrat) — la ligne AURAIT DÛ dire "opus" (le modèle
    réellement exécuté après escalade). Aucun appel LLM : lecture seule d'un
    artefact déjà sur disque (coût nul)."""
    repo_root = Path(__file__).resolve().parents[2]
    state_path = repo_root / "EVIDENCE" / "runs" / "shmup_slice" / "state.json"
    if not state_path.exists():
        pytest.skip("archive shmup_slice absente de ce poste (lecture best-effort)")
    state = json.loads(state_path.read_text(encoding="utf-8"))
    s9_detail = state["steps"]["s9-build"]["detail"]

    # AVANT M1 : la télémétrie enregistrait `reviewer` (== payload.model pour le
    # runner claude non-qwen, forge/runtime.py route_step l.92) — sur CE run
    # c'est très exactement `detail["model"]`, jamais l'override.
    avant = s9_detail["model"]
    assert avant == "claude-haiku-4-5-20251001", (
        "prémisse de l'archive modifiée depuis l'audit du 2026-07-26 — "
        "le test rétroactif n'a plus de sens, à réviser")

    # APRÈS M1 : state.get("model_override") or payload.model (payload.model
    # == detail["model"], le modèle du CONTRAT — jamais réécrit après coup).
    apres = s9_detail.get("model_override") or s9_detail["model"]
    assert apres == "opus"
    assert apres != avant, "la ligne aurait dû changer : opus, pas haiku"
    assert tier_of(avant) == "haiku"
    assert tier_of(apres) == "opus"


# --- cas limite : exception dans l'exécuteur (comportement INCHANGÉ) ------------

def test_exception_executeur_propage_sans_telemetrie_ni_changement_de_comportement(tmp_path, offline):
    """Cas limite explicite du protocole M1 : une exception LEVÉE par
    l'exécuteur (interruption, même scénario que
    test_resume_ne_rejoue_pas_les_etapes_terminees de test_driver.py) N'EST
    PAS un HALT du driver — elle se propage TELLE QUELLE (comportement de run
    INCHANGÉ, garde-fou advisory strict : l'observation ne doit jamais
    modifier le comportement). Aucune ligne de télémétrie n'est écrite pour
    cette tentative interrompue : ni `_halt_step` ni le chemin succès de
    `_run_llm` ne sont atteints."""

    class RaisingExecutor:
        def __call__(self, payload, decision, context):
            raise RuntimeError("interruption simulée")

    run_dir = tmp_path / "run"
    kw = _kwargs(tmp_path, run_dir)
    with pytest.raises(RuntimeError):
        ForgeDriver("proj", "proj-1", profile="micro",
                    executor=RaisingExecutor(), **kw).run()

    assert not kw["telemetry_path"].exists()
    state = json.loads((run_dir / "state.json").read_text(encoding="utf-8"))
    assert state["steps"]["s9-build"]["status"] == "RUNNING"  # interrompue, pas HALTED


# --- cas limite : échec d'écriture télémétrie avalé (jamais bloquant) -----------

def test_echec_ecriture_telemetrie_avale_sur_le_chemin_ok(tmp_path, offline, monkeypatch):
    """Garde-fou #2 : l'écriture télémétrie reste best-effort — un
    `record_telemetry` qui lève ne doit JAMAIS faire échouer un run qui a
    réussi, y compris avec le nouveau chemin (outcome/cost_usd)."""
    import forge.driver as driver_mod

    def _raise(*a, **k):
        raise OSError("disque plein (simulé)")

    monkeypatch.setattr(driver_mod, "record_telemetry", _raise)
    run_dir = tmp_path / "run"
    ex = StubExecutor(run_dir=run_dir)
    kw = _kwargs(tmp_path, run_dir)
    report = ForgeDriver("proj", "proj-1", profile="micro", executor=ex, **kw).run()
    assert report["status"] == "DONE"
    assert report["software_verdict"] == "OK"
    assert not kw["telemetry_path"].exists()  # la fonction a levé, rien n'a été écrit


def test_echec_ecriture_telemetrie_avale_sur_le_chemin_halt(tmp_path, offline, monkeypatch):
    """Même garde-fou, sur le chemin HALT (nouveau chemin d'écriture — c'est
    précisément celui que la mission ajoute) : ne doit JAMAIS faire lever le
    driver au-delà du HALT honnête déjà attendu."""
    import forge.driver as driver_mod

    def _raise(*a, **k):
        raise OSError("disque plein (simulé)")

    monkeypatch.setattr(driver_mod, "record_telemetry", _raise)
    run_dir = tmp_path / "run"
    kw = _kwargs(tmp_path, run_dir)
    report = ForgeDriver("proj", "proj-1", profile="micro", executor=None, **kw).run()
    assert report["status"] == "HALTED"
    assert not kw["telemetry_path"].exists()
