"""forge.learning_memory — Mémoire d'apprentissage Forge (FVL Phase 0.5, étape 3).

Source de vérité, non re-débattue ici :
  - docs/forge/FORGE_EVOLUTION_DOCTRINE_V0.md §2.1 (failure_event), §2.2 (lesson),
    §2.3 (périmètre minimal + politique d'injection + limite du pré-mortem), §0.1
    (les quatre couches).
  - docs/fvl/FVL_PHASE_0_5_CHARTER.md §4 (séquence, étape 3).

Ce module construit le MÉCANISME minimal, pas le moteur (§2.3) :

  A. `failure_event` — objet append-only, clé par `failure_id`, replié à la
     lecture. C'est le PREMIER objet Forge dont la durée de vie dépasse un run :
     erreur détectée, puis hypothèses de cause, puis expérience, puis verdict,
     puis leçon — des moments séparés par plusieurs runs. Écrire une NOUVELLE
     ligne à chaque évolution (jamais écraser une ligne passée) est le point de
     fond, pas un détail de format : la trace d'une attribution RÉVISÉE est
     exactement la donnée qui apprend à mieux attribuer.

  B. `lesson` — objet DISTINCT, autre temporalité (« une erreur appartient à un
     run, une leçon appartient à l'histoire de la Forge »). Statut révisable
     par PREUVE uniquement (jamais par avis), historique jamais perdu (même
     patron append-only + repli, pour la même raison qu'en A).

  C. `premortem_lessons` — le SEUL changement de lecture exigé par le minimum :
     récupérer -> filtrer (statut + génération, STRUCTUREL jamais sémantique)
     -> afficher. Déterministe, non-LLM, aucune reformulation, aucune
     priorisation au-delà d'un tri stable par identité.

HORS PÉRIMÈTRE (refusé explicitement par la doctrine et par la mission) : aucun
scoring, aucune probabilité, aucune sélection automatique, aucun MCTS, aucun
générateur d'hypothèses, aucun changement de verdict/gate/oracle. Ce module ne
prononce jamais son propre verdict — claim_verdict: NO_CLAIM_ALLOWED.

Compatibilité avec l'existant (RÈGLE DE COMPATIBILITÉ de la mission) : le
journal d'erreurs PAR DOMAINE (`forge.studio_link`) n'est ni modifié ni
réécrit. Les anciennes « leçons de méthode » (`project == "_global_"`,
`run_id == "_method_"`, aucun champ `statut`/`generation`) y restent
INTACTES ; `legacy_global_lessons()` les LIT (jamais ne les réécrit) et les
présente comme des leçons pré-schéma — ni perdues, ni promues en silence
(voir sa docstring pour la justification mécanique retenue).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
from pathlib import Path

import yaml

from forge.studio_link import DEFAULT_ERROR_JOURNAL, DOMAIN_JOURNAL_DIR, GLOBAL_SCOPE
from forge.verify_run import _harden_streams

# forge/learning_memory.py -> parents[2] == racine du repo.
REPO_ROOT = Path(__file__).resolve().parents[1]
FORGE_REPORTS = REPO_ROOT / "EVIDENCE" / "reports"

# Fichiers NOUVEAUX, distincts du journal d'erreurs par domaine existant
# (EVIDENCE/reports/error_journal/<domaine>.jsonl) — ce sont deux objets Forge
# différents (doctrine §0.1), pas une extension du journal.
DEFAULT_FAILURE_EVENTS_PATH = FORGE_REPORTS / "failure_events.jsonl"
DEFAULT_LESSONS_PATH = FORGE_REPORTS / "lessons.jsonl"

# Fichier de DONNÉES déclarant la génération courante du génome (voir sa propre
# docstring pour la source de ratification) — jamais une constante en dur ici.
DEFAULT_GENERATION_PATH = Path(__file__).resolve().parent / "genome_generation.yaml"

FAILURE_EVENT_SCHEMA = "forge.failure_event.v1"
# v2 (2026-09-01) : ajout du champ `cause`. La cause EXISTAIT déjà, structurée, chez le
# producteur (`_iter_manifest_reason_records` extrait `problem` ET `root_cause` du
# manifeste) — puis `promote_manifest_lessons` les APLATISSAIT en prose dans `statement`
# (`" — cause: ".join(...)`), détruisant le seul discriminant mécanique disponible. v2 ne
# crée donc aucune donnée : elle cesse d'en jeter une. `statement` reste identique au bit
# près (tous les lecteurs actuels sont inchangés). Mesuré au 2026-09-01 : 287 leçons sur
# 331 portent une analyse causale, 21 sont des événements d'exécution sans cause
# (« echec de la tentative 0 a s4-archi ») — c'est cette frontière que le champ rend
# opposable, sans jamais inférer depuis `statement` (règle ratifiée Pierre).
LESSON_SCHEMA = "forge.lesson.v2"

# --- Taxonomie des causes racines (doctrine §4.0, RATIFIÉE, telle quelle) -----------
# `etape_detection` (le LIEU où l'erreur a été vue) et `causes_suspectees` (le NIVEAU
# jugé responsable) sont deux champs SÉPARÉS, écrits indépendamment par l'appelant —
# ce module ne dérive JAMAIS l'un depuis l'autre. C'est la garantie mécanique contre
# l'anti-pattern nommé (précédent daté : chesscolor/s11-redteam-code, code correct,
# spec amont fausse) : automatiser « cause = étape de détection » reproduirait
# exactement l'erreur que la taxonomie existe pour empêcher.
CAUSE_CONNAISSANCE = "connaissance"
CAUSE_MEMOIRE = "memoire"
CAUSE_TRANSMISSION = "transmission"
CAUSE_SYSTEME = "systeme"
CAUSE_CONCEPTION = "conception"
CAUSE_EXECUTION = "execution"

CAUSE_LEVELS: tuple[str, ...] = (
    CAUSE_CONNAISSANCE, CAUSE_MEMOIRE, CAUSE_TRANSMISSION,
    CAUSE_SYSTEME, CAUSE_CONCEPTION, CAUSE_EXECUTION,
)

# Carte de routage (doctrine §4.4) : le niveau de mutation appelé par chaque cause.
# Purement informatif (aucune sélection automatique) — un appelant peut s'y référer,
# ce module ne l'utilise nulle part pour décider quoi que ce soit.
CAUSE_MUTATION_TARGET: dict[str, str] = {
    CAUSE_CONNAISSANCE: "WorldScan",
    CAUSE_MEMOIRE: "KB",
    CAUSE_TRANSMISSION: "contrats/livrables",
    CAUSE_SYSTEME: "WireMap/workflow",
    CAUSE_CONCEPTION: "Architect/Prisme",
    CAUSE_EXECUTION: "Worker",
}

# Statuts d'attribution d'une cause suspectée (doctrine §4.0 : « la classification
# est elle-même une hypothèse ») — plusieurs causes NON TRANCHÉES cohabitent.
CAUSE_STATUS_HYPOTHESIS = "hypothesis"
CAUSE_STATUS_CONFIRMED = "confirmed"
CAUSE_STATUS_REFUTED = "refuted"
CAUSE_ATTRIBUTION_STATUSES: tuple[str, ...] = (
    CAUSE_STATUS_HYPOTHESIS, CAUSE_STATUS_CONFIRMED, CAUSE_STATUS_REFUTED,
)

# Statut EMBARQUÉ dans failure_event.lesson (doctrine §2.1, littéral : « validee |
# rejetee »). Distinct des 5 statuts du VRAI objet Lesson (§2.2, ci-dessous) : c'est
# un pointeur court, pas un doublon de l'objet complet.
_EMBEDDED_LESSON_STATUSES = ("", "validee", "rejetee")

# --- Statuts de l'objet Lesson (doctrine §2.2, RATIFIÉS, telle quelle) --------------
LESSON_STATUS_CANDIDATE = "candidate"
LESSON_STATUS_VALIDATED = "validated"
LESSON_STATUS_WEAKENED = "weakened"
LESSON_STATUS_REJECTED = "rejected"
LESSON_STATUS_DEPRECATED = "deprecated"

LESSON_STATUSES: tuple[str, ...] = (
    LESSON_STATUS_CANDIDATE, LESSON_STATUS_VALIDATED, LESSON_STATUS_WEAKENED,
    LESSON_STATUS_REJECTED, LESSON_STATUS_DEPRECATED,
)

# Graphe de transition MÉCANIQUE (doctrine §2.2, table des transitions). Une leçon
# neuve démarre TOUJOURS `candidate` (appliqué dans record_lesson_event). Ce module
# ne calcule AUCUNE condition de franchissement (pas de comptage de N, pas de vote de
# contre-exemples — HORS PÉRIMÈTRE, « aucun scoring ») : il REFUSE seulement les
# transitions que la doctrine ne prévoit pas, la décision de franchir reste humaine ou
# agentique, citée via `caused_by`.
ALLOWED_TRANSITIONS: dict[str, frozenset[str]] = {
    LESSON_STATUS_CANDIDATE: frozenset({LESSON_STATUS_VALIDATED, LESSON_STATUS_DEPRECATED}),
    LESSON_STATUS_VALIDATED: frozenset({LESSON_STATUS_WEAKENED, LESSON_STATUS_DEPRECATED}),
    LESSON_STATUS_WEAKENED: frozenset({LESSON_STATUS_REJECTED, LESSON_STATUS_DEPRECATED}),
    LESSON_STATUS_REJECTED: frozenset({LESSON_STATUS_DEPRECATED}),
    LESSON_STATUS_DEPRECATED: frozenset(),  # terminal — doctrine ne prévoit aucune sortie
}

# Statut des leçons PRÉ-SCHÉMA (voir legacy_global_lessons) — délibérément AUCUN des
# 5 statuts officiels ci-dessus : une leçon legacy n'a jamais été jugée candidate ni
# validée par ce mécanisme, la confondre avec `candidate` la promouvrait en silence.
LEGACY_STATUS = "legacy_unversioned"

# Marqueurs de pré-mortem (ASCII strict — incident déjà rencontré dans ce dépôt :
# console Windows cp1252, cf. `reference_guard.KIND_*` et `studio_link._harden_streams`).
MARKER_DEPRECATED = "DEPRECIEE_HISTORIQUE_PAS_UNE_REGLE_ACTIVE"
MARKER_GENERATION_MISMATCH = "GENERATION_DIFFERENTE_A_REEXAMINER"


# --- E/S JSONL (patron best-effort en lecture : une ligne corrompue est ignorée, ---
# --- jamais un crash — même choix que forge.context_manifest._read_lines) ----------

def _append(path: Path, record: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")


def _read_jsonl(path: Path) -> list[dict]:
    if not path.exists():
        return []
    out: list[dict] = []
    try:
        raw_text = path.read_text(encoding="utf-8")
    except OSError:
        return []
    for line in raw_text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        if isinstance(rec, dict):
            out.append(rec)
    return out


def load_current_generation(path: Path | None = None) -> int | None:
    """Génération courante déclarée dans `genome_generation.yaml` (fichier de
    DONNÉES — voir sa docstring pour la source de ratification). `None` si le
    fichier est ABSENT : état légitime (« génération inconnue »), traité par
    `_generation_mismatch` exactement comme n'importe quelle génération inconnue
    — jamais une correspondance silencieuse. Un fichier PRÉSENT mais malformé
    lève `ValueError` (même philosophie que `reference_guard.load_config` :
    jamais un vert/None silencieux qui masquerait une configuration cassée)."""
    p = path or DEFAULT_GENERATION_PATH
    if not p.exists():
        return None
    try:
        raw = p.read_text(encoding="utf-8")
    except OSError as exc:
        raise ValueError(f"genome_generation illisible ({p}): {exc}") from exc
    try:
        data = yaml.safe_load(raw)
    except yaml.YAMLError as exc:
        raise ValueError(f"genome_generation YAML invalide ({p}): {exc}") from exc
    if not isinstance(data, dict) or not isinstance(data.get("current_generation"), int):
        raise ValueError(
            f"genome_generation mal formé (current_generation manquant/non-entier): {p}"
        )
    return data["current_generation"]


# =====================================================================================
# A. failure_event — append-only, clé par failure_id, replié à la lecture
# =====================================================================================

def make_failure_id(project: str, etape_detection: str, erreur_observee: str) -> str:
    """ID stable dérivé du CONTENU (projet + étape de détection + erreur observée).

    Convenance : deux détections INDÉPENDANTES du même problème (deux runs séparés
    qui tombent sur la même erreur, au même endroit) convergent sur le même
    `failure_id` sans coordination explicite. Un appelant qui préfère un identifiant
    choisi/lisible peut l'ignorer et fournir directement son propre `failure_id` à
    `record_failure_event` — ce helper n'est jamais la SEULE façon d'en obtenir un.
    """
    digest = hashlib.sha256(
        f"{project}|{etape_detection}|{erreur_observee}".encode("utf-8")
    ).hexdigest()
    return f"fail-{digest[:16]}"


def record_failure_event(
    failure_id: str,
    run_id: str,
    project: str,
    *,
    erreur_observee: str,
    etape_detection: str,
    causes_suspectees: list[dict] | None = None,
    niveaux_mutation_proposes: list[str] | None = None,
    experience_associee: str = "",
    verdict_oracle: str = "",
    lesson_texte: str = "",
    lesson_statut: str = "",
    path: Path | None = None,
    ts: float | None = None,
) -> dict:
    """Ajoute UN événement au journal append-only d'un `failure_id`.

    N'ÉCRASE JAMAIS un événement précédent du même `failure_id` : chaque appel
    AJOUTE une ligne. Une attribution révisée (ex. cause_suspectee `execution` ->
    `connaissance` après une expérience) s'enregistre en rappelant cette fonction
    avec le même `failure_id` et un `causes_suspectees` mis à jour — l'ancienne
    ligne reste lisible via `read_failure_event_history` (doctrine §2.1 : « la
    trace d'une attribution révisée est exactement la donnée qui apprend à mieux
    attribuer »).

    Champs sans producteur à ce stade (mission, règle des « trois états ») sont
    DÉCLARÉS VIDES (`""`/`[]`), jamais absents : `experience_associee`,
    `verdict_oracle`, `lesson_texte`/`lesson_statut` par défaut.
    """
    if not failure_id:
        raise ValueError("failure_id requis (clé de regroupement append-only)")
    causes = list(causes_suspectees or [])
    for cause in causes:
        level = cause.get("level") if isinstance(cause, dict) else None
        status = cause.get("status") if isinstance(cause, dict) else None
        if level not in CAUSE_LEVELS:
            raise ValueError(
                f"cause_suspectee.level invalide: {level!r} (attendu un de {CAUSE_LEVELS})"
            )
        if status not in CAUSE_ATTRIBUTION_STATUSES:
            raise ValueError(
                f"cause_suspectee.status invalide: {status!r} "
                f"(attendu un de {CAUSE_ATTRIBUTION_STATUSES})"
            )
    if lesson_statut not in _EMBEDDED_LESSON_STATUSES:
        raise ValueError(
            f"lesson_statut invalide: {lesson_statut!r} (attendu '', 'validee' ou 'rejetee')"
        )

    record = {
        "schema": FAILURE_EVENT_SCHEMA,
        "failure_id": failure_id,
        "run_id": run_id,
        "project": project,
        "etape_detection": etape_detection,
        "erreur_observee": erreur_observee,
        "causes_suspectees": causes,
        "niveaux_mutation_proposes": list(niveaux_mutation_proposes or []),
        "experience_associee": experience_associee,
        "verdict_oracle": verdict_oracle,
        "lesson": {"texte": lesson_texte, "statut": lesson_statut},
        "ts": ts if ts is not None else time.time(),
    }
    _append(path or DEFAULT_FAILURE_EVENTS_PATH, record)
    return record


def read_failure_event_history(failure_id: str, path: Path | None = None) -> list[dict]:
    """TOUS les événements bruts d'un `failure_id`, dans l'ordre d'écriture — rien de
    replié, rien de perdu. C'est la preuve que l'append-only conserve l'historique."""
    return [r for r in _read_jsonl(path or DEFAULT_FAILURE_EVENTS_PATH)
            if r.get("failure_id") == failure_id]


