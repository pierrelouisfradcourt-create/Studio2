"""Câblage de la variante STANDARD dans la chaîne Forge (curriculum de jeux,
2026-07-22) : le builder `s9-build-standard` et son oracle `s10s-oracle-standard`
(six volets de `forge/standard_oracles.py`) sont dispatchables via un
profil DÉDIÉ `standard`, sans jamais modifier le profil canonique `full`.

Portée de ce fichier :
  1. `full` reste rigoureusement identique, étape pour étape (le danger principal
     signalé pour cette tâche : PROFILES["full"] = tuple(ORDER)).
  2. le profil `standard` contient exactement les 5 étapes attendues, dans l'ordre.
  3. `prepare_dispatch("s10s-oracle-standard", ...)` résout un runtime non-LLM.
  4. l'étape est reconnue comme déterministe.
  5. le nouveau bloc du driver (`ForgeDriver._run_standard_oracle`) rend FAIL sur
     une wiremap avec une ligne restée REQUIRED après build.
  6. ce même bloc ne lève JAMAIS d'exception quand wiremap.json est absent.
"""
import json

import pytest
import yaml

from forge.dispatch import (
    PROFILES,
    DEDICATED_DETERMINISTIC_STEPS,
    DETERMINISTIC,
    ORDER,
    is_deterministic_step,
    order_for_profile,
    prepare_dispatch,
)
from forge.driver import ForgeDriver

# --------------------------------------------------------------------------------------
# 1-4. Câblage dispatch.py
# --------------------------------------------------------------------------------------


def test_full_profile_is_untouched_by_the_standard_addition():
    """LE danger principal de cette tâche : PROFILES["full"] = tuple(ORDER) — ajouter
    une étape à ORDER changerait TOUS les runs existants. Comparaison étape par étape
    avec la liste attendue, écrite en dur (pas dérivée de ORDER, pour détecter une
    régression même si ORDER lui-même était altéré par erreur).

    CE TEST FIGE AUSSI LA SÉQUENCE, et il le revendique désormais (2026-08-19). Il ne
    le disait pas : sa prose ne parlait que d'étapes AJOUTÉES, alors que sa liste en dur
    contraint l'ORDRE. Un réordonnancement accidentel change tous les runs autant qu'un
    ajout — la protection est utile, elle manquait seulement de mandat écrit.

    L'ordre attendu a été MIS À JOUR une fois, le 2026-08-19, pour `s2-worldscan` avant
    `s1-prisme` (cf. `test_le_world_scan_precede_le_prisme_DELIBEREMENT`). Ce n'est pas
    une assertion pliée à un changement : c'était le rouge assumé de `d8a5464`, laissé
    ouvert quinze jours en attente d'une décision humaine explicite (GO Pierre).
    """
    assert order_for_profile("full") == [
        "s0-contrat",
        "s2-worldscan",   # AVANT le Prisme depuis d8a5464 — voir le test dédié ci-dessous
        "s1-prisme",
        "s3-decompo",
        "s4-archi",
        "s5-wiremap",
        "s6-redteam-plan",
        "s9-build",
        "s10a-oracle-code",
        "s10b-oracle-archi",
        "s10c-oracle-wiremap",
        "s11-redteam-code",
        "s12-verdict",
    ]
    assert len(ORDER) == 13  # inchangé (régression du test_dispatch.py existant)
    assert "s9-build-standard" not in order_for_profile("full")
    assert "s10s-oracle-standard" not in order_for_profile("full")


def test_le_world_scan_precede_le_prisme_DELIBEREMENT():
    """POURQUOI `s2-worldscan` s'exécute AVANT `s1-prisme`, alors que leurs noms disent
    l'inverse. Sans ce test, la prochaine lecture prendra l'ordre pour une coquille et
    le « corrigera » — les noms d'étape sont le seul indice visible, et ils mentent.

    DÉCISION : application de `FORGE_PRISME_V2` (ratifié Pierre 2026-08-03), livrée par
    `d8a5464`, ordre ratifié le 2026-08-19.

    CAUSE MESURÉE : le Prisme tournait en position 2, avec le seul `charter.yaml` pour
    `mandatory_read` — structurellement aveugle au monde. Run témoin : **0 occurrence**
    de menu / pause / audio / onboarding dans son artefact.

    LE DÉFAUT NE PLANTAIT PAS, IL DÉGRADAIT EN SILENCE — c'est pourquoi il a survécu.
    `_UPSTREAM_BY_STEP` n'est pas contraignant : `run_real.py` fait
    `continue  # absent/illisible : omis (jamais bloquant à ce niveau)`. Dans l'ancien
    ordre, l'artefact amont manquant était simplement OMIS du prompt du Prisme. Aucune
    erreur, aucun rouge : seulement une production plus pauvre.

    LES NOMS RESTENT `s1` / `s2`, VOLONTAIREMENT : ils vivent dans les contrats, les
    `state.json` archivés et les traces Observer. Les renommer rendrait l'historique
    illisible — on paie une numérotation trompeuse pour garder la traçabilité.
    """
    ordre = order_for_profile("full")
    assert ordre.index("s2-worldscan") < ordre.index("s1-prisme"), \
        "le Prisme redeviendrait aveugle au monde (0 occurrence mesurée avant d8a5464)"

    # Le POURQUOI mécanique : le Prisme CONSOMME l'artefact du World Scan. C'est cette
    # dépendance de données — pas les noms — qui impose l'ordre. Les deux copies de la
    # table sont vérifiées : une seule mise à jour laisserait l'autre imposer l'inverse.
    from forge.context_manifest import _UPSTREAM_BY_STEP as AMONT_MANIFESTE
    from forge.run_real import _UPSTREAM_BY_STEP as AMONT_EXECUTEUR
    for table in (AMONT_MANIFESTE, AMONT_EXECUTEUR):
        assert "artifacts/s2-worldscan.txt" in table["s1-prisme"], \
            "sans cette entrée, l'inversion ne sert plus à rien : le Prisme ne reçoit rien"


