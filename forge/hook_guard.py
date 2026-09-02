"""Garde de spawn Forge — la logique du hook dur (ADR-002 connecteur 2).

Un sous-agent Forge s'annonce par un marqueur ``FORGE_DISPATCH:<etape>:<run_id>``
dans son prompt (posé par le skill /forge). Le garde n'autorise ce spawn que si
un dispatch validé correspondant a bien été enregistré dans l'audit (donc que le
contrat est passé par la porte ``dispatch.prepare_dispatch``).

Sans marqueur => spawn hors Forge => TOUJOURS autorisé : le hook ne gêne jamais
les autres usages de l'outil Agent. Pur (pas d'I/O réseau, pas de spawn).
"""
from __future__ import annotations

import json
import re
from pathlib import Path

# STDLIB-ONLY OBLIGATOIRE ici : ce garde est fail-CLOSED en périmètre Forge, donc un
# ImportError dans SA chaîne d'import ne serait pas une panne mais un REFUS UNIVERSEL de
# tout spawn Forge. `forge.audit` ne dépend que de la stdlib (+ forge.verdict, stdlib
# aussi) ; passer par `forge.dispatch` traînerait `forge.contract` -> `yaml`, absent hors
# venv (worktrees) — c'est exactement la panne corrigée. Ne jamais réintroduire d'import
# `forge.dispatch` dans ce module, ni au niveau module ni dans une fonction.
from forge.audit import DEFAULT_AUDIT, EVENT_AUTHORIZED, EVENT_PREPARED

# Marqueur : FORGE_DISPATCH:<etape>:<run_id>[:<attempt>]. Le 3e groupe (attempt) est
# OPTIONNEL — une ligne d'audit / un prompt au FORMAT HISTORIQUE 2-champs reste reconnu.
# Quand l'attempt est présent, l'unicité (D4) s'applique au TRIPLET (etape, run_id, attempt) ;
# absent, elle retombe sur le couple (etape, run_id) — cf. check_spawn.
MARKER = re.compile(r"FORGE_DISPATCH:([\w.\-]+):([\w.\-]+)(?::(\d+))?")
MARKER_TOKEN = "FORGE_DISPATCH"
SPAWN_TOOLS = ("Task", "Agent")


def marker_key(prompt: str) -> tuple[str, str, int] | None:
    """(etape, run_id, attempt) du marqueur, ou None s'il n'y en a pas.

    `attempt` vaut 0 pour un marqueur historique 2-champs — même convention que
    `DispatchRecord.attempt` (défaut 0), donc la corrélation reste exacte. Fonction
    PURE (aucune I/O) : c'est le seul point d'analyse du marqueur, partagé par le
    garde PreToolUse et par le hook PostToolUse (`spawn_executed`).
    """
    match = MARKER.search(prompt or "")
    if not match:
        return None
    attempt = int(match.group(3)) if match.group(3) is not None else 0
    return match.group(1), match.group(2), attempt


def check_spawn(prompt: str, audit_path: Path | None = None,
                key_file: Path | None = None) -> tuple[bool, str]:
    """Retourne (autorisé, raison). Sans marqueur Forge => autorisé.

    Unicité (D4) : COMPTE les lignes d'audit valides-HMAC qui matchent la clé du marqueur
    — le triplet (etape, run_id, attempt) si l'attempt est présent, sinon le couple
    (etape, run_id) (rétro-compat marqueur 2-champs). count == 1 => allow ; count == 0
    => refus (pas de dispatch pour cette clé) ; count >= 2 => refus (ambiguïté/replay).
    Ne matche JAMAIS sur (etape, run_id) seul quand un attempt est fourni : des tentatives
    distinctes (attempt 1,2,3) d'un même couple sont des retries LÉGITIMES, chacune count 1.
    """
    match = MARKER.search(prompt or "")
    if not match:
        return True, "non-forge (aucun marqueur)"

    etape, run_id = match.group(1), match.group(2)
    attempt = int(match.group(3)) if match.group(3) is not None else None
    key = f"{etape}/{run_id}" + (f"#{attempt}" if attempt is not None else "")
    path = Path(audit_path or DEFAULT_AUDIT)
    if not path.exists():
        return False, f"forge {key} : audit absent -> spawn hors contrat"

    from forge.audit import verify_audit_line
    valid_count = 0
    saw_tampered = False  # ligne qui matche la clé mais HMAC absent/invalide
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue
        if rec.get("etape") != etape or rec.get("run_id") != run_id:
            continue
        if attempt is not None and rec.get("attempt") != attempt:
            continue
        # L'unicité (D4) porte sur la PRÉPARATION, pas sur les événements de cycle de
        # vie. Depuis la Phase 2b, le même triplet reçoit aussi `spawn_authorized` /
        # `spawn_executed` : les compter ferait passer un spawn parfaitement légitime
        # pour un replay (count >= 2). Ligne historique sans `event` => spawn_prepared.
        if (rec.get("event") or EVENT_PREPARED) != EVENT_PREPARED:
            continue
        # La ligne doit porter un HMAC valide : une ligne forgée à la main (sans la
        # clé) ne compte pas -> le hook vérifie une PREUVE, pas une simple présence.
        if not verify_audit_line(rec, key_file):
            saw_tampered = True
            continue
        valid_count += 1

    if valid_count == 1:
        return True, f"dispatch validé {key}"
    if valid_count >= 2:
        return False, f"forge {key} : {valid_count} dispatches pour cette clé -> ambiguïté/replay, refus"
    # valid_count == 0 : distinguer altération (preuve tentée mais invalide) d'absence.
    if saw_tampered:
        return False, f"forge {key} : ligne d'audit non signée/altérée -> refus"
    return False, f"forge {key} : aucun dispatch validé -> spawn hors contrat"


