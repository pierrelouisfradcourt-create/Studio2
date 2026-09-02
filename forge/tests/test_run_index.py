"""Oracle de P4 — ranimer `EVIDENCE/runs/RUN_INDEX.md` en fin de run.

Le fichier s'est déclaré append-only le 2026-07-26 (« une entrée par run,
jamais réécrite ») puis s'est arrêté le 2026-07-28 (dernière entrée
`snake-20260728-091302`, ~41 runs postérieurs absents). Ce lot ajoute
`ForgeDriver._append_run_index_best_effort`, appelée juste après
`_trigger_observer_best_effort` (même point de fin de run).

PÉRIMÈTRE STRICT (verrouillé par Pierre) : run_id · timestamp RÉEL · projet ·
statut · verdict — rien d'autre. Best-effort NON SILENCIEUX (warning journalisé,
jamais bloquant), idempotent sur `run_id` (jamais un numéro de ligne).

Convention des fichiers `test_driver_*` du dépôt : autonome, tout redirigé
sous `tmp_path` (zéro pollution repo). `run_index_path` injecté EXPLICITEMENT
partout dans ce fichier — jamais le vrai `EVIDENCE/runs/RUN_INDEX.md` du
dépôt (contrairement à `journal_path`/`lessons_path`, ce fichier n'a AUCUNE
isolation implicite pour un run_dir hors dépôt, cf. docstring
`_run_index_target`)."""
import json
import sys
from pathlib import Path

import pytest

from forge.driver import ForgeDriver


# --- utilitaires (autonomes, même convention que test_driver_telemetry_outcome.py) --

def _oracle_config(tmp_path, project, exit_code=0):
    cfg = tmp_path / "oracles_test.json"
    cfg.write_text(
        json.dumps({project: {
            "cwd": str(tmp_path),
            "command": [sys.executable, "-c", f"import sys; sys.exit({exit_code})"],
        }}),
        encoding="utf-8",
    )
    return cfg


def _kwargs(tmp_path, run_dir, project="proj", exit_code=0, run_index_path=None):
    return dict(
        run_dir=run_dir,
        oracle_config=_oracle_config(tmp_path, project, exit_code),
        key_file=tmp_path / "forge_test.key",
        audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        builder_runs_path=tmp_path / "builder_runs.jsonl",
        run_index_path=run_index_path if run_index_path is not None else (tmp_path / "RUN_INDEX.md"),
    )


class StubExecutor:
    """Exécuteur LLM factice — même contrat que StubExecutor de
    test_driver_telemetry_outcome.py (réimplémenté ici, convention du dépôt :
    chaque fichier de test driver_* est autonome)."""

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


# --- (a) run DONE => entrée créée avec les 5 champs -------------------------------

def test_run_done_ecrit_une_entree_run_index_avec_les_5_champs(tmp_path, offline):
    run_dir = tmp_path / "run"
    ex = StubExecutor(run_dir=run_dir)
    kw = _kwargs(tmp_path, run_dir, project="proj")
    report = ForgeDriver("proj", "proj-run-a", profile="micro", executor=ex, **kw).run()
    assert report["status"] == "DONE"
    assert report["software_verdict"] == "OK"

    run_index = kw["run_index_path"]
    assert run_index.exists()
    text = run_index.read_text(encoding="utf-8")

    # en-tête EXACT réutilisé du format existant : "## <run_id> — <date>"
    assert "## proj-run-a —" in text
    # les 5 champs verrouillés : run_id (en-tête) + projet + statut + verdict + ts
    assert "projet=proj" in text
    assert "statut=DONE" in text
    assert "verdict=OK" in text
    assert "ts=" in text
    # ISO 8601 UTC — timestamp RÉEL, pas un placeholder
    import re
    assert re.search(r"ts=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", text)