def test_standard_profile_is_exactly_the_five_expected_steps():
    assert order_for_profile("standard") == [
        "s9-build-standard",
        "s10a-oracle-code",
        "s10s-oracle-standard",
        "s11-redteam-code",
        "s12-verdict",
    ]


def test_every_builder_step_has_a_non_empty_tool_allowlist():
    """RÉGRESSION du bloqueur du 2026-07-22 : `s9-build-standard` manquait à
    `_STEP_TOOLS`, et `run_real.py` fait `_STEP_TOOLS.get(etape, ())` — un défaut
    SILENCIEUX (tuple vide => `--permission-mode manual`, aucun outil). L'agent
    partait sans Read, sans Write, sans Bash, et le run se vidait sans rien signaler.

    L'invariant porte sur la CLASSE, pas sur le seul cas connu : toute étape dont le
    métier est de POSER DES FICHIERS (préfixe `s9-build`) doit déclarer ses outils.
    Les étapes de plan (s0..s6) sont légitimement sans outil — leur artefact est
    matérialisé par l'exécuteur, l'agent n'écrit aucun fichier."""
    from forge.run_real import _STEP_TOOLS

    builders = [s for p in PROFILES.values() for s in p if s.startswith("s9-build")]
    assert builders, "aucune étape builder trouvée — le test ne mord plus"
    for etape in sorted(set(builders)):
        assert _STEP_TOOLS.get(etape), (
            f"{etape} n'a pas d'entrée _STEP_TOOLS : l'agent partirait SANS AUCUN "
            "outil (défaut silencieux du .get(etape, ()))")


def test_no_builder_gets_a_bare_bash_which_would_reopen_git():
    """`Bash` nu hériterait de l'allow-list locale (qui contient git add/commit/push) :
    le vecteur que _STEP_DISALLOWED existe pour fermer. Les motifs restent explicites."""
    from forge.run_real import _STEP_DISALLOWED, _STEP_TOOLS

    for etape, tools in _STEP_TOOLS.items():
        assert "Bash" not in tools, f"{etape} : Bash nu interdit, motif explicite requis"
    # et la fermeture git elle-même ne doit pas se faire retirer en passant
    assert "Bash(git:*)" in _STEP_DISALLOWED
    assert "PowerShell(git:*)" in _STEP_DISALLOWED


def test_s9_build_standard_allowlist_matches_what_was_measured():
    """Ce que la sonde réelle a MESURÉ le 2026-07-22 (flux stream-json + trace disque),
    et non ce qu'on suppose : node autorisé (il a écrit un fichier), Write autorisé
    (fichier créé), `git status` refusé (« Permission to use Bash ... has been denied »),
    `python -c` refusé (« This command requires approval »).

    Python est VOLONTAIREMENT absent bien que le contrat §5 l'autorise : le seul
    interpréteur portant la chaîne est le .venv312 du repo PRINCIPAL, alors que le
    subprocess tourne cwd=worktree. Le motif donnerait une impasse, pas une capacité.
    Les six oracles et le gate mutation sont exécutés par le DRIVER, pas par le builder."""
    from forge.run_real import _STEP_TOOLS

    tools = _STEP_TOOLS["s9-build-standard"]
    assert set(tools) == {"Write", "Edit", "Read", "Bash(node:*)"}
    assert not any("python" in t for t in tools), (
        "python non accordé : cf. .venv312 absent du worktree (mesuré)")


