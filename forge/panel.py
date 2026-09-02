"""panel.py — panel Prisme (Tier 2 #6, WFL-02) : N lenses isolées + recombinaison
mécanique, promu en mécanisme RÉEL invocable (WFL-02 labo n'était, comme WFL-01,
jamais branché sur un exécuteur réel — seulement des artefacts produits à la main).

Au lieu d'un seul agent produisant l'artefact de l'étape s1-prisme, N lenses
(des points de vue distincts : CEO, Game Designer, Front, Back, Joueur) l'écrivent
chacun EN ISOLATION (ne voient que le charter, JAMAIS le contrôle ni les autres
lenses — c'est la discipline "contexte vierge" documentée par WFL-02). Le contrôle
(le producteur normal du contrat) et les N lenses passent tous par la même garde
structurelle (``check_prisme.mjs``), puis ``merge_prisme.mjs`` (Node, déterministe,
zéro LLM-arbitre) recombine leur UNION contre le contrôle. La sortie de l'étape est
le document recombiné.

Coût assumé, pas caché : N+1 appels LLM au lieu d'1, SEULEMENT pour l'étape
s1-prisme du profil ``full`` — jamais sur le chemin s9-build/patch quotidien.
"""
from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

PRISME_DIR = Path(__file__).resolve().parent / "prisme"
CHECK_PRISME = PRISME_DIR / "check_prisme.mjs"
MERGE_PRISME = PRISME_DIR / "merge_prisme.mjs"

# Les 5 lenses WFL-02 (docs/forge/PRISM_SCOPING.md) — chaque persona ne voit QUE le
# charter, jamais le contrôle ni les autres lenses (contexte vierge par construction :
# `claude_call` reçoit un prompt autonome, aucune session partagée).
LENSES = ("ceo", "game_designer", "front", "back", "joueur")

_LENS_INSTRUCTIONS = {
    "ceo": "Point de vue CEO/produit : valeur business, positionnement, quel problème "
           "joueur ça résout — pas les détails techniques.",
    "game_designer": "Point de vue Game Designer : la boucle de jeu, la courbe de "
                      "difficulté, ce qui rend l'expérience satisfaisante.",
    "front": "Point de vue développeur Front/rendu : ce que l'écran affiche, les "
              "retours visuels, les états d'interface (overlay, HUD, restart).",
    "back": "Point de vue développeur Back/logique : l'état du jeu, les invariants, "
             "les conditions de victoire/défaite, le déterminisme.",
    "joueur": "Point de vue Joueur réel : ce qu'il ressent en jouant, ce qui le "
              "frustrerait ou le satisferait, en langage non technique.",
}


_FENCED_JSON = re.compile(r"```json\s*(.*?)```", re.S)


def extract_json_fence(text: str) -> str | None:
    """Retourne le texte VERBATIM (sans les balises ```json``` / ```) du DERNIER
    bloc fencé qui parse comme un objet JSON, ou None si aucun ne convient.

    Même règle que `run_real.select_artifact_payload` (dernier bloc dict valide
    du texte) — réimplémentée ici en local, déterministe, sans dépendance sur
    run_real (qui importe déjà ce module : un import inverse serait circulaire).
    Aucun jugement de schéma ici (pas de vérification `exigences` etc.) — c'est
    le rôle de `run_real._validate_prisme`, appelé une seule fois, en aval,
    quand `_materialize_artifact` traite la sortie fusionnée de l'étape.
    """
    blocks = _FENCED_JSON.findall(text or "")
    for raw in reversed(blocks):
        try:
            data = json.loads(raw)
        except ValueError:
            continue
        if isinstance(data, dict):
            return raw
    return None


def lens_prompt(lens: str, contract_prompt: str, charter_text: str) -> str:
    """Construit le prompt d'un lens : MÊME contrat que le contrôle, mais borné à
    UN SEUL angle de vue, et seul le charter est fourni (jamais le contrôle)."""
    if lens not in _LENS_INSTRUCTIONS:
        raise ValueError(f"lens inconnu: {lens!r} (attendu: {', '.join(LENSES)})")
    return (
        f"{contract_prompt}\n\n"
        f"## ANGLE DE VUE IMPOSÉ (panel Prisme, lens={lens})\n{_LENS_INSTRUCTIONS[lens]}\n"
        "Tu ne vois PAS le travail des autres lenses ni celui d'un éventuel contrôle — "
        "contexte vierge, n'essaie pas de le reconstituer.\n\n"
        f"## CHARTER (étape 0, seule source de vérité déjà validée)\n{charter_text}"
    )


