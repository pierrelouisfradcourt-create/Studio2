"""Journal d'amendements / notifications — décision J1, ratifiée Pierre 2026-09-02.

CE QUE CE MODULE REMPLACE (règle anti-couches C2 de `KNOWLEDGE_RESOLVER_V1` : aucun
nouveau composant s'il ne remplace pas explicitement plusieurs composants existants) :

  design_questions.json    un fichier PAR RUN, aucun lecteur transversal  -> type "question"
  objections des verdicts  conservées, mais en fin de chaîne seulement    -> type "objection"
  amendements              AUCUN canal n'existait                         -> type "amendment"

Le journal unifie deux canaux qui s'ignorent et en absorbe un troisième qui n'existait
pas. C2 est satisfaite par consolidation, pas par exception.

EMPLACEMENT — c'est le coeur de J1, et ce n'est pas un détail de rangement.
Le journal est écrit HORS de tout `run_dir`. S'il y était, la référence d'un message
s'y trouverait PAR CONSTRUCTION, et `knowledge_trace.mjs --verify` — qui balaie
récursivement le run_dir — rendrait un `FOUND` qui ne prouverait rien (faux positif
F-1). L'acquittement doit prouver que la capacité a incorporé la référence dans SA
PROPRE PRODUCTION, jamais qu'un journal la contient.

Ce que J1 NE ferme PAS : F-2, le prompt. La référence apparaîtra toujours dans
`context/prompt_<etape>_a<n>.txt`, qui est dans le corpus du run. Seule la règle
d'acquittement du sas 1 (la ref doit être dans l'artefact DÉSIGNÉ — cf.
`contract.consumption_evidence`) le ferme.

QUI ÉCRIT : l'orchestrateur, jamais un outil autonome (contrainte C3 du cadre ratifié :
« hors V1 : toute écriture par l'outillage »). Ce module fournit le GESTE, il ne le
déclenche pas — aucun daemon, aucun watcher, aucune écriture spontanée.

RASOIR C1, ligne à ligne : déterministe (un message, un `id`, aucun calcul) ·
recomputable (le journal EST l'entrée) · append-only et non destructif (une objection
rejetée est CONSERVÉE, jamais effacée) · non liant (il transporte, il ne fait pas
doctrine).

ADVISORY : rien ici ne lit ni ne modifie un `software_verdict`, un `verdict.json`
signé, ni le comportement de `verify_run` / `gate.py` / `verdict.py`.
NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]

# Surface EVIDENCE du dépôt (V2 : `EVIDENCE/amendments/`). Hors `EVIDENCE/runs/`,
# donc hors du corpus balayé par `knowledge_trace.mjs --verify` — c'est la garantie
# d'emplacement exigée par J1.
JOURNAL_DIR = REPO_ROOT / "EVIDENCE" / "amendments"
JOURNAL_NAME = "journal.jsonl"

# Zone dont le journal doit rester DEHORS. Symétrique de la garde de `writeTrace`,
# qui refuse d'écrire la trace hors de cette même zone : deux fichiers, deux zones,
# jamais la même.
RUNS_ZONE = REPO_ROOT / "EVIDENCE" / "runs"

MESSAGE_TYPES = ("question", "objection", "amendment")

_REQUIRED_STR = ("id", "type", "from", "subject", "reason", "issued_at")
_REQUIRED_LIST = ("to",)
_OPTIONAL_LIST = ("impact", "evidence_ref")


class AmendmentLogError(Exception):
    """Message refusé, ou emplacement interdit. Rien n'a été écrit."""


def journal_path(journal_dir: Path | None = None) -> Path:
    return (Path(journal_dir) if journal_dir is not None else JOURNAL_DIR) / JOURNAL_NAME


def _is_inside_runs_zone(directory: Path) -> bool:
    try:
        Path(directory).resolve().relative_to(RUNS_ZONE.resolve())
    except (ValueError, OSError):
        return False
    return True


