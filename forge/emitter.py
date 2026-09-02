"""Émetteur de notifications — décision E, ratifiée Pierre 2026-09-02 (sas 2).

Le geste d'émission fait DEUX écritures distinctes, jamais confondues :

  1. LE MESSAGE   -> le JOURNAL, hors run_dir          (`forge.amendment_log`, J1)
     ce qui a été décidé — append-only, transversal, une seule fois.
  2. L'ITEM       -> `knowledge_trace.json`, DANS le run_dir   (`knowledge_trace.mjs`)
     à qui on l'a opposé — un item par capacité effectivement convoquée.

Les séparer est ce qui rend l'acquittement vérifiable : le premier dit *ce qui a été
décidé*, le second *à qui*. Si le message vivait dans le run_dir, sa référence s'y
trouverait par construction et `--verify` rendrait un `FOUND` qui ne prouve rien (F-1).

QUI ÉMET : l'orchestrateur (Fable), jamais un outil autonome — contrainte C3 du cadre
`KNOWLEDGE_RESOLVER_V1`. Ce module fournit le GESTE ; il ne le déclenche pas. Aucun
daemon, aucun watcher, aucun appel implicite depuis le driver.

ADVISORY : rien ici ne lit ni ne modifie un `software_verdict`, un `verdict.json` signé,
ni le comportement de `verify_run` / `gate.py` / `verdict.py`. Depuis la décision N-2,
`knowledge_trace` est de toute façon advisory. NO_CLAIM_ALLOWED.

DEUX CHOIX DE CONCEPTION, explicites parce qu'ils auraient pu être faits autrement :

* `source: "mandatory_read"`. `ALLOWED_SOURCES` est un enum FERMÉ de la sonde
  (`premortem` / `knowledge_base` / `mandatory_read` / `packet`) et ne contient pas
  "amendment". Plutôt que d'élargir la sonde — qui n'est pas dans le périmètre de E —
  l'émetteur emprunte le canal par lequel la notification atteint réellement une
  capacité : son `mandatory_read` (résolution Q4 du sas 1, « N2 + mandatory_read »).
  Aucune modification de `knowledge_trace.mjs`. Si un jour un type de source propre est
  jugé nécessaire, c'est une décision de schéma distincte.

* MERGE, jamais écrasement. `writeTrace` réécrit le fichier ENTIER (`writeFileSync`) :
  une seconde notification dans le même run effacerait la première. L'émetteur relit
  donc la trace existante et écrit l'UNION dédupliquée. La sonde reste inchangée ; c'est
  l'appelant qui porte la discipline non destructive (C1). Une trace existante illisible
  fait ÉCHOUER l'écriture au lieu de l'écraser — on ne détruit jamais une preuve qu'on
  ne sait pas relire.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
from pathlib import Path

from forge.amendment_log import (
    AmendmentLogError,
    append_message,
    validate_message,
)

REPO_ROOT = Path(__file__).resolve().parents[1]
_TRACE_SCRIPT = Path(__file__).resolve().parent / "knowledge_trace.mjs"
TRACE_FILENAME = "knowledge_trace.json"
_TIMEOUT_S = 60

# Canal réel par lequel une notification atteint une capacité (Q4, sas 1).
TRACE_SOURCE = "mandatory_read"

# Provenance de l'item, par type de message. Un amendement est ratifié par un humain ;
# une question et une objection restent advisory tant que personne ne les a tranchées.
PROVENANCE_BY_TYPE = {
    "amendment": "HUMAN_RATIFIED",
    "objection": "ADVISORY",
    "question": "ADVISORY",
}


class EmitterError(Exception):
    """Émission refusée. Voir le message : il dit ce qui a été écrit, et ce qui ne l'a pas été."""


def _item_key(item: dict) -> tuple:
    return (item.get("source"), item.get("ref"), item.get("reason"))


def build_trace_items(message: dict, capabilities: list[str] | None = None) -> list[dict]:
    """Un item de trace par capacité destinataire. Aucune écriture.

    `reason` porte la capacité visée : le schéma d'item n'a pas de champ pour elle, et
    c'est le seul endroit où l'inscrire sans toucher la sonde.
    """
    targets = list(capabilities if capabilities is not None else message.get("to", []))
    provenance = PROVENANCE_BY_TYPE.get(message.get("type"), "ADVISORY")
    return [
        {
            "source": TRACE_SOURCE,
            "ref": message["id"],
            "provenance": provenance,
            "valid_as_of": message["issued_at"],
            "reason": f"notification {message.get('type')} -> {capability} : {message.get('subject')}",
        }
        for capability in targets
    ]


