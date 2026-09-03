"""Vue FLEET de Forge Observer V0 — agregation multi-projets, lecture seule.

Les autres vues du cockpit (`cockpit.py`, `views.py`) reconstruisent UN projet en
profondeur, transcripts compris. Cette vue fait le choix inverse : elle balaie
TOUS les projets connus de `lab/forge_runs/` en une passe, mais volontairement
SANS les transcripts (le troisieme adaptateur, `transcripts`, est le plus
couteux — parcourir N projets avec lui a chaque rafraichissement de tableau de
bord n'est pas soutenable). C'est un choix de cout assume et declare, pas un
oubli : la reconstruction complete par projet (avec transcripts) reste
disponible via `cli.py --project <projet>`.

Consequence directe : les tokens mesures dans les transcripts ne sont
disponibles que pour le projet courant de la session (`current_project`), dont
la reconstruction complete est deja sur disque (`current_result`, le
`observer_run.json` produit par `cli.py`). Pour tous les autres projets, la
cellule `tokens_mesures` porte NOT_OBSERVABLE avec la raison exacte de ce choix
de cout — jamais un blanc silencieux.

Chaque projet est reconstruit dans son PROPRE `ObserverContext` : les racines
lisibles d'`ObserverContext` sont par construction specifiques a un projet
(voir `sources.py`), donc lire un autre projet necessite un contexte dedie,
jamais un partage de contexte entre projets. C'est le mecanisme prevu par
`ObserverContext.build`, pas un contournement.

Regle non negociable, deja posee par `cockpit.py` : un manque de mesure ne
devient jamais un OK. Une cellule sans donnee porte NOT_OBSERVABLE et sa
raison.
"""

from __future__ import annotations

import logging
import re
import sys
import time
from pathlib import Path
from typing import Any, Optional

_HERE = Path(__file__).resolve().parent
if str(_HERE.parent) not in sys.path:  # rend `import observer` possible sans install
    sys.path.insert(0, str(_HERE.parent))

from observer.adapters import forge_evidence, forge_run  # noqa: E402
from observer.correlate import reconstruct  # noqa: E402
from observer.events import Event  # noqa: E402
from observer.sources import BlindnessViolation, ObserverContext  # noqa: E402

LOG = logging.getLogger("observer.fleet")

NAME = "fleet"

NOT_OBSERVABLE = "NOT_OBSERVABLE"

# Phrase EXACTE exigee par la mission de fabrication : elle documente le choix
# de cout de balayage pour tout projet qui n'est pas le projet courant de la
# session (transcripts non recollectes pour lui dans cette vue).
NOTE_COUT_BALAYAGE = (
    "transcripts non correles pour ce projet dans cette vue — choix de cout de "
    "balayage, la reconstruction complete par projet reste disponible via "
    "--project"
)

# Colonnes de la vue Fleet, dans l'ordre d'affichage.
FLEET_COLONNES: tuple[tuple[str, str], ...] = (
    ("projet", "projet"),
    ("run_id", "run"),
    ("nom_humain", "session"),
    ("role", "role"),
    ("decision", "decision"),
    ("duree_s", "duree (s)"),
    ("cout_declare_usd", "cout declare ($)"),
    ("tokens_mesures", "tokens mesures"),
    ("mutation", "mutation"),
    ("tests", "tests"),
    ("failure_events", "failure_events"),
    ("activations", "activations"),
)

# --------------------------------------------------------------------------- #
# Noms humains — transformation mecanique, jamais une table maintenue a la main
# --------------------------------------------------------------------------- #

# Prefixe de sequence : 1 a 3 lettres, 1 a 3 chiffres, decimale optionnelle
# (`s2.5-`), lettre finale optionnelle (`s10s-`), puis un tiret. Borne en
# longueur de lettres pour ne jamais confondre un mot ordinaire finissant par
# un chiffre (ex. hypothetique `level2-boss`, 5 lettres, hors de la borne) avec
# un vrai code d'etape (`s9-`, `wm1-`, `gb1-`, `n2-`, tous <= 3 lettres).
_ETAPE_PREFIX_RE = re.compile(r"^[a-z]{1,3}\d{1,3}(?:\.\d+)?[a-z]?-")
_WORD_SPLIT_RE = re.compile(r"[-_]+")
_RUN_NUM_RE = re.compile(r"-run(\d+)-")

