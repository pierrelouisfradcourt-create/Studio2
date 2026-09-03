"""Evidence Engine — format commun des decisions : « pas de decision sans provenance ».

Moissonne les decisions EXISTANTES du studio (rien d'invente) et les normalise
au format ratifie :

    DECISION { Objectif / Pourquoi / Source / Confiance / Action / Resultat / Lecon }

Cinq familles de sources, toutes deja presentes sur disque :

    decision_log   — studio_brain/decisions/decision-log.md (registre prose canonique)
    verdict_signe  — verdicts HMAC des runs (events `verdict.signed` d'Observer)
    lesson         — ratifications candidate -> validated dans lab/reports/lessons.jsonl
    deferred       — les DR- de studio_brain/decisions/DEFERRED.md (decisions differees)
    planning_gate  — decision_attendue par tache du registre studio_brain/planning/
                     planning.yaml (decisions FUTURES, statut EN_ATTENTE)

Regles dures, herites de la doctrine du studio :

  * Champ non derivable => "UNKNOWN" explicite. JAMAIS omis, JAMAIS invente
    (« ne pas transformer une hypothese en fait »).
  * Chaque decision porte une provenance {path, localisateur} obligatoire.
    Une decision sans source n'est PAS emise : elle est comptee dans
    `non_normalisables` avec sa raison.
  * Toute lecture passe par `ObserverContext` (cecite structurelle) — sauf le
    registre de sortie, ecrit sous lab/reports/observer/<projet>/ uniquement,
    avec la meme garde dure que system_planning._write_proposition.
  * Le registre `decisions_normalized.jsonl` est une VUE DERIVEE, pas un store :
    il est reecrit en entier a chaque run (append-safe par reconstruction).
  * `confiance` est un vocabulaire ferme : SELF_DECLARED (prose, best-effort),
    SIGNED (verdict portant un HMAC — la re-verification est le travail de
    forge.verify_run, pas d'ici), MECHANICAL (transition d'etat machine dans
    un jsonl). Jamais d'autre valeur.

Parsing prose : reutilise les primitives de `observer.command`
(`_parse_headed_sections`, `_DECISION_HEADER_RE`, `_DEFERRED_HEADER_RE`) —
elles sont pures (regex + segmentation ligne a ligne, aucun effet de bord).

FORMAT V2 — RATIFIE Pierre 2026-08-02 (P0-2). Champs canoniques exacts :

    DECISION { decision / expected_result / evidence / observed_result /
               status / lesson_candidate }

Invariant ratifie (verbatim) : toute nouvelle decision porte `decision /
expected_result / evidence / observed_result / status / lesson_candidate`.
« Le passé reste une mesure historique du manque. Le futur doit produire la
boucle. » Aucune reconstruction des decisions historiques (v1 legacy intact).

Regles :
  * `expected_result` est obligatoire AU MOMENT de la decision — une decision
    qui ne dit pas ce qu'elle attend n'est pas falsifiable.
  * `status` est un vocabulaire FERME : EN_ATTENTE_RESULTAT |
    RESULTAT_CONFORME | RESULTAT_CONTRAIRE | ABANDONNEE. Toute autre valeur
    prose => UNKNOWN (jamais reinterpretee).
  * status RESULTAT_CONTRAIRE => la decision sort dans
    `lesson_candidates_suggerees` de la vue — SIGNALEMENT seul, la creation
    de la lecon reste humaine.
  * Les anciens noms v2 (resultat_attendu / resultat_observe / preuve /
    lesson_creee, et leurs marqueurs prose) restent des ALIAS DE LECTURE pour
    la compat detection — ils ne sont plus des champs canoniques.
  * Adoption MANUELLE : gabarit a coller dans le decision-log (document
    DECISION_FORMAT_V2_RATIFIE.md) — ce module ne modifie aucun skill ni le
    decision-log lui-meme.
"""

from __future__ import annotations

import json
import logging
import re
from collections import Counter
from pathlib import Path
from typing import Any, Optional

try:
    from observer.command import (
        _DECISION_HEADER_RE,
        _DEFERRED_HEADER_RE,
        _parse_headed_sections,
    )
except ImportError:  # execution directe : python scripts/observer/evidence.py
    import sys

    _HERE = Path(__file__).resolve().parent
    if str(_HERE.parent) not in sys.path:
        sys.path.insert(0, str(_HERE.parent))
    from observer.command import (  # noqa: E402
        _DECISION_HEADER_RE,
        _DEFERRED_HEADER_RE,
        _parse_headed_sections,
    )

LOG = logging.getLogger("observer.evidence")

SCHEMA = "observer.decision.v1"
SCHEMA_V2 = "observer.decision.v2"
UNKNOWN = "UNKNOWN"

# Les 7 champs canoniques du format v1 (legacy) — toujours tous presents.
CANONICAL_FIELDS: tuple[str, ...] = (
    "objectif", "pourquoi", "source", "confiance", "action", "resultat", "lecon",
)

# Les 6 champs canoniques du format v2 RATIFIE (Pierre 2026-08-02) —
# toujours tous presents.
CANONICAL_FIELDS_V2: tuple[str, ...] = (
    "decision", "expected_result", "evidence",
    "observed_result", "status", "lesson_candidate",
)

# Vocabulaire FERME du champ `status` v2. Toute autre valeur => UNKNOWN.
V2_STATUS_VALUES: tuple[str, ...] = (
    "EN_ATTENTE_RESULTAT", "RESULTAT_CONFORME", "RESULTAT_CONTRAIRE", "ABANDONNEE",
)

# Seuil du compteur « v2 EN_ATTENTE_RESULTAT » (jours).
V2_STALE_DAYS = 7

_TRUNCATE = 300


# --------------------------------------------------------------------------- #
# Aides communes
# --------------------------------------------------------------------------- #


def _short(text: str, limit: int = _TRUNCATE) -> str:
    text = " ".join(text.split())
    return text if len(text) <= limit else text[:limit].rstrip() + "…"