def record_authorization(prompt: str, audit_path: Path | None = None,
                         key_file: Path | None = None) -> bool:
    """Trace `spawn_authorized` — l'autorité qui AUTORISE écrit sa décision.

    ⚠ NON CÂBLÉE EN PRODUCTION (état assumé, Phase 2b) : le seul appelant légitime est
    `.claude/hooks/pretool_forge_guard.py`, HORS PÉRIMÈTRE de ce chantier (le script de
    hook de la session en cours ne devait pas être modifié). Le câblage tient en une
    ligne (`record_authorization(prompt)` après que `code` est figé, dans un try/except
    nu) et attend un go de Pierre. Les deux événements CÂBLÉS et suffisants à la preuve
    sont `spawn_prepared` (prepare_dispatch) et `spawn_executed` (hook PostToolUse +
    driver) — Pierre : « la preuve finale vient de spawn_executed ». `spawn_proof`
    compte déjà `authorized` : le lecteur existe, seul l'écrivain reste à brancher.

    DÉLIBÉRÉMENT SÉPARÉE de `hook_decision`, qui doit rester une fonction PURE :
    1. la décision du hook ne peut pas dépendre d'une écriture (elle est déjà prise
       quand on appelle ceci — l'audit ne peut donc jamais changer un allow en deny) ;
    2. `hook_decision` est appelée par des dizaines de tests sans `audit_path` : y
       cacher une écriture polluerait le fichier d'audit RÉEL du dépôt.
    L'appelant (le script de hook) appelle ceci UNIQUEMENT après un allow en périmètre
    Forge. Best-effort total (`append_spawn_event` ne lève jamais) : un audit non
    écrit dégrade la preuve, il ne bloque pas un spawn déjà autorisé.
    """
    key = marker_key(prompt)
    if key is None:
        return False
    from forge.audit import append_spawn_event
    etape, run_id, attempt = key
    return append_spawn_event(EVENT_AUTHORIZED, etape, run_id, attempt,
                              audit_path=audit_path, key_file=key_file)


def record_execution(prompt: str, audit_path: Path | None = None,
                     key_file: Path | None = None) -> bool:
    """Trace `spawn_executed` — LA preuve d'action (Pierre : « la preuve finale vient
    de spawn_executed »). Appelée par le hook PostToolUse APRÈS le retour réel de
    l'agent : à ce point, l'exécution a eu lieu, ce n'est plus une intention.

    Mêmes garanties que `record_authorization` : pure lecture du marqueur + écriture
    best-effort, aucune décision, aucun blocage possible.
    """
    key = marker_key(prompt)
    if key is None:
        return False
    from forge.audit import EVENT_EXECUTED, append_spawn_event
    etape, run_id, attempt = key
    return append_spawn_event(EVENT_EXECUTED, etape, run_id, attempt,
                              audit_path=audit_path, key_file=key_file)


def hook_decision(tool: str, prompt: str, audit_path: Path | None = None,
                  key_file: Path | None = None) -> tuple[int, str]:
    """Décision du hook PreToolUse : 0 = autoriser, 2 = bloquer.

    Fail-OPEN hors périmètre Forge (autre outil, ou aucun marqueur) : le hook ne
    gêne jamais les usages non-Forge de l'outil Agent. Fail-CLOSED SUR le périmètre
    Forge : dès qu'un marqueur ``FORGE_DISPATCH`` est présent, toute impossibilité
    de vérifier (garde qui lève, audit illisible) => refus (2), jamais un
    laissez-passer silencieux. C'est la correction du fail-open aveugle.
    """
    if tool not in SPAWN_TOOLS:
        return 0, "outil hors périmètre"
    if MARKER_TOKEN not in (prompt or ""):
        return 0, "non-forge (aucun marqueur)"
    # Périmètre Forge : à partir d'ici, toute erreur bloque (fail-closed).
    try:
        allow, reason = check_spawn(prompt, audit_path=audit_path, key_file=key_file)
    except Exception as exc:  # noqa: BLE001 — en périmètre Forge, l'incertitude = refus
        return 2, f"forge: vérification impossible ({exc}) -> refus fail-closed"
    return (0, reason) if allow else (2, reason)