# Dossiers de tentative archivee : jamais un projet a part entiere, meme s'ils
# sont l'endroit ou vit le seul `state.json` d'un projet plus ancien (ex.
# `snake/_run_cal1_20260730/state.json`).
_ATTEMPT_DIR_RE = re.compile(r"^_(run|blocked|halted)", re.IGNORECASE)


def human_name_etape(etape: str) -> str:
    """Transforme un identifiant d'etape en libelle lisible, mecaniquement.

    Retire un eventuel prefixe de sequence (`s9-`, `s10s-`, `s2.5-`, `wm1-`,
    `gb1-`, `n2-`, ...), remplace les separateurs par des espaces, capitalise
    chaque mot. Aucune table : si le motif ne correspond a rien de connu, le
    mot est simplement capitalise tel quel (cas generique lisible, ex.
    `orchestrator` -> `Orchestrator`).
    """
    if not etape:
        return etape

    stripped = _ETAPE_PREFIX_RE.sub("", etape, count=1)
    if not stripped:
        # Le prefixe a consomme la chaine entiere (improbable) : repli sur le
        # brut plutot que de rendre une etiquette vide.
        stripped = etape

    words = [w for w in _WORD_SPLIT_RE.split(stripped) if w]
    if not words:
        return etape
    return " ".join(w[:1].upper() + w[1:] for w in words)


def human_name_session(project: str, etape: str, run_id: str) -> str:
    """Compose `<Projet> · <Etape humaine> · run <n>`.

    `n` est extrait du run_id par le motif `-run(\\d+)-` (ex. `breakout_v2-
    run2-20260731-101252` -> `2`). Beaucoup de run_id plus anciens ne portent
    pas ce motif (`pong-01`, `snake-cal1-20260730-142335`) : dans ce cas `n`
    est le suffixe brut du run_id une fois le prefixe `<project>-` retire,
    jamais invente.
    """
    run_id = run_id or ""

    match = _RUN_NUM_RE.search(run_id)
    if match:
        n = match.group(1)
    else:
        prefix = f"{project}-"
        n = run_id[len(prefix):] if run_id.startswith(prefix) else (run_id or "?")

    # Un nom n'est pas une mesure : une etape absente (nom de RUN, pas de
    # session) fait simplement disparaitre le segment — NOT_OBSERVABLE est
    # reserve aux cellules de donnees, pas aux libelles de confort.
    if etape:
        return f"{project} · {human_name_etape(etape)} · run {n}"
    return f"{project} · run {n}"


# --------------------------------------------------------------------------- #
# Decouverte des projets
# --------------------------------------------------------------------------- #


def list_projects(repo_root: Path) -> list[str]:
    """Dossiers de `lab/forge_runs/*/` contenant un `state.json`.

    Exclut les entrees qui sont des fichiers (ex. `RUN_INDEX.md`,
    `_tmp_shmup_patch_tasks3.json`) et les dossiers prefixes `_` (ex.
    `_orphan_context`). La recherche de `state.json` est recursive : plusieurs
    projets reels (ex. `snake`) n'ont plus de `state.json` a leur racine, ce
    fichier n'existant que dans leurs sous-dossiers de tentative archivee
    (`_run*` / `_blocked*` / `_halted*`) — exactement le perimetre que
    `forge_run.collect` sait deja parcourir. Un projet dont AUCUN `state.json`
    n'existe nulle part (ex. `card_engine`, `chesscolor` : runs d'avant
    l'introduction du driver a etat) n'est pas un projet Fleet reconstruisible
    par cet adaptateur et n'est pas liste ici.
    """
    base = repo_root / "lab" / "forge_runs"
    if not base.is_dir():
        return []

    projects: list[str] = []
    for entry in sorted(base.iterdir(), key=lambda p: p.name):
        if not entry.is_dir():
            continue
        if entry.name.startswith("_"):
            continue
        try:
            has_state = next(entry.rglob("state.json"), None) is not None
        except OSError as exc:
            LOG.warning("balayage de %s impossible: %s", entry, exc)
            continue
        if has_state:
            projects.append(entry.name)
    return projects


