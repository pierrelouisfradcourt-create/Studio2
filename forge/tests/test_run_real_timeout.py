"""Oracle des correctifs P0 du run n°1 shmup (FIR-01 / FIR-02).

FIR-01 — timeout `claude -p` non appliqué : `subprocess.run(timeout=)` tue le
wrapper npm mais pas le petit-fils `claude.exe`, qui garde les pipes ouverts →
communicate() deadlocke, budget ignoré (2h15 observées), puis faux "timeout".
Correctif : Popen + tree-kill (`taskkill /T /F` Windows / `killpg` POSIX) au
timeout, tant que le wrapper est vivant, puis drain des pipes.

FIR-02 — build réussi jeté par un timeout non inspecté : sur timeout, le disque
est inspecté ; si un harnais de jeu existe, le build est CONSIGNÉ (salvageable),
jamais jeté sec.

Preuve MIXTE : unités déterministes (kill ciblé, drain, salvage) TOUJOURS jouées,
+ une intégration RÉELLE (petit-fils qui tient le pipe) qui prouve le tree-kill
et l'absence de deadlock sur la plateforme courante. NO_CLAIM_ALLOWED.
"""
import json
import os
import subprocess
import sys
import time
from dataclasses import dataclass

import pytest

import forge.run_real as run_real


@dataclass
class FakePayload:
    etape: str
    model: str = "haiku"
    prompt: str = "PROMPT CONTRAT"


def _context(run_dir, **extra):
    ctx = {
        "run_id": "run-1",
        "project": "proj",
        "run_dir": str(run_dir),
        "model_override": None,
        "dispatch_marker": "FORGE_DISPATCH:x:run-1",
        "attempt": 1,
        "premortem": [],
    }
    ctx.update(extra)
    return ctx


def _pid_alive(pid: int) -> bool:
    """Liveness cross-plateforme (sans psutil)."""
    if os.name == "nt":
        out = subprocess.run(
            ["tasklist", "/FI", f"PID eq {pid}", "/NH"],
            capture_output=True, text=True)
        return str(pid) in (out.stdout or "")
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


# --- FIR-01 : _kill_process_tree cible bien l'ARBRE (unités mockées) ----------------

def test_kill_process_tree_windows_cible_taskkill_arbre(monkeypatch):
    """Windows : `taskkill /T /F /PID <pid>` — /T inclut le petit-fils claude.exe."""
    calls = []

    def fake_run(cmd, **kw):
        calls.append(list(cmd))
        class C:  # noqa: E306
            returncode = 0
        return C()

    monkeypatch.setattr(run_real, "_IS_WINDOWS", True)
    monkeypatch.setattr(run_real.subprocess, "run", fake_run)

    class FakeProc:
        pid = 4216756
        def poll(self):  # vivant : le tree-kill doit s'appliquer
            return None
        def kill(self):
            calls.append(["proc.kill"])

    run_real._kill_process_tree(FakeProc())
    taskkill = [c for c in calls if c and c[0] == "taskkill"]
    assert taskkill, "taskkill doit être appelé sur un process vivant"
    assert taskkill[0] == ["taskkill", "/T", "/F", "/PID", "4216756"]


@pytest.mark.skipif(os.name == "nt",
                    reason="chemin POSIX (killpg/SIGKILL absents sur Windows)")
def test_kill_process_tree_posix_utilise_killpg(monkeypatch):
    monkeypatch.setattr(run_real, "_IS_WINDOWS", False)
    killed = {}
    monkeypatch.setattr(run_real.os, "getpgid", lambda pid: 777, raising=False)
    monkeypatch.setattr(run_real.os, "killpg",
                        lambda pgid, sig: killed.update(pgid=pgid, sig=sig),
                        raising=False)

    class FakeProc:
        pid = 123
        def poll(self):
            return None
        def kill(self):
            pass

    run_real._kill_process_tree(FakeProc())
    assert killed["pgid"] == 777
    assert killed["sig"] == run_real.signal.SIGKILL


def test_kill_process_tree_process_deja_mort_est_noop(monkeypatch):
    monkeypatch.setattr(run_real, "_IS_WINDOWS", True)
    called = []
    monkeypatch.setattr(run_real.subprocess, "run", lambda *a, **k: called.append(a))

    class Dead:
        pid = 1
        def poll(self):
            return 0  # déjà terminé
        def kill(self):
            called.append("kill")

    run_real._kill_process_tree(Dead())
    assert called == []  # rien à tuer, aucun taskkill/kill