def test_run_halted_ecrit_aussi_une_entree_avec_statut_et_verdict_reels(tmp_path, offline):
    """Le périmètre ne restreint pas aux runs DONE : le report existe (verdict
    BLOCKED) dès qu'un run se termine (idempotent DONE ou HALTED) — l'entrée
    porte le statut/verdict RÉELLEMENT produits, jamais un succès inventé.

    R1''' (GO Pierre 2026-08-14 ; amendement de zone protégée sous gate explicite
    le même jour) : ce test documentait jusqu'ici l'ABSENCE d'entrée sur le chemin
    HALTED — son corps affirmait `not run_index.exists()` alors que son NOM promet
    l'inverse. `_append_run_index_best_effort` n'avait qu'un appelant, sur le chemin
    DONE : le registre des runs ne connaissait que les succès. Mesure qui a motivé
    la réparation : `p1_3_exclusivity` — le run qui a RÉVÉLÉ la panne s2-worldscan —
    portait un state.json sur disque et aucune entrée à l'index. Le driver appelle
    désormais le writer sur le point de sortie HALTED de sa boucle (même patron que
    R1'' pour la promotion des lessons). Le nom du test devient donc exact."""
    run_dir = tmp_path / "run"
    kw = _kwargs(tmp_path, run_dir, project="proj")
    report = ForgeDriver("proj", "proj-run-b", profile="micro", executor=None, **kw).run()
    assert report["status"] == "HALTED"

    run_index = kw["run_index_path"]
    assert run_index.exists()
    text = run_index.read_text(encoding="utf-8")
    # Mêmes 5 champs verrouillés que le chemin DONE — statut/verdict RÉELS,
    # jamais un succès inventé : un run arrêté s'inscrit comme arrêté.
    assert "## proj-run-b —" in text
    assert "projet=proj" in text
    assert "statut=HALTED" in text
    assert "verdict=BLOCKED" in text
    import re
    assert re.search(r"ts=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", text)


# --- (b) rejeu du même run_id => aucun doublon --------------------------------------

def test_rejeu_du_meme_run_id_directement_sur_la_methode_najoute_aucun_doublon(tmp_path, offline):
    """Idempotence sur `run_id`, jamais sur un numéro de ligne : appelle deux
    fois la méthode d'ajout pour LE MÊME run_id (même patron qu'un run rejoué
    depuis un state.json déjà DONE, qui repasserait par le même report) —
    la deuxième écriture ne doit produire aucune ligne supplémentaire."""
    run_dir = tmp_path / "run"
    kw = _kwargs(tmp_path, run_dir, project="proj")
    driver = ForgeDriver("proj", "proj-run-c", profile="micro",
                          executor=StubExecutor(run_dir=run_dir), **kw)
    report = driver.run()
    assert report["status"] == "DONE"

    run_index = kw["run_index_path"]
    text_after_first = run_index.read_text(encoding="utf-8")
    assert text_after_first.count("## proj-run-c —") == 1

    # rejeu explicite de l'ajout (même report, même run_id)
    driver._append_run_index_best_effort(report)
    driver._append_run_index_best_effort(report)  # x2 pour bien prouver l'absence de dérive

    text_after_replay = run_index.read_text(encoding="utf-8")
    assert text_after_replay.count("## proj-run-c —") == 1
    assert text_after_replay == text_after_first  # bit-à-bit inchangé


def test_rejeu_du_run_complet_sur_le_meme_run_dir_najoute_aucun_doublon(tmp_path, offline):
    """Rejeu bout-en-bout : un run déjà DONE, rejoué via une NOUVELLE instance
    de ForgeDriver sur le même run_id/run_dir, reste idempotent — DONE
    idempotent renvoie le même report (via `_final_report` seul, sans repasser
    par `_promote_manifest_lessons_best_effort`/`_trigger_observer_best_effort`/
    l'ajout RUN_INDEX) : aucun doublon, comportement de run INCHANGÉ."""
    run_dir = tmp_path / "run"
    kw = _kwargs(tmp_path, run_dir, project="proj")
    ForgeDriver("proj", "proj-run-d", profile="micro",
                executor=StubExecutor(run_dir=run_dir), **kw).run()
    run_index = kw["run_index_path"]
    first = run_index.read_text(encoding="utf-8")

    report2 = ForgeDriver("proj", "proj-run-d", profile="micro",
                           executor=StubExecutor(run_dir=run_dir), **kw).run()
    assert report2["status"] == "DONE"

    second = run_index.read_text(encoding="utf-8")
    assert second == first
    assert second.count("## proj-run-d —") == 1