def test_cli_can_actually_reach_every_declared_profile():
    """Deuxième défaut silencieux de la même famille : `standard` existait dans
    PROFILES mais l'argparse le refusait — profil DÉCLARÉ, jamais ATTEIGNABLE. Les
    choix sont désormais dérivés de PROFILES ; ce test interdit qu'ils divergent."""
    from forge.run_real import build_parser

    action = next(a for a in build_parser()._actions if a.dest == "profile")
    assert set(action.choices) == set(PROFILES), (
        "les choix CLI ont divergé de PROFILES : un profil serait injoignable")
    assert "standard" in action.choices


def test_standard_builder_has_a_non_empty_default_task():
    """`task_by_step.get(etape, "")` : sans défaut, l'agent recevait une section
    « TÂCHE CONCRÈTE » VIDE — encore un vide silencieux, pas une erreur."""
    from forge.run_real import default_task_by_step

    task = default_task_by_step("pong", "GAMES/pong", profile="standard")
    assert task.get("s9-build-standard", "").strip()
    assert "wiremap.json" in task["s9-build-standard"]


def test_control_branch_is_closed_mechanically_not_by_polite_instruction():
    """Interdiction Pierre (2026-07-22) : le forgeur ne lit pas la branche de contrôle,
    sinon la comparaison ne mesure plus rien. MESURÉ le 2026-07-22 par sonde réelle :
    Read sur control/ => « File is in a directory that is denied by your permission
    settings », tandis que le contrôle positif (GAMES/pong/09_WIREMAP/wiremap.json)
    reste lisible — le deny mord sans être trop large."""
    from forge.run_real import _STEP_DISALLOWED

    assert "Read(lab/workflow_lab/**/control/**)" in _STEP_DISALLOWED


# --------------------------------------------------------------------------------------
# Boucle d'escalade : elle était INERTE pour le profil `standard` (garde en dur sur le
# nom `s9-build`). Un run partait donc en un seul coup, sans jamais pouvoir se corriger.
# --------------------------------------------------------------------------------------

_LEGACY_REPLAY = ("s9-build", "s10a-oracle-code", "s10b-oracle-archi", "s10c-oracle-wiremap")


@pytest.mark.parametrize("profile", ["full", "patch", "micro", "increment", "review", "artbible"])
def test_replay_list_is_bit_for_bit_unchanged_for_existing_profiles(tmp_path, profile):
    """La dérivation remplace une liste FIGÉE : elle ne doit RIEN changer aux profils
    déjà ratifiés. Comparaison à l'ancienne liste écrite en dur ici."""
    driver = ForgeDriver(
        "p", "r1", run_dir=tmp_path / profile, profile=profile,
        audit_path=tmp_path / "audit.jsonl", key_file=tmp_path / "k.key",
    )
    assert set(driver._steps_to_replay()) == {e for e in _LEGACY_REPLAY if e in driver.order}


def test_standard_profile_replays_its_builder_not_only_its_oracle(tmp_path):
    """Le défaut exact : l'ancienne liste ne croisait `standard` que sur
    `s10a-oracle-code` — on rejouait l'ORACLE sur un code INCHANGÉ, ce qui ne peut
    rien corriger. Le builder du profil doit être rejoué."""
    driver = ForgeDriver(
        "p", "r1", run_dir=tmp_path / "run", profile="standard",
        audit_path=tmp_path / "audit.jsonl", key_file=tmp_path / "k.key",
    )
    assert driver._builder_step() == "s9-build-standard"
    replay = driver._steps_to_replay()
    assert "s9-build-standard" in replay
    assert "s10s-oracle-standard" in replay


def test_s10s_fail_actually_triggers_a_rebuild_instead_of_being_ignored(tmp_path):
    """Bout en bout de la garde : un FAIL de l'oracle standard doit remettre le
    BUILDER à PENDING. Avant le correctif, `_maybe_escalate` sortait sur
    `"s9-build" not in self.order` et rendait False sans rien rejouer."""
    driver = ForgeDriver(
        "p", "r1", run_dir=tmp_path / "run", profile="standard",
        audit_path=tmp_path / "audit.jsonl", key_file=tmp_path / "k.key",
        builder_runs_path=tmp_path / "builder_runs.jsonl",
    )
    state = {
        "steps": {e: {"status": "OK", "attempts": 1, "detail": {}} for e in driver.order},
        "pool_attempts": 0,
    }
    state["steps"]["s10s-oracle-standard"]["status"] = "FAIL"
    state["steps"]["s9-build-standard"]["detail"] = {"model": "claude-haiku-4-5-20251001"}

    assert driver._maybe_escalate(state) is True, "la boucle est restée inerte"
    assert state["steps"]["s9-build-standard"]["status"] == "PENDING"
    assert state["steps"]["s10s-oracle-standard"]["status"] == "PENDING"


