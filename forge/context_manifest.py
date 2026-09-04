"""forge/context_manifest.py — Context Manifest (périmètre GO ratifié
Pierre, docs/forge/CONTEXT_LOOP_V1_1_FRESHNESS.md §7).

Ce module MESURE le contexte réellement servi à un agent Forge ; il ne décide
rien et ne change ni prompt ni gate. Deux enregistrements, appendés en JSONL,
UN PAR étape/run, sous ``EVIDENCE/runs/<projet>/context/<etape>.manifest.jsonl`` :

  kind "dispatch"  — écrit par ``forge.dispatch.prepare_dispatch`` : quelles
                     sources (contrat/mandatory_read/amont/registry) existaient
                     et sous quel hash au moment du dispatch.
  kind "execution" — écrit par ``forge.run_real.claude_executor`` au moment où
                     le prompt final existe : hash + taille + budget de fenêtre.

Chaque ligne est HMAC-signée avec le même mécanisme que ``forge.verdict``
(``_sign_mapping``/``_verify_mapping``, même ``.forge_key``) : une ligne
fabriquée à la main sans la clé ne peut pas se faire passer pour une mesure
réelle.

claim_verdict: NO_CLAIM_ALLOWED — un manifest est une mesure, jamais un claim.

Toute résolution de source est FAIL-SOFT : un fichier absent produit
``exists: false, sha256: null``, jamais une exception. L'écriture des lignes
elle-même (I/O) PEUT lever — c'est aux appelants (``dispatch.py``,
``run_real.py``) d'encapsuler l'appel dans un try/except best-effort, comme
prescrit par la mission (« une exception manifest ne doit JAMAIS faire
échouer un dispatch/build »).
"""
from __future__ import annotations

import hashlib
import json
import logging
import re
import time
from pathlib import Path

from forge.contract import CONTRACTS_DIR, FORGE_ROLES, base_step
from forge.verdict import CLAIM_VERDICT, _sign_mapping, _verify_mapping, current_git_head

logger = logging.getLogger(__name__)

REPO_ROOT = Path(__file__).resolve().parents[1]

SCHEMA = "forge.context_manifest.v1"

MODEL_WINDOWS_PATH = Path(__file__).resolve().parent / "model_windows.json"

# OVERFLOW_RISK si estimated_tokens > OVERFLOW_RATIO * fenêtre du modèle.
OVERFLOW_RATIO = 0.9

