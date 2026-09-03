"""Vues SYSTEME de la console Observer — le fonctionnement de la Forge elle-meme.

Trois vues, plus leur assemblage :

    s1_workflow  — les 9 blocs ratifies du pipeline (World Scan -> Knowledge
                   Base -> Architect -> WireMap -> Builder -> Runtime ->
                   Observer -> Lessons -> retour KB), chacun avec son etat
                   (ACTIF/DORMANT/NOT_OBSERVABLE), son producteur, son
                   consommateur, ses derniers artefacts et les drifts qui le
                   concernent.
    s5_artefacts — l'arbre des artefacts (Charters / Wiremaps / World Scan /
                   Knowledge / Skills / Contracts / Lessons / Reports / Games /
                   Runtime) : ce qui existe reellement sous chaque racine
                   lisible, avec pour chaque artefact son producteur (traces
                   file.write/wiremap) et DEUX listes de consommateurs -- ceux
                   qui le DECLARENT (mandatory_read des contrats) et ceux qui
                   l'OBSERVENT (file.read reel). L'ecart entre les deux est le
                   signal utile : un artefact declare mandatory_read jamais lu
                   en reel est un drift potentiel, jamais une conclusion toute
                   faite.
    s7_flow      — la chaine produit -> consomme -> valide -> archive,
                   instanciee sur les donnees reelles du projet observe.

Ce module ne lit rien lui-meme : toute lecture passe par `ObserverContext`
(`ctx.read_text` / `ctx.read_json` / `ctx.iter_files` / `ctx.exists`), qui leve
`BlindnessViolation` si une racine non declaree est touchee. Cette exception
n'est JAMAIS rattrapee ici -- la garde est prise EN AMONT : `_is_allowed`
reproduit la meme regle de correspondance que `ObserverContext._check` en
lecture pure (aucune E/S), pour decider AVANT tout appel `ctx.*` si le chemin
est dans le perimetre. Un chemin hors perimetre ne declenche donc jamais
l'exception -- il produit une cellule `NOT_OBSERVABLE` motivee.

Regle non negociable, identique aux autres vues Observer : un manque de mesure
ne devient jamais un OK. Une cellule sans preuve porte `NOT_OBSERVABLE` et sa
raison -- jamais 0 par defaut, jamais vide, jamais devine.
"""

from __future__ import annotations

import logging
import re
import time
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

LOG = logging.getLogger("observer.system_artefacts")

NOT_OBSERVABLE = "NOT_OBSERVABLE"

_RECENT_WINDOW_S = 7 * 86400  # ACTIF si la derniere trace datee a moins de 7 jours

# Un token qui ressemble a un chemin de depot : extensions reellement rencontrees
# dans les mandatory_read des contrats Forge (voir scripts/forge/contracts/*.yaml).
_PATH_TOKEN_RE = re.compile(r"[A-Za-z0-9_\-./]+\.(?:md|yaml|yml|json|py|gd|mjs|js|html)")


# --------------------------------------------------------------------------- #
# Aides communes -- meme contrat de cellule que cockpit.py/command.py :
# {v, src?, why?}
# --------------------------------------------------------------------------- #


def _cell(value: Any, src: Optional[dict[str, Any]] = None,
          why: Optional[str] = None) -> dict[str, Any]:
    out: dict[str, Any] = {"v": value}
    if src:
        out["src"] = src
    if value == NOT_OBSERVABLE and why:
        out["why"] = why
    return out


def _kinds(events: list[dict[str, Any]], kinds: tuple[str, ...],
           run_id: Optional[str] = None,
           etapes: Optional[tuple[str, ...]] = None) -> list[dict[str, Any]]:
    out = [e for e in events if e.get("kind") in kinds]
    if run_id:
        out = [e for e in out if e.get("run_id") == run_id]
    if etapes:
        out = [e for e in out if e.get("etape") in etapes]
    return out


def _cite(ev: dict[str, Any], field: Optional[str] = None) -> dict[str, Any]:
    src = ev.get("source", {}) or {}
    out: dict[str, Any] = {"path": src.get("path", "")}
    if src.get("line") is not None:
        out["line"] = src["line"]
    if field or src.get("field"):
        out["field"] = field or src.get("field")
    out["event_id"] = ev.get("event_id")
    return out


def _span(evs: list[dict[str, Any]]) -> dict[str, Any]:
    dated = [e for e in evs if e.get("ts")]
    if not dated:
        return {"premiere": None, "derniere": None}
    first = min(dated, key=lambda e: e["ts"])
    last = max(dated, key=lambda e: e["ts"])
    return {"premiere": first.get("ts_iso"), "derniere": last.get("ts_iso"),
            "derniere_epoch": last["ts"]}


# --------------------------------------------------------------------------- #
# Garde de perimetre -- reproduit ObserverContext._check en LECTURE PURE
# (aucune E/S), pour ne jamais declencher BlindnessViolation. Cette fonction
# n'ouvre aucun fichier : elle compare des Path, comme le fait deja
# ObserverContext._check avant d'autoriser une lecture.
# --------------------------------------------------------------------------- #


def _is_allowed(ctx: Any, path: Path) -> bool:
    try:
        resolved = Path(path).resolve()
    except OSError:
        return False
    for root in ctx.allowed_roots:
        try:
            resolved.relative_to(root)
            return True
        except ValueError:
            continue
    return False


def _norm(ctx: Any, raw: Optional[str]) -> Optional[str]:
    """Chemin relatif au depot, slash avant, minuscule -- pour comparaison
    UNIQUEMENT (l'affichage garde la casse via `ctx.rel` seul). `ctx.rel` ne
    fait aucune E/S et n'est pas gardee par `_check` : elle ne peut jamais
    lever `BlindnessViolation`."""
    if not raw:
        return None
    try:
        rel = ctx.rel(Path(raw))
    except (OSError, ValueError):
        return None
    return rel.replace("\\", "/").lower()


def _meta(path: Path) -> dict[str, Any]:
    """Metadonnees d'un fichier deja valide par `_is_allowed` (via
    `_dir_files`/`_single_file`) -- pas une nouvelle lecture de contenu."""
    try:
        st = path.stat()
    except OSError:
        return {"mtime": None, "mtime_epoch": None, "taille_octets": None}
    return {
        "mtime": datetime.fromtimestamp(st.st_mtime, tz=timezone.utc).isoformat(),
        "mtime_epoch": st.st_mtime,
        "taille_octets": st.st_size,
    }


def _dir_files(ctx: Any, root: Path, excludes: tuple[str, ...] = ()) -> Optional[list[Path]]:
    """Fichiers reels sous `root`. None si `root` est hors des racines
    autorisees d'Observer (categorie NOT_OBSERVABLE par construction, pas par
    absence de contenu) ; liste (eventuellement vide) sinon."""
    if not _is_allowed(ctx, root):
        return None
    out: list[Path] = []
    for p in ctx.iter_files(root):
        if not p.is_file():
            continue  # ctx.iter_files (rglob "*") rend aussi les dossiers
        relp = ctx.rel(p).replace("\\", "/")
        if any(ex in relp for ex in excludes):
            continue
        out.append(p)
    return out


