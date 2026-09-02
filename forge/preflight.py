"""forge/preflight.py — pre-vol MECANIQUE avant le premier dispatch LLM
d'une campagne Forge.

Consommateur naturel de la lecon KB ratifiee `pat-forge-preflight_oracle_registration`
(lesson_id `forge.preflight_oracle_registration`, EVIDENCE/reports/lessons.jsonl, statut
validated) : l'enregistrement d'un projet dans `forge/oracles.json` est un
prerequis MECANIQUEMENT VERIFIABLE avant tout appel LLM, mais rien ne le verifiait au
lancement -- son absence n'etait visible qu'a s10a, apres un build complet (un builder
entier pouvait tourner pour rien, cf. breakout_v2-run1-20260731-082705).

Deux garanties, dans cet ordre de priorite :

1. La garde PROTEGE TOUJOURS -- meme si la KB (`knowledge_base/search.mjs`) est
   injoignable ou si l'entree n'y figure plus. Une garde qui dependrait de la
   disponibilite de sa propre documentation ne serait pas une garde. Dans ce cas
   `justification_source` vaut `NOT_OBSERVABLE`, avec sa raison exacte.
2. Quand l'entree EST trouvee, elle est citee (brick_id + enonce tronque) dans la
   justification -- c'est la CONSOMMATION VISIBLE, mecanique, jamais manuelle : la
   KB est interrogee par un vrai sous-processus `node knowledge_base/search.mjs`
   (le meme moteur que n'importe quel autre consommateur), ce qui laisse une trace
   dans `knowledge_base/search_log.jsonl` -- la preuve que ce pre-vol a reellement
   consulte la bibliotheque, pas seulement cite son id en dur.

La regle elle-meme (le projet doit etre resoluble dans la config d'oracle) reutilise
`forge.oracle.resolve_oracle` -- elle n'est JAMAIS reimplementee ici.

claim_verdict: NO_CLAIM_ALLOWED -- ce module ne produit aucun claim, il verifie un
prerequis mecanique et rapporte honnetement ce qu'il a observe.
"""
from __future__ import annotations

import json
import logging
import subprocess
from pathlib import Path

from forge.oracle import DEFAULT_CONFIG as DEFAULT_ORACLE_CONFIG
from forge.oracle import OracleNotFound, resolve_oracle

logger = logging.getLogger(__name__)

# forge/preflight.py -> parents[2] == repo root (meme convention que
# forge.oracle / forge.run_real).
REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SEARCH_SCRIPT = REPO_ROOT / "knowledge_base" / "search.mjs"

# Identite STABLE de la lecon/brique consommee ici. LESSON_SLUG est incorpore
# LITTERALEMENT dans l'intention de recherche ci-dessous : search.mjs tokenise sa
# propre indexation, mais la chaine BRUTE `query` qu'il journalise dans
# search_log.jsonl conserve le texte tel quel -- c'est l'identifiant reconnaissable
# que scripts/observer/command.py cherche pour relier une ligne de log a CETTE
# lecon (search_log.jsonl ne porte ni lesson_id ni brick_id, seulement
# {query, matchCount, ts} : ce slug litteral est le lien minimal honnete). Ne pas
# renommer l'un sans l'autre.
LESSON_SLUG = "preflight_oracle_registration"
LESSON_BRICK_ID = "pat-forge-preflight_oracle_registration"

_SEARCH_INTENTION = (
    f"{LESSON_SLUG} enregistrement du projet dans oracles.json prerequis "
    "mecanique avant le premier dispatch LLM d'une campagne"
)

_SEARCH_TIMEOUT_S = 30.0