def fold_failure_events(path: Path | None = None) -> dict[str, dict]:
    """Replie le journal append-only : UN enregistrement courant par `failure_id`
    (le DERNIER événement écrit pour cet id — dernier-écrit-gagne, ordre de fichier =
    ordre chronologique d'écriture). L'historique complet reste disponible via
    `read_failure_event_history`/`read_all_failure_events_raw` ; ce repli est
    seulement une vue de LECTURE, jamais une réécriture du fichier source."""
    out: dict[str, dict] = {}
    for r in _read_jsonl(path or DEFAULT_FAILURE_EVENTS_PATH):
        fid = r.get("failure_id")
        if fid:
            out[fid] = r
    return out


def read_all_failure_events_raw(path: Path | None = None) -> list[dict]:
    """Tous les événements bruts, tous `failure_id` confondus, dans l'ordre
    d'écriture — pour un audit/index qui veut l'historique complet."""
    return list(_read_jsonl(path or DEFAULT_FAILURE_EVENTS_PATH))


# =====================================================================================
# B. lesson — objet distinct, statut révisable par preuve, jamais le passé
# =====================================================================================

def record_lesson_event(
    lesson_id: str,
    *,
    status: str,
    statement: str | None = None,
    cause: str | None = None,
    generation: int | None = None,
    add_supporting_run: str | None = None,
    add_counter_example: str | None = None,
    caused_by_failure_id: str = "",
    caused_by_experience: str = "",
    path: Path | None = None,
    ts: float | None = None,
) -> dict:
    """Ajoute UN événement (création OU transition) au journal append-only d'une
    leçon. Comme A, n'écrase JAMAIS un événement précédent : `fold_lessons` replie
    à la lecture, l'historique reste lisible via `read_lesson_history`.

    - Une leçon NEUVE (aucun événement préalable pour ce `lesson_id`) doit démarrer
      `candidate` avec un `statement` non vide — sinon `ValueError` (jamais une
      leçon qui apparaît déjà validée sans être passée par candidate).
    - Une leçon EXISTANTE ne peut transiter que selon `ALLOWED_TRANSITIONS`
      (doctrine §2.2) — une transition hors table lève `ValueError`. Ce n'est PAS
      une décision automatique (aucun comptage de preuve ici, HORS PÉRIMÈTRE) :
      c'est un GARDE-FOU mécanique contre une transition que la doctrine ne
      prévoit pas (ex. `weakened -> validated` directement).
    - `add_supporting_run`/`add_counter_example` sont CUMULATIFS : la nouvelle
      ligne écrite porte la liste PRÉCÉDENTE + l'ajout (jamais un remplacement),
      donc `evidence_count` ne peut jamais reculer en silence.
    - `caused_by_failure_id`/`caused_by_experience` : « chaque transition cite le
      failure_id ou l'expérience qui la provoque » (doctrine §2.2) — déclarés
      vides par défaut (règle des trois états), jamais absents.
    """
    if status not in LESSON_STATUSES:
        raise ValueError(f"status invalide: {status!r} (attendu un de {LESSON_STATUSES})")

    store = path or DEFAULT_LESSONS_PATH
    prior = fold_lessons(store).get(lesson_id)

    if prior is None:
        if status != LESSON_STATUS_CANDIDATE:
            raise ValueError(
                f"une leçon neuve ({lesson_id!r}) doit démarrer 'candidate', reçu {status!r}"
            )
        if not statement:
            raise ValueError("statement requis à la création d'une leçon")
        statement_final = statement
        # `cause` vide est un ÉTAT DÉCLARÉ, jamais un oubli : c'est ainsi qu'un
        # événement d'exécution (pas de `root_cause` au manifeste) se distingue d'une
        # connaissance. Aucune inférence depuis `statement` — règle ratifiée Pierre.
        cause_final = cause or ""
        supporting_runs: list[str] = []
        counter_examples: list[str] = []
        evidence_count = 0
    else:
        if status != prior.get("status"):
            allowed = ALLOWED_TRANSITIONS.get(prior.get("status", ""), frozenset())
            if status not in allowed:
                raise ValueError(
                    f"transition interdite pour {lesson_id!r}: "
                    f"{prior.get('status')!r} -> {status!r} (autorisées: {sorted(allowed)})"
                )
        statement_final = statement if statement is not None else prior.get("statement", "")
        # Même patron que `statement`/`generation` : une transition qui ne fournit pas
        # `cause` HÉRITE de la précédente. Une leçon v1 (sans le champ) reste sans cause
        # — aucune migration implicite : l'historique reste ce qu'il est.
        cause_final = cause if cause is not None else prior.get("cause", "")
        supporting_runs = list(prior.get("supporting_runs", []))
        counter_examples = list(prior.get("counter_examples", []))
        evidence_count = int(prior.get("evidence_count", 0))
        if generation is None:
            generation = prior.get("generation")

    if add_supporting_run:
        supporting_runs = supporting_runs + [add_supporting_run]
        evidence_count += 1
    if add_counter_example:
        counter_examples = counter_examples + [add_counter_example]

    record = {
        "schema": LESSON_SCHEMA,
        "lesson_id": lesson_id,
        "statement": statement_final,
        "cause": cause_final,
        "status": status,
        "evidence_count": evidence_count,
        "supporting_runs": supporting_runs,
        "counter_examples": counter_examples,
        "generation": generation,
        "caused_by": {"failure_id": caused_by_failure_id, "experience": caused_by_experience},
        "ts": ts if ts is not None else time.time(),
    }
    _append(store, record)
    return record