# --- table amont DUPLIQUÉE (anti import circulaire) --------------------------
# forge.run_real importe forge.dispatch (pour ORDER/DETERMINISTIC/PROFILES) qui
# importe forge.contract ; forge.run_real définit aussi `_UPSTREAM_BY_STEP`
# APRÈS ses propres imports de tête. Importer `forge.run_real` depuis ce module
# au niveau module (pour lire cette table) créerait un risque de cycle si
# run_real en venait à importer context_manifest en tête de fichier (c'est le
# cas ici, pour la ligne 'execution'). On duplique donc la table ci-dessous ;
# `forge/tests/test_context_manifest.py` porte un test d'égalité
# STRICTE contre `forge.run_real._UPSTREAM_BY_STEP` — toute divergence future
# entre les deux copies casse ce test, jamais un oubli silencieux.
_UPSTREAM_BY_STEP: dict[str, tuple[str, ...]] = {
    # FORGE_PRISME_V2 (Pierre, 2026-08-03) ' le Prisme RECOIT le World Scan.
    # Avant : aucune entree pour s1-prisme, et s2-worldscan n'avait AUCUN
    # consommateur mecanique. Le Prisme raisonnait sur le seul charter, ce qui
    # rendait son silence sur menu/pause/audio/onboarding structurel et non
    # accidentel. Le Prisme est le mecanisme qui transforme la connaissance
    # externe en exigences internes ' encore faut-il qu'il la recoive.
    # Choix (b) Pierre 2026-08-21 : le Prisme recoit AUSSI la Story Bible (s2.6) et
    # le GM World Scan (s2.7) quand ils existent (profil full_godot_narratif) ' c'est
    # par les exigences du Prisme que leur information atteint la decompo sans
    # assouplir la regle source_ref -> exigence de check_decompo. Fichier absent
    # (profil full) => omis par upstream_artifacts_section, comportement inchange.
    # Lot F (2026-08-23) : + design_questions.json ' copie STRICTEMENT identique
    # a run_real._UPSTREAM_BY_STEP (test d'egalite dans test_context_manifest.py).
    # Lot D (2026-08-23, GO Pierre, fuite 3) : copie STRICTEMENT identique a
    # run_real._UPSTREAM_BY_STEP (test d'egalite dans test_context_manifest.py).
    "s1-prisme": ("artifacts/s2-worldscan.txt", "artifacts/s2.6-story-bible.txt",
                  "artifacts/s2.7-gm-worldscan.txt", "design_questions.json",
                  "design/progression_contract.md", "design/calibration.md"),
    # SS7.2 . s2.7 ' copie STRICTEMENT identique a run_real._UPSTREAM_BY_STEP (test
    # d'egalite dans test_context_manifest.py) : toute divergence casse ce test.
    # Lot A 2026-08-23 : s2.7 recoit desormais AUSSI la Story Bible et l'Art Bible +
    # ses demandes d'assets (produite AVANT s2.7 dans full_godot_content).
    # Lot B T2(b) (2026-08-23) : s2.7 recoit AUSSI l'heritage inter-run (contrat
    # d'artefacts GM <-> Artiste) ' copie STRICTEMENT identique a run_real.
    # Lot D (2026-08-23, GO Pierre, fuite 3) : copie STRICTEMENT identique a
    # run_real._UPSTREAM_BY_STEP.
    "s2.7-gm-worldscan": ("artifacts/s2-worldscan.txt", "artifacts/s2.6-story-bible.txt",
                          "art_bible.md", "asset_requests.json",
                          "heritage/art_response.json", "heritage/gm_worldscan.json",
                          "design_intent.md", "design/gameplay_loop_content_contract.md",
                          "design/game_loop_blueprint.md",
                          "design/content_requirements.md",
                          "design/progression_contract.md", "design/calibration.md"),
    # Lot F (2026-08-23, round 2) ' copie STRICTEMENT identique a
    # run_real._UPSTREAM_BY_STEP (test d'egalite) : les alias round 2 recoivent
    # leur propre brouillon R1 (art_bible.md/asset_requests.json/gm_worldscan.json)
    # ET design_questions.json, en plus des sources amont narratives.
    # Lot D (2026-08-23, GO Pierre, fuite 3) : copie STRICTEMENT identique a
    # run_real._UPSTREAM_BY_STEP.
    "s2.5-artbible-r2": ("charter.yaml", "artifacts/s2-worldscan.txt",
                         "artifacts/s2.6-story-bible.txt", "gm_worldscan.json",
                         "design_questions.json", "art_bible.md",
                         "design_intent.md", "design/gameplay_loop_content_contract.md",
                          "design/game_loop_blueprint.md",
                          "design/content_requirements.md",
                         "design/progression_contract.md"),
    "s2.7-gm-worldscan-r2": ("artifacts/s2-worldscan.txt", "artifacts/s2.6-story-bible.txt",
                             "art_bible.md", "asset_requests.json",
                             "design_questions.json", "gm_worldscan.json",
                             "design_intent.md", "design/gameplay_loop_content_contract.md",
                          "design/game_loop_blueprint.md",
                          "design/content_requirements.md",
                             "design/progression_contract.md", "design/calibration.md"),
    "s2.6-story-bible": ("charter.yaml", "artifacts/s2-worldscan.txt"),
    # Lot A 2026-08-23 : copie STRICTEMENT identique a run_real._UPSTREAM_BY_STEP '
    # l'Art Bible herite du World Scan et de la Story Bible (plus du Prisme).
    # Lot B T2(b) (2026-08-23) : + heritage inter-run (art_bible.md, art_response.json
    # du run precedent) ' copie STRICTEMENT identique a run_real.
    # Lot D (2026-08-23, GO Pierre, fuite 3) : copie STRICTEMENT identique a
    # run_real._UPSTREAM_BY_STEP.
    "s2.5-artbible": ("charter.yaml", "artifacts/s2-worldscan.txt",
                      "artifacts/s2.6-story-bible.txt",
                      "heritage/art_bible.md", "heritage/art_response.json",
                      "design_intent.md", "design/gameplay_loop_content_contract.md",
                          "design/game_loop_blueprint.md",
                          "design/content_requirements.md",
                      "design/progression_contract.md"),
    # s3-decompo recoit desormais les DEUX : le Prisme (exigences) et le World
    # Scan (connaissance qui les fonde). Sans cette 2e source, la decompo perdait
    # les standards du genre des qu'ils n'etaient pas repris mot pour mot.
    # Choix (b) Pierre 2026-08-21 : idem pour la decompo (memes deux artefacts amont,
    # apres les 3 sources deja existantes). Fichier absent => omis, comportement
    # inchange pour les profils qui ne produisent pas s2.6/s2.7.
    # full_godot_content (Pierre 2026-08-22, composition) : la decompo recoit AUSSI
    # art_bible.md et asset_requests.json (produits par s2.5-artbible, injecte entre
    # s1 et s3 dans ce profil). Absents (autres profils) => omis, comportement inchange.
    # V4 GAME LOOP (2026-08-22, GO Pierre) : loop.json (projection deterministe
    # du Prisme, materialisee par run_real apres prisme.json) est injecte en FIN
    # de tuple a s3-decompo, s5-wiremap, s9-build-godot-standard ' une ENTREE a
    # lire, jamais une source de verite. Absent (runs sans exigence PLAYER, ou
    # profils qui ne materialisent pas loop.json) => omis par
    # upstream_artifacts_section, comportement inchange.
    "s3-decompo": ("charter.yaml", "artifacts/s1-prisme.txt", "artifacts/s2-worldscan.txt",
                   "artifacts/s2.6-story-bible.txt", "artifacts/s2.7-gm-worldscan.txt",
                   "art_bible.md", "asset_requests.json", "loop.json"),
    "s4-archi": ("charter.yaml", "artifacts/s3-decompo.txt",),
    # full_godot_content : le wiremap recoit aussi la Story Bible (s2.6) et l'art
    # bible + ses demandes d'assets (s2.5) ' meme raisonnement que s3-decompo
    # ci-dessus. Absents (autres profils) => omis, comportement inchange.
    "s5-wiremap": ("charter.yaml", "artifacts/s3-decompo.txt", "blueprint.json",
                   "artifacts/s2.6-story-bible.txt", "art_bible.md", "asset_requests.json",
                   "loop.json"),
    "s6-redteam-plan": ("charter.yaml", "artifacts/s3-decompo.txt", "artifacts/s4-archi.txt",
                        "artifacts/s5-wiremap.txt"),
    "s9-build": ("blueprint.json", "wiremap.json"),
    # full_godot_content : le builder Godot standard recoit blueprint+wiremap (comme
    # s9-build ci-dessus) PLUS l'art bible et ses demandes d'assets ' mesure (lot
    # full_godot_narratif) : aucune injection n'existait pour s9-build-godot-standard,
    # lecture declarative seule. Absents (autres profils) => omis par
    # upstream_artifacts_section, comportement inchange.
    # Lot B T2(b) (2026-08-23) : + economy.json (projection deterministe, derivee
    # a s2.7) ' copie STRICTEMENT identique a run_real.
    # Lot D (2026-08-23, GO Pierre, fuite 3) : copie STRICTEMENT identique a
    # run_real._UPSTREAM_BY_STEP.
    "s9-build-godot-standard": ("blueprint.json", "wiremap.json", "art_bible.md",
                                "asset_requests.json", "loop.json", "economy.json",
                                "design/gameplay_loop_content_contract.md"),
    "s11-redteam-code": ("wiremap.json",),
}



