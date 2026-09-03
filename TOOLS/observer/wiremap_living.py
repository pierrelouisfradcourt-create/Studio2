"""Vue WIREMAP VIVANTE de Forge Observer V0 — « La carte dit-elle la vérité ? »

CONSTAT MESURÉ (2026-08-02, breakout_v2) : les 52 lignes de la wiremap portent
`state=REQUIRED` (51) / `DEFERRED` (1) et un champ `preuve` vide sur TOUTES.
La carte PRESCRIT mais n'enregistre jamais la construction ni la validation :
elle est figée à l'instant wm1, alors que trois runs pilotés ont écrit les
fichiers et produit des reçus d'oracle après elle.

Ce module transforme Prescription → Prescription + Construction + Validation +
Preuve, en OVERLAY DÉRIVÉ : l'artefact du run (`lab/forge_runs/<p>/wiremap.json`)
n'est JAMAIS réécrit ni touché. Par ligne :

    * prescription  — ce que la carte déclare (state, expected_proof, fichiers),
                      source = la wiremap elle-même ;
    * construction  — OBSERVEE / PARTIELLE / NON_OBSERVEE : croisement des
                      fichiers déclarés par la ligne × événements `file.write` /
                      `file.edit` des transcripts (même marqueur games/<p>/ que
                      `system_production._fichiers_ecrits_observes`, réutilisé
                      par import — ici avec l'attribution par run et la source
                      transcript conservées, que le set de system_production
                      ne porte pas) ;
    * validation    — reçus d'oracle couvrant le run producteur (test.result,
                      mutation.result, solvability.result, oracle.result,
                      verdict.signed). GRANULARITÉ ASSUMÉE ET DITE : les reçus
                      sont émis PAR RUN, jamais par ligne — la couverture
                      ligne-à-ligne n'est PAS mesurable dans les traces
                      existantes, et cette vue ne la prétend jamais ;
    * preuve        — la plus forte disponible : SIGNED (verdict HMAC du run
                      producteur) > MECHANICAL (écritures observées + reçus
                      mécaniques) > NOT_OBSERVABLE, avec sa raison ;
    * derniere_validation — ts du reçu le plus fort (les reçus mécaniques de ce
                      run ne portent pas d'horodatage : ts_format=absent).

Sortie : `lab/reports/observer/<projet>/wiremap_LIVING.json` — VUE dérivée,
réécrite à chaque run. Garde d'écriture DURE identique à system_planning :
refus de toute destination hors de `lab/reports/observer/`.

Régime NOT_OBSERVABLE identique aux autres vues Observer : un manque de mesure
ne devient jamais un OK, une cellule sans preuve porte sa raison. Lecture
uniquement via `ObserverContext` (BlindnessViolation jamais rattrapée ici).

La section `proposition_pour_la_forge` est PROPOSE-ONLY : elle décrit comment
les runs FUTURS rempliraient state/preuve nativement — aucune implémentation
Forge ici, ratification Pierre requise.
"""

from __future__ import annotations

import json
import logging
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

LOG = logging.getLogger("observer.wiremap_living")

NOT_OBSERVABLE = "NOT_OBSERVABLE"

# Bootstrap identique a fleet.py / system_production.py : rend `import observer.*`
# possible sans install, AVANT tout import croise inter-modules.
_HERE = Path(__file__).resolve().parent
if str(_HERE.parent) not in sys.path:
    sys.path.insert(0, str(_HERE.parent))

from observer.system_production import _evs, _norm_path  # noqa: E402

QUESTION = "La carte dit-elle la vérité sur ce qui est construit ?"

# Vocabulaire ferme des etats de construction derives.
CONSTRUCTION_OBSERVEE = "OBSERVEE"
CONSTRUCTION_PARTIELLE = "PARTIELLE"
CONSTRUCTION_NON_OBSERVEE = "NON_OBSERVEE"

# Vocabulaire ferme des niveaux de preuve (aligne sur le champ `proof` des
# evenements Observer : SIGNED > MECHANICAL ; NOT_OBSERVABLE = pas de preuve).
PREUVE_SIGNED = "SIGNED"
PREUVE_MECHANICAL = "MECHANICAL"