def _single_file(ctx: Any, path: Path) -> Optional[list[Path]]:
    """Meme contrat que `_dir_files` pour un fichier unique declare."""
    if not _is_allowed(ctx, path):
        return None
    return [path] if ctx.exists(path) else []


def _index_by_path(ctx: Any, events: list[dict[str, Any]],
                    kinds: tuple[str, ...]) -> dict[str, list[dict[str, Any]]]:
    """Index chemin-normalise -> evenements, pour les kinds portant un
    `payload.path` (file.read / file.write / file.edit)."""
    idx: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for ev in events:
        if ev.get("kind") not in kinds:
            continue
        raw = (ev.get("payload") or {}).get("path")
        norm = _norm(ctx, raw)
        if norm:
            idx[norm].append(ev)
    return idx


# --------------------------------------------------------------------------- #
# Contrats -- source des consommateurs DECLARES (mandatory_read)
# --------------------------------------------------------------------------- #


def _load_contracts(ctx: Any) -> dict[str, dict[str, Any]]:
    """Charge tous les contrats *.yaml lisibles sous scripts/forge/contracts/.

    Import PyYAML tardif : meme discipline que scripts/forge/contract.py et
    scripts/forge/reasoning_observability.py (« yaml absent hors venv »).
    PyYAML absent -> dict vide, jamais une exception qui ferait echouer toute
    la vue : c'est une categorie de donnee NOT_OBSERVABLE parmi d'autres.
    """
    contracts_dir = ctx.repo_root / "scripts" / "forge" / "contracts"
    out: dict[str, dict[str, Any]] = {}
    files = _dir_files(ctx, contracts_dir)
    if not files:
        return out
    try:
        import yaml
    except ImportError:
        LOG.warning("PyYAML indisponible dans cet interpreteur : contrats non parses")
        return out
    for path in files:
        if path.suffix.lower() != ".yaml":
            continue
        text = ctx.read_text(path)
        if text is None:
            continue
        try:
            data = yaml.safe_load(text)
        except yaml.YAMLError as exc:
            LOG.warning("contrat illisible %s: %s", ctx.rel(path), exc)
            continue
        if isinstance(data, dict):
            out[path.stem] = {"data": data, "path": ctx.rel(path).replace("\\", "/")}
    return out


def _resolve_mandatory_read(ctx: Any, contracts: dict[str, dict[str, Any]],
                             project: Optional[str]) -> dict[str, list[dict[str, Any]]]:
    """Index chemin-normalise -> contrats qui le DECLARENT dans mandatory_read.

    Une entree `mandatory_read` est parfois un chemin litteral
    (`scripts/forge/contracts/SCHEMA.md`), parfois de la prose qui EN CONTIENT
    un (`« le squelette gele du jeu courant (09_WIREMAP/wiremap.json) »`). On
    extrait le token qui ressemble a un chemin, puis on tente deux
    resolutions -- litterale, puis prefixee par games/<project>/ -- et on ne
    retient QUE celle dont l'existence est confirmee (`ctx.exists`, apres
    verification `_is_allowed` : jamais de sonde hors perimetre). Un token qui
    ne resout nulle part reste un fait a part -- `mandatory_read_non_resolu`,
    retourne separement -- jamais force sur un artefact au hasard.
    """
    declares_idx: dict[str, list[dict[str, Any]]] = defaultdict(list)
    unresolved: list[dict[str, Any]] = []

    for name, contract in sorted(contracts.items()):
        raw_items = contract["data"].get("mandatory_read")
        if not isinstance(raw_items, list):
            continue
        for item in raw_items:
            if not isinstance(item, str):
                continue
            tokens = _PATH_TOKEN_RE.findall(item)
            if not tokens:
                unresolved.append({
                    "contrat": name, "raw": item,
                    "raison": "aucun token ressemblant a un chemin dans cette entree",
                })
                continue
            for token in tokens:
                resolved_path = None
                resolution = None
                hors_perimetre = 0
                candidates = [ctx.repo_root / token]
                if project:
                    candidates.append(ctx.repo_root / "games" / project / token)
                for idx, candidate in enumerate(candidates):
                    if not _is_allowed(ctx, candidate):
                        hors_perimetre += 1
                        continue
                    if ctx.exists(candidate):
                        resolved_path = candidate
                        resolution = "litteral" if idx == 0 else "prefixe_games_projet"
                        break
                if resolved_path is None:
                    if hors_perimetre == len(candidates):
                        raison = ("le(s) chemin(s) candidat(s) ne sont dans aucune racine "
                                   "lisible d'Observer -- existence non verifiable ici")
                    else:
                        raison = ("chemin(s) candidat(s) dans le perimetre lisible mais "
                                   "aucun fichier n'y existe reellement")
                    unresolved.append({
                        "contrat": name, "raw": item, "token": token, "raison": raison,
                    })
                    continue
                norm = _norm(ctx, str(resolved_path))
                if norm:
                    declares_idx[norm].append({
                        "contrat": name,
                        "raw": item,
                        "resolution": resolution,
                        "src": {"path": contract["path"]},
                    })

    return {"declares_idx": dict(declares_idx), "unresolved": unresolved}


def _short(text: str, limit: int = 160) -> str:
    text = " ".join(text.split())
    return text if len(text) <= limit else text[:limit].rstrip() + "…"


def _resolve_tests_oracles(ctx: Any, contracts: dict[str, dict[str, Any]],
                            project: Optional[str]) -> dict[str, Any]:
    """Meme mecanique de resolution que `_resolve_mandatory_read`, pour le champ
    `tests_oracles` (champ #11 du schema, voir SCHEMA.md) -- source des consommateurs
    QUI VALIDENT un artefact (oracles/tests cites par le contrat).

    Difference de forme assumee : `mandatory_read` est presque toujours une LISTE de
    chemins, `tests_oracles` est le plus souvent un bloc de PROSE (`>-`) qui peut
    contenir zero, un ou plusieurs chemins. On normalise les deux formes (str ou
    list[str]) en une liste d'items avant d'appliquer la meme extraction de token +
    resolution litterale/prefixee que pour `mandatory_read`.
    """
    declares_idx: dict[str, list[dict[str, Any]]] = defaultdict(list)
    unresolved: list[dict[str, Any]] = []

    for name, contract in sorted(contracts.items()):
        raw = contract["data"].get("tests_oracles")
        if isinstance(raw, str):
            raw_items = [raw]
        elif isinstance(raw, list):
            raw_items = [x for x in raw if isinstance(x, str)]
        else:
            continue

        for item in raw_items:
            tokens = _PATH_TOKEN_RE.findall(item)
            if not tokens:
                unresolved.append({
                    "contrat": name, "raw": _short(item),
                    "raison": "aucun token ressemblant a un chemin dans ce champ tests_oracles",
                })
                continue
            for token in tokens:
                resolved_path = None
                resolution = None
                hors_perimetre = 0
                candidates = [ctx.repo_root / token]
                if project:
                    candidates.append(ctx.repo_root / "games" / project / token)
                for idx, candidate in enumerate(candidates):
                    if not _is_allowed(ctx, candidate):
                        hors_perimetre += 1
                        continue
                    if ctx.exists(candidate):
                        resolved_path = candidate
                        resolution = "litteral" if idx == 0 else "prefixe_games_projet"
                        break
                if resolved_path is None:
                    if hors_perimetre == len(candidates):
                        raison = ("le(s) chemin(s) candidat(s) ne sont dans aucune racine "
                                   "lisible d'Observer -- existence non verifiable ici")
                    else:
                        raison = ("chemin(s) candidat(s) dans le perimetre lisible mais "
                                   "aucun fichier n'y existe reellement")
                    unresolved.append({
                        "contrat": name, "raw": _short(item), "token": token, "raison": raison,
                    })
                    continue
                norm = _norm(ctx, str(resolved_path))
                if norm:
                    declares_idx[norm].append({
                        "contrat": name,
                        "raw": _short(item),
                        "resolution": resolution,
                        "src": {"path": contract["path"]},
                    })

    return {"declares_idx": dict(declares_idx), "unresolved": unresolved}