def read_lesson_history(lesson_id: str, path: Path | None = None) -> list[dict]:
    """Tous les événements bruts d'une leçon, dans l'ordre d'écriture."""
    return [r for r in _read_jsonl(path or DEFAULT_LESSONS_PATH)
            if r.get("lesson_id") == lesson_id]


def fold_lessons(path: Path | None = None) -> dict[str, dict]:
    """Replie le journal append-only des leçons : un enregistrement courant par
    `lesson_id` (dernier événement écrit). Même garantie que `fold_failure_events` :
    lecture seule, l'historique reste intact sur disque."""
    out: dict[str, dict] = {}
    for r in _read_jsonl(path or DEFAULT_LESSONS_PATH):
        lid = r.get("lesson_id")
        if lid:
            out[lid] = r
    return out


# =====================================================================================
# D. promote_manifest_lessons — pont Context Manifest -> lesson (lot A réparation 2,
#    post-mortem pacman 2026-08-07, studio_brain/journal/2026-08-07_postmortem_pacman_
#    forge.md §1/§2/§6.2). MESURÉ : les manifests des lots V3-V6 pacman portent
#    `reason.problem`/`reason.root_cause` (root causes signées HMAC dans le Context
#    Manifest de dispatch de `s9-build-godot-standard`) jamais relues par
#    `premortem_lessons()` — la boucle Run -> FailureEvent -> Lesson -> Doctrine
#    s'arrêtait au 2e maillon (0 promotion, registres intacts).
# =====================================================================================