# --------------------------------------------------------------------------- #
# Aides de lecture d'evenements (objets `Event`, pas des dicts — cette vue
# n'a pas besoin de serialiser avant d'agreger, contrairement a cockpit.py qui
# travaille sur des dicts deja ecrits sur disque).
# --------------------------------------------------------------------------- #


def _first_event(events: list[Event], kind: str, run_id: Optional[str]) -> Optional[Event]:
    for ev in events:
        if ev.kind == kind and ev.run_id == run_id:
            return ev
    return None


def _count_events(events: list[Event], kind: str, run_id: Optional[str]) -> int:
    return sum(1 for ev in events if ev.kind == kind and ev.run_id == run_id)


def _cell(value: Any, src: Optional[dict] = None, why: Optional[str] = None) -> dict[str, Any]:
    out: dict[str, Any] = {"v": value}
    if src:
        out["src"] = src
    if value == NOT_OBSERVABLE and why:
        out["why"] = why
    return out


def _tokens_for_run(current_result: dict[str, Any], run_id: str) -> Optional[dict[str, int]]:
    """Totaux de tokens mesures pour `run_id`, lus dans `current_result` deja
    reconstruit (celui-ci, contrairement a cette vue, a collecte les
    transcripts)."""
    for run in current_result.get("runs", []) or []:
        if run.get("run_id") != run_id:
            continue
        totals = run.get("totals") or {}
        mesures = totals.get("tokens_measured_in_transcripts")
        if not mesures:
            return None
        return {
            "input": mesures.get("input", 0),
            "output": mesures.get("output", 0),
            "cache_read": mesures.get("cache_read", 0),
            "cache_creation": mesures.get("cache_creation", 0),
        }
    return None


# --------------------------------------------------------------------------- #
# Reconstruction d'un seul projet (forge_run + forge_evidence uniquement)
# --------------------------------------------------------------------------- #


def _collect_project_events(ctx: ObserverContext) -> list[Event]:
    """Adaptateurs `forge_run` et `forge_evidence` SEULS — pas `transcripts`.

    C'est le choix de cout de la vue Fleet, declare dans le module docstring
    et dans `NOTE_COUT_BALAYAGE` : balayer N projets avec l'adaptateur
    transcripts (le plus lourd, il parcourt les fichiers `.jsonl` de session)
    a chaque rafraichissement n'est pas soutenable.
    """
    events: list[Event] = []
    events.extend(forge_run.collect(ctx))
    events.extend(forge_evidence.collect(ctx))
    return events


def _ligne_erreur(projet: str, exc: Exception) -> dict[str, Any]:
    return {
        "projet": projet,
        "v": "ERREUR",
        "why": f"{type(exc).__name__}: {exc}",
    }