# --------------------------------------------------------------------------- #
# Oracles observes -- source des consommateurs QUI VALIDENT (evenements reels)
# --------------------------------------------------------------------------- #

_ORACLE_KINDS: tuple[str, ...] = ("test.result", "mutation.result", "solvability.result",
                                   "oracle.result")


def _index_oracle_events_by_run(events: list[dict[str, Any]]) -> dict[Optional[str], list[dict[str, Any]]]:
    idx: dict[Optional[str], list[dict[str, Any]]] = defaultdict(list)
    for ev in events:
        if ev.get("kind") in _ORACLE_KINDS:
            idx[ev.get("run_id")].append(ev)
    return dict(idx)


# --------------------------------------------------------------------------- #
# Archive -- source des consommateurs QUI ARCHIVENT (dossiers _run*/_blocked*/_halted*)
# --------------------------------------------------------------------------- #


def _in_archive_dir(relp: str) -> bool:
    return any(re.match(r"^_(run|blocked|halted)", seg, re.IGNORECASE)
               for seg in relp.split("/"))


def _build_archive_index(ctx: Any) -> Optional[dict[str, list[str]]]:
    """basename (minuscule) -> chemins relatifs des copies archivees qui le portent.

    None si `lab/forge_runs/<projet>` est hors perimetre lisible (categorie
    NOT_OBSERVABLE par construction, comme `_dir_files`) ; dict (eventuellement vide)
    sinon.
    """
    run_dir = ctx.run_dir
    if not _is_allowed(ctx, run_dir):
        return None
    idx: dict[str, list[str]] = defaultdict(list)
    for p in ctx.iter_files(run_dir):
        if not p.is_file():
            continue
        relp = ctx.rel(p).replace("\\", "/")
        if not _in_archive_dir(relp):
            continue
        idx[p.name.lower()].append(relp)
    return {k: sorted(set(v)) for k, v in idx.items()}


# --------------------------------------------------------------------------- #
# Artefact -- fiche commune (quatre roles : produit_par / consomme_par /
# valide_par / archive_par -- meme vocabulaire que s7_flow, fusion conceptuelle
# demandee. produit_par/consomme_par sont des ALIAS de producteur/consommateurs
# (meme calcul, rien de duplique) -- valide_par/archive_par sont nouveaux.
# --------------------------------------------------------------------------- #


def _producer_info(write_idx: dict[str, list[dict[str, Any]]],
                    norm_path: str) -> tuple[Optional[dict[str, Any]], Optional[dict[str, Any]]]:
    evs = write_idx.get(norm_path) or []
    if not evs:
        return None, None
    dated = [e for e in evs if e.get("ts")]
    first = min(dated, key=lambda e: e["ts"]) if dated else evs[0]
    info = {
        "etape": first.get("etape") or NOT_OBSERVABLE,
        "run_id": first.get("run_id") or NOT_OBSERVABLE,
        "session_id": (first.get("actor") or {}).get("session_id") or NOT_OBSERVABLE,
        "n_ecritures": len(evs),
    }
    return info, first


def _observed_consumers(read_idx: dict[str, list[dict[str, Any]]],
                         norm_path: str) -> dict[str, Any]:
    evs = read_idx.get(norm_path) or []
    if not evs:
        return {"n": 0, "etapes": [], "src": None}
    etapes = sorted({e.get("etape") for e in evs if e.get("etape")})
    return {"n": len(evs), "etapes": etapes, "src": _cite(evs[0], "path")}


def _valide_par(valid_idx: dict[str, list[dict[str, Any]]],
                 oracle_by_run: dict[Optional[str], list[dict[str, Any]]],
                 norm_path: str, producer_run_id: Optional[str]) -> dict[str, Any]:
    contract_hits = valid_idx.get(norm_path) or []
    event_hits = oracle_by_run.get(producer_run_id, []) if producer_run_id else []
    if not contract_hits and not event_hits:
        return _cell(
            NOT_OBSERVABLE,
            why="aucun evenement d'oracle (test.result/mutation.result/solvability.result/"
                "oracle.result) rattache au run producteur de cet artefact, et aucun "
                "contrat ne cite ce chemin dans tests_oracles",
        )
    value = {
        "oracle_events_du_run_producteur": sorted({e.get("kind") for e in event_hits if e.get("kind")}),
        "contrats_tests_oracles": sorted({h["contrat"] for h in contract_hits}),
    }
    src = _cite(event_hits[0]) if event_hits else contract_hits[0]["src"]
    cell = _cell(value, src)
    cell["note"] = ("couverture par run_id du producteur, pas par chemin precis : un "
                     "evenement d'oracle ne porte pas le chemin exact de l'artefact qu'il "
                     "couvre")
    return cell


def _archive_par(archive_idx: Optional[dict[str, list[str]]], basename: str) -> dict[str, Any]:
    if archive_idx is None:
        return _cell(NOT_OBSERVABLE, why="lab/forge_runs/<projet> hors perimetre lisible")
    hits = archive_idx.get(basename.lower())
    if not hits:
        return _cell(
            NOT_OBSERVABLE,
            why="aucun dossier _run*/_blocked*/_halted* sous lab/forge_runs/<projet> ne "
                "contient de fichier du meme nom",
        )
    cell = _cell(hits)
    cell["note"] = "correspondance par nom de fichier (basename), pas par chemin complet"
    return cell


def _artefact_record(ctx: Any, path: Path,
                      write_idx: dict[str, list[dict[str, Any]]],
                      read_idx: dict[str, list[dict[str, Any]]],
                      declares_idx: dict[str, list[dict[str, Any]]],
                      oracle_by_run: dict[Optional[str], list[dict[str, Any]]],
                      valid_idx: dict[str, list[dict[str, Any]]],
                      archive_idx: Optional[dict[str, list[str]]]) -> dict[str, Any]:
    rel = ctx.rel(path).replace("\\", "/")
    norm = rel.lower()
    meta = _meta(path)
    declares = declares_idx.get(norm, [])
    observed = _observed_consumers(read_idx, norm)
    consommateurs = {"declares": declares, "observes": observed}

    info, first = _producer_info(write_idx, norm)
    if info is None:
        producteur = _cell(NOT_OBSERVABLE, why="aucun evenement file.write/file.edit rattache "
                                                "a ce chemin dans les traces observees")
        producer_run_id: Optional[str] = None
    else:
        producteur = _cell(info, _cite(first, "path"))
        producer_run_id = info.get("run_id")
        if producer_run_id == NOT_OBSERVABLE:
            producer_run_id = None

    valide_par = _valide_par(valid_idx, oracle_by_run, norm, producer_run_id)
    archive_par = _archive_par(archive_idx, path.name)

    return {
        "chemin": rel,
        "mtime": meta["mtime"],
        "mtime_epoch": meta["mtime_epoch"],
        "taille_octets": meta["taille_octets"],
        "producteur": producteur,
        "consommateurs": consommateurs,
        "produit_par": producteur,
        "consomme_par": consommateurs,
        "valide_par": valide_par,
        "archive_par": archive_par,
    }