def _decision(
    decision_id: str,
    source_family: str,
    statut: str,
    objectif: str,
    pourquoi: str,
    source: dict[str, Any],
    confiance: str,
    action: str,
    resultat: str,
    lecon: str,
) -> dict[str, Any]:
    """Une decision normalisee. Les 7 champs canoniques sont TOUJOURS presents ;
    la provenance est verifiee par l'appelant AVANT construction."""
    return {
        "schema": SCHEMA,
        "decision_id": decision_id,
        "source_family": source_family,
        "statut": statut,
        "objectif": objectif,
        "pourquoi": pourquoi,
        "source": source,
        "confiance": confiance,
        "action": action,
        "resultat": resultat,
        "lecon": lecon,
    }


def _section_bodies(text: str, header_re: re.Pattern) -> dict[int, list[str]]:
    """Pour chaque entete matchant `header_re` (ligne 1-indexee), les lignes de
    son corps : de la ligne suivante jusqu'au prochain '## ' (tout titre H2,
    pas seulement ceux du regex) ou la fin du document."""
    lines = text.splitlines()
    header_linenos = [
        i for i, line in enumerate(lines, start=1) if header_re.match(line)
    ]
    all_h2 = [i for i, line in enumerate(lines, start=1) if line.startswith("## ")]
    bodies: dict[int, list[str]] = {}
    for lineno in header_linenos:
        nexts = [h for h in all_h2 if h > lineno]
        end = (nexts[0] - 1) if nexts else len(lines)
        bodies[lineno] = lines[lineno:end]
    return bodies


def _extract_bold_field(body: list[str], label: str) -> Optional[str]:
    """Extrait '**<label>...** : valeur' d'un corps de section markdown.

    Best-effort assume (meme regime que command.py) : premiere ligne qui
    commence par `**<label>` — la valeur est ce qui suit le premier ':' hors
    gras, plus les lignes de continuation jusqu'a la prochaine ligne vide,
    la prochaine puce '- ' ou le prochain champ '**'. Prose, pas un schema.
    """
    marker = f"**{label}"
    for i, line in enumerate(body):
        stripped = line.strip()
        low = stripped.lower()
        if not (low.startswith(marker.lower()) or low.startswith(f"- {marker.lower()}")):
            continue
        after_bold = stripped.split("**", 2)[-1]
        value = after_bold.split(":", 1)[1].strip() if ":" in after_bold else ""
        parts = [value] if value else []
        for follow in body[i + 1:]:
            fs = follow.strip()
            if not fs or fs.startswith(("**", "- **", "##", "```")):
                break
            parts.append(fs)
        joined = " ".join(p for p in parts if p).strip()
        return joined or None
    return None


def _extract_bold_field_any(body: list[str], labels: tuple[str, ...]) -> Optional[str]:
    """Premier label (variantes accentuees/non accentuees) qui donne une valeur."""
    for label in labels:
        value = _extract_bold_field(body, label)
        if value is not None:
            return value
    return None


# --------------------------------------------------------------------------- #
# Format v2 — schema, gabarit, constructeur
# --------------------------------------------------------------------------- #

# Marqueurs prose -> champs v2 RATIFIES. Chaque tuple liste : les marqueurs du
# format ratifie D'ABORD, puis les anciens marqueurs v2 (alias de lecture,
# compat detection — les entrees deja ecrites avec l'ancien brouillon v2
# restent detectees). L'entree est classee v2 des qu'AU MOINS UN marqueur
# discriminant est present — un v2 incomplet reste v2, UNKNOWN visibles.
_V2_FIELD_LABELS: dict[str, tuple[str, ...]] = {
    "decision": ("Décision", "Decision", "Action"),
    "expected_result": ("Résultat attendu", "Resultat attendu"),
    "evidence": ("Preuve",),
    "observed_result": ("Résultat observé", "Resultat observe"),
    "status": ("Statut", "Status"),
    # « Leçon candidate » AVANT « Leçon » (prefixe commun) ; « Leçon » seul =
    # alias de l'ancien champ lesson_creee.
    "lesson_candidate": ("Leçon candidate", "Lecon candidate", "Leçon", "Lecon"),
}
# « Décision : » et « Statut : » seuls ne discriminent PAS : des entrees v1
# legacy portent deja '**Décision**' et '**Statut**' en prose (verifie sur le
# decision-log reel, entree 2026-07-23 l.242) — le v2 se reconnait a la boucle
# resultat/preuve/lecon-candidate.
_V2_DISCRIMINANT_FIELDS: tuple[str, ...] = (
    "expected_result", "observed_result", "evidence", "lesson_candidate",
)
_DATE_RE = re.compile(r"^(\d{4})-(\d{2})-(\d{2})")

_ACCENT_FOLD = str.maketrans("ÉÈÊËÀÂÎÏÔÛÙÇéèêëàâîïôûùç", "EEEEAAIIOUUCeeeeaaiiouuc")


def _normalize_status(raw: Optional[str]) -> Optional[str]:
    """Projette une valeur prose sur le vocabulaire FERME de `status`.
    Retourne la valeur canonique, ou None si rien ne matche (=> UNKNOWN)."""
    if not raw:
        return None
    folded = raw.translate(_ACCENT_FOLD).upper().replace(" ", "_")
    for value in V2_STATUS_VALUES:
        if value in folded:
            return value
    return None


def decision_template() -> str:
    """Gabarit vide commente du format `observer.decision.v2` RATIFIE — a
    coller tel quel dans une entree de decision-log (adoption manuelle). Les
    commentaires <!-- --> expliquent chaque champ, a supprimer au remplissage."""
    return "\n".join([
        "## AAAA-MM-JJ — <titre court de la decision>",
        "",
        "**Décision** :          <!-- decision -- ce qui est decide, verbatim -->",
        "**Résultat attendu** :  <!-- expected_result -- OBLIGATOIRE A LA DECISION : effet observable, falsifiable -->",
        "**Preuve** :            <!-- evidence -- chemin / verdict signe / mesure qui attestera le resultat -->",
        "**Résultat observé** :  <!-- observed_result -- rempli PLUS TARD, quand le reel a parle -->",
        "**Statut** :            <!-- status -- EN_ATTENTE_RESULTAT | RESULTAT_CONFORME | RESULTAT_CONTRAIRE | ABANDONNEE -->",
        "**Leçon candidate** :   <!-- lesson_candidate -- enonce propose si RESULTAT_CONTRAIRE ; 'aucune' si assume -->",
    ])


