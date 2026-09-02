"""RUN 2 V1 — point A2 du protocole (docs/forge/RUN2_PROTOCOLE_V1_PROPOSED.md) :
« Masquage V2 ». Le masquage V1 (mots-interdits, ligne à ligne) a tué au
pilote une ligne portant une valeur de gameplay réelle simplement parce
qu'elle contenait, quelque part sur la ligne, un mot qui matchait la liste
noire de provenance -- alors que la ligne n'appartenait à aucune section de
provenance. Le V2 remplace ça par : suppression de BLOCS STRUCTURÉS nommés
(sections markdown dont le TITRE matche des motifs de provenance/protocole),
jamais un filtre mot-à-mot sur le contenu. Plus une passe de contrôle
obligatoire (`verify_masking`) : aucune ligne à valeur numérique de gameplay
ne peut avoir disparu du document masqué, sauf exception listée et justifiée.

Non-régression obligatoire (bug du pilote) : une ligne comme
`gain_clic: 1  # ... (structure imposée)`, qui vit dans un bloc de contenu
normal (pas un bloc de provenance/protocole), ne doit JAMAIS disparaître --
le masquage V2 ne touche qu'à des blocs entiers désignés par leur titre,
jamais à une ligne isolée à l'intérieur d'un bloc conservé.
"""
from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# Heuristique de « ligne portant une valeur numérique de gameplay »
# ---------------------------------------------------------------------------
#
# Une ligne est considérée comme PORTEUSE DE VALEUR si, après avoir retiré les
# ANCRES PURES connues (numérotation markdown, dates ISO, références de
# ligne/issue, hash de commit), il reste au moins un chiffre dessus. C'est une
# heuristique documentée, pas une preuve sémantique : elle sur-détecte plutôt
# que sous-détecte (une ligne ambiguë est traitée comme porteuse de valeur),
# parce que le risque asymétrique du sas est de PERDRE une valeur de
# gameplay, pas de garder une ligne inerte de trop.
#
# Ancres reconnues et retirées avant le test de présence de chiffre :
#   - dates ISO complètes            : 2026-08-30
#   - puce de liste ordonnée markdown: "12. " ou "12) " en tête de ligne
#   - référence de ligne             : "L123", "ligne 123"
#   - référence d'issue/PR/IMP       : "#123", "IMP-123"
#   - hash de commit (hex avec au moins une lettre a-f, 7-40 car.)
#   - ancre de footnote markdown     : "[^12]"
#
# Une ligne de titre markdown (`#`, `##`, ...) n'est PAS testée : un titre est
# structurel, jamais une valeur de gameplay au sens de ce sas.

_ANCHOR_PATTERNS: list[re.Pattern[str]] = [
    re.compile(r"\b\d{4}-\d{2}-\d{2}\b"),  # date ISO
    re.compile(r"^\s*\d+[.)]\s+"),  # puce de liste ordonnée en tête de ligne
    re.compile(r"\b[Ll]igne\s+\d+\b"),  # "ligne 123"
    re.compile(r"\bL\d+\b"),  # "L123" (référence de ligne style diff)
    re.compile(r"#\d+\b"),  # référence d'issue/PR "#123"
    re.compile(r"\bIMP-\d+\b", re.IGNORECASE),  # "IMP-123"
    re.compile(r"\[\^\d+\]"),  # footnote markdown "[^12]"
    re.compile(r"\b(?=[0-9a-f]{7,40}\b)(?=[0-9a-f]*[a-f])[0-9a-f]{7,40}\b"),  # hash commit hex
]

_HEADING_RE = re.compile(r"^(#{1,6})\s+(.*)$")


def is_gameplay_value_line(line: str) -> bool:
    """Heuristique documentée ci-dessus. Une ligne de titre markdown n'est
    jamais une ligne à valeur (elle est structurelle)."""
    if _HEADING_RE.match(line):
        return False
    stripped_anchors = line
    for pat in _ANCHOR_PATTERNS:
        stripped_anchors = pat.sub("", stripped_anchors)
    return bool(re.search(r"\d", stripped_anchors))


# ---------------------------------------------------------------------------
# Découpage en blocs structurés (sections markdown par titre)
# ---------------------------------------------------------------------------


@dataclass
class _Block:
    title: str | None  # None = préambule avant le premier titre
    start: int  # index de ligne inclus
    end: int  # index de ligne exclu
    lines: list[str] = field(default_factory=list)


def _split_blocks(lines: list[str]) -> list[_Block]:
    blocks: list[_Block] = []
    current_title: str | None = None
    current_start = 0
    for idx, line in enumerate(lines):
        m = _HEADING_RE.match(line)
        if m:
            # ferme le bloc courant (peut être vide si deux titres se suivent)
            blocks.append(_Block(title=current_title, start=current_start, end=idx, lines=lines[current_start:idx]))
            current_title = m.group(2).strip()
            current_start = idx
    blocks.append(_Block(title=current_title, start=current_start, end=len(lines), lines=lines[current_start:len(lines)]))
    return blocks


def _pattern_matches_title(pattern: str, title: str) -> bool:
    if not title:
        return False
    try:
        if re.search(pattern, title, re.IGNORECASE):
            return True
    except re.error:
        pass
    return pattern.lower() in title.lower()