# --------------------------------------------------------------------------- #
# s5_artefacts -- l'arbre
# --------------------------------------------------------------------------- #

# Combien d'artefacts affiches par categorie dans le detail -- le TOTAL reel
# est toujours rapporte a part, jamais tronque silencieusement.
_MAX_ARTEFACTS_DETAIL = 60

# Repertoires bruits/techniques a exclure du sous-arbre "Games" (cache moteur
# Godot, jamais un artefact produit par la Forge).
_GAME_NOISE_EXCLUDES = (".godot/",)


def _category_roots(ctx: Any, project: Optional[str]) -> dict[str, dict[str, Any]]:
    """Racines de l'arbre ratifie, par categorie. Chaque entree porte soit une
    liste de racines (dossiers) a scanner recursivement, soit un fichier
    unique -- jamais les deux dans le meme appel a `_dir_files`/`_single_file`,
    pour garder le contrat de retour (`None` = hors perimetre) sans ambiguite.
    """
    game_dir = ctx.game_dir
    run_dir = ctx.run_dir
    specs: dict[str, dict[str, Any]] = {}

    specs["Charters"] = {
        "dirs": [run_dir],
        "files": [run_dir / "charter.yaml"],
        "extra_dirs": [game_dir / "00_CHARTER"],
        "filtre": lambda relp: relp.endswith("charter.yaml")
        or "/00_charter/" in relp.lower() or relp.lower().startswith("00_charter/"),
    }
    specs["Wiremaps"] = {
        "files": [run_dir / "wiremap.json"],
        "extra_dirs": [game_dir / "09_WIREMAP"],
    }
    specs["World Scan"] = {
        # sortie standard de s2-worldscan.yaml : GAME_REFERENCE/. Aucune des
        # deux racines candidates n'existe pour un projet passe par le regime
        # STANDARD sans etape World Scan (voir vue s1_workflow, meme constat).
        "extra_dirs": [game_dir / "GAME_REFERENCE", run_dir / "GAME_REFERENCE"],
    }
    specs["Knowledge"] = {"dirs": [ctx.repo_root / "knowledge_base"]}
    specs["Skills"] = {"none_why": "aucune racine lisible declaree pour .claude/skills/ "
                                    "dans ce contexte Observer"}
    specs["Contracts"] = {"dirs": [ctx.repo_root / "scripts" / "forge" / "contracts"]}
    specs["Lessons"] = {"files": [ctx.repo_root / "lab" / "reports" / "lessons.jsonl"]}
    specs["Reports"] = {
        "dirs": [ctx.repo_root / "lab" / "reports" / "error_journal"],
        "extra_dirs": [run_dir / "artifacts"],
    }
    specs["Games"] = {
        "dirs": [game_dir],
        "exclude_dirs": {"00_CHARTER", "09_WIREMAP", "06_RUNTIME"},
    }
    specs["Runtime"] = {"extra_dirs": [game_dir / "06_RUNTIME"]}
    return specs


def _collect_category(ctx: Any, label: str, spec: dict[str, Any]) -> dict[str, Any]:
    if "none_why" in spec:
        return {"racine_lisible": False, "why": spec["none_why"], "paths": None}

    paths: list[Path] = []
    racine_lisible = False
    why: Optional[str] = None

    for d in spec.get("dirs", []):
        files = _dir_files(ctx, d, excludes=_GAME_NOISE_EXCLUDES if label == "Games" else ())
        if files is None:
            continue
        racine_lisible = True
        excl = spec.get("exclude_dirs")
        if excl:
            files = [p for p in files
                     if not any(f"\\{name}\\" in str(p) or f"/{name}/" in str(p).replace("\\", "/")
                                for name in excl)]
        paths.extend(files)

    for d in spec.get("extra_dirs", []):
        files = _dir_files(ctx, d)
        if files is None:
            continue
        racine_lisible = True
        paths.extend(files)

    for f in spec.get("files", []):
        files = _single_file(ctx, f)
        if files is None:
            continue
        racine_lisible = True
        paths.extend(files)

    filtre = spec.get("filtre")
    if filtre:
        paths = [p for p in paths if filtre(str(p).replace("\\", "/").lower())]

    # dedoublonne (une meme racine peut etre visitee via deux chemins d'appel)
    seen: set[str] = set()
    unique: list[Path] = []
    for p in paths:
        key = str(p.resolve())
        if key not in seen:
            seen.add(key)
            unique.append(p)

    if not racine_lisible:
        why = f"aucune des racines declarees pour « {label} » n'est dans le perimetre " \
              "lisible de ce contexte Observer"

    return {"racine_lisible": racine_lisible, "why": why, "paths": unique}


def view_artefacts(ctx: Any, result: dict[str, Any], events: list[dict[str, Any]]) -> dict[str, Any]:
    project = result.get("project")

    write_idx = _index_by_path(ctx, events, ("file.write", "file.edit"))
    read_idx = _index_by_path(ctx, events, ("file.read",))
    contracts = _load_contracts(ctx)
    mandatory = _resolve_mandatory_read(ctx, contracts, project)
    declares_idx = mandatory["declares_idx"]
    tests_oracles = _resolve_tests_oracles(ctx, contracts, project)
    valid_idx = tests_oracles["declares_idx"]
    oracle_by_run = _index_oracle_events_by_run(events)
    archive_idx = _build_archive_index(ctx)

    categories: dict[str, Any] = {}
    all_records: list[dict[str, Any]] = []

    for label, spec in _category_roots(ctx, project).items():
        collected = _collect_category(ctx, label, spec)
        if collected["paths"] is None:
            categories[label] = {
                "racine_lisible": False,
                "total": NOT_OBSERVABLE,
                "why": collected["why"],
                "artefacts": [],
            }
            continue

        paths = sorted(collected["paths"], key=lambda p: str(p))
        records = [_artefact_record(ctx, p, write_idx, read_idx, declares_idx,
                                     oracle_by_run, valid_idx, archive_idx) for p in paths]
        records.sort(key=lambda r: r["mtime_epoch"] or 0, reverse=True)
        all_records.extend(records)

        categories[label] = {
            "racine_lisible": True,
            "total": len(records),
            "why": collected["why"] if not records else None,
            "artefacts": records[:_MAX_ARTEFACTS_DETAIL],
            "tronque": len(records) > _MAX_ARTEFACTS_DETAIL,
        }

    ecarts_lecture = []
    for rec in all_records:
        declares = rec["consommateurs"]["declares"]
        observed = rec["consommateurs"]["observes"]
        if declares and observed["n"] == 0:
            ecarts_lecture.append({
                "artefact": rec["chemin"],
                "declare_par": sorted({d["contrat"] for d in declares}),
                "lu": 0,
                "constat": "au moins un contrat cite ce chemin dans mandatory_read, "
                           "aucune lecture file.read de ce chemin n'est observee dans "
                           "les traces retenues -- ecart factuel, pas une conclusion "
                           "sur la conformite de l'agent",
            })

    total_artefacts = sum(c["total"] for c in categories.values() if isinstance(c["total"], int))
    categories_lisibles = sum(1 for c in categories.values() if c["racine_lisible"])
    resume = (
        f"{total_artefacts} artefact(s) recense(s) sur {categories_lisibles}/{len(categories)} "
        f"categorie(s) lisible(s). {len(ecarts_lecture)} ecart(s) de lecture (declares en "
        f"mandatory_read, jamais lus en reel)."
    )

    return {
        "categories": categories,
        "ecarts_lecture": ecarts_lecture,
        "mandatory_read_non_resolu": mandatory["unresolved"],
        "tests_oracles_non_resolu": tests_oracles["unresolved"],
        "regle": "producteur = trace file.write/file.edit ; consommateurs.declares = "
                 "mandatory_read des contrats resolu a un fichier existant ; "
                 "consommateurs.observes = file.read reel. Un artefact sans aucune "
                 "trace productrice reste NOT_OBSERVABLE, jamais impute a un auteur "
                 "devine. valide_par = oracle.result/test.result/mutation.result/"
                 "solvability.result du run producteur, ou contrat citant ce chemin "
                 "dans tests_oracles. archive_par = copie de meme nom sous un dossier "
                 "_run*/_blocked*/_halted* de lab/forge_runs/<projet>.",
        "question": "Qui produit quoi ?",
        "resume": resume,
    }


