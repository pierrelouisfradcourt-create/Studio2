"""Correlateur — assemble des evenements plats en une reconstruction de run.

Chaine canonique reconstituee :

    Run -> Dispatch -> Agent -> Contexte -> Tools -> Fichiers -> Tests
        -> Preuves -> Verdict

Trois sorties, volontairement separees :

  * `runs`     : ce qui s'est passe, ordonne, attribue, date.
  * `coverage` : pour chaque donnee attendue, OBSERVE / AUTO-DECLARE / NON
                 OBSERVABLE — avec la raison. Observer prefere dire "je ne sais
                 pas" plutot que de combler un blanc.
  * `drift`    : les ecarts entre ce qui est declare et ce qui est execute.
                 Observer les SIGNALE et ne les corrige jamais.
"""

from __future__ import annotations

import logging
import re
from collections import Counter, defaultdict
from typing import Any, Iterable, Optional

from observer.events import (
    LINK_DIRECT,
    LINK_FILE_SCOPE,
    PROOF_MECHANICAL,
    PROOF_SELF_DECLARED,
    PROOF_SIGNED,
    Event,
    iso,
)

LOG = logging.getLogger("observer.correlate")

SCHEMA_VERSION = "observer.run.v0"

_ATTEMPT_RE = re.compile(r"-run(\d+)-")

# En-dessous de ce seuil, un `ts` decode n'est pas un instant plausible du
# studio (epoch 0.0 = 1970-01-01, observe sur des recus signes de la Forge —
# voir studio_brain/journal/2026-08-07_postmortem_pacman_forge.md). Un ts
# declare sous ce seuil est traite comme ABSENT pour les fenetres temporelles :
# l'evenement reste compte, mais ne peut plus dater ni allonger un run. La
# regle du studio : une valeur declaree se compare au reel, elle ne s'invente
# jamais — donc on ne la corrige pas non plus, on l'ecarte et on la signale
# (cf. `detect_drift`, type `ts_declare_invalide`).
_MIN_PLAUSIBLE_TS = 1577836800.0  # 2020-01-01T00:00:00Z


def _is_plausible_ts(ts: Optional[float]) -> bool:
    return ts is not None and ts >= _MIN_PLAUSIBLE_TS

# Ordre de la chaine canonique : sert a ranger les evenements d'une etape.
CHAIN_ORDER: dict[str, int] = {
    "run.declared": 0,
    "run.charter": 0,
    "run.task_prompt": 1,
    "dispatch.prepared": 2,
    "dispatch.executed": 3,
    "dispatch.context_manifest": 4,
    "dispatch.reasoning": 4,
    "dispatch.tools": 4,
    "agent.session": 5,
    "agent.message": 6,
    "llm.usage": 6,
    "tool.call": 7,
    "tool.result": 7,
    "shell.exec": 7,
    "file.read": 8,
    "file.write": 8,
    "file.edit": 8,
    "artifact.self_declared": 9,
    "wiremap.line": 9,
    "test.result": 10,
    "mutation.result": 10,
    "solvability.result": 10,
    "oracle.result": 11,
    "capture.visual": 11,
    "guard.reference": 11,
    "telemetry.step": 12,
    "builder.attempt": 12,
    "failure.event": 13,
    "step.status": 13,
    "run.status": 14,
    "verdict.signed": 15,
    "git.commit": 16,
    "drift.detected": 17,
}