def _consult_kb(search_script: Path) -> dict:
    """Interroge REELLEMENT la KB par sous-processus (`node <search_script> ... --json`)
    -- jamais une lecture directe de catalog.json, qui court-circuiterait le moteur et
    donc la trace dans search_log.jsonl (la preuve de consultation).

    Retourne TOUJOURS {reachable, brick_id, statement, raw_error} :
      - reachable=False  : la KB n'a pas pu etre consultee (node absent, script
        absent, sortie non-JSON, timeout, code de sortie >=2 -- cf. search.mjs
        docstring : 0/1 sont des reponses VALIDES, seul >=2 est une panne).
      - reachable=True, brick_id=None : la KB a repondu mais LESSON_BRICK_ID n'est
        pas dans les resultats (catalogue perime, ou intention mal formee).
      - reachable=True, brick_id=LESSON_BRICK_ID : la brique a ete trouvee et citee.

    Jamais d'exception : toute panne inattendue (OSError, JSON invalide...) est
    interceptee et rendue comme reachable=False avec sa raison exacte -- un capteur
    qui casserait la garde qu'il sert d'evidence rendrait la garde elle-meme fragile."""
    if not search_script.exists():
        return {"reachable": False, "brick_id": None, "statement": None,
                "raw_error": f"script de recherche KB introuvable: {search_script}"}
    try:
        proc = subprocess.run(
            ["node", str(search_script), _SEARCH_INTENTION, "--json"],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
            timeout=_SEARCH_TIMEOUT_S,
        )
    except FileNotFoundError:
        return {"reachable": False, "brick_id": None, "statement": None,
                "raw_error": "'node' introuvable sur PATH"}
    except subprocess.TimeoutExpired:
        return {"reachable": False, "brick_id": None, "statement": None,
                "raw_error": f"recherche KB: timeout apres {_SEARCH_TIMEOUT_S:.0f}s"}
    except OSError as exc:
        return {"reachable": False, "brick_id": None, "statement": None,
                "raw_error": f"recherche KB: erreur systeme ({exc})"}
    if proc.returncode not in (0, 1):
        return {"reachable": False, "brick_id": None, "statement": None,
                "raw_error": f"search.mjs returncode={proc.returncode}: "
                             f"{proc.stderr.strip()[-500:]}"}
    try:
        data = json.loads(proc.stdout)
    except ValueError:
        return {"reachable": False, "brick_id": None, "statement": None,
                "raw_error": f"sortie search.mjs non-JSON: {proc.stdout.strip()[-500:]}"}
    if not isinstance(data, dict):
        return {"reachable": False, "brick_id": None, "statement": None,
                "raw_error": "sortie search.mjs: JSON valide mais pas un objet"}
    for result in data.get("results") or []:
        if not isinstance(result, dict):
            continue
        entry = result.get("entry") or {}
        if isinstance(entry, dict) and entry.get("brick_id") == LESSON_BRICK_ID:
            statement = str(entry.get("function") or "").strip()
            return {"reachable": True, "brick_id": LESSON_BRICK_ID,
                    "statement": statement, "raw_error": None}
    return {"reachable": True, "brick_id": None, "statement": None, "raw_error": None}


def _resolve_oracle_status(project: str, oracle_config_path: Path | None) -> tuple[bool, str | None]:
    """(oracle_resolu, raison_echec) -- reutilise forge.oracle.resolve_oracle SANS la
    reimplementer. Toute panne de resolution (projet absent, config illisible/invalide)
    devient un echec de pre-vol honnete plutot qu'une exception qui remonterait crue."""
    try:
        resolve_oracle(project, config_path=oracle_config_path)
        return True, None
    except OracleNotFound as exc:
        return False, str(exc)
    except (OSError, ValueError) as exc:
        config = oracle_config_path or DEFAULT_ORACLE_CONFIG
        return False, f"config d'oracle illisible ou invalide ({config}): {exc}"