# --------------------------------------------------------------------------- #
# s1_workflow -- les 9 blocs
# --------------------------------------------------------------------------- #

# Definition des 9 blocs ratifies. `etapes` = noms d'etape Forge qui font
# vivre ce bloc (matching direct sur `event["etape"]`). `extra_kinds` = kinds
# d'evenement propres au bloc au-dela des file.write/read generiques (ex.
# wiremap.line). `roots` = racines de fichiers a citer en `derniers_artefacts`
# quand le bloc n'est pas pilote par etape (Knowledge Base, Lessons, Runtime).
_WORKFLOW_BLOCKS: tuple[dict[str, Any], ...] = (
    {"label": "World Scan", "etapes": ("s2-worldscan",)},
    {"label": "Knowledge Base", "etapes": ()},
    {"label": "Architect", "etapes": ("s4-archi",)},
    {"label": "WireMap", "etapes": ("wm1-wiremap-breakout", "s5-wiremap"),
     "extra_kinds": ("wiremap.line",)},
    {"label": "Builder", "etapes": ("s9-build-godot-standard", "s9-build",
                                     "s9-build-standard", "s9-build-godot")},
    {"label": "Runtime", "etapes": ()},
    {"label": "Observer", "etapes": ()},
    {"label": "Lessons", "etapes": ()},
    {"label": "retour KB", "etapes": ()},
)

# Routage des drifts vers un bloc quand `item["etape"]` ne matche aucun bloc
# (reference_guard/tokens/scratchpad n'ont pas de champ etape dans les
# adaptateurs actuels -- constat, pas une lacune de ce module).
_DRIFT_STATIC_BLOCK: dict[str, str] = {
    "tools_used_beyond_declared": "Builder",
    "tools_used_without_declaration": "Builder",
    "tool_observability_not_measured": "Builder",
    "token_accounting_below_measured": "Builder",
    "prompt_sans_empreinte_declaree": "Builder",
    "prompt_recu_differe_du_prompt_signe": "Builder",
    "reference_guard_drift": "Runtime",
    "file_written_outside_game_and_lab": "Runtime",
    "file_written_in_session_scratchpad": "Runtime",
    "lecon_routee_sans_consommateur": "Lessons",
    "lecon_candidate_non_arbitree": "Lessons",
}


def _route_drift(item: dict[str, Any], block_etapes: dict[str, tuple[str, ...]]) -> list[str]:
    """Route UN item de drift vers son ou ses blocs, une seule fois par item
    (appele depuis `_route_all_drifts`, jamais par bloc -- router item par
    item, bloc par bloc, ferait matcher un item deux fois : une fois par son
    `etape` reel, une fois par le repli statique du type, pour deux blocs
    differents. La priorite est stricte : etape reelle d'abord, famille
    documentation ensuite (double routage assume, Lessons ET Knowledge Base),
    repli statique par type en dernier -- jamais les trois a la fois.
    """
    etape = item.get("etape")
    if etape:
        for label, etapes in block_etapes.items():
            if etape in etapes:
                return [label]
    if item.get("famille") == "documentation":
        return ["Lessons", "Knowledge Base"]
    static = _DRIFT_STATIC_BLOCK.get(item.get("type"))
    return [static] if static else []


def _route_all_drifts(result: dict[str, Any],
                       block_etapes: dict[str, tuple[str, ...]]) -> dict[str, list[dict[str, Any]]]:
    out: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for item in result.get("drift", []):
        entry = {
            "type": item.get("type"), "severity": item.get("severity"),
            "detail": item.get("detail"), "run_id": item.get("run_id"),
            "etape": item.get("etape"),
        }
        for label in _route_drift(item, block_etapes):
            out[label].append(entry)
    return dict(out)


def _block_state(evs: list[dict[str, Any]], now_ts: float) -> tuple[str, Optional[dict[str, Any]]]:
    if not evs:
        return NOT_OBSERVABLE, None
    span = _span(evs)
    if span["derniere"] is None:
        # des evenements existent mais aucun n'est date -- fait a part, pas un
        # DORMANT devine.
        return "NON_DATE", None
    age_s = now_ts - span["derniere_epoch"]
    etat = "ACTIF" if age_s < _RECENT_WINDOW_S else "DORMANT"
    src = _cite(max((e for e in evs if e.get("ts")), key=lambda e: e["ts"]))
    return etat, {"derniere_activite": span["derniere"], "age_jours": round(age_s / 86400, 1),
                  "src": src}


def _world_scan_discovery(ctx: Any) -> dict[str, Any]:
    """`knowledge_base/catalog.json` porte des entrees a `provenance_url` non
    nul -- des patterns/assets cites depuis une source externe, la trace la
    plus proche d'un « World Scan » que ce perimetre lisible expose. Ce n'est
    PAS une preuve d'etape World Scan pour le projet observe : ces entrees
    sont globales a la bibliotheque, sans lien de production trace vers ce
    run (aucun evenement file.write ne les rattache)."""
    catalog_path = ctx.repo_root / "knowledge_base" / "catalog.json"
    if not _is_allowed(ctx, catalog_path) or not ctx.exists(catalog_path):
        return {"entrees_provenance_url": NOT_OBSERVABLE,
                "why": "knowledge_base/catalog.json absent ou hors perimetre"}
    data = ctx.read_json(catalog_path)
    entries = (data or {}).get("entries", []) if isinstance(data, dict) else []
    sourced = [e for e in entries if e.get("provenance_url")]
    exemples = [{
        "id": e.get("brick_id") or e.get("asset_id"),
        "provenance_url": e.get("provenance_url"),
        "tier": e.get("tier"),
    } for e in sourced[:5]]
    return {
        "entrees_provenance_url": len(sourced),
        "exemples": exemples,
        "note": "vestige global de la bibliotheque de connaissance, hors perimetre du "
                "run observe -- ne compte pas comme preuve d'un World Scan pour ce projet",
        "src": {"path": "knowledge_base/catalog.json"},
    }