# Ce qu'un observateur doit pouvoir retrouver. Une entree absente n'est pas une
# erreur d'Observer : c'est un angle mort du systeme observe, et il doit etre
# nomme comme tel.
COVERAGE_SPEC: tuple[dict[str, Any], ...] = (
    {"key": "chronologie", "kinds": ("run.declared", "step.status", "run.status")},
    {"key": "agents", "kinds": ("dispatch.prepared", "dispatch.reasoning", "agent.session")},
    {"key": "modeles", "kinds": ("dispatch.prepared", "dispatch.context_manifest", "llm.usage")},
    {"key": "contrats", "kinds": ("dispatch.context_manifest",),
     "note_absent": "seule l'empreinte contract_sha256 est tracee ; le texte du contrat "
                    "actif n'est archive nulle part dans le run"},
    {"key": "contexte_injecte", "kinds": ("run.task_prompt", "dispatch.context_manifest"),
     "note_absent": "seules des empreintes SHA-256 du prompt final existent ; le texte "
                    "complet du contexte ambiant n'est pas conserve"},
    {"key": "tools_reellement_utilises", "kinds": ("tool.call", "shell.exec")},
    {"key": "fichiers_lus", "kinds": ("file.read",)},
    {"key": "fichiers_modifies", "kinds": ("file.write", "file.edit")},
    {"key": "tokens", "kinds": ("llm.usage", "telemetry.step", "builder.attempt")},
    {"key": "couts", "kinds": ("telemetry.step", "builder.attempt")},
    {"key": "tests_executes", "kinds": ("test.result",)},
    {"key": "mutation", "kinds": ("mutation.result",)},
    {"key": "solvabilite", "kinds": ("solvability.result",)},
    {"key": "failure_events", "kinds": ("failure.event",)},
    {"key": "captures", "kinds": ("capture.visual",)},
    {"key": "verdict_signe", "kinds": ("verdict.signed",)},
    {"key": "commits", "kinds": ("git.commit",)},
)


# --------------------------------------------------------------------------- #
# Classification des run_id
# --------------------------------------------------------------------------- #


def classify_run(run_id: str) -> str:
    """Un identifiant de run ne designe pas toujours une tentative de fabrication."""
    low = run_id.lower()
    if "dryrun" in low:
        return "dryrun"
    if _ATTEMPT_RE.search(low):
        return "attempt"
    return "pre_run"


def attempt_index(run_id: str) -> Optional[int]:
    match = _ATTEMPT_RE.search(run_id)
    return int(match.group(1)) if match else None


# --------------------------------------------------------------------------- #
# Assemblage
# --------------------------------------------------------------------------- #


def _window(events: Iterable[Event]) -> dict[str, Any]:
    stamps: list[float] = []
    invalid = 0
    for e in events:
        if e.ts is None:
            continue
        if not _is_plausible_ts(e.ts):
            invalid += 1
            continue
        stamps.append(e.ts)
    if not stamps:
        result: dict[str, Any] = {
            "start": None,
            "end": None,
            "duration_s": None,
            "dated_events": 0,
        }
        if invalid:
            result["ts_invalides"] = invalid
        return result
    start, end = min(stamps), max(stamps)
    result = {
        "start": iso(start),
        "end": iso(end),
        "duration_s": round(end - start, 3),
        "dated_events": len(stamps),
    }
    if invalid:
        # Des evenements portent un ts hors plage (ecarte du calcul ci-dessus,
        # jamais silencieusement) : `dated_events` ne compte que les valides,
        # `ts_invalides` rend le reste visible plutot que de le faire disparaitre.
        result["ts_invalides"] = invalid
    return result


def _actor_summary(events: Iterable[Event]) -> dict[str, Any]:
    models = Counter(e.actor.model for e in events if e.actor.model)
    roles = Counter(e.actor.capability_role for e in events if e.actor.capability_role)
    providers = Counter(e.actor.provider for e in events if e.actor.provider)
    return {
        "models": dict(models),
        "capability_roles": dict(roles),
        "providers": dict(providers),
    }


def _files_touched(events: Iterable[Event]) -> dict[str, Any]:
    """Fichiers reellement ecrits/edites/lus, d'apres les transcripts seuls.

    Le rattachement au run est de niveau fichier de session (`BY_FILE_SCOPE`) :
    on le conserve dans la sortie pour que personne ne prenne cette liste pour
    une trace signee.
    """
    written: Counter[str] = Counter()
    edited: Counter[str] = Counter()
    read: Counter[str] = Counter()
    links: set[str] = set()
    for ev in events:
        path = ev.payload.get("path")
        if not path:
            continue
        links.add(ev.link)
        if ev.kind == "file.write":
            written[path] += 1
        elif ev.kind == "file.edit":
            edited[path] += 1
        elif ev.kind == "file.read":
            read[path] += 1
    return {
        "written": dict(written.most_common()),
        "edited": dict(edited.most_common()),
        "read_count": len(read),
        "read_top": dict(read.most_common(25)),
        "link_levels": sorted(links),
    }


