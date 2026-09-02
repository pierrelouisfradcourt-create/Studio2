"""forge.kb_proposal — Playtest -> Observer -> Lesson validee -> KB proposal -> KB update.

Chantier P0 ratifie (studio_brain/planning/planning.yaml, tache 'P0-boucle-lessons-kb').
Directive Pierre (verbatim) : « Creer le vrai cycle : Playtest -> Observer -> Lesson
candidate -> Validation humaine -> KB proposal -> KB update -> Nouvelle construction.
Pas d'ecriture automatique. Mais le chemin doit exister. »

Constat qui motive ce module (memoire studio, 2026-08) : 5 lecons `validated` liees a
la campagne breakout_v2 existent dans EVIDENCE/reports/lessons.jsonl (forge.learning_memory),
0 entree correspondante dans knowledge_base/catalog.json -- drift nomme
`lecon_routee_sans_consommateur` (x5). Une lecon validee par un humain n'atteignait
jamais la bibliotheque : rien ne portait la lecon jusqu'au catalogue, meme comme
proposition. Ce module ferme cette portion PRECISE du chemin, pas tout le cycle :
il part de lessons.jsonl (deja ecrit par forge.learning_memory, deja valide par un
humain en amont via record_lesson_event(status="validated")) et s'arrete a une
proposition YAML relisible + un geste d'application EXPLICITE.

POURQUOI aucune ecriture automatique du catalogue (invariant dur -- ADR-002 +
decision Pierre P0, "la machine propose et prouve, l'humain tranche et signe") :
  - `knowledge_base/catalog.json` est une memoire de REFERENCE versionnee, au meme
    titre que IMPROVEMENT_LEDGER.yaml ou la liste des projets forges. Toutes les
    autres portes d'ecriture vers ce genre de memoire dans ce depot sont
    PROPOSE-ONLY (voir forge.studio_link.propose_brick / propose_bible_entry /
    propose_ledger_entry / propose_project_record) : un agent depose, un humain
    promeut. Un module qui ecrirait le catalogue directement depuis --generate
    rouvrirait exactement le trou que ce patron ferme partout ailleurs.
  - Le validateur du catalogue (knowledge_base/kb-validate.mjs, regles R1..R14)
    est la SEULE porte de conformite reconnue par le studio ; il doit s'executer
    sur du contenu DEJA ECRIT sur disque, jamais avant/a la place. --apply
    l'invoque APRES ecriture et restaure si le verdict est negatif -- jamais un
    verdict de conformite decide par ce module lui-meme.
  - Limite honnete assumee (pas corrigee ici, voir _lesson_to_pattern_entry) :
    une Lesson Forge est une observation de PROCESSUS interne, pas un pattern de
    jeu cite depuis une source externe. Le catalogue exige (R3, kind=pattern)
    une `provenance_url` http(s) verifiable ; une proposition generee depuis une
    lecon n'en a structurellement pas. Automatiser l'ecriture masquerait ce trou
    au lieu de le rendre visible a Pierre au moment de la decision.
  - Trois gestes seulement : --generate (deterministe, idempotent, ne touche
    JAMAIS catalog.json) ; --list (lecture pure) ; --apply/--reject (les SEULS
    points d'ecriture du catalogue ou d'une proposition, geste manuel explicite
    -- --ratifie-par est un argument requis, jamais une valeur par defaut).

Aucun import de ce module ailleurs dans le depot (verifie par grep avant
livraison) : kb_proposal est appele a la main, jamais depuis un autre script.
"""
from __future__ import annotations

import argparse
import json
import logging
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

try:
    import yaml
except ImportError as _exc:  # pragma: no cover — environnement sans PyYAML
    yaml = None  # type: ignore[assignment]
    _YAML_IMPORT_ERROR: Exception | None = _exc
else:
    _YAML_IMPORT_ERROR = None

from forge.learning_memory import DEFAULT_LESSONS_PATH, LESSON_STATUS_VALIDATED, fold_lessons
from forge.verify_run import _harden_streams

logger = logging.getLogger(__name__)

