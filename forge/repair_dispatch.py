"""Passage du runtime `repair_runtime` par la porte de dispatch, et sa trace Observer.

POURQUOI CE MODULE EXISTE — `run_repair_step()` appelait `repair_step.mjs` en direct.
Le réparateur tournait donc réellement, mais aucun reçu signé n'était émis : l'Observer,
qui reconstruit l'exécution depuis `EVIDENCE/bundles/dispatch_audit.jsonl` et les
transcripts, ne pouvait pas le voir. Un runtime déclaré dans `roles.yaml` et invisible à
l'exécution est exactement l'écart que cette lane cherche à supprimer.

CE QUE CE MODULE NE FAIT PAS :
  * il ne répare rien — `repair_step.mjs` et `repair_loop.mjs` sont inchangés ;
  * il ne crée aucun système d'événements — il écrit dans le MÊME fichier d'audit signé
    (`append_spawn_event`, HMAC identique, lecteur identique) et ajoute UNE source
    `repair_results.jsonl` que l'adaptateur `observer.adapters.forge_evidence` lit
    comme les autres ;
  * il ne juge rien : aucun score, aucune récompense, aucun classement.

CE QU'IL PARTAGE AVEC LA PORTE, ET CE QU'IL N'A PAS — dit franchement :
  PARTAGÉ   le fichier d'audit, le format `DispatchRecord`, la signature HMAC, le
            triplet de corrélation (etape, run_id, attempt), la résolution du runtime
            par le registry (`roles.yaml`, jamais un modèle en dur).
  ABSENT    aucun `contracts/<etape>.yaml`, donc aucune validation C1/C2 et aucun prompt
            de payload. La réparation n'est pas une étape de chaîne : c'est une passe
            interne à une étape. Son contrat vit dans `roles.yaml:runtime_contracts`
            et est appliqué par `repair_runtime_adapter.mjs`. Inventer un contrat
            d'étape pour lui donner l'air d'un agent aurait produit un prompt jamais
            envoyé — une trace fausse vaut moins qu'une trace absente.

BEST-EFFORT ABSOLU : aucune fonction ici ne lève. Une trace est une preuve, pas un gate ;
elle ne doit jamais faire tomber la réparation qu'elle observe.

claim_posture: NO_CLAIM_ALLOWED
"""
from __future__ import annotations

import hashlib
import json
import logging
import time
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

REPO_ROOT = Path(__file__).resolve().parents[1]
FORGE_ROLES = Path(__file__).resolve().parent / "contracts" / "roles.yaml"
CAPABILITIES = Path(__file__).resolve().parent / "capabilities.json"

#: Rôle runtime déclaré dans roles.yaml (accepté sous condition, HumanGate 2026-08-04).
RUNTIME_ID = "repair_runtime"
#: Capacité que ce runtime exécute (catalogue `capabilities.json`).
CAPABILITY_ID = "targeted_field_repair"
#: Chaîne d'exécution réelle — sert au Runtime Drift Oracle (`entrypoints`).
ENTRYPOINT = "forge/repair_step.mjs"

#: Source lue par `observer.adapters.forge_evidence`. Partagée entre projets, comme
#: `dispatch_audit.jsonl` : le filtrage se fait sur le préfixe du `run_id`.
RESULTS_PATH = REPO_ROOT / "EVIDENCE" / "bundles" / "repair_results.jsonl"

#: Champs interdits dans la trace (invariant de lane : jamais de note globale).
FORBIDDEN_KEYS = ("score", "reward", "ranking", "rank", "fitness", "weight")


def resolve_runtime(caps_path: Path | None = None) -> tuple[str, str]:
    """Résout (modèle, provider) du rôle `repair_runtime` via le registry.

    Jamais de modèle en dur : si `roles.yaml` ne déclare pas le rôle, on rend
    ``("", "")`` — « non résolu », ce qui est une information, pas une valeur devinée.
    """
    try:
        from control_plane.registry import get_model_for_role, get_provider_for_role
        path = caps_path or FORGE_ROLES
        return (get_model_for_role(RUNTIME_ID, path) or "",
                get_provider_for_role(RUNTIME_ID, path) or "")
    except Exception:
        logger.warning("repair_dispatch : runtime non résolu (advisory)", exc_info=True)
        return ("", "")


def _capability_facts() -> tuple[str, str]:
    """(root_problem_id, mutation_id) lus dans le catalogue. ("", "") si illisible."""
    try:
        cat = json.loads(CAPABILITIES.read_text(encoding="utf-8"))
        cap = next(c for c in cat["capabilities"] if c["id"] == CAPABILITY_ID)
        solves = cap.get("solves") or []
        return (solves[0] if solves else "", cap.get("source_mutation") or "")
    except Exception:
        return ("", "")


def repo_relative(path: Path | str) -> str:
    """Chemin relatif au dépôt, en séparateurs POSIX. Un chemin absolu dans une preuve
    la rend illisible sur une autre machine — et une preuve illisible n'est pas une
    preuve."""
    try:
        return Path(path).resolve().relative_to(REPO_ROOT).as_posix()
    except Exception:
        return str(path).replace("\\", "/")


def file_sha256(path: Path) -> str:
    """Empreinte d'un fichier, ou "" s'il est illisible. Jamais d'exception."""
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except Exception:
        return ""