def validate_message(message: object) -> list[str]:
    """Liste les problèmes d'un message. Vide = recevable. Ne lève jamais.

    Schéma (spécification du sas 2, section 1) :
      {id, type, from, to[], subject, reason, impact[], evidence_ref[], blocking, issued_at}
    """
    problems: list[str] = []
    if not isinstance(message, dict):
        return [f"message n'est pas un objet ({type(message).__name__})"]
    for field in _REQUIRED_STR:
        value = message.get(field)
        if not isinstance(value, str) or not value.strip():
            problems.append(f"{field!r} manquant ou vide (chaîne non vide attendue)")
    mtype = message.get("type")
    if isinstance(mtype, str) and mtype not in MESSAGE_TYPES:
        problems.append(f"type {mtype!r} inconnu (attendu : {', '.join(MESSAGE_TYPES)})")
    for field in _REQUIRED_LIST:
        value = message.get(field)
        if not isinstance(value, (list, tuple)) or not value:
            problems.append(f"{field!r} doit être une liste non vide de destinataires")
        elif not all(isinstance(x, str) and x.strip() for x in value):
            problems.append(f"{field!r} contient une entrée vide ou non textuelle")
    for field in _OPTIONAL_LIST:
        value = message.get(field)
        if value is not None and (
            not isinstance(value, (list, tuple))
            or not all(isinstance(x, str) for x in value)
        ):
            problems.append(f"{field!r} présent mais n'est pas une liste de chaînes")
    blocking = message.get("blocking")
    if blocking is not None and not isinstance(blocking, bool):
        problems.append("'blocking' présent mais n'est pas un booléen")
    return problems


def read_messages(journal_dir: Path | None = None) -> list[dict]:
    """Lit le journal. Absent => []. Une ligne illisible est IGNORÉE, jamais effacée
    ni corrigée : append-only vaut aussi pour ce qui est mal formé."""
    path = journal_path(journal_dir)
    if not path.exists():
        return []
    messages: list[dict] = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                item = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(item, dict):
                messages.append(item)
    return messages


def append_message(message: dict, journal_dir: Path | None = None) -> Path:
    """Ajoute UN message au journal. Append-only. Retourne le chemin du journal.

    Refuse — et n'écrit alors RIEN, même discipline que `validateTraceItems` :
      - un message qui ne valide pas le schéma ;
      - un `id` déjà présent (append-only n'autorise pas la réécriture d'une entrée) ;
      - un emplacement situé sous `EVIDENCE/runs/` (le journal DANS le corpus d'un
        run fabriquerait un faux `FOUND` — c'est précisément ce que J1 empêche).
    """
    problems = validate_message(message)
    if problems:
        raise AmendmentLogError("message refusé : " + " ; ".join(problems))

    directory = Path(journal_dir) if journal_dir is not None else JOURNAL_DIR
    if _is_inside_runs_zone(directory):
        raise AmendmentLogError(
            f"emplacement interdit : {directory} est sous {RUNS_ZONE} — le journal doit "
            "rester HORS du corpus d'un run (J1), sinon la référence d'un message y serait "
            "trouvée par construction et l'acquittement ne prouverait rien"
        )

    existing = {m.get("id") for m in read_messages(directory)}
    if message["id"] in existing:
        raise AmendmentLogError(
            f"id {message['id']!r} déjà présent — le journal est append-only : "
            "émettre un nouveau message, jamais réécrire une entrée"
        )

    entry = dict(message)
    entry.setdefault("impact", [])
    entry.setdefault("evidence_ref", [])
    entry.setdefault("blocking", False)

    directory.mkdir(parents=True, exist_ok=True)
    path = directory / JOURNAL_NAME
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(entry, ensure_ascii=False, sort_keys=True) + "\n")
    return path


def new_message_id(subject: str, issued_at: str | None = None) -> str:
    """Identifiant déterministe et lisible : `AMD-<horodatage>-<sujet>`. Aucun hasard,
    aucun compteur d'état — C1 (déterministe, recomputable)."""
    stamp = (issued_at or datetime.now(timezone.utc).isoformat()).replace(":", "").replace("-", "")
    stamp = stamp.split(".")[0].replace("+0000", "Z")
    slug = "".join(c if c.isalnum() else "-" for c in subject.strip().lower()).strip("-")
    slug = "-".join(part for part in slug.split("-") if part)[:48]
    return f"AMD-{stamp}-{slug}" if slug else f"AMD-{stamp}"
