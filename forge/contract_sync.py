"""contract_sync — capteur de synchronisation du CONTRAT DE SYSTÈME Forge.

Point d'accroche déclaré par `forge/FORGE_SYSTEM_CONTRACT.yaml`
(bloc ``verification``). Contrôle MÉCANIQUE, déterministe, non-LLM : pour
chaque règle de ``regles_canoniques``, vérifie que le fichier de pilotage
(``.claude/skills/forge/skill.md``) CITE le symbole de sa source unique, au
lieu de la réécrire ailleurs (l'incident fondateur de ce contrat : la règle
d'escalade décrite en prose dans le skill pendant que le code la rendait
inerte — trouvé le 2026-07-22).

Deux violations distinctes :
  - ``regle_non_citee``  : aucun symbole de la règle n'apparaît dans le skill.
  - ``source_introuvable`` : le fichier déclaré comme source n'existe pas sur
    disque, ou (source ``fichier::symbole``) le symbole n'existe pas dedans.
    Un contrat qui pointe vers du vide est le défaut qu'il prétend combattre.

Extraction du symbole attendu (règle donnée, appliquée littéralement) :
  - s'il y a ``::``, le symbole est ce qui suit ;
  - sinon, c'est le nom de fichier sans extension.
Cas particulier rencontré dans le contrat réel : plusieurs symboles groupés
dans UNE source après ``::``, séparés par des virgules (ex.
``dispatch.py::ORDER, PROFILES, order_for_profile``). Ce module les découpe
en symboles candidats et applique la MÊME règle « au moins un cité » que
pour une ``source`` déclarée comme liste de fichiers — c'est une
généralisation mécanique (tokenisation sur la virgule), pas un jugement
sémantique. La vérification d'EXISTENCE, elle, reste stricte : chaque
symbole déclaré doit être présent dans le fichier, faute de quoi
``source_introuvable`` (le contrat ne peut pas prétendre qu'un symbole vit
dans un fichier qui ne le contient pas, même si un autre symbole du même
groupe suffit à satisfaire la citation).

CE QUE CE MODULE NE FAIT PAS : il ne juge pas la prose, ne compare aucune
sémantique, n'appelle aucun LLM, et ne modifie JAMAIS ``skill.md`` ni le
contrat — il constate. Limite déclarée (identique à celle du contrat,
bloc ``verification.limite_declaree``) : ce contrôle détecte l'ABSENCE DE
CITATION, pas la duplication sémantique. Une prose qui cite correctement sa
source tout en la contredisant passerait au travers. Garantie partielle,
assumée comme telle — ne jamais la présenter comme une preuve de
non-divergence.

Aucune fonction de ce module ne lève d'exception sur une entrée malformée
(contrat absent, YAML illisible, ``regles_canoniques`` absent/malformé,
``source`` d'un type inattendu, fichier de pilotage absent) : FAIL honnête
avec raison explicite, même doctrine que ``static_oracles.check_charter``.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any

import yaml

from forge.verify_run import _harden_streams

DEFAULT_CONTRACT_PATH = "forge/FORGE_SYSTEM_CONTRACT.yaml"
DEFAULT_SKILL_PATH = ".claude/skills/forge/skill.md"


def _read_text(path: Path) -> str | None:
    """Lecture UTF-8 tolérante — None (jamais d'exception) si illisible."""
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        return None


def _symbol_present(text: str, symbol: str) -> bool:
    """Le token `symbol` apparaît-il dans `text`, aux frontières de mot (pas une sous-chaîne d'un autre identifiant) ?"""
    if not symbol:
        return False
    pattern = r"(?<!\w)" + re.escape(symbol) + r"(?!\w)"
    return re.search(pattern, text) is not None


def _split_source_entry(entry: str) -> tuple[str, list[str]]:
    """Découpe une entrée `source` unique en (chemin_fichier, [symboles attendus]).

    Règle d'extraction : s'il y a `::`, le symbole est ce qui suit ; sinon,
    nom de fichier sans extension. Un groupe de symboles séparés par des
    virgules après `::` (cas réel : `dispatch.py::ORDER, PROFILES,
    order_for_profile`) est découpé en plusieurs symboles candidats.
    """
    if "::" in entry:
        file_part, _, symbol_part = entry.partition("::")
        file_part = file_part.strip()
        symbols = [s.strip() for s in symbol_part.split(",") if s.strip()]
        if not symbols:
            symbols = [symbol_part.strip()]
        return file_part, symbols
    file_part = entry.strip()
    return file_part, [Path(file_part).stem]


def _normalize_sources(raw: Any) -> list[str] | None:
    """`source` (str ou liste de str) -> liste d'entrées source. None si type inattendu/vide."""
    if isinstance(raw, str) and raw.strip():
        return [raw]
    if isinstance(raw, list) and raw and all(isinstance(x, str) and x.strip() for x in raw):
        return list(raw)
    return None


def _audit_rule(repo_root: Path, rule: dict, skill_text: str) -> dict:
    """Audite une entrée de `regles_canoniques`. Ne lève jamais.

    Retourne {regle, symboles_attendus, cite, cited_symbol, entries, violations}.
    """
    regle_nom = rule.get("regle") if isinstance(rule.get("regle"), str) else "<sans nom>"
    raw_source = rule.get("source")
    sources = _normalize_sources(raw_source)

    if sources is None:
        return {
            "regle": regle_nom,
            "symboles_attendus": [],
            "cite": False,
            "cited_symbol": None,
            "entries": [],
            "violations": [{
                "type": "source_malformee",
                "regle": regle_nom,
                "detail": f"champ 'source' absent ou de type inattendu (reçu {raw_source!r})",
            }],
        }

    violations: list[dict] = []
    entries_report: list[dict] = []
    tous_symboles: list[str] = []

    for entry in sources:
        file_part, symbols = _split_source_entry(entry)
        tous_symboles.extend(symbols)
        abs_path = repo_root / file_part
        file_exists = abs_path.is_file()
        content = _read_text(abs_path) if file_exists else None
        missing_symbols: list[str] = []
        if file_exists and content is not None and "::" in entry:
            missing_symbols = [s for s in symbols if not _symbol_present(content, s)]
        elif file_exists and content is None and "::" in entry:
            # fichier présent mais illisible (pas UTF-8, permission...) : on ne peut
            # pas prouver le symbole présent -> traité comme absent, motivé.
            missing_symbols = list(symbols)

        entries_report.append({
            "source": entry,
            "file": file_part,
            "file_exists": file_exists,
            "symbols": symbols,
            "missing_symbols": missing_symbols,
        })

        if not file_exists:
            violations.append({
                "type": "source_introuvable",
                "regle": regle_nom,
                "source": entry,
                "detail": f"fichier source introuvable : {file_part}",
            })
        elif missing_symbols:
            violations.append({
                "type": "source_introuvable",
                "regle": regle_nom,
                "source": entry,
                "detail": f"symbole(s) absent(s) de {file_part} : {', '.join(missing_symbols)}",
            })

    cited_symbol = next((s for s in tous_symboles if _symbol_present(skill_text, s)), None)
    cite = cited_symbol is not None
    if not cite:
        violations.append({
            "type": "regle_non_citee",
            "regle": regle_nom,
            "symboles_attendus": list(tous_symboles),
            "detail": (f"règle « {regle_nom} » : aucun des symboles attendus "
                       f"{tous_symboles} n'est cité dans le fichier de pilotage"),
        })

    return {
        "regle": regle_nom,
        "symboles_attendus": tous_symboles,
        "cite": cite,
        "cited_symbol": cited_symbol,
        "entries": entries_report,
        "violations": violations,
    }


def check_contract_sync(
    repo_root: Path | str,
    contract_path: str = DEFAULT_CONTRACT_PATH,
    skill_path: str = DEFAULT_SKILL_PATH,
) -> dict:
    """Capteur de synchronisation contrat-de-système <-> fichier de pilotage.

    Retourne TOUJOURS {passed, checked, violations[], regles[], raison?} —
    jamais d'exception, même sur une entrée totalement cassée.
    ``checked`` distingue « le contrôle a pu tourner » (violations éventuelles
    dedans) de « le contrôle n'a pas pu démarrer » (raison motivée, ``regles``
    vide). ``passed`` est faux dans les deux cas si un problème existe.
    """
    repo_root = Path(repo_root)
    contract_full = repo_root / contract_path
    skill_full = repo_root / skill_path

    if not contract_full.is_file():
        return {"passed": False, "checked": False, "violations": [], "regles": [],
                "raison": f"contrat introuvable : {contract_path}"}

    raw_yaml = _read_text(contract_full)
    if raw_yaml is None:
        return {"passed": False, "checked": False, "violations": [], "regles": [],
                "raison": f"contrat illisible (erreur de lecture) : {contract_path}"}

    try:
        contract = yaml.safe_load(raw_yaml)
    except yaml.YAMLError as exc:
        return {"passed": False, "checked": False, "violations": [], "regles": [],
                "raison": f"YAML illisible dans {contract_path} : {exc}"}

    if not isinstance(contract, dict):
        return {"passed": False, "checked": False, "violations": [], "regles": [],
                "raison": f"contrat n'est pas un mapping (reçu {type(contract).__name__})"}

    regles = contract.get("regles_canoniques")
    if not isinstance(regles, list) or not regles:
        return {"passed": False, "checked": False, "violations": [], "regles": [],
                "raison": "'regles_canoniques' absent, vide ou de type inattendu (liste non vide attendue)"}

    if not skill_full.is_file():
        return {"passed": False, "checked": False, "violations": [], "regles": [],
                "raison": f"fichier de pilotage introuvable : {skill_path}"}

    skill_text = _read_text(skill_full)
    if skill_text is None:
        return {"passed": False, "checked": False, "violations": [], "regles": [],
                "raison": f"fichier de pilotage illisible (erreur de lecture) : {skill_path}"}

    all_violations: list[dict] = []
    rule_reports: list[dict] = []
    for i, rule in enumerate(regles):
        if not isinstance(rule, dict):
            all_violations.append({
                "type": "regle_malformee",
                "index": i,
                "detail": f"regles_canoniques[{i}] n'est pas un mapping (reçu {type(rule).__name__})",
            })
            continue
        report = _audit_rule(repo_root, rule, skill_text)
        rule_reports.append(report)
        all_violations.extend(report["violations"])

    return {
        "passed": not all_violations,
        "checked": True,
        "violations": all_violations,
        "regles": rule_reports,
        "contract_path": contract_path,
        "skill_path": skill_path,
    }


def main(argv: list[str] | None = None) -> int:
    """Point d'entrée CLI séparé — le module lui-même ne fait aucun print().

    `_harden_streams()` (réutilisée telle quelle depuis `forge.verify_run`, même
    doctrine que `run_real.py`) est appelée EN PREMIER : sous Windows cp1252, un
    caractère hors table (⚠, ✅...) — qu'il vienne des libellés fixes ci-dessous OU
    du CONTENU du contrat (nom de règle, symbole) — levait `UnicodeEncodeError` à
    l'impression, faussant le code de sortie d'une chaîne automatisée. On garde
    l'encodage natif de la console (pas de bascule UTF-8 qui produirait du charabia
    illisible sur une console cp1252) et on remplace juste les caractères non
    représentables au lieu de planter — la valeur de retour de
    `check_contract_sync`, elle, est inchangée.

    `--json` (n'importe où dans argv, avant ou après `<repoRoot>`) bascule en sortie
    machine : stdout ne contient QUE `json.dumps(check_contract_sync(...), ensure_ascii=False)`,
    rien d'autre — aucune prose. Les codes de sortie (0/1/2) restent identiques dans les
    deux modes. Un drapeau n'est jamais confondu avec l'argument positionnel `<repoRoot>` :
    on ne garde que les éléments d'argv qui ne sont PAS `--json` pour trouver la racine."""
    _harden_streams()

    argv = argv if argv is not None else sys.argv[1:]
    json_mode = "--json" in argv
    positional = [a for a in argv if a != "--json"]

    here = Path(__file__).resolve()
    repo_root = here.parents[2]  # forge/contract_sync.py -> repo root
    if positional:
        repo_root = Path(positional[0]).resolve()

    r = check_contract_sync(repo_root)

    if json_mode:
        print(json.dumps(r, ensure_ascii=False))
        if not r["checked"]:
            return 2
        return 0 if r["passed"] else 1

    print(f"=== CAPTEUR DE SYNCHRONISATION — contrat de système Forge ({repo_root}) ===\n")
    if not r["checked"]:
        print(f"NON ÉVALUABLE : {r['raison']}")
        return 2

    print(f"Règles auditées : {len(r['regles'])}")
    print(f"Violations      : {len(r['violations'])}\n")

    for v in r["violations"]:
        if v["type"] == "regle_non_citee":
            print(f"  [regle_non_citee] « {v['regle']} » — symboles attendus "
                  f"{v['symboles_attendus']}, aucun cité dans le fichier de pilotage")
        elif v["type"] == "source_introuvable":
            print(f"  [source_introuvable] « {v['regle']} » — {v['detail']}")
        elif v["type"] == "source_malformee":
            print(f"  [source_malformee] « {v['regle']} » — {v['detail']}")
        elif v["type"] == "regle_malformee":
            print(f"  [regle_malformee] index {v['index']} — {v['detail']}")
        else:
            print(f"  [{v['type']}] {v}")

    print(f"\nVERDICT : {'SYNCHRONISÉ (mécaniquement) ✅' if r['passed'] else 'DÉRIVE DÉTECTÉE ⚠'}")
    print("\nLimite déclarée : détecte l'ABSENCE de citation, pas la duplication sémantique.")
    print("Ce n'est PAS une preuve de non-divergence — claim_verdict: NO_CLAIM_ALLOWED.")
    return 0 if r["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
