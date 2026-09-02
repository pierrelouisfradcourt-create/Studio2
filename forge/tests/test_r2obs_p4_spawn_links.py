"""R2-OBS · P4 — UNE ligne par spawn qui répond aux 6 questions.

Défaut mesuré : répondre à « pour CE spawn : quel contrat (sha) · quel prompt
(fichier + sha) · quels outils réellement appliqués · quel runtime/modèle · quelle
sortie (sha) · quel verdict ? » exigeait de croiser 4 fichiers
(`<etape>.manifest.jsonl`, `state.json`, `audit.jsonl`, `telemetry.jsonl`) et,
pour le prompt, un fichier qui n'existait pas (cf. P2). Le JOINT manquait.

`<run_dir>/context/spawn_links.jsonl` est ce joint — PAS un nouveau manifeste, PAS
un PromptComposer : chaque valeur reste produite là où elle existe déjà, la ligne
ne fait que les nouer. Deux producteurs, UN seul écrivain :
  * `run_real.claude_executor` dépose `res["spawn_link"]` (contrat, prompt, outils
    RÉELLEMENT passés à la CLI, modèle MESURÉ) — les seules valeurs qu'il connaisse ;
  * `ForgeDriver._run_llm` y noue la sortie (artefact + sha), le verdict et l'issue,
    puis écrit la ligne — le seul acteur qui les connaisse.

INVARIANT RATIFIÉ PIERRE 2026-08-28 appliqué ici : « une preuve doit provenir du
mécanisme qui a réalisé l'action, sinon elle est explicitement AUTO_ATTESTED ».
La ligne porte donc `attestation: "self"` : sur ce chemin (B, headless), le driver
est sa PROPRE autorité — `spawn_executed` est écrit par le mécanisme qui exécute,
sans tiers observateur. La ligne dit ce qu'elle est, elle ne se fait pas passer
pour une observation externe.
"""
from __future__ import annotations

import hashlib
import json
import types
from pathlib import Path

import pytest

from forge import run_real
from forge.driver import ForgeDriver

ETAPE = "s9-build"


# --- harnais -----------------------------------------------------------------

def _payload(etape=ETAPE):
    return types.SimpleNamespace(
        etape=etape, prompt="PROMPT CONTRACTUEL", model="haiku",
        provider="anthropic", allowed_tools=(),
    )


def _context(tmp_path, attempt=1, etape=ETAPE):
    return {
        "run_id": "r2obs-4", "project": "proj",
        "run_dir": str(tmp_path / "run"), "model_override": None,
        "dispatch_marker": f"FORGE_DISPATCH:{etape}:r2obs-4:{attempt}",
        "attempt": attempt, "premortem": [], "project_bible": "",
        "materialize_feedback": None,
    }


def _succes():
    return {"ok": True, "output": "SORTIE DU MODELE", "tokens": 10,
            "duration_s": 1.0, "cost_usd": 0.0, "cache_creation_tokens": 0,
            "cache_read_tokens": 0, "returncode": 0, "stderr_tail": "",
            "process_state": "MODEL_REACHED", "session_id": "s",
            "model_used": ["claude-haiku-4-5"], "tokens_measured": None,
            "tools_used": None}


def _ecrire_ligne_dispatch(run_dir: Path, etape: str, sha: str) -> None:
    """Simule la ligne `kind: dispatch` que `prepare_dispatch` a déjà écrite —
    c'est de LÀ que vient le sha de contrat (jamais d'un recalcul divergent)."""
    path = run_dir / "context" / f"{etape}.manifest.jsonl"
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps({"kind": "dispatch", "etape": etape,
                             "contract_sha256": sha}) + "\n")


def _lignes(run_dir: Path) -> list[dict]:
    path = run_dir / "context" / "spawn_links.jsonl"
    return [json.loads(l) for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]


@pytest.fixture
def offline(monkeypatch):
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


# --- (a) le producteur amont : run_real dépose ce qu'il connaît -------------