# --- (c) échec d'écriture => warning journalisé, run_status inchangé, jamais d'exception --

def test_echec_ecriture_run_index_avale_run_status_inchange(tmp_path, offline, caplog):
    """Chemin invalide (dossier au lieu d'un fichier — provoque IsADirectoryError
    à l'ouverture en append) : la méthode ne lève jamais, le run reste DONE/OK,
    et l'échec est journalisé (logger.warning, exc_info)."""
    run_dir = tmp_path / "run"
    ex = StubExecutor(run_dir=run_dir)
    # run_index_path pointe vers un DOSSIER existant, pas un fichier : open(..., "a")
    # lève IsADirectoryError (Linux) / PermissionError (Windows) à l'écriture.
    bad_path = tmp_path / "run_index_is_a_dir"
    bad_path.mkdir()
    kw = _kwargs(tmp_path, run_dir, project="proj", run_index_path=bad_path)

    import logging
    caplog.set_level(logging.WARNING, logger="forge.driver")
    report = ForgeDriver("proj", "proj-run-e", profile="micro", executor=ex, **kw).run()

    assert report["status"] == "DONE"
    assert report["software_verdict"] == "OK"
    assert any(
        "RUN_INDEX" in r.message and r.levelno == logging.WARNING
        for r in caplog.records
    )


def test_echec_ecriture_run_index_ne_leve_jamais_meme_appele_directement(tmp_path, offline):
    """Même garde-fou, isolé de la boucle `run()` : appel direct de la méthode
    avec une cible invalide — jamais de levée, aucune exception ne remonte."""
    run_dir = tmp_path / "run"
    ex = StubExecutor(run_dir=run_dir)
    bad_path = tmp_path / "run_index_is_a_dir2"
    bad_path.mkdir()
    kw = _kwargs(tmp_path, run_dir, project="proj", run_index_path=bad_path)
    driver = ForgeDriver("proj", "proj-run-f", profile="micro", executor=ex, **kw)
    report = driver.run()
    # ne doit jamais lever, quel que soit le nombre de rejeux
    driver._append_run_index_best_effort(report)
    driver._append_run_index_best_effort(report)


# --- (d) le fichier historique n'est jamais réécrit ---------------------------------

def test_fichier_historique_reel_nest_jamais_reecrit_teste_sur_une_copie(tmp_path, offline):
    """Copie EXACTE du vrai `EVIDENCE/runs/RUN_INDEX.md` (jamais le vrai
    fichier lui-même) : les 226 lignes historiques doivent rester INTACTES
    après un run réel dont l'entrée est ajoutée — seul un append en fin de
    fichier est autorisé, aucune réécriture des lignes existantes."""
    repo_root = Path(__file__).resolve().parents[2]
    real_run_index = repo_root / "EVIDENCE" / "runs" / "RUN_INDEX.md"
    if not real_run_index.exists():
        pytest.skip("RUN_INDEX.md absent de ce poste (lecture best-effort)")

    copy_path = tmp_path / "RUN_INDEX_copy.md"
    original_text = real_run_index.read_text(encoding="utf-8")
    copy_path.write_text(original_text, encoding="utf-8")

    run_dir = tmp_path / "run"
    ex = StubExecutor(run_dir=run_dir)
    kw = _kwargs(tmp_path, run_dir, project="proj", run_index_path=copy_path)
    report = ForgeDriver("proj", "proj-run-g", profile="micro", executor=ex, **kw).run()
    assert report["status"] == "DONE"

    new_text = copy_path.read_text(encoding="utf-8")
    assert new_text.startswith(original_text)  # les lignes historiques n'ont pas bougé
    assert new_text != original_text  # mais une entrée a bien été ajoutée
    assert "## proj-run-g —" in new_text[len(original_text):]

    # le VRAI fichier du dépôt reste totalement inchangé
    assert real_run_index.read_text(encoding="utf-8") == original_text