def _totals(events: Iterable[Event]) -> dict[str, Any]:
    cost = 0.0
    tokens_declared = 0
    out_tokens = 0
    in_tokens = 0
    cache_read = 0
    cache_creation = 0
    seen_cost = False
    # DEDUPLICATION OBLIGATOIRE (corrige 2026-08-02) : une meme reponse du modele
    # apparait sur PLUSIEURS lignes de transcript (une par bloc de contenu) avec
    # le MEME `usage` et le meme `request_id`. Sommer ligne a ligne surcompte les
    # tokens d'un facteur 3,3 a 14,2 (mesure sur breakout_v2). L'usage se compte
    # UNE FOIS PAR REPONSE. Sans identifiant, on retombe sur le comptage par
    # evenement — degradation nommee, jamais silencieuse.
    vus: set[str] = set()
    sans_identifiant = 0
    for ev in events:
        if ev.kind in ("telemetry.step", "builder.attempt"):
            for key in ("cost_usd", "cost_estimated"):
                value = ev.payload.get(key)
                if isinstance(value, (int, float)):
                    cost += float(value)
                    seen_cost = True
            for key in ("tokens", "tokens_estimated"):
                value = ev.payload.get(key)
                if isinstance(value, int):
                    tokens_declared += value
        elif ev.kind == "llm.usage":
            rid = ev.payload.get("request_id")
            if rid:
                if rid in vus:
                    continue
                vus.add(rid)
            else:
                sans_identifiant += 1
            in_tokens += int(ev.payload.get("input_tokens") or 0)
            out_tokens += int(ev.payload.get("output_tokens") or 0)
            cache_read += int(ev.payload.get("cache_read_input_tokens") or 0)
            cache_creation += int(ev.payload.get("cache_creation_input_tokens") or 0)
    return {
        "cost_usd_declared": round(cost, 4) if seen_cost else None,
        "tokens_declared_by_forge": tokens_declared or None,
        "tokens_measured_in_transcripts": {
            "input": in_tokens,
            "output": out_tokens,
            "cache_read": cache_read,
            "cache_creation": cache_creation,
            "reponses_distinctes": len(vus),
            "evenements_sans_request_id": sans_identifiant or None,
            "note": "une reponse compte une fois (dedup par request_id) — les "
                    "lignes de transcript repetent le meme usage",
        }
        if (in_tokens or out_tokens or cache_read or cache_creation)
        else None,
    }


def _step_node(etape: str, events: list[Event]) -> dict[str, Any]:
    events = sorted(events, key=lambda e: (CHAIN_ORDER.get(e.kind, 99), e.ts or 0.0))
    by_kind = Counter(e.kind for e in events)

    declared_tools: list[str] = []
    observed_tools: Counter[str] = Counter()
    loaded_status: Optional[str] = None
    for ev in events:
        if ev.kind == "dispatch.context_manifest":
            tools = ev.payload.get("tools_effective")
            if isinstance(tools, (list, tuple)):
                declared_tools = sorted({str(t) for t in tools})
        elif ev.kind == "dispatch.tools":
            loaded = ev.payload.get("loaded")
            if isinstance(loaded, dict):
                loaded_status = loaded.get("status")
        elif ev.kind == "tool.call":
            name = ev.payload.get("tool_name")
            if name:
                observed_tools[str(name)] += 1

    statuses = [
        ev.payload.get("status")
        for ev in events
        if ev.kind == "step.status" and ev.payload.get("status")
    ]

    return {
        "etape": etape,
        "window": _window(events),
        "event_counts": dict(by_kind.most_common()),
        "status_declared": statuses[-1] if statuses else None,
        "actor": _actor_summary(events),
        "attempt_fields_seen": sorted(
            {e.attempt_field for e in events if e.attempt_field}
        ),
        "attempts_seen": sorted({e.attempt for e in events if e.attempt is not None}),
        "tools": {
            "declared_by_forge": declared_tools,
            "declared_measurement_status": loaded_status,
            "observed_in_transcripts": dict(observed_tools.most_common()),
        },
        "files": _files_touched(events),
        "totals": _totals(events),
        "proof_mix": dict(Counter(e.proof for e in events).most_common()),
        "event_ids": [e.event_id for e in events],
    }