def test_s10b_archi_fail_declenche_desormais_l_escalade(tmp_path):
    """PRÉDICAT D'ESCALADE — s10b-archi EST une cause d'escalade depuis le 2026-08-12.

    MISE À JOUR RATIFIÉE PAR GO EXPLICITE DE PIERRE, 2026-08-12 (reconnexion du canal de
    causalité). Ce test encodait le comportement INVERSE, et son ancien nom l'affirmait :
    `..._still_does_not_trigger_escalation`. L'exclusion de s10b était délibérée ; elle ne
    l'est plus. Un test dont le NOM affirme le contraire de la règle en vigueur est pire
    qu'un test rouge — il a donc été renommé, pas seulement retourné.

    MOTIF MESURÉ : `s10b-oracle-archi` était calculé et stocké, puis exclu du prédicat par
    commentaire. Une faute d'architecture était donc VUE et SANS EFFET — l'un des points où
    l'audit d'autonomie a montré que la causalité se perdait.

    PORTÉE DE LA RATIFICATION : ce test seul, dans le cadre des quatre branchements du canal
    de causalité. Elle ne vaut pas autorisation générale de modifier `forge/tests/**`.

    CE QUI N'EST PAS TOUCHÉ, et reste vérifié ailleurs : `BLOCKED` demeure hors du prédicat
    (infra/hypothèse inconnue, re-builder n'y changerait rien), et `_steps_to_replay()` est
    inchangé — son test bit-à-bit reste vert."""
    driver = ForgeDriver(
        "p", "r1", run_dir=tmp_path / "run", profile="full",
        audit_path=tmp_path / "audit.jsonl", key_file=tmp_path / "k.key",
        builder_runs_path=tmp_path / "builder_runs.jsonl",
    )
    state = {
        "steps": {e: {"status": "OK", "attempts": 1, "detail": {}} for e in driver.order},
        "pool_attempts": 0,
    }
    state["steps"]["s10b-oracle-archi"]["status"] = "FAIL"
    state["steps"]["s9-build"]["detail"] = {"model": "claude-haiku-4-5-20251001"}

    assert driver._maybe_escalate(state) is True, "une faute d'architecture reste sans effet"
    assert state["steps"]["s9-build"]["status"] == "PENDING"
    assert state["steps"]["s10b-oracle-archi"]["status"] == "PENDING"


def test_prepare_dispatch_resolves_a_non_llm_runtime_for_s10s(tmp_path):
    payload = prepare_dispatch(
        "s10s-oracle-standard", run_id="t-standard", audit_path=tmp_path / "audit.jsonl"
    )
    assert payload.model == "non-llm"
    assert payload.provider == "forge"


def test_s10s_oracle_standard_is_recognized_as_deterministic():
    """`s10s-oracle-standard` est HORS de la chaîne canonique "full" (donc hors de
    `ORDER`) — l'invariant `DETERMINISTIC ⊆ ORDER` couvert par un test existant de
    test_dispatch.py (test_order_covers_the_agent_steps) reste donc intact : cette
    étape vit dans la catégorie SŒUR `DEDICATED_DETERMINISTIC_STEPS`. La reconnaissance
    « est-ce un oracle non-LLM ? » se fait par le prédicat commun `is_deterministic_step`,
    qui couvre les deux catégories — c'est LUI que le driver consulte (driver.py)."""
    assert "s10s-oracle-standard" not in DETERMINISTIC
    assert "s10s-oracle-standard" in DEDICATED_DETERMINISTIC_STEPS
    assert is_deterministic_step("s10s-oracle-standard") is True
    # non-régression : les 4 oracles canoniques restent reconnus comme avant.
    for canonical in DETERMINISTIC:
        assert is_deterministic_step(canonical) is True


def test_s9_build_standard_resolves_a_real_llm_runtime(tmp_path):
    """Contrôle positif : le builder STANDARD (LLM, capability_role game_forger)
    résout bien un vrai modèle, distinct du non-llm de son oracle jumeau."""
    payload = prepare_dispatch(
        "s9-build-standard", run_id="t-standard", audit_path=tmp_path / "audit.jsonl"
    )
    assert payload.model
    assert payload.model != "non-llm"


# --------------------------------------------------------------------------------------
# 5-6. Câblage driver.py — ForgeDriver._run_standard_oracle (s10s)
# --------------------------------------------------------------------------------------

_CORE_IDS = [
    "core.boot", "core.main_loop", "core.input", "core.game_state",
    "core.end_condition", "core.restart", "core.exit", "core.render",
    "core.audio", "core.error_handling",
]
_CORE_PROVIDES = {
    "core.boot": "game.boot", "core.main_loop": "game.loop", "core.input": "input.action",
    "core.game_state": "game.state", "core.end_condition": "game.end",
    "core.restart": "game.restart", "core.exit": "game.exit", "core.render": "render.frame",
    "core.audio": "audio.cue", "core.error_handling": "error.guard",
}


def _game_contract() -> dict:
    return {
        "schema_version": 1,
        "game_id": "teststd",
        "node": 1,
        "runtimes": ["rules"],
        "budget": {"reuses": [], "adds": []},
        "assets": {"plan": "cc0"},
    }