def _lessons_for_project(ctx: Any, result: dict[str, Any]) -> list[dict[str, Any]]:
    """Lecons dont `supporting_runs` cite un run_id de ce projet -- le seul
    lien mecanique disponible entre `lessons.jsonl` et un projet : le schema
    d'evenements (KINDS de events.py) ne definit AUCUN kind pour l'ecriture
    d'une lecon, donc aucune trace file.write ne relie jamais ce fichier a un
    producteur -- fait a rapporter, pas un defaut de ce module."""
    lessons_path = ctx.repo_root / "lab" / "reports" / "lessons.jsonl"
    if not _is_allowed(ctx, lessons_path):
        return []
    run_ids = {r.get("run_id") for r in result.get("runs", [])}
    out = []
    for lineno, obj in ctx.read_jsonl(lessons_path):
        supporting = obj.get("supporting_runs") or []
        if any(r in run_ids for r in supporting):
            out.append({
                "lesson_id": obj.get("lesson_id"), "status": obj.get("status"),
                "supporting_runs": supporting, "destination": obj.get("destination"),
                "ts": obj.get("ts"),
                "src": {"path": "lab/reports/lessons.jsonl", "line": lineno},
            })
    return out


def view_workflow(ctx: Any, result: dict[str, Any], events: list[dict[str, Any]]) -> dict[str, Any]:
    project = result.get("project")
    now_ts = time.time()
    write_idx = _index_by_path(ctx, events, ("file.write", "file.edit"))
    block_etapes = {spec["label"]: spec["etapes"] for spec in _WORKFLOW_BLOCKS}
    drift_by_block = _route_all_drifts(result, block_etapes)

    blocs: list[dict[str, Any]] = []
    for spec in _WORKFLOW_BLOCKS:
        label = spec["label"]
        etapes = spec["etapes"]
        extra_kinds = spec.get("extra_kinds", ())
        kinds = ("file.write", "file.edit", "dispatch.prepared", "dispatch.executed",
                  "step.status", "artifact.self_declared") + extra_kinds
        evs = _kinds(events, kinds, etapes=etapes) if etapes else []

        # --- cas particuliers, pilotes par racine/result plutot que par etape
        derniers_artefacts: Any = NOT_OBSERVABLE
        producteur: Any
        consommateur: Any

        if label == "Knowledge Base":
            catalog_path = ctx.repo_root / "knowledge_base" / "catalog.json"
            files = _single_file(ctx, catalog_path)
            meta = _meta(catalog_path) if files else {"mtime": None, "mtime_epoch": None}
            data = ctx.read_json(catalog_path) if files else None
            entries = (data or {}).get("entries", []) if isinstance(data, dict) else []
            tiers = dict(Counter(e.get("tier") for e in entries))
            derniers_artefacts = {"catalog_mtime": meta["mtime"], "n_entries": len(entries),
                                   "par_tier": tiers,
                                   "src": {"path": "knowledge_base/catalog.json"}}
            evs = [{"ts": meta["mtime_epoch"], "ts_iso": meta["mtime"],
                    "kind": "file.write",
                    "source": {"path": "knowledge_base/catalog.json"}}] if meta["mtime_epoch"] else []
            producteur = _cell("proposition Forge (propose-only) + ratification Pierre",
                                why=None)
            consommateur = _cell("knowledge_base/search.mjs (SEARCH obligatoire avant "
                                  "build, cf. contrats s9-build*.yaml)")
        elif label == "World Scan":
            derniers_artefacts = _world_scan_discovery(ctx)
            producteur = _cell(NOT_OBSERVABLE,
                                why="aucune etape s2-worldscan observee pour ce projet")
            consommateur = _cell(NOT_OBSERVABLE,
                                  why="pas de producteur observe : aucun consommateur ne "
                                      "peut etre rattache mecaniquement")
        elif label == "Runtime":
            root = ctx.game_dir / "06_RUNTIME"
            files = _dir_files(ctx, root) or []
            write_evs = []
            for p in files:
                norm = _norm(ctx, str(p))
                write_evs.extend(write_idx.get(norm, []) if norm else [])
            evs = write_evs
            derniers_artefacts = {
                "n_fichiers": len(files),
                "recents": sorted(
                    [{"chemin": ctx.rel(p).replace("\\", "/"), **_meta(p)} for p in files],
                    key=lambda r: r["mtime_epoch"] or 0, reverse=True,
                )[:10],
            }
            etapes_ecriture = sorted({e.get("etape") for e in write_evs if e.get("etape")})
            producteur = _cell(etapes_ecriture or NOT_OBSERVABLE,
                                why=None if etapes_ecriture else
                                "aucun evenement file.write sous games/<projet>/06_RUNTIME/")
            consommateur = _cell("adapters/ consommes par le point d'entree runtime "
                                  "(main.tscn) -- separation dure imposee par le standard "
                                  "(logique pure hors 06_RUNTIME, presentation dedans)")
        elif label == "Observer":
            derniers_artefacts = {
                "observed_at": result.get("observed_at"),
                "event_count": result.get("event_count"),
                "counts": result.get("counts"),
                "schema": result.get("schema"),
                "note": "lu depuis `result` (observer_run.json deja charge par "
                        "l'appelant) -- lab/reports/observer/ n'est PAS une racine "
                        "lisible d'Observer (pas d'auto-lecture de son propre rapport)",
            }
            producteur = _cell("Observer lui-meme (scripts/observer/cli.py, ce run de "
                                "reconstruction)")
            consommateur = _cell("console cockpit (scripts/observer/cockpit.py, "
                                  "command.py, views.py, ce module) + Pierre (HumanGate)")
            etat = "ACTIF"
            blocs.append({
                "bloc": label, "etat": etat,
                "activite": {"derniere_activite": result.get("observed_at")},
                "producteur": producteur, "consommateur": consommateur,
                "derniers_artefacts": derniers_artefacts,
                "derniers_drifts": drift_by_block.get(label, []),
                "liens": {"vue_detail": "s7_flow"},
            })
            continue
        elif label == "Lessons":
            liees = _lessons_for_project(ctx, result)
            derniers_artefacts = {
                "lecons_liees_au_projet": liees,
                "n": len(liees),
            }
            evs = [{
                "ts": l["ts"],
                "ts_iso": datetime.fromtimestamp(l["ts"], tz=timezone.utc).isoformat()
                if l.get("ts") else None,
                "kind": "artifact.self_declared", "source": l["src"],
            } for l in liees]
            producteur = _cell(
                NOT_OBSERVABLE,
                why="aucun kind d'evenement du schema Observer (events.KINDS) ne "
                    "trace l'ecriture d'une lecon ; le lien au projet ne passe que "
                    "par `supporting_runs`, jamais par un file.write observe")
            destinations = sorted({l["destination"] for l in liees if l.get("destination")})
            consommateur = _cell(
                destinations if destinations else NOT_OBSERVABLE,
                why=None if destinations else
                f"{len(liees)} lecon(s) liee(s) a ce projet, `destination` vaut None "
                "pour toutes -- aucun consommateur mecanique declare")
        elif label == "retour KB":
            liees = _lessons_for_project(ctx, result)
            validees = [l for l in liees if l.get("status") == "validated"]
            catalog_path = ctx.repo_root / "knowledge_base" / "catalog.json"
            raw = ctx.read_text(catalog_path) if _is_allowed(ctx, catalog_path) else None
            mentionne = bool(raw and project and project.lower() in raw.lower())
            derniers_artefacts = {
                "lecons_validees_liees_au_projet": len(validees),
                "projet_mentionne_dans_catalog_json": mentionne,
            }
            producteur = _cell(len(validees) if validees else NOT_OBSERVABLE,
                                why=None if validees else
                                "aucune lecon validee liee a ce projet")
            consommateur = _cell(
                "knowledge_base/catalog.json" if mentionne else NOT_OBSERVABLE,
                why=None if mentionne else
                f"{len(validees)} lecon(s) validee(s) liee(s) au projet, mais aucune "
                "occurrence du nom du projet dans knowledge_base/catalog.json -- la "
                "boucle Lessons -> KB ne se referme pas pour ce projet, constat "
                "factuel")
            etat = NOT_OBSERVABLE if not (validees and mentionne) else "ACTIF"
            blocs.append({
                "bloc": label, "etat": etat,
                "activite": None,
                "producteur": producteur, "consommateur": consommateur,
                "derniers_artefacts": derniers_artefacts,
                "derniers_drifts": drift_by_block.get(label, []),
                "liens": {"vue_detail": "s5_artefacts.Knowledge"},
            })
            continue
        else:
            # blocs pilotes par etape : Architect, WireMap, Builder, World Scan
            # (deja traite ci-dessus s'il a des artefacts KB ; sinon ce
            # chemin generique s'applique aussi a lui via etapes=() -> evs=[]).
            write_evs = _kinds(events, ("file.write", "file.edit"), etapes=etapes) if etapes else []
            recents = sorted(
                [{"chemin": ctx.rel(Path(e["payload"]["path"])).replace("\\", "/")
                  if e.get("payload", {}).get("path") else NOT_OBSERVABLE,
                  "etape": e.get("etape"), "ts_iso": e.get("ts_iso")}
                 for e in write_evs if e.get("payload", {}).get("path")],
                key=lambda r: r["ts_iso"] or "", reverse=True,
            )[:10]
            derniers_artefacts = {"n_ecritures": len(write_evs), "recents": recents} \
                if write_evs else NOT_OBSERVABLE

            dispatch_evs = _kinds(events, ("dispatch.executed",), etapes=etapes) if etapes else []
            producteur = _cell(
                sorted({e.get("run_id") for e in dispatch_evs if e.get("run_id")})
                or NOT_OBSERVABLE,
                _cite(dispatch_evs[0]) if dispatch_evs else None,
                why=None if dispatch_evs else
                f"aucune etape {etapes} observee dans les traces de ce projet"
                if etapes else "bloc sans etape Forge associee dans ce regime",
            )
            # consommateur declare : contrats dont mandatory_read cite le mot-cle
            # du bloc (ex. "wiremap" pour WireMap) -- resolution la meme que
            # view_artefacts, mais ici on ne veut que les NOMS de contrat.
            keyword = {"WireMap": "wiremap", "Architect": "blueprint",
                       "Builder": "squelette"}.get(label)
            citants: list[str] = []
            if keyword:
                for name, contract in _load_contracts(ctx).items():
                    reads = contract["data"].get("mandatory_read")
                    if isinstance(reads, list) and any(
                            keyword in str(item).lower() for item in reads):
                        citants.append(name)
            consommateur = _cell(sorted(citants) if citants else NOT_OBSERVABLE,
                                  why=None if citants else
                                  "aucun contrat ne cite ce mot-cle dans mandatory_read")

        etat, activite = _block_state(evs, now_ts)
        blocs.append({
            "bloc": label,
            "etat": etat,
            "activite": activite,
            "producteur": producteur,
            "consommateur": consommateur,
            "derniers_artefacts": derniers_artefacts,
            "derniers_drifts": drift_by_block.get(label, []),
            "liens": {"vue_detail": "s5_artefacts"},
        })

    n_actifs = sum(1 for b in blocs if b["etat"] == "ACTIF")
    retour_kb = next((b for b in blocs if b["bloc"] == "retour KB"), None)
    if retour_kb is None:
        retour_msg = "le bloc retour KB est introuvable dans l'assemblage."
    elif retour_kb["etat"] == NOT_OBSERVABLE:
        retour_msg = ("La boucle retour vers la connaissance est cassee : rien ne "
                       "revient dans la bibliotheque.")
    elif retour_kb["etat"] == "ACTIF":
        retour_msg = "La boucle retour vers la connaissance fonctionne."
    else:
        retour_msg = f"La boucle retour vers la connaissance est a l'etat {retour_kb['etat']}."
    resume = f"{n_actifs} bloc(s) actif(s) sur {len(blocs)}. {retour_msg}"

    return {
        "blocs": blocs,
        "regle": "etat = ACTIF (trace datee < 7 jours) / DORMANT (plus ancienne) / "
                 "NOT_OBSERVABLE (aucune trace) -- jamais devine.",
        "question": "Où en est la Forge ?",
        "resume": resume,
    }


