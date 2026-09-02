"""Journal d'audit de spawn Forge — format, signature, écriture, lecture.

STDLIB ONLY. C'est la propriété la plus importante de ce module et la raison de
son existence : le GARDE de spawn (`forge.hook_guard`, appelé par le hook
PreToolUse `.claude/hooks/pretool_forge_guard.py`) est fail-CLOSED en périmètre
Forge — un ImportError dans sa chaîne d'import ne devient pas une panne, il
devient un REFUS UNIVERSEL de tout spawn Forge. Le garde ne doit donc dépendre
que de ce qui est garanti présent : la bibliothèque standard.

Avant l'extraction de ce module, `hook_guard` importait `forge.dispatch`, qui
importe `forge.contract`, qui importe `yaml` (PyYAML). Hors du venv (worktrees,
`python` nu), le garde répondait « garde indisponible (No module named 'yaml')
-> refus fail-closed » : il ne jugeait plus rien, il refusait tout.

Ce module contient exactement la couche « fichier d'audit » : les événements du
cycle de spawn, l'enregistrement signé, l'écriture et la relecture vérifiée.
`forge.dispatch` (couche contrat/profils, qui a besoin de YAML) l'importe et le
ré-exporte : `from forge.dispatch import DEFAULT_AUDIT / EVENT_* /
verify_audit_line / ...` continue de fonctionner à l'identique.

Seule dépendance interne : `forge.verdict` (HMAC), lui-même stdlib-only, importé
paresseusement dans les fonctions de signature — exactement comme avant.
"""
from __future__ import annotations

import json
import logging
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path

logger = logging.getLogger(__name__)

# forge/audit.py -> parents[2] == racine du dépôt. Recalculé ICI plutôt
# qu'importé de `forge.contract` (qui importe yaml) : c'est tout l'objet du module.
_REPO_ROOT = Path(__file__).resolve().parents[1]

DEFAULT_AUDIT = _REPO_ROOT / "EVIDENCE" / "bundles" / "dispatch_audit.jsonl"

# Événements immuables du cycle de spawn (DISPATCH_SPAWN_AUTHORITY_V1, Pierre 2026-07-23).
# Une ligne d'audit HISTORIQUE (sans champ `event`) est, par convention, un
# `spawn_prepared` : c'est le seul événement qui existait quand elle a été écrite.
EVENT_PREPARED = "spawn_prepared"     # prepare_dispatch : contrat validé, payload fabriqué
EVENT_AUTHORIZED = "spawn_authorized"  # hook PreToolUse : le garde a laissé passer le spawn
EVENT_EXECUTED = "spawn_executed"     # l'exécution a RÉELLEMENT eu lieu et est revenue
SPAWN_EVENTS = (EVENT_PREPARED, EVENT_AUTHORIZED, EVENT_EXECUTED)


@dataclass(frozen=True)
class DispatchRecord:
    run_id: str
    etape: str
    capability_role: str
    model: str
    provider: str
    allowed_tools: tuple[str, ...]
    ts: float
    # Champs additifs (Phase 2a DISPATCH_SPAWN_AUTHORITY_V1). Defaults => les lignes
    # d'audit historiques (écrites sans ces champs) restent vérifiables : le HMAC porte
    # sur le corps réellement présent, `verify_audit_line` ne les exige pas.
    # - event : type d'événement de la ligne (cf. SPAWN_EVENTS). `prepare_dispatch`
    #   écrit "spawn_prepared" (une INTENTION) ; "spawn_authorized" et "spawn_executed"
    #   sont écrits par `append_spawn_event` (Phase 2b) — c'est `spawn_executed` qui
    #   porte la PREUVE D'ACTION.
    # - attempt : n° de tentative (corrèle la ligne au triplet du marqueur, unicité D4).
    # - unprofiled : true ssi le dispatch a été autorisé HORS de son profil via
    #   allow_unprofiled — trace INFALSIFIABLE (dans le corps signé) d'une dérogation D1.
    event: str = EVENT_PREPARED
    attempt: int = 0
    unprofiled: bool = False
    # A3 (ratifié Pierre 2026-08-28) — BORNAGE RÉELLEMENT APPLIQUÉ, signé.
    # `allowed_tools` (ci-dessus) reste ce qu'il a toujours été : la DÉCLARATION du
    # contrat (champs skill/plugin), vide par construction pour 17 contrats sur 19.
    # Le bornage réel de l'exécuteur (`run_real._effective_step_tools` /
    # `_derive_disallowed`, passé à `claude -p`) n'entrait dans AUCUNE signature :
    # la ligne signée décrivait des outils qu'elle n'appliquait pas.
    # Ces DEUX clés NOUVELLES (jamais une redéfinition de `allowed_tools`, dont les
    # lecteurs restent valides) le portent, et sont renseignées par les événements
    # écrits APRÈS l'exécution — là où le mécanisme a réellement appliqué la borne.
    # `None` = non connu à ce point (ligne `spawn_prepared`, oracle in-process) ;
    # `[]` dirait « aucun outil », ce serait une affirmation, pas une mesure.
    tools_effective_signed: tuple[str, ...] | None = None
    tools_disallowed_count: int | None = None


