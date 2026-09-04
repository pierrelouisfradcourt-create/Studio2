"""DIRECTOR v0 — noyau déterministe (Lots 3 et 4, plan V2 2026-09-03, GO Pierre, D3).

CE QU'IL FAIT, et rien d'autre :
  1. LIT le GAME_BLUEPRINT, l'état courant (`director_state.json`), les preuves (couverture design
     et construite recalculées par l'oracle de production, reçus d'oracle du run), le registre.
  2. MESURE les manques (section absente, jointure non JOINED, jeu non construit, oracle rouge) et
     rend une ACTION déterministe : `convoke` · `reconvoke` (avec message d'objection émis par
     `forge.emitter`) · `gate_open` · `build` · `qa` · `humangate` · `halt` (question -> Pierre).
  3. Après CHAQUE convocation, MESURE L'EFFET lui-même — jamais rapporté par la capacité :
        effect   CHANGED · NO_EFFECT · REGRESSED   (contrat Lot 3, inchangé)
        progress IMPROVED · NONE                   (Lot 4 : un CHANGED sans progrès est nommé)
     REGRESSED = un régime de jointure recule, une couverture baisse, ou des fantômes apparaissent.
  4. RÉAGIT : REGRESSED -> objection au producteur (journal append-only + trace de run, acquittement
     mesuré sur l'artefact désigné ET la restitution texte — K4) et UNE re-convocation ; encore
     REGRESSED ou NO_EFFECT -> HALT (options accept / revert). Deux NO_EFFECT ou deux CHANGED sans
     progrès consécutifs sur le même signal -> HALT. Oracle rouge après build -> re-convocation du
     builder au tier supérieur (échelle `forge.escalate`, portée builder seule — ESC-1), bornée.
  5. JOURNALISE chaque décision en champs structurés (K6) : `decisions.jsonl` + section `decisions`.
     La suite RÉELLE des convocations est enregistrée (`sequence`) et comparée aux profils ORDER.

CE QU'IL N'EST PAS : un agent LLM (aucun appel modèle ici), un ordre d'étapes (la suite dépend de
l'état et n'est imprimable qu'après l'avoir observé), un juge de valeur (vision, contraintes,
cibles, acceptation d'un écart, merge : Pierre), un oracle (le `software_verdict` vient des reçus
du driver, jamais d'ici). Une demande de l'agent (`requests`) est consignée, jamais exécutée (K7).
NO_CLAIM_ALLOWED.

Usage : python -m forge.director run --blueprint <json> --run-id <id> [--max-steps N] [--timeout S]
                                    [--out <json>] [--stop-at-gate]
        python -m forge.director next --blueprint <json> --run-id <id>
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

from forge import blueprint as bp
from forge import build_orchestrator as bo
from forge import capability as cap
from forge.amendment_log import new_message_id, read_messages
from forge.consumption import CONSUMED, NOT_CONSUMED, _contains_ref
from forge.coverage import coverage_of
from forge.emitter import EmitterError, notify
from forge.escalate import MAX_ESCALATIONS, next_tier, tier_of
from forge.run_real import default_task_by_step

REPO_ROOT = Path(__file__).resolve().parents[1]
STATE_FILE = "director_state.json"
DECISIONS_FILE = "decisions.jsonl"
ANSWERS_FILE = "answers.json"          # K8 : réponses humaines structurées, jamais de prose

CHANGED, NO_EFFECT, REGRESSED = "CHANGED", "NO_EFFECT", "REGRESSED"
IMPROVED, NONE = "IMPROVED", "NONE"
REGIME_RANK = {"EMPTY_FORM": 0, "VOID": 1, "PARTIAL": 2, "JOINED": 3}
MAX_NO_EFFECT = 2          # 2 NO_EFFECT consécutifs sur le même signal => HALT
MAX_NO_PROGRESS = 2        # 2 CHANGED sans progrès consécutifs => HALT (Lot 4)

# Codes de diagnostic (producteur : forge.director, sur des mesures d'oracle)
SECTION_ABSENT = "SECTION_ABSENT"
JOIN_LINES_WITHOUT_COUVRE = "JOIN_LINES_WITHOUT_COUVRE"
JOIN_GHOST_COVERAGE = "JOIN_GHOST_COVERAGE"
JOIN_CAPACITY_UNCOVERED = "JOIN_CAPACITY_UNCOVERED"
JOIN_NOT_MEASURED = "JOIN_NOT_MEASURED"
REGRESSION_DETECTED = "REGRESSION_DETECTED"
NO_EFFECT_REPEATED = "NO_EFFECT_REPEATED"
NO_PROGRESS_REPEATED = "NO_PROGRESS_REPEATED"
CAPABILITY_UNAVAILABLE = "CAPABILITY_UNAVAILABLE"
BLOCKING_QUESTION_OPEN = "BLOCKING_QUESTION_OPEN"
BUILD_REQUIRED = "BUILD_REQUIRED"
ORACLE_RED = "ORACLE_RED"
ORACLE_RED_PERSISTENT = "ORACLE_RED_PERSISTENT"
QA_REQUIRED = "QA_REQUIRED"
VERDICT_NOT_AUTHENTIC = "VERDICT_NOT_AUTHENTIC"

_JOIN_KEYS = ("regime", "status", "capacites", "capacites_couvertes", "lignes",
              "lignes_sans_couvre", "capacites_non_couvertes", "couverture_fantome", "forme_satisfaite")
TERMINAL_KINDS = ("halt", "humangate")


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


# ============================================================================ état persistant

def new_state(run_id: str, project: str) -> dict:
    return {"schema": "DIRECTOR_STATE/v0", "run_id": run_id, "project": project, "steps": 0,
            "status": "RUNNING", "pending_question": None, "accepted": [], "signals": {},
            "convocations": {}, "snapshots": {}, "decisions": [], "sequence": [],
            "build": {"attempts": 0, "last_model": None, "qa": None},
            "last_problems": []}


def load_state(run_dir: Path, run_id: str, project: str) -> dict:
    p = Path(run_dir) / STATE_FILE
    if p.exists():
        st = json.loads(p.read_text(encoding="utf-8"))
        for k, v in new_state(run_id, project).items():     # champs ajoutés en Lot 4 : défauts
            st.setdefault(k, v)
        return st
    return new_state(run_id, project)


def save_state(run_dir: Path, state: dict) -> None:
    run_dir = Path(run_dir)
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / STATE_FILE).write_text(json.dumps(state, ensure_ascii=False, indent=1, sort_keys=True),
                                      encoding="utf-8")


def read_answers(run_dir: Path) -> dict:
    p = Path(run_dir) / ANSWERS_FILE
    if not p.exists():
        return {}
    data = json.loads(p.read_text(encoding="utf-8"))
    return data if isinstance(data, dict) else {}


# ============================================================================ mesure

def measure(blueprint: dict) -> dict:
    """Ce que le Director observe : versions/sha des sections (et de leurs sous-entrées) + couvertures."""
    sections = {}
    for s, m in blueprint["sections"].items():
        entry_shas = {}
        if isinstance(m.get("content"), dict):
            for k, v in m["content"].items():
                if isinstance(v, dict) and "content" in v:
                    entry_shas[k] = bp.content_sha256(v["content"])
        sections[s] = {"version": m["version"], "content_sha256": m["content_sha256"], "entries": entry_shas}
    return {"sections": sections,
            "coverage": {w: _join_view(coverage_of(blueprint, which=w)) for w in ("design", "built")}}


def _join_view(cov: dict) -> dict:
    return {k: cov.get(k) for k in _JOIN_KEYS}


def compare_join(before: dict, after: dict) -> list[str]:
    """Raisons de RÉGRESSION entre deux vues de jointure (vide = aucune)."""
    reasons: list[str] = []
    rb, ra = REGIME_RANK.get(before.get("regime")), REGIME_RANK.get(after.get("regime"))
    if rb is not None and ra is not None and ra < rb:
        reasons.append(f"régime {before['regime']} -> {after['regime']}")
    cb, ca = before.get("capacites_couvertes"), after.get("capacites_couvertes")
    if isinstance(cb, int) and isinstance(ca, int) and ca < cb:
        reasons.append(f"capacités couvertes {cb} -> {ca}")
    fb, fa = before.get("couverture_fantome") or 0, after.get("couverture_fantome") or 0
    if isinstance(fb, int) and isinstance(fa, int) and fa > fb:
        reasons.append(f"fantômes {fb} -> {fa}")
    return reasons


def improvements(before: dict, after: dict) -> list[str]:
    """Raisons de PROGRÈS entre deux vues de jointure (vide = aucun)."""
    out: list[str] = []
    rb, ra = REGIME_RANK.get(before.get("regime")), REGIME_RANK.get(after.get("regime"))
    if ra is not None and (rb is None or ra > rb):
        out.append(f"régime {before.get('regime')} -> {after['regime']}")
    cb, ca = before.get("capacites_couvertes"), after.get("capacites_couvertes")
    if isinstance(ca, int) and (not isinstance(cb, int) or ca > cb):
        out.append(f"capacités couvertes {cb} -> {ca}")
    fb, fa = before.get("couverture_fantome"), after.get("couverture_fantome")
    if isinstance(fb, int) and isinstance(fa, int) and fa < fb:
        out.append(f"fantômes {fb} -> {fa}")
    return out


def _entry_sha(measured: dict, path: str) -> str | None:
    sec, _, entry = path.partition(".")
    m = measured["sections"].get(sec) or {}
    return m.get("entries", {}).get(entry) if entry else m.get("content_sha256")


def effect_of(before: dict, after: dict, section_written: str | None) -> tuple[str, list[str]]:
    """L'effet d'une convocation (contrat Lot 3) : CHANGED / NO_EFFECT / REGRESSED."""
    reasons: list[str] = []
    for w in ("design", "built"):
        for r in compare_join(before["coverage"][w], after["coverage"][w]):
            reasons.append(f"{w}: {r}")
    if reasons:
        return REGRESSED, reasons
    if section_written is None:
        return NO_EFFECT, ["aucune section écrite"]
    sb, sa = _entry_sha(before, section_written), _entry_sha(after, section_written)
    if sb == sa:
        return NO_EFFECT, [f"{section_written}: contenu identique (sha inchangé)"]
    sec = section_written.split(".")[0]
    return CHANGED, [f"{section_written}: v{before['sections'][sec]['version']} -> v{after['sections'][sec]['version']}"]


def progress_of(before: dict, after: dict) -> tuple[str, list[str]]:
    """Le progrès (Lot 4) : IMPROVED si une couverture a progressé, sinon NONE. Ne touche pas `effect`."""
    reasons: list[str] = []
    for w in ("design", "built"):
        for r in improvements(before["coverage"][w], after["coverage"][w]):
            reasons.append(f"{w}: {r}")
    return (IMPROVED, reasons) if reasons else (NONE, ["aucune couverture n'a progressé"])


# ============================================================================ politique

def _open_blocking_questions(blueprint: dict) -> list[dict]:
    qs = blueprint["sections"]["questions"].get("content") or []
    return [q for q in qs if isinstance(q, dict) and q.get("blocking") and q.get("answer") in (None, "")]


def _section_present(blueprint: dict, ref: str) -> bool:
    section, _, entry = ref.partition(".")
    content = blueprint["sections"][section].get("content")
    if not entry:
        return content is not None
    sub = (content or {}).get(entry) if isinstance(content, dict) else None
    return isinstance(sub, dict) and sub.get("content") is not None


def diagnose_join(view: dict) -> tuple[str, str] | None:
    """(code, capacité responsable) depuis une vue de jointure non JOINED ; None si JOINED."""
    regime = view.get("regime")
    if regime == "JOINED":
        return None
    if regime in (None, "NOT_MEASURED", "NOT_APPLICABLE"):
        return JOIN_NOT_MEASURED, "wiremap"
    if (view.get("couverture_fantome") or 0) > 0:
        return JOIN_GHOST_COVERAGE, "wiremap"
    if (view.get("lignes_sans_couvre") or 0) > 0:
        return JOIN_LINES_WITHOUT_COUVRE, "wiremap"
    return JOIN_CAPACITY_UNCOVERED, "wiremap"


def _signal_key(path: str, capability: str) -> str:
    """Clé d'un signal = CHEMIN de section visé + capacité responsable — pas le code du diagnostic,
    qui peut changer d'une mesure à l'autre alors que la responsabilité ne change pas."""
    return f"{path}@{capability}"


def _sig(state: dict, key: str) -> dict:
    return state["signals"].get(key, {"no_effect": 0, "regressed": 0, "no_progress": 0,
                                       "last_effect": None, "convocations": 0})


def next_action(blueprint: dict, state: dict, measured: dict, registry: dict | None = None) -> dict:
    """LA politique : une table état -> action, sans LLM, sans ordre pré-écrit."""
    reg = registry or cap.load_registry()
    if state.get("pending_question"):
        return {"kind": "halt", "code": state["pending_question"]["code"],
                "question": state["pending_question"], "reason": "question en attente de réponse (answers.json)"}
    open_q = _open_blocking_questions(blueprint)
    if open_q:
        q = open_q[0]
        return {"kind": "halt", "code": BLOCKING_QUESTION_OPEN,
                "question": {"id": q.get("id"), "code": BLOCKING_QUESTION_OPEN, "to": q.get("to"),
                             "text": q.get("about") or q.get("why"), "signal": "questions@pierre"},
                "reason": f"question bloquante ouverte {q.get('id')!r}"}
    # --- conception : sections dans l'ordre de dépendance des LECTURES (registre), pas d'un profil
    for ref, capability in (("gameplay", "contract_author"), ("understanding.prisme", "prisme"),
                            ("feature_map", "decompose"), ("architecture_contract", "architect"),
                            ("wiremap.design", "wiremap")):
        if _section_present(blueprint, ref):
            continue
        spec = cap.spec(capability, reg)
        key = _signal_key(ref, capability)
        if spec.get("locked") or not spec["invokable_v0"]:
            return _halt_question(state, CAPABILITY_UNAVAILABLE, capability,
                                  f"section {ref!r} absente et capacité {capability!r} indisponible : "
                                  f"{spec.get('locked') or spec.get('invokable_reason')}",
                                  options=["provide_section", "skip"], signal=key)
        return {"kind": "convoke", "capability": capability, "code": SECTION_ABSENT, "signal": key,
                "path": ref, "reason": f"section {ref!r} absente", "message": None}
    # --- porte de suffisance : jointure de design
    view = measured["coverage"]["design"]
    diag = diagnose_join(view)
    if diag is not None:
        code, capability = diag
        key = _signal_key("wiremap.design", capability)
        if key not in state.get("accepted", []):
            sig = _sig(state, key)
            if sig["no_effect"] >= MAX_NO_EFFECT:
                return _halt_question(state, NO_EFFECT_REPEATED, capability,
                                      f"{sig['no_effect']} convocations de {capability!r} sans effet sur {code}",
                                      options=["accept", "provide_section", "skip"], measure=view, signal=key)
            if sig["no_progress"] >= MAX_NO_PROGRESS:
                return _halt_question(state, NO_PROGRESS_REPEATED, capability,
                                      f"{sig['no_progress']} convocations de {capability!r} qui changent la "
                                      f"section sans faire progresser {code}",
                                      options=["accept", "provide_section", "skip"], measure=view, signal=key)
            if sig["regressed"] >= 1 and sig["convocations"] >= 2 and sig["last_effect"] != CHANGED:
                return _halt_question(state, REGRESSION_DETECTED, capability,
                                      f"régression non résorbée après objection ({capability!r}, {code}, "
                                      f"dernier effet {sig['last_effect']})",
                                      options=["accept", "revert", "skip"], measure=view, signal=key)
            message = _objection(state, capability, code, view, sig) if sig["convocations"] > 0 else None
            return {"kind": "reconvoke" if sig["convocations"] > 0 else "convoke", "capability": capability,
                    "code": code, "signal": key, "path": "wiremap.design", "measure": view,
                    "reason": f"jointure de design {view.get('regime')} : {code}", "message": message}
        gate_code = "SUFFICIENCY_ACCEPTED_BY_PIERRE"
    else:
        gate_code = "SUFFICIENCY_JOINED"
    if state.get("status") not in ("GATE_OPEN", "BUILT", "QA_DONE", "HUMANGATE_READY"):
        return {"kind": "gate_open", "code": gate_code, "measure": view,
                "reason": "toute capacité portée par une ligne de wiremap, aucun fantôme"
                          if gate_code == "SUFFICIENCY_JOINED" else "écart accepté explicitement par Pierre"}
    # --- construction, QA, évidence, HumanGate
    return _next_build_action(blueprint, state, measured, reg)


def _next_build_action(blueprint: dict, state: dict, measured: dict, reg: dict) -> dict:
    b = state["build"]
    key = _signal_key("wiremap.built", "builder")
    built_present = _section_present(blueprint, "wiremap.built")
    built_version = blueprint["sections"]["wiremap"]["version"] if built_present else None
    qa = b.get("qa")
    if b["attempts"] == 0 or (not built_present and b["attempts"] <= MAX_ESCALATIONS):
        return {"kind": "build", "capability": "builder", "code": BUILD_REQUIRED, "signal": key,
                "path": "wiremap.built", "reason": "jeu non construit", "message": None, "model_override": None}
    if not built_present:
        return _halt_question(state, ORACLE_RED_PERSISTENT, "builder",
                              f"{b['attempts']} build(s) sans wiremap construite", options=["accept", "skip"], signal=key)
    if qa is None or qa.get("built_version") != built_version:
        return {"kind": "qa", "code": QA_REQUIRED, "signal": _signal_key("verdict", "qa"),
                "reason": "jeu construit, oracles non rendus sur cette version"}
    if qa.get("software_verdict") == "OK" and qa.get("verify_run") == "AUTHENTIQUE":
        return {"kind": "humangate", "code": "VERDICT_OK_AUTHENTIC", "signal": _signal_key("verdict", "pierre"),
                "reason": "verdict signé OK et authentifié : dossier pour Pierre"}
    if qa.get("software_verdict") == "OK":
        return _halt_question(state, VERDICT_NOT_AUTHENTIC, "evidence", "verdict OK mais non authentifié",
                              options=["skip"], measure=qa, signal=_signal_key("verdict", "qa"))
    # oracle rouge : réaction = re-convocation du builder au tier supérieur, bornée (ESC-1 : builder seul)
    last_model = b.get("last_model") or ""
    tier = next_tier(last_model) if tier_of(last_model) else None
    escalations_done = max(b["attempts"] - 1, 0)
    if tier is None or escalations_done >= MAX_ESCALATIONS:
        return _halt_question(state, ORACLE_RED_PERSISTENT, "builder",
                              f"oracles rouges après {b['attempts']} build(s) (dernier tier {last_model!r}) : "
                              f"{[p['code'] for p in state.get('last_problems') or []]}",
                              options=["accept", "requalify", "skip"], measure=qa.get("statuses"), signal=key)
    return {"kind": "build", "capability": "builder", "code": ORACLE_RED, "signal": key, "path": "wiremap.built",
            "reason": f"oracle(s) rouge(s) {[p['producer'] for p in state.get('last_problems') or []]} : "
                      f"re-convocation du builder au tier {tier}",
            "message": _objection_oracles(state, qa), "model_override": tier}


def _halt_question(state: dict, code: str, capability: str, text: str, *, options: list[str],
                   measure: dict | None = None, signal: str = "") -> dict:
    qid = f"Q-{state['run_id']}-{state['steps'] + 1}-{code}"
    question = {"id": qid, "code": code, "capability": capability, "signal": signal, "to": "pierre",
                "text": text, "options": options, "measure": measure, "asked_at": _now()}
    return {"kind": "halt", "code": code, "question": question, "reason": text}


def _objection(state: dict, capability: str, code: str, view: dict, sig: dict) -> dict:
    issued = _now()
    return {
        "id": new_message_id(f"{code} {capability} {state['run_id']}", issued), "type": "objection",
        "from": "director", "to": [capability],
        "subject": f"{code} : ta production précédente n'a pas joint la feature_map",
        "reason": (f"jointure de design mesurée par check_wiremap_contract : régime {view.get('regime')}, "
                   f"{view.get('capacites_couvertes')}/{view.get('capacites')} capacités couvertes, "
                   f"{view.get('lignes_sans_couvre')} ligne(s) sans couvre, {view.get('couverture_fantome')} "
                   f"fantôme(s). Effet de ta dernière convocation : {sig.get('last_effect')}. Chaque ligne "
                   f"`couvre` doit citer l'id EXACT d'une capacité de la feature_map lue dans le Blueprint ; "
                   f"cite l'identifiant de ce message dans ta restitution."),
        "impact": ["wiremap.design", "porte de suffisance"], "evidence_ref": [f"decisions.jsonl#{state['steps']}"],
        "blocking": False, "issued_at": issued,
    }


def _objection_oracles(state: dict, qa: dict) -> dict:
    issued = _now()
    problems = state.get("last_problems") or []
    if not problems or all(not p.get("message") for p in problems):
        # reçus signés relus depuis le state du run QA : l'objection porte les raisons de l'oracle
        problems = bo.qa_problems_from_state((qa or {}).get("state_path")) or problems
        state["last_problems"] = problems
    return {
        "id": new_message_id(f"ORACLE_RED builder {state['run_id']}", issued), "type": "objection",
        "from": "director", "to": ["builder"],
        "subject": "ORACLE_RED : le jeu construit ne passe pas les oracles déterministes",
        "reason": ("Reçus d'oracle (producteur = l'oracle, jamais un jugement) : " + " | ".join(
            f"{p['producer']} {p['code']} : {p['message'][:300]}" for p in problems))[:3000]
                  + ". Corrige dans ton ownership, tiens la WireMap à jour, cite l'identifiant de ce message.",
        "impact": ["GAMES/<project>", "wiremap.built"], "evidence_ref": [str((qa or {}).get("state_path"))],
        "blocking": False, "issued_at": issued,
    }


# ============================================================================ exécution

class Director:
    def __init__(self, blueprint: dict, run_dir: Path, *, run_id: str, executor=None,
                 audit_path: Path | None = None, journal_dir: Path | None = None,
                 registry: dict | None = None, timeout_s: float | None = None,
                 stop_at_gate: bool = True, qa_runner=None):
        self.blueprint = blueprint
        self.run_dir = Path(run_dir)
        self.run_id = run_id
        self.executor = executor
        self.audit_path = audit_path
        self.journal_dir = journal_dir
        self.registry = registry or cap.load_registry()
        self.timeout_s = timeout_s
        self.stop_at_gate = stop_at_gate          # Lot 3 : s'arrêter à la porte (défaut conservé)
        self.qa_runner = qa_runner                # injectable (tests) ; défaut = build_orchestrator
        self.state = load_state(self.run_dir, run_id, blueprint.get("project", ""))

    # ---- décisions (K6)
    def _decide(self, kind: str, **fields) -> dict:
        self.state["steps"] += 1
        rec = {"id": f"D-{self.run_id}-{self.state['steps']}", "ts": _now(), "by": "director", "kind": kind,
               "signal": None, "measure": None, "diagnosis_code": None, "effect": None, "progress": None, "refs": []}
        rec.update(fields)
        self.state["decisions"].append(rec["id"])
        self.run_dir.mkdir(parents=True, exist_ok=True)
        with open(self.run_dir / DECISIONS_FILE, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(rec, ensure_ascii=False, sort_keys=True) + "\n")
        current = list(self.blueprint["sections"]["decisions"].get("content") or [])
        bp.write_section(self.blueprint, "decisions", current + [rec], writer="director",
                         source={"path": str(self.run_dir / DECISIONS_FILE), "sha256": None,
                                 "status": "JOURNAL", "run_id": self.run_id})
        save_state(self.run_dir, self.state)
        return rec

    # ---- K8 : réponses humaines
    def apply_answers(self) -> dict | None:
        pq = self.state.get("pending_question")
        if not pq:
            return None
        ans = read_answers(self.run_dir).get(pq["id"])
        if not isinstance(ans, dict) or ans.get("by") != "pierre" or not ans.get("answer"):
            return None
        answer = str(ans["answer"])
        signal = pq.get("signal") or _signal_key("?", pq.get("capability", ""))
        rec_fields = {"signal": signal, "diagnosis_code": pq["code"],
                      "measure": {"question": pq["id"], "answer": answer, "by": ans.get("by")}, "refs": [pq["id"]]}
        if answer == "revert":
            section = signal.split("@")[0].split(".")[0]
            sig = self.state["signals"].get(signal) or {}
            snaps = self.state["snapshots"].get(section) or []
            snap = sig.get("revert_to") or (snaps[-1] if snaps else None)
            if snap is None:
                self.state["pending_question"] = None
                return self._decide("answer_unapplicable", reason="aucun snapshot à restaurer", **rec_fields)
            content = json.loads(Path(snap["path"]).read_text(encoding="utf-8"))
            rec = self._decide("revert", reason=f"restauration de {section} v{snap['version']} sur réponse de Pierre",
                               **rec_fields)
            bp.restore_section(self.blueprint, section, {"content": content, "version": snap["version"],
                                                          "path": snap["path"]},
                               decision_id=rec["id"], authorized_by="pierre")
            self.state["signals"].pop(signal, None)
        elif answer == "accept":
            self.state.setdefault("accepted", []).append(signal)
            rec = self._decide("accept_gap", reason="écart accepté explicitement par Pierre", **rec_fields)
        elif answer == "requalify":
            # Pierre demande de RE-JUGER le jeu tel qu'il est sur disque (ex. build interrompu par un
            # timeout qui a pourtant écrit) : la wiremap du run est reprise comme `wiremap.built`
            # (écrivain builder, source SALVAGED), la QA se rejoue sur cette version. Aucun jugement
            # ici : ce sont les oracles qui diront.
            post = self.run_dir / "wiremap.json"
            if not post.exists():
                self.state["pending_question"] = None
                return self._decide("answer_unapplicable", reason="requalify : aucune wiremap.json dans le run",
                                    **rec_fields)
            data = json.loads(post.read_text(encoding="utf-8"))
            current = self.blueprint["sections"]["wiremap"].get("content")
            composite = dict(current) if isinstance(current, dict) else {}
            composite["built"] = {"source": {"path": str(post), "sha256": bp.file_sha256(post), "status": "SALVAGED",
                                             "run_id": self.run_id, "authorized_by": "pierre"}, "content": data}
            bp.write_section(self.blueprint, "wiremap", composite, writer="builder",
                             source={"path": None, "sha256": None, "status": "COMPOSITE", "run_id": self.run_id})
            self.state["build"]["qa"] = None          # la QA doit se rejouer sur cette version
            self.state["status"] = "BUILT"
            rec = self._decide("requalify", reason="re-jugement demandé par Pierre : wiremap du run reprise "
                                                   "comme wiremap.built, QA à rejouer", **rec_fields)
        else:
            rec = self._decide("answer_recorded", reason=f"réponse de Pierre : {answer[:200]}", **rec_fields)
            self.state["signals"].pop(signal, None)
        self.state["pending_question"] = None
        if self.state["status"] == "HALTED":
            self.state["status"] = "RUNNING"
        save_state(self.run_dir, self.state)
        return rec

    # ---- snapshots
    def _snapshot(self, section: str) -> dict:
        meta = self.blueprint["sections"][section]
        d = self.run_dir / "snapshots"
        d.mkdir(parents=True, exist_ok=True)
        path = d / f"{section}.v{meta['version']}.json"
        path.write_text(json.dumps(meta["content"], ensure_ascii=False), encoding="utf-8")
        snap = {"section": section, "version": meta["version"], "content_sha256": meta["content_sha256"],
                "path": str(path)}
        self.state["snapshots"].setdefault(section, []).append(snap)
        return snap

    # ---- K4 : acquittement sur l'artefact désigné ET la restitution texte de l'agent
    def _consumption(self, message: dict | None, res: dict) -> dict | None:
        if not message:
            return None
        checked: list[str] = []
        found: list[str] = []
        for p in (res.get("artifact"), res.get("output_file")):
            if not p:
                continue
            path = Path(p)
            if path.exists():
                checked.append(path.name)
                if _contains_ref(path, message["id"]):
                    found.append(path.name)
        return {"status": CONSUMED if found else NOT_CONSUMED, "declared_by": "capability_registry",
                "checked": checked, "found_in": found}

    # ---- un pas
    def step(self) -> dict:
        self.apply_answers()
        before = measure(self.blueprint)
        action = next_action(self.blueprint, self.state, before, self.registry)
        kind = action["kind"]
        if kind == "halt":
            q = action["question"]
            if self.state.get("pending_question") is None or self.state["pending_question"]["id"] != q["id"]:
                self.state["pending_question"] = q
                self.state["status"] = "HALTED"
                rec = self._decide("halt", signal=q.get("signal") or action["code"], diagnosis_code=action["code"],
                                   measure=q.get("measure"), reason=action["reason"], refs=[q["id"]], question=q)
            else:
                rec = {"kind": "halt", "id": None, "question": q, "reason": action["reason"], "repeated": True}
            return {"action": action, "decision": rec, "effect": None}
        if kind == "gate_open":
            self.state["status"] = "GATE_OPEN"
            rec = self._decide("gate_open", signal="SUFFICIENCY", diagnosis_code=action["code"],
                               measure=action["measure"], reason=action["reason"])
            return {"action": action, "decision": rec, "effect": None}
        if kind == "qa":
            return self._step_qa(action)
        if kind == "humangate":
            return self._step_humangate(action)
        return self._step_convoke(action, before)

    def _step_convoke(self, action: dict, before: dict) -> dict:
        capability = action["capability"]
        section = action["path"].split(".")[0]
        snap = self._snapshot(section)
        notified = None
        if action.get("message"):
            try:
                notified = notify(action["message"], self.run_dir, [capability],
                                  journal_dir=self.journal_dir, run_id=self.run_id)
            except EmitterError as exc:
                notified = {"error": str(exc)}
        spec = cap.spec(capability, self.registry)
        etape = spec["etape"]
        self.state["convocations"][etape] = self.state["convocations"].get(etape, 0) + 1
        attempt = self.state["convocations"][etape]
        project = self.blueprint.get("project", "")
        src_rel = f"GAMES/{project}"
        task = default_task_by_step(project, src_rel, profile="full").get(etape, "")
        if action.get("message"):
            m = action["message"]
            task += (f"\n\n## MESSAGE DU DIRECTOR — {m['type']} {m['id']}\n{m['subject']}\n{m['reason']}\n"
                     f"Cite l'identifiant {m['id']} dans ta restitution pour acquitter.")
        kwargs: dict = {}
        if self.timeout_s is not None:
            kwargs["timeout_s"] = self.timeout_s
        add_dir = None
        if action["kind"] == "build":
            bo.prepare_build(self.blueprint, self.run_dir, project)     # projections + gel + oracles.json
            add_dir = REPO_ROOT / src_rel
            self.state["build"]["attempts"] += 1
            self.state["build"]["last_model"] = action.get("model_override") or spec["model_policy"]["model"]
            if action.get("model_override"):
                kwargs["model_override"] = action["model_override"]
        res = cap.invoke_capability(capability, self.blueprint, self.run_dir, run_id=self.run_id,
                                    attempt=attempt, executor=self.executor, audit_path=self.audit_path,
                                    task=task, registry=self.registry, project=project, src_root_rel=src_rel,
                                    add_dir=add_dir, **kwargs)
        self.state["sequence"].append(etape)
        after = measure(self.blueprint)
        effect, why = effect_of(before, after, res.get("section_written"))
        progress, why_p = progress_of(before, after)
        key = action["signal"]
        sig = self.state["signals"].setdefault(key, _sig(self.state, key))
        sig["convocations"] += 1
        sig["last_effect"] = effect
        if effect == NO_EFFECT:
            sig["no_effect"] += 1
        elif effect == REGRESSED:
            sig["regressed"] += 1
            sig.setdefault("revert_to", snap)          # point de retour : AVANT la première régression
        else:
            sig["no_effect"], sig["regressed"] = 0, 0
            sig.pop("revert_to", None)
            sig["no_progress"] = sig["no_progress"] + 1 if progress == NONE else 0
        self.state["last_problems"] = list(res.get("problems") or [])
        if action["kind"] == "build" and res.get("ok"):
            self.state["status"] = "BUILT"
        rec = self._decide(
            action["kind"], signal=key, diagnosis_code=action["code"], effect=effect, progress=progress,
            measure={"before": before["coverage"], "after": after["coverage"],
                     "before_section_sha": _entry_sha(before, action["path"]),
                     "after_section_sha": _entry_sha(after, action["path"]),
                     "effect_reasons": why, "progress_reasons": why_p, "capability_ok": res.get("ok"),
                     "model_executed": res.get("model_executed"), "problems": res.get("problems"),
                     "requests": res.get("requests"), "consumption": self._consumption(action.get("message"), res),
                     "cost": res.get("cost")},
            reason=action["reason"], capability=capability, attempt=attempt,
            message_id=(action.get("message") or {}).get("id"), notified=notified,
            refs=[res.get("prompt_file"), res.get("artifact")],
        )
        return {"action": action, "decision": rec, "effect": effect, "progress": progress, "result": res}

    def _step_qa(self, action: dict) -> dict:
        project = self.blueprint.get("project", "")
        runner = self.qa_runner or (lambda: bo.run_qa_and_verdict(
            self.blueprint, self.run_dir, project, self.run_id,
            sequence_so_far=list(self.state["sequence"]), audit_path=self.audit_path))
        qa = runner()
        self.state["sequence"].extend(qa.get("executed") or [])
        verdict = qa.get("verdict") or {}
        summary = {"statuses": qa.get("statuses"), "software_verdict": verdict.get("software_verdict"),
                   "decision": verdict.get("decision"), "verify_run": qa.get("verify_run"),
                   "verdict_path": qa.get("verdict_path"), "state_path": qa.get("state_path"),
                   "built_version": self.blueprint["sections"]["wiremap"]["version"]}
        self.state["build"]["qa"] = summary
        self.state["last_problems"] = bo.qa_problems(qa)
        self.state["status"] = "QA_DONE"
        rec = self._decide("qa", signal=action["signal"], diagnosis_code=action["code"],
                           measure={**summary, "problems": self.state["last_problems"]},
                           reason=action["reason"], refs=[qa.get("verdict_path"), qa.get("state_path")])
        return {"action": action, "decision": rec, "effect": None, "result": qa}

    def _step_humangate(self, action: dict) -> dict:
        qa = self.state["build"].get("qa") or {}
        coverage = {w: _join_view(coverage_of(self.blueprint, which=w)) for w in ("design", "built")}
        dossier = bo.humangate_dossier(self.blueprint, self.run_dir, self.state,
                                       {**qa, "verdict": _read_json(qa.get("verdict_path"))},
                                       coverage, read_messages(self.journal_dir))
        self.state["status"] = "HUMANGATE_READY"
        rec = self._decide("humangate", signal=action["signal"], diagnosis_code=action["code"],
                           measure={"software_verdict": dossier.get("software_verdict"),
                                    "verify_run": dossier.get("verify_run"), "sequence": dossier.get("sequence"),
                                    "sequence_equals_profile": dossier.get("sequence_equals_profile"),
                                    "cost_usd_llm": dossier.get("cost_usd_llm")},
                           reason=action["reason"], refs=[str(self.run_dir / "HUMANGATE_DOSSIER.json")])
        return {"action": action, "decision": rec, "effect": None, "result": dossier}

    def run(self, max_steps: int = 6) -> list[dict]:
        out: list[dict] = []
        for _ in range(max_steps):
            r = self.step()
            out.append(r)
            k = r["action"]["kind"]
            if k in TERMINAL_KINDS or (k == "gate_open" and self.stop_at_gate):
                break
        return out


def _read_json(path) -> dict | None:
    if not path:
        return None
    p = Path(path)
    if not p.exists():
        return None
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


# ============================================================================ CLI

def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Director v0 — noyau déterministe sur le GAME_BLUEPRINT")
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("run", "next"):
        s = sub.add_parser(name)
        s.add_argument("--blueprint", required=True); s.add_argument("--run-id", required=True)
        s.add_argument("--out", default=None)
        if name == "run":
            s.add_argument("--max-steps", type=int, default=3); s.add_argument("--timeout", type=float, default=None)
            s.add_argument("--stop-at-gate", action="store_true", help="Lot 3 : s'arrêter à la porte de suffisance")
    a = p.parse_args(argv)
    b = bp.load(REPO_ROOT / a.blueprint)
    run_dir = REPO_ROOT / "EVIDENCE" / "runs" / a.run_id
    d = Director(b, run_dir, run_id=a.run_id, timeout_s=getattr(a, "timeout", None),
                 stop_at_gate=bool(getattr(a, "stop_at_gate", False)))
    if a.cmd == "next":
        d.apply_answers()
        print(json.dumps(next_action(b, d.state, measure(b), d.registry), ensure_ascii=False, indent=1, default=str))
        return 0
    results = d.run(max_steps=a.max_steps)
    bp.save(b, REPO_ROOT / (a.out or a.blueprint))
    for r in results:
        res = r.get("result")
        print(json.dumps({"kind": r["action"]["kind"], "capability": r["action"].get("capability"),
                          "code": r["action"].get("code"), "effect": r.get("effect"), "progress": r.get("progress"),
                          "decision": r["decision"].get("id"),
                          "cost": res.get("cost") if isinstance(res, dict) else None},
                         ensure_ascii=False, default=str))
    print(json.dumps({"status": d.state["status"], "steps": d.state["steps"], "sequence": d.state["sequence"],
                      "pending_question": d.state.get("pending_question")}, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