# --------------------------------------------------------------------------- #
# s7_flow -- produit -> consomme -> valide -> archive
# --------------------------------------------------------------------------- #

# La chaine ratifiee, dans l'ordre. `objet` nomme le maillon ; `write_etapes`
# et `read_after` bornent la recherche des roles produit/consomme ; `oracle_kinds`
# borne la recherche du role valide ; `archive_hint` documente le role archive
# (prose, car aucun kind d'evenement generique ne signale « archivage »).
_FLOW_STEPS: tuple[dict[str, Any], ...] = (
    {"objet": "World Scan -> Genre Bible",
     "produit_etapes": ("s2-worldscan",),
     "consomme_etapes": ("s4-archi", "wm1-wiremap-breakout", "s5-wiremap"),
     "oracle_kinds": (),
     "archive_hint": "aucune -- artefact GAME_REFERENCE/ non observe pour ce projet"},
    {"objet": "Genre Bible -> Architect",
     "produit_etapes": (),
     "consomme_etapes": ("s4-archi",),
     "oracle_kinds": (),
     "archive_hint": "aucune"},
    {"objet": "Architect -> WireMap",
     "produit_etapes": ("s4-archi",),
     "consomme_etapes": ("wm1-wiremap-breakout", "s5-wiremap"),
     "oracle_kinds": (),
     "archive_hint": "aucune"},
    {"objet": "WireMap -> Builder",
     "produit_etapes": ("wm1-wiremap-breakout", "s5-wiremap"),
     "consomme_etapes": ("s9-build-godot-standard", "s9-build", "s9-build-standard",
                          "s9-build-godot"),
     "oracle_kinds": (),
     "archive_hint": "dossiers _run*/ du run_dir (archivage par le driver)"},
    {"objet": "Builder -> Observer",
     "produit_etapes": ("s9-build-godot-standard", "s9-build", "s9-build-standard",
                         "s9-build-godot"),
     "consomme_etapes": (),
     "oracle_kinds": ("test.result", "mutation.result", "solvability.result",
                       "oracle.result"),
     "archive_hint": "dossiers _run*/ du run_dir"},
    {"objet": "Observer -> Lessons",
     "produit_etapes": (),
     "consomme_etapes": (),
     "oracle_kinds": (),
     "archive_hint": "aucune -- lab/reports/lessons.jsonl est append-only, pas archive"},
    {"objet": "Lessons -> KB",
     "produit_etapes": (),
     "consomme_etapes": (),
     "oracle_kinds": (),
     "archive_hint": "tier candidate -> validated dans knowledge_base/catalog.json "
                      "(propose-only, ratification Pierre)"},
)