def _ligne_attempt(
    projet: str,
    run: dict[str, Any],
    events: list[Event],
    current_project: str,
    current_result: dict[str, Any],
) -> dict[str, Any]:
    run_id = run["run_id"]
    decision = run.get("decision")
    duree = (run.get("window") or {}).get("duration_s")
    totals = run.get("totals") or {}
    cout = totals.get("cost_usd_declared")

    verdict_ev = _first_event(events, "verdict.signed", run_id)
    tests_ev = _first_event(events, "test.result", run_id)
    mutation_ev = _first_event(events, "mutation.result", run_id)
    declared_ev = _first_event(events, "run.declared", run_id)

    activations = _count_events(events, "dispatch.executed", run_id)
    failures = _count_events(events, "failure.event", run_id)

    # Nom de RUN, pas de session : a cette granularite l'etape n'a pas de sens
    # (« Verdict · run 3 » laisserait croire que le run n'a fait que l'etape
    # finale). L'etape reste pertinente pour nommer une SESSION d'agent.
    nom_humain = human_name_session(projet, "", run_id)

    if projet == current_project:
        mesures = _tokens_for_run(current_result, run_id)
        tokens_total = None
        if mesures:
            tokens_total = mesures["input"] + mesures["output"] + mesures["cache_creation"]
        tokens_cell = _cell(
            tokens_total if tokens_total else NOT_OBSERVABLE,
            {
                "path": f"EVIDENCE/reports/observer/{projet}/observer_run.json",
                "field": "runs[].totals.tokens_measured_in_transcripts",
            },
            "aucun transcript rattache a ce run dans la reconstruction courante",
        )
    else:
        tokens_cell = _cell(NOT_OBSERVABLE, None, NOTE_COUT_BALAYAGE)

    return {
        "projet": _cell(projet),
        # `role` vient de classify_run : `pre_run` sur un run pilote signifie
        # « nommage hors motif -runN- », pas « pas une tentative » — la colonne
        # reste visible precisement pour que cette nuance ne disparaisse pas.
        "role": _cell(run.get("role")),
        "run_id": _cell(run_id, {"path": f"lab/forge_runs/{projet}"}),
        "nom_humain": _cell(nom_humain),
        "decision": _cell(
            decision or NOT_OBSERVABLE,
            verdict_ev.source.to_dict() if verdict_ev else None,
            "aucun verdict signe n'existe pour ce run",
        ),
        "duree_s": _cell(
            duree if duree is not None else NOT_OBSERVABLE,
            declared_ev.source.to_dict() if declared_ev else None,
            "aucun evenement date rattache a ce run",
        ),
        "cout_declare_usd": _cell(
            cout if cout is not None else NOT_OBSERVABLE,
            None,
            "la telemetrie ne porte pas de cout pour ce run",
        ),
        "tokens_mesures": tokens_cell,
        "mutation": _cell(
            f"{mutation_ev.payload.get('killed')}/{mutation_ev.payload.get('total')}"
            if mutation_ev else NOT_OBSERVABLE,
            mutation_ev.source.to_dict() if mutation_ev else None,
            "aucun recu de mutation pour ce run",
        ),
        "tests": _cell(
            f"{tests_ev.payload.get('passed')}/{tests_ev.payload.get('failed')} (ok/ko)"
            if tests_ev else NOT_OBSERVABLE,
            tests_ev.source.to_dict() if tests_ev else None,
            "aucun oracle de test n'a produit de resultat pour ce run",
        ),
        "failure_events": _cell(failures),
        "activations": _cell(activations),
        "_debut": (run.get("window") or {}).get("start") or "",
    }


def _reconstruire_projet(
    repo_root: Path,
    transcripts_root: Path,
    projet: str,
    current_project: str,
    current_result: dict[str, Any],
) -> list[dict[str, Any]]:
    """Contexte dedie, adaptateurs bornes, une ligne par run role=='attempt'.

    Ne rattrape JAMAIS `BlindnessViolation` : une tentative de lecture hors des
    racines autorisees pour CE projet doit arreter net la reconstruction Fleet
    plutot que produire un resultat dont la validite est compromise pour tous
    les projets.
    """
    ctx = ObserverContext.build(repo_root, projet, transcripts_root)
    events = _collect_project_events(ctx)
    result = reconstruct(events, projet, ctx.read_paths)

    lignes: list[dict[str, Any]] = []
    for run in result.get("runs", []):
        # Critere d'appartenance a la flotte : « le driver l'a pilote », pas
        # « son nom ressemble a celui de Breakout ». `classify_run` ne reconnait
        # `attempt` que sur le motif `-runN-` — or pong-01, snake-cal1-...,
        # shmup_slice-20260714a sont des runs pilotes reels avec statut et/ou
        # verdict. On inclut donc tout run porteur d'une preuve de pilotage,
        # et la colonne `role` reste visible pour ne rien confondre.
        if run.get("role") == "dryrun":
            continue
        piloted = (
            run.get("role") == "attempt"
            or run.get("run_status") is not None
            or run.get("decision") is not None
        )
        if not piloted:
            continue
        lignes.append(
            _ligne_attempt(projet, run, events, current_project, current_result)
        )
    return lignes