# --- hachage utilitaire (fail-soft) ------------------------------------------

def _sha256_file(path: Path) -> str | None:
    """Hash du contenu d'un fichier. ``None`` si absent/illisible — JAMAIS
    d'exception (contrairement à ``forge.verdict.sha256_file`` qui rend '')."""
    try:
        return hashlib.sha256(Path(path).read_bytes()).hexdigest()
    except OSError:
        return None


def _sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _rel_to_repo(path: Path) -> str:
    """Chemin repo-relatif (slashs POSIX) pour un affichage/stockage stable —
    best-effort : hors repo, on rend le chemin tel quel (str)."""
    try:
        return str(Path(path).resolve().relative_to(REPO_ROOT)).replace("\\", "/")
    except ValueError:
        return str(path).replace("\\", "/")


# --- résolution des sources (kind dispatch) ----------------------------------

def _source_record(path: Path, role: str) -> dict:
    p = Path(path)
    exists = p.is_file()
    return {
        "path": _rel_to_repo(p),
        "sha256": _sha256_file(p) if exists else None,
        "exists": exists,
        "role": role,
    }


def _looks_like_path(entry: str) -> bool:
    """Heuristique de tri mandatory_read : les entrées-CHEMIN du schéma des
    contrats (ex. ``forge/contracts/SCHEMA.md``) ne portent jamais
    d'espace ; les entrées NARRATIVES (ex. « l'artefact featuremap produit par
    l'étape 3 ») sont des phrases françaises à plusieurs mots. Vérifié contre
    les 14 contrats réels du dépôt (aucun contre-exemple)."""
    stripped = entry.strip()
    return bool(stripped) and " " not in stripped