def announce(etape: str, run_id: str, attempt: int = 0,
             audit_path: Path | None = None) -> bool:
    """Reçu signé `spawn_prepared` : la réparation VA tourner.

    Écrit AVANT l'exécution, comme `prepare_dispatch` — sinon une réparation qui plante
    ne laisserait aucune trace de son intention, et l'absence se lirait « rien n'a été
    tenté » au lieu de « une tentative a échoué ».
    """
    modele, provider = resolve_runtime()
    try:
        from forge.audit import EVENT_PREPARED, append_spawn_event
        return append_spawn_event(
            EVENT_PREPARED, etape=etape, run_id=run_id, attempt=attempt,
            capability_role=RUNTIME_ID, model=modele, provider=provider,
            allowed_tools=(), audit_path=audit_path,
        )
    except Exception:
        logger.warning("repair_dispatch : reçu 'prepared' non écrit (advisory)", exc_info=True)
        return False


#: Capacités qui s'exécutent À L'INTÉRIEUR de ce runtime (`capabilities.json` :
#: `executor_status: EMBEDDED_IN_RUNTIME`). Détection déterministe, aucun modèle.
_EMBARQUEES = (
    ("duplicate_content_detection", "SEMANTIC_SIGNAL", "SIGNAUX_AVANT", "SIGNAUX_APRES"),
    ("cross_field_copy_detection", "CROSS_FIELD", None, None),
)


def _capacites_embarquees(qualite: dict[str, Any]) -> list[dict[str, Any]]:
    """Trace d'exécution des capacités embarquées, depuis le bloc QUALITE.

    Liste VIDE si la phase qualité n'a pas tourné — jamais un « rien détecté » inventé :
    ne pas détecter et ne pas s'exécuter sont deux faits différents.
    """
    if not qualite:
        return []
    out = []
    for cap, prefixe, avant_k, apres_k in _EMBARQUEES:
        bloc: dict[str, Any] = {
            "capability_id": cap,
            "runtime_role": "deterministic",
            "verdict_before": qualite.get(f"{prefixe}_BEFORE"),
            "verdict_after": qualite.get(f"{prefixe}_AFTER"),
        }
        if avant_k:
            bloc["signals_before"] = qualite.get(avant_k)
            bloc["signals_after"] = qualite.get(apres_k)
        out.append(bloc)
    return out


def build_result(etape: str, run_id: str, mesure: dict[str, Any], *,
                 input_hash: str, output_hash: str, evidence_ref: str) -> dict[str, Any]:
    """Construit l'enregistrement `repair.result`. Pur, testable, sans effet de bord.

    `oracle_before`/`oracle_after` sont dérivés des COMPTEURS de problèmes rendus par
    l'oracle, jamais d'une affirmation du réparateur : 0 problème => OK.
    """
    root_problem_id, mutation_id = _capability_facts()
    avant, apres = mesure.get("PROBLEMS_BEFORE"), mesure.get("PROBLEMS_AFTER")
    verdict = lambda n: ("" if n is None else ("OK" if n == 0 else "FAIL"))  # noqa: E731
    return {
        # PREUVE D'EXÉCUTION des capacités de détection (alignement 2026-08-04). Elles
        # tournent à chaque réparation (`repair_step.mjs` phaseQualite) mais leur sortie
        # n'était nulle part dans la trace : une capacité qui s'exécute sans laisser
        # d'empreinte est indiscernable d'une capacité qui ne tourne pas. Bloc ADDITIF,
        # aucune métrique existante modifiée.
        "embedded_capabilities": _capacites_embarquees(mesure.get("QUALITE") or {}),
        "run_id": run_id,
        "etape": etape,
        "runtime_id": RUNTIME_ID,
        "root_problem_id": root_problem_id,
        "capability_id": CAPABILITY_ID,
        "mutation_id": mutation_id,
        "model_id": mesure.get("WORKER") or resolve_runtime()[0],
        "entrypoint": ENTRYPOINT,
        "input_hash": input_hash,
        "output_hash": output_hash,
        "allowed_fields": list(mesure.get("ALLOWED_FIELDS") or []),
        "written_fields": list(mesure.get("FIELDS_CHANGED") or []),
        "oracle": mesure.get("ORACLE") or "",
        "oracle_before": verdict(avant),
        "oracle_after": verdict(apres),
        "problems_before": avant,
        "problems_after": apres,
        "regression_count": len(mesure.get("REGRESSION") or []),
        "completion_tokens": mesure.get("TOKENS"),
        "status": mesure.get("STATUS") or "",
        "evidence_ref": evidence_ref,
        # L'oracle atteste la FERMETURE du défaut mesuré, pas la justesse de ce qui a
        # été écrit. Constant : aucune exécution ne peut le faire tomber.
        "quality_not_proven": True,
        "ts": time.time(),
    }


def record(etape: str, run_id: str, mesure: dict[str, Any], *,
           input_hash: str, output_hash: str, evidence_ref: str = "",
           attempt: int = 0, audit_path: Path | None = None,
           results_path: Path | None = None) -> dict[str, Any] | None:
    """Reçu signé `spawn_executed` + ligne `repair.result`. Rend l'enregistrement écrit.

    Rend ``None`` si rien n'a pu être écrit — l'appelant continue comme avant.
    """
    modele, provider = resolve_runtime()
    try:
        from forge.audit import EVENT_EXECUTED, append_spawn_event
        append_spawn_event(
            EVENT_EXECUTED, etape=etape, run_id=run_id, attempt=attempt,
            capability_role=RUNTIME_ID, model=modele, provider=provider,
            allowed_tools=(), audit_path=audit_path,
        )
    except Exception:
        logger.warning("repair_dispatch : reçu 'executed' non écrit (advisory)", exc_info=True)

    try:
        enreg = build_result(etape, run_id, mesure, input_hash=input_hash,
                             output_hash=output_hash, evidence_ref=evidence_ref)
        path = results_path or RESULTS_PATH
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(enreg, ensure_ascii=False, sort_keys=True) + "\n")
        return enreg
    except Exception:
        logger.warning("repair_dispatch : trace repair.result non écrite (advisory)", exc_info=True)
        return None
