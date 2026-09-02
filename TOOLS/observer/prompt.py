"""Vue « prompt reel » de Forge Observer V0 — lecture seule.

Objectif : rendre observable, et VERIFIABLE, le prompt reellement recu par
chaque activation d'un agent d'etape Forge — pas ce que le contrat pretend
avoir envoye, pas ce que l'agent pretend avoir lu, mais le texte exact stocke
dans son transcript, confronte a l'empreinte que la Forge a elle-meme
declaree au moment du dispatch.

Fait etabli (verifie manuellement avant d'ecrire ce module) : le prompt
REELLEMENT recu par un agent d'etape Forge est stocke integralement dans son
transcript, dans la premiere ligne de type ``queue-operation`` (champ
``content``), et repete dans le premier message ``user``. La Forge declare de
son cote, dans ``lab/forge_runs/<projet>/context/<etape>.manifest.jsonl``, les
champs ``final_prompt_sha256`` et ``final_prompt_chars`` d'une ligne
``kind: "execution"``. En normalisant les fins de ligne (``\r\n`` -> ``\n``),
le SHA-256 du texte INTEGRAL (marqueur de dispatch final compris) reproduit
exactement ``final_prompt_sha256`` — verifie sur breakout_v2 run3/s9 :
13 717 caracteres normalises, empreinte ``be5e274b1dcd6c...``.

Correlation attempt <-> declaration — point non trivial : le marqueur de
dispatch apparait DEUX fois dans un meme prompt (un en-tete au debut, sans
suffixe ; le marqueur final ajoute par le mecanisme de dispatch, en toute fin
de texte, AVEC suffixe ``:<attempt>`` s'il y en a un). C'est ce dernier
(occurrence la plus a droite dans le texte) qui fait foi. Le numero
d'``attempt`` qu'il porte est un compteur LOCAL a (etape, run_id) : il ne
correspond PAS au champ ``activation`` du manifest, qui lui incremente
globalement sur tout le fichier ``<etape>.manifest.jsonl`` (verifie : trois
dispatches du meme run_id portent activation 1/2/3 mais un run_id different,
dispatche une seule fois, porte activation 4 avec un attempt de marqueur = 1).
La correlation correcte se fait donc par position dans le groupe
``(run_id, etape)`` de declarations d'execution, dans l'ordre du fichier —
avec repli sur une recherche par empreinte exacte si l'attempt est absent ou
hors bornes, et ``NO_DECLARATION`` explicite si aucune des deux ne resout
l'ambiguite plutot que de deviner.

Lecture UNIQUEMENT via `ObserverContext` (garde de cecite). Aucune ecriture.
Aucun `open()` direct. `BlindnessViolation` n'est jamais rattrapee.
"""

from __future__ import annotations

import argparse
import hashlib
import logging
import re
import sys
import unicodedata
from pathlib import Path
from typing import Any, Optional

_HERE = Path(__file__).resolve().parent
if str(_HERE.parent) not in sys.path:  # rend `import observer` possible sans install
    sys.path.insert(0, str(_HERE.parent))

from observer.sources import (  # noqa: E402
    BlindnessViolation,
    ObserverContext,
    default_repo_root,
    default_transcripts_root,
)

LOG = logging.getLogger("observer.prompt")

NAME = "prompt"

# Meme forme que `scripts/forge/hook_guard.py` ~l.29 (MARKER) et
# `observer/adapters/transcripts.py` ~l.65 (_MARKER_RE) : etape et run_id en
# [\w.\-]+, attempt optionnel en suffixe numerique. Reproduite ici (pas
# importee) pour la meme raison d'independance : Observer ne doit jamais
# dependre du module `forge`.
_MARKER_RE = re.compile(r"FORGE_DISPATCH:([\w.\-]+):([\w.\-]+)(?::(\d+))?")

# Le prompt est en ligne 1 (queue-operation) — au plus quelques lignes de
# marge (attachements, repetition en message user). Meme borne que
# `transcripts.py::_HEAD_SCAN_LINES` : un fichier de transcript peut peser
# plusieurs Mo, il est hors de question de le lire en entier pour ca.
_HEAD_SCAN_LINES = 50

_EXCERPT_CHARS = 300
_HEADER_NAME_MAX = 120

