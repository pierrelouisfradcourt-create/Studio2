"""Acquittement structuré d'un message du Director (Lot 6, spec 2026-09-04, GO Pierre) — K4.

Remplace la recherche de sous-chaîne (`consumption._contains_ref`) sur le chemin d'acquittement :
citer un identifiant dans sa prose ne prouve pas qu'on a corrigé quelque chose. Mesuré sur les runs
réels : `wiremap` « consumed » parce que l'id apparaissait dans sa PROSE, `builder` « not_consumed »
deux fois avec `checked []` — aucun fichier vérifiable.

La capacité répond dans une fence dédiée, et le jugement est MÉCANIQUE :

    acknowledged            message valide, action applied|partial, effet mesuré != NO_EFFECT
    claimed_without_effect  action applied mais le Director n'a mesuré AUCUN effet
    rejected                désaccord motivé — transporté, jamais tranché ici
    unknown_message         id inconnu, autre capacité, autre run, ou message DÉJÀ acquitté
    not_acknowledged        aucun bloc, bloc illisible, action hors énumération, rejected sans raison

Un `rejected` produit DEUX objets distincts (spec §4.3) : un désaccord (objection en sens inverse,
capacité -> director) puis une question ouverte qui le référence. Question initiale, objection du
Director et réponse négative de la capacité restent ainsi distinguables pour l'arbitrage.

Ce module ne lit ni ne modifie un verdict, n'appelle aucun modèle, n'écrit aucun fichier.
NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import json
import re
from datetime import datetime, timezone

from forge.amendment_log import new_message_id

FENCE = re.compile(r"^```acquittement[ \t]*\r?\n(.*?)^```", re.S | re.M)

ACKNOWLEDGED = "acknowledged"
CLAIMED_WITHOUT_EFFECT = "claimed_without_effect"
REJECTED = "rejected"
UNKNOWN_MESSAGE = "unknown_message"
NOT_ACKNOWLEDGED = "not_acknowledged"
ACTIONS = ("applied", "partial", "rejected")
NO_EFFECT = "NO_EFFECT"          # même vocabulaire que forge.director.effect_of


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def extract_block(output: str) -> tuple[dict | None, str]:
    """(bloc, diagnostic) — SEUL le dernier fence ```acquittement``` fait foi (même règle que
    `run_real._extract_design_questions_block` : un fence antérieur est un brouillon)."""
    blocks = FENCE.findall(output or "")
    if not blocks:
        return None, "aucun fence ```acquittement"
    raw = blocks[-1]
    try:
        candidat = json.loads(raw)
    except ValueError as exc:
        return None, f"fence présent mais JSON illisible : {exc}"
    if not isinstance(candidat, dict):
        return None, f"fence présent mais ce n'est pas un objet ({type(candidat).__name__})"
    return candidat, ""


def judge(block, *, message: dict | None, capability: str, run_id: str, effect: str | None,
          already_acknowledged: set[str] | None = None) -> dict:
    """Statut d'un acquittement. Ne lève jamais. `effect` vient du Director (`effect_of`) : lui seul
    a mesuré l'avant/après, donc lui seul peut distinguer « appliqué » de « prétendu »."""
    out = {"status": NOT_ACKNOWLEDGED, "message_id": None, "action": None,
           "changes": [], "reason": "", "effect": effect}
    if not isinstance(block, dict):
        out["reason"] = "aucun bloc d'acquittement recevable"
        return out
    mid = str(block.get("message_id") or "")
    action = str(block.get("action") or "").strip().lower()
    out.update({"message_id": mid or None, "action": action or None,
                "changes": [str(c) for c in (block.get("changes") or []) if str(c)],
                "reason": str(block.get("reason") or "")})
    attendu = (message or {}).get("id")
    destinataires = [str(x) for x in ((message or {}).get("to") or [])]
    if (not attendu or mid != attendu or capability not in destinataires
            or (message or {}).get("run_id") not in (None, run_id)
            or mid in (already_acknowledged or set())):
        out["status"] = UNKNOWN_MESSAGE
        return out
    if action not in ACTIONS:
        return out                       # NOT_ACKNOWLEDGED : action hors énumération
    if action == "rejected":
        out["status"] = REJECTED if out["reason"].strip() else NOT_ACKNOWLEDGED
        return out
    if action == "applied" and effect == NO_EFFECT:
        out["status"] = CLAIMED_WITHOUT_EFFECT
        return out
    out["status"] = ACKNOWLEDGED
    return out


def disagreement_message(judgment: dict, *, capability: str, run_id: str, message: dict) -> dict:
    """Le DÉSACCORD : une objection en sens INVERSE (capacité -> director), distincte de l'objection
    du Director et de la question initiale (spec §4.3, correction 3 de Pierre). Le type `objection`
    existe déjà au journal ; seul le sens de circulation change."""
    issued = _now()
    return {
        "id": new_message_id(f"desaccord {capability} {run_id}", issued),
        "type": "objection", "from": capability, "to": ["director"],
        "in_reply_to": message.get("id"), "run_id": run_id,
        "subject": f"DÉSACCORD sur {message.get('id')} : {message.get('subject', '')}"[:200],
        "reason": judgment.get("reason") or "(aucune raison transmise)",
        "impact": [], "evidence_ref": [str(message.get("id"))], "blocking": False,
        "issued_at": issued,
    }


def question_entry(judgment: dict, *, capability: str, run_id: str, disagreement_id: str) -> dict:
    """La QUESTION ouverte qui suit le désaccord : arbitrage par le Director puis Pierre. Non
    bloquante — un désaccord ne gèle pas le run, il se tranche."""
    issued = _now()
    return {
        "id": new_message_id(f"arbitrage {capability} {run_id}", issued),
        "type": "question", "from": capability, "to": ["director", "pierre"],
        "run_id": run_id, "about": judgment.get("message_id"),
        "why": judgment.get("reason") or "(aucune raison transmise)",
        "evidence_ref": [disagreement_id], "blocking": False, "issued_at": issued,
    }