_GRANULARITE_NOTE = (
    "GRANULARITÉ RUN, PAS LIGNE : les reçus d'oracle (test.result, "
    "mutation.result, solvability.result, oracle.result, verdict.signed) sont "
    "émis PAR RUN et couvrent le run producteur ENTIER. Aucune trace existante "
    "ne relie un reçu à une ligne de wiremap individuelle — la couverture "
    "ligne-à-ligne n'est pas mesurable et cette vue ne la prétend jamais."
)

_RECEIPT_KINDS: tuple[str, ...] = (
    "test.result", "mutation.result", "solvability.result",
    "oracle.result", "verdict.signed",
)


# --------------------------------------------------------------------------- #
# Aides communes
# --------------------------------------------------------------------------- #


def _cell(value: Any, src: Optional[dict] = None,
          why: Optional[str] = None) -> dict[str, Any]:
    """Une cellule : valeur, provenance, raison si non observable (cockpit._cell)."""
    out: dict[str, Any] = {"v": value}
    if src:
        out["src"] = src
    if value == NOT_OBSERVABLE and why:
        out["why"] = why
    return out


def _short(text: Any, limit: int = 200) -> str:
    text = " ".join(str(text).split())
    return text if len(text) <= limit else text[:limit].rstrip() + "…"


# --------------------------------------------------------------------------- #
# Sources derivees
# --------------------------------------------------------------------------- #


def _load_wiremap(ctx: Any) -> Optional[dict[str, Any]]:
    return ctx.read_json(ctx.run_dir / "wiremap.json")


def _run_order(result: dict[str, Any]) -> dict[str, str]:
    """run_id -> window.start, pour ordonner « le plus recent » mecaniquement."""
    out: dict[str, str] = {}
    for run in result.get("runs", []):
        rid = run.get("run_id")
        if rid:
            out[rid] = (run.get("window") or {}).get("start") or ""
    return out


def _writes_by_relpath(events: list[dict[str, Any]],
                       project: str) -> dict[str, list[dict[str, Any]]]:
    """Chemin relatif (sous games/<projet>/) -> ecritures observees.

    Meme marqueur d'appartenance que `system_production._fichiers_ecrits_observes`
    (reutilise par import pour `_norm_path`) — mais ici chaque ecriture garde son
    run_id, son horodatage et sa source transcript : c'est l'attribution dont
    l'overlay a besoin et que le set de system_production ne porte pas.
    """
    marqueur = f"games/{project.lower()}/"
    out: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for kind in ("file.write", "file.edit"):
        for e in _evs(events, kind):
            p = _norm_path((e.get("payload") or {}).get("path") or "")
            if marqueur not in p:
                continue
            rel = p.split(marqueur, 1)[1]
            out[rel].append({
                "kind": kind,
                "run_id": e.get("run_id"),
                "ts_iso": e.get("ts_iso") or NOT_OBSERVABLE,
                "src": e.get("source"),
            })
    return out


