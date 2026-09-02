"""forge.reference_guard — détection MÉCANIQUE de modification des arbres de
référence protégés (``GAMES/pong/**``, ``tests/**``).

Contexte (ne pas re-débattre ici — voir les sources) :
  - docs/fvl/FVL_PHASE_0_5_CHARTER.md §7 point 1 : « périmètre minimal ratifié » —
    protection du témoin · **détection de modification** · dérogation humaine
    explicite, rien d'autre avant la calibration.
  - docs/forge/FORGE_EVOLUTION_DOCTRINE_V0.md §1.1/§1.2 : le gel de Pong n'était que
    documentaire (aucune des trois surfaces d'écriture — outils de session, shell,
    sous-processus — n'était réellement couverte). La SEULE couche complète est une
    empreinte de référence, vérifiée à l'ouverture et à la clôture d'un run — c'est
    de la détection, pas de la prévention, mais elle ne dépend d'AUCUN chemin
    d'écriture (cinquième règle d'usine : une garde est indépendante de l'état
    courant).

VOLET DÉTECTION UNIQUEMENT. Ce module ne pose ni gate, ni verdict, ni politique de
dérogation : il lit une liste protégée (fichier de DONNÉES, jamais un chemin en dur
ici), calcule une empreinte, la compare à une baseline enregistrée, et lit un fichier
de dérogation déclaré s'il existe. La pose de la permission `deny` sur
`.claude/settings.json` (qui rendrait la protection *préventive* elle aussi complète)
reste un geste de Pierre, hors périmètre de ce module.

Enumération du témoin — pourquoi `git ls-files`, pas un parcours brut du disque :
`GAMES/pong/06_RUNTIME/adapters/presentation/godot/.godot/` est un cache d'import +
shader Vulkan régénéré à chaque ouverture de l'éditeur Godot (des centaines de
fichiers, jamais identiques d'une capture à l'autre) — incident déjà rencontré et
ratifié Pierre 2026-07-28 (voir le commentaire dans `.gitignore` racine). Un parcours
brut du disque fabriquerait un générateur de faux positifs permanent, exactement
l'anti-pattern que la doctrine désigne : « une métrique sans bande de bruit connue
peut valider n'importe quelle mutation » — ici, invalider n'importe quel run.
`git ls-files --cached --others --exclude-standard` résout les deux exigences à la
fois : il respecte `.gitignore` (donc ignore `.godot/`, `__pycache__/`, ...) tout en
listant aussi bien le contenu COMMIT que le contenu simplement présent sur disque et
non ignoré (`--others`) — un fichier neuf qu'un sous-processus déposerait dans l'arbre
protégé SANS jamais le stager apparaît donc quand même comme AJOUTÉ. Seul le contenu
IGNORÉ échappe à l'empreinte, par construction déjà déclaré non pertinent par le dépôt
lui-même.

Le contenu haché est TOUJOURS lu depuis le disque (jamais depuis l'objet git) : c'est
le point du dispositif — un processus qui modifierait un fichier suivi SANS jamais
committer (le cas nommé par la doctrine : « un sous-processus, build Godot, exécuteur,
script ») change le contenu sur disque, pas l'objet git ; seule une lecture directe du
fichier le voit.

Best-effort au sens de `forge.learning_hook` UNIQUEMENT pour `advisory_check` (le
point d'entrée appelé par `driver.py`) : cette fonction précise ne lève JAMAIS. Le
reste du module (utilisé par la CLI) lève `ReferenceGuardError` normalement — une
CLI qui avale ses propres erreurs en silence fabriquerait exactement le vert que la
doctrine interdit.

claim_verdict: NO_CLAIM_ALLOWED — ce module ne prononce aucun verdict logiciel ; ses
statuts (`CLEAN`/`AUTORISE`/`DRIFT`/`INCOMPLET`/`ERROR`/`NO_BASELINE`) sont un
vocabulaire de DÉTECTION distinct du vocabulaire de verdict (OK/FAIL/BLOCKED), pour
ne jamais laisser croire que ce module gate quoi que ce soit.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

import yaml

from forge.static_oracles import utc_iso_now
from forge.verdict import current_git_head
from forge.verify_run import _harden_streams

# forge/reference_guard.py -> parents[2] == racine du repo.
REPO_ROOT = Path(__file__).resolve().parents[1]

DEFAULT_CONFIG_PATH = Path(__file__).resolve().parent / "reference_protected.yaml"
# EVIDENCE/bundles/ : même convention que studio_link (PROPOSE-ONLY / observation,
# jamais une mémoire de référence) — voir studio_link.FORGE_EVIDENCE.
DEFAULT_BASELINE_PATH = REPO_ROOT / "EVIDENCE" / "bundles" / "reference_baseline.json"
# Réutilise le sentinel déjà en place pour forge.git_guard (doctrine §1.1 : « Forme de
# la dérogation : réutiliser le précédent .claude/HUMAN_GIT_OVERRIDE.json, déjà dans la
# liste deny — un fichier de ratification que la session ne peut pas s'auto-écrire »).
DEFAULT_DEROGATION_PATH = REPO_ROOT / ".claude" / "HUMAN_GIT_OVERRIDE.json"

FINGERPRINT_SCHEMA = "forge.reference_guard.fingerprint.v1"
BASELINE_SCHEMA = "forge.reference_guard.baseline.v1"
REPORT_SCHEMA = "forge.reference_guard.report.v1"

# Écarts typés (SORTIE ATTENDUE point 1) — valeurs ASCII (le studio a déjà un incident
# documenté d'encodage sur console Windows cp1252, cf. `_harden_streams` /
# studio_link.main ; ce sont les mêmes trois notions que AJOUTÉ/MODIFIÉ/SUPPRIMÉ).
KIND_ADDED = "AJOUTE"
KIND_MODIFIED = "MODIFIE"
KIND_REMOVED = "SUPPRIME"

# Statuts de DÉTECTION — jamais un statut de verdict (OK/FAIL/BLOCKED). Ordre de
# gravité croissant utilisé par `verify()` pour choisir le statut final.
STATUS_NO_BASELINE = "NO_BASELINE"   # rien à comparer : jamais une erreur, jamais un vert
STATUS_CLEAN = "CLEAN"               # aucun écart
STATUS_AUTHORIZED = "AUTORISE"       # écart(s), tous couverts par une dérogation déclarée
STATUS_DRIFT = "DRIFT"               # au moins un écart NON couvert par une dérogation
STATUS_INCOMPLETE = "INCOMPLET"      # au moins un fichier protégé illisible : couverture compromise
STATUS_ERROR = "ERROR"               # configuration/baseline/git en échec — pas une mesure


class ReferenceGuardError(Exception):
    """Erreur de configuration ou de preuve (liste protégée vide, chemin inexistant,
    `git` en échec, baseline illisible...). Distincte de `STATUS_NO_BASELINE`, qui
    n'est PAS une erreur — l'absence de baseline est un état légitime avant le
    premier `record`."""


# --- configuration (fichier de DONNÉES — SORTIE ATTENDUE point 2) --------------------

def load_config(config_path: "Path | str | None" = None) -> dict:
    """Charge `reference_protected.yaml`. Une liste `protected` absente, vide, ou dont
    un élément n'est pas une chaîne non vide est une ERREUR rapportée — jamais un vert
    silencieux (garde-fou explicite de la mission)."""
    path = Path(config_path) if config_path else DEFAULT_CONFIG_PATH
    if not path.exists():
        raise ReferenceGuardError(f"fichier de configuration introuvable: {path}")
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise ReferenceGuardError(f"configuration illisible ({path}): {exc}") from exc
    try:
        data = yaml.safe_load(raw)
    except yaml.YAMLError as exc:
        raise ReferenceGuardError(f"configuration YAML invalide ({path}): {exc}") from exc
    if not isinstance(data, dict):
        raise ReferenceGuardError(f"configuration mal formée (racine non-objet): {path}")
    protected = data.get("protected")
    if (not isinstance(protected, list) or not protected
            or not all(isinstance(p, str) and p.strip() for p in protected)):
        raise ReferenceGuardError(
            f"liste 'protected' vide ou invalide dans {path} — une liste protégée "
            "vide (ou un motif non-chaîne) est une ERREUR, jamais un vert silencieux"
        )
    derogation_path = data.get("derogation_path")
    if derogation_path is not None and not isinstance(derogation_path, str):
        raise ReferenceGuardError(f"'derogation_path' doit être une chaîne dans {path}")
    return {
        "protected": [p.strip() for p in protected],
        "derogation_path": derogation_path or str(
            DEFAULT_DEROGATION_PATH.relative_to(REPO_ROOT).as_posix()
        ),
        "source_path": str(path),
    }


# --- énumération du témoin (git, jamais un parcours brut du disque — voir docstring) --

def _pattern_to_pathspec(pattern: str) -> str:
    """``GAMES/pong/**`` -> ``GAMES/pong`` (préfixe de répertoire pour `git ls-files`,
    qui liste déjà récursivement sans magie glob supplémentaire nécessaire)."""
    p = pattern.strip().replace("\\", "/")
    if p.endswith("/**"):
        p = p[: -len("/**")]
    return p.rstrip("/") or "."


def _git_ls_files(repo_root: Path, pathspec: str) -> list[str]:
    """Fichiers COMMIT + présents-non-ignorés sous `pathspec`, chemins repo-relatifs
    POSIX. Jamais un vert silencieux : tout échec de `git` lève `ReferenceGuardError`."""
    try:
        proc = subprocess.run(
            ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard",
             "--", pathspec],
            cwd=str(repo_root), capture_output=True, timeout=30,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise ReferenceGuardError(f"git ls-files a échoué sur {pathspec!r}: {exc}") from exc
    if proc.returncode != 0:
        stderr = proc.stderr.decode("utf-8", errors="replace")
        raise ReferenceGuardError(
            f"git ls-files a échoué sur {pathspec!r} (code {proc.returncode}): {stderr.strip()}"
        )
    raw = proc.stdout.decode("utf-8", errors="surrogateescape")
    return [p for p in raw.split("\0") if p]


def resolve_protected_files(protected: list[str], repo_root: "Path | None" = None) -> list[str]:
    """Chemins repo-relatifs triés couverts par les motifs protégés. Un motif dont le
    chemin de base est absent du disque, OU qui ne couvre aucun fichier suivi/présent,
    est une ERREUR — jamais une liste vide silencieuse (garde-fou explicite)."""
    root = Path(repo_root) if repo_root else REPO_ROOT
    all_files: set[str] = set()
    for pattern in protected:
        pathspec = _pattern_to_pathspec(pattern)
        if not (root / pathspec).exists():
            raise ReferenceGuardError(
                f"motif protégé {pattern!r} -> chemin inexistant ({root / pathspec}) "
                "— ERREUR rapportée, jamais un vert silencieux"
            )
        files = _git_ls_files(root, pathspec)
        if not files:
            raise ReferenceGuardError(
                f"motif protégé {pattern!r} ne couvre AUCUN fichier (suivi ou présent "
                "non-ignoré) — ERREUR rapportée, jamais un vert silencieux"
            )
        all_files.update(files)
    return sorted(all_files)


# --- empreinte (SORTIE ATTENDUE point 1) ---------------------------------------------

def _sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def compute_fingerprint(protected: list[str], repo_root: "Path | None" = None) -> dict:
    """Empreinte stable : sha256 par fichier, chemins repo-relatifs TRIÉS, résultat
    reproductible d'un run à l'autre pour un arbre inchangé (E1 du charter, transposé
    à ce garde). Un fichier illisible (permission, disparu entre l'énumération et la
    lecture — jamais un fichier BINAIRE, qui se hache sans lever) est rapporté dans
    `unreadable`, jamais ignoré en silence ; `complete=False` dans ce cas, pour que
    l'appelant ne prenne jamais une couverture partielle pour un vert plein."""
    root = Path(repo_root) if repo_root else REPO_ROOT
    rel_files = resolve_protected_files(protected, root)  # déjà trié
    files: dict[str, str] = {}
    unreadable: list[dict] = []
    for rel in rel_files:
        abs_path = root / rel
        if not abs_path.exists():
            # Listé par `git ls-files --cached` (suivi) mais absent du disque : une
            # SUPPRESSION CERTAINE, pas une incertitude de lecture — distincte d'un
            # fichier présent mais illisible (permission, verrou...). Absent de
            # `files` (donc SUPPRIMÉ via `compare_to_baseline`) SANS entrer dans
            # `unreadable` : ce n'est pas la même famille de problème, et la
            # confondre ferait remonter `complete=False` (INCOMPLET) pour une simple
            # suppression, alors que le sort du fichier est parfaitement connu.
            continue
        try:
            files[rel] = _sha256_of(abs_path)
        except OSError as exc:
            unreadable.append({"path": rel, "error": str(exc)})
    lines = "\n".join(f"{path}\t{files[path]}" for path in sorted(files))
    combined = hashlib.sha256(lines.encode("utf-8")).hexdigest()
    return {
        "schema": FINGERPRINT_SCHEMA,
        "files": files,
        "unreadable": unreadable,
        "file_count": len(files),
        "combined_sha256": combined,
        "complete": not unreadable,
    }


# --- baseline (SORTIE ATTENDUE point 3 : calculer / enregistrer / vérifier) ----------

def _atomic_write_json(path: Path, data: dict) -> None:
    """Écriture atomique (tmp + replace) — même patron que `ForgeDriver._save`."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(
        json.dumps(data, ensure_ascii=False, sort_keys=True, indent=1), encoding="utf-8"
    )
    os.replace(tmp, path)


def record_baseline(
    config_path: "Path | str | None" = None,
    baseline_path: "Path | str | None" = None,
    repo_root: "Path | None" = None,
) -> dict:
    """Calcule l'empreinte courante et l'enregistre comme baseline (écriture DURABLE,
    jamais appelée depuis `advisory_check`/le driver — c'est un geste explicite, via
    la CLI). Lève `ReferenceGuardError` si l'empreinte est incomplète (fichier
    illisible) : une baseline enregistrée sur une couverture partielle serait un
    témoin corrompu dès sa naissance."""
    root = Path(repo_root) if repo_root else REPO_ROOT
    config = load_config(config_path)
    fingerprint = compute_fingerprint(config["protected"], root)
    if not fingerprint["complete"]:
        raise ReferenceGuardError(
            f"empreinte incomplète ({len(fingerprint['unreadable'])} fichier(s) "
            "illisible(s)) — refus d'enregistrer une baseline corrompue"
        )
    record = {
        **fingerprint,
        "schema": BASELINE_SCHEMA,  # APRÈS **fingerprint : écrase son propre schema
        "protected": config["protected"],
        "config_path": config["source_path"],
        "recorded_at": utc_iso_now(),
        "git_head": current_git_head(),
    }
    path = Path(baseline_path) if baseline_path else DEFAULT_BASELINE_PATH
    _atomic_write_json(path, record)
    return record


def load_baseline(baseline_path: "Path | str | None" = None) -> "dict | None":
    """`None` si aucune baseline n'a encore été enregistrée (état légitime, PAS une
    erreur). Lève `ReferenceGuardError` si le fichier existe mais est illisible/corrompu
    — un JSON invalide n'est pas la même chose qu'une absence de baseline."""
    path = Path(baseline_path) if baseline_path else DEFAULT_BASELINE_PATH
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise ReferenceGuardError(f"baseline illisible ({path}): {exc}") from exc


# --- dérogation humaine (SORTIE ATTENDUE point 4) ------------------------------------

def _read_derogation(derogation_path: Path) -> dict:
    """Lit le fichier de dérogation déclaré. « Tu ne crées PAS de gouvernance autour :
    tu lis un fichier, c'est tout » — aucune fenêtre de fraîcheur, aucune vérification
    de qui l'a écrit (cette garantie externe est celle de `.claude/settings.json`, hors
    périmètre ici, voir `forge.git_guard._read_override`). Absent / illisible / mal
    formé -> AUCUNE dérogation, jamais une exception, jamais un octroi implicite."""
    if not derogation_path.exists():
        return {"paths": set(), "reason": "", "present": False}
    try:
        data = json.loads(derogation_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {"paths": set(), "reason": "", "present": False}
    if not isinstance(data, dict):
        return {"paths": set(), "reason": "", "present": False}
    raw_paths = data.get("paths")
    paths = {p for p in raw_paths if isinstance(p, str)} if isinstance(raw_paths, list) else set()
    reason = data.get("reason") if isinstance(data.get("reason"), str) else ""
    return {"paths": paths, "reason": reason, "present": True}


# --- comparaison (SORTIE ATTENDUE point 3 : écarts typés) ---------------------------

def compare_to_baseline(current: dict, baseline: dict) -> list[dict]:
    """Écarts typés AJOUTÉ / MODIFIÉ / SUPPRIMÉ entre l'empreinte courante et la
    baseline enregistrée. Trié par chemin — déterministe, comme le reste du module."""
    cur_files = current.get("files", {})
    base_files = baseline.get("files", {})
    diffs: list[dict] = []
    for path in sorted(set(cur_files) | set(base_files)):
        cur_hash = cur_files.get(path)
        base_hash = base_files.get(path)
        if base_hash is None and cur_hash is not None:
            diffs.append({"path": path, "kind": KIND_ADDED})
        elif base_hash is not None and cur_hash is None:
            diffs.append({"path": path, "kind": KIND_REMOVED})
        elif base_hash != cur_hash:
            diffs.append({"path": path, "kind": KIND_MODIFIED})
    return diffs


# --- vérification bout-en-bout --------------------------------------------------------

def verify(
    config_path: "Path | str | None" = None,
    baseline_path: "Path | str | None" = None,
    derogation_path: "Path | str | None" = None,
    repo_root: "Path | None" = None,
) -> dict:
    """Rapport structuré : statut de DÉTECTION (jamais un verdict), écarts typés,
    dérogations appliquées. Précédence de gravité : ERROR > INCOMPLET > DRIFT >
    AUTORISE > CLEAN > NO_BASELINE (NO_BASELINE court-circuite avant tout calcul —
    rien à comparer, jamais une erreur ni un vert)."""
    root = Path(repo_root) if repo_root else REPO_ROOT
    checked_at = utc_iso_now()
    base_report = {"schema": REPORT_SCHEMA, "checked_at": checked_at, "diffs": []}

    try:
        config = load_config(config_path)
    except ReferenceGuardError as exc:
        return {**base_report, "status": STATUS_ERROR, "error": str(exc)}

    try:
        baseline = load_baseline(baseline_path)
    except ReferenceGuardError as exc:
        return {**base_report, "status": STATUS_ERROR, "error": str(exc)}

    resolved_baseline_path = str(Path(baseline_path) if baseline_path else DEFAULT_BASELINE_PATH)
    if baseline is None:
        return {**base_report, "status": STATUS_NO_BASELINE,
                "baseline_path": resolved_baseline_path}

    try:
        current = compute_fingerprint(config["protected"], root)
    except ReferenceGuardError as exc:
        return {**base_report, "status": STATUS_ERROR, "error": str(exc)}

    diffs = compare_to_baseline(current, baseline)
    derog_path = Path(derogation_path) if derogation_path else (
        root / config["derogation_path"]
    )
    derog = _read_derogation(derog_path)
    for d in diffs:
        authorized = d["path"] in derog["paths"]
        d["authorized"] = authorized
        d["derogation_reason"] = derog["reason"] if authorized else None

    violations = [d for d in diffs if not d["authorized"]]

    if not current["complete"]:
        status = STATUS_INCOMPLETE
    elif violations:
        status = STATUS_DRIFT
    elif diffs:
        status = STATUS_AUTHORIZED
    else:
        status = STATUS_CLEAN

    return {
        **base_report,
        "status": status,
        "diffs": diffs,
        "unreadable": current["unreadable"],
        "current_combined_sha256": current["combined_sha256"],
        "current_file_count": current["file_count"],
        "baseline_combined_sha256": baseline.get("combined_sha256", ""),
        "baseline_recorded_at": baseline.get("recorded_at", ""),
        "baseline_path": resolved_baseline_path,
        "derogation_path": str(derog_path),
        "derogation_present": derog["present"],
    }


def advisory_check(phase: str, **kwargs) -> dict:
    """Point d'entrée UNIQUE pour `driver.py`. Best-effort STRICT, même garantie que
    `forge.learning_hook.record_learning_for_subject` : ne lève JAMAIS, quelle que soit
    la cause (config absente, git indisponible, baseline corrompue, bug interne...).
    `phase` ∈ {"open", "close"} — pas imposé ici (le driver décide), juste consigné."""
    try:
        report = verify(**kwargs)
    except Exception as exc:  # noqa: BLE001 — best-effort strict, ne remonte jamais
        report = {
            "schema": REPORT_SCHEMA, "checked_at": utc_iso_now(),
            "status": STATUS_ERROR, "diffs": [],
            "error": f"exception best-effort: {exc}",
        }
    report["phase"] = phase
    return report


# --- CLI (SORTIE ATTENDUE point 3 : compute / record / verify) ----------------------

def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="CLI forge.reference_guard : empreinte + baseline + vérification "
                     "des arbres de référence protégés (GAMES/pong/**, tests/**)."
    )
    sub = parser.add_subparsers(dest="cmd")

    p_compute = sub.add_parser(
        "compute", help="calcule l'empreinte courante (lecture seule, n'écrit rien)")
    p_compute.add_argument("--config", type=Path, default=None)

    p_record = sub.add_parser(
        "record", help="calcule l'empreinte courante et l'enregistre comme baseline (ÉCRIT)")
    p_record.add_argument("--config", type=Path, default=None)
    p_record.add_argument("--baseline", type=Path, default=None)

    p_verify = sub.add_parser(
        "verify", help="compare l'empreinte courante à la baseline enregistrée")
    p_verify.add_argument("--config", type=Path, default=None)
    p_verify.add_argument("--baseline", type=Path, default=None)
    p_verify.add_argument("--derogation", type=Path, default=None)

    return parser


def main(argv: "list[str] | None" = None) -> int:
    """Contrat identique à `studio_link.main` : `_harden_streams()` en premier (console
    Windows cp1252), jamais de trace Python nue, toujours un int en retour."""
    _harden_streams()
    parser = _build_parser()
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:
        return exc.code if isinstance(exc.code, int) else 2

    if args.cmd == "compute":
        try:
            config = load_config(args.config)
            fp = compute_fingerprint(config["protected"])
        except ReferenceGuardError as exc:
            print(f"erreur: {exc}", file=sys.stderr)
            return 2
        print(json.dumps(fp, ensure_ascii=False, sort_keys=True, indent=2))
        return 0

    if args.cmd == "record":
        try:
            record = record_baseline(config_path=args.config, baseline_path=args.baseline)
        except ReferenceGuardError as exc:
            print(f"erreur: {exc}", file=sys.stderr)
            return 2
        path = Path(args.baseline) if args.baseline else DEFAULT_BASELINE_PATH
        print(f"baseline enregistrée -> {path} "
              f"({record['file_count']} fichiers, {record['combined_sha256']})")
        return 0

    if args.cmd == "verify":
        report = verify(config_path=args.config, baseline_path=args.baseline,
                         derogation_path=args.derogation)
        print(json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2))
        return 0 if report["status"] in (STATUS_CLEAN, STATUS_AUTHORIZED, STATUS_NO_BASELINE) else 1

    parser.print_usage(sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