def _line(line_id: str, state: str) -> dict:
    return {
        "id": line_id,
        "source": "CORE",
        "source_role": None,
        "reference": None,
        "category": "system",
        "provides": [_CORE_PROVIDES[line_id]],
        "requires": [],
        "owner": True,
        "system_parent": "core_sys",
        "address": "05_SYSTEMS/core_sys/",
        "expected_proof": {"kind": "test", "statement": "peu importe pour ce test"},
        "state": state,
        "reason": None, "until": None, "decider": None, "write_order": None,
        "fichiers": [], "fonction": "", "preuve": "", "statut": "",
    }


def _wiremap_all_implemented_but_one(offending_id: str, offending_state: str) -> dict:
    """Un squelette qui satisferait TOUS les six oracles après build SAUF la
    contrainte `required_apres_build` sur `offending_id` — isole la cause du FAIL."""
    lines = [
        _line(lid, offending_state if lid == offending_id else "IMPLEMENTED")
        for lid in _CORE_IDS
    ]
    return {
        "schema_version": 2,
        "game_id": "teststd",
        "systems": [{"id": "core_sys", "category": "system", "allowed_deps": []}],
        "lines": lines,
        "discarded": [],
    }


def _write_game(tmp_path, wiremap: dict | None, contract: dict | None = "default"):
    game_dir = tmp_path / "game"
    charter = game_dir / "00_CHARTER"
    charter.mkdir(parents=True)
    if contract == "default":
        contract = _game_contract()
    if contract is not None:
        (charter / "game_contract.yaml").write_text(
            yaml.safe_dump(contract, allow_unicode=True), encoding="utf-8")
    if wiremap is not None:
        wiremap_dir = game_dir / "09_WIREMAP"
        wiremap_dir.mkdir(parents=True)
        (wiremap_dir / "wiremap.json").write_text(
            json.dumps(wiremap, ensure_ascii=False), encoding="utf-8")
    # dossier attendu par l'index (adresse déclarée par toutes les lignes CORE)
    (game_dir / "05_SYSTEMS" / "core_sys").mkdir(parents=True, exist_ok=True)
    return game_dir


def _write_catalog(tmp_path, brick_ids, name="catalog_auto.json", tier="validated"):
    """Catalogue de briques minimal (knowledge_base/catalog.json réel : entrées
    `entry_type: brick`, `brick_id`, `tier`, distinctes des entrées `asset`)."""
    path = tmp_path / name
    entries = [{"entry_type": "brick", "brick_id": bid, "tier": tier} for bid in brick_ids]
    path.write_text(json.dumps({"entries": entries}, ensure_ascii=False), encoding="utf-8")
    return path


def _driver(tmp_path, game_dir, catalog_path=None):
    return ForgeDriver(
        "teststd", "teststd-1",
        run_dir=tmp_path / "run",
        profile="standard",
        game_dir=game_dir,
        # catalogue vide par défaut (tests qui ne portent pas sur le budget) : un
        # catalogue vide + un instantané "same-as-catalog" (défaut de _run_s10s)
        # donne un différentiel vide, donc un budget mesuré et systématiquement propre.
        catalog_path=catalog_path or _write_catalog(tmp_path, []),
        audit_path=tmp_path / "audit.jsonl",
        key_file=tmp_path / "forge_test.key",
    )


def _run_s10s(driver, snapshot="same-as-catalog"):
    """`snapshot` : liste explicite de brick_id AU DÉMARRAGE du run, ou le sentinel
    "same-as-catalog" (aucun différentiel — budget mesuré et propre par construction,
    pour les tests qui ne portent pas sur le budget), ou `None` (instantané jamais
    pris => volet budget NON MESURÉ, cf. `_run_standard_oracle`)."""
    if snapshot == "same-as-catalog":
        catalog = driver._load_brick_catalog(driver.catalog_path)
        snapshot = sorted(catalog.keys()) if catalog is not None else None
    state = {
        "steps": {"s10s-oracle-standard": {"status": "PENDING", "attempts": 0}},
        "catalog_brick_ids_snapshot": snapshot,
    }
    driver._run_deterministic(state, "s10s-oracle-standard")
    return state["steps"]["s10s-oracle-standard"]


def test_required_line_after_build_fails_the_standard_oracle(tmp_path):
    """LE cas nominal d'échec demandé : une ligne restée REQUIRED après build."""
    wiremap = _wiremap_all_implemented_but_one("core.restart", "REQUIRED")
    game_dir = _write_game(tmp_path, wiremap)
    entry = _run_s10s(_driver(tmp_path, game_dir))

    assert entry["status"] == "FAIL"
    line_states = entry["detail"]["line_states"]
    assert line_states["passed"] is False
    assert "core.restart" in line_states["required_apres_build"]
    # isolation de la cause : les cinq autres volets restent verts sur ce squelette
    # (budget mesuré ET propre — catalogue vide, aucun différentiel, cf. _driver/_run_s10s).
    for oracle_name in ("contract_completeness", "budget", "placement", "index", "collisions"):
        assert entry["detail"][oracle_name]["passed"] is True, (
            f"{oracle_name} n'aurait pas dû échouer sur ce squelette de contrôle")
    assert entry["detail"]["budget"]["measured"] is True