def _decision_v2(
    decision_id: str,
    source_family: str,
    statut: str,
    source: dict[str, Any],
    confiance: str,
    decision: str,
    expected_result: str,
    evidence: str,
    observed_result: str,
    status: str,
    lesson_candidate: str,
    date_decision: str,
) -> dict[str, Any]:
    """Une decision normalisee au schema v2 RATIFIE. Les 6 champs canoniques
    sont TOUJOURS presents ; l'enveloppe (decision_id, source_family, statut,
    source, confiance) est identique a v1 pour que les vues agregees restent
    valables — `statut` (enveloppe : PRISE/DIFFEREE/EN_ATTENTE) est distinct
    du champ ratifie `status` (boucle resultat). `date_decision` (AAAA-MM-JJ
    ou UNKNOWN) sert au compteur > 7 jours."""
    return {
        "schema": SCHEMA_V2,
        "decision_id": decision_id,
        "source_family": source_family,
        "statut": statut,
        "date_decision": date_decision,
        "source": source,
        "confiance": confiance,
        "decision": decision,
        "expected_result": expected_result,
        "evidence": evidence,
        "observed_result": observed_result,
        "status": status,
        "lesson_candidate": lesson_candidate,
    }


def _resultat_of(decision: dict[str, Any]) -> str:
    """Le champ « resultat » comparable inter-schemas : `resultat` en v1,
    `observed_result` en v2 (le resultat ATTENDU n'est pas un resultat)."""
    if decision.get("schema") == SCHEMA_V2:
        return decision.get("observed_result", UNKNOWN)
    return decision.get("resultat", UNKNOWN)


# --------------------------------------------------------------------------- #
# 1. decision-log.md — registre prose canonique
# --------------------------------------------------------------------------- #


def _harvest_decision_log(ctx: Any, non_normalisables: list[dict[str, Any]]) -> list[dict[str, Any]]:
    path = ctx.repo_root / "studio_brain" / "decisions" / "decision-log.md"
    text = ctx.read_text(path)
    if text is None:
        non_normalisables.append({
            "source_family": "decision_log",
            "raison": f"{ctx.rel(path)} illisible ou absent — 0 decision moissonnee",
        })
        return []

    sections = _parse_headed_sections(text, _DECISION_HEADER_RE)
    bodies = _section_bodies(text, _DECISION_HEADER_RE)
    out: list[dict[str, Any]] = []
    for section in sections:
        body = bodies.get(section["ligne"], [])

        # --- detection v2 : l'entree porte-t-elle les marqueurs du format
        # RATIFIE (« Résultat attendu : », « Résultat observé : », « Preuve : »,
        # « Statut : », « Leçon candidate : » — anciens marqueurs conserves en
        # alias) ? Si oui -> schema v2 ; sinon -> v1 legacy, inchange.
        v2_values = {
            field: _extract_bold_field_any(body, _V2_FIELD_LABELS[field])
            for field in _V2_DISCRIMINANT_FIELDS
        }
        if any(v2_values[f] is not None for f in _V2_DISCRIMINANT_FIELDS):
            decision_v2 = _extract_bold_field_any(body, _V2_FIELD_LABELS["decision"])
            # `status` n'est pas discriminant : extrait ici, une fois l'entree
            # reconnue v2 par la boucle resultat/preuve/lecon-candidate.
            status_raw = _extract_bold_field_any(body, _V2_FIELD_LABELS["status"])
            observed = (_short(v2_values["observed_result"])
                        if v2_values["observed_result"] else UNKNOWN)
            # `status` : vocabulaire ferme. Declare en prose => projete sur le
            # vocabulaire (hors vocabulaire => UNKNOWN, jamais reinterprete).
            # Non declare : EN_ATTENTE_RESULTAT est DERIVABLE mecaniquement
            # quand observed_result est vide ; sinon UNKNOWN (on ne devine pas
            # conforme/contraire a la place de l'humain).
            declared = _normalize_status(status_raw)
            if declared is not None:
                status = declared
            elif status_raw is not None:
                status = UNKNOWN  # declare mais hors vocabulaire ferme
            elif observed == UNKNOWN:
                status = "EN_ATTENTE_RESULTAT"
            else:
                status = UNKNOWN
            date_m = _DATE_RE.match(section["id"])
            out.append(_decision_v2(
                decision_id=f"declog:{section['id']}:l{section['ligne']}",
                source_family="decision_log",
                statut="PRISE",
                source={
                    "path": ctx.rel(path),
                    "localisateur": f"ligne {section['ligne']} — section "
                                    f"'## {section['id']} — {_short(section['titre'], 80)}'",
                },
                confiance="SELF_DECLARED",  # registre prose — parsing best-effort
                decision=_short(decision_v2) if decision_v2 else _short(section["titre"]),
                expected_result=(_short(v2_values["expected_result"])
                                 if v2_values["expected_result"] else UNKNOWN),
                evidence=(_short(v2_values["evidence"])
                          if v2_values["evidence"] else UNKNOWN),
                observed_result=observed,
                status=status,
                lesson_candidate=(_short(v2_values["lesson_candidate"])
                                  if v2_values["lesson_candidate"] else UNKNOWN),
                date_decision=date_m.group(0) if date_m else UNKNOWN,
            ))
            continue

        # --- v1 legacy (entrees existantes : historique intact, non reecrit).
        # 'Décision' couvre aussi '**Décisions ...**' (entree D1-D6) et
        # '**Décision (verbatim Pierre)**'.
        action = _extract_bold_field(body, "Décision")
        pourquoi = _extract_bold_field(body, "Contexte")
        out.append(_decision(
            decision_id=f"declog:{section['id']}:l{section['ligne']}",
            source_family="decision_log",
            statut="PRISE",
            objectif=_short(section["titre"]),
            pourquoi=_short(pourquoi) if pourquoi else UNKNOWN,
            source={
                "path": ctx.rel(path),
                "localisateur": f"ligne {section['ligne']} — section "
                                f"'## {section['id']} — {_short(section['titre'], 80)}'",
            },
            confiance="SELF_DECLARED",  # registre prose — parsing best-effort
            action=_short(action) if action else UNKNOWN,
            # Le format du registre (date · decision · contexte · alternatives ·
            # criteres de revision) ne porte AUCUN champ resultat ni lecon :
            # UNKNOWN honnete, pas une omission de parsing.
            resultat=UNKNOWN,
            lecon=UNKNOWN,
        ))
    return out