# --- FIR-01 : _run_subprocess_tree draine après kill (unité déterministe) -----------

def test_run_subprocess_tree_timeout_tue_arbre_puis_draine(monkeypatch):
    """Au timeout : l'arbre est tué PUIS communicate() re-draine (pas de deadlock),
    la sortie partielle est récupérée, timed_out=True."""
    monkeypatch.setattr(run_real, "_IS_WINDOWS", False)
    killed = []
    monkeypatch.setattr(run_real, "_kill_process_tree",
                        lambda proc: killed.append(proc.pid))

    class FakePopen:
        pid = 999
        def __init__(self):
            self._calls = 0
            self.returncode = None
        def communicate(self, input=None, timeout=None):
            self._calls += 1
            if self._calls == 1:  # 1er appel : timeout (petit-fils tient le pipe)
                raise run_real.subprocess.TimeoutExpired(cmd="x", timeout=timeout)
            self.returncode = 1  # 2e appel : draine après le kill de l'arbre
            return ("partial-out", "partial-err")
        def poll(self):
            return None
        def kill(self):
            pass

    monkeypatch.setattr(run_real.subprocess, "Popen", lambda *a, **k: FakePopen())
    rc, out, err, timed_out = run_real._run_subprocess_tree(
        ["x"], cwd=".", input_text="p", timeout_s=0.01)
    assert timed_out is True
    assert killed == [999], "l'arbre de process doit être ciblé au timeout"
    assert out == "partial-out"  # drainé après le kill => aucun deadlock
    assert err == "partial-err"


def test_run_subprocess_tree_honore_le_double_subprocess_run(monkeypatch):
    """Seam compat : un double de test de subprocess.run est honoré (aucun Popen,
    aucun spawn réel) — c'est ce qui garde `capture_cmd` vert."""
    seen = {}

    def fake_run(cmd, **kw):
        seen["cmd"] = list(cmd)
        class C:
            returncode = 0
            stdout = "OUT"
            stderr = ""
        return C()

    monkeypatch.setattr(run_real.subprocess, "run", fake_run)
    # Popen doit rester intouché sur ce chemin.
    monkeypatch.setattr(run_real.subprocess, "Popen",
                        lambda *a, **k: pytest.fail("Popen ne doit pas être appelé"))
    rc, out, err, timed_out = run_real._run_subprocess_tree(
        ["claude", "-p"], cwd=".", input_text="p", timeout_s=1.0)
    assert timed_out is False
    assert out == "OUT"
    assert seen["cmd"] == ["claude", "-p"]


def test_claude_call_raw_timeout_flag(monkeypatch):
    """_claude_call_raw remonte {ok:False, timeout:True} avec un motif borné."""
    monkeypatch.setattr(
        run_real, "_run_subprocess_tree",
        lambda cmd, **kw: (None, "", "", True))
    res = run_real._claude_call_raw("p", "haiku", add_dir=".", timeout_s=30.0)
    assert res["ok"] is False
    assert res["timeout"] is True
    assert "timeout" in res["reason"]
    assert "arbre de process tué" in res["reason"]


# --- FIR-01 : intégration RÉELLE (petit-fils tient le pipe) --------------------------

# Wrapper réel : spawn un petit-fils qui HÉRITE du stdout (notre PIPE) et le garde
# ouvert en dormant longtemps ; le wrapper reste vivant lui aussi (comme le wrapper
# npm attend claude.exe). Sans tree-kill, communicate() deadlockerait sur le pipe.
_WRAPPER_SRC = (
    "import subprocess, sys, time\n"
    "pidfile = sys.argv[1]\n"
    "gc = subprocess.Popen([sys.executable, '-c',\n"
    "    'import time; time.sleep(60)'])\n"  # petit-fils : hérite du stdout, dort
    "open(pidfile, 'w').write(str(gc.pid))\n"
    "time.sleep(60)\n"  # le wrapper reste vivant
)