def _iter_manifest_reason_records(run_dir: Path):
    """Itère les enregistrements de `run_dir/context/*.manifest.jsonl` dont `reason`
    porte un `problem` OU un `root_cause` non vide — les SEULS candidats à la
    promotion (la grande majorité des lignes de Context Manifest, ex.
    `reason: {"status": "NOT_TRANSMITTED", ...}`, n'en portent aucun et sont
    silencieusement ignorées, PAS une erreur).

    Tolérant aux lignes/fichiers corrompus ou absents (même patron `_read_jsonl` que
    le reste de ce module) : un manifest partiel ne fait jamais lever cette fonction.
    Générateur PUR EN LECTURE — n'écrit jamais rien.
    """
    context_dir = Path(run_dir) / "context"
    if not context_dir.is_dir():
        return
    for manifest_path in sorted(context_dir.glob("*.manifest.jsonl")):
        for row in _read_jsonl(manifest_path):
            reason = row.get("reason")
            if not isinstance(reason, dict):
                continue
            problem = str(reason.get("problem") or "").strip()
            root_cause = str(reason.get("root_cause") or "").strip()
            if not problem and not root_cause:
                continue
            yield manifest_path, row, problem, root_cause


def make_manifest_lesson_id(etape: str, problem: str, root_cause: str) -> str:
    """ID stable dérivé du CONTENU (étape + problem + root_cause) — même patron que
    `make_failure_id` : deux manifests INDÉPENDANTS (deux runs séparés, ou deux
    exécutions du pont sur le même run) qui portent le MÊME couple problem/root_cause
    convergent sur le MÊME `lesson_id` sans coordination explicite — c'est ce qui
    rend `promote_manifest_lessons` idempotent."""
    digest = hashlib.sha256(f"{etape}|{problem}|{root_cause}".encode("utf-8")).hexdigest()
    return f"manifest-{digest[:16]}"