# Detection des en-tetes de section — PAS de liste fermee de noms : on
# detecte par MOTIF, pas par catalogue. Trois formes rencontrees en pratique
# dans les prompts Forge (et au-dela, pour rester generique) :
#   1. `## TITRE ...`                          (dominant, verifie en pratique)
#   2. une ligne entierement en majuscules, seule sur sa ligne
#   3. une ligne courte terminee par ` :` (titre de bloc a l'ancienne)
_HEADER_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"(?m)^##[ \t]*[^\n]*"),
    re.compile(r"(?m)^[A-Z0-9\ufffd][A-Z0-9 _\-'\"/()\ufffd]{3,79}$"),
    re.compile(r"(?m)^[^\n]{2,80}[ \t]*:[ \t]*$"),
)


# --------------------------------------------------------------------------- #
# Point d'entree
# --------------------------------------------------------------------------- #


def collect_prompts(ctx: ObserverContext) -> list[dict[str, Any]]:
    """Reconstruit UNE entree par activation d'agent d'etape Forge trouvee
    dans les transcripts, avec verification croisee contre la declaration de
    la Forge (`context/<etape>.manifest.jsonl`).

    Ne leve jamais que `BlindnessViolation` (jamais rattrapee) : un fichier
    illisible ou inattendu est journalise et saute, il n'interrompt pas le
    balayage global.
    """
    project_prefix = f"{ctx.project}-"
    declared_index = _build_declared_index(ctx)

    entries: list[dict[str, Any]] = []
    for path in ctx.iter_files(ctx.transcripts_root, "*.jsonl"):
        try:
            found = _find_dispatch_prompt(ctx, path, project_prefix)
        except BlindnessViolation:
            raise
        except Exception:
            LOG.warning("extraction du prompt echouee sur %s", path, exc_info=True)
            continue
        if found is None:
            continue
        try:
            entries.append(_build_entry(ctx, path, found, declared_index))
        except BlindnessViolation:
            raise
        except Exception:
            LOG.warning("construction d'entree echouee sur %s", path, exc_info=True)
            continue
    return entries


# --------------------------------------------------------------------------- #
# Detection + extraction du prompt (une seule passe bornee par fichier)
# --------------------------------------------------------------------------- #


def _instruction_text(obj: dict[str, Any]) -> tuple[str, str]:
    """Texte d'une ligne susceptible de porter une INSTRUCTION recue par
    l'agent, et l'etiquette de sa provenance.

    Mirroir de `adapters/transcripts.py::_dispatch_text` : seules deux
    positions comptent comme instruction — `queue-operation.content` (prompt
    injecte en tete de session) et un message `user` dont le contenu est du
    texte (jamais un `tool_result`). Tout le reste (sorties d'outils, texte du
    modele, tool_use d'un orchestrateur qui dispatche un sous-agent) est
    ignore : un marqueur MENTIONNE ailleurs n'est pas un marqueur RECU.
    """
    kind = obj.get("type")
    if kind == "queue-operation":
        content = obj.get("content")
        return (content if isinstance(content, str) else ""), "queue-operation"
    if kind == "user":
        message = obj.get("message")
        if not isinstance(message, dict):
            return "", "user"
        content = message.get("content")
        if isinstance(content, str):
            return content, "user"
        if isinstance(content, list):
            text = " ".join(
                block.get("text", "")
                for block in content
                if isinstance(block, dict) and block.get("type") == "text"
            )
            return text, "user"
        return "", "user"
    return "", str(kind) if kind else "unknown"


def _find_dispatch_prompt(
    ctx: ObserverContext, path: Path, project_prefix: str
) -> Optional[dict[str, Any]]:
    """Cherche, dans les `_HEAD_SCAN_LINES` premieres lignes de `path`, la
    premiere ligne en position d'instruction qui porte au moins un marqueur
    de ce projet. Retourne son texte INTEGRAL et le marqueur RETENU (le
    dernier trouve dans le texte — c'est le marqueur final de dispatch, pas
    l'en-tete de rappel qui le precede, cf. docstring de module).

    Une seule passe, arret des la premiere ligne exploitable trouvee : on ne
    lit jamais un fichier de transcript en entier pour cette extraction.
    """
    gen = ctx.read_jsonl(path)
    try:
        for i, (lineno, obj) in enumerate(gen):
            if i >= _HEAD_SCAN_LINES:
                break
            text, source_type = _instruction_text(obj)
            if not text:
                continue
            matches = [
                m for m in _MARKER_RE.finditer(text) if m.group(2).startswith(project_prefix)
            ]
            if not matches:
                continue
            last = matches[-1]
            etape, run_id, attempt_raw = last.group(1), last.group(2), last.group(3)
            attempt = int(attempt_raw) if attempt_raw is not None else None
            session_id = obj.get("sessionId") if isinstance(obj.get("sessionId"), str) else None
            return {
                "lineno": lineno,
                "text": text,
                "run_id": run_id,
                "etape": etape,
                "attempt": attempt,
                "session_id": session_id,
                "source_type": source_type,
            }
    finally:
        gen.close()
    return None