# --- (e) garde PYTEST : jamais de redirection silencieuse vers le vrai registre -----

def test_garde_pytest_refuse_le_registre_reel_sans_injection_explicite(tmp_path, offline, caplog):
    """Incident du lot P4 précédent (revert Pierre) : des fixtures qui
    n'injectaient pas `run_index_path` ont écrit 3 lignes polluantes dans le
    vrai `EVIDENCE/runs/RUN_INDEX.md`. Ce test prouve la garde : sous pytest
    (`PYTEST_CURRENT_TEST` est positionné par pytest lui-même pendant ce test),
    un driver construit SANS `run_index_path` injecté doit refuser d'écrire
    dans le fichier réel — explicitement (exception journalisée en warning),
    jamais une redirection silencieuse vers un autre chemin.

    Le vrai fichier du dépôt est lu avant/après : il doit rester bit-à-bit
    inchangé."""
    import logging
    import os

    assert "PYTEST_CURRENT_TEST" in os.environ  # précondition : on est bien sous pytest

    repo_root = Path(__file__).resolve().parents[2]
    real_run_index = repo_root / "EVIDENCE" / "runs" / "RUN_INDEX.md"
    before = real_run_index.read_text(encoding="utf-8") if real_run_index.exists() else None

    run_dir = tmp_path / "run"
    ex = StubExecutor(run_dir=run_dir)
    kw = _kwargs(tmp_path, run_dir, project="proj")
    kw.pop("run_index_path")  # AUCUNE injection — force la résolution par défaut

    caplog.set_level(logging.WARNING, logger="forge.driver")
    report = ForgeDriver("proj", "proj-run-h", profile="micro", executor=ex, **kw).run()

    # le run lui-même reste OK — la garde ne doit jamais invalider le verdict
    assert report["status"] == "DONE"
    assert report["software_verdict"] == "OK"

    assert any(
        "RUN_INDEX" in r.message and r.levelno == logging.WARNING
        for r in caplog.records
    )
    # la cause précise (garde PYTEST) vit dans la trace de l'exception capturée
    # (exc_info=True), pas dans le message court du warning lui-même.
    assert "PYTEST_CURRENT_TEST" in caplog.text

    after = real_run_index.read_text(encoding="utf-8") if real_run_index.exists() else None
    assert after == before  # le vrai fichier du dépôt n'a pas bougé, ni créé ni modifié


def test_garde_pytest_leve_explicitement_meme_hors_boucle_run(tmp_path, offline, monkeypatch):
    """Même garde, isolée de `run()` : appel direct de `_run_index_target()` sur
    un driver sans `run_index_path` injecté — lève `RuntimeError` explicitement
    (pas de valeur de repli silencieuse) tant que `PYTEST_CURRENT_TEST` est
    présent."""
    import os

    assert "PYTEST_CURRENT_TEST" in os.environ
    run_dir = tmp_path / "run"
    ex = StubExecutor(run_dir=run_dir)
    kw = _kwargs(tmp_path, run_dir, project="proj")
    kw.pop("run_index_path")
    driver = ForgeDriver("proj", "proj-run-i", profile="micro", executor=ex, **kw)

    with pytest.raises(RuntimeError, match="PYTEST_CURRENT_TEST"):
        driver._run_index_target()
