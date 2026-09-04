"""BUILD ORCHESTRATOR v0 (Lot 4, plan V2 2026-09-03, GO Pierre) — C13 · L5 · L6.

Trois gestes, aucun nouveau mécanisme de preuve :
  * `prepare_build` — projette les sections du Blueprint dans le run_dir (ce que les oracles legacy
    lisent), FIGE le jeu de règles (`wiremap_frozen.json`, jamais écrasé — même règle que le driver
    après s5) et écrit la config d'oracle locale au run (`oracles.json` du run, pas le registre
    global : R3, un run ne modifie pas une surface).
  * `run_qa_and_verdict` — réutilise `ForgeDriver` comme MOTEUR d'oracles et de verdict : ses
    exécuteurs déterministes (`_run_deterministic` pour s10a/s10b/s10c/s12), ses reçus signés, son
    `_run_verdict` (HMAC + `verify_run`). Le Director décide QUAND ; le driver mesure COMMENT, tel
    qu'il l'a toujours fait. Aucun oracle n'est réécrit.
  * `humangate_dossier` — L8 : le jeu, ce qu'il fait (verdict, reçus), la couverture design et
    construite, la suite RÉELLE des convocations (comparée aux profils ORDER), les objections
    conservées, les problèmes restants, le coût, et ce qui n'est PAS prouvé.

`software_verdict` vient UNIQUEMENT des reçus d'oracle (ADR-002) ; ce module ne le calcule ni ne
le corrige. NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import json
import time
from pathlib import Path

import yaml

from forge import blueprint as bp
from forge.dispatch import PROFILES
from forge.driver import ForgeDriver
from forge.static_oracles import frozen_features_from_wiremap

REPO_ROOT = Path(__file__).resolve().parents[1]
QA_STEPS = ("s10a-oracle-code", "s10b-oracle-archi", "s10c-oracle-wiremap")
VERDICT_STEP = "s12-verdict"


def _dump(path: Path, data, *, yaml_out: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if yaml_out:
        path.write_text(yaml.safe_dump(data, allow_unicode=True, sort_keys=False), encoding="utf-8")
    else:
        path.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")


def _entry(blueprint: dict, section: str, entry: str | None = None):
    content = blueprint["sections"][section].get("content")
    if entry is None:
        return content
    sub = (content or {}).get(entry) if isinstance(content, dict) else None
    return sub.get("content") if isinstance(sub, dict) else None


def prepare_build(blueprint: dict, run_dir: Path, project: str) -> dict:
    """Projections + gel des règles + config d'oracle locale. Idempotent, jamais d'écrasement du gel."""
    run_dir = Path(run_dir)
    run_dir.mkdir(parents=True, exist_ok=True)
    written: list[str] = []
    for section, entry, filename, as_yaml in (
        ("gameplay", None, "charter.yaml", True),
        ("feature_map", None, "featuremap.json", False),
        ("architecture_contract", None, "blueprint.json", False),
        ("wiremap", "design", "wiremap.json", False),
    ):
        data = _entry(blueprint, section, entry)
        if data is None:
            continue
        _dump(run_dir / filename, data, yaml_out=as_yaml)
        written.append(filename)
    frozen_path = run_dir / "wiremap_frozen.json"
    design = _entry(blueprint, "wiremap", "design")
    frozen = {"status": "KEPT" if frozen_path.exists() else "ABSENT"}
    if not frozen_path.exists() and design is not None:
        _dump(frozen_path, {"features": frozen_features_from_wiremap(design)})
        frozen = {"status": "WRITTEN", "features": len(frozen_features_from_wiremap(design))}
    oracle_cfg = run_dir / "oracles.json"
    if not oracle_cfg.exists():
        _dump(oracle_cfg, {project: {"cwd": f"GAMES/{project}", "command": ["node", "run-oracle.mjs"]}})
    (REPO_ROOT / "GAMES" / project).mkdir(parents=True, exist_ok=True)
    return {"projections": written, "frozen": frozen, "oracle_config": str(oracle_cfg),
            "src_root": f"GAMES/{project}"}


def _fresh_qa_state(driver: ForgeDriver, run_id: str, project: str, sequence_so_far: list[str]) -> dict:
    steps = {e: {"status": "PENDING", "attempts": 0} for e in driver.order}
    for e in driver.order:
        if e in QA_STEPS or e == VERDICT_STEP:
            continue
        # étapes de ORDER non conduites par le driver : le Director a convoqué des CAPACITÉS ;
        # on le dit dans l'état, on ne fabrique jamais un statut OK
        steps[e] = {"status": "SKIPPED", "attempts": 0,
                    "detail": {"reason": "chemin Director (V2) : étape non conduite par ORDER ; "
                                         f"convocations réelles : {sequence_so_far}"}}
    return {"run_id": run_id, "project": project, "profile": driver.profile, "run_status": "RUNNING",
            "is_game": True, "created_ts": time.time(), "steps": steps, "escalations": 0,
            "humangate_notes": ["verdict rendu sur le chemin Director V2 : s0..s6 non conduits par ORDER"]}


def run_qa_and_verdict(blueprint: dict, run_dir: Path, project: str, run_id: str, *,
                       sequence_so_far: list[str], audit_path: Path | None = None,
                       steps: tuple[str, ...] = QA_STEPS + (VERDICT_STEP,)) -> dict:
    """Oracles déterministes + verdict signé, par les exécuteurs du driver. Rend statuts et chemins."""
    run_dir = Path(run_dir)
    prep = prepare_build(blueprint, run_dir, project)
    driver = ForgeDriver(
        project, run_id, run_dir=run_dir, profile="full", src_root=REPO_ROOT / prep["src_root"],
        is_game=True, oracle_config=run_dir / "oracles.json", audit_path=audit_path,
        journal_path=run_dir / "error_journal.jsonl", lessons_path=run_dir / "lessons.jsonl",
        failure_events_path=run_dir / "failure_events.jsonl",
    )
    state_path = run_dir / "state.json"
    state = json.loads(state_path.read_text(encoding="utf-8")) if state_path.exists() else None
    if not isinstance(state, dict) or state.get("run_id") != run_id:
        state = _fresh_qa_state(driver, run_id, project, sequence_so_far)
    for e in steps:
        state["steps"][e] = {"status": "PENDING", "attempts": state["steps"].get(e, {}).get("attempts", 0)}
    driver._save(state)
    executed: list[str] = []
    for e in steps:
        driver._run_deterministic(state, e)
        executed.append(e)
        if e == VERDICT_STEP:
            break
    state["run_status"] = "DONE" if state["steps"].get(VERDICT_STEP, {}).get("status") == "OK" else "HALTED"
    driver._save(state)
    statuses = {e: state["steps"][e].get("status") for e in steps}
    details = {e: state["steps"][e].get("detail") for e in steps}
    verdict_path = run_dir / "verdict.json"
    verdict = json.loads(verdict_path.read_text(encoding="utf-8")) if verdict_path.exists() else None
    return {"prepare": prep, "executed": executed, "statuses": statuses, "details": details,
            "verdict": verdict, "verdict_path": str(verdict_path) if verdict else None,
            "verify_run": (details.get(VERDICT_STEP) or {}).get("verify_run"),
            "state_path": str(state_path)}


def _failing_checks(detail, prefix: str = "") -> list[tuple[str, str]]:
    """(chemin, raisons) de chaque sous-contrôle rouge d'un reçu d'oracle : `passed: False` avec
    `raisons`/`reason`, ou `status: FAIL|BLOCKED`. Parcours récursif borné, jamais d'exception."""
    out: list[tuple[str, str]] = []
    if not isinstance(detail, dict):
        return out
    for k, v in detail.items():
        if not isinstance(v, dict):
            continue
        path = f"{prefix}.{k}" if prefix else k
        red = v.get("passed") is False or v.get("status") in ("FAIL", "BLOCKED")
        if red and v.get("status") != "SKIPPED":
            raisons = v.get("raisons") or v.get("reason") or v.get("problems") or ""
            if not isinstance(raisons, str):
                raisons = " ; ".join(str(r) for r in raisons) if isinstance(raisons, (list, tuple)) else json.dumps(raisons, ensure_ascii=False)
            out.append((path, raisons))
        out.extend(_failing_checks(v, path))
    return out