# --------------------------------------------------------------------------- #
# Declaration de la Forge — context/<etape>.manifest.jsonl
# --------------------------------------------------------------------------- #


def _build_declared_index(ctx: ObserverContext) -> dict[tuple[str, str], list[dict[str, Any]]]:
    """Index (run_id, etape) -> liste ordonnee (ordre du fichier = ordre
    chronologique) des declarations d'execution (`kind: "execution"`),
    chacune enrichie des champs de son `kind: "dispatch"` correspondant
    (memes run_id, la ligne de dispatch la plus recente vue pour ce run_id
    au moment de l'execution — les deux s'entrelacent dans le fichier).

    Un (run_id, etape) qui n'a QUE des lignes `dispatch` (jamais suivies
    d'une `execution`) n'apparait pas dans cet index : c'est un fait reel
    (la Forge a prepare le dispatch mais n'a jamais declare de prompt final
    pour cette activation), pas une lacune de lecture.
    """
    index: dict[tuple[str, str], list[dict[str, Any]]] = {}
    context_dir = ctx.run_dir / "context"
    for path in ctx.iter_files(context_dir, "*.manifest.jsonl"):
        etape_guess = path.name.split(".", 1)[0]
        pending_dispatch: dict[str, dict[str, Any]] = {}
        for lineno, obj in ctx.read_jsonl(path):
            kind = obj.get("kind")
            run_id = obj.get("run_id")
            if not isinstance(run_id, str):
                continue
            etape = obj.get("etape") if isinstance(obj.get("etape"), str) else etape_guess

            if kind == "dispatch":
                pending_dispatch[run_id] = {
                    "contract_sha256": obj.get("contract_sha256"),
                    "payload_prompt_sha256": obj.get("payload_prompt_sha256"),
                    "activation": obj.get("activation"),
                }
            elif kind == "execution":
                disp = pending_dispatch.get(run_id, {})
                record = {
                    "final_prompt_sha256": obj.get("final_prompt_sha256"),
                    "final_prompt_chars": obj.get("final_prompt_chars"),
                    "premortem_sha256": obj.get("premortem_sha256"),
                    "prompt_budget": obj.get("prompt_budget"),
                    "contract_sha256": disp.get("contract_sha256"),
                    "payload_prompt_sha256": disp.get("payload_prompt_sha256"),
                    "activation": disp.get("activation"),
                    "source": {"path": ctx.rel(path), "line": lineno},
                }
                index.setdefault((run_id, etape), []).append(record)
    return index


def _finalize_declared(record: dict[str, Any]) -> dict[str, Any]:
    return {
        "final_prompt_sha256": record.get("final_prompt_sha256"),
        "final_prompt_chars": record.get("final_prompt_chars"),
        "contract_sha256": record.get("contract_sha256"),
        "premortem_sha256": record.get("premortem_sha256"),
        "payload_prompt_sha256": record.get("payload_prompt_sha256"),
        "prompt_budget": record.get("prompt_budget"),
        "source": record.get("source"),
    }


def _match_declared(
    candidates: list[dict[str, Any]],
    attempt: Optional[int],
    sha256_normalized: str,
) -> tuple[Optional[dict[str, Any]], Optional[str]]:
    """Choisit, parmi les declarations connues pour (run_id, etape), celle
    qui correspond a CETTE activation. Ordre de resolution, du plus sur au
    plus incertain — jamais de choix silencieux :

      1. `attempt` du marqueur final, utilise comme position 1-indexee dans
         le groupe (l'attempt d'un marqueur est un compteur local a ce
         run_id, qui coincide avec l'ordre d'ecriture des declarations).
      2. une seule declaration connue pour ce (run_id, etape) : rattachement
         par defaut, note si `attempt` etait pourtant present et hors bornes.
      3. plusieurs declarations, attempt absent/hors bornes : recherche
         d'une empreinte EXACTEMENT unique parmi elles.
      4. sinon : aucun rattachement — `None`, avec la raison.
    """
    if not candidates:
        return None, None

    if attempt is not None and 1 <= attempt <= len(candidates):
        return _finalize_declared(candidates[attempt - 1]), None

    if len(candidates) == 1:
        note = (
            None
            if attempt is None
            else f"attempt={attempt} hors bornes (1 seule declaration connue) — rattachee par defaut"
        )
        return _finalize_declared(candidates[0]), note

    exact = [c for c in candidates if c.get("final_prompt_sha256") == sha256_normalized]
    if len(exact) == 1:
        return (
            _finalize_declared(exact[0]),
            "rattachement par empreinte exacte (attempt absent ou hors bornes)",
        )

    return None, (
        f"{len(candidates)} declarations connues pour ce run/etape, attempt={attempt!r} "
        "non resolu et aucune empreinte ne correspond de facon unique"
    )