def test_run_real_depose_contrat_prompt_outils_et_modele(tmp_path, monkeypatch):
    run_dir = tmp_path / "run"
    _ecrire_ligne_dispatch(run_dir, ETAPE, "deadbeef" * 8)
    monkeypatch.setattr(run_real, "_claude_call_raw", lambda *a, **k: _succes())

    executor = run_real.claude_executor(tmp_path, {}, profile="micro")
    res = executor(_payload(), None, _context(tmp_path))
    link = res["spawn_link"]

    # 1. quel contrat
    assert link["contract_path"] == f"forge/contracts/{ETAPE}.yaml"
    assert link["contract_sha256"] == "deadbeef" * 8
    # 2. quel prompt — le FICHIER de P2, et son sha == celui du manifeste
    assert Path(link["prompt_file"]).exists()
    assert link["prompt_sha256"] == hashlib.sha256(
        Path(link["prompt_file"]).read_bytes()).hexdigest()
    # 3. quels outils RÉELLEMENT appliqués (les mêmes valeurs qu'à la CLI)
    attendus = list(run_real._effective_step_tools(ETAPE))
    assert link["tools_effective"] == attendus
    assert link["tools_disallowed_count"] == len(
        run_real._derive_disallowed(tuple(attendus)))
    # 4. quel runtime/modèle — DÉCLARÉ vs MESURÉ, jamais confondus
    assert link["model_declared"] == "haiku"
    assert link["model_used"] == ["claude-haiku-4-5"]


def test_sans_ligne_dispatch_le_sha_de_contrat_est_null_jamais_invente(tmp_path, monkeypatch):
    monkeypatch.setattr(run_real, "_claude_call_raw", lambda *a, **k: _succes())
    executor = run_real.claude_executor(tmp_path, {}, profile="micro")
    res = executor(_payload(), None, _context(tmp_path))
    assert res["spawn_link"]["contract_sha256"] is None


# --- (b) l'écrivain : le driver noue sortie/verdict/issue et écrit ----------

def _driver(tmp_path, executor):
    return ForgeDriver(
        "proj-r2obs4", "r2obs-4", run_dir=tmp_path / "run", profile="micro",
        key_file=tmp_path / "k.key", audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        journal_path=tmp_path / "journal.jsonl",
        failure_events_path=tmp_path / "failure_events.jsonl",
        executor=executor,
    )


def _state(d):
    return {"steps": {e: {"status": "PENDING", "attempts": 0, "detail": {}}
                      for e in d.order}}


_LINK_AMONT = {
    "contract_path": f"forge/contracts/{ETAPE}.yaml",
    "contract_sha256": "ab" * 32,
    "prompt_file": "run/context/prompt_s9-build_a1.txt",
    "prompt_sha256": "cd" * 32,
    "tools_effective": ["Read", "Write"],
    "tools_disallowed_count": 12,
    "model_declared": "haiku",
    "model_used": ["claude-haiku-4-5"],
}


def test_la_ligne_repond_aux_six_questions(tmp_path, offline):
    d = _driver(tmp_path, lambda p, dec, ctx: {
        "ok": True, "output": "SORTIE DU MODELE", "tokens": 1, "duration_s": 1.0,
        "cost_usd": 0.0, "spawn_link": dict(_LINK_AMONT)})
    state = _state(d)
    etape = d.order[0]
    assert d._run_llm(state, etape) is True

    lignes = _lignes(d.run_dir)
    assert len(lignes) == 1
    ligne = lignes[0]

    assert ligne["run_id"] == "r2obs-4"
    assert ligne["etape"] == etape
    assert ligne["attempt"] == 1
    assert isinstance(ligne["ts"], float)
    # Q1 contrat · Q2 prompt · Q3 outils · Q4 modèle (repris tels quels de l'amont)
    for cle, valeur in _LINK_AMONT.items():
        assert ligne[cle] == valeur
    # Q5 sortie : l'artefact RÉELLEMENT écrit et son sha
    artefact = Path(ligne["artifact_path"])
    assert artefact.exists()
    assert ligne["artifact_sha256"] == hashlib.sha256(
        artefact.read_bytes()).hexdigest()
    # Q6 verdict : absent du run -> null, jamais inventé
    assert ligne["verdict_ref"] is None
    assert ligne["status"] == "OK"
    # Invariant de provenance
    assert ligne["attestation"] == "self"
    assert "auto-attest" in ligne["attestation_note"].lower()