def preflight_campagne(
    project: str,
    oracle_config_path: Path | None = None,
    repo_root: Path | None = None,
    *,
    search_script: Path | None = None,
) -> dict:
    """Pre-vol MECANIQUE a appeler AVANT le premier dispatch LLM d'une campagne.

    Applique la regle de la lecon consommee ici : le projet doit etre resoluble dans
    la config d'oracle (reutilise `forge.oracle.resolve_oracle`) AVANT toute depense
    LLM -- sinon un builder entier peut tourner pour rien (visible seulement a s10a,
    apres coup). Consulte REELLEMENT la KB (sous-processus node, meme mecanisme que
    n'importe quel consommateur) pour citer la lecon dans le message d'echec.

    Regle d'honnetete dure : la verification protege TOUJOURS, meme si la KB est
    injoignable ou l'entree absente -- `justification_source` vaut alors
    'NOT_OBSERVABLE' avec sa raison, mais `oracle_resolu`/`ok` restent corrects
    (calcules independamment de la KB, via resolve_oracle).

    Retourne TOUJOURS un dict (jamais d'exception non maitrisee -- une exception
    imprevue a l'interieur devient elle-meme un echec de pre-vol honnete, ok=False,
    plutot que de laisser une campagne demarrer sur un pre-vol qui a lui-meme plante) :
        {
            "ok": bool,                      # == oracle_resolu
            "project": str,
            "oracle_resolu": bool,
            "kb_consultee": bool,             # KB reellement interrogee et joignable
            "brick_id": str | None,           # LESSON_BRICK_ID si trouve dans la KB
            "justification": str,             # message humain, cite la lecon si trouvee
            "justification_source": "KB" | "NOT_OBSERVABLE",
            "raison_echec": str | None,       # pourquoi oracle_resolu est faux
        }
    """
    try:
        root = repo_root or REPO_ROOT
        script = search_script if search_script is not None else (root / "knowledge_base" / "search.mjs")

        kb = _consult_kb(script)
        oracle_resolu, raison_echec = _resolve_oracle_status(project, oracle_config_path)

        if kb["reachable"] and kb["brick_id"]:
            statement = kb["statement"] or ""
            # "..." ASCII (pas l'ellipse unicode '…') : evite le piege console
            # cp1252 deja connu du studio (P3, forge.verify_run._harden_streams)
            # sur un message qui remonte jusqu'a un print() CLI (run_real.py).
            truncated = statement[:220] + ("..." if len(statement) > 220 else "")
            justification_source = "KB"
            justification = f"{kb['brick_id']}: {truncated}"
        elif kb["reachable"]:
            justification_source = "NOT_OBSERVABLE"
            justification = (
                f"KB consultee ({script}) mais {LESSON_BRICK_ID} n'apparait pas dans "
                "les resultats -- regle appliquee quand meme, sans citation."
            )
        else:
            justification_source = "NOT_OBSERVABLE"
            justification = (
                f"KB injoignable ({kb['raw_error']}) -- regle appliquee quand meme, "
                "sans citation : une garde ne doit jamais dependre de la disponibilite "
                "de sa propre documentation."
            )

        return {
            "ok": oracle_resolu,
            "project": project,
            "oracle_resolu": oracle_resolu,
            "kb_consultee": bool(kb["reachable"]),
            "brick_id": kb["brick_id"],
            "justification": justification,
            "justification_source": justification_source,
            "raison_echec": raison_echec,
        }
    except Exception as exc:  # noqa: BLE001 — garde-fou terminal, voir docstring.
        logger.warning("preflight_campagne: echec interne non anticipe pour projet=%s",
                       project, exc_info=True)
        return {
            "ok": False,
            "project": project,
            "oracle_resolu": False,
            "kb_consultee": False,
            "brick_id": None,
            "justification": (
                "pre-vol interrompu par une erreur interne non anticipee -- campagne "
                "NON lancee par prudence (une garde qui plante doit bloquer, pas "
                "laisser passer)."
            ),
            "justification_source": "NOT_OBSERVABLE",
            "raison_echec": f"exception interne au pre-vol: {exc!r}",
        }