def read_existing_items(run_dir: Path) -> list[dict]:
    """Items déjà présents dans la trace du run. Absente => []. ILLISIBLE => lève.

    Ne jamais rendre `[]` sur un fichier corrompu : l'appelant écrirait alors l'union
    d'une trace vide et effacerait des items qu'il n'a pas su lire.
    """
    path = Path(run_dir) / TRACE_FILENAME
    if not path.exists():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise EmitterError(
            f"trace existante illisible ({path}) : {exc} — écriture REFUSÉE plutôt que "
            "d'écraser une preuve qu'on ne sait pas relire"
        ) from exc
    items = data.get("items") if isinstance(data, dict) else None
    return [i for i in items if isinstance(i, dict)] if isinstance(items, list) else []


def write_trace_items(run_dir: Path, items: list[dict], run_id: str | None = None) -> dict:
    """Écrit l'UNION dédupliquée (existants + nouveaux) via `knowledge_trace.mjs write`.

    Idempotent : réémettre les mêmes items ne les duplique pas et n'en perd aucun. La
    validation de schéma reste celle de la sonde (`validateTraceItems`) — invalide, rien
    n'est écrit. `node` indisponible n'est JAMAIS travesti en écriture réussie.
    """
    run_dir = Path(run_dir)
    existing = read_existing_items(run_dir)
    merged = list(existing)
    seen = {_item_key(i) for i in existing}
    added = 0
    for item in items:
        key = _item_key(item)
        if key in seen:
            continue
        seen.add(key)
        merged.append(item)
        added += 1

    payload = {"items": merged}
    if run_id:
        payload["run_id"] = run_id

    node_cmd = shutil.which("node")
    if node_cmd is None:
        raise EmitterError(
            "node indisponible — la trace n'a PAS été écrite. Le journal, lui, peut "
            "l'avoir été : voir la valeur retournée par `notify`."
        )

    tmp = Path(tempfile.mkdtemp(prefix="forge_emitter_")) / "items.json"
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    try:
        proc = subprocess.run(
            [node_cmd, str(_TRACE_SCRIPT), "write", str(run_dir.resolve()), str(tmp)],
            capture_output=True, text=True, encoding="utf-8", timeout=_TIMEOUT_S,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise EmitterError(f"knowledge_trace.mjs write non exécutable : {exc}") from exc
    finally:
        try:
            tmp.unlink()
            tmp.parent.rmdir()
        except OSError:
            pass

    if proc.returncode != 0:
        detail = "\n".join(p for p in (proc.stderr, proc.stdout) if p).strip()
        raise EmitterError(f"knowledge_trace.mjs write a échoué (exit {proc.returncode}) : {detail[-2000:]}")

    return {
        "trace_path": str(run_dir / TRACE_FILENAME),
        "items_total": len(merged),
        "items_added": added,
        "items_preserved": len(existing),
    }


def notify(
    message: dict,
    run_dir: Path | str,
    capabilities: list[str] | None = None,
    *,
    journal_dir: Path | None = None,
    run_id: str | None = None,
) -> dict:
    """LE geste d'émission : message -> journal, puis items -> trace du run.

    ORDRE, et il est délibéré : le journal D'ABORD. Le journal EST l'entrée, la trace en
    DÉRIVE (C1, recomputable). Si l'écriture de la trace échoue ensuite, le message reste
    au journal — on ne le retire pas : append-only vaut aussi quand la suite se passe mal.
    Le résultat dit alors exactement ce qui a été écrit et ce qui ne l'a pas été, et
    `write_trace_items` peut être rappelé seul pour finir le geste (il est idempotent).

    Refuse AVANT toute écriture : un message invalide, ou une liste de destinataires vide.
    """
    problems = validate_message(message)
    if problems:
        raise EmitterError("message refusé, rien n'a été écrit : " + " ; ".join(problems))

    targets = list(capabilities if capabilities is not None else message.get("to", []))
    if not targets:
        raise EmitterError(
            "aucune capacité destinataire — rien n'a été écrit. Une notification sans "
            "destinataire convoqué n'a rien à prouver."
        )

    try:
        journal = append_message(message, journal_dir=journal_dir)
    except AmendmentLogError as exc:
        raise EmitterError(f"journal refusé, rien n'a été écrit : {exc}") from exc

    items = build_trace_items(message, targets)
    try:
        trace = write_trace_items(run_dir, items, run_id=run_id)
    except EmitterError as exc:
        raise EmitterError(
            f"message ÉCRIT au journal ({journal}), trace NON écrite : {exc}"
        ) from exc

    return {
        "journal_path": str(journal),
        "message_id": message["id"],
        "notified": targets,
        **trace,
    }