def panel_prisme_executor(claude_call, charter_path: Path, run_dir: Path, lenses: tuple = LENSES):
    """Fabrique un executor(payload, decision, context) -> dict pour l'étape s1-prisme.

    ``claude_call(prompt, model) -> str | None`` est injecté (même canal que
    ``run_real.claude_executor`` — None = échec, jamais une exception qui remonte).
    """
    charter_text = Path(charter_path).read_text(encoding="utf-8")
    run_dir = Path(run_dir)
    run_dir.mkdir(parents=True, exist_ok=True)

    def executor(payload, decision, context) -> dict:
        control_out = claude_call(payload.prompt, payload.model)
        if control_out is None:
            return {"ok": False, "reason": "panel Prisme: le contrôle a échoué"}
        control_path = run_dir / "prisme_control.md"
        control_path.write_text(control_out, encoding="utf-8")

        lens_paths = []
        for lens in lenses:
            out = claude_call(lens_prompt(lens, payload.prompt, charter_text), payload.model)
            if out is None:
                continue  # un lens qui échoue = gap potentiel, pas un blocage total
            p = run_dir / f"prisme_lens_{lens}.md"
            p.write_text(out, encoding="utf-8")
            lens_paths.append(p)

        if not lens_paths:
            return {"ok": False, "reason": "panel Prisme: aucun lens n'a produit de sortie exploitable"}

        check = subprocess.run(
            ["node", str(CHECK_PRISME), str(control_path), *[str(p) for p in lens_paths]],
            capture_output=True, text=True, encoding="utf-8",
        )
        # La garde de forme est advisory ICI (elle ne bloque pas la fabrication du
        # document recombiné) — mais son verdict est TOUJOURS remonté, jamais tu.
        findings = [] if check.returncode == 0 else [check.stdout[-2000:]]

        merged = subprocess.run(
            ["node", str(MERGE_PRISME), str(charter_path), str(control_path),
             *[str(p) for p in lens_paths]],
            capture_output=True, text=True, encoding="utf-8",
        )
        if merged.returncode != 0:
            return {"ok": False, "reason": f"merge_prisme.mjs a échoué: {merged.stderr[-2000:]}"}

        # Matérialisation de prisme.json (FICHE 4, GO Pierre 2026-08-29) : merge_
        # prisme.mjs recombine la PROSE (product_snapshot, criteres_succes cités,
        # règles observables) — il ne touche JAMAIS au schéma `{"exigences": [...]}`
        # attendu de prisme.json (ancien format cible, WFL-02 ; le contrat réel
        # produit désormais un bloc ```json``` structuré, voir prisme.json
        # historiques dans EVIDENCE/runs/). Les lenses sont des points de vue
        # NARRATIFS uniquement (cf. lens_prompt) — le panel n'invente donc aucune
        # exigence : le bloc structuré du CONTRÔLE (seul artefact réel produit avec
        # le même contrat que la voie simple) est repris VERBATIM, tel quel, en
        # dernier bloc fencé de la sortie fusionnée. `run_real._materialize_
        # artifact` (même chemin de code que la voie simple, zéro nouveau writer)
        # retrouve ce bloc par sa propre règle "dernier ```json``` dict valide" et
        # le valide via `_validate_prisme` — AUCUNE duplication de schéma ici.
        #
        # Fail-closed : si le contrôle n'a produit aucun bloc ```json``` objet
        # exploitable, l'étape ÉCHOUE ici — jamais un run qui continue sans
        # artefact structuré sous panel (c'était le bug mesuré : prisme.json
        # jamais écrit, s3-decompo bloqué en aval).
        control_json = extract_json_fence(control_out)
        if control_json is None:
            return {"ok": False,
                    "reason": "panel Prisme: le contrôle n'a produit aucun bloc "
                              "```json``` exploitable (objet JSON valide attendu) — "
                              "prisme.json non matérialisable (aucun fichier écrit)"}

        fused_output = (
            merged.stdout.rstrip()
            + "\n\n## Artefact structuré (issu du contrôle, repris verbatim par le panel)\n\n"
            + "```json\n" + control_json.strip() + "\n```\n"
        )

        return {
            "ok": True,
            "output": fused_output,
            "blocked": bool(findings),
            "findings": findings,
        }

    return executor
