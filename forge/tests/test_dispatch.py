"""Oracle du dispatch gouverné Forge.

`prepare_dispatch` charge le contrat d'une étape, le valide, fabrique le payload
borné et TRACE un enregistrement d'audit — sans jamais spawner. `plan_chain`
fait le dry-run de toute la chaîne (preuve de câblage bout-en-bout).
"""
import json
from pathlib import Path

import pytest

import pytest

from forge.dispatch import (
    DEDICATED_PROFILE_STEPS,
    DETERMINISTIC,
    ORDER,
    PROFILES,
    order_for_profile,
    plan_chain,
    prepare_dispatch,
)


def test_order_covers_the_agent_steps():
    assert len(ORDER) == 13
    assert set(DETERMINISTIC).issubset(set(ORDER))


# --- profils de chaîne (full / patch / review) --------------------------------

def test_profiles_are_subsets_of_order_or_explicitly_dedicated():
    """Un profil référence soit une étape de ORDER (chaîne canonique "full"), soit une
    étape listée dans DEDICATED_PROFILE_STEPS (hors ORDER par décision explicite, ex.
    s2.5-artbible — jamais dans "full", cf. commentaire dispatch.py). Aucune autre
    étape "mystère" : un typo dans un profil doit toujours être détecté."""
    allowed = set(ORDER) | set(DEDICATED_PROFILE_STEPS)
    for name, steps in PROFILES.items():
        assert set(steps).issubset(allowed), f"profil {name} référence une étape hors ORDER/DEDICATED_PROFILE_STEPS"


def test_dedicated_steps_never_leak_into_full():
    """Une étape dédiée (hors ORDER) ne doit JAMAIS se retrouver dans "full" — sinon
    la distinction "profil dédié" vs "chaîne canonique" n'a plus de sens (régression
    du 2026-07-14 : s2.5-artbible câblé dans un profil dédié `artbible`, PAS dans full)."""
    assert set(DEDICATED_PROFILE_STEPS).isdisjoint(set(ORDER))
    assert set(DEDICATED_PROFILE_STEPS).isdisjoint(set(order_for_profile("full")))


def test_artbible_profile_is_dedicated_and_standalone():
    assert order_for_profile("artbible") == ["s2.5-artbible"]
    assert "s2.5-artbible" not in order_for_profile("full")


def test_patch_profile_is_the_short_fix_chain():
    assert order_for_profile("patch") == [
        "s9-build", "s10a-oracle-code", "s11-redteam-code", "s12-verdict",
    ]


def test_micro_profile_is_proportional_to_trivial_tasks():
    """#4a : profil micro pour un one-liner — pas de red-team ni de design."""
    assert order_for_profile("micro") == ["s9-build", "s10a-oracle-code", "s12-verdict"]
    assert "s6-redteam-plan" not in order_for_profile("micro")


def test_full_profile_is_the_whole_chain():
    assert order_for_profile("full") == list(ORDER)


def test_unknown_profile_raises():
    with pytest.raises(ValueError):
        order_for_profile("mysteryyy")


def test_increment_profile_skips_s0_s1_s2_but_keeps_archi_and_wiremap():
    """Ratifié Pierre 2026-07-19 (FORGE_PLAN_PROPOSAL.md §5 R1) : un incrément sur un
    projet dont le corpus de bibles fait déjà foi saute charter/prisme/world-scan, mais
    REFAIT archi/wiremap (contrairement à `patch`) — c'est justement ce qu'un moteur
    multi-incréments doit re-prouver à chaque incrément (deps_interdites, wiremap à jour)."""
    steps = order_for_profile("increment")
    assert steps == [
        "s3-decompo", "s4-archi", "s5-wiremap", "s6-redteam-plan", "s9-build",
        "s10a-oracle-code", "s10b-oracle-archi", "s10c-oracle-wiremap",
        "s11-redteam-code", "s12-verdict",
    ]
    assert "s0-contrat" not in steps and "s1-prisme" not in steps and "s2-worldscan" not in steps
    assert "s10b-oracle-archi" in steps and "s10c-oracle-wiremap" in steps


def test_plan_chain_patch_profile_plans_only_its_steps(tmp_path):
    plan = plan_chain(run_id="p", profile="patch", audit_path=tmp_path / "a.jsonl")
    assert [p.etape for p in plan] == order_for_profile("patch")
    for p in plan:
        assert p.model


def test_plan_chain_artbible_profile_resolves_a_real_runtime(tmp_path):
    """Preuve de câblage bout-en-bout du profil dédié artbible (2026-07-14) : le
    contrat charge, se valide, et le registry résout un runtime réel (pas un stub)."""
    plan = plan_chain(run_id="ab", profile="artbible", audit_path=tmp_path / "a.jsonl")
    assert [p.etape for p in plan] == ["s2.5-artbible"]
    assert plan[0].model == "claude-opus-4-8"
    assert plan[0].provider == "claude-local"