def resolve_dispatch_sources(
    etape: str, contract: dict, *, run_dir: Path | None = None,
    caps_path: Path | None = None,
) -> list[dict]:
    """(a) le YAML du contrat, (b) les entrées path-like de mandatory_read,
    (c) la table amont (_UPSTREAM_BY_STEP) résolue relative à run_dir si connu,
    (d) le registry (roles.yaml). Un fichier absent ne lève jamais — il est
    simplement consigné exists:false."""
    sources: list[dict] = []

    # (a) contrat -- Lot F (2026-08-23) : alias round >=2 resolu vers le fichier
    # de la BASE (cf. forge.contract.base_step/load_contract) -- il n'existe et
    # n'existera jamais de fichier "<etape>-r2.yaml".
    sources.append(_source_record(CONTRACTS_DIR / f"{base_step(etape)}.yaml", "contract"))

    # (b) mandatory_read : seules les entrées qui RESSEMBLENT à un chemin.
    for entry in contract.get("mandatory_read") or ():
        if isinstance(entry, str) and _looks_like_path(entry):
            sources.append(_source_record(REPO_ROOT / entry.strip(), "mandatory_read"))

    # (c) artefacts amont — seulement si run_dir est connu (sinon rien à résoudre).
    if run_dir is not None:
        for rel in _UPSTREAM_BY_STEP.get(etape, ()):
            sources.append(_source_record(Path(run_dir) / rel, "upstream"))

    # (d) registry local (résout capability_role -> runtime).
    sources.append(_source_record(caps_path or FORGE_ROLES, "registry"))

    return sources


# --- dérivation du run_dir par défaut (F7) ------------------------------------
# Convention observée dans les runs réels (EVIDENCE/runs/*/state.json) :
# run_id = "<projet>-<date AAAAMMJJ>[suffixe lettre]" (ex. "shmup_slice-20260714a").
# Un run_id qui NE porte PAS ce suffixe (ex. "t1", "dryrun" — usages de test/dry-run)
# est indécidable : le manifest part alors sous un dossier orphelin dédié plutôt
# que de deviner un projet.
_RUN_ID_DATE_SUFFIX = re.compile(r"^(.+)-\d{8}[a-z]?$")


