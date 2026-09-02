"""PreToolUse hook — CLASSIFICATION des spawns, MESURE PURE. Ne juge, ne bloque jamais.

§7.1-D' (GO Pierre 2026-08-14). Objet : répondre quantitativement à « quelle est la
NATURE de la population qui démarre », avant de dimensionner C (identité producteur)
puis B (prédicat par type). Ce hook ne participe à AUCUNE décision de juridiction.

POURQUOI ICI ET PAS SUR SubagentStart — mesuré, pas supposé (2026-08-14) :
`SubagentStart` ne transporte PAS la mission. Payload réel capturé :
  {agent_id, agent_type, cwd, hook_event_name, prompt_id, session_id, transcript_path}
La présence d'un marqueur Forge y est donc structurellement indétectable : une première
version de D, posée sur cet évènement, classait 100 % de la population `unknown`.
`PreToolUse` sur `Agent` est le SEUL point qui voit la mission ET le type ensemble
(`tool_input.prompt` + `tool_input.subagent_type`) — c'est là que la classification
est possible.

TROIS ÉTATS, JAMAIS DEUX — un marqueur absent et un prompt absent ne sont pas la même
information (doctrine du studio : NOT_MEASURED != absent) :
  YES     : prompt exploitable ET marqueur FORGE_DISPATCH présent
  NO      : prompt exploitable, marqueur absent
  UNKNOWN : aucun prompt exploitable dans le payload — le hook NE PEUT PAS conclure
Interdit : compter un UNKNOWN comme un NO. C'est exactement l'erreur que la version
SubagentStart aurait produite en silence.

FAIL-OPEN ABSOLU, plus strict encore que le hook PostToolUse jumeau : un PreToolUse
peut BLOQUER l'appel d'outil. Ce fichier ne doit donc JAMAIS écrire sur stdout, JAMAIS
écrire sur stderr, JAMAIS sortir avec un code non nul, quelle que soit l'anomalie
(stdin illisible, JSON malformé, disque plein, chemin invalide). Le prix d'une mesure
manquante est infiniment plus faible que celui d'un spawn refusé par erreur.

NE REMPLACE PAS `pretool_forge_guard.py` et n'interagit pas avec lui : les deux hooks
s'exécutent sur le même évènement, celui-ci n'écrit qu'un journal. Le prédicat de
juridiction (surface B) et l'identité de production (surface C) restent INCHANGÉS.

Journal : `lab/reports/spawn_classification.jsonl`, DISTINCT de
`lab/forge_evidence/dispatch_audit.jsonl` — ce dernier est un registre de preuve
opérationnelle, celui-ci un instrument de mesure. Ne pas les fusionner (la pollution
de l'audit par les suites de tests, 1 203 lignes mesurées le 2026-08-14, est
précisément le symptôme d'un registre qui mélange deux natures de preuve).
"""
import sys


def main() -> None:
    raw = sys.stdin.read()
    if not raw or not raw.strip():
        return

    import json
    data = json.loads(raw)
    if not isinstance(data, dict):
        return

    tool = data.get("tool_name") or data.get("tool") or ""
    if tool not in ("Task", "Agent"):
        return  # hors périmètre de mesure : aucun spawn

    ti = data.get("tool_input")
    if not isinstance(ti, dict):
        ti = {}

    # Le prompt est-il RÉELLEMENT présent ? Une clé absente et une clé vide se
    # traitent pareil ici : dans les deux cas il n'y a rien à inspecter.
    parts = [ti.get(k) for k in ("prompt", "description")]
    prompt = " ".join(str(p) for p in parts if isinstance(p, str) and p.strip())

    if not prompt:
        marker = "UNKNOWN"
        run_id = None
    elif "FORGE_DISPATCH" in prompt:
        marker = "YES"
        run_id = None
        # FORGE_DISPATCH:<etape>:<run_id>[:attempt] — extraction du seul marqueur,
        # jamais une donnée devinée ailleurs dans le prompt.
        import re
        m = re.search(r"FORGE_DISPATCH:([^\s:]+):([^\s:]+)", prompt)
        if m:
            run_id = m.group(2)
    else:
        marker = "NO"
        run_id = None

    import time
    from pathlib import Path

    record = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "tool": tool,
        "subagent_type": ti.get("subagent_type") or "<ABSENT>",
        "forge_marker": marker,
        "run_id": run_id,
        "prompt_chars": len(prompt),
        "session_id": data.get("session_id") or "",
    }

    repo_root = Path(__file__).resolve().parents[2]
    log = repo_root / "lab" / "reports" / "spawn_classification.jsonl"
    log.parent.mkdir(parents=True, exist_ok=True)
    with open(log, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")


if __name__ == "__main__":
    try:
        main()
    except BaseException:  # noqa: BLE001 — aucune sortie non nulle ne doit être possible
        pass
    sys.exit(0)