# --------------------------------------------------------------------------- #
# Assemblage
# --------------------------------------------------------------------------- #


def view_fleet(
    repo_root: Path,
    transcripts_root: Path,
    current_project: str,
    current_result: dict[str, Any],
) -> dict[str, Any]:
    """Vue agregee multi-projets : une ligne par run de tentative, tous
    projets confondus, sans les transcripts (voir docstring de module)."""
    debut = time.perf_counter()

    projets = list_projects(repo_root)
    lignes: list[dict[str, Any]] = []

    for projet in projets:
        try:
            lignes.extend(
                _reconstruire_projet(
                    repo_root, transcripts_root, projet, current_project, current_result
                )
            )
        except BlindnessViolation:
            raise
        except Exception as exc:  # noqa: BLE001 - un projet en echec ne bloque pas les autres
            LOG.error("reconstruction Fleet de %s en echec: %s", projet, exc, exc_info=True)
            lignes.append(_ligne_erreur(projet, exc))

    # Plus recent en haut. Les lignes ERREUR n'ont pas de fenetre temporelle :
    # elles n'ont pas de cle "_debut", donc elles descendent naturellement en
    # bas du tri (chaine vide = la plus petite valeur lexicographique).
    lignes.sort(key=lambda l: l.get("_debut", ""), reverse=True)
    for ligne in lignes:
        ligne.pop("_debut", None)

    duree_s = round(time.perf_counter() - debut, 3)

    out: dict[str, Any] = {
        "colonnes": [{"cle": k, "titre": t} for k, t in FLEET_COLONNES],
        "lignes": lignes,
        "projets": projets,
        "note_cout_balayage": NOTE_COUT_BALAYAGE,
        "duree_construction_s": duree_s,
    }
    if duree_s > 30:
        out["avertissement_performance"] = (
            f"construction de la vue Fleet : {duree_s}s (> 30s) sur "
            f"{len(projets)} projet(s) — aucun projet n'a ete saute pour tenir "
            "un budget de temps, la limite est rapportee telle quelle"
        )
        LOG.warning("view_fleet a depasse 30s: %.3fs pour %d projets", duree_s, len(projets))
    return out


# --------------------------------------------------------------------------- #
# Preuve d'execution
# --------------------------------------------------------------------------- #

if __name__ == "__main__":
    import json

    logging.basicConfig(level=logging.WARNING, format="%(levelname)s %(name)s: %(message)s")

    from observer.sources import default_repo_root, default_transcripts_root  # noqa: E402

    _repo_root = default_repo_root()
    _transcripts_root = default_transcripts_root(_repo_root)
    _current_project = "breakout_v2"
    _current_result_path = (
        _repo_root / "EVIDENCE" / "reports" / "observer" / _current_project / "observer_run.json"
    )
    with _current_result_path.open("r", encoding="utf-8") as _fh:
        _current_result = json.load(_fh)

    _out = view_fleet(_repo_root, _transcripts_root, _current_project, _current_result)

    print(f"projets trouves : {_out['projets']}")
    print(f"lignes           : {len(_out['lignes'])}")
    print(f"duree            : {_out['duree_construction_s']}s")
    if "avertissement_performance" in _out:
        print(f"avertissement    : {_out['avertissement_performance']}")
    print()
    print("8 premieres lignes (projet, nom humain, decision, mutation) :")
    for _ligne in _out["lignes"][:8]:
        if _ligne.get("v") == "ERREUR":
            print(f"  ERREUR projet={_ligne['projet']} why={_ligne['why']}")
            continue
        print(
            f"  {_ligne['projet']['v']:<14} | {_ligne['nom_humain']['v']:<55} | "
            f"{_ligne['decision']['v']:<20} | mutation={_ligne['mutation']['v']}"
        )

    print()
    print("3 exemples human_name_etape :")
    for _etape in ("s9-build-godot-standard", "s11-redteam-code", "wm1-wiremap-breakout"):
        print(f"  {_etape!r:<32} -> {human_name_etape(_etape)!r}")