def qa_problems(qa: dict) -> list[dict]:
    """Problèmes K7 tirés des reçus d'oracle (producteur = l'oracle et son sous-contrôle), pour la
    réaction du Director. Un oracle rouge sans raison nommée produit quand même UN problème."""
    problems: list[dict] = []
    for e in QA_STEPS:
        st = (qa.get("statuses") or {}).get(e)
        if st not in ("FAIL", "BLOCKED"):
            continue
        det = (qa.get("details") or {}).get(e) or {}
        checks = _failing_checks(det)
        if not checks:
            top = det.get("raisons") or det.get("reason") or ""
            checks = [("", top if isinstance(top, str) else json.dumps(top, ensure_ascii=False))]
        for path, raisons in checks:
            problems.append({"code": f"ORACLE_{st}", "producer": f"{e}.{path}" if path else e,
                             "path": "GAMES/<project>", "message": (raisons or "(sans raison nommée)")[:600],
                             "suggested_action": "reconvoke_builder"})
    return problems


def qa_problems_from_state(state_path) -> list[dict]:
    """Recalcule les problèmes depuis le state.json du run QA (les reçus signés y sont)."""
    try:
        state = json.loads(Path(state_path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, TypeError):
        return []
    steps = state.get("steps") or {}
    return qa_problems({"statuses": {e: (steps.get(e) or {}).get("status") for e in QA_STEPS},
                        "details": {e: (steps.get(e) or {}).get("detail") for e in QA_STEPS}})


# Pas exécutés par genre de décision. Une décision est une unité du Director ; un pas est une
# convocation/oracle réellement lancé(e). Les deux compteurs ne coïncident jamais : `qa` lance
# les 3 oracles + le verdict, et les décisions de politique (gate, halt, réponse K8, dossier)
# n'exécutent rien. Le dossier écrit les deux et vérifie qu'ils se recoupent.
STEPS_BY_DECISION_KIND = {"convoke": 1, "reconvoke": 1, "build": 1, "qa": len(QA_STEPS) + 1}


def decision_step_counts(decisions: list[dict], sequence: list[str]) -> dict:
    """Compteurs dérivés (jamais déclarés) : décisions vs pas exécutés, et leur cohérence."""
    expected = sum(STEPS_BY_DECISION_KIND.get(d.get("kind"), 0) for d in decisions)
    without = sorted({d.get("kind") for d in decisions if STEPS_BY_DECISION_KIND.get(d.get("kind"), 0) == 0})
    return {"director_decisions": len(decisions), "executed_steps": len(sequence), "expected_steps": expected,
            "consistent": expected == len(sequence), "decisions_without_step": [k for k in without if k],
            "includes_humangate_decision": any(d.get("kind") == "humangate" for d in decisions),
            "steps_per_qa_decision": len(QA_STEPS) + 1}


def humangate_dossier(blueprint: dict, run_dir: Path, director_state: dict, qa: dict | None,
                      coverage: dict, journal_messages: list[dict]) -> dict:
    """L8 — dossier pour Pierre. Faits séparés des jugements ; ce qui n'est pas prouvé est écrit."""
    run_dir = Path(run_dir)
    sequence = list(director_state.get("sequence") or [])
    profiles_equal = [name for name, steps in PROFILES.items() if tuple(steps) == tuple(sequence)]
    decisions = []
    dj = run_dir / "decisions.jsonl"
    if dj.exists():
        decisions = [json.loads(l) for l in dj.read_text(encoding="utf-8").splitlines() if l.strip()]
    cost = sum(float(((d.get("measure") or {}).get("cost") or {}).get("cost_usd") or 0) for d in decisions)
    counts = decision_step_counts(decisions, sequence)
    verdict = (qa or {}).get("verdict") or {}
    # Lot 5 (réserve 3) : seules les objections de CE run sont listées ; les autres sont comptées
    run_id = director_state.get("run_id")
    mine = [m for m in journal_messages if m.get("run_id") == run_id]
    autres = len(journal_messages) - len(mine)
    run_dir.mkdir(parents=True, exist_ok=True)
    dossier = {
        "project": blueprint.get("project"), "run_id": director_state.get("run_id"),
        "software_verdict": verdict.get("software_verdict"), "decision": verdict.get("decision"),
        "evidence_verdict": verdict.get("evidence_verdict"), "claim_verdict": "NO_CLAIM_ALLOWED",
        "verify_run": (qa or {}).get("verify_run"), "verdict_path": (qa or {}).get("verdict_path"),
        "oracles": (qa or {}).get("statuses"), "redteam_ran": verdict.get("redteam_ran"),
        "humangate_flags": verdict.get("humangate_flags"),
        "coverage": coverage,
        "sequence": sequence, "sequence_equals_profile": profiles_equal or None,
        "counts": counts,
        "decisions": [{k: d.get(k) for k in ("id", "kind", "capability", "diagnosis_code", "effect", "progress")}
                      for d in decisions],
        "objections_conservees": [{k: m.get(k) for k in ("id", "type", "from", "to", "subject", "run_id")} for m in mine],
        "objections_autres_runs": autres,
        "problems_remaining": (director_state.get("last_problems") or []),
        "cost_usd_llm": round(cost, 4),
        "not_proven": ["valeur du jeu (Pierre joue)", "variance de l'oracle de solvabilité (défaut connu)",
                       "UX · design_metrics · game_flow (sections DOCUMENTED_ONLY)",
                       "revue indépendante (red team non convoquée en v0)"],
        "no_global_ready_verdict": True,
    }
    (run_dir / "HUMANGATE_DOSSIER.json").write_text(json.dumps(dossier, ensure_ascii=False, indent=1), encoding="utf-8")
    objections_md = [f"- {m['id']} · {m['type']} {m['from']} → {m['to']} : {m['subject']}"
                     for m in dossier["objections_conservees"]] or ["(aucune)"]
    md = [f"# HumanGate — {dossier['project']} · {dossier['run_id']}", "",
          f"software_verdict: {dossier['software_verdict']} · evidence_verdict: {dossier['evidence_verdict']} · "
          f"claim_verdict: NO_CLAIM_ALLOWED · verify_run: {dossier['verify_run']}", "",
          "## Oracles", json.dumps(dossier["oracles"], ensure_ascii=False), "",
          "## Couverture (feature_map ↔ wiremap)", json.dumps(coverage, ensure_ascii=False), "",
          "## Suite réelle des convocations", " → ".join(sequence) or "(aucune)",
          f"égale à un profil ORDER : {profiles_equal or 'non'}", "",
          "## Compteurs (deux unités distinctes)",
          f"- décisions du Director enregistrées au moment du dossier : {counts['director_decisions']}"
          + ("" if counts["includes_humangate_decision"] else
             " (la décision `humangate` qui produit ce dossier est enregistrée après lui)"),
          f"- pas exécutés (entrées de la suite) : {counts['executed_steps']}",
          f"- pas attendus d'après les décisions : {counts['expected_steps']} → "
          f"{'cohérent' if counts['consistent'] else 'INCOHÉRENT'}",
          f"- décisions sans pas exécuté : {counts['decisions_without_step']}",
          f"- pas par décision `qa` : {counts['steps_per_qa_decision']} ({', '.join(QA_STEPS + (VERDICT_STEP,))})", "",
          "## Décisions du Director",
          *[f"- {d['id']} · {d['kind']} · {d.get('capability') or ''} · {d.get('diagnosis_code') or ''} · effet {d.get('effect') or ''} · progrès {d.get('progress') or ''}"
            for d in dossier["decisions"]], "",
          "## Objections conservées (run seul)", *objections_md,
          f"- {autres} objection(s) d'autres runs ou sans run_id, non listées", "",
          f"## Coût LLM : {dossier['cost_usd_llm']} $", "",
          "## Non prouvé", *[f"- {x}" for x in dossier["not_proven"]], "", "no_global_ready_verdict: true"]
    (run_dir / "HUMANGATE_DOSSIER.md").write_text("\n".join(md) + "\n", encoding="utf-8")
    return dossier