def derive_project_from_run_id(run_id: str) -> str | None:
    """Projet dérivé du run_id AVANT le dernier tiret-date, ou None si le
    run_id ne suit pas la convention ``<projet>-<AAAAMMJJ>[lettre]``."""
    m = _RUN_ID_DATE_SUFFIX.match(run_id or "")
    return m.group(1) if m else None


def default_run_dir(run_id: str) -> Path:
    """run_dir par défaut quand l'appelant n'en connaît pas un explicitement.
    Projet dérivable => EVIDENCE/runs/<projet> (même racine que le driver).
    Indécidable => EVIDENCE/runs/_orphan_context/<run_id> (jamais mélangé à
    un run_dir réel, jamais une exception)."""
    project = derive_project_from_run_id(run_id)
    if project:
        return REPO_ROOT / "EVIDENCE" / "runs" / project
    return REPO_ROOT / "EVIDENCE" / "runs" / "_orphan_context" / run_id


# --- chemin + I/O du manifest --------------------------------------------------

def manifest_path(run_dir: Path | str, etape: str) -> Path:
    return Path(run_dir) / "context" / f"{etape}.manifest.jsonl"


def _read_lines(path: Path) -> list[dict]:
    """Lignes JSON déjà présentes. Une ligne corrompue est ignorée (jamais
    bloquant) — le compteur d'activation ne doit pas planter sur un fichier
    partiellement écrit."""
    if not path.exists():
        return []
    records: list[dict] = []
    try:
        raw_text = path.read_text(encoding="utf-8")
    except OSError:
        return []
    for raw in raw_text.splitlines():
        raw = raw.strip()
        if not raw:
            continue
        try:
            rec = json.loads(raw)
        except ValueError:
            continue
        if isinstance(rec, dict):
            records.append(rec)
    return records


