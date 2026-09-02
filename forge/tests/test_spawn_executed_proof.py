"""Oracle Phase 2b — DISPATCH_SPAWN_AUTHORITY_V1 : la PREUVE D'EXÉCUTION.

Pierre (decision-log, 2026-07-23) : « aujourd'hui `prepare()` écrit la ligne d'audit et
`spawn()` n'ajoute aucune preuve : on prouve une intention, pas une exécution. Événements
immuables spawn_prepared / spawn_authorized / spawn_executed ; la preuve finale vient de
`spawn_executed`. » Impact voulu : « l'audit devient une preuve d'action ».

Ce que ce fichier prouve, section par section :
1. `append_spawn_event` écrit un événement SIGNÉ corrélable au `spawn_prepared` par le
   triplet (etape, run_id, attempt) — même mécanisme, même fichier, une seule signature.
2. `spawn_proof` LIT ces événements (l'événement a un consommateur, pas un connecteur
   dormant de plus) et rend visible l'écart préparé/exécuté + la duplication de préparation.
3. NON-RÉGRESSION D4 : une ligne `spawn_executed` ne doit JAMAIS être comptée par
   `check_spawn` — sinon un spawn parfaitement légitime passerait pour un replay (count 2).
4. CHEMIN B (headless/driver) : un tour d'exécuteur écrit `spawn_executed` en code, et le
   rapport de fin de run expose la preuve (aucun hook Task ne se déclenche sur ce chemin).
5. CHEMIN A (hook PostToolUse) : le script réel, exécuté en sous-processus avec du JSON
   sur stdin — sortie 0 dans les trois cas (sans marqueur / avec marqueur / malformé),
   écriture UNIQUEMENT dans le cas « avec marqueur ».

NO_CLAIM_ALLOWED.
"""
import json
import subprocess
import sys
from pathlib import Path

import pytest