def _resolve_audit_path(audit_path: Path | str | None) -> Path:
    """Chemin d'audit effectif. Un `audit_path` explicite gagne toujours.

    Sinon `DEFAULT_AUDIT`, en honorant le POINT DE SURCHARGE HISTORIQUE
    `forge.dispatch.DEFAULT_AUDIT` : avant l'extraction de ce module, les écrivains
    et lecteurs relisaient CE global-là à chaque appel, et du code de test le
    réassigne pour rediriger l'audit vers un fichier temporaire (sinon un test
    écrirait dans `EVIDENCE/bundles/` réel). On le respecte pour ne changer AUCUN
    comportement observable.

    Ce module n'IMPORTE PAS `forge.dispatch` (il resterait stdlib-only, mais la
    dépendance serait circulaire ET ramènerait yaml) : on regarde seulement s'il est
    DÉJÀ chargé. Surcharger `forge.audit.DEFAULT_AUDIT` fonctionne aussi (le global
    est relu à chaque appel).
    """
    if audit_path:
        return Path(audit_path)
    dispatch_mod = sys.modules.get("forge.dispatch")
    override = getattr(dispatch_mod, "DEFAULT_AUDIT", None) if dispatch_mod else None
    if override is not None and override != DEFAULT_AUDIT:
        return Path(override)
    return Path(DEFAULT_AUDIT)


def sign_audit_record(rec: dict, key_file: Path | None = None) -> dict:
    """Ajoute un HMAC à un enregistrement d'audit — une ligne forgée à la main
    (sans la clé) ne pourra pas se faire passer pour un dispatch validé."""
    from forge.verdict import _sign_mapping
    signed = dict(rec)
    signed["hmac"] = _sign_mapping(rec, key_file)
    return signed


def verify_audit_line(rec: dict, key_file: Path | None = None) -> bool:
    """Vrai ssi la ligne porte un HMAC valide sur son contenu (hors champ hmac)."""
    from forge.verdict import _verify_mapping
    sig = rec.get("hmac")
    if not sig:
        return False
    body = {k: v for k, v in rec.items() if k != "hmac"}
    return _verify_mapping(body, sig, key_file)


def _append_audit(record: DispatchRecord, audit_path: Path | None,
                  key_file: Path | None = None) -> None:
    path = _resolve_audit_path(audit_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    signed = sign_audit_record(asdict(record), key_file)
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(signed, ensure_ascii=False, sort_keys=True) + "\n")