def build_runs(events: list[Event]) -> tuple[list[dict[str, Any]], list[Event]]:
    """Regroupe les evenements par run puis par etape. Retourne (runs, orphelins)."""
    by_run: dict[str, list[Event]] = defaultdict(list)
    orphans: list[Event] = []
    for ev in events:
        if ev.run_id:
            by_run[ev.run_id].append(ev)
        else:
            orphans.append(ev)

    runs: list[dict[str, Any]] = []
    for run_id, run_events in by_run.items():
        by_step: dict[str, list[Event]] = defaultdict(list)
        run_level: list[Event] = []
        for ev in run_events:
            if ev.etape:
                by_step[ev.etape].append(ev)
            else:
                run_level.append(ev)

        verdicts = [e for e in run_events if e.kind == "verdict.signed"]
        statuses = [e for e in run_events if e.kind == "run.status"]

        runs.append(
            {
                "run_id": run_id,
                "role": classify_run(run_id),
                "attempt_index": attempt_index(run_id),
                "window": _window(run_events),
                "event_count": len(run_events),
                "run_status": next(
                    (
                        value
                        for ev in reversed(statuses)
                        for value in (ev.payload.get("status"), ev.payload.get("run_status"))
                        if value
                    ),
                    None,
                ),
                "decision": verdicts[-1].payload.get("decision") if verdicts else None,
                "verdict": verdicts[-1].payload if verdicts else None,
                "actor": _actor_summary(run_events),
                "totals": _totals(run_events),
                "files": _files_touched(run_events),
                "steps": [
                    _step_node(etape, evs)
                    for etape, evs in sorted(
                        by_step.items(),
                        key=lambda kv: min((e.ts or 0.0) for e in kv[1]),
                    )
                ],
                "run_level_event_counts": dict(
                    Counter(e.kind for e in run_level).most_common()
                ),
                "proof_mix": dict(Counter(e.proof for e in run_events).most_common()),
            }
        )

    runs.sort(key=lambda r: (r["window"]["start"] or "", r["run_id"]))
    return runs, orphans


# --------------------------------------------------------------------------- #
# Couverture
# --------------------------------------------------------------------------- #


def build_coverage(events: list[Event]) -> dict[str, Any]:
    """Pour chaque donnee attendue : observee, seulement auto-declaree, ou absente."""
    by_kind: dict[str, list[Event]] = defaultdict(list)
    for ev in events:
        by_kind[ev.kind].append(ev)

    coverage: dict[str, Any] = {}
    for spec in COVERAGE_SPEC:
        matched = [e for kind in spec["kinds"] for e in by_kind.get(kind, [])]
        if not matched:
            coverage[spec["key"]] = {
                "status": "NOT_OBSERVABLE",
                "count": 0,
                "kinds": list(spec["kinds"]),
                "why": spec.get(
                    "note_absent",
                    "aucune trace de ce type n'existe dans les sources autorisees",
                ),
            }
            continue
        proofs = Counter(e.proof for e in matched)
        hard = proofs.get(PROOF_SIGNED, 0) + proofs.get(PROOF_MECHANICAL, 0)
        status = "OBSERVED" if hard else "SELF_DECLARED_ONLY"
        sources = sorted({e.source.path for e in matched})
        coverage[spec["key"]] = {
            "status": status,
            "count": len(matched),
            "proof_mix": dict(proofs),
            "link_mix": dict(Counter(e.link for e in matched)),
            "sources": sources[:12],
            "sources_truncated": len(sources) > 12,
        }
        if spec.get("note_absent") and status != "OBSERVED":
            coverage[spec["key"]]["why"] = spec["note_absent"]
    return coverage


