"""Mesure d'adoption de la primitive `skipped_validation[]`.

Ratification Pierre 2026-07-26 (primitive 1 du salvage Codex — voir
`studio_brain/decisions/PROPOSED_2026-07-26_ratifications.md`) : généraliser aux
21 contrats Forge une exigence déjà présente en prose dans un seul
(`contracts/orchestrator.yaml` : « ce que je n'ai PAS prouvé »). L'exigence elle-
même est injectée verbatim par `contract.RESTITUTION_RULE`.

Ce module fait l'AUTRE moitié, sans laquelle une règle en prose finit comme le
corpus Codex — déclarative, jamais lue (cf. memory `structured_field_not_comment`
et le garde-fou posé par la ratification : « toute primitive reprise doit arriver
avec son point de mesure »). Il répond à une seule question, sur la sortie texte
RÉELLE d'un agent : la section `SKIPPED_VALIDATION` a-t-elle été produite, et
comment ?

ADVISORY UNIQUEMENT (garde-fou de la ratification, GO conditionné à l'advisory
d'abord) :
- Aucune fonction ici ne lit ni ne modifie un `software_verdict`, un
  `evidence_verdict`, un `verdict.json` signé, ni le comportement de
  `verify_run`/`gate.py`/`verdict.py`.
- Ce module ne bloque RIEN et ne lève jamais d'exception sur une entrée
  malformée : le pire résultat possible est "absent".
- Le passage en gate dur (faire échouer un run si la section manque) est une
  décision Pierre distincte et ultérieure, prise au vu des chiffres d'adoption
  mesurés par ce module — pas ici.

Les 3 résultats retournés reprennent le vocabulaire des 3 états d'un champ de
`contract.field_state` (SCHEMA.md), appliqués ici à une sortie de texte libre
plutôt qu'à un champ de contrat d'entrée :

- "filled"         : section présente, avec un contenu réel (>=1 entrée).
- "declared_empty" : section présente, sentinelle `aucun` (SENTINEL_EMPTY) —
                      décision assumée : rien n'a été sauté.
- "absent"         : aucune section détectée (ou header sans corps) — un
                      silence/oubli, exactement ce que la primitive combat.
"""
from __future__ import annotations

import re

from forge.contract import SENTINEL_EMPTY

# Header autonome sur sa propre ligne : "## SKIPPED_VALIDATION", "SKIPPED_VALIDATION:",
# "Skipped Validation" ... insensible à la casse, underscore ou espace entre les mots.
_HEADER_LINE = re.compile(r"(?im)^[ \t]*#{0,6}[ \t]*skipped[_\s]validation[ \t]*:?[ \t]*$")

# Forme compacte en une seule ligne : "SKIPPED_VALIDATION: aucun" (avec ou sans '##'
# devant, ou toute autre décoration en tête de ligne).
_INLINE_DECLARED_EMPTY = re.compile(r"(?im)skipped[_\s]validation[ \t]*:[ \t]*aucun\b")

# Prochain header markdown : borne la fin du corps de la section repérée.
_NEXT_HEADER = re.compile(r"(?m)^[ \t]*#{1,6}[ \t]+\S")

# Caractères de décoration markdown tolérés autour de la sentinelle isolée
# ("- aucun", "* aucun *", "`aucun`"...).
_DECORATION_CHARS = "-*`_ \t"


def skipped_validation_status(agent_output: str | None) -> str:
    """Classe la section `skipped_validation` d'une sortie d'agent Forge.

    Ne lève jamais, quelle que soit l'entrée : `None`/vide/malformé => "absent".
    Pur advisory — ne consulte ni ne modifie aucun verdict, aucun état de run.
    """
    if not agent_output or not agent_output.strip():
        return "absent"

    if _INLINE_DECLARED_EMPTY.search(agent_output):
        return "declared_empty"

    header = _HEADER_LINE.search(agent_output)
    if not header:
        return "absent"

    tail = agent_output[header.end():]
    next_header = _NEXT_HEADER.search(tail)
    body = (tail[:next_header.start()] if next_header else tail).strip()

    if not body:
        # Header déclaré mais rien dessous : un oubli, pas une décision assumée.
        return "absent"

    stripped = body.strip(_DECORATION_CHARS).strip().rstrip(".").strip()
    if stripped.lower() == SENTINEL_EMPTY:
        return "declared_empty"

    return "filled"