def append_spawn_event(
    event: str,
    etape: str,
    run_id: str,
    attempt: int = 0,
    *,
    capability_role: str = "",
    model: str = "",
    provider: str = "",
    allowed_tools: tuple[str, ...] = (),
    tools_effective_signed: tuple[str, ...] | None = None,
    tools_disallowed_count: int | None = None,
    audit_path: Path | None = None,
    key_file: Path | None = None,
) -> bool:
    """Append un événement de spawn signé. Retourne True ssi la ligne a été écrite.

    Réutilise le MÊME mécanisme que `prepare_dispatch` (`DispatchRecord` + HMAC via
    `_append_audit`) — un seul format d'audit, une seule signature, un seul lecteur.
    La corrélation avec le `spawn_prepared` correspondant se fait par le TRIPLET
    `(etape, run_id, attempt)`, exactement la clé du marqueur de spawn.

    BEST-EFFORT ABSOLU : ne lève JAMAIS. Un événement d'audit est une preuve, pas un
    gate — une écriture impossible (disque plein, chemin en lecture seule, clé absente)
    doit dégrader la preuve, jamais casser un spawn ni un run en cours. L'appelant qui
    veut savoir lit la valeur de retour.

    Les champs de payload (`model`, `provider`, ...) sont OPTIONNELS : un hook
    PostToolUse ne connaît que le marqueur (etape/run_id/attempt) et laisse le reste
    vide plutôt que d'inventer. Vide = « non connu à ce point », jamais « aucun ».

    A3 : `tools_effective_signed` / `tools_disallowed_count` = le bornage RÉELLEMENT
    appliqué à l'exécution (cf. DispatchRecord). Rapportés par l'appelant qui vient
    de voir l'exécution revenir — jamais recalculés ici (ce module est stdlib-only
    par contrat : importer `run_real` y ramènerait yaml et casserait le garde
    fail-closed). Omis => `None` = non connu, jamais un bornage supposé.
    """
    try:
        _append_audit(
            DispatchRecord(
                run_id=run_id,
                etape=etape,
                capability_role=capability_role,
                model=model,
                provider=provider,
                allowed_tools=tuple(allowed_tools),
                ts=time.time(),
                event=event,
                attempt=int(attempt),
                tools_effective_signed=(
                    None if tools_effective_signed is None
                    else tuple(tools_effective_signed)),
                tools_disallowed_count=(
                    None if tools_disallowed_count is None
                    else int(tools_disallowed_count)),
            ),
            audit_path,
            key_file,
        )
        return True
    except Exception:  # noqa: BLE001 — best-effort : l'audit ne casse jamais l'appelant
        logger.warning("événement d'audit %s non écrit pour %s/%s#%s (non bloquant)",
                       event, etape, run_id, attempt)
        return False


def _iter_audit_records(path: Path, key_file: Path | None = None):
    """Itère les lignes d'audit VALIDES-HMAC d'un fichier. Une ligne tronquée (écriture
    concurrente interrompue) ou non signée est ignorée : l'audit lit des PREUVES, pas
    des présences. Ne lève jamais sur le contenu."""
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(rec, dict) or not verify_audit_line(rec, key_file):
            continue
        yield rec


def spawn_proof(run_id: str, audit_path: Path | None = None,
                key_file: Path | None = None) -> dict:
    """Preuve d'ACTION d'un run : combien de spawns préparés / autorisés / EXÉCUTÉS.

    C'est le LECTEUR de `spawn_executed` (DISPATCH_SPAWN_AUTHORITY_V1, Pierre) : sans
    lui, l'événement serait un connecteur dormant de plus. Branché dans le rapport de
    fin de run (`forge.driver.ForgeDriver._cost_and_effort`), il rend visible l'écart
    « N dispatches préparés / M spawns réellement exécutés » — l'écart que personne ne
    pouvait voir (ex. réel : 7 lignes préparées pour `pong-01`, `attempts: 1` déclaré).

    `unproven` = les triplets PRÉPARÉS sans `spawn_executed` correspondant : une
    intention dont l'exécution n'est pas prouvée. Ce n'est PAS un verdict — un run
    interrompu ou antérieur à la Phase 2b en produit légitimement.

    Même RÈGLE DURE que `cost`/`pool` dans le rapport : un fichier d'audit ABSENT ou
    VIDE rend `measured: False` + une raison lisible — jamais un « 0 exécuté »
    silencieux qui affirmerait faussement qu'aucun spawn n'a eu lieu.
    """
    path = _resolve_audit_path(audit_path)
    out = {"run_id": run_id, "measured": False, "prepared": 0, "prepared_distinct": 0,
           "authorized": 0, "executed": 0, "unproven": []}
    try:
        measured = path.exists() and path.stat().st_size > 0
    except OSError:
        measured = False
    if not measured:
        out["reason"] = f"{path} absent ou vide — spawns NON MESURÉS (pas un zéro réel)"
        return out

    prepared: list[tuple[str, int]] = []
    executed: set[tuple[str, int]] = set()
    try:
        for rec in _iter_audit_records(path, key_file):
            if rec.get("run_id") != run_id:
                continue
            # Ligne historique sans `event` => spawn_prepared (seul événement d'alors).
            event = rec.get("event") or EVENT_PREPARED
            key = (str(rec.get("etape") or ""), int(rec.get("attempt") or 0))
            if event == EVENT_PREPARED:
                out["prepared"] += 1
                prepared.append(key)
            elif event == EVENT_AUTHORIZED:
                out["authorized"] += 1
            elif event == EVENT_EXECUTED:
                out["executed"] += 1
                executed.add(key)
    except OSError:
        out["measured"] = False
        out["reason"] = f"{path} illisible — spawns NON MESURÉS"
        return out

    out["measured"] = True
    # `prepared` compte les LIGNES, `prepared_distinct` les TRIPLETS : l'écart entre les
    # deux est la duplication de préparation elle-même (7 lignes pour 1 seul triplet).
    out["prepared_distinct"] = len(set(prepared))
    seen: set[tuple[str, int]] = set()
    for etape, attempt in prepared:
        if (etape, attempt) in executed or (etape, attempt) in seen:
            continue
        seen.add((etape, attempt))
        out["unproven"].append({"etape": etape, "attempt": attempt})
    return out