def promote_manifest_lessons(
    run_dir: Path, lessons_path: Path | None = None, *, ts: float | None = None,
) -> list[dict]:
    """Pont Context Manifest -> lesson : lit `run_dir/context/*.manifest.jsonl`,
    promeut chaque `reason.problem`/`reason.root_cause` distinct en leçon
    `forge.lesson.v1` CANDIDATE (jamais un statut plus fort — voir doctrine §2.2, une
    leçon se gagne par PREUVE, jamais par ce pont mécanique).

    Garanties tenues :
      - AUCUNE reformulation, AUCUNE synthèse, AUCUN scoring : `statement` concatène
        `problem` et `root_cause` VERBATIM (séparateur fixe) — jamais réécrits,
        jamais résumés, jamais jugés pertinents ou non par ce code.
      - IDEMPOTENTE : `lesson_id` est dérivé du CONTENU (`make_manifest_lesson_id`).
        Une leçon déjà présente dans `lessons_path` (même `lesson_id`) n'est PAS
        ré-écrite — 0 doublon à la ré-exécution, prouvé par test, pas par convention.
        (`record_lesson_event` refuserait de toute façon une 2e création `candidate`
        du même id — ALLOWED_TRANSITIONS ne permet pas candidate->candidate — mais ce
        pont évite même l'appel superflu en vérifiant `fold_lessons` d'abord.)
      - `add_supporting_run` porte le `run_id` du manifest (ou, à défaut, le nom du
        dossier de run) — jamais un `project` inventé : le schéma `forge.lesson.v1`
        n'a pas de champ projet (leçons cross-projet par construction, doctrine §2.2).
      - Écrit UNIQUEMENT dans `lessons_path` (ou le défaut PRODUCTION de
        `record_lesson_event` si `None` — même convention que tout le reste de ce
        module) : ne touche JAMAIS `run_dir/context/` (lecture seule).

    Retourne la liste des enregistrements de leçon RÉELLEMENT écrits par CET appel —
    une leçon déjà connue est absente de ce retour (c'est la preuve d'idempotence
    lisible par l'appelant, sans avoir à relire le fichier).
    """
    written: list[dict] = []
    existing = fold_lessons(lessons_path)
    for manifest_path, row, problem, root_cause in _iter_manifest_reason_records(run_dir):
        etape = row.get("etape") or manifest_path.name.removesuffix(".manifest.jsonl")
        run_id = row.get("run_id") or Path(run_dir).name
        lesson_id = make_manifest_lesson_id(etape, problem, root_cause)
        if lesson_id in existing:
            continue  # déjà promue par un appel précédent (idempotence)
        statement = " — cause: ".join(part for part in (problem, root_cause) if part)
        record = record_lesson_event(
            lesson_id, status=LESSON_STATUS_CANDIDATE, statement=statement,
            # v2 : `root_cause` voyage AUSSI en champ. `statement` est INCHANGÉ (même
            # concaténation, mêmes octets) — la cause n'est pas déplacée, elle cesse
            # d'être UNIQUEMENT en prose. `root_cause` vide => `cause` vide : le
            # manifeste ne portait pas de cause, on ne l'invente pas.
            cause=root_cause,
            add_supporting_run=str(run_id),
            caused_by_experience=f"{etape} ({manifest_path.name})",
            path=lessons_path, ts=ts,
        )
        existing[lesson_id] = record
        written.append(record)
    return written


