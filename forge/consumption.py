"""Mesure d'adoption de l'acquittement — décision P1, ratifiée Pierre 2026-09-02.

LA QUESTION, exactement : une capacité à qui un message a été opposé en a-t-elle
incorporé la référence dans **l'artefact qu'elle a elle-même désigné comme faisant foi**
(`consumption_evidence`, couche `verification`, P3) ?

Trois états, vocabulaire calqué sur `forge.skipped_validation.skipped_validation_status`
(ratification 2026-07-26, primitive livrée avec son point de mesure) :

  consumed              la référence est dans l'artefact DÉSIGNÉ de la capacité
  not_consumed          la capacité a un artefact désigné, la référence n'y est pas
  no_evidence_declared  la capacité n'a pas déclaré quel artefact fait foi

POURQUOI L'ARTEFACT DÉSIGNÉ, ET PAS « QUELQUE PART DANS LE RUN ».
`knowledge_trace.mjs --verify` balaie le run_dir ENTIER : il rend `FOUND` dès que la
référence apparaît dans un fichier quelconque — y compris
`context/prompt_<etape>_a<n>.txt`, qui contient le message parce qu'on le lui a servi
(faux positif F-2). Un `FOUND` prouve alors que le message a été DISTRIBUÉ, jamais qu'il
a été INCORPORÉ. Ce module ne regarde donc QUE l'artefact désigné : c'est la règle
d'acquittement du sas 1, et c'est la seule chose que `--verify` ne peut pas faire seul.

ADVISORY UNIQUEMENT — garde-fou de la ratification 2026-07-26, repris à la lettre :
- aucune fonction ici ne lit ni ne modifie un `software_verdict`, un `evidence_verdict`,
  un `verdict.json` signé, ni le comportement de `verify_run` / `gate.py` / `verdict.py` ;
- rien ne bloque, rien ne lève sur une entrée malformée : le pire résultat est
  `no_evidence_declared` ;
- le passage en gate dur est une **décision Pierre distincte et ultérieure**, prise au vu
  des chiffres mesurés ici — pas ici. Et elle reste bornée aux capacités **effectivement
  notifiées** : 88 run_dirs sur 89 ne portent aucune trace, les transformer en blocage
  global serait exactement la faute que N-2 vient de corriger.

NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

from pathlib import Path

from forge.contract import consumption_evidence_status, load_contract

CONSUMED = "consumed"
NOT_CONSUMED = "not_consumed"
NO_EVIDENCE_DECLARED = "no_evidence_declared"

# Fichiers jamais retenus comme preuve d'incorporation, même s'ils sont désignés : ils
# contiennent le message parce qu'on l'a SERVI, pas parce que la capacité l'a repris.
_NEVER_EVIDENCE_PARTS = ("context",)
_NEVER_EVIDENCE_NAMES = ("knowledge_trace.json",)

_MAX_BYTES = 4_000_000


def declared_evidence(capability: str, contracts_dir: Path | None = None) -> list[str]:
    """Artefacts déclarés faisant foi pour une capacité. Jamais d'exception.

    `aucun` (sentinelle) et l'absence rendent tous deux `[]` — la distinction entre les
    deux est portée par `consumption_evidence_status`, pas ici.
    """
    try:
        contract = load_contract(capability, contracts_dir=contracts_dir)
    except Exception:
        # Advisory : contrat introuvable, illisible ou mal formé ne peut JAMAIS faire
        # échouer une mesure. Rien de déclaré => rien à opposer.
        return []
    if consumption_evidence_status(contract) != "filled":
        return []
    value = contract.get("consumption_evidence")
    if isinstance(value, str):
        value = [value]
    return [str(v).strip() for v in value if str(v).strip()]


def _is_never_evidence(rel: str) -> bool:
    parts = rel.replace("\\", "/").split("/")
    return any(p in _NEVER_EVIDENCE_PARTS for p in parts[:-1]) or parts[-1] in _NEVER_EVIDENCE_NAMES


def resolve_artifacts(run_dir: Path, declared: list[str]) -> tuple[list[Path], list[str]]:
    """Résout des noms déclarés en fichiers réels du run. Retourne (trouvés, manquants).

    Trois règles, dans cet ordre, toutes déterministes : chemin relatif EXACT, puis
    suffixe de chemin, puis égalité de nom de fichier. Un artefact désigné qui vit sous
    `context/` (ou qui EST la trace) n'est jamais retenu — cf. F-2.
    """
    run_dir = Path(run_dir)
    if not run_dir.is_dir():
        return [], list(declared)
    corpus: list[tuple[str, Path]] = []
    for path in run_dir.rglob("*"):
        if not path.is_file():
            continue
        rel = str(path.relative_to(run_dir)).replace("\\", "/")
        if _is_never_evidence(rel):
            continue
        corpus.append((rel, path))

    found: list[Path] = []
    missing: list[str] = []
    for name in declared:
        want = name.replace("\\", "/").strip("/")
        hits = [p for rel, p in corpus if rel == want]
        if not hits:
            hits = [p for rel, p in corpus if rel.endswith("/" + want)]
        if not hits:
            base = want.rsplit("/", 1)[-1]
            hits = [p for rel, p in corpus if rel.rsplit("/", 1)[-1] == base]
        if hits:
            found.extend(sorted(set(hits)))
        else:
            missing.append(name)
    return found, missing


def _needles(ref: str) -> tuple[str, ...]:
    ref = str(ref or "")
    return tuple({ref, ref.replace("\\", "/"), ref.replace("/", "\\")} - {""})


def _contains_ref(path: Path, ref: str) -> bool:
    try:
        if path.stat().st_size > _MAX_BYTES:
            return False
        text = path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return False
    return any(n in text for n in _needles(ref))


def consumption_detail(
    message: dict,
    capability: str,
    run_dir: Path | str,
    contracts_dir: Path | None = None,
) -> dict:
    """Le constat complet : statut + ce sur quoi il repose. Ne lève jamais.

    ``artifacts_missing`` non vide avec ``status == not_consumed`` dit une chose que le
    vocabulaire à trois états ne sait PAS distinguer : la capacité a bien désigné un
    artefact, mais **ne l'a pas produit**. Ce n'est pas la même chose que « a produit
    sans reprendre la référence ». La distinction est portée ici, en clair, plutôt
    qu'inventée dans un 4e état non ratifié — c'est une question à trancher au vu des
    chiffres, pas par ce module.
    """
    ref = (message or {}).get("id") if isinstance(message, dict) else None
    declared = declared_evidence(capability, contracts_dir=contracts_dir)
    if not declared:
        return {
            "status": NO_EVIDENCE_DECLARED,
            "capability": capability,
            "ref": ref,
            "declared": [],
            "artifacts_checked": [],
            "artifacts_missing": [],
            "found_in": [],
        }

    run_path = Path(run_dir)
    found_files, missing = resolve_artifacts(run_path, declared)
    hits = [f for f in found_files if ref and _contains_ref(f, ref)]
    status = CONSUMED if hits else NOT_CONSUMED
    return {
        "status": status,
        "capability": capability,
        "ref": ref,
        "declared": declared,
        "artifacts_checked": [str(p.relative_to(run_path)).replace("\\", "/") for p in found_files],
        "artifacts_missing": missing,
        "found_in": [str(p.relative_to(run_path)).replace("\\", "/") for p in hits],
    }


def consumption_status(
    message: dict,
    capability: str,
    run_dir: Path | str,
    contracts_dir: Path | None = None,
) -> str:
    """`consumed` / `not_consumed` / `no_evidence_declared`. Ne lève jamais.

    Signature et vocabulaire exacts de la spécification ratifiée (sas 2, P1).
    """
    return consumption_detail(message, capability, run_dir, contracts_dir=contracts_dir)["status"]


def consumption_adoption(
    messages: list[dict],
    run_dir: Path | str,
    contracts_dir: Path | None = None,
) -> dict:
    """Adoption sur UN run : un constat par couple (message, capacité destinataire).

    Retourne les trois compteurs, le total de couples, et le détail. C'est la matière
    de la mesure M : combien de capacités notifiées acquittent réellement ? Aucun
    verdict n'est consulté ni produit.
    """
    counts = {CONSUMED: 0, NOT_CONSUMED: 0, NO_EVIDENCE_DECLARED: 0}
    details: list[dict] = []
    for message in messages or []:
        if not isinstance(message, dict):
            continue
        for capability in message.get("to", []) or []:
            detail = consumption_detail(message, str(capability), run_dir,
                                        contracts_dir=contracts_dir)
            counts[detail["status"]] += 1
            details.append(detail)
    return {**counts, "pairs": len(details), "details": details}
