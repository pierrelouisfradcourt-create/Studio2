"""Tests du Runtime Inventory Oracle.

Ce que ces tests protègent en priorité : la SÉPARATION des trois catégories. Un oracle
qui confond « présent dans le code » et « réellement exécuté » ment dans les deux sens.
"""
from __future__ import annotations

import json

from pathlib import Path

import pytest

from forge import runtime_inventory_oracle as rio

ROLES_MIN = """
version: "1.0"
models:
  - id: lmstudio/qwen2.5-14b-instruct
    provider: lmstudio
    roles:
      - repair_runtime
  - id: anthropic/claude-opus-4-8
    provider: claude-local
    roles:
      - architect
runtime_contracts:
  repair_runtime:
    implementation:
      entrypoint: forge/repair_step.mjs
      adapter: forge/repair_runtime_adapter.mjs
      kill_switch: FORGE_REPAIR=0
"""


def _repo(tmp_path, evenements, ts=1785000000.0):
    (tmp_path / "EVIDENCE/reports/observer/jeu").mkdir(parents=True)
    p = tmp_path / "EVIDENCE/reports/observer/jeu/events.jsonl"
    p.write_text("\n".join(json.dumps({
        "kind": "dispatch.prepared", "ts": ts,
        "actor": {"capability_role": r}, "payload": {},
    }) for r in evenements), encoding="utf-8")
    return tmp_path


def test_declared_runtimes_lit_modele_ET_contrat_runtime(tmp_path):
    f = tmp_path / "roles.yaml"
    f.write_text(ROLES_MIN, encoding="utf-8")
    d = rio.declared_runtimes(f)
    assert set(d) == {"repair_runtime", "architect"}
    assert d["repair_runtime"]["model"] == "lmstudio/qwen2.5-14b-instruct"
    assert d["repair_runtime"]["entrypoint"] == "forge/repair_step.mjs"
    assert d["repair_runtime"]["kill_switch"] == "FORGE_REPAIR=0"
    # un rôle sans runtime_contract ne se voit pas inventer un entrypoint
    assert d["architect"]["entrypoint"] is None


# --- la séparation des trois catégories -------------------------------------------

def test_mention_d_un_modele_n_est_PAS_un_appel():
    """9 faux positifs sur 14 mesurés le 2026-08-04 : c'est ce test qui les arrête."""
    assert rio.classify_file('PORTS = {"lm_studio": 1234}') == rio.MENTIONS_MODEL
    assert rio.classify_file('if "claude" in model.lower(): return "llm_agent"') == rio.MENTIONS_MODEL
    assert rio.classify_file("PROVIDER_LMSTUDIO = 'lmstudio'") == rio.MENTIONS_MODEL
    assert rio.classify_file("rien du tout") is None


def test_un_vrai_appel_est_classe_CALLS_MODEL():
    assert rio.classify_file(
        'r = requests.post(base + "/v1/chat/completions", json=p)') == rio.CALLS_MODEL
    assert rio.classify_file(
        'const r = await fetch("http://x/v1/chat/completions", {})') == rio.CALLS_MODEL
    assert rio.classify_file(
        'CMD = shutil.which("claude")\nsubprocess.run([CMD])') == rio.CALLS_MODEL


def test_observed_by_event_ne_compte_QUE_les_evenements(tmp_path):
    r = _repo(tmp_path, ["architect", "architect", "repair_runtime"])
    vus = rio.observed_by_event(rio.ObservationWindow(), repo_root=r)
    assert vus["architect"]["events"] == 2
    assert vus["repair_runtime"]["projects"] == ["jeu"]
    assert "council" not in vus, "un fichier de code n'est jamais un rôle observé"


# --- fenêtre d'observation ---------------------------------------------------------

def test_hors_fenetre_n_est_PAS_jamais_observe(tmp_path, monkeypatch):
    """Les deux états sont distincts — les confondre fait conclure « mort » à tort."""
    vieux = 1000000.0  # très ancien
    r = _repo(tmp_path, ["architect"], ts=vieux)
    monkeypatch.setattr(rio, "ROLES_YAML", tmp_path / "roles.yaml")
    (tmp_path / "roles.yaml").write_text(ROLES_MIN, encoding="utf-8")

    rapport = rio.compare(rio.ObservationWindow(days=30), repo_root=r)
    archi = next(x for x in rapport["declared_not_observed"] if x["capability_role"] == "architect")
    assert archi["status"] == "observed_outside_window"
    assert archi["events_total"] == 1

    jamais = next(x for x in rapport["declared_not_observed"]
                  if x["capability_role"] == "repair_runtime")
    assert jamais["status"] == "never_observed"
    assert jamais["events_total"] == 0