def backfill_cause_from_manifests(
    runs_root: Path | None = None,
    lessons_path: Path | None = None,
    *,
    dry_run: bool = True,
) -> list[dict]:
    """Renseigne `cause` sur les leçons v1 EN LA RELISANT DEPUIS SON MANIFESTE D'ORIGINE.

    Ce n'est PAS une migration ni une inférence : `_iter_manifest_reason_records` relit
    `reason.root_cause` du fichier source, exactement comme à la première promotion. La
    prose de `statement` n'est jamais lue (règle ratifiée Pierre 2026-09-01).

    NÉCESSAIRE parce que `promote_manifest_lessons` est IDEMPOTENTE : une leçon déjà
    promue n'est jamais ré-émise, donc les leçons v1 ne recevraient jamais de champ.

    APPEND-ONLY : écrit un ÉVÉNEMENT de plus sur la leçon (même `status`, donc aucune
    transition — `record_lesson_event` ne contrôle la table que si le statut change).
    L'historique n'est jamais réécrit ; `fold_lessons` replie sur le dernier événement.

    Traite UNIQUEMENT les leçons dont le champ est ABSENT et dont le manifeste porte une
    `root_cause` non vide. Une leçon déjà pourvue n'est pas retouchée ; un manifeste
    disparu avec son run_dir laisse la leçon sans cause — un trou MESURÉ, jamais comblé.

    `dry_run=True` (défaut) ne touche RIEN : rend la liste de ce qui serait écrit.
    """
    root = Path(runs_root) if runs_root is not None else (REPO_ROOT / "EVIDENCE" / "runs")
    store = lessons_path or DEFAULT_LESSONS_PATH
    connues = fold_lessons(store)

    # Reconstruire id -> root_cause depuis les manifestes encore présents.
    causes: dict[str, str] = {}
    if root.is_dir():
        for run_dir in sorted(p for p in root.iterdir() if p.is_dir()):
            try:
                for manifest_path, _row, problem, root_cause in _iter_manifest_reason_records(run_dir):
                    if not root_cause:
                        continue
                    etape = manifest_path.name.split(".")[0]
                    causes.setdefault(make_manifest_lesson_id(etape, problem, root_cause), root_cause)
            except OSError:
                continue  # run_dir illisible : trou mesuré, jamais une exception

    plan: list[dict] = []
    for lesson_id, cause in sorted(causes.items()):
        prior = connues.get(lesson_id)
        if prior is None or "cause" in prior:
            continue  # inconnue du journal, ou déjà pourvue : on ne retouche rien
        plan.append({"lesson_id": lesson_id, "cause": cause, "status": prior.get("status")})

    if dry_run:
        return plan
    for item in plan:
        record_lesson_event(item["lesson_id"], status=item["status"],
                            cause=item["cause"], path=store)
    return plan


# --- Compatibilité : anciennes leçons de méthode (pré-schéma) ----------------------

def legacy_global_lessons(
    *, domain_path: Path | None = None, monolith_path: Path | None = None,
) -> list[dict]:
    """Lit (jamais n'écrit) les anciennes « leçons de méthode » du journal d'erreurs
    existant : convention historique `project == "_global_"`, `run_id == "_method_"`
    (doctrine §2.1 — « une leçon de méthode est enregistrée aujourd'hui comme une
    erreur ordinaire »). Par défaut, mêmes DEUX sources que `forge.studio_link.
    premortem()` lit déjà pour le scope global : le journal de domaine
    `_global_.jsonl` (peut être vide/absent) PLUS le monolithe historique
    `forge_error_journal.jsonl` en fallback (source réelle actuelle : 3 leçons,
    cf. corpus du dépôt). `domain_path`/`monolith_path` permettent à un appelant
    (ex. `ForgeDriver`, pour un run isolé hors repo) de rediriger la lecture vers
    des chemins vides plutôt que le corpus réel — jamais utilisé pour un vrai run
    studio, où les défauts ci-dessus s'appliquent.

    Forme mécanique retenue pour « ni perdue, ni promue en silence » (RÈGLE DE
    COMPATIBILITÉ de la mission) : chaque entrée legacy est enveloppée en vue de
    LECTURE au format Lesson, avec `status=LEGACY_STATUS` — délibérément AUCUN des
    5 statuts officiels, donc jamais confondue avec `candidate`/`validated`
    (PAS PERDUE : elle apparaît dans `premortem_lessons()` comme les autres ;
    PAS PROMUE : son statut ne prétend à aucune validation, et `generation=None`
    la fait retomber dans la même case que « génération différente » à l'injection
    — réutilisation de la politique déjà ratifiée plutôt qu'un 6e état inventé).

    `lesson_id` est DÉRIVÉ du contenu (étape + texte), stable d'une lecture à
    l'autre — jamais un compteur qui dépendrait de l'ordre de lecture.
    """
    domain_path = domain_path if domain_path is not None else (
        DOMAIN_JOURNAL_DIR / f"{GLOBAL_SCOPE}.jsonl"
    )
    monolith_path = monolith_path if monolith_path is not None else DEFAULT_ERROR_JOURNAL
    rows = _read_jsonl(domain_path)
    rows += [r for r in _read_jsonl(monolith_path) if r.get("project") == GLOBAL_SCOPE]

    out: list[dict] = []
    seen: set[str] = set()
    for row in rows:
        if row.get("run_id") != "_method_" or row.get("project") != GLOBAL_SCOPE:
            continue
        statement = row.get("error") or ""
        etape = row.get("etape") or ""
        digest = hashlib.sha256(f"{etape}|{statement}".encode("utf-8")).hexdigest()[:16]
        lesson_id = f"legacy-{digest}"
        if lesson_id in seen:
            continue
        seen.add(lesson_id)
        out.append({
            "schema": None,  # pré-schéma : versionné nulle part, jamais inventé
            "lesson_id": lesson_id,
            "statement": statement,
            "status": LEGACY_STATUS,
            "evidence_count": 1,
            "supporting_runs": [],
            "counter_examples": [],
            "generation": None,
            "caused_by": {"failure_id": "", "experience": ""},
            "source_etape": etape,
            "legacy": True,
        })
    return out


