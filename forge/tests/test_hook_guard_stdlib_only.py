"""Oracle : le GARDE de spawn s'importe et juge SANS dépendance tierce.

Pourquoi ce test existe (panne réelle, mesurée le 2026-07-24) : le garde
(`forge.hook_guard`, appelé par `.claude/hooks/pretool_forge_guard.py`) est
fail-CLOSED en périmètre Forge. Un ImportError dans sa chaîne d'import ne produit
donc PAS une panne visible mais un REFUS UNIVERSEL — le garde cesse de juger et
refuse tout spawn Forge, y compris parfaitement contractualisé :

    $ echo '{"tool_name":"Task","tool_input":{"prompt":"FORGE_DISPATCH:s9-build:x:9"}}' \
        | python .claude/hooks/pretool_forge_guard.py
    [forge-gate] garde indisponible (No module named 'yaml') -> refus fail-closed.

La chaîne fautive était `hook_guard` -> `forge.dispatch` -> `forge.contract` ->
`yaml`. Or `.venv312` (le seul interpréteur qui a PyYAML) n'existe PAS dans les
worktrees, c.-à-d. là où le travail Forge se fait. D'où l'extraction de la couche
audit dans `forge.audit` (stdlib-only).

Ces tests verrouillent l'invariant DANS LES DEUX SENS : la propriété statique
(aucun import tiers dans le module extrait) ET la propriété dynamique (le garde
juge correctement alors que `yaml` est rendu inimportable).
"""
import ast
import json
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
# Layout L1 : le paquet vit à la racine du Studio (`Studio/forge/`), plus sous `scripts/`.
SCRIPTS = REPO_ROOT
AUDIT_MODULE = SCRIPTS / "forge" / "audit.py"
GUARD_MODULE = SCRIPTS / "forge" / "hook_guard.py"

# Les seuls modules NON-stdlib que la chaîne du garde a le droit de toucher : eux-mêmes
# stdlib-only (vérifié par test_les_modules_internes_de_la_chaine_sont_stdlib_only).
ALLOWED_INTERNAL = {"forge", "forge.audit", "forge.verdict", "forge.hook_guard"}

# Rend `yaml` inimportable, quel que soit l'interpréteur — y compris le venv qui l'a.
# Le test mesure donc l'invariant lui-même, pas la configuration du poste.
_BLOCK_YAML = (
    "import sys\n"
    "class _NoYaml:\n"
    "    def find_spec(self, fullname, path=None, target=None):\n"
    "        if fullname == 'yaml' or fullname.startswith('yaml.'):\n"
    "            raise ImportError(\"No module named 'yaml'\")\n"
    "        return None\n"
    "sys.meta_path.insert(0, _NoYaml())\n"
    f"sys.path.insert(0, {str(SCRIPTS)!r})\n"
)


def _run(code: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, "-c", _BLOCK_YAML + code],
                          capture_output=True, text=True, timeout=60)