# forge/kb_proposal.py -> parents[2] == racine du depot (meme convention
# que forge.studio_link / forge.learning_memory).
REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_KB_ROOT = REPO_ROOT / "knowledge_base"
KB_VALIDATE_SCRIPT = REPO_ROOT / "knowledge_base" / "kb-validate.mjs"

PROPOSAL_SCHEMA = "kb.proposal.v1"
PROPOSAL_STATUS_PROPOSED = "PROPOSED"
PROPOSAL_STATUS_APPLIED = "APPLIQUEE"
PROPOSAL_STATUS_REJECTED = "REJETEE"

# Licence par defaut d'une proposition derivee d'une lecon : ce n'est ni du code
# importe ni un asset telecharge (c'est une observation interne du pipeline
# Forge) -- CC0-1.0 est la valeur SPDX fermee la plus proche de "connaissance
# interne, aucune restriction" et reste une licence VALIDE pour un brick de
# kind=pattern (BRICK_SPEC/PATTERN_LICENSES, knowledge_base/kb-validate.mjs).
LESSON_DEFAULT_LICENSE = "CC0-1.0"

# Delta V2 ratifie (voir knowledge_base/proposals/_TAXONOMY_AMENDMENT_PROPOSAL.md,
# section "Delta V2") : deux origines de connaissance possibles pour une entree de
# catalogue kind=pattern. Ce module ne produit JAMAIS que la seconde -- une
# lecon Forge validee est par construction une observation interne, jamais une
# citation externe. La constante existe quand meme (paire complete, jamais une
# seule valeur nue) pour que le champ `knowledge_source` soit un enum ferme
# documente ici, au meme endroit que la valeur qu'il prend reellement.
KNOWLEDGE_SOURCE_EXTERNAL = "external_reference"
KNOWLEDGE_SOURCE_INTERNAL = "internal_lesson"


def _require_yaml() -> None:
    """Echec propre (jamais une trace Python nue) si PyYAML est absent."""
    if yaml is None:
        raise SystemExit(
            "PyYAML est requis (module 'yaml' introuvable) pour forge/"
            f"kb_proposal.py -- installe-le dans l'environnement utilise. "
            f"Erreur d'import d'origine: {_YAML_IMPORT_ERROR}"
        )


def _proposals_dir(kb_root: Path) -> Path:
    return kb_root / "proposals"


def _proposal_path(kb_root: Path, lesson_id: str) -> Path:
    return _proposals_dir(kb_root) / f"{lesson_id}.yaml"


def _catalog_path(kb_root: Path) -> Path:
    return kb_root / "catalog.json"


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _read_yaml(path: Path) -> dict:
    with open(path, encoding="utf-8") as fh:
        data = yaml.safe_load(fh)
    return data if isinstance(data, dict) else {}


