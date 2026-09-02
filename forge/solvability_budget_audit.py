# -*- coding: utf-8 -*-
"""Audit de contradiction contrat <-> `oracles.json` sur le budget de solvabilité.

RAPPORTE, ne répare rien, ne gate rien — même discipline que `registryDivergences`
(« la réconciliation rapporte, ne ratifie jamais », doctrine 2026-08-10).

DÉFAUT MESURÉ (2026-08-17). Le budget EFFECTIF de la solvabilité est lu par
`godot_oracle.mjs::resolveSolvabilityConfig` dans `forge/oracles.json`. Le bloc
`proof.solvability` du contrat de jeu, lui, n'est lu QUE pour son champ `entry` — le câblage,
via `check_solvability_wired`. Ses trois champs de budget (`trials`, `max_ticks`,
`trial_timeout_ms`) n'ont AUCUN lecteur.

Ce n'est donc pas « un déclarant sans lecteur » mais une DÉCLARATION PARTIELLEMENT LUE : un
champ consommé sur quatre, sans qu'aucun signal ne distingue les deux catégories. Plus
insidieux qu'une inertie totale — la présence d'un consommateur donne l'impression que tout
le bloc compte.

Cas réel : `tetris` déclare `max_ticks: 20000, trial_timeout_ms: 60000` à son contrat et
tourne à `200 / 10000` (les VALEURS PAR DÉFAUT), faute d'entrée `solvability` dans
`oracles.json`. Son contrat n'a jamais eu la moindre chance d'agir.

Et le risque déborde ce cas : `snake`, `breakout_v2` et `bomberman_3d` sont cohérents parce
que quelqu'un a maintenu DEUX fichiers à la main. Rien ne garantit qu'ils le restent.

CE QUI N'EST PAS SIGNALÉ, décision de cadrage assumée : déclarer dans `oracles.json` SANS
bloc au contrat (cas `pacman`) est le régime NORMAL d'un jeu sans descripteur `proof`. Le
classer en anomalie créerait un faux positif PERMANENT. L'audit ne signale que la direction
inverse — le contrat déclare, l'oracle l'ignore ou le contredit.
"""
from __future__ import annotations

import json
from pathlib import Path

import yaml

# Les trois champs de BUDGET. `entry` en est exclu volontairement : c'est le seul champ du
# bloc qui ait un lecteur, et le compter comme budget ferait de tout jeu câblé un faux positif.
BUDGET_FIELDS = ("trials", "max_ticks", "trial_timeout_ms")

ETAT_CONTRAT_IGNORE = "CONTRAT_IGNORE"
ETAT_DIVERGENT = "DIVERGENT"
ETAT_NON_EVALUABLE = "NON_EVALUABLE"


def _budget(bloc: object) -> dict:
    """Sous-ensemble BUDGET d'un bloc `solvability`, valeurs non nulles seulement."""
    if not isinstance(bloc, dict):
        return {}
    return {k: bloc[k] for k in BUDGET_FIELDS if bloc.get(k) is not None}


def audit_solvability_budgets(repo_root: Path | str) -> list[dict]:
    """Anomalies budget contrat<->oracles.json. Liste VIDE = parc cohérent.

    Best-effort STRICT (même discipline que `registryDivergences`) : un fichier illisible
    devient un état NOMMÉ `NON_EVALUABLE`, jamais une exception qui interrompt l'audit —
    un auditeur qui casse sur une donnée cassée n'audite plus rien.
    """
    root = Path(repo_root)
    games = root / "GAMES"
    if not games.is_dir():
        return []

    oracles_path = root / "forge" / "oracles.json"
    oracles: dict | None
    try:
        oracles = json.loads(oracles_path.read_text(encoding="utf-8"))
        if not isinstance(oracles, dict):
            oracles = None
    except (OSError, ValueError):
        oracles = None

    anomalies: list[dict] = []
    for game_dir in sorted(p for p in games.iterdir() if p.is_dir()):
        contrat_path = game_dir / "00_CHARTER" / "game_contract.yaml"
        if not contrat_path.is_file():
            continue
        try:
            contrat = yaml.safe_load(contrat_path.read_text(encoding="utf-8")) or {}
        except (OSError, yaml.YAMLError) as exc:
            anomalies.append({
                "jeu": game_dir.name, "etat": ETAT_NON_EVALUABLE,
                "raison": f"contrat illisible : {exc.__class__.__name__}",
            })
            continue
        proof = contrat.get("proof") if isinstance(contrat, dict) else None
        declare = _budget((proof or {}).get("solvability") if isinstance(proof, dict) else None)
        if not declare:
            # Rien de déclaré au contrat : hors périmètre, y compris le cas `oracles.json`
            # seul (régime normal d'un jeu sans descripteur `proof`).
            continue

        if oracles is None:
            anomalies.append({
                "jeu": game_dir.name, "etat": ETAT_NON_EVALUABLE,
                "raison": f"{oracles_path.name} absent ou illisible", "contrat": declare,
            })
            continue

        entree = oracles.get(game_dir.name)
        effectif = _budget((entree or {}).get("solvability") if isinstance(entree, dict) else None)

        if not effectif:
            anomalies.append({
                "jeu": game_dir.name, "etat": ETAT_CONTRAT_IGNORE,
                "contrat": declare, "oracles_json": {},
                "raison": "le contrat declare un budget, `oracles.json` n'en porte aucun "
                          "— les valeurs PAR DEFAUT s'appliquent, en silence",
            })
            continue

        divergents = sorted(k for k in declare if k in effectif and declare[k] != effectif[k])
        if divergents:
            anomalies.append({
                "jeu": game_dir.name, "etat": ETAT_DIVERGENT,
                "contrat": declare, "oracles_json": effectif,
                "champs_divergents": divergents,
                "raison": "deux declarations se contredisent — `oracles.json` fait autorite",
            })
    return anomalies


def main(argv: list[str] | None = None) -> int:
    """Mode machine-a-machine : `python -m forge.solvability_budget_audit <repo> --json`.

    Même pont que `auditContractSync` (`studio_selfaudit.mjs`) : aucun parseur YAML n'existe
    côté Node dans ce dépôt, la lecture des contrats se fait donc en Python et le résultat
    voyage en JSON.
    """
    import sys

    args = list(sys.argv[1:] if argv is None else argv)
    repo = args[0] if args else "."
    sys.stdout.reconfigure(encoding="utf-8")
    print(json.dumps({"anomalies": audit_solvability_budgets(repo)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":  # pragma: no cover - point d'entrée CLI
    raise SystemExit(main())
