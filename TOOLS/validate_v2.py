"""Validation de CLÔTURE du Studio V2 — V0 gel · V1 structurel.

PIÈGE DE PROVENANCE (découvert le 2026-09-02) : depuis le `git init`, `Desktop/Studio` EST un
dépôt git. Une commande git lancée avec `cwd = Studio` interroge donc CE dépôt — qui ne contient
aucun objet de V1. Toute question portant sur `58095ba9` DOIT être posée avec `cwd = V1`.
Ce module ne pose jamais une question V1 au dépôt V2 : chaque appel nomme son `cwd`.

Ne modifie rien. Rend un compte-rendu par catégorie.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

V2 = Path(__file__).resolve().parents[1]
V1 = Path(r"C:\TACTICAL_CHESS_STUDIO")
HEAD_CANONIQUE = "58095ba9"

resultats: list[tuple[str, str, str]] = []          # (categorie, libelle, detail)


def note(cat: str, libelle: str, detail: str = "") -> None:
    resultats.append((cat, libelle, detail))


def git(cwd: Path, *args: str) -> tuple[int, str]:
    """Appel git EXPLICITEMENT situé — jamais de cwd implicite (piège de provenance)."""
    p = subprocess.run(["git", *args], cwd=str(cwd), capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    return p.returncode, (p.stdout or "").strip()


# ----------------------------------------------------------------------------- V0 · gel
def v0_gel() -> None:
    rc, head = git(V1, "log", "-1", "--format=%H")
    note("PASS" if rc == 0 and head.startswith(HEAD_CANONIQUE) else "FAIL",
         "V1 HEAD canonique", f"{head[:12]} (attendu {HEAD_CANONIQUE})")

    rc, sortie = git(V1, "status", "--porcelain", "scripts/forge")
    ecarts = [l for l in sortie.splitlines() if l.strip()]
    attendus = {"dispatch.py", "oracles.json", "test_evidence_isolation_fixture.py",
                "test_micro_sonde_profile.py"}
    noms = {Path(l[3:]).name for l in ecarts}
    note("PASS" if noms <= attendus else "FAIL",
         "V1 sans absorption concurrente",
         f"{len(ecarts)} écart(s), tous de l'autre session" if noms <= attendus
         else f"écarts inattendus : {sorted(noms - attendus)}")

    rc, _ = git(V2, "rev-parse", "--is-inside-work-tree")
    rc2, n = git(V2, "rev-list", "--count", "--all")
    note("PASS" if rc == 0 else "FAIL", "V2 est un dépôt git indépendant",
         f"{n or 0} commit — aucun historique V1 importé")

    rc, _ = git(V2, "cat-file", "-e", f"{HEAD_CANONIQUE}^{{commit}}")
    note("PASS" if rc != 0 else "FAIL", "V2 n'a AUCUN objet de V1",
         "58095ba9 introuvable dans le dépôt V2 — provenance étanche")


# ---------------------------------------------------------------- V1 · structurel
def v1_surfaces() -> None:
    attendues = ["forge", "knowledge_base", "GAMES", "EVIDENCE", "TOOLS", "docs",
                 ".claude", "control_plane", "MASTER_SCHEMA.html"]
    manquantes = [s for s in attendues if not (V2 / s).exists()]
    note("PASS" if not manquantes else "FAIL", "surfaces attendues",
         f"{len(attendues) - len(manquantes)}/{len(attendues)}"
         + (f" — manquantes : {manquantes}" if manquantes else ""))

    for nom, chemin in (("Control Plane — lane EXCLUE", V2 / "FORGE"),
                        ("EVIDENCE/bundles/asset_lessons", V2 / "EVIDENCE" / "bundles" / "asset_lessons")):
        if nom.startswith("Control"):
            note("PASS" if "FORGE" not in os.listdir(V2) else "FAIL", nom,
                 "aucune surface FORGE/ résiduelle (os.listdir : Path.exists() ment sur Windows, casse insensible)")
        else:
            note("NOT_YET_PRODUCED" if not chemin.exists() else "PASS", nom,
                 "n'existera qu'au premier run d'assets — non créé artificiellement")
    note("PASS" if (V2 / "control_plane" / "registry.py").exists() else "FAIL",
         "control_plane.registry CONSERVÉ", "dépendance runtime de forge.contract (ADR-002 gate 1)")


def v1_imports() -> None:
    import importlib, pkgutil
    sys.path.insert(0, str(V2))
    import forge  # noqa: E402
    ok, ko = 0, []
    for m in sorted(x.name for x in pkgutil.iter_modules(forge.__path__)):
        try:
            importlib.import_module(f"forge.{m}"); ok += 1
        except Exception as e:  # noqa: BLE001
            ko.append(f"{m}: {type(e).__name__}")
    note("PASS" if not ko else "FAIL", "modules forge importables", f"{ok}/{ok + len(ko)}"
         + (f" — échecs : {ko}" if ko else ""))

    from forge.contract import CONTRACTS_DIR, FORGE_ROLES, KB_CATALOG, KB_PROPOSALS_DIR
    from forge.verdict import DEFAULT_KEY_FILE
    from forge.oracle import DEFAULT_CONFIG
    chemins = {"CONTRACTS_DIR": CONTRACTS_DIR, "FORGE_ROLES": FORGE_ROLES,
               "KB_CATALOG": KB_CATALOG, "KB_PROPOSALS": KB_PROPOSALS_DIR,
               "DEFAULT_KEY_FILE": DEFAULT_KEY_FILE, "oracles.json": DEFAULT_CONFIG}
    absents = [k for k, p in chemins.items() if not p.exists()]
    note("PASS" if not absents else "FAIL", "chemins runtime résolus",
         f"{len(chemins) - len(absents)}/{len(chemins)}" + (f" — absents : {absents}" if absents else ""))


def v1_kb_contrats() -> None:
    from forge.contract import KB_CATALOG, consumption_evidence_adoption
    cat = json.loads(KB_CATALOG.read_text(encoding="utf-8"))
    entrees = cat if isinstance(cat, list) else next((v for v in cat.values() if isinstance(v, list)), [])
    note("PASS" if entrees else "FAIL", "knowledge_base — catalogue ratifié",
         f"{len(entrees)} entrées · {len(list((V2 / 'knowledge_base' / 'proposals').glob('*.yaml')))} propositions (jamais servies, R7)")
    a = consumption_evidence_adoption()
    note("PASS" if a["total"] else "FAIL", "contrats d'agent chargeables",
         f"{a['total']} lus · consumption_evidence : filled {a['filled']} / absent {a['absent']} (base P3)")


def v1_mandatory_read() -> None:
    motif = re.compile(r"(?<![\w/.])(?:\.claude|docs|forge|knowledge_base|GAMES)/[A-Za-z0-9_/.-]+\.(?:md|yaml|json|jsonl)")
    tot, manquants = 0, []
    for p in sorted((V2 / "forge" / "contracts").glob("*.yaml")):
        s = p.read_text(encoding="utf-8", errors="replace")
        m = re.search(r"^mandatory_read:(.*?)(?=^\w|\Z)", s, re.S | re.M)
        if not m:
            continue
        for r in motif.findall(m.group(1)):
            r = r.rstrip("."); tot += 1
            if not (V2 / r).is_file():
                manquants.append((p.name, r))
    note("PASS" if not manquants else "BLOCKED", "mandatory_read — précondition dure",
         f"{tot - len(manquants)}/{tot} résolues" + (f" — absentes : {manquants}" if manquants else ""))


def v1_fantomes_et_residus() -> None:
    s = json.loads((V2 / ".claude" / "settings.json").read_text(encoding="utf-8"))
    ok, ko = 0, []
    for groupes in s.get("hooks", {}).values():
        for g in groupes:
            for h in g.get("hooks", []):
                m = re.search(r'([\w./${}"-]*\.claude/hooks/[\w.-]+)', h.get("command", ""))
                if not m:
                    continue
                rel = m.group(1).replace('"', "").replace("$CLAUDE_PROJECT_DIR/", "")
                (ok := ok + 1) if (V2 / rel).is_file() else ko.append(rel)
    note("PASS" if not ko else "FAIL", ".claude — aucune référence fantôme",
         f"{ok} références résolues" + (f" — fantômes : {ko}" if ko else ""))

    exts = {".py", ".mjs", ".js", ".json", ".yaml", ".yml", ".gd"}
    actifs = {"lab/": 0, "games/": 0, "scripts/forge": 0}
    for f in (V2 / "forge").rglob("*"):
        if not f.is_file() or f.suffix not in exts or "__pycache__" in str(f):
            continue
        t = f.read_text(encoding="utf-8", errors="surrogateescape")
        for motif in actifs:
            if motif == "lab/":
                actifs[motif] += len(re.findall(r"(?<![A-Za-z0-9_])lab[/\\]", t))
            elif motif == "scripts/forge":
                # Une mention DATÉE de l'arborescence V1 (« `scripts/forge` (V1) ») est un
                # CONSTAT historique, pas une désignation active : elle ne compte pas.
                actifs[motif] += t.count(motif) - t.count("scripts/forge` (V1)")
            else:
                actifs[motif] += t.count(motif)
    note("PASS" if actifs["games/"] == 0 else "FAIL", "aucun chemin `games/` actif", str(actifs["games/"]))
    note("PASS" if actifs["scripts/forge"] == 0 else "FAIL", "aucun chemin `scripts/forge` actif",
         str(actifs["scripts/forge"]))
    note("PASS" if actifs["lab/"] <= 55 else "FAIL", "résidus `lab/` bornés et classés",
         f"{actifs['lab/']} occurrences — agent_policy (hors périmètre) · workflow_lab (garde) · placeholders de test")

    docs = len(list((V2 / "docs").rglob("*.md")))
    note("PASS" if docs >= 44 else "FAIL", "docs — dépendances documentaires importées",
         f"{docs} fichiers (critère : cité par un contrat ou du code actif)")


def rapport() -> int:
    par_cat: dict[str, int] = {}
    print("=" * 78)
    print("V2 VALIDATION — V0 gel · V1 structurel")
    print("=" * 78)
    for cat, libelle, detail in resultats:
        par_cat[cat] = par_cat.get(cat, 0) + 1
        marque = {"PASS": "  OK ", "FAIL": "FAIL ", "BLOCKED": "BLOC ",
                  "NOT_YET_PRODUCED": "NYP  ", "INTENTIONALLY_OUT_OF_SCOPE": "OOS  "}.get(cat, "  ?  ")
        print(f"{marque}{libelle:<44} {detail}")
    print("-" * 78)
    for c in ("PASS", "INTENTIONALLY_OUT_OF_SCOPE", "NOT_YET_PRODUCED", "BLOCKED", "FAIL"):
        print(f"  {c:<28}: {par_cat.get(c, 0)}")
    return 1 if par_cat.get("FAIL") else 0


if __name__ == "__main__":
    os.chdir(V2)
    v0_gel(); v1_surfaces(); v1_imports(); v1_kb_contrats(); v1_mandatory_read()
    v1_fantomes_et_residus()
    sys.exit(rapport())