def test_all_implemented_after_build_passes_the_standard_oracle(tmp_path):
    """Contrôle positif : le même squelette, sans ligne REQUIRED, verdit OK."""
    wiremap = _wiremap_all_implemented_but_one("core.restart", "IMPLEMENTED")
    game_dir = _write_game(tmp_path, wiremap)
    entry = _run_s10s(_driver(tmp_path, game_dir))

    assert entry["status"] == "OK"
    assert all(entry["detail"][k]["passed"] for k in (
        "contract_completeness", "budget", "line_states", "placement", "index", "collisions"))
    assert entry["detail"]["budget"]["measured"] is True


# --------------------------------------------------------------------------------------
# Budget (check_budget) : deposited_bricks DOIT venir du différentiel RÉEL du catalogue,
# jamais du budget déclaré lui-même — sinon la vérification est vraie par construction
# (tautologie déjà corrigée une fois, commit bb6ea2f). Correction demandée par le
# coordinateur après revue du premier câblage.
# --------------------------------------------------------------------------------------


def test_budget_bites_on_undeclared_brick_deposited_during_run(tmp_path):
    """LE test qui mord : le contrat ne déclare que `adds: [game_loop]`. Pendant le
    run, le catalogue gagne `collision_system` — une brique qu'AUCUNE ligne de
    contrat ne couvre. Le différentiel (catalogue après - instantané avant) doit le
    signaler nommément dans `hors_budget`, jamais un vert par tautologie."""
    wiremap = _wiremap_all_implemented_but_one("core.restart", "IMPLEMENTED")
    contract = _game_contract()
    contract["budget"] = {"reuses": [], "adds": ["game_loop"]}
    game_dir = _write_game(tmp_path, wiremap, contract=contract)

    # catalogue AU MOMENT DE L'ORACLE (après build) : game_loop préexistait,
    # collision_system est apparu PENDANT le run.
    catalog_path = _write_catalog(tmp_path, ["game_loop", "collision_system"])
    driver = _driver(tmp_path, game_dir, catalog_path=catalog_path)
    # instantané AU DÉMARRAGE du run : seul game_loop existait déjà.
    entry = _run_s10s(driver, snapshot=["game_loop"])

    assert entry["status"] == "FAIL"
    budget = entry["detail"]["budget"]
    assert budget["measured"] is True
    assert budget["passed"] is False
    assert budget["hors_budget"] == ["collision_system"]
    # les cinq autres volets restent propres : le FAIL est imputable au SEUL budget.
    for k in ("contract_completeness", "line_states", "placement", "index", "collisions"):
        assert entry["detail"][k]["passed"] is True


def test_budget_passes_when_catalog_differential_matches_declared_budget(tmp_path):
    """Contrôle positif jumeau : même scénario, mais `collision_system` est bien
    déclaré dans `adds` — le différentiel ne trouve alors rien hors budget."""
    wiremap = _wiremap_all_implemented_but_one("core.restart", "IMPLEMENTED")
    contract = _game_contract()
    contract["budget"] = {"reuses": [], "adds": ["collision_system"]}
    game_dir = _write_game(tmp_path, wiremap, contract=contract)

    catalog_path = _write_catalog(tmp_path, ["game_loop", "collision_system"])
    driver = _driver(tmp_path, game_dir, catalog_path=catalog_path)
    entry = _run_s10s(driver, snapshot=["game_loop"])

    assert entry["status"] == "OK"
    assert entry["detail"]["budget"]["measured"] is True
    assert entry["detail"]["budget"]["hors_budget"] == []


def test_budget_not_measured_when_snapshot_absent_blocks_the_whole_step(tmp_path):
    """Run démarré avant ce mécanisme (ou catalogue illisible au démarrage) : le
    différentiel est incalculable. NON MESURÉ, jamais vert par défaut — BLOCKED
    (hypothèse inconnue), pas un FAIL qui prétendrait avoir prouvé une violation."""
    wiremap = _wiremap_all_implemented_but_one("core.restart", "IMPLEMENTED")
    game_dir = _write_game(tmp_path, wiremap)
    catalog_path = _write_catalog(tmp_path, ["game_loop"])
    driver = _driver(tmp_path, game_dir, catalog_path=catalog_path)
    entry = _run_s10s(driver, snapshot=None)  # instantané jamais pris

    assert entry["status"] == "BLOCKED"
    assert entry["detail"]["budget"]["measured"] is False
    assert entry["detail"]["budget"]["passed"] is False  # jamais vert par défaut
    # les cinq autres volets, EUX, sont toujours calculés et exposés (transparence).
    for k in ("contract_completeness", "line_states", "placement", "index", "collisions"):
        assert entry["detail"][k]["passed"] is True