def _flow_role_produit(events: list[dict[str, Any]], etapes: tuple[str, ...]) -> dict[str, Any]:
    if not etapes:
        return _cell(NOT_OBSERVABLE, why="aucune etape associee a ce maillon dans ce regime")
    evs = _kinds(events, ("dispatch.executed", "file.write", "file.edit"), etapes=etapes)
    if not evs:
        return _cell(NOT_OBSERVABLE,
                      why=f"aucune trace de production (dispatch.executed/file.write) "
                          f"pour l'etape {etapes} dans ce projet")
    dated = [e for e in evs if e.get("ts")]
    first = min(dated, key=lambda e: e["ts"]) if dated else evs[0]
    return _cell(sorted({e.get("etape") for e in evs if e.get("etape")}), _cite(first))


def _flow_role_consomme(events: list[dict[str, Any]], etapes: tuple[str, ...]) -> dict[str, Any]:
    if not etapes:
        return _cell(NOT_OBSERVABLE, why="aucune etape aval associee a ce maillon dans ce regime")
    evs = _kinds(events, ("dispatch.executed",), etapes=etapes)
    if not evs:
        return _cell(NOT_OBSERVABLE,
                      why=f"aucune trace de consommation (dispatch.executed) pour "
                          f"l'etape {etapes} dans ce projet")
    return _cell(sorted({e.get("etape") for e in evs if e.get("etape")}), _cite(evs[0]))


def _flow_role_valide(events: list[dict[str, Any]], kinds: tuple[str, ...]) -> dict[str, Any]:
    if not kinds:
        return _cell(NOT_OBSERVABLE, why="aucun kind d'oracle associe a ce maillon")
    evs = _kinds(events, kinds)
    if not evs:
        return _cell(NOT_OBSERVABLE, why="aucun evenement d'oracle observe pour ce maillon")
    par_kind = dict(Counter(e["kind"] for e in evs))
    return _cell(par_kind, _cite(evs[0]))


def view_flow(ctx: Any, result: dict[str, Any], events: list[dict[str, Any]]) -> dict[str, Any]:
    etapes: list[dict[str, Any]] = []
    for spec in _FLOW_STEPS:
        etapes.append({
            "objet": spec["objet"],
            "produit_par": _flow_role_produit(events, spec["produit_etapes"]),
            "consomme_par": _flow_role_consomme(events, spec["consomme_etapes"]),
            "valide_par": _flow_role_valide(events, spec["oracle_kinds"]),
            "archive_par": _cell(spec["archive_hint"] if spec["archive_hint"] != "aucune"
                                  else NOT_OBSERVABLE,
                                  why=spec["archive_hint"] if spec["archive_hint"] == "aucune"
                                  or spec["archive_hint"].startswith("aucune") else None),
        })
    n_produit = sum(1 for e in etapes if e["produit_par"]["v"] != NOT_OBSERVABLE)
    n_valide = sum(1 for e in etapes if e["valide_par"]["v"] != NOT_OBSERVABLE)
    resume = (
        f"{n_produit}/{len(etapes)} maillon(s) de la chaine ont une preuve de production "
        f"tracee. {n_valide}/{len(etapes)} ont une validation d'oracle observee."
    )

    return {
        "chaine": "World Scan -> Genre Bible -> Architect -> WireMap -> Builder -> "
                  "Observer -> Lessons -> KB",
        "etapes": etapes,
        "note": "instanciee sur les traces reelles du projet observe -- un maillon "
                "sans trace est NOT_OBSERVABLE, jamais suppose franchi",
        "question": "Comment circulent les artefacts ?",
        "resume": resume,
    }


# --------------------------------------------------------------------------- #
# Assemblage
# --------------------------------------------------------------------------- #


def build_artefact_views(ctx: Any, result: dict[str, Any], events: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "s1_workflow": view_workflow(ctx, result, events),
        "s5_artefacts": view_artefacts(ctx, result, events),
        "s7_flow": view_flow(ctx, result, events),
    }


# --------------------------------------------------------------------------- #
# Preuve d'execution
# --------------------------------------------------------------------------- #

if __name__ == "__main__":
    import json
    import sys

    _HERE = Path(__file__).resolve().parent
    if str(_HERE.parent) not in sys.path:  # rend `import observer` possible sans install
        sys.path.insert(0, str(_HERE.parent))

    from observer.sources import ObserverContext, default_repo_root, default_transcripts_root  # noqa: E402

    logging.basicConfig(level=logging.WARNING)

    repo_root = default_repo_root()
    transcripts_root = default_transcripts_root(repo_root)
    ctx = ObserverContext.build(repo_root, "breakout_v2", transcripts_root)

    report_dir = repo_root / "EVIDENCE" / "reports" / "observer" / "breakout_v2"
    with (report_dir / "observer_run.json").open("r", encoding="utf-8-sig") as fh:
        result = json.load(fh)

    events: list[dict[str, Any]] = []
    with (report_dir / "events.jsonl").open("r", encoding="utf-8-sig") as fh:
        for line in fh:
            line = line.strip()
            if line:
                events.append(json.loads(line))

    views = build_artefact_views(ctx, result, events)

    print(f"cles produites : {sorted(views.keys())}")

    print("\n--- s1_workflow : etat des 9 blocs ---")
    for bloc in views["s1_workflow"]["blocs"]:
        print(f"  {bloc['bloc']:<16} etat={bloc['etat']:<14} "
              f"drifts={len(bloc['derniers_drifts'])}")

    print("\n--- s5_artefacts : comptes par categorie ---")
    art = views["s5_artefacts"]
    for label, cat in art["categories"].items():
        print(f"  {label:<12} racine_lisible={cat['racine_lisible']!s:<6} total={cat['total']}")
    print(f"  ecarts_lecture (declare mandatory_read, jamais lu en reel) : "
          f"{len(art['ecarts_lecture'])}")
    print(f"  mandatory_read_non_resolu : {len(art['mandatory_read_non_resolu'])}")

    print("\n--- s7_flow : resume ---")
    for etape in views["s7_flow"]["etapes"]:
        print(f"  {etape['objet']:<28} produit={etape['produit_par']['v'] != NOT_OBSERVABLE!s:<6} "
              f"consomme={etape['consomme_par']['v'] != NOT_OBSERVABLE!s:<6} "
              f"valide={etape['valide_par']['v'] != NOT_OBSERVABLE!s:<6} "
              f"archive={etape['archive_par']['v'] != NOT_OBSERVABLE!s}")

    print("\n--- detail ecarts_lecture ---")
    print(json.dumps(art["ecarts_lecture"], indent=2, ensure_ascii=False))