# --------------------------------------------------------------------------- #
# Construction d'une entree
# --------------------------------------------------------------------------- #


def _build_entry(
    ctx: ObserverContext,
    path: Path,
    found: dict[str, Any],
    declared_index: dict[tuple[str, str], list[dict[str, Any]]],
) -> dict[str, Any]:
    text: str = found["text"]
    normalized = text.replace("\r\n", "\n")
    sha256_normalized = hashlib.sha256(normalized.encode("utf-8")).hexdigest()

    run_id: str = found["run_id"]
    etape: str = found["etape"]
    attempt: Optional[int] = found["attempt"]

    candidates = declared_index.get((run_id, etape), [])
    declared, note = _match_declared(candidates, attempt, sha256_normalized)

    if declared is None:
        verification = "NO_DECLARATION"
    elif declared.get("final_prompt_sha256") == sha256_normalized:
        verification = "MATCH"
    else:
        verification = "MISMATCH"

    entry: dict[str, Any] = {
        "run_id": run_id,
        "etape": etape,
        "attempt": attempt,
        "session_file": str(path),
        "session_id": found.get("session_id"),
        "source": {
            "path": ctx.rel(path),
            "line": found["lineno"],
            "fmt": "jsonl",
            "field": found["source_type"],
        },
        "chars": len(text),
        "chars_normalized": len(normalized),
        "sha256_normalized": sha256_normalized,
        "declared": declared,
        "verification": verification,
        "sections": _split_sections(text),
        "texte": text,
    }
    if note:
        entry["note"] = note
    return entry


# --------------------------------------------------------------------------- #
# Decoupage en sections
# --------------------------------------------------------------------------- #


def _split_sections(text: str) -> list[dict[str, Any]]:
    """Decoupe `text` par ses en-tetes de section REELLEMENT trouves (aucune
    liste fermee codee en dur, cf. `_HEADER_PATTERNS`). Une section va du
    debut de son en-tete au debut du suivant (ou a la fin du texte)."""
    starts: list[tuple[int, str]] = []
    seen_offsets: set[int] = set()
    for pattern in _HEADER_PATTERNS:
        for m in pattern.finditer(text):
            if m.start() in seen_offsets:
                continue
            seen_offsets.add(m.start())
            starts.append((m.start(), m.group(0)))
    starts.sort(key=lambda pair: pair[0])

    sections: list[dict[str, Any]] = []
    for idx, (start, header) in enumerate(starts):
        end = starts[idx + 1][0] if idx + 1 < len(starts) else len(text)
        name = header.strip()
        if len(name) > _HEADER_NAME_MAX:
            name = name[:_HEADER_NAME_MAX].rstrip() + "…"
        sections.append(
            {
                "nom": name,
                "debut": start,
                "longueur": end - start,
                "extrait": text[start : start + _EXCERPT_CHARS],
            }
        )
    return sections


# --------------------------------------------------------------------------- #
# Classement dans les 6 rubriques de la vue « prompt reel »
# --------------------------------------------------------------------------- #

# Motifs tolerants au mojibake observe dans les transcripts (les caracteres
# accentues du francais sont parfois decodes en U+FFFD par la source elle
# meme, avant meme qu'Observer ne la lise — `## RÔLE` devient `## R<0xFFFD>LE`).
# Un seul caractere generique remplace la position de l'accent : ca couvre
# aussi bien la forme correctement accentuee que la forme corrompue.
_ROLE_RE = re.compile(r"R.LE", re.IGNORECASE)
_MEMOIRE_RE = re.compile(r"M.MOIRE", re.IGNORECASE)
_CONTRAT_RE = re.compile(r"CONTRAT", re.IGNORECASE)
_LIRE_RE = re.compile(r"\bLIRE\b", re.IGNORECASE)


def _find_section(sections: list[dict[str, Any]], pattern: re.Pattern[str]) -> Optional[dict[str, Any]]:
    for section in sections:
        if pattern.search(section.get("nom", "")):
            return section
    return None


def _rubrique_found(section: dict[str, Any]) -> dict[str, Any]:
    return {"status": "FOUND", "section": section, "reason": None}


def _rubrique_not_observable(reason: str) -> dict[str, Any]:
    return {"status": "NOT_OBSERVABLE", "section": None, "reason": reason}