def test_budget_not_measured_when_catalog_unreadable_at_oracle_time_blocks(tmp_path):
    """Même discipline quand le catalogue lui-même est illisible AU MOMENT de
    l'oracle (pas seulement au démarrage) : jamais d'exception, jamais un vert."""
    wiremap = _wiremap_all_implemented_but_one("core.restart", "IMPLEMENTED")
    game_dir = _write_game(tmp_path, wiremap)
    driver = _driver(tmp_path, game_dir, catalog_path=tmp_path / "does_not_exist.json")
    entry = _run_s10s(driver, snapshot=[])  # peu importe : le catalogue est illisible

    assert entry["status"] == "BLOCKED"
    assert entry["detail"]["budget"]["measured"] is False


# --------------------------------------------------------------------------------------
# Priorité (arbitrage coordinateur) : UNE PREUVE D'ÉCHEC L'EMPORTE SUR UNE ABSENCE DE
# PREUVE. FAIL = « c'est faux, prouvé » (répare le JEU) ; BLOCKED = « je ne peux pas
# savoir » (répare l'INSTRUMENT). Un budget non mesurable ne doit JAMAIS masquer une
# violation prouvée ailleurs derrière un BLOCKED — sinon un problème d'instrumentation
# rend une vraie violation invisible.
# --------------------------------------------------------------------------------------


def test_priority_proven_violation_beats_unmeasurable_budget_fail(tmp_path):
    """Budget NON MESURABLE + une ligne restée REQUIRED après build => FAIL (pas
    BLOCKED) : la preuve d'échec (line_states) l'emporte. Les deux informations
    (la violation ET l'absence de mesure du budget) restent visibles dans le détail."""
    wiremap = _wiremap_all_implemented_but_one("core.restart", "REQUIRED")
    game_dir = _write_game(tmp_path, wiremap)
    driver = _driver(tmp_path, game_dir)  # catalogue vide par défaut
    entry = _run_s10s(driver, snapshot=None)  # instantané jamais pris => non mesurable

    assert entry["status"] == "FAIL"
    assert entry["detail"]["budget"]["measured"] is False
    assert "reason" in entry["detail"]["budget"]
    assert entry["detail"]["line_states"]["passed"] is False
    assert "core.restart" in entry["detail"]["line_states"]["required_apres_build"]


def test_priority_no_other_violation_and_unmeasurable_budget_blocks(tmp_path):
    """Contrôle jumeau : budget NON MESURABLE mais les cinq autres volets verts =>
    BLOCKED — le seul cas où on ne sait vraiment rien (répare l'INSTRUMENT, pas le jeu)."""
    wiremap = _wiremap_all_implemented_but_one("core.restart", "IMPLEMENTED")
    game_dir = _write_game(tmp_path, wiremap)
    driver = _driver(tmp_path, game_dir)
    entry = _run_s10s(driver, snapshot=None)

    assert entry["status"] == "BLOCKED"
    assert entry["detail"]["budget"]["measured"] is False
    assert "reason" in entry["detail"]["budget"]
    for k in ("contract_completeness", "line_states", "placement", "index", "collisions"):
        assert entry["detail"][k]["passed"] is True


def test_load_state_captures_catalog_snapshot_on_run_creation(tmp_path):
    """Le mécanisme d'instantané lui-même (pas seulement sa consommation par
    l'oracle) : `_load_state` capture les `brick_id` du catalogue à la création
    d'un run neuf, et les stocke dans `state.json` (state.get, mécanisme d'état
    déjà en place)."""
    catalog_path = _write_catalog(tmp_path, ["b2", "b1"])  # ordre volontairement inversé
    driver = ForgeDriver(
        "teststd", "r1", run_dir=tmp_path / "run", profile="standard",
        catalog_path=catalog_path,
        audit_path=tmp_path / "audit.jsonl", key_file=tmp_path / "forge_test.key",
    )
    state, refus = driver._load_state()
    assert refus == ""
    assert state["catalog_brick_ids_snapshot"] == ["b1", "b2"]  # trié, déterministe


def test_load_state_snapshot_is_none_when_catalog_unreadable_at_run_creation(tmp_path):
    """Catalogue illisible dès la création du run : l'instantané est None (pas une
    liste vide qui se ferait passer pour « catalogue vide constaté »)."""
    driver = ForgeDriver(
        "teststd", "r1", run_dir=tmp_path / "run", profile="standard",
        catalog_path=tmp_path / "does_not_exist.json",
        audit_path=tmp_path / "audit.jsonl", key_file=tmp_path / "forge_test.key",
    )
    state, refus = driver._load_state()
    assert refus == ""
    assert state["catalog_brick_ids_snapshot"] is None