def test_prepare_dispatch_returns_payload_and_audits(tmp_path):
    audit = tmp_path / "audit.jsonl"
    payload = prepare_dispatch("s4-archi", run_id="t1", audit_path=audit)
    assert payload.model  # runtime résolu
    line = audit.read_text(encoding="utf-8").strip()
    rec = json.loads(line)
    assert rec["etape"] == "s4-archi"
    assert rec["run_id"] == "t1"
    assert rec["model"] == payload.model
    assert rec["capability_role"] == "architect"


def test_plan_chain_dryrun_covers_whole_chain(tmp_path):
    audit = tmp_path / "audit.jsonl"
    plan = plan_chain(run_id="dry", audit_path=audit)
    assert len(plan) == 13
    for p in plan:
        assert p.model  # chaque étape a un runtime résolu
    # audit : une ligne par étape
    assert len(audit.read_text(encoding="utf-8").strip().splitlines()) == 13


def test_deterministic_steps_plan_as_non_llm(tmp_path):
    audit = tmp_path / "audit.jsonl"
    plan = {p.etape: p for p in plan_chain(run_id="d", audit_path=audit)}
    for cid in DETERMINISTIC:
        assert plan[cid].model == "non-llm"


def test_unknown_step_raises(tmp_path):
    with pytest.raises(FileNotFoundError):
        prepare_dispatch("s99-inexistant", run_id="x", audit_path=tmp_path / "a.jsonl")


# --- model_executed (0.5.d) : passe-plat vers le Context Manifest, jamais l'audit --

def test_prepare_dispatch_threads_model_executed_into_context_manifest(tmp_path):
    """`model_executed` n'affecte QUE la ligne Context Manifest `kind: dispatch` —
    jamais la ligne d'audit (`DispatchRecord`, INTERDIT de toucher par la mission),
    jamais `payload.model`."""
    from forge import context_manifest as cm
    audit = tmp_path / "audit.jsonl"
    run_dir = tmp_path / "run"
    payload = prepare_dispatch(
        "s9-build", run_id="esc-run", audit_path=audit, run_dir=run_dir,
        model_executed="claude-opus-4-8",
    )
    assert payload.model != "claude-opus-4-8"  # le contrat, inchangé

    audit_rec = json.loads(audit.read_text(encoding="utf-8").strip())
    assert audit_rec["model"] == payload.model  # ligne d'audit : STRICTEMENT inchangée

    manifest_path = cm.manifest_path(run_dir, "s9-build")
    manifest_rec = json.loads(manifest_path.read_text(encoding="utf-8").strip())
    assert manifest_rec["model"] == payload.model
    assert manifest_rec["model_executed"] == "claude-opus-4-8"


def test_prepare_dispatch_without_model_executed_leaves_manifest_unambiguous(tmp_path):
    """NÉGATIF : sans override, `model_executed` doit égaler `model` — si le champ
    restait absent ou None par défaut, un lecteur ne pourrait pas trancher entre
    'pas mesuré' et 'pas d'escalade' ; cette assertion échouerait si le repli
    `model_executed or payload.model` disparaissait."""
    from forge import context_manifest as cm
    audit = tmp_path / "audit.jsonl"
    run_dir = tmp_path / "run"
    payload = prepare_dispatch("s4-archi", run_id="no-esc-run", audit_path=audit, run_dir=run_dir)
    manifest_rec = json.loads(
        cm.manifest_path(run_dir, "s4-archi").read_text(encoding="utf-8").strip()
    )
    assert manifest_rec["model_executed"] == manifest_rec["model"] == payload.model


# --- R2 (audit branchements 2026-07-24) : marqueur injecté par la porte -----------

def test_prepare_dispatch_injecte_le_marqueur_forge_dispatch(tmp_path):
    """La porte (prepare_dispatch) connaît etape ET run_id : le prompt qu'elle
    produit doit systématiquement porter le marqueur exact attendu par le hook,
    plus besoin que l'orchestrateur l'appose à la main."""
    from forge.hook_guard import MARKER, marker_key
    audit = tmp_path / "audit.jsonl"
    payload = prepare_dispatch("s4-archi", run_id="run-int-1", audit_path=audit)
    matches = MARKER.findall(payload.prompt)
    assert len(matches) == 1, f"un seul marqueur attendu, trouvé: {matches}"
    # Forme 2-champs rendue par la porte => attempt normalisé à 0 par `marker_key`.
    assert marker_key(payload.prompt) == ("s4-archi", "run-int-1", 0)