def _imported_roots(path: Path) -> set[str]:
    """Tous les modules importés par un fichier — niveau module ET dans les fonctions
    (un import paresseux casse tout autant, juste plus tard)."""
    tree = ast.parse(path.read_text(encoding="utf-8"), str(path))
    names: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            names.update(a.name for a in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module and node.level == 0:
            names.add(node.module)
    return names


# --- 1. propriété STATIQUE : aucun import tiers dans la chaîne du garde -------

@pytest.mark.parametrize("module", [AUDIT_MODULE, GUARD_MODULE])
def test_les_modules_internes_de_la_chaine_sont_stdlib_only(module):
    """`forge.audit` et `forge.hook_guard` n'importent QUE la stdlib (+ des modules
    internes eux-mêmes stdlib-only). Un `import yaml` réintroduit ici — ou un retour à
    `from forge.dispatch import ...` — rallume la panne de refus universel."""
    tiers = sorted(
        name for name in _imported_roots(module)
        if name.split(".")[0] not in sys.stdlib_module_names
        and name not in ALLOWED_INTERNAL
    )
    assert tiers == [], f"{module.name} importe du non-stdlib : {tiers}"


def test_le_garde_n_importe_jamais_forge_dispatch():
    """`forge.dispatch` (qui traîne `forge.contract` -> yaml) ne doit PAS être chargé
    par l'import du garde. Mesuré sur sys.modules réel, pas sur le source."""
    res = _run(
        "import forge.hook_guard, sys\n"
        "charges = sorted(m for m in sys.modules if m.startswith('forge'))\n"
        "print(':'.join(charges))\n"
    )
    assert res.returncode == 0, res.stderr
    charges = set(res.stdout.strip().split(":"))
    assert "forge.dispatch" not in charges and "forge.contract" not in charges, charges
    assert charges <= ALLOWED_INTERNAL, charges


# --- 2. propriété DYNAMIQUE : le garde JUGE, sans yaml ------------------------

def _decide(prompt: str, audit: Path) -> tuple[int, str]:
    res = _run(
        "import json, pathlib\n"
        "from forge.hook_guard import hook_decision\n"
        f"code, reason = hook_decision('Task', {prompt!r}, audit_path=pathlib.Path({str(audit)!r}))\n"
        "print(json.dumps([code, reason]))\n"
    )
    assert res.returncode == 0, res.stderr
    code, reason = json.loads(res.stdout.strip().splitlines()[-1])
    return code, reason


@pytest.fixture()
def audit_avec_dispatch(tmp_path):
    """Un audit contenant UN dispatch valide signé (s9-build / run-z / attempt 3).
    Écrit via `forge.audit` — donc par le même chemin que `prepare_dispatch`."""
    from forge.audit import EVENT_PREPARED, append_spawn_event
    audit = tmp_path / "audit.jsonl"
    assert append_spawn_event(EVENT_PREPARED, "s9-build", "run-z", 3, audit_path=audit)
    return audit


def test_sans_marqueur_le_garde_laisse_passer_sans_yaml(audit_avec_dispatch):
    code, reason = _decide("analyse ce fichier", audit_avec_dispatch)
    assert code == 0 and "non-forge" in reason


def test_sans_dispatch_le_garde_refuse_pour_la_BONNE_raison(audit_avec_dispatch):
    """La distinction qui EST le sujet : « aucun dispatch validé » (le garde a jugé)
    et non « garde indisponible » (le garde a planté)."""
    code, reason = _decide("FORGE_DISPATCH:s9-build:jamais-dispatche:9", audit_avec_dispatch)
    assert code == 2
    assert "aucun dispatch" in reason
    assert "indisponible" not in reason and "yaml" not in reason


def test_avec_dispatch_valide_le_garde_autorise_sans_yaml(audit_avec_dispatch):
    """Le cas qui prouve que le garde DISCRIMINE au lieu de tout refuser."""
    code, reason = _decide("go FORGE_DISPATCH:s9-build:run-z:3", audit_avec_dispatch)
    assert code == 0, reason
    assert "dispatch valid" in reason


# --- 3. rétro-compatibilité : les ré-exports de forge.dispatch tiennent -------

def test_forge_dispatch_reexporte_les_memes_objets():
    """Du code (driver.py) et des tests importent ces noms depuis `forge.dispatch`.
    L'extraction est un DÉPLACEMENT : ce doivent être les mêmes objets, pas des copies."""
    import forge.audit as a
    import forge.dispatch as d
    for nom in ("DEFAULT_AUDIT", "EVENT_PREPARED", "EVENT_AUTHORIZED", "EVENT_EXECUTED",
                "SPAWN_EVENTS", "DispatchRecord", "sign_audit_record", "verify_audit_line",
                "append_spawn_event", "spawn_proof", "_append_audit", "_iter_audit_records"):
        assert getattr(d, nom) is getattr(a, nom), nom


def test_surcharger_forge_dispatch_DEFAULT_AUDIT_redirige_toujours_l_ecriture(tmp_path,
                                                                             monkeypatch):
    """Point de surcharge HISTORIQUE conservé : réassigner `forge.dispatch.DEFAULT_AUDIT`
    redirige encore l'audit par défaut (des tests l'utilisent pour ne pas écrire dans
    `EVIDENCE/bundles/` réel). Vérifié APRÈS l'extraction du module."""
    import forge.audit as a
    import forge.dispatch as d
    audit = tmp_path / "redirige.jsonl"
    monkeypatch.setattr(d, "DEFAULT_AUDIT", audit)
    assert a.append_spawn_event(a.EVENT_EXECUTED, "s9-build", "run-r", 1)
    assert audit.exists() and json.loads(audit.read_text(encoding="utf-8"))["run_id"] == "run-r"