def test_load_state_snapshot_never_recaptured_on_resume(tmp_path):
    """L'instantané est pris UNE FOIS, au démarrage — une reprise (state.json déjà
    présent) ne le recalcule JAMAIS, même si le catalogue a changé entre-temps."""
    catalog_path = _write_catalog(tmp_path, ["b1"])
    run_dir = tmp_path / "run"
    driver1 = ForgeDriver(
        "teststd", "r1", run_dir=run_dir, profile="standard",
        catalog_path=catalog_path,
        audit_path=tmp_path / "audit.jsonl", key_file=tmp_path / "forge_test.key",
    )
    state1, _ = driver1._load_state()
    driver1._save(state1)
    assert state1["catalog_brick_ids_snapshot"] == ["b1"]

    # le catalogue grossit APRÈS la création du run (comme un vrai build qui dépose
    # une brique) — une reprise ne doit PAS re-capturer un nouvel instantané.
    _write_catalog(tmp_path, ["b1", "b2"], name=catalog_path.name)
    driver2 = ForgeDriver(
        "teststd", "r1", run_dir=run_dir, profile="standard",
        catalog_path=catalog_path,
        audit_path=tmp_path / "audit.jsonl", key_file=tmp_path / "forge_test.key",
    )
    state2, refus = driver2._load_state()
    assert refus == ""
    assert state2["catalog_brick_ids_snapshot"] == ["b1"]  # inchangé, pas recalculé


def test_missing_wiremap_never_raises_and_blocks_honestly(tmp_path):
    """Le pire cas immédiat : 09_WIREMAP/wiremap.json absent du jeu courant. Le bloc
    driver ne doit JAMAIS lever — reçu BLOCKED motivé (hypothèse inconnue)."""
    game_dir = _write_game(tmp_path, wiremap=None)  # pas de 09_WIREMAP/ du tout
    entry = _run_s10s(_driver(tmp_path, game_dir))  # ne doit pas lever

    assert entry["status"] == "BLOCKED"
    assert any("wiremap.json" in m for m in entry["detail"]["missing"])


def test_missing_game_contract_never_raises_and_blocks_honestly(tmp_path):
    """Même discipline côté contrat de jeu absent."""
    wiremap = _wiremap_all_implemented_but_one("core.restart", "IMPLEMENTED")
    game_dir = _write_game(tmp_path, wiremap, contract=None)
    entry = _run_s10s(_driver(tmp_path, game_dir))

    assert entry["status"] == "BLOCKED"
    assert any("game_contract.yaml" in m for m in entry["detail"]["missing"])


def test_malformed_wiremap_json_never_raises(tmp_path):
    """JSON illisible — même discipline que check_architecture (F2b)."""
    game_dir = _write_game(tmp_path, wiremap=None)
    (game_dir / "09_WIREMAP").mkdir(parents=True, exist_ok=True)
    (game_dir / "09_WIREMAP" / "wiremap.json").write_text("{ceci n'est pas du JSON", encoding="utf-8")
    entry = _run_s10s(_driver(tmp_path, game_dir))

    assert entry["status"] == "BLOCKED"
    assert any("wiremap.json" in m for m in entry["detail"]["missing"])


def test_malformed_catalog_json_never_raises(tmp_path):
    """Catalogue de briques au JSON cassé — la docstring de `_load_brick_catalog`
    promet « mal formé => None » (volet budget NON MESURÉ). Le code n'attrapait que
    `OSError` : un catalogue corrompu FAISAIT LEVER l'oracle de budget au lieu de le
    déclarer non mesuré. Même discipline que le wiremap illisible ci-dessus."""
    game_dir = _write_game(tmp_path, wiremap=None)
    bad_catalog = tmp_path / "catalog.json"
    bad_catalog.write_text("{entries: [ceci n'est pas du JSON", encoding="utf-8")

    entry = _run_s10s(_driver(tmp_path, game_dir, catalog_path=bad_catalog))

    # Le volet budget se déclare NON MESURÉ ; aucune exception ne remonte.
    assert entry["status"] in {"OK", "FAIL", "BLOCKED"}


def test_game_dir_defaults_to_games_slash_project(tmp_path):
    """Sans `game_dir` explicite, le driver retombe sur GAMES/<project> sous la
    racine du repo (convention documentée pour la variante STANDARD)."""
    driver = ForgeDriver(
        "un_jeu_qui_n_existe_pas", "r1",
        run_dir=tmp_path / "run", profile="standard",
        audit_path=tmp_path / "audit.jsonl", key_file=tmp_path / "forge_test.key",
    )
    assert driver.game_dir.name == "un_jeu_qui_n_existe_pas"
    assert driver.game_dir.parent.name == "GAMES"   # surface V2 (ex-`games/`)