def test_hook_autorise_un_prompt_rendu_par_la_porte_avec_son_audit(tmp_path):
    """Comportement APRÈS le correctif : un prompt réellement produit par
    prepare_dispatch (donc avec sa ligne d'audit signée correspondante) passe le
    hook — la porte s'auto-atteste correctement de bout en bout."""
    from forge.hook_guard import hook_decision
    audit = tmp_path / "audit.jsonl"
    key = tmp_path / "audit.key"
    payload = prepare_dispatch("s4-archi", run_id="run-int-2",
                              audit_path=audit)
    code, reason = hook_decision("Task", payload.prompt, audit_path=audit)
    assert code == 0, reason


def test_hook_refuse_un_marqueur_sans_ligne_d_audit_correspondante(tmp_path):
    """Comportement AVANT/attaque : un prompt qui PORTE le marqueur (etape/run_id
    plausibles) mais dont AUCUN dispatch validé n'a été enregistré (audit vide/
    absent) reste refusé — le marqueur seul ne suffit jamais, il faut la preuve
    d'audit signée que seule la porte produit."""
    from forge.hook_guard import MARKER, hook_decision
    audit = tmp_path / "audit.jsonl"
    audit.write_text("", encoding="utf-8")  # aucun dispatch validé enregistré
    fake_prompt = "## RÔLE\nun faux prompt\n\nFORGE_DISPATCH:s4-archi:run-jamais-audite"
    assert MARKER.search(fake_prompt)  # le marqueur est bien présent/valide
    code, reason = hook_decision("Task", fake_prompt, audit_path=audit)
    assert code == 2, reason


# --- profil standard_godot (jumeau Godot de `standard`, Pierre 2026-07-28) -----

def test_standard_godot_profile_is_exactly_the_five_expected_steps():
    assert order_for_profile("standard_godot") == [
        "s9-build-godot-standard",
        "s10a-oracle-code",
        "s10s-oracle-standard",
        "s11-redteam-code",
        "s12-verdict",
    ]


def test_standard_profile_is_unchanged_by_the_godot_addition():
    """Non-régression : le profil `standard` (web/JS) rend toujours exactement ce
    qu'il rendait avant l'ajout du jumeau Godot."""
    assert order_for_profile("standard") == [
        "s9-build-standard",
        "s10a-oracle-code",
        "s10s-oracle-standard",
        "s11-redteam-code",
        "s12-verdict",
    ]


def test_s9_build_godot_is_historical_and_belongs_to_no_profile():
    """`s9-build-godot` (étape 0, brique M01, contrat du 2026-07-21) est une trace
    historique figée : il ne doit apparaître dans AUCUN profil, ni `standard_godot`
    ni `full` ni aucun autre — sinon un forgeron Snake recevrait par erreur l'ordre
    de produire grid_nav (cf. commentaire du contrat s9-build-godot-standard.yaml)."""
    for name, steps in PROFILES.items():
        assert "s9-build-godot" not in steps, f"s9-build-godot fuite dans le profil {name}"
    assert "s9-build-godot" not in ORDER
    assert "s9-build-godot" not in DEDICATED_PROFILE_STEPS


def test_plan_chain_standard_godot_profile_resolves_real_runtimes(tmp_path):
    plan = plan_chain(run_id="sg", profile="standard_godot", audit_path=tmp_path / "a.jsonl")
    assert [p.etape for p in plan] == order_for_profile("standard_godot")
    for p in plan:
        assert p.model


def test_prepare_dispatch_resolves_each_standard_godot_step(tmp_path):
    """Chaque étape du profil est effectivement dispatchable — pas seulement
    déclarée dans PROFILES (le défaut « profil déclaré, jamais atteignable »
    déjà rencontré une fois pour `standard`, cf. test_standard_step_wiring.py)."""
    audit = tmp_path / "audit.jsonl"
    for etape in order_for_profile("standard_godot"):
        payload = prepare_dispatch(etape, run_id="t-standard-godot", profile="standard_godot",
                                   audit_path=audit)
        assert payload.model


def test_s9_build_godot_standard_resolves_the_game_forger_role(tmp_path):
    """Le builder Godot du curriculum résout bien son rôle `game_forger` via
    roles.yaml — même capability_role que son jumeau web s9-build-standard."""
    from forge.contract import load_contract

    contract = load_contract("s9-build-godot-standard")
    assert contract["capability_role"] == "game_forger"
    payload = prepare_dispatch("s9-build-godot-standard", run_id="t-godot",
                               audit_path=tmp_path / "audit.jsonl")
    assert payload.model
    assert payload.model != "non-llm"


def test_dispatch_module_ne_spawn_pas():
    """Le dispatch gouverné TRACE et prépare — le spawn appartient au skill /forge."""
    source = Path(__file__).resolve().parents[1].joinpath("dispatch.py").read_text(encoding="utf-8")
    for interdit in ("subprocess", "Popen", "os.system"):
        assert interdit not in source, f"spawn interdit détecté : {interdit}"