# =====================================================================================
# C. premortem_lessons — le seul changement de lecture (récupérer / filtrer / afficher)
# =====================================================================================

def _generation_mismatch(lesson_generation: int | None, current_generation: int | None) -> bool:
    """Vrai si la génération de la leçon N'EST PAS PROUVÉE identique à la génération
    courante. `None` d'UN COTÉ OU DE L'AUTRE signifie « inconnue », jamais « égale » :
    l'absence de preuve de correspondance ne doit jamais se lire comme une
    correspondance silencieuse (doctrine §3, observed != declared, transposé à la
    génération). C'est ce qui fait retomber une leçon legacy (`generation=None`)
    dans la case « génération différente » même quand l'appelant ne connaît pas non
    plus sa propre génération courante (`current_generation=None`)."""
    if lesson_generation is None or current_generation is None:
        return True
    return lesson_generation != current_generation


def apply_injection_policy(lessons: list[dict], current_generation: int | None) -> list[dict]:
    """FILTRE structurel — politique d'injection RATIFIÉE (doctrine §2.3) :

        | cas                    | traitement                                  |
        |-------------------------|---------------------------------------------|
        | statut rejected         | OMISE (jamais injectée comme contrainte)     |
        | statut deprecated       | conservée, marquée historique (pas active)   |
        | génération différente   | conservée, marquée « à réexaminer »          |
        | même génération         | conservée, sans marqueur (injection normale) |

    Filtre sur des CHAMPS (statut, génération) — jamais sur le CONTENU de la
    leçon : aucune lecture sémantique, aucun jugement de pertinence. Chaque leçon
    retenue porte un `marker` (`None` si injection normale)."""
    out: list[dict] = []
    for lesson in lessons:
        status = lesson.get("status")
        if status == LESSON_STATUS_REJECTED:
            continue
        # GATE 1 (ratifiée Pierre 2026-09-01) — RÈGLE DES TROIS ÉTATS sur `cause` :
        #   absent  (leçon v1) -> TOLÉRÉ : la cause est INCONNUE, pas niée. Exclure ici
        #                         supprimerait définitivement les 287 leçons causales de
        #                         l'historique — `promote_manifest_lessons` est idempotente
        #                         (`if lesson_id in existing: continue`), elles ne seraient
        #                         JAMAIS ré-émises avec un champ. Mesuré : 0/326 passeraient.
        #   vide    (leçon v2) -> EXCLU : le manifeste ne portait pas de `root_cause`, donc
        #                         l'absence de cause est DÉCLARÉE. C'est un événement
        #                         d'exécution (« echec de la tentative 0 a s4-archi »), pas
        #                         une connaissance : stocké à l'historique, hors contexte agent.
        #   rempli             -> ADMIS.
        # Reste un filtre sur CHAMP, jamais sur le CONTENU (aucune lecture de `statement`,
        # aucun jugement de pertinence) — l'invariant de cette fonction est conservé.
        # Gate 2 (`valider()` -> KB) est SÉPARÉE : une leçon `candidate` causale entre ici.
        if "cause" in lesson and not str(lesson.get("cause") or "").strip():
            continue
        marker: str | None = None
        if status == LESSON_STATUS_DEPRECATED:
            marker = MARKER_DEPRECATED
        elif _generation_mismatch(lesson.get("generation"), current_generation):
            marker = MARKER_GENERATION_MISMATCH
        out.append({**lesson, "marker": marker})
    return out


def format_premortem_lessons(annotated: list[dict], limit: int = 5) -> list[str]:
    """AFFICHE : rendu texte déterministe. Tri par RÉCENCE décroissante (`ts`,
    un champ ÉCRIT avec la leçon — jamais une horloge de lecture, le déterminisme
    est conservé) puis par `lesson_id` (départage stable), puis troncature aux
    `limit` premières. Aucune reformulation du `statement` : affiché tel quel.

    Lot 1 ADR-003 (P0-5) — avant : tri par `lesson_id` alphabétique SEUL + limit=5.
    Mesuré le 2026-08-15 : les 6 leçons `manifest-*` de la réparation post-mortem
    pacman (les plus récentes du corpus) arrivaient aux index 21-26 sur 27 — AUCUN
    run ne pouvait jamais les voir. Une boucle d'apprentissage qui écrit ce que
    son consommateur ne relit jamais n'apprend rien : la récence est un critère
    STRUCTUREL (quand la leçon a été écrite), pas un jugement de contenu."""
    ordered = sorted(annotated,
                     key=lambda l: (-(l.get("ts") or 0), l.get("lesson_id") or ""))
    if limit:
        ordered = ordered[:limit]
    lines = []
    for lesson in ordered:
        base = f"[{lesson.get('lesson_id')}] {lesson.get('statement')}"
        marker = lesson.get("marker")
        if marker:
            base += f" -- {marker}"
        lines.append(base)
    return lines