def check_spawn_invariant(run_id: str | None = None, audit_path: Path | None = None,
                          key_file: Path | None = None) -> dict:
    """Vérité en LECTURE SEULE de l'invariant ``executed ⇒ authorized`` : toute ligne
    `spawn_executed` doit avoir une ligne `spawn_authorized` correspondante pour le
    MÊME triplet (run_id, etape, attempt).

    N'écrit rien, ne décide rien — un lecteur de cohérence (post-mortem pacman
    2026-08-07, lot A réparation 3 : `spawn_authorized` mesuré à 0/1418 alors que
    `spawn_executed` l'était pour 561 dispatches — l'invariant était violé en silence
    parce que rien ne le vérifiait). Sert de garde de non-régression (tests) et
    d'outil d'audit ponctuel — PAS branché dans un gate de run : casser l'invariant
    dégrade la preuve, ça ne doit jamais bloquer un run déjà exécuté.

    `run_id=None` vérifie TOUT le fichier d'audit (tous runs confondus) ; un `run_id`
    fourni restreint la vérification à ce run. Même RÈGLE DURE que `spawn_proof` : un
    fichier d'audit ABSENT ou VIDE rend `measured: False` — jamais un « 0 violation »
    silencieux qui affirmerait faussement que l'invariant tient.
    """
    path = _resolve_audit_path(audit_path)
    out = {"run_id": run_id, "measured": False, "executed": 0, "authorized": 0,
           "violations": []}
    try:
        measured = path.exists() and path.stat().st_size > 0
    except OSError:
        measured = False
    if not measured:
        out["reason"] = f"{path} absent ou vide — invariant NON MESURÉ (pas un zéro réel)"
        return out

    authorized: set[tuple[str, str, int]] = set()
    executed: list[tuple[str, str, int]] = []
    try:
        for rec in _iter_audit_records(path, key_file):
            rid = str(rec.get("run_id") or "")
            if run_id is not None and rid != run_id:
                continue
            event = rec.get("event") or EVENT_PREPARED
            key = (rid, str(rec.get("etape") or ""), int(rec.get("attempt") or 0))
            if event == EVENT_AUTHORIZED:
                authorized.add(key)
            elif event == EVENT_EXECUTED:
                executed.append(key)
    except OSError:
        out["reason"] = f"{path} illisible — invariant NON MESURÉ"
        return out

    out["measured"] = True
    out["executed"] = len(executed)
    out["authorized"] = len(authorized)
    seen: set[tuple[str, str, int]] = set()
    for key in executed:
        if key in seen or key in authorized:
            continue
        seen.add(key)
        rid, etape, attempt = key
        out["violations"].append({"run_id": rid, "etape": etape, "attempt": attempt})
    return out