def _append_line(path: Path, record: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")


def _next_activation(path: Path) -> int:
    """1-based : nombre de lignes ``kind: dispatch`` déjà présentes pour cette
    étape, +1."""
    return 1 + sum(1 for rec in _read_lines(path) if rec.get("kind") == "dispatch")


# --- signature (même mécanisme que forge.verdict) -----------------------------

def _sign(body: dict, key_file: Path | None) -> str:
    return _sign_mapping(body, key_file)


def verify_manifest_record(record: dict, key_file: Path | None = None) -> bool:
    """Vrai ssi la ligne porte un HMAC valide sur son contenu (hors champ hmac)."""
    sig = record.get("hmac") if isinstance(record, dict) else None
    if not sig:
        return False
    body = {k: v for k, v in record.items() if k != "hmac"}
    return _verify_mapping(body, sig, key_file)


# --- kind "dispatch" ------------------------------------------------------------

def build_dispatch_manifest_record(
    etape: str, run_id: str, payload, contract: dict, *,
    run_dir: Path | None = None, caps_path: Path | None = None,
    ts: float | None = None, activation: int = 1,
    model_executed: str | None = None,
    reason: 'str | dict' = "",
    sources_override: list[dict] | None = None,
) -> dict:
    """Corps NON SIGNÉ de la ligne 'dispatch' (utile aux tests qui veulent
    inspecter le contenu avant signature).

    ``model`` reste — INCHANGÉ — le modèle résolu par le contrat/registry
    (``payload.model``, "déclaré"). ``model_executed`` (0.5.d, additif) porte
    le modèle qui exécute RÉELLEMENT cette tentative : ``model_executed`` si
    l'appelant en connaît un (ex. ``state["model_override"]`` après escalade
    côté driver), sinon replié sur ``payload.model`` — jamais None, jamais
    ambigu avec ``model`` (les deux sont toujours renseignés, égaux hors
    escalade). Une ligne écrite avant ce chantier n'a simplement pas ce champ
    — les lecteurs existants (``model``) restent valides tels quels.

    ``reason`` (P5, lot dégel 2, additif) : pourquoi CETTE étape démarre
    maintenant — "" par défaut (aucune décision n'affecte le dispatch : ni la
    porte C1/C2, ni le hook, ni le gate — c'est un champ PUREMENT informatif).
    Le driver, seul appelant réel en production, passe toujours une valeur
    explicite (voir ``forge.driver``) ; un appel direct de la porte (tests,
    dry-run) sans ``reason`` produit une ligne "" — jamais une valeur devinée."""
    if sources_override is not None:
        # Lot 5 (L8, 2026-09-04) : l'appelant SAIT d'où vient le contexte (sections du Blueprint) —
        # la table amont d'ORDER ne mesure pas cette convocation. Contrat + mandatory_read +
        # registre restent mesurés ; les sources fournies prennent la place des `upstream`.
        base = resolve_dispatch_sources(etape, contract, run_dir=None, caps_path=caps_path)
        sources = base[:-1] + [dict(s) for s in sources_override] + base[-1:]
    else:
        sources = resolve_dispatch_sources(etape, contract, run_dir=run_dir, caps_path=caps_path)
    return {
        "schema": SCHEMA,
        "kind": "dispatch",
        "run_id": run_id,
        "etape": etape,
        "activation": activation,
        "ts": ts if ts is not None else time.time(),
        "git_head": current_git_head() or None,
        "model": payload.model,
        "model_executed": model_executed or payload.model,
        "provider": payload.provider,
        # Lot F (2026-08-23) : meme resolution d'alias que resolve_dispatch_sources
        # ci-dessus -- le hash porte sur le fichier de contrat REELLEMENT charge.
        "contract_sha256": _sha256_file(CONTRACTS_DIR / f"{base_step(etape)}.yaml"),
        "payload_prompt_sha256": _sha256_text(payload.prompt),
        "sources": sources,
        "reason": reason,
        "claim_verdict": CLAIM_VERDICT,
    }


def append_dispatch_manifest(
    etape: str, run_id: str, payload, contract: dict, *,
    run_dir: Path | str, caps_path: Path | None = None,
    key_file: Path | None = None, ts: float | None = None,
    model_executed: str | None = None,
    reason: 'str | dict' = "",
    sources_override: list[dict] | None = None,
) -> dict:
    """Construit, signe et APPEND la ligne 'dispatch' du Context Manifest de
    cette étape. ``run_dir`` est requis ici (l'appelant — ``dispatch.py`` —
    le dérive via ``default_run_dir`` si non fourni). ``model_executed`` :
    voir ``build_dispatch_manifest_record``. ``reason`` : idem (P5)."""
    path = manifest_path(run_dir, etape)
    activation = _next_activation(path)
    record = build_dispatch_manifest_record(
        etape, run_id, payload, contract, run_dir=run_dir,
        caps_path=caps_path, ts=ts, activation=activation,
        model_executed=model_executed, reason=reason, sources_override=sources_override,
    )
    record["hmac"] = _sign(record, key_file)
    _append_line(path, record)
    return record


# --- kind "execution" -----------------------------------------------------------

def _load_model_windows(path: Path | None = None) -> dict:
    p = path or MODEL_WINDOWS_PATH
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def _normalize_model_key(key: str) -> str:
    """Tolère le style ``provider/modèle`` (roles.yaml) ET le nom court résolu
    par le registry (``get_model_for_role`` ne rend que le dernier segment) —
    les deux se comparent sur leur dernier segment, en minuscules."""
    return key.rsplit("/", 1)[-1].strip().lower()


def lookup_model_window(model: str, model_windows_path: Path | None = None) -> int | None:
    """Fenêtre de contexte (tokens) du modèle, ou None si absent de la table
    (lookup tolérant : jamais d'exception, jamais de KeyError)."""
    if not model:
        return None
    table = _load_model_windows(model_windows_path)
    target = _normalize_model_key(model)
    for key, value in table.items():
        if key.startswith("_"):
            continue
        if isinstance(value, (int, float)) and _normalize_model_key(key) == target:
            return int(value)
    return None


def _context_budget(final_prompt_chars: int, model: str,
                    model_windows_path: Path | None = None) -> dict:
    window = lookup_model_window(model, model_windows_path)
    estimated_tokens = round(final_prompt_chars / 4)
    if window is None:
        status = "UNKNOWN_WINDOW"
    elif estimated_tokens > OVERFLOW_RATIO * window:
        status = "OVERFLOW_RISK"
    else:
        status = "OK"
    return {
        "model_window_tokens": window,
        "estimated_tokens": estimated_tokens,
        "status": status,
    }


def build_execution_manifest_record(
    run_id: str, etape: str, final_prompt: str, *, model: str,
    premortem_section: str | None = None, ts: float | None = None,
    model_windows_path: Path | None = None,
    tools_effective: tuple[str, ...] = (),
    tools_disallowed_count: int = 0,
    project_brief_sha256: str | None = None,
) -> dict:
    """Corps NON SIGNÉ de la ligne 'execution'.

    R1' : la lignée RETURN ne vit PAS ici — cette ligne est écrite AVANT l'appel LLM.
    Voir `append_return_manifest` (kind 'return'), écrit après la réponse."""
    budget = _context_budget(len(final_prompt), model, model_windows_path)
    return {
        "schema": SCHEMA,
        "kind": "execution",
        "run_id": run_id,
        "etape": etape,
        "ts": ts if ts is not None else time.time(),
        "final_prompt_sha256": _sha256_text(final_prompt),
        "final_prompt_chars": len(final_prompt),
        "premortem_sha256": _sha256_text(premortem_section) if premortem_section else None,
        # FORGE_PROJECT_INPUT_V0 §3 (ratifié Pierre 2026-08-29) : empreinte du
        # Brief injecté ENTIER à s0-contrat (cf. run_real.claude_executor). Champ
        # TOUJOURS présent, None si aucun Brief à cette étape — même convention
        # que premortem_sha256 ci-dessus (le lecteur ne distingue jamais "non
        # mesuré" de "absent" par l'absence de clé).
        "project_brief_sha256": project_brief_sha256,
        # P7 (lot dégel 2, docs/forge/FORGE_CONTEXT_COMPACT_V1.md §05.6) :
        # `context_budget` ne mesurait QUE le prompt contractuel (~8 % du
        # contexte réellement reçu, ~2,6-3k tk) — un nom qui promettait plus
        # qu'il ne mesurait. Requalifié honnêtement en `prompt_budget` (MÊME
        # calcul, `_context_budget` inchangée : seul le nom change). Le champ
        # informatif `ambient_context_note` rend visible ce qui n'est PAS
        # mesuré ici — la constante ambiante (~32 775 tk/appel : hook
        # SessionStart + CLAUDE.md + .claude/rules + settings.local, non
        # défalquée de cette mesure).
        # UN SEUL nom émis : `prompt_budget`. L'ancien nom `context_budget`
        # n'est PLUS écrit (deux noms pour la même donnée = le motif « deux
        # vérités » que ce lot éradique). Les manifestes HISTORIQUES sur disque
        # portent l'ancien nom : c'est le LECTEUR (`context_check.mjs
        # extractBudget`) qui accepte les deux, avec priorité au nouveau —
        # on ne réécrit jamais les artefacts de runs passés (même principe
        # que les 17 wiremaps v1 conservées telles quelles).
        "prompt_budget": budget,
        "ambient_context_note": {
            "measured": False,
            "estimate_tokens": 32775,
            "note": ("constante ambiante non mesurée ici (hooks SessionStart + "
                     "CLAUDE.md + .claude/rules + settings.local) — voir "
                     "docs/forge/FORGE_CONTEXT_COMPACT_V1.md §02"),
        },
        # P4 (lot dégel 2, docs/forge/FORGE_CONTEXT_COMPACT_V1.md §05.1) : le
        # plancher RÉEL d'outils accordés à l'exécuteur (`run_real._STEP_TOOLS`),
        # jamais la ligne d'audit signée de dispatch.py (`allowed_tools=()`,
        # INTOUCHÉE par ce lot) — la preuve d'exécution porte enfin ce que
        # l'agent a VRAIMENT pu utiliser, pas seulement le plafond skill/plugin
        # du contrat (souvent vide par construction). Champ TOUJOURS présent
        # (tuple vide si l'étape n'a pas d'entrée dans `_STEP_TOOLS`), jamais
        # absent — un lecteur ne doit jamais avoir à distinguer "non mesuré" de
        # "zéro outil accordé" ici : les deux se lisent `[]`.
        "tools_effective": list(tools_effective),
        "tools_disallowed_count": tools_disallowed_count,
        "claim_verdict": CLAIM_VERDICT,
    }


def append_execution_manifest(
    run_id: str, etape: str, run_dir: Path | str, final_prompt: str, *, model: str,
    premortem_section: str | None = None, key_file: Path | None = None,
    ts: float | None = None, model_windows_path: Path | None = None,
    tools_effective: tuple[str, ...] = (),
    tools_disallowed_count: int = 0,
    project_brief_sha256: str | None = None,
) -> dict:
    """Construit, signe et APPEND la ligne 'execution' du Context Manifest de
    cette étape."""
    record = build_execution_manifest_record(
        run_id, etape, final_prompt, model=model, premortem_section=premortem_section,
        ts=ts, model_windows_path=model_windows_path,
        tools_effective=tools_effective, tools_disallowed_count=tools_disallowed_count,
        project_brief_sha256=project_brief_sha256,
    )
    record["hmac"] = _sign(record, key_file)
    _append_line(manifest_path(run_dir, etape), record)
    return record


def return_manifest_path(run_dir: Path | str, etape: str) -> Path:
    """Fichier jumeau de la lignée Return — voir `append_return_manifest`."""
    return Path(run_dir) / "context" / f"{etape}.return.manifest.jsonl"


def append_return_manifest(
    run_id: str, etape: str, run_dir: Path | str, reason: dict, *,
    key_file: Path | None = None, ts: float | None = None,
) -> dict:
    """R1' (GO Pierre 2026-08-13) — ligne 'return' du Context Manifest : la lignée
    RETURN du worker, écrite APRÈS sa réponse (l'enregistrement 'execution' est écrit
    AVANT l'appel LLM et ne peut donc pas la porter — mesuré, pas supposé).

    `reason` (voir `build_execution_manifest_record`) : DISCOVERED {problem,
    root_cause} => candidat mécanique à `promote_manifest_lessons` (le pont lit TOUT
    enregistrement du manifeste dont reason.problem/root_cause est non vide — aucun
    câblage supplémentaire) · NOT_DISCOVERED => honnête, ignoré par le pont ·
    NOT_TRANSMITTED => le worker n'a pas honoré la règle de restitution (défaut
    mesurable, jamais assimilé à « rien à signaler »).

    Même signature HMAC et même répertoire que dispatch/execution, dans un fichier
    JUMEAU `<etape>.return.manifest.jsonl` : les consommateurs par glob
    (`promote_manifest_lessons`, `verify_run` — `*.manifest.jsonl`) le découvrent
    sans câblage, et le fichier `<etape>.manifest.jsonl` garde EXACTEMENT sa
    structure d'avant R1' (des lecteurs existants supposent que sa dernière ligne
    est l'enregistrement 'execution' — mesuré sur les tests de garde P4/P7, pas
    supposé)."""
    record = {
        "schema": SCHEMA,
        "kind": "return",
        "run_id": run_id,
        "etape": etape,
        "reason": reason,
        "ts": ts if ts is not None else time.time(),
        "git_head": current_git_head(),
        "claim_verdict": CLAIM_VERDICT,
    }
    record["hmac"] = _sign(record, key_file)
    _append_line(return_manifest_path(run_dir, etape), record)
    return record
