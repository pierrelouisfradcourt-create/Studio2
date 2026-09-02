"""R2-OBS · P2 — le PROMPT FINAL est persisté, pas seulement son empreinte.

Défaut mesuré : le Context Manifest écrit `final_prompt_sha256`
(`context_manifest.build_execution_manifest_record`) mais le TEXTE réellement
servi à l'agent n'existe nulle part sur disque. Une empreinte sans son antécédent
ne permet ni de relire ce qui a été demandé, ni de rejouer un spawn : elle prouve
seulement qu'on aurait pu.

Invariant FIGÉ ici : le fichier et l'empreinte du manifeste viennent des MÊMES
OCTETS. Le prompt est donc écrit en BINAIRE (`prompt.encode("utf-8")`) et jamais
via un `write_text` : sous Windows, la traduction `\\n` -> `\\r\\n` du mode texte
suffirait à faire diverger `sha256(fichier)` de `final_prompt_sha256` — deux
vérités pour une même donnée, exactement le motif que ce lot ferme.

Best-effort ASSUMÉ mais JOURNALISÉ : un échec d'écriture laisse une trace
(`logger.warning`) et ne tue jamais le run — un capteur n'a pas le droit de
casser ce qu'il mesure.
"""
from __future__ import annotations

import hashlib
import json
import types
from pathlib import Path

from forge import run_real


def _payload(etape="s9-build"):
    return types.SimpleNamespace(
        etape=etape, prompt="PROMPT CONTRACTUEL\navec des accents : éàü\net des lignes",
        model="haiku", provider="anthropic", allowed_tools=(),
    )


def _context(tmp_path, attempt=1, etape="s9-build"):
    return {
        "run_id": "r2obs-2",
        "project": "proj",
        "run_dir": str(tmp_path / "run"),
        "model_override": None,
        "dispatch_marker": f"FORGE_DISPATCH:{etape}:r2obs-2:{attempt}",
        "attempt": attempt,
        "premortem": [],
        "project_bible": "",
        "materialize_feedback": None,
    }


def _succes():
    return {"ok": True, "output": "SORTIE", "tokens": 10, "duration_s": 1.0,
            "cost_usd": 0.0, "cache_creation_tokens": 0, "cache_read_tokens": 0,
            "returncode": 0, "stderr_tail": "", "process_state": "MODEL_REACHED",
            "session_id": "s", "model_used": ["claude-haiku"],
            "tokens_measured": None, "tools_used": None}


def _manifest_execution_records(run_dir: Path, etape: str) -> list[dict]:
    path = run_dir / "context" / f"{etape}.manifest.jsonl"
    out = []
    for ligne in path.read_text(encoding="utf-8").splitlines():
        if ligne.strip():
            rec = json.loads(ligne)
            if rec.get("kind") == "execution":
                out.append(rec)
    return out


def _run(tmp_path, monkeypatch, attempt=1, etape="s9-build"):
    monkeypatch.setattr(run_real, "_claude_call_raw",
                        lambda *a, **k: _succes())
    executor = run_real.claude_executor(tmp_path, {}, profile="micro")
    return executor(_payload(etape), None, _context(tmp_path, attempt, etape))


# --- (a) le fichier existe et porte EXACTEMENT les octets du manifeste -------

def test_le_prompt_final_est_ecrit_et_son_sha_concorde(tmp_path, monkeypatch):
    _run(tmp_path, monkeypatch)
    run_dir = tmp_path / "run"

    chemin = run_dir / "context" / "prompt_s9-build_a1.txt"
    assert chemin.exists(), "le prompt final n'a pas été persisté"

    octets = chemin.read_bytes()
    sha_fichier = hashlib.sha256(octets).hexdigest()
    records = _manifest_execution_records(run_dir, "s9-build")
    assert len(records) == 1
    assert sha_fichier == records[0]["final_prompt_sha256"]
    # Même source, donc même taille — jamais un recalcul divergent.
    assert len(octets.decode("utf-8")) == records[0]["final_prompt_chars"]


def test_le_prompt_persiste_contient_le_marqueur_de_dispatch(tmp_path, monkeypatch):
    _run(tmp_path, monkeypatch)
    texte = (tmp_path / "run" / "context" / "prompt_s9-build_a1.txt").read_text(
        encoding="utf-8")
    assert "FORGE_DISPATCH:s9-build:r2obs-2:1" in texte
    assert "PROMPT CONTRACTUEL" in texte


# --- (b) une 2e tentative écrit un 2e fichier : jamais d'écrasement ----------

def test_une_deuxieme_tentative_n_ecrase_jamais_la_premiere(tmp_path, monkeypatch):
    _run(tmp_path, monkeypatch, attempt=1)
    _run(tmp_path, monkeypatch, attempt=2)
    ctx = tmp_path / "run" / "context"
    a1, a2 = ctx / "prompt_s9-build_a1.txt", ctx / "prompt_s9-build_a2.txt"
    assert a1.exists() and a2.exists()
    assert "r2obs-2:1" in a1.read_text(encoding="utf-8")
    assert "r2obs-2:2" in a2.read_text(encoding="utf-8")

    records = _manifest_execution_records(tmp_path / "run", "s9-build")
    assert len(records) == 2
    assert hashlib.sha256(a2.read_bytes()).hexdigest() == records[1]["final_prompt_sha256"]


# --- (c) best-effort : une écriture impossible ne tue pas le run -------------

def test_une_ecriture_impossible_ne_tue_pas_le_run(tmp_path, monkeypatch, caplog):
    def boom(path, data):
        raise OSError("disque plein (simulé)")

    monkeypatch.setattr(run_real, "_write_prompt_bytes", boom)
    res = _run(tmp_path, monkeypatch)
    assert res["ok"] is True
    assert any("prompt final" in r.message or "prompt final" in r.getMessage()
               for r in caplog.records), "l'échec d'écriture doit laisser une trace"
