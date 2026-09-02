"""forge_gate — the FORCER brick.

Ties oracle resolution + execution + signed verdict into one gate. Green oracle
=> signed OK verdict. Red, missing-config, or unrunnable oracle => FAIL / BLOCKED.
The caller (the /forge skill) MUST NOT proceed past a non-OK gate: that runtime
enforcement is what superpowers does not provide. This function never raises for
an operational oracle failure — it always returns a signed verdict.
"""
from __future__ import annotations

import logging
from dataclasses import dataclass
from pathlib import Path

from forge.oracle import OracleNotFound, resolve_oracle, run_oracle
from forge.verdict import (
    CLAIM_VERDICT,
    EVIDENCE_VERDICT,
    Verdict,
    build_verdict,
    sign_verdict,
)

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class GateResult:
    verdict: Verdict
    signature: str
    ok: bool
    # Maillon que le DRIVER voit reellement : sans lui la mesure s'arreterait au gate.
    # NON signe — la charge HMAC ne porte que `Verdict` (lecon e48801c).
    summary: dict | None = None


def _blocked(project: str, key_file: Path | None) -> GateResult:
    verdict = Verdict(
        project=project,
        software_verdict="BLOCKED",
        evidence_verdict=EVIDENCE_VERDICT,
        claim_verdict=CLAIM_VERDICT,
        returncode=-1,
        evidence_path="",
    )
    return GateResult(verdict=verdict, signature=sign_verdict(verdict, key_file), ok=False)


def forge_gate(
    project: str,
    config_path: Path | None = None,
    key_file: Path | None = None,
    evidence_dir: Path | None = None,
) -> GateResult:
    try:
        spec = resolve_oracle(project, config_path=config_path)
    except (OracleNotFound, OSError, ValueError) as exc:
        logger.warning("oracle config for %s unusable (%s) -> BLOCKED", project, exc)
        return _blocked(project, key_file)

    try:
        result = run_oracle(spec, evidence_dir=evidence_dir)
    except OSError as exc:
        logger.warning("oracle for %s could not run (%s) -> BLOCKED", project, exc)
        return _blocked(project, key_file)

    # `timed_out` propagé TEL QUEL depuis le reçu d'exécution : le gate ne le devine pas,
    # il le transmet. Même esprit que le `_blocked(...)` sur OSError juste au-dessus —
    # quand l'oracle n'a pas pu conclure, le verdict le dit au lieu de condamner le produit.
    verdict = build_verdict(project, result.passed, result.returncode, result.evidence_path,
                            timed_out=result.timed_out)
    signature = sign_verdict(verdict, key_file)
    return GateResult(verdict=verdict, signature=signature, ok=result.passed,
                      summary=result.summary)