# --------------------------------------------------------------------------- #
# 2. Verdicts signes des runs (events `verdict.signed`)
# --------------------------------------------------------------------------- #


def _harvest_verdicts(
    ctx: Any,
    result: dict[str, Any],
    events: list[dict[str, Any]],
    lesson_lines: list[tuple[int, dict[str, Any]]],
    non_normalisables: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    runs_by_id = {r.get("run_id"): r for r in result.get("runs", [])}
    verdict_events = [e for e in events if e.get("kind") == "verdict.signed"]
    seen_run_ids: set[str] = set()
    out: list[dict[str, Any]] = []

    for ev in verdict_events:
        run_id = ev.get("run_id")
        payload = ev.get("payload") or {}
        src = ev.get("source") or {}
        src_path = src.get("path")
        if not src_path:
            non_normalisables.append({
                "source_family": "verdict_signe",
                "id": run_id,
                "raison": "event verdict.signed sans source.path — decision sans "
                          "provenance, non emise",
            })
            continue
        seen_run_ids.add(run_id)
        run = runs_by_id.get(run_id) or {}

        decision_value = payload.get("decision")
        hmac = payload.get("hmac")
        flags = payload.get("humangate_flags") or []
        software = payload.get("software_verdict")
        provenance_ok = payload.get("provenance_ok")

        pourquoi_parts = []
        if software is not None:
            pourquoi_parts.append(f"software_verdict={software}")
        if provenance_ok is not None:
            pourquoi_parts.append(f"provenance_ok={provenance_ok}")
        if flags:
            pourquoi_parts.append("humangate_flags: " + " | ".join(flags))

        # Croisement mecanique : les lecons dont supporting_runs cite ce run.
        lesson_ids = sorted({
            obj["lesson_id"] for _, obj in lesson_lines
            if obj.get("lesson_id") and run_id in (obj.get("supporting_runs") or [])
        })

        out.append(_decision(
            decision_id=f"verdict:{run_id}",
            source_family="verdict_signe",
            statut="PRISE",
            objectif=f"decision de gate pour le run {run_id}",
            pourquoi=_short(" ; ".join(pourquoi_parts)) if pourquoi_parts else UNKNOWN,
            source={
                "path": src_path,
                "localisateur": "champ 'decision' du verdict signe",
            },
            confiance="SIGNED" if hmac else "SELF_DECLARED",
            action=str(decision_value) if decision_value else UNKNOWN,
            resultat=(f"run_status={run.get('run_status')}"
                      if run.get("run_status") else UNKNOWN),
            lecon=("; ".join(lesson_ids) if lesson_ids else UNKNOWN),
        ))

    # Un run qui porte une decision mais aucun event verdict.signed = decision
    # sans source verifiable : comptee, jamais emise.
    for run_id, run in sorted(runs_by_id.items(), key=lambda kv: str(kv[0])):
        if run.get("decision") and run_id not in seen_run_ids:
            non_normalisables.append({
                "source_family": "verdict_signe",
                "id": run_id,
                "raison": f"run porte decision={run['decision']} mais aucun event "
                          "verdict.signed observe — pas de provenance, non emise",
            })
    return out


# --------------------------------------------------------------------------- #
# 3. Ratifications de lecons (candidate -> validated dans lessons.jsonl)
# --------------------------------------------------------------------------- #


def _harvest_lessons(
    ctx: Any,
    lesson_lines: list[tuple[int, dict[str, Any]]],
    non_normalisables: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    lessons_path = ctx.repo_root / "lab" / "reports" / "lessons.jsonl"
    by_id: dict[str, list[tuple[int, dict[str, Any]]]] = {}
    for lineno, obj in lesson_lines:
        lid = obj.get("lesson_id")
        if lid:
            by_id.setdefault(lid, []).append((lineno, obj))

    out: list[dict[str, Any]] = []
    for lid, entries in sorted(by_id.items()):
        validated = [(ln, o) for ln, o in entries if o.get("status") == "validated"]
        if not validated:
            # candidate seule = ratification pas encore prononcee, pas une decision.
            non_normalisables.append({
                "source_family": "lesson",
                "id": lid,
                "raison": "lecon candidate sans ligne validated — ratification non "
                          "prononcee, pas une decision prise",
            })
            continue
        lineno, obj = max(validated, key=lambda pair: pair[1].get("ts") or 0.0)
        caused = obj.get("caused_by") or {}
        pourquoi = (caused.get("experience") or "").strip() \
            or (caused.get("failure_id") or "").strip()
        supporting = obj.get("supporting_runs") or []
        out.append(_decision(
            decision_id=f"lesson:{lid}",
            source_family="lesson",
            statut="PRISE",
            objectif=f"ratifier la lecon {lid}",
            pourquoi=_short(pourquoi) if pourquoi else UNKNOWN,
            source={
                "path": ctx.rel(lessons_path),
                "localisateur": f"ligne {lineno} (derniere ligne status=validated)",
            },
            confiance="MECHANICAL",  # transition d'etat dans un jsonl machine
            action="candidate -> validated",
            resultat=f"validated (evidence_count={obj.get('evidence_count')}, "
                     f"supporting_runs={supporting})",
            lecon=_short(str(obj.get("statement") or "")) or UNKNOWN,
        ))
    return out


# --------------------------------------------------------------------------- #
# 4. DEFERRED.md — decisions differees (DR-)
# --------------------------------------------------------------------------- #

_REPONSE_PIERRE_RE = re.compile(r"r[ée]ponse\s+pierre", re.IGNORECASE)


def _harvest_deferred(ctx: Any, non_normalisables: list[dict[str, Any]]) -> list[dict[str, Any]]:
    path = ctx.repo_root / "studio_brain" / "decisions" / "DEFERRED.md"
    text = ctx.read_text(path)
    if text is None:
        non_normalisables.append({
            "source_family": "deferred",
            "raison": f"{ctx.rel(path)} illisible ou absent — 0 decision moissonnee",
        })
        return []

    sections = _parse_headed_sections(text, _DEFERRED_HEADER_RE)
    bodies = _section_bodies(text, _DEFERRED_HEADER_RE)
    out: list[dict[str, Any]] = []
    for section in sections:
        body = bodies.get(section["ligne"], [])
        raison = _extract_bold_field(body, "Raison du report")
        question = _extract_bold_field(body, "Question exacte")

        # Resultat best-effort : une ligne 'Réponse Pierre' dans le corps
        # (arbitrage intermediaire consigne en append). Sinon UNKNOWN : la
        # decision est differee, son resultat n'existe pas encore.
        resultat: Optional[str] = None
        for line in body:
            if _REPONSE_PIERRE_RE.search(line):
                resultat = line.strip().lstrip("- ").strip()
                break

        out.append(_decision(
            decision_id=f"deferred:{section['id']}",
            source_family="deferred",
            statut="DIFFEREE",
            objectif=_short(f"{section['id']} — {section['titre']}"),
            pourquoi=_short(raison) if raison else UNKNOWN,
            source={
                "path": ctx.rel(path),
                "localisateur": f"ligne {section['ligne']} — section "
                                f"'## {section['id']} — {_short(section['titre'], 80)}'",
            },
            confiance="SELF_DECLARED",
            action=(_short(f"question posee a l'echeance : {question}")
                    if question else UNKNOWN),
            resultat=_short(resultat) if resultat else UNKNOWN,
            lecon=UNKNOWN,
        ))
    return out


# --------------------------------------------------------------------------- #
# 5. Gates du registre planning (decision_attendue = decisions FUTURES)
# --------------------------------------------------------------------------- #


def _harvest_planning_gates(ctx: Any, non_normalisables: list[dict[str, Any]]) -> list[dict[str, Any]]:
    path = ctx.repo_root / "studio_brain" / "planning" / "planning.yaml"
    if not ctx.exists(path):
        non_normalisables.append({
            "source_family": "planning_gate",
            "raison": f"{ctx.rel(path)} absent — 0 gate moissonnee",
        })
        return []
    text = ctx.read_text(path)
    if text is None:
        non_normalisables.append({
            "source_family": "planning_gate",
            "raison": f"{ctx.rel(path)} illisible — 0 gate moissonnee",
        })
        return []

    try:
        import yaml
        data = yaml.safe_load(text)
    except ImportError:
        non_normalisables.append({
            "source_family": "planning_gate",
            "raison": "PyYAML indisponible dans cet interpreteur — registre non parse",
        })
        return []
    except Exception as exc:  # yaml.YAMLError — import local, pas de nom au module
        non_normalisables.append({
            "source_family": "planning_gate",
            "raison": f"planning.yaml n'est pas un YAML valide : {exc}",
        })
        return []

    taches = data if isinstance(data, list) else \
        (data.get("taches") or data.get("tasks") or []) if isinstance(data, dict) else []
    if not isinstance(taches, list):
        non_normalisables.append({
            "source_family": "planning_gate",
            "raison": "format planning.yaml non reconnu (liste de taches attendue)",
        })
        return []

    out: list[dict[str, Any]] = []
    for item in taches:
        if not isinstance(item, dict):
            continue
        task_id = item.get("id") or UNKNOWN
        attendue = str(item.get("decision_attendue") or "").strip()
        if not attendue:
            non_normalisables.append({
                "source_family": "planning_gate",
                "id": task_id,
                "raison": "tache sans champ decision_attendue — aucune decision a "
                          "normaliser",
            })
            continue
        if attendue.lower().startswith("aucune"):
            non_normalisables.append({
                "source_family": "planning_gate",
                "id": task_id,
                "raison": f"decision_attendue declare 'aucune' — pas une decision "
                          f"future ({_short(attendue, 120)})",
            })
            continue
        out.append(_decision(
            decision_id=f"planning:{task_id}",
            source_family="planning_gate",
            statut="EN_ATTENTE",  # decision FUTURE : personne ne l'a encore prise
            objectif=_short(f"gate de la tache {task_id} : {attendue}"),
            pourquoi=_short(str(item.get("raison") or "")) or UNKNOWN,
            source={
                "path": ctx.rel(path),
                "localisateur": f"tache id={task_id}, champ decision_attendue",
            },
            confiance="SELF_DECLARED",
            action=UNKNOWN,   # la decision n'est pas prise — aucune action a rapporter
            resultat=UNKNOWN,
            lecon=UNKNOWN,
        ))
    return out


# --------------------------------------------------------------------------- #
# Interface publique
# --------------------------------------------------------------------------- #

_FAMILY_ORDER = ("decision_log", "verdict_signe", "lesson", "deferred", "planning_gate")


def harvest_decisions(
    ctx: Any,
    result: dict[str, Any],
    events: list[dict[str, Any]],
    non_normalisables: Optional[list[dict[str, Any]]] = None,
) -> list[dict[str, Any]]:
    """Moissonne toutes les decisions existantes, normalisees au schema
    `observer.decision.v1`. Ordre deterministe (famille puis decision_id).

    `non_normalisables` : liste optionnelle que l'appelant peut fournir pour
    recuperer les decisions ecartees faute de provenance (avec raison).
    """
    if non_normalisables is None:
        non_normalisables = []

    lessons_path = ctx.repo_root / "lab" / "reports" / "lessons.jsonl"
    lesson_lines = list(ctx.read_jsonl(lessons_path))

    decisions: list[dict[str, Any]] = []
    decisions += _harvest_decision_log(ctx, non_normalisables)
    decisions += _harvest_verdicts(ctx, result, events, lesson_lines, non_normalisables)
    decisions += _harvest_lessons(ctx, lesson_lines, non_normalisables)
    decisions += _harvest_deferred(ctx, non_normalisables)
    decisions += _harvest_planning_gates(ctx, non_normalisables)

    rank = {f: i for i, f in enumerate(_FAMILY_ORDER)}
    decisions.sort(key=lambda d: (rank.get(d["source_family"], 99), d["decision_id"]))
    return decisions


def _write_registry(ctx: Any, project: str,
                    decisions: list[dict[str, Any]]) -> tuple[Optional[str], Optional[str]]:
    """La SEULE ecriture de ce module : le registre normalise, VUE derivee
    reecrite en entier a chaque run. Garde dure identique a system_planning :
    refuse d'ecrire hors de EVIDENCE/reports/observer/ — jamais studio_brain/,
    jamais scripts/forge/, jamais un store canonique."""
    out_path = (ctx.repo_root / "EVIDENCE" / "reports" / "observer" / project).resolve()
    guard_root = (ctx.repo_root / "EVIDENCE" / "reports" / "observer").resolve()
    try:
        out_path.relative_to(guard_root)
    except ValueError:
        why = (f"chemin de sortie {out_path} hors de EVIDENCE/reports/observer/ — "
               "ecriture refusee")
        LOG.error(why)
        return None, why

    out_path.mkdir(parents=True, exist_ok=True)
    file_path = out_path / "decisions_normalized.jsonl"
    lines = [json.dumps(d, ensure_ascii=False, sort_keys=False) for d in decisions]
    file_path.write_text("\n".join(lines) + ("\n" if lines else ""),
                         encoding="utf-8", newline="\n")
    return str(file_path), None


def _write_format_ratifie(
    ctx: Any, project: str, total: int, sans_resultat_n: int,
) -> tuple[Optional[str], Optional[str]]:
    """Ecrit le document `DECISION_FORMAT_V2_RATIFIE.md` sous
    EVIDENCE/reports/observer/<projet>/ — meme garde dure que _write_registry.
    Statut : RATIFIE Pierre 2026-08-02, adoption MANUELLE (gabarit pret a
    coller dans le decision-log). Remplace DECISION_FORMAT_PROPOSED.md
    (supprime s'il existe, dans le meme dossier de sortie uniquement)."""
    from datetime import date as _date

    out_path = (ctx.repo_root / "EVIDENCE" / "reports" / "observer" / project).resolve()
    guard_root = (ctx.repo_root / "EVIDENCE" / "reports" / "observer").resolve()
    try:
        out_path.relative_to(guard_root)
    except ValueError:
        why = (f"chemin de sortie {out_path} hors de EVIDENCE/reports/observer/ — "
               "ecriture refusee")
        LOG.error(why)
        return None, why

    today = _date.today().isoformat()
    doc = "\n".join([
        "# DECISION_FORMAT_V2_RATIFIE — format `observer.decision.v2`",
        "",
        f"> Genere le {today} par `scripts/observer/evidence.py` (Evidence Engine).",
        "> Statut : **RATIFIÉ Pierre 2026-08-02** — adoption MANUELLE : le gabarit",
        "> ci-dessous est pret a coller dans le decision-log ; aucun skill ni store",
        "> canonique n'est modifie par ce module.",
        "",
        "## Invariant ratifie (verbatim)",
        "",
        "> toute nouvelle décision porte `decision / expected_result / evidence /",
        "> observed_result / status / lesson_candidate`. « Le passé reste une mesure",
        "> historique du manque. Le futur doit produire la boucle. » Aucune",
        "> reconstruction des 39/49.",
        "",
        "## Constat (moisson au jour de generation)",
        "",
        f"{total} decision(s) moissonnee(s) et normalisee(s), dont "
        f"{sans_resultat_n} SANS trace de resultat. Le format v1 legacy du "
        "decision-log (date · decision · contexte · alternatives · criteres de "
        "revision) ne porte aucun champ resultat : une decision sans resultat "
        "est invisible par construction. Le passe reste cette mesure historique "
        "du manque — le futur doit produire la boucle.",
        "",
        "## Le format ratifie",
        "",
        "```",
        "DECISION { decision / expected_result / evidence /",
        "           observed_result / status / lesson_candidate }",
        "```",
        "",
        "| Champ | Rempli quand | Role |",
        "|---|---|---|",
        "| `decision` | a la decision | ce qui est decide, verbatim |",
        "| `expected_result` | **a la decision — OBLIGATOIRE** | effet observable, falsifiable |",
        "| `evidence` | avec le resultat observe | chemin / verdict signe / mesure |",
        "| `observed_result` | **plus tard** | ce qui s'est reellement passe |",
        "| `status` | vit avec la decision | EN_ATTENTE_RESULTAT \\| RESULTAT_CONFORME \\| RESULTAT_CONTRAIRE \\| ABANDONNEE |",
        "| `lesson_candidate` | si RESULTAT_CONTRAIRE | enonce de lecon propose — creation humaine |",
        "",
        "## Les regles",
        "",
        "* `expected_result` est obligatoire **À la decision** — une decision qui",
        "  ne dit pas ce qu'elle attend n'est pas falsifiable.",
        "* `status` est un vocabulaire FERME (4 valeurs). Tant que la decision est",
        "  EN_ATTENTE_RESULTAT, elle apparait dans « sans resultat » de la vue",
        f"  s10_evidence, et passe {V2_STALE_DAYS} jours dans le compteur",
        "  « v2 EN_ATTENTE_RESULTAT » : une decision sans resultat doit devenir",
        "  VISIBLE, pas disparaitre.",
        "* `status: RESULTAT_CONTRAIRE` fait sortir la decision dans",
        "  `lesson_candidates_suggerees` de la vue — SIGNALEMENT seul, la creation",
        "  de la lecon reste humaine.",
        "* Les decisions historiques restent v1 legacy telles quelles — aucune",
        "  reconstruction ; le format s'applique aux NOUVELLES decisions uniquement.",
        "* Les anciens marqueurs prose du brouillon v2 (« Résultat attendu »,",
        "  « Résultat observé », « Preuve », « Leçon ») restent des alias de",
        "  LECTURE pour la detection — les noms canoniques sont les 6 ci-dessus.",
        "",
        "## Gabarit (retourne par `evidence.decision_template()`) — pret a coller",
        "",
        "```markdown",
        decision_template(),
        "```",
        "",
        "## Adoption",
        "",
        "Adoption MANUELLE : coller le gabarit dans",
        "`studio_brain/decisions/decision-log.md` a chaque nouvelle decision.",
        "La moisson d'Evidence detecte automatiquement toute entree portant les",
        "marqueurs (« Résultat attendu : », « Résultat observé : », « Preuve : »,",
        "« Statut : », « Leçon candidate : ») et la normalise en",
        "`observer.decision.v2` — l'adoption est mesurable sans autre changement",
        "de code.",
        "",
    ])

    out_path.mkdir(parents=True, exist_ok=True)
    file_path = out_path / "DECISION_FORMAT_V2_RATIFIE.md"
    file_path.write_text(doc, encoding="utf-8", newline="\n")

    # L'ancien document propose est REMPLACE par le ratifie : supprime pour ne
    # pas laisser deux statuts contradictoires dans la meme vue derivee.
    stale = out_path / "DECISION_FORMAT_PROPOSED.md"
    if stale.exists():
        try:
            stale.unlink()
        except OSError as exc:  # non fatal : le ratifie est ecrit, on le signale
            LOG.warning("suppression de %s impossible : %s", stale, exc)
    return str(file_path), None


def view_evidence(ctx: Any, result: dict[str, Any], events: list[dict[str, Any]]) -> dict[str, Any]:
    """Vue s10_evidence : la moisson comptee par source et par confiance,
    l'ecart interessant (decisions sans trace de resultat), et l'ecriture du
    registre normalise. Retourne {"s10_evidence": ...}."""
    project = result.get("project") or "unknown_project"
    non_normalisables: list[dict[str, Any]] = []
    decisions = harvest_decisions(ctx, result, events, non_normalisables)

    par_source = Counter(d["source_family"] for d in decisions)
    par_confiance = Counter(d["confiance"] for d in decisions)
    par_statut = Counter(d["statut"] for d in decisions)

    v1_decisions = [d for d in decisions if d.get("schema") != SCHEMA_V2]
    v2_decisions = [d for d in decisions if d.get("schema") == SCHEMA_V2]

    sans_resultat = [d["decision_id"] for d in decisions
                     if _resultat_of(d) == UNKNOWN]
    unknown_par_champ = {
        champ: sum(1 for d in v1_decisions if d[champ] == UNKNOWN)
        for champ in CANONICAL_FIELDS if champ != "source"  # source jamais UNKNOWN par construction
    }
    unknown_par_champ_v2 = {
        champ: sum(1 for d in v2_decisions if d[champ] == UNKNOWN)
        for champ in CANONICAL_FIELDS_V2
    }

    # Compteur « v2 EN_ATTENTE_RESULTAT depuis > V2_STALE_DAYS jours » :
    # la mecanique existe et rend 0 honnetement tant qu'aucune decision v2
    # n'existe — elle n'est jamais omise.
    from datetime import date as _date, timedelta as _timedelta
    today = _date.today()
    v2_stale: list[str] = []
    for d in v2_decisions:
        if d["status"] != "EN_ATTENTE_RESULTAT":
            continue
        date_m = _DATE_RE.match(str(d.get("date_decision") or ""))
        if not date_m:
            continue  # date non derivable — pas d'age calculable, pas d'invention
        y, m, dd = (int(g) for g in date_m.groups())
        try:
            decided = _date(y, m, dd)
        except ValueError:
            continue
        if (today - decided) > _timedelta(days=V2_STALE_DAYS):
            v2_stale.append(d["decision_id"])

    # Boucle vers lesson : status RESULTAT_CONTRAIRE => la decision sort en
    # candidate de lecon SUGGEREE. Signalement seul — la creation de la lecon
    # (lessons.jsonl) reste humaine, jamais ecrite d'ici.
    lesson_candidates_suggerees = [
        {
            "decision_id": d["decision_id"],
            "decision": d["decision"],
            "expected_result": d["expected_result"],
            "observed_result": d["observed_result"],
            "evidence": d["evidence"],
            "lesson_candidate": d["lesson_candidate"],
        }
        for d in v2_decisions if d["status"] == "RESULTAT_CONTRAIRE"
    ]

    registry_path, write_why = _write_registry(ctx, project, decisions)
    format_doc_path, format_doc_why = _write_format_ratifie(
        ctx, project, total=len(decisions), sans_resultat_n=len(sans_resultat))

    fondations = [d["decision_id"] for d in decisions
                  if d["statut"] == "PRISE" and _resultat_of(d) != UNKNOWN]
    resume = (
        f"{len(decisions)} decision(s) normalisee(s) "
        f"({', '.join(f'{k}={par_source[k]}' for k in _FAMILY_ORDER if par_source[k])}) ; "
        f"format : v1_legacy={len(v1_decisions)}, v2={len(v2_decisions)} ; "
        f"{len(sans_resultat)} sans trace de resultat ({UNKNOWN}) ; "
        f"{len(v2_stale)} v2 EN_ATTENTE_RESULTAT depuis > {V2_STALE_DAYS} j ; "
        f"{len(lesson_candidates_suggerees)} lesson candidate(s) suggeree(s) "
        f"(RESULTAT_CONTRAIRE) ; "
        f"{len(non_normalisables)} non normalisable(s) ; "
        f"confiance : {', '.join(f'{k}={v}' for k, v in sorted(par_confiance.items()))}"
    )

    view: dict[str, Any] = {
        "schema": SCHEMA,
        "schema_v2": SCHEMA_V2,
        "format_ratifie": True,  # format v2 RATIFIE Pierre 2026-08-02
        "total": len(decisions),
        "par_source": dict(par_source),
        "par_confiance": dict(par_confiance),
        "par_statut": dict(par_statut),
        "par_format": {
            "v1_legacy": len(v1_decisions),
            "v2": len(v2_decisions),
            "note": "split legacy/v2 — les entrees historiques restent v1 telles "
                    "quelles ; v2 detecte par les marqueurs prose du format ratifie",
        },
        "sans_resultat": {
            "n": len(sans_resultat),
            "ids": sans_resultat,
            "note": "l'ecart interessant : decision prise ou differee dont aucune "
                    "trace de resultat n'est derivable des sources lisibles "
                    "(v1 : champ resultat ; v2 : champ observed_result)",
        },
        "v2_sans_resultat_observe": {
            "n": len(v2_stale),
            "ids": v2_stale,
            "seuil_jours": V2_STALE_DAYS,
            "note": f"decisions v2 en status EN_ATTENTE_RESULTAT depuis plus de "
                    f"{V2_STALE_DAYS} jours (date de la decision) — 0 est un zero "
                    "honnete tant qu'aucune decision v2 n'existe",
        },
        "lesson_candidates_suggerees": {
            "n": len(lesson_candidates_suggerees),
            "items": lesson_candidates_suggerees,
            "note": "decisions v2 en status RESULTAT_CONTRAIRE (observed_result "
                    "contredit expected_result) — SIGNALEMENT seul : la creation "
                    "de la lecon reste humaine",
        },
        "unknown_par_champ": unknown_par_champ,
        "unknown_par_champ_v2": unknown_par_champ_v2,
        "non_normalisables": non_normalisables,
        "question": "Quelles decisions fondent le systeme, et lesquelles sont sans "
                    "trace de resultat ?",
        "reponse": {
            "fondent_avec_resultat_trace": fondations,
            "sans_trace_de_resultat": sans_resultat,
        },
        "resume": resume,
        "registre": {
            "path": registry_path if registry_path else UNKNOWN,
            "lignes": len(decisions),
            "note": "vue derivee reecrite en entier a chaque run — pas un store",
        },
        "format_document": {
            "chemin": format_doc_path if format_doc_path else UNKNOWN,
            "statut": "RATIFIE_PIERRE_2026-08-02",
            "note": "DECISION_FORMAT_V2_RATIFIE.md — adoption MANUELLE : gabarit "
                    "pret a coller dans le decision-log ; aucun skill modifie "
                    "par ce module",
        },
    }
    if registry_path is None:
        view["registre"]["why"] = write_why
    if format_doc_path is None:
        view["format_document"]["why"] = format_doc_why
    return {"s10_evidence": view}


# --------------------------------------------------------------------------- #
# Preuve d'execution — reel breakout_v2 (meme patron que command.py)
# --------------------------------------------------------------------------- #

if __name__ == "__main__":
    from observer.sources import ObserverContext, default_repo_root, default_transcripts_root  # noqa: E402

    logging.basicConfig(level=logging.WARNING)

    repo_root = default_repo_root()
    transcripts_root = default_transcripts_root(repo_root)
    ctx = ObserverContext.build(repo_root, "breakout_v2", transcripts_root)

    report_dir = repo_root / "EVIDENCE" / "reports" / "observer" / "breakout_v2"
    with (report_dir / "observer_run.json").open("r", encoding="utf-8-sig") as fh:
        result = json.load(fh)

    events: list[dict[str, Any]] = []
    with (report_dir / "events.jsonl").open("r", encoding="utf-8-sig") as fh:
        for line in fh:
            line = line.strip()
            if line:
                events.append(json.loads(line))

    view = view_evidence(ctx, result, events)["s10_evidence"]

    print("--- total moissonne par source ---")
    for family in _FAMILY_ORDER:
        print(f"  {family:14s} : {view['par_source'].get(family, 0)}")
    print(f"  TOTAL          : {view['total']}")

    print(f"\n--- registre ecrit : {view['registre']['path']} "
          f"({view['registre']['lignes']} lignes) ---")

    # Relecture du registre reellement ecrit (preuve d'execution, pas d'existence)
    reg_path = Path(view["registre"]["path"])
    written = [json.loads(ln) for ln in
               reg_path.read_text(encoding="utf-8").splitlines() if ln.strip()]
    prose = next(d for d in written if d["source_family"] == "decision_log")
    signee = next(d for d in written if d["source_family"] == "verdict_signe")

    print("\n--- decision normalisee 1/2 (prose, decision_log) ---")
    print(json.dumps(prose, indent=2, ensure_ascii=False))
    print("\n--- decision normalisee 2/2 (signee, verdict_signe) ---")
    print(json.dumps(signee, indent=2, ensure_ascii=False))

    print("\n--- UNKNOWN par champ ---")
    print(json.dumps(view["unknown_par_champ"], indent=2, ensure_ascii=False))

    print(f"\n--- sans resultat : {view['sans_resultat']['n']} ---")
    print(f"--- non normalisables : {len(view['non_normalisables'])} ---")
    for item in view["non_normalisables"]:
        print(f"    [{item['source_family']}] {item.get('id', '-')}: {item['raison']}")

    print(f"\n--- format v2 ratifie ---")
    print(f"format_ratifie          : {view['format_ratifie']}")
    print(f"v1_legacy / v2          : {view['par_format']['v1_legacy']} / "
          f"{view['par_format']['v2']}")
    print(f"v2 EN_ATTENTE > {V2_STALE_DAYS} j    : {view['v2_sans_resultat_observe']['n']}")
    print(f"lesson candidates sugg. : {view['lesson_candidates_suggerees']['n']}")
    print(f"document                : {view['format_document']['chemin']} "
          f"[{view['format_document']['statut']}]")

    print("\n--- gabarit decision_template() (6 champs ratifies) ---")
    print(decision_template())

    print(f"\n--- resume ---\n{view['resume']}")