def _write_yaml(path: Path, record: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        yaml.safe_dump(record, fh, allow_unicode=True, sort_keys=False)


# =====================================================================================
# Traduction Lesson -> entree catalogue (au format REEL decouvert dans catalog.json,
# verifie contre knowledge_base/kb-validate.mjs::BRICK_SPEC)
# =====================================================================================

def _brick_id_from_lesson(lesson_id: str) -> str:
    """`pat-<lesson_id>` ('.' normalise en '-') : kb-validate.mjs (ID_PREFIX) exige
    qu'un brick_id de kind=pattern commence par 'pat-'."""
    return "pat-" + lesson_id.replace(".", "-")


def _genre_tags_from_lesson(lesson: dict) -> list[str]:
    """Tags derives des `supporting_runs` (nom de projet avant le premier '-run',
    ex. 'breakout_v2-run1-20260731-082705' -> 'breakout_v2'). Jamais vide :
    'forge_process' est toujours present, une lecon de ce pipeline documente le
    PROCESSUS Forge, pas un genre de jeu au sens habituel du catalogue."""
    tags = ["forge_process"]
    for run_id in lesson.get("supporting_runs") or []:
        project = run_id.split("-run")[0] if "-run" in run_id else run_id
        if project and project not in tags:
            tags.append(project)
    return tags


def _confidence_level_from_lesson(lesson: dict) -> str:
    """Niveau de confiance NOMME, derive MECANIQUEMENT de deux signaux deja
    presents dans la Lesson source (forge.learning_memory, schema forge.lesson.v1)
    -- jamais un score invente (regle Pierre : « nb de supporting_runs + statut
    validated -> un niveau nomme, JAMAIS un score invente »).

    Signaux utilises :
      - lesson['status'] : seul 'validated' atteint cette fonction en pratique
        (generate_proposals filtre deja sur LESSON_STATUS_VALIDATED avant
        d'appeler _lesson_to_pattern_entry) -- verifie quand meme ici, jamais
        suppose silencieusement.
      - len(lesson['supporting_runs']) : nombre de runs REELS distincts qui ont
        produit cette lecon. Equivalent a evidence_count par construction
        (forge.learning_memory.record_lesson_event incremente evidence_count de 1
        a chaque add_supporting_run) -- on lit supporting_runs directement plutot
        que de dupliquer ce couplage.

    Seuils (arbitraires mais NOMMES, stables, a ajuster seulement sur decision
    Pierre -- jamais un recalibrage silencieux dans ce module) :
      status != validated  -> "non_validee"  (ne devrait pas arriver ici)
      1 supporting_run     -> "unique"        (une observation, pas reproduite)
      2-3 supporting_runs  -> "recurrente"    (observee plusieurs fois)
      >=4 supporting_runs  -> "forte"         (large base d'observations)

    Avec les 5 lecons breakout_v2 actuelles (1 supporting_run chacune), ce niveau
    vaut "unique" pour les 5 -- pas de variance artificielle inventee pour
    satisfaire une preuve ; la regle est ecrite pour varier des qu'une lecon
    accumule plusieurs runs (cf. forge.learning_memory.LESSON_STATUS_VALIDATED,
    transition candidate -> validated -> weakened avec add_supporting_run repete).
    """
    if lesson.get("status") != LESSON_STATUS_VALIDATED:
        return "non_validee"
    n = len(lesson.get("supporting_runs") or [])
    if n <= 1:
        return "unique"
    if n <= 3:
        return "recurrente"
    return "forte"


def _origin_from_lesson(lesson: dict) -> str:
    """Origine causale humaine-lisible, depuis lesson['caused_by'] (jamais
    inventee) -- champ structure ecrit par forge.learning_memory.record_lesson_event
    (`{"failure_id": ..., "experience": ...}`). Par convention observee sur les 5
    lecons breakout_v2 existantes, exactement un des deux est renseigne (jamais
    les deux a la fois) : un echec Forge trace (failure_id) OU une observation
    directe en texte libre (experience). On prefere failure_id quand present
    (reference tracable a un enregistrement, plus verifiable qu'un texte libre)."""
    caused_by = lesson.get("caused_by") or {}
    failure_id = (caused_by.get("failure_id") or "").strip()
    experience = (caused_by.get("experience") or "").strip()
    if failure_id:
        return f"failure_id={failure_id}"
    if experience:
        return experience
    return "(caused_by vide dans la lecon source -- origine non tracee)"


def _observed_result_from_lesson(lesson: dict) -> dict:
    """'Resultat observe' distinct du 'constat', si la lecon en porte un.

    Verifie contre le schema REEL de Lesson (forge.learning_memory, forge.lesson.v1
    -- champs : lesson_id, statement, status, evidence_count, supporting_runs,
    caused_by, counter_examples, generation, ts) : il n'existe PAS de champ
    'resultat observe' distinct du 'statement'. Une Lesson Forge est deja une
    observation de processus (le statement EST le resultat constate, pas une
    hypothese dont un resultat serait rapporte separement ailleurs).

    Directive explicite pour ce cas (delta V2) : « si la leçon ne porte pas de
    résultat distinct du constat -> champ = le constat, avec note. » Renvoie donc
    le statement tel quel sous 'valeur', jamais reformule, avec 'note' qui rend
    cette egalite visible plutot que de la masquer derriere un nom different."""
    statement = lesson.get("statement", "")
    return {
        "valeur": statement,
        "note": (
            "identique au constat (statement) -- la Lesson source (forge.lesson.v1) "
            "ne porte pas de champ resultat distinct du constat"
        ),
    }


def _provenance_internal_entry(lesson: dict) -> dict:
    """Bloc `provenance_internal` au schema EXACT ratifie (kb-validate.mjs v4,
    isProvenanceInternal — schema ferme, 4 cles, pas une de plus).

    `validated_by`/`validated_at` : la validation candidate→validated des lecons
    L1-L5 est un geste Pierre (BREAKOUT_V2_LESSONS_VALIDATION_2026-07-31) ; la
    date vient du ts de l'evenement `validated` de la lecon elle-meme.
    """
    from datetime import datetime, timezone

    ts = lesson.get("ts")
    validated_at = (
        datetime.fromtimestamp(float(ts), tz=timezone.utc).isoformat()
        if isinstance(ts, (int, float)) else "1970-01-01T00:00:00+00:00"
    )
    return {
        "lessons_source": "EVIDENCE/reports/lessons.jsonl",
        "lesson_id": lesson["lesson_id"],
        "supporting_runs": list(lesson.get("supporting_runs") or []),
        "validation": {
            "status": "validated",
            "validated_by": "Pierre",
            "validated_at": validated_at,
        },
    }


def _internal_lesson_provenance(lesson: dict) -> dict:
    """Bloc `internal_lesson` du delta V2 (knowledge_base/proposals/
    _TAXONOMY_AMENDMENT_PROPOSAL.md, section 'Delta V2') : lesson_id ·
    supporting_runs · origine (depuis caused_by) · confiance (derivee
    mecaniquement, jamais un score invente) · resultat_observe (depuis statement,
    ou le constat lui-meme avec note si aucun resultat distinct n'existe)."""
    return {
        "lesson_id": lesson["lesson_id"],
        "supporting_runs": list(lesson.get("supporting_runs") or []),
        "origine": _origin_from_lesson(lesson),
        "confiance": _confidence_level_from_lesson(lesson),
        "resultat_observe": _observed_result_from_lesson(lesson),
    }


def _lesson_to_pattern_entry(lesson: dict) -> dict:
    """Traduit une Lesson (forge.learning_memory, schema forge.lesson.v1) au format
    REEL d'une entree BRICK de kind=pattern de knowledge_base/catalog.json (champs
    et types exacts : knowledge_base/kb-validate.mjs::BRICK_SPEC).

    Limite honnete, ASSUMEE et non corrigee ici : un pattern deja present dans le
    catalogue (ex. pat-damage-floor) cite une source EXTERNE avec un
    provenance_url http(s) verifiable — R3 de kb-validate.mjs l'exige pour tout
    brick de kind=pattern. Une Lesson Forge est une observation INTERNE issue de
    runs du studio : elle n'a structurellement pas de citation externe verifiable.
    `provenance_url` est donc laisse a `None` ici — ce qui fait echouer R3 au
    moment de --apply, DELIBEREMENT : c'est le validateur, pas ce module, qui doit
    trancher qu'une proposition manque de provenance, et Pierre qui doit ensuite
    decider (fournir une reference reelle, ou juger que cette lecon ne releve pas
    de cette taxonomie). Voir le rapport de mission pour la demonstration de ce
    comportement (restauration automatique du catalogue sur ce rejet R3 reel).

    Delta V2 (ajoute sans toucher au comportement ci-dessus) : la fonction porte
    aussi `knowledge_source`/`internal_lesson` -- ces deux champs ne sont PAS
    encore reconnus par kb-validate.mjs::BRICK_SPEC (le pseudo-diff de
    _TAXONOMY_AMENDMENT_PROPOSAL.md reste non applique). Ils documentent, de
    facon structuree et deja verifiable a l'oeil, ce qu'une future regle R3
    amendee consommerait -- ils n'ouvrent AUCUNE nouvelle voie de PASS pour
    --apply : le validateur reel continue de rejeter sur provenance_url=None
    exactement comme avant ce delta.
    """
    lesson_id = lesson["lesson_id"]
    statement = lesson.get("statement", "")
    return {
        "entry_type": "brick",
        "brick_id": _brick_id_from_lesson(lesson_id),
        "kind": "pattern",
        "function": statement,
        "source": f"Forge lesson '{lesson_id}' (EVIDENCE/reports/lessons.jsonl, forge.learning_memory)",
        "provenance_url": None,
        # RATIFIE Pierre 2026-08-02 (option 1 de _TAXONOMY_AMENDMENT_PROPOSAL) :
        # la provenance INTERNE est desormais un champ reconnu par
        # kb-validate.mjs v4 (schema ferme isProvenanceInternal, regle R3 en
        # exactement-une-provenance). Le detail enrichi (origine, confiance,
        # resultat_observe) reste dans le YAML de proposition, PAS dans l'entree
        # catalogue : le schema du catalogue est ferme, on n'y met que ce que le
        # validateur reconnait.
        "provenance_internal": _provenance_internal_entry(lesson),
        "license": LESSON_DEFAULT_LICENSE,
        "runtime": "agnostic",
        "dependencies": [],
        "parameters": {},
        "genre_compatible": _genre_tags_from_lesson(lesson),
        "invariants": [statement] if statement else ["(statement vide dans la lecon source -- a completer avant promotion)"],
        "proof_of_use": None,
        "tier": "candidate",
        "path": None,
        "sha256": None,
        "tests": None,
        "advisory_only": True,
        "affordances": {},
    }


# =====================================================================================
# --generate : lessons.jsonl (validated, sans proposition existante) -> YAML proposees
# =====================================================================================

def generate_proposals(
    *, kb_root: Path | None = None, lessons_path: Path | None = None, force: bool = False,
) -> dict[str, list[str]]:
    """Ecrit UNE proposition YAML par lecon `status==validated` (fold_lessons =
    deja replie sur le dernier evenement par lesson_id) sans proposition deja
    presente sur disque. Idempotent : relancer sans `force` ne duplique rien
    (skip silencieux, jamais un ecrasement d'une decision Pierre deja actee dans
    le fichier existant — APPLIQUEE/REJETEE compris)."""
    _require_yaml()
    kb_root = kb_root or DEFAULT_KB_ROOT
    lessons_path = lessons_path or DEFAULT_LESSONS_PATH
    proposals_dir = _proposals_dir(kb_root)
    proposals_dir.mkdir(parents=True, exist_ok=True)

    folded = fold_lessons(lessons_path)
    result: dict[str, list[str]] = {
        "generated": [], "skipped_existing": [], "skipped_not_validated": [],
    }

    for lesson_id, lesson in sorted(folded.items()):
        if lesson.get("status") != LESSON_STATUS_VALIDATED:
            result["skipped_not_validated"].append(lesson_id)
            continue

        out_path = _proposal_path(kb_root, lesson_id)
        if out_path.exists() and not force:
            result["skipped_existing"].append(lesson_id)
            continue

        record = {
            "schema": PROPOSAL_SCHEMA,
            "status": PROPOSAL_STATUS_PROPOSED,
            "lesson_id": lesson_id,
            "statement": lesson.get("statement", ""),
            "entree_catalogue_proposee": _lesson_to_pattern_entry(lesson),
            "provenance": {
                "lessons_source": "EVIDENCE/reports/lessons.jsonl",
                "supporting_runs": list(lesson.get("supporting_runs") or []),
                "drift_source": "lecon_routee_sans_consommateur (Observer)",
                "genere_le": _now_iso(),
                "genere_par": "kb_proposal.py --generate",
            },
            "ratification": {
                "decideur": "Pierre",
                "statut": "EN_ATTENTE",
            },
        }
        _write_yaml(out_path, record)
        result["generated"].append(lesson_id)
        logger.info("proposition KB generee -> %s", out_path)

    return result


# =====================================================================================
# --list : lecture seule des propositions
# =====================================================================================

def list_proposals(*, kb_root: Path | None = None) -> list[dict]:
    """Toutes les propositions presentes sous <kb_root>/proposals/, lues telles
    quelles (pas de filtrage par statut — c'est l'affichage qui trie)."""
    _require_yaml()
    kb_root = kb_root or DEFAULT_KB_ROOT
    proposals_dir = _proposals_dir(kb_root)
    out: list[dict] = []
    if not proposals_dir.exists():
        return out
    for path in sorted(proposals_dir.glob("*.yaml")):
        try:
            data = _read_yaml(path)
        except (OSError, yaml.YAMLError) as exc:  # type: ignore[union-attr]
            out.append({"lesson_id": path.stem, "status": "ILLISIBLE", "statement": str(exc), "path": str(path)})
            continue
        out.append({
            "lesson_id": data.get("lesson_id", path.stem),
            "status": data.get("status", "?"),
            "statement": data.get("statement", ""),
            "path": str(path),
        })
    return out


def format_proposal_list(proposals: list[dict]) -> str:
    """Rendu texte deterministe, trie par lesson_id."""
    if not proposals:
        return "Aucune proposition dans knowledge_base/proposals/."
    lines = []
    for p in sorted(proposals, key=lambda p: p["lesson_id"]):
        statement = (p.get("statement") or "")[:100]
        lines.append(f"[{p['status']:>10}] {p['lesson_id']} -- {statement}")
    return "\n".join(lines)


# =====================================================================================
# --apply / --reject : les SEULS points d'ecriture du catalogue ou d'une proposition.
# Geste MANUEL uniquement — jamais appele par un autre module de ce depot.
# =====================================================================================

def _load_catalog(catalog_path: Path) -> dict:
    with open(catalog_path, encoding="utf-8") as fh:
        return json.load(fh)


def _write_catalog_atomic(catalog_path: Path, catalog: dict) -> None:
    """Ecriture atomique : fichier temporaire dans le MEME dossier puis rename —
    jamais de catalog.json partiellement ecrit visible par un autre lecteur."""
    tmp_path = catalog_path.parent / f"{catalog_path.name}.tmp-{int(time.time() * 1000)}"
    with open(tmp_path, "w", encoding="utf-8") as fh:
        json.dump(catalog, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    tmp_path.replace(catalog_path)


def _restore_catalog_from_backup(catalog_path: Path, backup_path: Path) -> None:
    """Restauration ATOMIQUE (meme patron que l'ecriture) depuis le backup."""
    tmp_path = catalog_path.parent / f"{catalog_path.name}.restore-{int(time.time() * 1000)}"
    shutil.copy2(backup_path, tmp_path)
    tmp_path.replace(catalog_path)


def _run_kb_validate(catalog_path: Path) -> tuple[bool, str]:
    """Execute le VRAI validateur (knowledge_base/kb-validate.mjs du depot, jamais
    une copie/maquette) sur `catalog_path`. Renvoie (ok, sortie stdout+stderr).
    Best-effort si `node` ou le script sont introuvables : ne bloque pas
    --apply (best-effort documente), mais le signale clairement dans la sortie."""
    if not KB_VALIDATE_SCRIPT.exists():
        return True, f"(kb-validate.mjs introuvable a {KB_VALIDATE_SCRIPT} -- validation ignoree, best-effort)"
    try:
        proc = subprocess.run(
            ["node", str(KB_VALIDATE_SCRIPT), str(catalog_path)],
            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=60,
        )
    except FileNotFoundError:
        return True, "('node' introuvable sur PATH -- validation ignoree, best-effort)"
    except subprocess.TimeoutExpired as exc:
        return False, f"kb-validate.mjs: timeout ({exc})"
    output = ((proc.stdout or "") + (proc.stderr or "")).strip()
    return proc.returncode == 0, output


def apply_proposal(lesson_id: str, *, ratifie_par: str, kb_root: Path | None = None) -> dict:
    """--apply : verifie PROPOSED -> backup -> insertion -> ecriture atomique du
    catalogue -> proposition marquee APPLIQUEE -> execution de kb-validate.mjs.

    Si le validateur echoue : RESTAURE le catalogue depuis le backup et remet la
    proposition a PROPOSED avec l'erreur du validateur consignee dans
    `ratification.erreur` — le catalogue ne reste jamais dans un etat que son
    propre validateur rejette, et la proposition ne reste jamais marquee
    APPLIQUEE si l'application a ete defaite.

    `ratifie_par` est un parametre REQUIS (jamais de defaut) : ce module ne
    devine jamais qui a autorise l'ecriture.
    """
    _require_yaml()
    if not ratifie_par:
        raise ValueError("ratifie_par est requis pour --apply (jamais de defaut implicite)")
    kb_root = kb_root or DEFAULT_KB_ROOT

    proposal_path = _proposal_path(kb_root, lesson_id)
    if not proposal_path.exists():
        raise ValueError(f"aucune proposition pour lesson_id={lesson_id!r} ({proposal_path})")
    proposal = _read_yaml(proposal_path)
    if proposal.get("status") != PROPOSAL_STATUS_PROPOSED:
        raise ValueError(
            f"proposition {lesson_id!r} n'est pas PROPOSED (statut actuel: {proposal.get('status')!r})"
        )

    catalog_path = _catalog_path(kb_root)
    if not catalog_path.exists():
        raise ValueError(f"catalogue introuvable: {catalog_path}")
    catalog = _load_catalog(catalog_path)

    entry = proposal.get("entree_catalogue_proposee")
    if not isinstance(entry, dict):
        raise ValueError(f"proposition {lesson_id!r}: 'entree_catalogue_proposee' absente ou invalide")

    new_id = entry.get("brick_id") or entry.get("asset_id") or entry.get("role_id")
    existing_ids = {
        e.get("brick_id") or e.get("asset_id") or e.get("role_id") for e in catalog.get("entries", [])
    }
    if new_id in existing_ids:
        raise ValueError(f"id deja present dans le catalogue: {new_id!r} — pas de doublon insere")

    backup_path = catalog_path.with_name(f"{catalog_path.name}.bak-{int(time.time())}")
    shutil.copy2(catalog_path, backup_path)
    logger.info("backup du catalogue -> %s", backup_path)

    catalog.setdefault("entries", []).append(entry)
    _write_catalog_atomic(catalog_path, catalog)

    proposal["status"] = PROPOSAL_STATUS_APPLIED
    ratification = proposal.setdefault("ratification", {})
    ratification["statut"] = "APPLIQUEE"
    ratification["decideur"] = ratifie_par
    ratification["date"] = _now_iso()
    ratification.pop("erreur", None)
    _write_yaml(proposal_path, proposal)

    ok, output = _run_kb_validate(catalog_path)
    if not ok:
        _restore_catalog_from_backup(catalog_path, backup_path)
        proposal["status"] = PROPOSAL_STATUS_PROPOSED
        ratification = proposal.setdefault("ratification", {})
        ratification["statut"] = "EN_ATTENTE"
        ratification.pop("date", None)
        ratification["erreur"] = output[-4000:]
        _write_yaml(proposal_path, proposal)
        logger.warning("kb-validate.mjs a rejete %r apres application -- catalogue restaure", new_id)
        return {
            "ok": False, "lesson_id": lesson_id, "brick_id": new_id,
            "backup_path": str(backup_path), "validator_output": output,
            "message": (
                "kb-validate.mjs a REJETE le catalogue apres insertion -- "
                "catalogue restaure depuis le backup, proposition remise PROPOSED."
            ),
        }

    return {
        "ok": True, "lesson_id": lesson_id, "brick_id": new_id,
        "backup_path": str(backup_path), "validator_output": output,
        "message": "entree appliquee au catalogue, backup conserve, kb-validate.mjs: PASS.",
    }


def reject_proposal(lesson_id: str, *, raison: str, kb_root: Path | None = None) -> dict:
    """--reject : marque une proposition PROPOSED comme REJETEE, avec sa raison.
    N'ecrit jamais le catalogue (aucune entree n'a ete inseree pour une proposition
    rejetee)."""
    _require_yaml()
    if not raison:
        raise ValueError("raison est requise pour --reject (jamais de defaut implicite)")
    kb_root = kb_root or DEFAULT_KB_ROOT

    proposal_path = _proposal_path(kb_root, lesson_id)
    if not proposal_path.exists():
        raise ValueError(f"aucune proposition pour lesson_id={lesson_id!r} ({proposal_path})")
    proposal = _read_yaml(proposal_path)
    if proposal.get("status") != PROPOSAL_STATUS_PROPOSED:
        raise ValueError(
            f"proposition {lesson_id!r} n'est pas PROPOSED (statut actuel: {proposal.get('status')!r})"
        )

    proposal["status"] = PROPOSAL_STATUS_REJECTED
    ratification = proposal.setdefault("ratification", {})
    ratification["statut"] = "REJETEE"
    ratification["decideur"] = "Pierre"
    ratification["date"] = _now_iso()
    ratification["raison"] = raison
    _write_yaml(proposal_path, proposal)
    logger.info("proposition %s -> REJETEE (%s)", lesson_id, raison)
    return {"lesson_id": lesson_id, "status": PROPOSAL_STATUS_REJECTED, "raison": raison}


# =====================================================================================
# CLI
# =====================================================================================

def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "kb_proposal — Lesson validee (EVIDENCE/reports/lessons.jsonl) -> proposition KB "
            "-> (geste manuel Pierre) application a knowledge_base/catalog.json. "
            "La machine propose et prouve, l'humain tranche et signe."
        )
    )
    parser.add_argument(
        "--kb-root", type=Path, default=None,
        help=f"racine knowledge_base (defaut: {DEFAULT_KB_ROOT}) -- seam de test (copie hors depot)",
    )
    parser.add_argument(
        "--lessons-path", type=Path, default=None,
        help=f"chemin lessons.jsonl (defaut: {DEFAULT_LESSONS_PATH})",
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--generate", action="store_true", help="genere les propositions KB manquantes")
    group.add_argument("--list", action="store_true", help="liste les propositions existantes")
    group.add_argument("--apply", metavar="LESSON_ID", help="applique une proposition PROPOSED au catalogue")
    group.add_argument("--reject", metavar="LESSON_ID", help="rejette une proposition PROPOSED")
    parser.add_argument("--force", action="store_true", help="--generate: recree une proposition deja presente")
    parser.add_argument("--ratifie-par", default=None, help="requis avec --apply : nom du decideur humain")
    parser.add_argument("--raison", default=None, help="requis avec --reject : raison du rejet")
    return parser


def main(argv: list[str] | None = None) -> int:
    """Meme contrat que les autres CLI Forge (`studio_link.main`,
    `learning_memory.main`) : `_harden_streams()` en premier (console Windows
    cp1252 — incident deja rencontre dans ce depot), jamais de trace Python nue,
    toujours un int en retour."""
    _harden_streams()
    parser = _build_parser()
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:
        return exc.code if isinstance(exc.code, int) else 2

    if yaml is None:
        print(f"erreur: PyYAML manquant ({_YAML_IMPORT_ERROR})", file=sys.stderr)
        return 2

    if args.generate:
        result = generate_proposals(kb_root=args.kb_root, lessons_path=args.lessons_path, force=args.force)
        print(f"generees: {len(result['generated'])} {result['generated']}")
        print(f"deja presentes (ignorees): {len(result['skipped_existing'])} {result['skipped_existing']}")
        print(f"candidates ignorees (non validees): {len(result['skipped_not_validated'])} {result['skipped_not_validated']}")
        return 0

    if args.list:
        print(format_proposal_list(list_proposals(kb_root=args.kb_root)))
        return 0

    if args.apply:
        if not args.ratifie_par:
            print('erreur: --apply exige --ratifie-par "<nom>"', file=sys.stderr)
            return 2
        try:
            result = apply_proposal(args.apply, ratifie_par=args.ratifie_par, kb_root=args.kb_root)
        except ValueError as exc:
            print(f"erreur: {exc}", file=sys.stderr)
            return 2
        print(result["message"])
        print(f"backup: {result['backup_path']}")
        if result["validator_output"]:
            print(result["validator_output"])
        return 0 if result["ok"] else 1

    if args.reject:
        if not args.raison:
            print('erreur: --reject exige --raison "..."', file=sys.stderr)
            return 2
        try:
            result = reject_proposal(args.reject, raison=args.raison, kb_root=args.kb_root)
        except ValueError as exc:
            print(f"erreur: {exc}", file=sys.stderr)
            return 2
        print(f"proposition {result['lesson_id']} -> REJETEE ({result['raison']})")
        return 0

    parser.print_usage(sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