def test_le_verdict_est_reference_quand_il_existe(tmp_path, offline):
    d = _driver(tmp_path, lambda p, dec, ctx: {
        "ok": True, "output": "S", "tokens": 1, "duration_s": 1.0, "cost_usd": 0.0})
    d.run_dir.mkdir(parents=True, exist_ok=True)
    (d.run_dir / "verdict.json").write_text("{}", encoding="utf-8")
    state = _state(d)
    d._run_llm(state, d.order[0])
    assert _lignes(d.run_dir)[0]["verdict_ref"] == str(d.run_dir / "verdict.json")


def test_un_halt_produit_aussi_sa_ligne(tmp_path, offline):
    d = _driver(tmp_path, lambda p, dec, ctx: {
        "ok": False, "reason": "claude -p returncode=1: ", "returncode": 1,
        "stderr_tail": "", "process_state": "PROCESS_EXIT_NONZERO",
        "spawn_link": dict(_LINK_AMONT)})
    state = _state(d)
    assert d._run_llm(state, d.order[0]) is False

    ligne = _lignes(d.run_dir)[0]
    assert ligne["status"] == "HALTED"
    assert ligne["artifact_path"] is None
    assert ligne["artifact_sha256"] is None
    assert ligne["contract_sha256"] == "ab" * 32
    assert ligne["attestation"] == "self"


def test_un_executeur_sans_amont_produit_une_ligne_a_champs_nuls(tmp_path, offline):
    """Aucun champ inventé : un exécuteur injecté qui ne dépose rien laisse des
    `null` explicites — « non mesuré » se lit, il ne se devine pas."""
    d = _driver(tmp_path, lambda p, dec, ctx: {
        "ok": True, "output": "S", "tokens": 1, "duration_s": 1.0, "cost_usd": 0.0})
    state = _state(d)
    d._run_llm(state, d.order[0])
    ligne = _lignes(d.run_dir)[0]
    assert ligne["prompt_file"] is None
    assert ligne["contract_sha256"] is None
    assert ligne["model_used"] is None
    assert ligne["artifact_sha256"] is not None  # la sortie, elle, est mesurée


def test_deux_tentatives_produisent_deux_lignes(tmp_path, offline):
    appels = []

    def executor(payload, decision, context):
        appels.append(context["attempt"])
        if len(appels) == 1:
            return {"ok": False, "output": "CASSE",
                    "reason": "worldscan.json non matérialisable — virgule"}
        return {"ok": True, "output": "S", "tokens": 1, "duration_s": 1.0,
                "cost_usd": 0.0}

    d = _driver(tmp_path, executor)
    state = _state(d)
    assert d._run_llm(state, d.order[0]) is True
    lignes = _lignes(d.run_dir)
    assert [l["attempt"] for l in lignes] == [1, 2]
    assert [l["status"] for l in lignes] == ["RETRY", "OK"]


def test_l_ecriture_de_la_ligne_ne_casse_jamais_le_run(tmp_path, offline, monkeypatch):
    d = _driver(tmp_path, lambda p, dec, ctx: {
        "ok": True, "output": "S", "tokens": 1, "duration_s": 1.0, "cost_usd": 0.0})
    monkeypatch.setattr(ForgeDriver, "_append_spawn_link",
                        lambda *a, **k: (_ for _ in ()).throw(OSError("disque plein")))
    state = _state(d)
    assert d._run_llm(state, d.order[0]) is True
