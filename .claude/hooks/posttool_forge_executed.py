"""PostToolUse hook — écrit la PREUVE D'EXÉCUTION d'un spawn Forge (`spawn_executed`).

DISPATCH_SPAWN_AUTHORITY_V1 (Pierre, 2026-07-23) : « aujourd'hui prepare() écrit la
ligne d'audit et spawn() n'ajoute aucune preuve : on prouve une intention, pas une
exécution […] la preuve finale vient de `spawn_executed` ».

Ce hook est le pendant PostToolUse du garde PreToolUse : il se déclenche APRÈS le
retour de l'outil `Task`, donc à un point où le sous-agent a RÉELLEMENT tourné. Il
écrit une ligne d'audit signée `spawn_executed` corrélée au `spawn_prepared` par le
triplet `(etape, run_id, attempt)` du marqueur `FORGE_DISPATCH`.

Il couvre le CHEMIN A (orchestrateur interactif, spawn via l'outil Task). Le CHEMIN B
(headless `run_real.py` -> `claude -p`) ne passe par AUCUN hook Task : sa preuve est
écrite EN CODE par `forge.driver.ForgeDriver._record_spawn_executed`.

FAIL-OPEN ABSOLU — c'est la propriété la plus importante de ce fichier :
ce hook ENREGISTRE, il ne JUGE jamais et ne BLOQUE jamais rien. Toute exception,
stdin illisible, JSON malformé, import cassé, écriture impossible => exit 0 silencieux.
Un hook PostToolUse mal formé perturberait TOUS les appels d'outil de la session en
cours (d'autres agents d'outillage y sont spawnés) : le prix d'une preuve manquante
est infiniment plus faible que celui d'une session cassée.
"""
import sys


def main() -> None:
    try:
        raw = sys.stdin.read()
    except Exception:
        return
    if not raw or not raw.strip():
        return

    try:
        import json
        data = json.loads(raw)
    except Exception:
        return
    if not isinstance(data, dict):
        return

    try:
        tool = data.get("tool_name") or data.get("tool") or ""
        ti = data.get("tool_input")
        if not isinstance(ti, dict):
            ti = {}
        prompt = " ".join(str(ti.get(k, "")) for k in ("prompt", "description"))
    except Exception:
        return

    # Hors périmètre : autre outil, ou aucun marqueur Forge => rien à prouver, on sort.
    # Test de chaîne PUR, avant tout import fragile (même patron que le garde PreToolUse).
    if tool not in ("Task", "Agent") or "FORGE_DISPATCH" not in prompt:
        return

    try:
        from pathlib import Path
        repo_root = Path(__file__).resolve().parents[2]
        # V2 : le tronc est `<racine>/forge`, plus `<racine>/scripts/forge` (V1).
        sys.path.insert(0, str(repo_root))
        from forge.hook_guard import record_execution

        record_execution(prompt)  # best-effort, ne lève jamais, retour ignoré
    except Exception:
        return  # garde indisponible : preuve non écrite, session INTACTE


if __name__ == "__main__":
    try:
        main()
    except BaseException:  # noqa: BLE001 — aucune sortie non nulle ne doit être possible
        pass
    sys.exit(0)