# --------------------------------------------------------------------------- #
# Drift — signale, jamais corrige
# --------------------------------------------------------------------------- #


def detect_drift(events: list[Event], runs: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Ecarts entre le declare et l'execute. Observer n'est pas un reparateur."""
    drift: list[dict[str, Any]] = []

    # 1. Dispatch prepare sans execution correspondante.
    prepared: dict[tuple, Event] = {}
    executed: set[tuple] = set()
    for ev in events:
        key = (ev.run_id, ev.etape, ev.attempt)
        if ev.kind == "dispatch.prepared":
            prepared[key] = ev
        elif ev.kind == "dispatch.executed":
            executed.add(key)
    for key, ev in prepared.items():
        if key not in executed:
            drift.append(
                {
                    "type": "dispatch_prepared_never_executed",
                    "severity": "info",
                    "run_id": key[0],
                    "etape": key[1],
                    "attempt": key[2],
                    "detail": "un dispatch a ete prepare et signe, aucun evenement "
                              "d'execution ne lui correspond",
                    "source": ev.source.to_dict(),
                }
            )

    # 2. Outils : ce que la Forge declare vs ce que les transcripts montrent.
    for run in runs:
        for step in run["steps"]:
            declared = set(step["tools"]["declared_by_forge"])
            observed = set(step["tools"]["observed_in_transcripts"])
            if observed and declared and not observed <= declared:
                drift.append(
                    {
                        "type": "tools_used_beyond_declared",
                        "severity": "high",
                        "run_id": run["run_id"],
                        "etape": step["etape"],
                        "detail": "des outils observes dans le transcript ne figurent "
                                  "pas dans tools_effective declare par la Forge",
                        "declared": sorted(declared),
                        "observed_only": sorted(observed - declared),
                    }
                )
            if observed and not declared:
                drift.append(
                    {
                        "type": "tools_used_without_declaration",
                        "severity": "high",
                        "run_id": run["run_id"],
                        "etape": step["etape"],
                        "detail": "l'agent a utilise des outils alors qu'aucune liste "
                                  "d'outils n'est declaree dans la trace de dispatch",
                        "observed": sorted(observed),
                    }
                )
            if step["tools"]["declared_measurement_status"] == "NOT_MEASURED" and observed:
                drift.append(
                    {
                        "type": "tool_observability_not_measured",
                        "severity": "medium",
                        "run_id": run["run_id"],
                        "etape": step["etape"],
                        "detail": "tool_observability declare loaded.status=NOT_MEASURED "
                                  "alors que des appels d'outils sont observables dans "
                                  "les transcripts",
                        "observed_count": sum(
                            step["tools"]["observed_in_transcripts"].values()
                        ),
                    }
                )

    # 3. Modele declare vs modele execute.
    for ev in events:
        declared = ev.payload.get("model")
        executed_model = ev.payload.get("model_executed")
        if declared and executed_model and declared != executed_model:
            drift.append(
                {
                    "type": "model_declared_differs_from_executed",
                    "severity": "high",
                    "run_id": ev.run_id,
                    "etape": ev.etape,
                    "declared": declared,
                    "executed": executed_model,
                    "source": ev.source.to_dict(),
                }
            )

    # 3-bis. Modele DECLARE par la Forge vs modele MESURE dans les transcripts.
    #
    # C'est la comparaison inter-sources la plus importante d'Observer. Le champ
    # `model` de l'audit de dispatch est signe HMAC : la signature prouve que la
    # DECLARATION n'a pas ete alteree, elle ne prouve pas que la declaration est
    # VRAIE. Seul le transcript porte le modele qui a reellement repondu.
    declared_models: dict[tuple, set[str]] = defaultdict(set)
    observed_models: dict[tuple, Counter] = defaultdict(Counter)
    for ev in events:
        key = (ev.run_id, ev.etape)
        if ev.kind in ("dispatch.prepared", "dispatch.executed", "dispatch.context_manifest"):
            for candidate in (ev.payload.get("model"), ev.actor.model):
                if candidate and candidate not in ("", "non-llm"):
                    declared_models[key].add(str(candidate))
        elif ev.kind == "llm.usage":
            model = ev.payload.get("model") or ev.actor.model
            if model and model != "<synthetic>":
                observed_models[key][str(model)] += 1

    for key, declared in declared_models.items():
        observed = observed_models.get(key)
        if not declared or not observed:
            continue
        if declared & set(observed):
            continue
        drift.append(
            {
                "type": "model_audit_differs_from_transcript",
                "severity": "high",
                "run_id": key[0],
                "etape": key[1],
                "detail": "le modele declare dans l'audit signe de la Forge n'apparait "
                          "dans aucun message du transcript : la signature protege la "
                          "declaration, elle ne mesure pas l'execution",
                "declared_by_forge": sorted(declared),
                "observed_in_transcripts": dict(observed),
            }
        )

    # 4. Garde de reference en derive.
    for ev in events:
        if ev.kind == "guard.reference" and ev.payload.get("status") == "DRIFT":
            drift.append(
                {
                    "type": "reference_guard_drift",
                    "severity": "medium",
                    "run_id": ev.run_id,
                    "phase": ev.payload.get("phase"),
                    "detail": "la garde de reference a constate une modification de "
                              "fichiers proteges pendant le run",
                    "diffs": ev.payload.get("diffs"),
                    "source": ev.source.to_dict(),
                }
            )

    # 4-bis. Comptabilite de tokens : ce que la Forge declare vs ce que les
    # transcripts mesurent. Un ecart d'un ordre de grandeur ne se corrige pas
    # ici — il se signale, parce qu'il fausse toute decision de cout prise a
    # partir de forge_telemetry.
    for run in runs:
        declared = run["totals"].get("tokens_declared_by_forge")
        measured = run["totals"].get("tokens_measured_in_transcripts")
        if not declared or not measured:
            continue
        billable = measured["input"] + measured["output"] + measured["cache_creation"]
        if billable > declared * 1.5:
            drift.append(
                {
                    "type": "token_accounting_below_measured",
                    "severity": "high",
                    "run_id": run["run_id"],
                    "detail": "la telemetrie de la Forge declare nettement moins de "
                              "tokens que les transcripts n'en mesurent — la lecture "
                              "de cache n'est meme pas comptee",
                    "declared_by_forge": declared,
                    "measured_billable": billable,
                    "measured_cache_read": measured["cache_read"],
                    "ratio": round(billable / declared, 2),
                }
            )

    # 5. Fichiers ecrits hors du perimetre attendu.
    #
    # Deux cas tres differents, qu'il serait trompeur de confondre :
    #   * le scratchpad de session (hors depot, jetable) — l'agent a fabrique un
    #     script de verification. C'est un fait interessant (il a VRAIMENT
    #     verifie au lieu de l'affirmer), pas une violation ;
    #   * une ecriture DANS le depot hors de games/ et lab/ — la, un agent
    #     d'etape a touche autre chose que son livrable.
    for run in runs:
        for path in run["files"]["written"]:
            normalized = path.replace("\\", "/")
            if "/games/" in normalized or "/lab/" in normalized:
                continue
            if "/scratchpad/" in normalized or "/Temp/claude/" in normalized:
                drift.append(
                    {
                        "type": "file_written_in_session_scratchpad",
                        "severity": "info",
                        "run_id": run["run_id"],
                        "path": path,
                        "detail": "script jetable ecrit hors depot dans le scratchpad de "
                                  "session — trace qu'une verification a reellement ete "
                                  "executee, pas seulement affirmee",
                    }
                )
            else:
                drift.append(
                    {
                        "type": "file_written_outside_game_and_lab",
                        "severity": "high",
                        "run_id": run["run_id"],
                        "path": path,
                        "detail": "ecriture dans le depot hors de games/ et lab/ pendant "
                                  "une fenetre de session rattachee a ce run",
                    }
                )

    # 6. Horodatage declare invalide (epoch <= 0 ou avant 2020). Regroupe par
    # (run_id, kind, fichier source) pour ne pas noyer le rapport quand la
    # meme source signe systematiquement ts=0.0 (cas mesure : oracle.result et
    # verdict.signed d'un run pacman entier). L'evenement lui-meme reste compte
    # ailleurs — seule la fenetre temporelle l'ignore (cf. `_window`).
    invalid_groups: dict[tuple, list[Event]] = defaultdict(list)
    for ev in events:
        if ev.ts is not None and not _is_plausible_ts(ev.ts):
            invalid_groups[(ev.run_id, ev.kind, ev.source.path)].append(ev)
    for (run_id, kind, _path), evs in invalid_groups.items():
        raw_examples = sorted({e.ts_raw for e in evs if e.ts_raw is not None})[:5]
        drift.append(
            {
                "type": "ts_declare_invalide",
                "severity": "medium",
                "run_id": run_id,
                "kind": kind,
                "detail": "horodatage declare hors plage plausible (<=0 ou avant "
                          "2020-01-01) — traite comme absent pour le calcul des "
                          "fenetres de run ; l'evenement reste compte ailleurs, "
                          "seule sa date est ecartee",
                "count": len(evs),
                "ts_raw_examples": raw_examples,
                "source": evs[0].source.to_dict(),
            }
        )

    return drift


# --------------------------------------------------------------------------- #
# Reconstruction complete
# --------------------------------------------------------------------------- #


def prompt_drift(prompts: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Ecarts sur la chaine de prompt.

    Un `MISMATCH` est l'ecart le plus grave que ce systeme puisse produire :
    l'agent n'aurait pas recu le texte que la Forge a signe avoir envoye. Aucun
    n'est observe sur cette campagne — la regle existe pour le jour ou il s'en
    produira un, pas pour meubler.
    """
    drift: list[dict[str, Any]] = []
    for entry in prompts:
        verification = entry.get("verification")
        if verification == "MISMATCH":
            drift.append({
                "type": "prompt_recu_differe_du_prompt_signe",
                "severity": "high",
                "run_id": entry.get("run_id"),
                "etape": entry.get("etape"),
                "detail": "le SHA-256 du prompt present dans le transcript ne "
                          "reproduit pas l'empreinte signee par la Forge : le "
                          "texte recu par l'agent n'est pas celui declare",
                "chars_transcript": entry.get("chars_normalized"),
                "chars_declares": (entry.get("declared") or {}).get("final_prompt_chars"),
                "source": entry.get("source"),
            })
        elif verification == "NO_DECLARATION":
            drift.append({
                "type": "prompt_sans_empreinte_declaree",
                "severity": "medium",
                "run_id": entry.get("run_id"),
                "etape": entry.get("etape"),
                "detail": "le prompt recu est lisible mais la Forge n'a signe "
                          "aucune empreinte pour cette activation : sa conformite "
                          "n'est ni prouvable ni refutable",
                "source": entry.get("source"),
            })
    return drift


def reconstruct(events: list[Event], project: str, sources_read: list[str]) -> dict[str, Any]:
    runs, orphans = build_runs(events)
    coverage = build_coverage(events)
    drift = detect_drift(events, runs)

    return {
        "schema": SCHEMA_VERSION,
        "project": project,
        "event_count": len(events),
        "counts": {
            "by_kind": dict(Counter(e.kind for e in events).most_common()),
            "by_proof": dict(Counter(e.proof for e in events).most_common()),
            "by_link": dict(Counter(e.link for e in events).most_common()),
            "by_ts_format": dict(Counter(e.ts_format for e in events).most_common()),
            "undated_events": sum(1 for e in events if e.ts is None),
        },
        "runs": runs,
        "unlinked": {
            "count": len(orphans),
            "by_kind": dict(Counter(e.kind for e in orphans).most_common()),
        },
        "coverage": coverage,
        "drift": drift,
        "sources_read": sorted(set(sources_read)),
    }