def _receipts_by_run(events: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    """run_id -> reçus d'oracle du run, en cellules {v,src}.

    Les reçus mecaniques de breakout_v2 ne portent pas d'horodatage
    (ts_format=absent) : seul verdict.signed fournit un ts exploitable.
    """
    par_run: dict[str, dict[str, Any]] = {}

    def _bloc(run_id: str) -> dict[str, Any]:
        return par_run.setdefault(run_id, {"oracles": {}})

    for e in events:
        kind = e.get("kind")
        if kind not in _RECEIPT_KINDS:
            continue
        rid = e.get("run_id")
        if not rid:
            continue
        p = e.get("payload") or {}
        bloc = _bloc(rid)
        if kind == "test.result":
            bloc["tests"] = _cell(f"{p.get('passed')}/{p.get('failed')} (ok/ko)",
                                  e.get("source"))
        elif kind == "mutation.result":
            bloc["mutation"] = _cell(f"{p.get('killed')}/{p.get('total')} tues",
                                     e.get("source"))
        elif kind == "solvability.result":
            bloc["solvabilite"] = _cell(
                f"{p.get('won')}/{p.get('trials')} gagnes ({p.get('verdict')})",
                e.get("source"))
        elif kind == "oracle.result":
            oid = p.get("oracle_id") or "?"
            bloc["oracles"][oid] = _cell(p.get("status", NOT_OBSERVABLE),
                                         e.get("source"))
        elif kind == "verdict.signed":
            cell = _cell(p.get("decision", NOT_OBSERVABLE), e.get("source"))
            cell["software_verdict"] = p.get("software_verdict", NOT_OBSERVABLE)
            cell["hmac_present"] = bool(p.get("hmac"))
            cell["ts_iso"] = e.get("ts_iso") or NOT_OBSERVABLE
            bloc["verdict"] = cell

    # Cellules manquantes rendues explicites — jamais un trou silencieux.
    for rid, bloc in par_run.items():
        for champ in ("tests", "mutation", "solvabilite", "verdict"):
            if champ not in bloc:
                bloc[champ] = _cell(NOT_OBSERVABLE, None,
                                    f"aucun evenement {champ} pour le run {rid}")
        if not bloc["oracles"]:
            bloc["oracles"] = {"_": _cell(NOT_OBSERVABLE, None,
                                          f"aucun oracle.result pour le run {rid}")}
    return par_run


# --------------------------------------------------------------------------- #
# Overlay par ligne
# --------------------------------------------------------------------------- #


def _prescription(line: dict[str, Any], index: int, project: str) -> dict[str, Any]:
    ep = line.get("expected_proof") or {}
    return {
        "state_declare": line.get("state", NOT_OBSERVABLE),
        "preuve_declaree": line.get("preuve") or "",
        "expected_proof": {
            "kind": ep.get("kind", NOT_OBSERVABLE),
            "statement": _short(ep.get("statement") or NOT_OBSERVABLE, 240),
        },
        "fichiers": [f.get("path") for f in (line.get("fichiers") or [])],
        "src": {"path": f"lab/forge_runs/{project}/wiremap.json",
                "field": f"lines[{index}]"},
    }


def _construction(line: dict[str, Any],
                  writes: dict[str, list[dict[str, Any]]],
                  ordre: dict[str, str]) -> tuple[dict[str, Any], list[str]]:
    """Etat de construction derive + run(s) producteur(s) de la ligne."""
    declares = [f.get("path") for f in (line.get("fichiers") or []) if f.get("path")]
    if not declares:
        return ({
            "etat": CONSTRUCTION_NON_OBSERVEE,
            "why": "la ligne ne declare aucun fichier : la construction n'est "
                   "pas mesurable par croisement fichiers × ecritures",
            "fichiers_ecrits": {"n": 0, "m": 0},
            "detail": [],
        }, [])

    detail: list[dict[str, Any]] = []
    runs_producteurs: set[str] = set()
    n_ecrits = 0
    for path in declares:
        obs = writes.get(_norm_path(path), [])
        entry: dict[str, Any] = {"path": path, "ecrit": bool(obs)}
        if obs:
            n_ecrits += 1
            runs = sorted({o["run_id"] for o in obs if o.get("run_id")})
            runs_producteurs.update(runs)
            entry["ecritures"] = len(obs)
            entry["runs"] = runs
            entry["premiere_ecriture_ts"] = min(
                (o["ts_iso"] for o in obs), default=NOT_OBSERVABLE)
            entry["src"] = obs[0].get("src")
        else:
            entry["why"] = ("aucun evenement file.write/file.edit observe pour "
                            "ce chemin dans les transcripts")
        detail.append(entry)

    if n_ecrits == len(declares):
        etat = CONSTRUCTION_OBSERVEE
    elif n_ecrits > 0:
        etat = CONSTRUCTION_PARTIELLE
    else:
        etat = CONSTRUCTION_NON_OBSERVEE

    bloc = {
        "etat": etat,
        "fichiers_ecrits": {"n": n_ecrits, "m": len(declares)},
        "src_regle": ("evenements file.write/file.edit des transcripts, "
                      "croisement par chemin normalise sous games/<projet>/ "
                      "(meme marqueur que system_production)"),
        "detail": detail,
    }
    producteurs = sorted(runs_producteurs, key=lambda r: ordre.get(r, ""))
    return bloc, producteurs


def _validation(runs_producteurs: list[str],
                receipts: dict[str, dict[str, Any]]) -> tuple[dict[str, Any],
                                                              Optional[str]]:
    """Reçus couvrant le run producteur (au niveau RUN — dit explicitement).

    Retourne (bloc_validation, run_reference) ; run_reference = le run
    producteur LE PLUS RECENT qui porte au moins un reçu, None sinon.
    Les reçus complets vivent dans `recus_par_run` (table partagee de
    l'overlay) — la ligne les REFERENCE, elle ne les duplique pas 52 fois.
    """
    if not runs_producteurs:
        return ({
            "granularite": _GRANULARITE_NOTE,
            "runs_producteurs": [],
            "run_reference": _cell(NOT_OBSERVABLE, None,
                                   "aucun run producteur observe pour cette ligne "
                                   "— aucun reçu rattachable"),
        }, None)

    run_ref = None
    for rid in reversed(runs_producteurs):  # deja tries du plus ancien au plus recent
        if rid in receipts:
            run_ref = rid
            break

    bloc: dict[str, Any] = {
        "granularite": _GRANULARITE_NOTE,
        "runs_producteurs": runs_producteurs,
    }
    if run_ref is None:
        bloc["run_reference"] = _cell(
            NOT_OBSERVABLE, None,
            "aucun des runs producteurs ne porte de reçu d'oracle dans les "
            "evenements de cette reconstruction")
    else:
        bloc["run_reference"] = _cell(
            run_ref, {"path": "recus_par_run (table partagee de cet overlay)",
                      "field": run_ref})
        bloc["recus"] = f"voir recus_par_run['{run_ref}']"
    return bloc, run_ref


def _preuve_et_derniere_validation(
        etat_construction: str, run_ref: Optional[str],
        receipts: dict[str, dict[str, Any]]) -> tuple[dict[str, Any],
                                                      dict[str, Any]]:
    """Preuve la plus forte disponible + ts de derniere validation.

    SIGNED (verdict HMAC du run producteur) > MECHANICAL (ecritures observees
    dans les transcripts, reçus mecaniques du run) > NOT_OBSERVABLE.
    Toujours au niveau RUN — la preuve cite le run, jamais une ligne isolee.
    """
    if run_ref is not None:
        bloc = receipts.get(run_ref, {})
        verdict = bloc.get("verdict") or {}
        if verdict.get("v") not in (None, NOT_OBSERVABLE) and verdict.get("hmac_present"):
            preuve = {
                "niveau": PREUVE_SIGNED,
                "detail": (f"verdict signe HMAC du run producteur {run_ref} "
                           f"(decision={verdict.get('v')}, couvre le run entier, "
                           "pas la ligne isolement)"),
                "src": verdict.get("src"),
            }
            ts = verdict.get("ts_iso", NOT_OBSERVABLE)
            derniere = (_cell(ts, verdict.get("src")) if ts != NOT_OBSERVABLE
                        else _cell(NOT_OBSERVABLE, None,
                                   "verdict signe sans horodatage exploitable"))
            return preuve, derniere
        preuve = {
            "niveau": PREUVE_MECHANICAL,
            "detail": (f"ecritures de fichiers observees dans les transcripts + "
                       f"reçus mecaniques du run {run_ref} (aucun verdict signe "
                       "sur ce run)"),
        }
        derniere = _cell(NOT_OBSERVABLE, None,
                         "les reçus mecaniques de ce run ne portent pas "
                         "d'horodatage (ts_format=absent)")
        return preuve, derniere

    if etat_construction in (CONSTRUCTION_OBSERVEE, CONSTRUCTION_PARTIELLE):
        preuve = {
            "niveau": PREUVE_MECHANICAL,
            "detail": ("ecritures de fichiers observees dans les transcripts, "
                       "mais aucun reçu d'oracle rattachable aux runs producteurs"),
        }
        derniere = _cell(NOT_OBSERVABLE, None,
                         "aucun reçu d'oracle rattachable — pas de ts de validation")
        return preuve, derniere

    preuve = {
        "niveau": NOT_OBSERVABLE,
        "why": ("aucune ecriture observee pour les fichiers de cette ligne et "
                "aucun reçu rattachable : rien ne prouve la construction"),
    }
    derniere = _cell(NOT_OBSERVABLE, None, "aucune validation observee")
    return preuve, derniere


def _artefacts_lies(line: dict[str, Any], project: str) -> list[str]:
    return [f"games/{project}/{f.get('path')}"
            for f in (line.get("fichiers") or []) if f.get("path")]


# --------------------------------------------------------------------------- #
# Overlay complet
# --------------------------------------------------------------------------- #


def build_living_overlay(ctx: Any, result: dict[str, Any],
                         events: list[dict[str, Any]]) -> dict[str, Any]:
    """Construit l'overlay derive Prescription+Construction+Validation+Preuve.

    Ne touche JAMAIS `lab/forge_runs/<p>/wiremap.json` : lecture seule via ctx,
    l'overlay est un objet neuf. N'ecrit aucun fichier (l'ecriture gardee vit
    dans `view_wiremap_living` / `_write_overlay`).
    """
    project = result.get("project") or ctx.project
    wiremap = _load_wiremap(ctx)

    if not wiremap or not wiremap.get("lines"):
        return {
            "schema": "observer.wiremap_living/v0",
            "project": project,
            "v": NOT_OBSERVABLE,
            "why": (f"lab/forge_runs/{project}/wiremap.json absente ou sans "
                    "lines[] : aucun overlay derivable"),
            "lignes": [],
        }

    ordre = _run_order(result)
    writes = _writes_by_relpath(events, project)
    receipts = _receipts_by_run(events)

    lignes: list[dict[str, Any]] = []
    par_etat: Counter = Counter()
    ecart_required_construit = 0
    ecart_deferred_construit = 0
    preuve_niveaux: Counter = Counter()

    for index, line in enumerate(wiremap["lines"]):
        prescription = _prescription(line, index, project)
        construction, producteurs = _construction(line, writes, ordre)
        validation, run_ref = _validation(producteurs, receipts)
        preuve, derniere = _preuve_et_derniere_validation(
            construction["etat"], run_ref, receipts)

        par_etat[construction["etat"]] += 1
        preuve_niveaux[preuve.get("niveau") or NOT_OBSERVABLE] += 1
        if (prescription["state_declare"] == "REQUIRED"
                and construction["etat"] == CONSTRUCTION_OBSERVEE):
            ecart_required_construit += 1
        if (prescription["state_declare"] == "DEFERRED"
                and construction["etat"] == CONSTRUCTION_OBSERVEE):
            ecart_deferred_construit += 1

        lignes.append({
            "id": line.get("id"),
            "prescription": prescription,
            "construction": construction,
            "validation": validation,
            "preuve": preuve,
            "derniere_validation": derniere,
            "artefacts_lies": _artefacts_lies(line, project),
        })

    n = len(lignes)
    n_preuve_vide_carte = sum(
        1 for l in lignes if not l["prescription"]["preuve_declaree"])
    par_state_declare = Counter(l["prescription"]["state_declare"] for l in lignes)

    return {
        "schema": "observer.wiremap_living/v0",
        "project": project,
        "genere_le": datetime.now(timezone.utc).isoformat(),
        "source_wiremap": f"lab/forge_runs/{project}/wiremap.json",
        "wiremap_run_id": wiremap.get("run_id", NOT_OBSERVABLE),
        "nature": ("OVERLAY DERIVE, vue recalculee a chaque run d'Observer — "
                   "l'artefact du run (wiremap.json) n'est JAMAIS modifie"),
        "granularite_validation": _GRANULARITE_NOTE,
        "resume": {
            "n_lignes": n,
            "par_state_declare": dict(par_state_declare),
            "par_etat_construction": dict(par_etat),
            "par_niveau_preuve": dict(preuve_niveaux),
            "preuve_vide_dans_la_carte": f"{n_preuve_vide_carte}/{n}",
            "ecart_required_mais_construction_observee": ecart_required_construit,
            "ecart_deferred_mais_construction_observee": ecart_deferred_construit,
            "note_ecart": ("LE chiffre : nombre de lignes que la carte declare "
                           "encore REQUIRED (a construire) alors que la "
                           "construction est OBSERVEE dans les transcripts — "
                           "la carte prescrit, elle n'enregistre pas"),
        },
        "recus_par_run": receipts,
        "lignes": lignes,
    }


# --------------------------------------------------------------------------- #
# Ecriture gardee — meme garde dure que system_planning._write_proposition
# --------------------------------------------------------------------------- #


def _write_overlay(ctx: Any, out_dir: Optional[Path],
                   overlay: dict[str, Any]) -> tuple[Optional[str], Optional[str]]:
    """La SEULE ecriture de ce module. `out_dir=None` = pas d'ecriture (defaut).

    Garde dure : refuse d'ecrire hors de `lab/reports/observer/` — jamais dans
    `lab/forge_runs/`, `games/` ni `scripts/forge/`, meme si l'appelant se
    trompe de chemin.
    """
    if out_dir is None:
        return None, None

    out_path = Path(out_dir).resolve()
    guard_root = (ctx.repo_root / "EVIDENCE" / "reports" / "observer").resolve()
    try:
        out_path.relative_to(guard_root)
    except ValueError:
        why = (f"out_dir {out_path} n'est pas sous lab/reports/observer/ — "
               "ecriture refusee (seule sortie autorisee pour Observer)")
        LOG.error(why)
        return None, why

    out_path.mkdir(parents=True, exist_ok=True)
    file_path = out_path / "wiremap_LIVING.json"
    file_path.write_text(json.dumps(overlay, ensure_ascii=False, indent=1),
                         encoding="utf-8")
    return str(file_path), None


# --------------------------------------------------------------------------- #
# Vue s11
# --------------------------------------------------------------------------- #

_PROPOSITION_POUR_LA_FORGE = {
    "statut": ("PROPOSITION — propose-only, a ratifier par Pierre (HumanGate). "
               "AUCUNE implementation Forge dans ce module."),
    "texte": (
        "Pour que les runs FUTURS remplissent state/preuve nativement, au lieu "
        "de laisser la carte figee a la prescription : (1) apres un run vert, "
        "l'oracle s10s (deterministe, non-LLM) stampe chaque ligne de la "
        "wiremap dont les fichiers declares existent et sont couverts par les "
        "reçus du run — state REQUIRED→IMPLEMENTED et preuve = reference du "
        "reçu (chemin du verdict.json + run_id + ts), jamais un texte libre ; "
        "(2) le stamp est ecrit par l'oracle en passe post-verdict, jamais par "
        "le builder — un agent ne se declare pas lui-meme construit ; "
        "(3) tant qu'aucun reçu par ligne n'existe, le champ preuve cite le "
        "RUN, sans pretendre a une preuve ligne-a-ligne (meme granularite "
        "assumee que cet overlay). Variante conservatrice si la wiremap doit "
        "rester immuable apres wm1 : la Forge ecrit un overlay separe du meme "
        "schema que ce fichier, et la carte d'origine reste l'artefact fige. "
        "Candidat a ratifier, aucune des deux options n'est implementee ici."),
}


def view_wiremap_living(ctx: Any, result: dict[str, Any],
                        events: list[dict[str, Any]],
                        out_dir: Optional[Path] = None) -> dict[str, Any]:
    """Vue s11 : overlay + question + resume 2 phrases + proposition Forge.

    Ecrit `wiremap_LIVING.json` dans `out_dir` si fourni (garde dure : sous
    lab/reports/observer/ uniquement) ; `out_dir=None` = aucune ecriture.
    """
    overlay = build_living_overlay(ctx, result, events)

    if overlay.get("v") == NOT_OBSERVABLE:
        return {"s11_wiremap_living": {
            "question": QUESTION,
            "resume": _cell(NOT_OBSERVABLE, None, overlay.get("why")),
            "overlay": overlay,
            "proposition_pour_la_forge": _PROPOSITION_POUR_LA_FORGE,
            "fichier": _cell(NOT_OBSERVABLE, None,
                             "aucun overlay derivable, rien d'ecrit"),
        }}

    r = overlay["resume"]
    n = r["n_lignes"]
    ecart = r["ecart_required_mais_construction_observee"]
    n_required = r["par_state_declare"].get("REQUIRED", 0)
    n_obs = r["par_etat_construction"].get(CONSTRUCTION_OBSERVEE, 0)
    n_part = r["par_etat_construction"].get(CONSTRUCTION_PARTIELLE, 0)
    n_non = r["par_etat_construction"].get(CONSTRUCTION_NON_OBSERVEE, 0)

    if ecart > 0:
        resume = (
            f"Non : {ecart} des {n_required} lignes declarees REQUIRED sont "
            f"observees construites dans les transcripts (au total "
            f"{n_obs} OBSERVEE / {n_part} PARTIELLE / {n_non} NON_OBSERVEE sur "
            f"{n}), et la carte porte toujours state=REQUIRED et preuve vide "
            f"({r['preuve_vide_dans_la_carte']}). "
            "La wiremap est une prescription figee a l'instant wm1 : la verite "
            "de construction et de validation vit dans les transcripts et les "
            "reçus d'oracle (au niveau run), pas dans l'artefact.")
    else:
        resume = (
            f"Aucun ecart mesure : sur {n} lignes, aucune ligne REQUIRED n'est "
            f"observee construite ({n_obs} OBSERVEE / {n_part} PARTIELLE / "
            f"{n_non} NON_OBSERVEE). "
            "La carte et les traces racontent la meme histoire sur cet "
            "echantillon — l'ecart est un chiffre mesure, jamais suppose.")

    written_path, write_why = _write_overlay(ctx, out_dir, overlay)
    fichier = (_cell(written_path,
                     {"path": "lab/reports/observer/", "field": "wiremap_LIVING.json"})
               if written_path else
               _cell(NOT_OBSERVABLE, None,
                     write_why or "out_dir=None : aucune ecriture demandee"))

    return {"s11_wiremap_living": {
        "question": QUESTION,
        "resume": resume,
        "l_ecart": {
            "required_mais_construction_observee": ecart,
            "deferred_mais_construction_observee":
                r["ecart_deferred_mais_construction_observee"],
            "regle": r["note_ecart"],
        },
        "granularite_validation": _GRANULARITE_NOTE,
        "overlay": overlay,
        "proposition_pour_la_forge": _PROPOSITION_POUR_LA_FORGE,
        "fichier": fichier,
    }}


# --------------------------------------------------------------------------- #
# Preuve d'execution
# --------------------------------------------------------------------------- #

if __name__ == "__main__":
    from observer.sources import ObserverContext, default_repo_root, default_transcripts_root  # noqa: E402

    logging.basicConfig(level=logging.WARNING)
    try:  # console Windows cp1252 : jamais un crash d'affichage pour un accent
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except AttributeError:
        pass

    repo_root = default_repo_root()
    transcripts_root = default_transcripts_root(repo_root)
    project = "breakout_v2"
    ctx = ObserverContext.build(repo_root, project, transcripts_root)

    report_dir = repo_root / "EVIDENCE" / "reports" / "observer" / project
    with (report_dir / "observer_run.json").open("r", encoding="utf-8-sig") as fh:
        result = json.load(fh)

    events: list[dict[str, Any]] = []
    with (report_dir / "events.jsonl").open("r", encoding="utf-8-sig") as fh:
        for raw in fh:
            raw = raw.strip()
            if raw:
                events.append(json.loads(raw))

    views = view_wiremap_living(ctx, result, events, out_dir=report_dir)
    vue = views["s11_wiremap_living"]
    overlay = vue["overlay"]
    r = overlay["resume"]

    print(f"question : {vue['question']}")
    print(f"resume   : {vue['resume']}")

    print("\n--- resume chiffre ---")
    print(f"  lignes                : {r['n_lignes']}")
    print(f"  state declare         : {r['par_state_declare']}")
    print(f"  construction          : {r['par_etat_construction']}")
    print(f"  niveaux de preuve     : {r['par_niveau_preuve']}")
    print(f"  preuve vide (carte)   : {r['preuve_vide_dans_la_carte']}")
    print(f"  ECART REQUIRED/construit : "
          f"{r['ecart_required_mais_construction_observee']}")
    print(f"  ecart DEFERRED/construit : "
          f"{r['ecart_deferred_mais_construction_observee']}")

    print("\n--- reçus par run (validation au niveau RUN) ---")
    for rid, bloc in sorted(overlay["recus_par_run"].items()):
        verdict = bloc.get("verdict") or {}
        print(f"  {rid:<38} tests={bloc['tests']['v']:<14} "
              f"mutation={bloc['mutation']['v']:<12} "
              f"solvabilite={bloc['solvabilite']['v']:<20} "
              f"verdict={verdict.get('v')}")

    print("\n--- echantillon de lignes (3 premieres + la DEFERRED) ---")
    echantillon = list(overlay["lignes"][:3]) + [
        l for l in overlay["lignes"]
        if l["prescription"]["state_declare"] == "DEFERRED"]
    for l in echantillon:
        c = l["construction"]
        fe = c.get("fichiers_ecrits", {})
        print(f"  {l['id']:<34} declare={l['prescription']['state_declare']:<9} "
              f"construction={c['etat']:<13} "
              f"fichiers={fe.get('n')}/{fe.get('m')} "
              f"preuve={l['preuve'].get('niveau')} "
              f"derniere_validation={l['derniere_validation']['v']}")

    print(f"\nfichier ecrit : {vue['fichier']['v']}")

    blob = json.dumps(views, ensure_ascii=False)
    json.loads(blob)  # round-trip : la vue est integralement serialisable
    print(f"serialisation JSON OK ({len(blob)} caracteres, round-trip verifie)")