def test_integration_reelle_timeout_tue_le_petit_fils_sans_deadlock(tmp_path):
    """Preuve RÉELLE sur la plateforme courante : au timeout, le petit-fils
    (orphelin potentiel qui tient le pipe) est tué et l'appel rend la main vite
    (pas de deadlock à 60s)."""
    wrapper = tmp_path / "wrapper.py"
    wrapper.write_text(_WRAPPER_SRC, encoding="utf-8")
    pidfile = tmp_path / "gc.pid"

    started = time.time()
    rc, out, err, timed_out = run_real._run_subprocess_tree(
        [sys.executable, str(wrapper), str(pidfile)],
        cwd=str(tmp_path), input_text="", timeout_s=3.0)
    elapsed = time.time() - started

    assert timed_out is True
    # Pas de deadlock : on rend la main peu après le budget (jamais ~60s).
    assert elapsed < 40, f"deadlock suspecté (elapsed={elapsed:.1f}s)"

    # Le petit-fils doit être mort après le tree-kill.
    assert pidfile.exists(), "le wrapper doit avoir écrit le PID du petit-fils"
    gc_pid = int(pidfile.read_text().strip())
    deadline = time.time() + 5
    while _pid_alive(gc_pid) and time.time() < deadline:
        time.sleep(0.2)
    assert not _pid_alive(gc_pid), f"petit-fils {gc_pid} survivant après tree-kill"


# --- FIR-02 : salvage d'un build sur timeout ---------------------------------------

def test_salvage_timeout_jeu_present_est_salvageable(tmp_path):
    add_dir = tmp_path / "game"
    add_dir.mkdir()
    (add_dir / "run-oracle.mjs").write_text("x", encoding="utf-8")
    (add_dir / "logic.mjs").write_text("y", encoding="utf-8")
    run_dir = tmp_path / "run"

    salvage = run_real._salvage_on_timeout(
        "s9-build", add_dir, run_dir, "claude -p timeout (30s)")
    assert salvage["salvageable"] is True
    assert "run-oracle.mjs" in salvage["harness_present"]
    assert "logic.mjs" in salvage["produced_mjs"]

    written = json.loads(
        (run_dir / "salvage_s9-build.json").read_text(encoding="utf-8"))
    assert written["salvageable"] is True
    assert "BLOCKED sec" in written["note"]  # note pédagogique : ne pas jeter sec


def test_salvage_timeout_sans_harnais_non_salvageable(tmp_path):
    add_dir = tmp_path / "empty"
    add_dir.mkdir()
    run_dir = tmp_path / "run"
    salvage = run_real._salvage_on_timeout("s9-build", add_dir, run_dir, "timeout")
    assert salvage["salvageable"] is False
    assert (run_dir / "salvage_s9-build.json").exists()


def test_executor_timeout_avec_artefacts_ne_jette_pas_sec(tmp_path, monkeypatch):
    """FIR-02 câblé dans l'executor : un timeout AVEC harnais de jeu sur disque
    n'est pas un BLOCKED sec — le motif d'arrêt flagge le salvage et le fichier
    est consigné (ce motif remonte dans humangate_flags via _halt_step du driver)."""
    add_dir = tmp_path / "game"
    add_dir.mkdir()
    (add_dir / "run-oracle.mjs").write_text("x", encoding="utf-8")
    run_dir = tmp_path / "run"

    def fake_call(prompt, model, **kw):
        return {"ok": False, "timeout": True, "duration_s": 1.0,
                "reason": "claude -p timeout (30s) — arbre de process tué (FIR-01)"}

    monkeypatch.setattr(run_real, "_claude_call_raw", fake_call)
    ex = run_real.claude_executor(add_dir=add_dir, task_by_step={})
    res = ex(FakePayload("s9-build"), None, _context(run_dir))

    assert res["ok"] is False          # le run halte quand même (pas fini)
    assert res["salvageable"] is True  # mais le travail est REPÉRÉ, pas détruit
    assert "SALVAGEABLES" in res["reason"]
    assert res["salvage_path"].endswith("salvage_s9-build.json")
    assert (run_dir / "salvage_s9-build.json").exists()


def test_executor_timeout_sans_artefacts_reste_un_echec_sans_salvage(tmp_path, monkeypatch):
    add_dir = tmp_path / "empty"
    add_dir.mkdir()
    run_dir = tmp_path / "run"

    def fake_call(prompt, model, **kw):
        return {"ok": False, "timeout": True, "duration_s": 1.0,
                "reason": "claude -p timeout (30s) — arbre de process tué (FIR-01)"}

    monkeypatch.setattr(run_real, "_claude_call_raw", fake_call)
    ex = run_real.claude_executor(add_dir=add_dir, task_by_step={})
    res = ex(FakePayload("s9-build"), None, _context(run_dir))
    assert res["ok"] is False
    assert res["salvageable"] is False
    assert "SALVAGEABLES" not in res["reason"]
    assert (run_dir / "salvage_s9-build.json").exists()  # consigné (non salvageable)