def _normalize_blocks_to_strip(blocks_to_strip: list[Any]) -> list[dict[str, str | None]]:
    """Accepte soit une chaîne (motif simple), soit un dict
    {"pattern": ..., "justification": ...} pour pré-déclarer une exception
    justifiée sur un bloc dont on SAIT qu'il contient des valeurs (ex. un
    bloc de calibration en clair délibérément retiré du dossier aveugle)."""
    normalized: list[dict[str, str | None]] = []
    for entry in blocks_to_strip:
        if isinstance(entry, str):
            normalized.append({"pattern": entry, "justification": None})
        elif isinstance(entry, dict):
            pattern = entry.get("pattern")
            if not pattern:
                continue
            normalized.append({"pattern": pattern, "justification": entry.get("justification")})
        else:
            raise TypeError(f"blocks_to_strip: entrée non supportée {entry!r}")
    return normalized


def mask_document(text: str, blocks_to_strip: list[Any]) -> tuple[str, dict[str, Any]]:
    """Masquage V2 : suppression de BLOCS STRUCTURÉS entiers dont le titre
    matche un des motifs de `blocks_to_strip`. Jamais de suppression
    ligne-à-ligne par mot interdit.

    Retourne (masked_text, report). `report["stripped_blocks"]` liste les
    blocs effectivement retirés ; `report["exceptions"]` liste, pour les
    blocs retirés qui portaient au moins une ligne à valeur de gameplay ET
    dont le motif d'appel fournissait une justification, l'exception
    correspondante (consommée ensuite par `verify_masking`).
    """
    patterns = _normalize_blocks_to_strip(blocks_to_strip)
    lines = text.splitlines()
    blocks = _split_blocks(lines)

    kept_lines: list[str] = []
    stripped_blocks: list[dict[str, Any]] = []
    exceptions: list[dict[str, Any]] = []

    for block in blocks:
        matched_pattern: dict[str, str | None] | None = None
        if block.title is not None:
            for p in patterns:
                if _pattern_matches_title(p["pattern"], block.title):
                    matched_pattern = p
                    break

        if matched_pattern is None:
            kept_lines.extend(block.lines)
            continue

        value_lines = [ln for ln in block.lines if is_gameplay_value_line(ln)]
        stripped_blocks.append(
            {
                "heading": block.title,
                "pattern": matched_pattern["pattern"],
                "line_count": len(block.lines),
                "value_lines_removed": list(value_lines),
            }
        )
        if value_lines:
            exceptions.append(
                {
                    "heading": block.title,
                    "pattern": matched_pattern["pattern"],
                    "justification": matched_pattern["justification"],
                    "value_lines_removed": list(value_lines),
                }
            )
        # bloc retiré : ses lignes ne rejoignent pas kept_lines.

    masked_text = "\n".join(kept_lines)
    if text.endswith("\n") and not masked_text.endswith("\n"):
        masked_text += "\n"

    report = {
        "stripped_blocks": stripped_blocks,
        "exceptions": exceptions,
    }
    return masked_text, report


# ---------------------------------------------------------------------------
# Contrôle obligatoire : aucune valeur de gameplay ne disparaît sans exception
# ---------------------------------------------------------------------------


def verify_masking(
    original: str,
    masked: str,
    exceptions: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """RÈGLE DURE : toute ligne de `original` classée porteuse de valeur par
    `is_gameplay_value_line` doit être présente TELLE QUELLE dans `masked`,
    sauf si son texte exact apparaît dans un `value_lines_removed` d'une
    entrée de `exceptions` munie d'une `justification` non vide.

    `exceptions` est typiquement `report["exceptions"]` retourné par
    `mask_document` (chaque entrée sans justification n'excuse RIEN --
    justification vide/None = violation quand même, fail-closed).
    """
    exceptions = exceptions or []

    justified_lines: set[str] = set()
    for exc in exceptions:
        justification = exc.get("justification")
        if not justification:
            continue  # exception non justifiée = ne couvre aucune ligne
        for ln in exc.get("value_lines_removed", []):
            justified_lines.add(ln)

    masked_lines = set(masked.splitlines())

    violations: list[dict[str, str]] = []
    for ln in original.splitlines():
        if not is_gameplay_value_line(ln):
            continue
        if ln in masked_lines:
            continue
        if ln in justified_lines:
            continue
        violations.append({"line": ln, "reason": "valeur de gameplay disparue sans exception justifiée"})

    return {"ok": len(violations) == 0, "violations": violations}


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="forge.m7_masking",
        description="Masquage V2 par blocs structurés (A2) avec contrôle obligatoire de non-perte de valeur.",
    )
    parser.add_argument("input_path", type=Path)
    parser.add_argument("output_path", type=Path)
    parser.add_argument(
        "--strip",
        default="",
        help="motifs de titres de bloc à retirer, séparés par des virgules",
    )
    args = parser.parse_args(argv)

    motifs = [m.strip() for m in args.strip.split(",") if m.strip()]

    original = args.input_path.read_text(encoding="utf-8")
    masked, report = mask_document(original, motifs)
    verify = verify_masking(original, masked, report["exceptions"])

    if not verify["ok"]:
        print("M7_MASKING: FAIL -- valeurs de gameplay perdues sans exception justifiée :", file=sys.stderr)
        for v in verify["violations"]:
            print(f"  - {v['line']!r}", file=sys.stderr)
        return 1

    args.output_path.write_text(masked, encoding="utf-8")
    print(f"M7_MASKING: OK -- {len(report['stripped_blocks'])} bloc(s) retiré(s), écrit dans {args.output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