def premortem_lessons(
    *,
    current_generation: int | None = None,
    lessons_path: Path | None = None,
    include_legacy: bool = True,
    legacy_domain_path: Path | None = None,
    legacy_monolith_path: Path | None = None,
    limit: int = 5,
) -> list[str]:
    """Point d'entrée unique des trois gestes (doctrine §2.3 : « récupérer les
    leçons pertinentes · appliquer les filtres · afficher le contexte », pas un de
    plus) :

        récupérer -> fold_lessons() + legacy_global_lessons()
        filtrer   -> apply_injection_policy()
        afficher  -> format_premortem_lessons()

    Déterministe par construction (aucun appel LLM, aucune horloge dans le tri) :
    deux appels sur le même corpus rendent une sortie IDENTIQUE — propriété
    vérifiée par `test_learning_memory.py::test_premortem_lessons_is_deterministic`.

    `legacy_domain_path`/`legacy_monolith_path` sont transmis tels quels à
    `legacy_global_lessons` (voir sa docstring) — permettent à un appelant
    d'isoler un run de test du corpus legacy réel sans changer le comportement
    par défaut (production : les vrais chemins `forge.studio_link`).
    """
    current = list(fold_lessons(lessons_path).values())
    if include_legacy:
        current = current + legacy_global_lessons(
            domain_path=legacy_domain_path, monolith_path=legacy_monolith_path,
        )
    annotated = apply_injection_policy(current, current_generation)
    return format_premortem_lessons(annotated, limit=limit)


# =====================================================================================
# CLI — entrée humaine/agent pour un acte qui ne peut pas être automatisé (même
# doctrine que forge.studio_link.main : consigner une cause suspectée ou une
# transition de leçon est un JUGEMENT, jamais fabriqué par du code).
# =====================================================================================

def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="CLI forge.learning_memory : failure_event + lesson (append-only)."
    )
    sub = parser.add_subparsers(dest="cmd")

    p_failure = sub.add_parser(
        "failure", help="ajoute un événement à un failure_event (record_failure_event)")
    p_failure.add_argument("--failure-id", required=True)
    p_failure.add_argument("--run-id", required=True)
    p_failure.add_argument("--project", required=True)
    p_failure.add_argument("--erreur-observee", required=True)
    p_failure.add_argument("--etape-detection", required=True)
    p_failure.add_argument("--experience-associee", default="")
    p_failure.add_argument("--verdict-oracle", default="")

    p_lesson = sub.add_parser(
        "lesson", help="ajoute un événement à une leçon (record_lesson_event)")
    p_lesson.add_argument("--lesson-id", required=True)
    p_lesson.add_argument("--status", required=True, choices=LESSON_STATUSES)
    p_lesson.add_argument("--statement", default=None)
    p_lesson.add_argument("--generation", type=int, default=None)
    p_lesson.add_argument("--caused-by-failure-id", default="")
    p_lesson.add_argument("--caused-by-experience", default="")

    # promote-manifest : DISTINCT des deux sous-commandes ci-dessus — pas un jugement
    # humain/agent, un pont MÉCANIQUE déterministe (promote_manifest_lessons) qui lit
    # `reason.problem`/`reason.root_cause` déjà écrits (signés HMAC) dans le Context
    # Manifest d'un run et les promeut en leçons CANDIDATE, verbatim, idempotent.
    p_promote = sub.add_parser(
        "promote-manifest",
        help="promeut reason.problem/root_cause des manifests d'un run en leçons "
             "CANDIDATE (promote_manifest_lessons, idempotent, aucune reformulation)")
    p_promote.add_argument("--run-dir", required=True)
    p_promote.add_argument("--lessons-path", default=None)

    return parser


def main(argv: list[str] | None = None) -> int:
    """Même contrat que `studio_link.main` : `_harden_streams()` en premier,
    jamais de trace Python nue, toujours un int en retour."""
    _harden_streams()
    parser = _build_parser()
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:
        return exc.code if isinstance(exc.code, int) else 2

    if args.cmd == "failure":
        try:
            record = record_failure_event(
                args.failure_id, args.run_id, args.project,
                erreur_observee=args.erreur_observee,
                etape_detection=args.etape_detection,
                experience_associee=args.experience_associee,
                verdict_oracle=args.verdict_oracle,
            )
        except ValueError as exc:
            print(f"erreur: {exc}", file=sys.stderr)
            return 2
        print(f"failure_event consigné -> {DEFAULT_FAILURE_EVENTS_PATH} "
              f"(failure_id={record['failure_id']})")
        return 0

    if args.cmd == "lesson":
        try:
            record = record_lesson_event(
                args.lesson_id, status=args.status, statement=args.statement,
                generation=args.generation,
                caused_by_failure_id=args.caused_by_failure_id,
                caused_by_experience=args.caused_by_experience,
            )
        except ValueError as exc:
            print(f"erreur: {exc}", file=sys.stderr)
            return 2
        print(f"lesson consignée -> {DEFAULT_LESSONS_PATH} "
              f"(lesson_id={record['lesson_id']}, status={record['status']})")
        return 0

    if args.cmd == "promote-manifest":
        lessons_path = Path(args.lessons_path) if args.lessons_path else None
        written = promote_manifest_lessons(Path(args.run_dir), lessons_path=lessons_path)
        target = lessons_path or DEFAULT_LESSONS_PATH
        print(f"{len(written)} leçon(s) nouvellement promue(s) -> {target}")
        for w in written:
            print(f"  - {w['lesson_id']}: {w['statement'][:100]}")
        return 0

    parser.print_usage(sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