def classify_sections(entry: dict[str, Any]) -> dict[str, Any]:
    """Pour les six rubriques demandees par la vue « prompt reel », rend soit
    la section reellement trouvee dans `entry["sections"]`, soit
    littéralement `NOT_OBSERVABLE` (statut) avec une raison courte.

    N'INVENTE jamais une rubrique absente : une rubrique qui ne correspond a
    aucune section reelle du texte est `NOT_OBSERVABLE`, point final — ce
    module ne devine pas ce qu'un prompt "devrait" contenir.
    """
    sections = entry.get("sections") or []
    out: dict[str, Any] = {}

    role_section = _find_section(sections, _ROLE_RE)
    out["prompt_systeme"] = (
        _rubrique_found(role_section)
        if role_section is not None
        else _rubrique_not_observable("aucun en-tete de type '## ROLE' detecte dans le texte")
    )

    # Le contexte AMBIANT (hooks SessionStart, CLAUDE.md, .claude/rules,
    # settings.local) est injecte par le harnais Claude Code EN AMONT du
    # texte capture ici — la Forge elle-meme le documente comme non mesure
    # (`ambient_context_note` du manifest dit explicitement : "constante
    # ambiante non mesuree ici"). Aucune section du prompt ne le porte : ce
    # n'est pas une lacune de detection, c'est une absence reelle.
    out["contexte_injecte"] = _rubrique_not_observable(
        "contexte ambiant (hooks/CLAUDE.md/regles) injecte par le harnais en amont du "
        "texte capture ici ; aucune section du prompt ne le rend observable "
        "(cf. ambient_context_note du manifest, qui le declare lui-meme non mesure)"
    )

    memoire_section = _find_section(sections, _MEMOIRE_RE)
    out["memoire"] = (
        _rubrique_found(memoire_section)
        if memoire_section is not None
        else _rubrique_not_observable("aucun en-tete de type 'MEMOIRE' detecte dans le texte")
    )

    contrat_section = _find_section(sections, _CONTRAT_RE)
    out["contrats"] = (
        _rubrique_found(contrat_section)
        if contrat_section is not None
        else _rubrique_not_observable("aucun en-tete contenant 'CONTRAT' detecte dans le texte")
    )

    lire_section = _find_section(sections, _LIRE_RE)
    out["documents_lus"] = (
        _rubrique_found(lire_section)
        if lire_section is not None
        else _rubrique_not_observable("aucun en-tete de type 'A LIRE' detecte dans le texte")
    )

    # Le "prompt final" n'est pas une sous-section : c'est le texte INTEGRAL
    # deja capture et verifie plus haut (chars_normalized/sha256_normalized).
    # Le rendre NOT_OBSERVABLE serait faux : c'est precisement ce que ce
    # module observe.
    out["prompt_final"] = {
        "status": "FOUND",
        "section": {
            "nom": "PROMPT_FINAL (texte integral capture, marqueur de dispatch compris)",
            "debut": 0,
            "longueur": entry.get("chars_normalized"),
            "extrait": (entry.get("texte") or "")[:_EXCERPT_CHARS],
        },
        "reason": None,
    }

    return out


# --------------------------------------------------------------------------- #
# Demonstration / preuve d'execution
# --------------------------------------------------------------------------- #


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Vue 'prompt reel' de Forge Observer V0 (lecture seule)"
    )
    parser.add_argument("--project", default="breakout_v2")
    parser.add_argument("--repo", type=Path, default=default_repo_root())
    parser.add_argument(
        "--transcripts",
        type=Path,
        default=default_transcripts_root(),
    )
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.INFO if args.verbose else logging.WARNING,
        format="%(levelname)s %(name)s: %(message)s",
    )

    ctx = ObserverContext.build(args.repo, args.project, args.transcripts)
    entries = collect_prompts(ctx)

    print(f"activations trouvees : {len(entries)}")
    print()
    for entry in sorted(
        entries,
        key=lambda e: (e["run_id"] or "", e["etape"] or "", e["attempt"] if e["attempt"] is not None else -1),
    ):
        section_names = [s["nom"] for s in entry["sections"]]
        print(f"run_id      : {entry['run_id']}")
        print(f"etape       : {entry['etape']}")
        print(f"attempt     : {entry['attempt']}")
        print(f"chars       : {entry['chars']} (normalise: {entry['chars_normalized']})")
        print(f"verification: {entry['verification']}")
        if entry.get("note"):
            print(f"note        : {entry['note']}")
        print(f"sections    : {section_names}")
        print("-" * 72)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