from forge.dispatch import (
    EVENT_AUTHORIZED,
    EVENT_EXECUTED,
    EVENT_PREPARED,
    append_spawn_event,
    prepare_dispatch,
    spawn_proof,
    verify_audit_line,
)
from forge.driver import ForgeDriver
from forge.hook_guard import (
    check_spawn,
    hook_decision,
    marker_key,
    record_authorization,
    record_execution,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
POSTTOOL_HOOK = REPO_ROOT / ".claude" / "hooks" / "posttool_forge_executed.py"


def _lines(audit: Path) -> list[dict]:
    return [json.loads(l) for l in audit.read_text(encoding="utf-8").splitlines() if l.strip()]


# --- 1. écriture d'un événement typé, signé, corrélable -----------------------

def test_append_spawn_event_ecrit_une_ligne_signee_correlable(tmp_path):
    """L'événement réutilise le mécanisme existant (DispatchRecord + HMAC) et porte le
    MÊME triplet que le spawn_prepared : la corrélation est mécanique, pas narrative."""
    audit = tmp_path / "a.jsonl"
    prepare_dispatch("s9-build-standard", "r1", profile="standard", attempt=2,
                     audit_path=audit)
    assert append_spawn_event(EVENT_EXECUTED, "s9-build-standard", "r1", 2,
                              model="claude-x", audit_path=audit) is True

    prep, exe = _lines(audit)
    assert prep["event"] == EVENT_PREPARED and exe["event"] == EVENT_EXECUTED
    # corrélation par TRIPLET
    for champ in ("etape", "run_id", "attempt"):
        assert prep[champ] == exe[champ]
    # la preuve est SIGNÉE : une ligne fabriquée à la main ne peut pas s'y substituer
    assert verify_audit_line(exe) is True


def test_append_spawn_event_ne_leve_jamais(tmp_path):
    """Best-effort absolu : un chemin d'écriture impossible rend False, ne lève pas —
    une preuve manquante ne casse jamais un spawn ni un run."""
    impossible = tmp_path / "fichier.txt"
    impossible.write_text("je suis un fichier, pas un dossier", encoding="utf-8")
    assert append_spawn_event(EVENT_EXECUTED, "s9-build", "r", 1,
                              audit_path=impossible / "sous" / "a.jsonl") is False


def test_marker_key_pur():
    assert marker_key("bla FORGE_DISPATCH:s9-build:pong-01:3 bla") == ("s9-build", "pong-01", 3)
    # marqueur historique 2-champs -> attempt 0, même défaut que DispatchRecord.attempt
    assert marker_key("FORGE_DISPATCH:s4-archi:run1") == ("s4-archi", "run1", 0)
    assert marker_key("aucun marqueur") is None
    assert marker_key("") is None


def test_record_execution_et_authorization_depuis_un_marqueur(tmp_path):
    audit = tmp_path / "a.jsonl"
    assert record_execution("x FORGE_DISPATCH:s9-build:r:1 y", audit_path=audit) is True
    assert record_authorization("x FORGE_DISPATCH:s9-build:r:1 y", audit_path=audit) is True
    assert record_execution("pas de marqueur", audit_path=audit) is False
    events = [l["event"] for l in _lines(audit)]
    assert events == [EVENT_EXECUTED, EVENT_AUTHORIZED]


# --- 2. LE LECTEUR : spawn_proof ---------------------------------------------

def test_spawn_proof_rend_visible_l_ecart_prepare_execute(tmp_path):
    """LE test du lecteur : 3 préparations, 1 seule exécution prouvée -> l'écart et les
    triplets non prouvés deviennent visibles (c'est exactement ce que personne ne
    pouvait voir sur le run réel pong-01)."""
    audit = tmp_path / "a.jsonl"
    for att in (1, 2, 3):
        prepare_dispatch("s9-build-standard", "pong-x", profile="standard", attempt=att,
                         audit_path=audit)
    append_spawn_event(EVENT_EXECUTED, "s9-build-standard", "pong-x", 2, audit_path=audit)

    proof = spawn_proof("pong-x", audit_path=audit)
    assert proof["measured"] is True
    assert proof["prepared"] == 3
    assert proof["executed"] == 1
    assert proof["unproven"] == [
        {"etape": "s9-build-standard", "attempt": 1},
        {"etape": "s9-build-standard", "attempt": 3},
    ]


def test_spawn_proof_expose_la_duplication_de_preparation(tmp_path):
    """Le cas réel pong-01 : plusieurs lignes préparées pour UN SEUL triplet.
    `prepared` (lignes) >> `prepared_distinct` (triplets) rend la duplication lisible."""
    audit = tmp_path / "a.jsonl"
    for _ in range(7):
        prepare_dispatch("s9-build-standard", "pong-y", profile="standard", attempt=0,
                         audit_path=audit)
    proof = spawn_proof("pong-y", audit_path=audit)
    assert proof["prepared"] == 7
    assert proof["prepared_distinct"] == 1
    assert proof["executed"] == 0
    assert proof["unproven"] == [{"etape": "s9-build-standard", "attempt": 0}]


def test_spawn_proof_ignore_les_autres_runs(tmp_path):
    audit = tmp_path / "a.jsonl"
    prepare_dispatch("s9-build", "run-a", attempt=1, audit_path=audit)
    prepare_dispatch("s9-build", "run-b", attempt=1, audit_path=audit)
    append_spawn_event(EVENT_EXECUTED, "s9-build", "run-b", 1, audit_path=audit)
    assert spawn_proof("run-a", audit_path=audit)["executed"] == 0
    assert spawn_proof("run-b", audit_path=audit)["executed"] == 1


def test_spawn_proof_audit_absent_est_non_mesure_pas_un_zero(tmp_path):
    """RÈGLE DURE identique à cost/pool : un audit absent ne doit JAMAIS s'afficher en
    « 0 exécuté », qui affirmerait faussement qu'aucun spawn n'a eu lieu."""
    proof = spawn_proof("r", audit_path=tmp_path / "n_existe_pas" / "a.jsonl")
    assert proof["measured"] is False
    assert proof["executed"] == 0
    assert "non mesur" in proof["reason"].lower()


def test_spawn_proof_audit_vide_est_non_mesure(tmp_path):
    vide = tmp_path / "a.jsonl"
    vide.write_text("", encoding="utf-8")
    assert spawn_proof("r", audit_path=vide)["measured"] is False


def test_spawn_proof_ligne_tronquee_ou_non_signee_ne_casse_rien(tmp_path):
    """Écriture concurrente interrompue + ligne forgée à la main : la première est
    ignorée, la seconde n'est PAS comptée comme preuve (HMAC invalide)."""
    audit = tmp_path / "a.jsonl"
    prepare_dispatch("s9-build", "r", attempt=1, audit_path=audit)
    with open(audit, "a", encoding="utf-8") as fh:
        fh.write('{"run_id": "r", "etape": "s9-build", "event": "spawn_exec')  # tronquée
        fh.write("\n")
        fh.write(json.dumps({"run_id": "r", "etape": "s9-build", "attempt": 1,
                             "event": EVENT_EXECUTED}) + "\n")       # non signée
    proof = spawn_proof("r", audit_path=audit)
    assert proof["measured"] is True
    assert proof["executed"] == 0          # la ligne forgée ne prouve rien
    assert proof["unproven"] == [{"etape": "s9-build", "attempt": 1}]


def test_spawn_proof_lit_les_lignes_historiques_sans_champ_event(tmp_path):
    """Rétro-compat : les lignes écrites avant la Phase 2a n'ont ni `event` ni `attempt`
    — elles restent lues comme des préparations (le seul événement qui existait alors)."""
    audit = tmp_path / "a.jsonl"
    from forge.dispatch import sign_audit_record
    audit.write_text(json.dumps(sign_audit_record(
        {"run_id": "vieux", "etape": "s9-build-standard", "model": "m"})) + "\n",
        encoding="utf-8")
    proof = spawn_proof("vieux", audit_path=audit)
    assert proof["prepared"] == 1
    assert proof["unproven"] == [{"etape": "s9-build-standard", "attempt": 0}]


# --- 3. NON-RÉGRESSION D4 : le nouvel événement ne casse pas l'unicité --------

def test_spawn_executed_ne_compte_pas_dans_l_unicite_du_garde(tmp_path):
    """LE test de non-régression : préparation + exécution = 2 lignes sur le MÊME triplet.
    Si `check_spawn` les comptait toutes deux, il verrait count==2 et refuserait un spawn
    légitime comme un replay. L'unicité porte sur la PRÉPARATION seule."""
    audit = tmp_path / "a.jsonl"
    prepare_dispatch("s9-build-standard", "pong-z", profile="standard", attempt=1,
                     audit_path=audit)
    append_spawn_event(EVENT_EXECUTED, "s9-build-standard", "pong-z", 1, audit_path=audit)
    append_spawn_event(EVENT_AUTHORIZED, "s9-build-standard", "pong-z", 1, audit_path=audit)
    assert len(_lines(audit)) == 3

    allow, reason = check_spawn("FORGE_DISPATCH:s9-build-standard:pong-z:1", audit_path=audit)
    assert allow is True, reason
    code, _ = hook_decision("Task", "FORGE_DISPATCH:s9-build-standard:pong-z:1",
                            audit_path=audit)
    assert code == 0


def test_deux_preparations_restent_un_refus_meme_avec_des_evenements(tmp_path):
    """Le vrai replay (2 PRÉPARATIONS au même triplet) reste refusé : le filtrage par
    `event` n'a pas désarmé D4."""
    audit = tmp_path / "a.jsonl"
    for _ in range(2):
        prepare_dispatch("s9-build-standard", "pong-w", profile="standard", attempt=1,
                         audit_path=audit)
    append_spawn_event(EVENT_EXECUTED, "s9-build-standard", "pong-w", 1, audit_path=audit)
    allow, reason = check_spawn("FORGE_DISPATCH:s9-build-standard:pong-w:1", audit_path=audit)
    assert allow is False
    assert "ambigu" in reason.lower() or "replay" in reason.lower()


def test_un_executed_seul_n_autorise_aucun_spawn(tmp_path):
    """Une preuve d'exécution n'est PAS une autorisation : sans préparation, refus.
    (Sinon le nouvel événement deviendrait un contournement du contrat.)"""
    audit = tmp_path / "a.jsonl"
    append_spawn_event(EVENT_EXECUTED, "s9-build", "r", 1, audit_path=audit)
    allow, reason = check_spawn("FORGE_DISPATCH:s9-build:r:1", audit_path=audit)
    assert allow is False
    assert "aucun dispatch" in reason


# --- 4. CHEMIN B : driver / headless (aucun hook Task ne s'y déclenche) -------

class StubExecutor:
    """Exécuteur simulé — remplace `claude -p` (aucun vrai spawn dans un test)."""

    def __init__(self):
        self.calls = []

    def __call__(self, payload, decision, context):
        self.calls.append(context["dispatch_marker"])
        return {"ok": True, "output": f"artefact {payload.etape}"}


@pytest.fixture
def offline(monkeypatch):
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


def _driver_kw(tmp_path, exit_code=0):
    cfg = tmp_path / "oracles_test.json"
    cfg.write_text(json.dumps({"proj": {
        "cwd": str(tmp_path),
        "command": [sys.executable, "-c", f"import sys; sys.exit({exit_code})"],
    }}), encoding="utf-8")
    return dict(
        run_dir=tmp_path / "run",
        oracle_config=cfg,
        key_file=tmp_path / "forge_test.key",
        audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        builder_runs_path=tmp_path / "builder_runs.jsonl",
        journal_path=tmp_path / "journal.jsonl",
    )


def test_chemin_b_un_tour_d_executeur_ecrit_spawn_executed(tmp_path, offline):
    """Preuve du chemin B : l'exécuteur simulé revient -> une ligne `spawn_executed`
    existe pour l'étape LLM, avec le MÊME triplet que le marqueur remis à l'exécuteur."""
    kw = _driver_kw(tmp_path)
    stub = StubExecutor()
    ForgeDriver("proj", "proj-b", profile="micro", executor=stub, **kw).run()

    assert stub.calls == ["FORGE_DISPATCH:s9-build:proj-b:1"]
    executed = [l for l in _lines(kw["audit_path"]) if l["event"] == EVENT_EXECUTED]
    s9 = [l for l in executed if l["etape"] == "s9-build"]
    assert len(s9) == 1
    assert (s9[0]["run_id"], s9[0]["attempt"]) == ("proj-b", 1)
    assert s9[0]["model"]  # le driver connaît le payload : il ne laisse pas vide


def test_chemin_b_sans_executeur_aucune_preuve_d_execution(tmp_path, offline):
    """Contre-épreuve : sans exécuteur, le run HALTE — il doit rester une préparation
    NON PROUVÉE, jamais une ligne d'exécution de complaisance."""
    kw = _driver_kw(tmp_path)
    report = ForgeDriver("proj", "proj-c", profile="micro", executor=None, **kw).run()
    assert report["status"] == "HALTED"
    assert [l for l in _lines(kw["audit_path"]) if l["event"] == EVENT_EXECUTED] == []
    proof = spawn_proof("proj-c", audit_path=kw["audit_path"])
    assert proof["prepared"] == 1 and proof["executed"] == 0
    assert proof["unproven"] == [{"etape": "s9-build", "attempt": 1}]


def test_le_rapport_de_fin_de_run_expose_la_preuve(tmp_path, offline):
    """Le LECTEUR est branché : le rapport imprimé par run_real.py porte `spawn`, et
    un run nominal n'y laisse AUCUN triplet non prouvé."""
    kw = _driver_kw(tmp_path)
    report = ForgeDriver("proj", "proj-d", profile="micro", executor=StubExecutor(),
                         **kw).run()
    assert report["software_verdict"] == "OK"
    spawn = report["spawn"]
    assert spawn["measured"] is True
    assert spawn["prepared"] == 3          # micro = s9-build + s10a + s12
    assert spawn["executed"] == 3
    assert spawn["unproven"] == []


def test_le_rapport_distingue_non_mesure_d_un_zero(tmp_path, offline):
    """Même règle dure que cost/pool dans ce même rapport : audit absent => measured
    False + raison, jamais un « 0 exécuté » silencieux."""
    d = ForgeDriver("proj", "proj-e", run_dir=tmp_path / "run", profile="micro",
                    audit_path=tmp_path / "n_existe_pas" / "audit.jsonl")
    report = d._final_report({
        "run_id": "proj-e", "project": "proj", "profile": "micro", "is_game": False,
        "escalations": 0, "pool_attempts": 0, "run_status": "DONE",
        "steps": {"s9-build": {"status": "OK", "attempts": 1}},
    })
    assert report["spawn"]["measured"] is False
    assert "non mesur" in report["spawn"]["reason"].lower()


def test_un_retry_produit_une_preuve_par_tentative(tmp_path, offline):
    """Un oracle rouge -> escalade -> 2e tentative de s9-build : chaque tentative a SA
    préparation ET SA preuve d'exécution (le triplet reste la clé)."""
    kw = _driver_kw(tmp_path, exit_code=1)
    report = ForgeDriver("proj", "proj-f", profile="micro", executor=StubExecutor(),
                         pool_size=1, **kw).run()
    assert report["software_verdict"] == "FAIL"
    s9 = [(l["event"], l["attempt"]) for l in _lines(kw["audit_path"])
          if l["etape"] == "s9-build"]
    assert (EVENT_PREPARED, 1) in s9 and (EVENT_EXECUTED, 1) in s9
    assert (EVENT_PREPARED, 2) in s9 and (EVENT_EXECUTED, 2) in s9
    assert report["spawn"]["unproven"] == []


# --- 5. CHEMIN A : le hook PostToolUse réel, en sous-processus ----------------

def _run_hook_entrypoint(payload: str) -> subprocess.CompletedProcess:
    """Exécute le VRAI script de hook EXACTEMENT comme le harnais Claude Code : le
    fichier lui-même, JSON sur stdin. Réservé aux cas qui NE DOIVENT RIEN ÉCRIRE (sinon
    ils écriraient dans l'audit réel du dépôt) — c'est le code de sortie qu'on mesure."""
    return subprocess.run([sys.executable, str(POSTTOOL_HOOK)], input=payload,
                          capture_output=True, text=True, timeout=60)


def _run_hook_redirected(payload: str, audit: Path) -> subprocess.CompletedProcess:
    """Même script, même point d'entrée `__main__` (donc même code de sortie), mais
    l'audit par défaut est redirigé vers un fichier temporaire : c'est ce qui permet
    d'observer la ligne ÉCRITE sans toucher `EVIDENCE/bundles/`."""
    script = (
        "import sys, pathlib, runpy\n"
        f"sys.path.insert(0, {str(REPO_ROOT / 'scripts')!r})\n"
        "import forge.dispatch as d\n"
        f"d.DEFAULT_AUDIT = pathlib.Path({str(audit)!r})\n"
        f"runpy.run_path({str(POSTTOOL_HOOK)!r}, run_name='__main__')\n"
    )
    return subprocess.run([sys.executable, "-c", script], input=payload,
                          capture_output=True, text=True, timeout=60)


def test_hook_posttool_existe_et_est_du_python_valide():
    assert POSTTOOL_HOOK.exists(), POSTTOOL_HOOK
    compile(POSTTOOL_HOOK.read_text(encoding="utf-8"), str(POSTTOOL_HOOK), "exec")


def test_hook_posttool_sans_marqueur_sort_0_sans_ecrire(tmp_path):
    audit = tmp_path / "a.jsonl"
    payload = json.dumps({"tool_name": "Task", "tool_input": {"prompt": "sans marqueur"}})
    assert _run_hook_entrypoint(payload).returncode == 0     # vrai point d'entrée
    res = _run_hook_redirected(payload, audit)
    assert res.returncode == 0, res.stderr
    assert not audit.exists()                                # et RIEN n'est écrit


def test_hook_posttool_avec_marqueur_ecrit_spawn_executed(tmp_path):
    audit = tmp_path / "a.jsonl"
    res = _run_hook_redirected(json.dumps({
        "tool_name": "Task",
        "tool_input": {"prompt": "blabla FORGE_DISPATCH:s9-build-standard:pong-h:2"},
        "tool_response": {"ok": True},
    }), audit)
    assert res.returncode == 0, res.stderr
    ligne, = _lines(audit)
    assert ligne["event"] == EVENT_EXECUTED
    assert (ligne["etape"], ligne["run_id"], ligne["attempt"]) == (
        "s9-build-standard", "pong-h", 2)
    assert verify_audit_line(ligne) is True


@pytest.mark.parametrize("payload", ["", "   ", "pas du json", "[]", "null",
                                     '{"tool_name": "Task"}',
                                     '{"tool_name": "Task", "tool_input": "pas un dict"}',
                                     '{"tool_name": "Task", "tool_input": {"prompt": null}}'])
def test_hook_posttool_malforme_sort_0_sans_crash(tmp_path, payload):
    """Fail-open ABSOLU : le hook tourne dans la session en cours — aucune entrée ne
    doit pouvoir le faire sortir non nul (il perturberait TOUS les appels d'outil).
    Mesuré sur le VRAI point d'entrée, celui que le harnais exécute."""
    assert _run_hook_entrypoint(payload).returncode == 0
    audit = tmp_path / f"a{abs(hash(payload))}.jsonl"
    res = _run_hook_redirected(payload, audit)
    assert res.returncode == 0, res.stderr
    assert not audit.exists()


def test_hook_posttool_autre_outil_ne_prouve_rien(tmp_path):
    """Un marqueur dans un appel Read/Bash n'est pas un spawn : rien n'est écrit."""
    audit = tmp_path / "a.jsonl"
    payload = json.dumps({"tool_name": "Read",
                          "tool_input": {"prompt": "FORGE_DISPATCH:s9-build:r:1"}})
    assert _run_hook_entrypoint(payload).returncode == 0
    assert _run_hook_redirected(payload, audit).returncode == 0
    assert not audit.exists()