def test_la_fenetre_est_toujours_exigee_dans_la_sortie(tmp_path, monkeypatch):
    r = _repo(tmp_path, [])
    monkeypatch.setattr(rio, "ROLES_YAML", tmp_path / "roles.yaml")
    (tmp_path / "roles.yaml").write_text(ROLES_MIN, encoding="utf-8")
    rapport = rio.compare(repo_root=r)
    assert rapport["requires_observation_window"] is True
    assert all(x["requires_observation_window"] for x in rapport["declared_not_observed"])
    assert "observation_window" in rapport


def test_aucune_sortie_ne_contient_de_score(tmp_path, monkeypatch):
    r = _repo(tmp_path, ["architect"])
    monkeypatch.setattr(rio, "ROLES_YAML", tmp_path / "roles.yaml")
    (tmp_path / "roles.yaml").write_text(ROLES_MIN, encoding="utf-8")
    brut = json.dumps(rio.compare(repo_root=r)).lower()
    for interdit in rio.FORBIDDEN_KEYS:
        assert f'"{interdit}' not in brut, f"champ interdit : {interdit}"
    assert "mort" not in brut and "dead" not in brut


# --- drift.detected ----------------------------------------------------------------

def test_les_trois_cas_de_derive_restent_SEPARES(tmp_path, monkeypatch):
    r = _repo(tmp_path, ["architect"])
    monkeypatch.setattr(rio, "ROLES_YAML", tmp_path / "roles.yaml")
    (tmp_path / "roles.yaml").write_text(ROLES_MIN, encoding="utf-8")
    rapport = rio.compare(repo_root=r)
    lignes = rio.drift_records(rapport)

    kinds = {x["drift_kind"] for x in lignes}
    assert kinds <= set(rio.DRIFT_KINDS)
    for x in lignes:
        assert x["severity"] == rio.DRIFT_KINDS[x["drift_kind"]]
    # information ≠ alerte : un rôle non observé n'est pas une anomalie
    assert rio.DRIFT_KINDS["declared_not_observed"] == "INFORMATION"
    assert rio.DRIFT_KINDS["observed_not_declared_event"] == "ALERTE"
    assert rio.DRIFT_KINDS["observed_code_not_declared"] == "ALERTE_CODE"


def test_emit_drift_ecrit_des_lignes_relisibles(tmp_path, monkeypatch):
    r = _repo(tmp_path, [])
    monkeypatch.setattr(rio, "ROLES_YAML", tmp_path / "roles.yaml")
    (tmp_path / "roles.yaml").write_text(ROLES_MIN, encoding="utf-8")
    cible = tmp_path / "out" / "runtime_drift.jsonl"
    n = rio.emit_drift(rio.compare(repo_root=r), path=cible)
    lignes = [json.loads(x) for x in cible.read_text(encoding="utf-8").splitlines() if x.strip()]
    assert len(lignes) == n >= 2
    assert all(x["schema"] == "forge.runtime_drift.v1" for x in lignes)


# --- réalité du dépôt (non fixturé) ------------------------------------------------

@pytest.mark.parametrize("attendu", ["scripts/council.py", "scripts/claude_proxy.py"])
def test_le_depot_reel_expose_ses_appelants_de_modele_non_declares(attendu):
    code = {x["entrypoint"] for x in rio.observed_in_code()}
    assert attendu in code


def test_la_forge_n_importe_PLUS_council_la_dependance_est_interne():
    """Lot B (GO Pierre 2026-09-02) — INVERSION ASSUMÉE de ce test, avec sa raison.

    Ce test affirmait : « `forge/runtime.py` importe `council.QwenAdapter` ; un fichier legacy
    importé par le runtime est une dépendance, pas un vestige. » **Il avait raison, et il l'a dit
    avant nous** : le 2026-09-02 au matin, `scripts/council.py` a été classé « hors périmètre V2 »
    et CE test rangé en OUT_OF_SCOPE — alors que son nom même énonçait le contraire. RUN M s'est
    arrêté à s6 sur le `ModuleNotFoundError` qu'il annonçait.

    Il garde donc son rôle, retourné : la dépendance existe toujours, mais elle est désormais
    INTERNE au paquet (`forge.lm_adapter`, extrait verbatim). Ce test devient la garde de
    non-régression contre une ré-introduction de la dépendance sortante.
    """
    src = (Path(__file__).resolve().parents[1] / "runtime.py").read_text(encoding="utf-8")
    assert "from forge.lm_adapter import QwenAdapter" in src,         "l'adaptateur doit venir du paquet, pas d'un fichier de lane"
    assert "from council import" not in src,         "dépendance SORTANTE ré-introduite : c'est exactement ce qui a fait tomber RUN M à s6"
