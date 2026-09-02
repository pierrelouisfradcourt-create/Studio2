#!/usr/bin/env python
"""analyze_batch.py — CONSOMME les generation_report.json d'un lot et en tire des lecons.

Ferme la boucle d'amelioration : jusqu'ici `build_asset.py` ecrivait un
`generation_report.json` par asset et PERSONNE ne le relisait. Chaque lot repartait de
zero. Ce module lit ces rapports, rejoue l'oracle, et emet des `asset_lesson` (schema
`asset_lesson.schema.json`) PUIS des CONTRAINTES que le dispatcher applique au lot
suivant -- c'est la contrainte, pas la lecon, qui rend le lot n+1 different du lot n.

    generation_report (n) + verdicts oracle (n) + manifestes HumanGate (n)
        -> analyze_batch
        -> asset_lesson (CANDIDATE)
        -> batch_constraints.json
        -> asset_dispatch refuse/exige au lot (n+1)

CE QUE CE MODULE NE FAIT PAS :
  * il ne juge pas la qualite artistique -- il ne voit que ce que les oracles voient ;
  * il n'ecrit ni le catalogue, ni un manifeste, ni un asset ;
  * il ne valide pas ses propres lecons : elles sortent en `CANDIDATE`, la validation
    est un geste humain (`--valider <lesson_id> --par "<humain>"`).

Les lecons sont DERIVEES MECANIQUEMENT (aucun modele, aucun LLM) de trois faits
observables : le verdict de l'oracle, la presence d'un manifeste HumanGate, et les
champs du rapport de generation.

Usage :
  python -m scripts.forge.asset_producer.analyze_batch <dir> --batch-id <id>
  python -m scripts.forge.asset_producer.analyze_batch --list
  python -m scripts.forge.asset_producer.analyze_batch --valider <lesson_id> --par "<humain>"
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[2]
LESSONS_DIR = REPO / "EVIDENCE" / "bundles" / "asset_lessons"
CONSTRAINTS_PATH = LESSONS_DIR / "batch_constraints.json"

SCHEMA_VERSION = "1.0"
STATUS_CANDIDATE = "CANDIDATE"
STATUS_VALIDATED = "VALIDATED"


def _oracle():
    sys.path.insert(0, str(REPO))
    from forge.asset_geometry import oracle as O
    return O


def collect(batch_dir: Path) -> list[dict[str, Any]]:
    """Lit les generation_report.json du lot et rejoue l'oracle sur chaque asset.

    Le rapport de generation est la parole du PRODUCTEUR : on en tire les parametres,
    jamais un verdict. Le verdict vient du rejeu de l'oracle.
    """
    O = _oracle()
    obs = []
    for rep_path in sorted(batch_dir.glob("*.generation_report.json")):
        gen = json.loads(rep_path.read_text(encoding="utf-8"))
        asset_id = gen.get("asset_id", rep_path.stem.split(".")[0])
        glb = batch_dir / f"{asset_id}.glb"
        if not glb.is_file():
            obs.append({"asset_id": asset_id, "archetype": gen.get("archetype"),
                        "verdict": "NOT_FOUND", "checks": {}, "manifeste_humain": False,
                        "objets": len(gen.get("objects_created") or [])})
            continue
        rapport = O.run(glb)
        obs.append({
            "asset_id": asset_id,
            "archetype": gen.get("archetype"),
            "objets": len(gen.get("objects_created") or []),
            "glb_bytes": gen.get("glb_bytes"),
            "verdict": rapport.verdict,
            "reason": rapport.reason,
            "checks": {c["name"]: c["verdict"] for c in rapport.checks},
            # Trace du passage par un humain : le sidecar de recensement existe.
            "manifeste_humain": Path(str(glb) + ".geometry.json").is_file(),
            "inconnus": [c["name"] for c in rapport.census
                         if c["classification"] == "UNKNOWN"],
        })
    return obs


def derive_lessons(obs: list[dict[str, Any]], batch_id: str) -> list[dict[str, Any]]:
    """Derive des lecons MECANIQUEMENT. Aucun modele, aucune interpretation libre."""
    lessons: list[dict[str, Any]] = []

    # --- Regle 1 : un archetype qui a EXIGE une intervention humaine la ré-exigera.
    par_arch: dict[str, list[dict]] = {}
    for o in obs:
        par_arch.setdefault(o.get("archetype") or "?", []).append(o)

    for arch, items in sorted(par_arch.items()):
        besoin_humain = [i for i in items if i["manifeste_humain"]]
        if not besoin_humain:
            continue
        lessons.append({
            "schema_version": SCHEMA_VERSION,
            "lesson_id": f"asset.{arch}_exige_declaration_variantes",
            "batch_id": batch_id,
            "asset_type": arch,
            "generation": 1,
            "defauts_detectes": [{
                "oracle": "forge/asset_geometry/oracle.py",
                "check": "all_meshes_declared",
                "verdict": "BLOCKED",
                "assets": [i["asset_id"] for i in besoin_humain],
                "detail": (f"{len(besoin_humain)}/{len(items)} asset(s) de type '{arch}' "
                           "ont exige un manifeste HumanGate avant de passer"),
            }],
            "cause_racine": {
                "couche": "spec",
                "enonce": (f"Les specs de type '{arch}' ne declarent pas leurs etats "
                           "mutuellement exclusifs en amont ; le blocage arrive donc "
                           "APRES production, quand un humain doit trancher."),
            },
            "correction_recommandee": {
                "cible": f"spec de tout asset archetype='{arch}'",
                "action": ("Exiger `variants` non vide dans la spec AVANT production, "
                           "pour que le besoin de recensement soit connu d'avance."),
                "interdit": ("Classer les variantes MAIN automatiquement pour eviter le "
                             "blocage : ce serait supprimer la question, pas y repondre."),
            },
            "impact_prochain_lot": {
                "change": (f"Le dispatcher refusera une spec '{arch}' sans `variants` "
                           "declarees."),
                "verification": ("Dispatcher une spec de ce type sans variants : le run "
                                 "doit s'arreter AVANT Blender."),
                "attendu": "BLOCKED · SPEC_VIOLATES_BATCH_CONSTRAINT",
            },
            # Version MECANIQUE de `attendu` : sans elle, APPLIED/REFUTED resterait un
            # jugement de lecture. C'est ce champ que `verify_lesson` consomme.
            "verification_mecanique": {
                "kind": "dispatch_blocked",
                "archetype": arch,
                "expected_reason": "SPEC_VIOLATES_BATCH_CONSTRAINT",
            },
            "status": STATUS_CANDIDATE,
        })

    # --- Regle 2 : un check en echec sur un archetype devient une lecon nommee.
    echecs: dict[tuple[str, str], list[str]] = {}
    for o in obs:
        for nom, v in (o.get("checks") or {}).items():
            if v == "FAIL":
                echecs.setdefault((o.get("archetype") or "?", nom), []).append(o["asset_id"])
    for (arch, check), assets in sorted(echecs.items()):
        lessons.append({
            "schema_version": SCHEMA_VERSION,
            "lesson_id": f"asset.{arch}_{check}",
            "batch_id": batch_id,
            "asset_type": arch,
            "generation": 1,
            "defauts_detectes": [{
                "oracle": "forge/asset_geometry/oracle.py",
                "check": check, "verdict": "FAIL", "assets": assets,
                "detail": f"{len(assets)} asset(s) en echec sur {check}",
            }],
            "cause_racine": {
                "couche": "producteur",
                "enonce": f"La construction de l'archetype '{arch}' viole {check}.",
            },
            "correction_recommandee": {
                "cible": "forge/asset_producer/build_asset.py",
                "action": f"Corriger la construction de '{arch}' pour satisfaire {check}.",
                "interdit": ("Desserrer le seuil correspondant dans rules.yaml : il "
                             "protege tous les assets, pas seulement celui-ci."),
            },
            "impact_prochain_lot": {
                "change": f"L'archetype '{arch}' est interdit de dispatch jusqu'a correction.",
                "verification": f"Rejouer le lot : plus aucun FAIL sur {check}.",
                "attendu": f"0 FAIL sur {check}",
            },
            "verification_mecanique": {
                "kind": "no_check_failure",
                "archetype": arch,
                "check": check,
            },
            "status": STATUS_CANDIDATE,
        })

    return lessons


def build_constraints(lessons: list[dict[str, Any]]) -> dict[str, Any]:
    """Traduit les lecons ratifiees en contraintes appliquees au lot suivant.

    Statuts CONTRAIGNANTS : `VALIDATED` (ratifiee, effet pas encore mesure) et
    `APPLIED` (ratifiee ET effet mesure). Une lecon APPLIED garde sa contrainte —
    la retirer parce qu'elle a marche reintroduirait le defaut qu'elle ferme.

    Statuts NON contraignants : `CANDIDATE` (pas de ratification humaine) et
    `REFUTED` (l'effet annonce ne s'est pas produit : la contrainte tombe, c'est
    tout l'interet de pouvoir refuter).
    """
    CONTRAIGNANTS = (STATUS_VALIDATED, STATUS_APPLIED)
    require_variants: list[str] = []
    archetypes_bloques: list[str] = []
    sources: list[str] = []

    for l in lessons:
        if l.get("status") not in CONTRAIGNANTS:
            continue
        sources.append(l["lesson_id"])
        if l["lesson_id"].endswith("_exige_declaration_variantes"):
            require_variants.append(l["asset_type"])
        elif l["defauts_detectes"][0]["verdict"] == "FAIL":
            archetypes_bloques.append(l["asset_type"])

    return {
        "schema_version": SCHEMA_VERSION,
        "require_variants_declared": sorted(set(require_variants)),
        "archetypes_blocked": sorted(set(archetypes_bloques)),
        "derived_from": sorted(set(sources)),
        "note": ("Contraintes appliquees par asset_dispatch AVANT production. "
                 "Seules les lecons VALIDATED sont prises en compte."),
    }


# --------------------------------------------------------------------- P1 : APPLIED / REFUTED

STATUS_APPLIED = "APPLIED"
STATUS_REFUTED = "REFUTED"

RESULTS_PATH = REPO / "EVIDENCE" / "bundles" / "asset_results.jsonl"


def load_run_results(results_path: Path | None = None) -> list[dict[str, Any]]:
    """Lit la trace REELLE des dispatches. Source unique de la mesure d'effet."""
    p = results_path or RESULTS_PATH
    if not p.is_file():
        return []
    out = []
    for ligne in p.read_text(encoding="utf-8").splitlines():
        ligne = ligne.strip()
        if not ligne:
            continue
        try:
            out.append(json.loads(ligne))
        except json.JSONDecodeError:
            continue
    return out


def verify_lesson(lesson: dict[str, Any], resultats: list[dict[str, Any]],
                  *, depuis_ts: float | None = None) -> dict[str, Any]:
    """Mesure si l'effet ANNONCE par une lecon s'est produit dans les runs posterieurs.

    Retourne {verdict, observed, expected, n_runs}. `verdict` vaut :
      APPLIED           -- l'effet annonce est observe
      REFUTED           -- des runs pertinents existent et l'effet ne s'est PAS produit
      INSUFFICIENT_DATA -- aucun run pertinent depuis la validation : on ne conclut PAS

    INSUFFICIENT_DATA est un verdict a part entiere. Confondre « pas encore verifie »
    avec « refute » ferait mentir la boucle dans les deux sens.
    """
    vm = lesson.get("verification_mecanique") or {}
    kind = vm.get("kind")
    arch = vm.get("archetype")
    if not kind:
        return {"verdict": "INSUFFICIENT_DATA", "observed": None,
                "expected": lesson.get("impact_prochain_lot", {}).get("attendu"),
                "n_runs": 0, "detail": "lecon sans verification_mecanique"}

    ts0 = depuis_ts if depuis_ts is not None else lesson.get("validated_at_ts") or 0
    pertinents = [r for r in resultats
                  if (r.get("ts") or 0) > ts0 and r.get("archetype") == arch]

    if not pertinents:
        return {"verdict": "INSUFFICIENT_DATA", "observed": None,
                "expected": vm, "n_runs": 0,
                "detail": f"aucun run '{arch}' posterieur a la validation"}

    if kind == "dispatch_blocked":
        attendu = vm.get("expected_reason")
        # L'effet est observe si TOUT run pertinent a ete bloque pour la bonne raison.
        bloques = [r for r in pertinents if r.get("reason") == attendu]
        ok = len(bloques) == len(pertinents)
        return {
            "verdict": STATUS_APPLIED if ok else STATUS_REFUTED,
            "observed": [r.get("reason") or r.get("oracle_verdict") for r in pertinents],
            "expected": attendu, "n_runs": len(pertinents),
            "detail": (f"{len(bloques)}/{len(pertinents)} run(s) '{arch}' bloque(s) "
                       f"pour {attendu}"),
        }

    if kind == "no_check_failure":
        check = vm.get("check")
        echecs = [r for r in pertinents
                  if (r.get("oracle_checks") or {}).get(check) == "FAIL"]
        ok = not echecs
        return {
            "verdict": STATUS_APPLIED if ok else STATUS_REFUTED,
            "observed": f"{len(echecs)} echec(s) sur {check}",
            "expected": f"0 echec sur {check}", "n_runs": len(pertinents),
            "detail": (f"{len(echecs)}/{len(pertinents)} run(s) '{arch}' encore en echec"
                       if echecs else f"aucun echec sur {check} depuis la validation"),
        }

    return {"verdict": "INSUFFICIENT_DATA", "observed": None, "expected": vm,
            "n_runs": len(pertinents), "detail": f"kind inconnu: {kind}"}


def load_lessons() -> list[dict[str, Any]]:
    if not LESSONS_DIR.is_dir():
        return []
    out = []
    for f in sorted(LESSONS_DIR.glob("asset.*.json")):
        out.append(json.loads(f.read_text(encoding="utf-8")))
    return out


def write_lessons(lessons: list[dict[str, Any]]) -> list[str]:
    LESSONS_DIR.mkdir(parents=True, exist_ok=True)
    ecrits = []
    for l in lessons:
        p = LESSONS_DIR / f"{l['lesson_id']}.json"
        if p.is_file():
            # Ne jamais ecraser une lecon deja validee par un humain.
            existante = json.loads(p.read_text(encoding="utf-8"))
            if existante.get("status") != STATUS_CANDIDATE:
                continue
        p.write_text(json.dumps(l, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        ecrits.append(l["lesson_id"])
    return ecrits


def refresh_constraints() -> dict[str, Any]:
    c = build_constraints(load_lessons())
    LESSONS_DIR.mkdir(parents=True, exist_ok=True)
    CONSTRAINTS_PATH.write_text(json.dumps(c, indent=2, ensure_ascii=False) + "\n",
                                encoding="utf-8")
    return c


def load_constraints() -> dict[str, Any]:
    """Lu par asset_dispatch. Absent = aucune contrainte (jamais une erreur)."""
    if not CONSTRAINTS_PATH.is_file():
        return {"require_variants_declared": [], "archetypes_blocked": []}
    return json.loads(CONSTRAINTS_PATH.read_text(encoding="utf-8"))


# Une signature humaine ne peut JAMAIS etre simulee, meme pour une demonstration
# (regle ratifiee Pierre, 2026-08-06). Incident a l'origine de cette garde : une lecon
# avait ete validee `--par "Pierre (demo)"` pour montrer la boucle bouger — une signature
# qu'il n'avait pas donnee. Retiree depuis, et rendue impossible ici.
#
# LIMITE ASSUMEE : ce filtre attrape les marqueurs EXPLICITES de simulation. Il ne peut
# pas distinguer un nom plausible mais faux — aucune garde locale ne le peut. Il ferme
# la panne observee, il ne prouve pas l'authenticite d'une signature.
MARQUEURS_DE_SIMULATION = ("demo", "test", "fake", "factice", "simul", "example",
                           "exemple", "dummy", "todo", "xxx", "placeholder")

#: Repertoire de lecons du DEPOT. Toute autre valeur de `LESSONS_DIR` est un bac a sable.
LESSONS_DIR_REEL = REPO / "EVIDENCE" / "bundles" / "asset_lessons"


def _dans_l_etat_reel() -> bool:
    """`LESSONS_DIR` pointe-t-il sur l'etat versionne du depot ?"""
    try:
        return Path(LESSONS_DIR).resolve() == LESSONS_DIR_REEL.resolve()
    except Exception:
        return True  # dans le doute, on protege l'etat reel


def valider(lesson_id: str, par: str) -> dict[str, Any]:
    """CANDIDATE -> VALIDATED. Geste humain : `par` est requis, jamais un defaut."""
    if not par:
        raise ValueError("--par est requis : on ne valide jamais une lecon anonymement")

    minuscule = par.lower()
    trouve = [m for m in MARQUEURS_DE_SIMULATION if m in minuscule]
    # La regle porte sur l'ETAT REEL, pas sur le geste en soi : simuler une signature
    # dans un bac a sable est precisement la maniere correcte de tester la boucle
    # (c'est ce que ce message recommandait tout en l'interdisant — incoherence
    # corrigee le 2026-08-06). `LESSONS_DIR` hors du depot = bac a sable.
    if trouve and _dans_l_etat_reel():
        raise ValueError(
            f"ratification refusee : {par!r} porte un marqueur de simulation {trouve}. "
            "Une signature humaine ne se simule jamais dans l'etat reel du depot. "
            "Pour tester la boucle, pointez LESSONS_DIR sur un repertoire jetable : "
            "la simulation y est autorisee, et n'engage personne."
        )
    p = LESSONS_DIR / f"{lesson_id}.json"
    if not p.is_file():
        raise ValueError(f"lecon inconnue: {lesson_id}")
    l = json.loads(p.read_text(encoding="utf-8"))
    import time as _time
    l["status"] = STATUS_VALIDATED
    l["validated_by"] = par
    # Horodatage indispensable a P1 : sans lui, `verify_lesson` ne saurait pas quels
    # runs sont POSTERIEURS a la validation, et mesurerait l'effet sur des runs qui
    # l'ont precede — une lecon se confirmerait toujours retroactivement.
    l["validated_at_ts"] = _time.time()
    p.write_text(json.dumps(l, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    refresh_constraints()
    return l


def classer(lesson_id: str, *, results_path: Path | None = None) -> dict[str, Any]:
    """P1 : mesure l'effet et fige APPLIED / REFUTED dans la lecon.

    Ne fige RIEN si la mesure rend INSUFFICIENT_DATA : on ne conclut pas sans runs.
    """
    p = LESSONS_DIR / f"{lesson_id}.json"
    if not p.is_file():
        raise ValueError(f"lecon inconnue: {lesson_id}")
    l = json.loads(p.read_text(encoding="utf-8"))
    if l.get("status") != STATUS_VALIDATED:
        raise ValueError(
            f"lecon {lesson_id!r} en statut {l.get('status')!r} : seule une lecon "
            "VALIDATED peut etre classee (une lecon non ratifiee n'a contraint aucun lot)"
        )

    mesure = verify_lesson(l, load_run_results(results_path))
    l["verification_result"] = mesure
    if mesure["verdict"] in (STATUS_APPLIED, STATUS_REFUTED):
        l["status"] = mesure["verdict"]
    p.write_text(json.dumps(l, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    refresh_constraints()
    return l


# --------------------------------------------------------------------- P3 : lecon -> proposition

PROPOSALS_DIR = REPO / "knowledge_base" / "proposals"
ORIGINAL_MARKER = "ORIGINAL — aucune inspiration externe citee"


def _repo_relative(p: Path) -> str:
    """Chemin relatif au depot si possible, sinon tel quel. Ne leve jamais."""
    try:
        return p.resolve().relative_to(REPO).as_posix()
    except Exception:
        return str(p).replace("\\", "/")


def propose_lesson(lesson_id: str) -> Path:
    """Depose la lecon comme `kb.proposal.v1` — MEME porte que tout le reste.

    Pourquoi : `--valider --par` etait une porte de ratification AD HOC, propre a ce
    module. Une lecon qui contraint la production merite la meme porte que l'ingestion
    d'un asset : une seule autorite, un seul geste, un seul endroit ou un humain signe.
    La promotion se fait par :

        python -m scripts.forge.kb_proposal --apply lesson.<id> --ratifie-par "<humain>"

    Ce module n'ecrit JAMAIS le catalogue.
    """
    import yaml

    p = LESSONS_DIR / f"{lesson_id}.json"
    if not p.is_file():
        raise ValueError(f"lecon inconnue: {lesson_id}")
    l = json.loads(p.read_text(encoding="utf-8"))

    pid = f"lesson.{lesson_id}"
    brick_id = "pat-" + lesson_id.replace("asset.", "asset-").replace("_", "-")
    enonce = l["cause_racine"]["enonce"]

    record = {
        "schema": "kb.proposal.v1",
        "status": "PROPOSED",
        "proposal_id": pid,
        "origine": "asset_library_v1 — forge/asset_producer/analyze_batch.py",
        "statement": (f"Lecon tiree du lot '{l['batch_id']}' sur les assets de type "
                      f"'{l['asset_type']}' : {enonce}"),
        "entree_catalogue_proposee": {
            "entry_type": "brick",
            "brick_id": brick_id,
            "kind": "pattern",
            "function": enonce,
            "source": ORIGINAL_MARKER + " — lecon Forge (analyze_batch)",
            "provenance_url": None,
            "license": "CC0-1.0",
            "runtime": "agnostic",
            "dependencies": [],
            "parameters": {},
            "genre_compatible": ["generic"],
            "invariants": [l["correction_recommandee"]["action"]],
            "proof_of_use": None,
            "tier": "candidate",
            "path": None,
            "sha256": None,
        },
        "preuve": {
            "batch_id": l["batch_id"],
            "asset_type": l["asset_type"],
            "defauts_detectes": l["defauts_detectes"],
            "verification_mecanique": l.get("verification_mecanique"),
            "attendu": l["impact_prochain_lot"]["attendu"],
            # Chemin relatif au depot quand c'est possible ; un bac a sable vit hors
            # du depot et garde alors son chemin tel quel (jamais une exception).
            "lesson_ref": _repo_relative(p),
        },
        "ratification": {
            "statut": "EN_ATTENTE",
            "decideur": None,
            "commande": f'python -m scripts.forge.kb_proposal --apply {pid} --ratifie-par "<humain>"',
        },
    }

    PROPOSALS_DIR.mkdir(parents=True, exist_ok=True)
    out = PROPOSALS_DIR / f"{pid}.yaml"
    with open(out, "w", encoding="utf-8") as fh:
        yaml.safe_dump(record, fh, allow_unicode=True, sort_keys=False)
    return out


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("batch_dir", nargs="?", help="repertoire du lot analyse")
    ap.add_argument("--batch-id", default=None)
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--valider", metavar="LESSON_ID", default=None)
    ap.add_argument("--par", default=None, help="requis avec --valider")
    ap.add_argument("--proposer", metavar="LESSON_ID", default=None,
                    help="depose la lecon comme kb.proposal.v1 (porte de ratification commune)")
    ap.add_argument("--classer", metavar="LESSON_ID", default=None,
                    help="mesure l'effet reel et fige APPLIED / REFUTED")
    ns = ap.parse_args(argv)

    if ns.proposer:
        out = propose_lesson(ns.proposer)
        print(f"PROPOSE   lesson.{ns.proposer}")
        print(f"          -> {out.relative_to(REPO).as_posix()}")
        print("Ratification (geste humain, porte commune) :")
        print(f'  python -m scripts.forge.kb_proposal --apply lesson.{ns.proposer} '
              f'--ratifie-par "<humain>"')
        return 0

    if ns.classer:
        l = classer(ns.classer)
        m = l["verification_result"]
        print(f"{l['status']:<18} {l['lesson_id']}")
        print(f"  attendu  : {m['expected']}")
        print(f"  observe  : {m['observed']}")
        print(f"  runs     : {m['n_runs']}")
        print(f"  detail   : {m['detail']}")
        return 0

    if ns.valider:
        l = valider(ns.valider, ns.par or "")
        print(f"VALIDEE   {l['lesson_id']} (par {l['validated_by']})")
        print(f"contraintes -> {CONSTRAINTS_PATH.relative_to(REPO).as_posix()}")
        return 0

    if ns.list:
        for l in load_lessons():
            print(f"{l['status']:<10} {l['lesson_id']:<50} {l['asset_type']}")
        c = load_constraints()
        print(f"\ncontraintes actives : variants exiges={c['require_variants_declared']} "
              f"archetypes bloques={c['archetypes_blocked']}")
        return 0

    if not ns.batch_dir:
        ap.print_help()
        return 2

    batch_dir = Path(ns.batch_dir)
    batch_id = ns.batch_id or batch_dir.name
    obs = collect(batch_dir)
    if not obs:
        print(f"aucun generation_report.json dans {batch_dir}", file=sys.stderr)
        return 2

    lessons = derive_lessons(obs, batch_id)
    ecrits = write_lessons(lessons)
    refresh_constraints()

    print(f"lot analyse   : {batch_id} ({len(obs)} asset(s))")
    for o in obs:
        marque = " [manifeste humain]" if o["manifeste_humain"] else ""
        print(f"  {o['verdict']:<8} {o['asset_id']:<26} archetype={o['archetype']}{marque}")
    print(f"\nlecons ecrites : {len(ecrits)}")
    for e in ecrits:
        print(f"  CANDIDATE  {e}")
    print(f"\nRatification (geste humain) :")
    print("  python -m scripts.forge.asset_producer.analyze_batch --valider <lesson_id> --par \"<humain>\"")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
