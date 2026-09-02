"""Lot C.4-code (2026-08-24, plan `2026-08-24-forge-lot-c4-code-boucles.md`) :
`design_state.loops` calculé (COMPLETE|OPEN(n)|PROPOSED|DEFERRED|UNKNOWN pour les
9 boucles GM figées), R3-lite (« théâtre de questions »), R1 étendu (pilier ready
malgré une bloquante reçue/émise), la gate `design_freeze` réécrite sur ces règles,
et `heritage/` écrit DÈS le freeze (additif au post-s9). Patron strict de
`test_driver_design_freeze.py` (`ForgeDriver.__new__` pour les méthodes pures,
runners/fixtures injectés, jamais de vrai sous-processus). Fixture gm LOCALE
(Agent B, format {steps, produces, consumes, unlocks, transformation_perceptible,
metric_propre} par boucle — copié du plan, PAS le format produit par
`game_master_schema.mjs`, hors périmètre ici, Agent A en parallèle)."""
import json
from pathlib import Path

from forge.driver import ForgeDriver


def _driver_for_gate(run_dir: Path, order=("s2.7-gm-worldscan", "s1-prisme")) -> ForgeDriver:
    d = ForgeDriver.__new__(ForgeDriver)  # pas de __init__ : méthodes pures seulement
    d.run_id = "r1"
    d.project = "proj"
    d.profile = "full"
    d.run_dir = run_dir
    d.game_dir = run_dir.parent / "game"
    d.order = list(order)
    d.state_path = run_dir / "state.json"
    return d


_LOOPS_9 = (
    "core_loop", "gameplay_loop", "progression_loop", "content_loop",
    "economy_loop", "skill_loop", "world_loop", "quest_loop", "meta_loop",
)


def _valid_gm_nine_loops() -> dict:
    """Anneau de 9 boucles : chaque `produces` est consommé par la suivante,
    chaque `unlocks` pointe vers une boucle réelle, `transformation_perceptible`
    et `metric_propre` complets et exclusifs -> les 9 boucles sont COMPLETE."""
    n = len(_LOOPS_9)
    loops = {}
    for i, name in enumerate(_LOOPS_9):
        prev_name = _LOOPS_9[(i - 1) % n]
        next_name = _LOOPS_9[(i + 1) % n]
        loops[name] = {
            "steps": [],
            "produces": f"p_{name}",
            "consumes": [prev_name],  # noms de boucles (semantique mjs), jamais des jetons produces
            "unlocks": [next_name],
            "transformation_perceptible": {
                "text": f"transformation perceptible de {name}",
                "proof_ref": f"proof_{name}",
            },
            "metric_propre": f"m_{name}",
        }
    return {"game_master": {"loops": loops}}


def _write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")


def _write_gm(run_dir: Path, payload: dict) -> None:
    _write_json(run_dir / "gm_worldscan.json", payload)


def _write_questions(run_dir: Path, payload: dict) -> None:
    _write_json(run_dir / "design_questions.json", payload)


def _empty_questions(round_=1, ready_art=True, ready_gm=True):
    return {
        "schema_version": 1, "round": round_, "questions": [],
        "declarations": {
            "ART": {"round": round_, "ready_for_freeze": ready_art, "open_to_gm": 0},
            "GM": {"round": round_, "ready_for_freeze": ready_gm, "open_to_art": 0},
        },
    }


# =====================================================================
# (a) gm 9-boucles valide + 0 question ouverte + deferred vide -> toutes
#     COMPLETE, freeze PASSE, heritage/ écrit AVANT s1 (fichiers + manifest.at)
# =====================================================================


def test_a_neuf_boucles_completes_freeze_passe_heritage_ecrit_avant_s1(tmp_path):
    run_dir = tmp_path / "run"
    d = _driver_for_gate(run_dir)
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "art_bible.md").write_text("# art bible", encoding="utf-8")
    _write_gm(run_dir, _valid_gm_nine_loops())
    _write_questions(run_dir, _empty_questions())

    state = {"steps": {"s1-prisme": {"status": "PENDING"}}}
    result = d._design_freeze_gate(state)

    assert result is None  # s1 tourne
    assert state["design_freeze"]["passed"] is True
    for name in _LOOPS_9:
        assert state["design_freeze"]["loops"][name]["status"] == "COMPLETE"
    assert state["design_freeze"]["shared_design_pct"] == 100
    assert state["design_state"]["loops"] == state["design_freeze"]["loops"]

    heritage = run_dir / "heritage"
    assert (heritage / "art_bible.md").read_text(encoding="utf-8") == "# art bible"
    assert (heritage / "gm_worldscan.json").is_file()
    assert (heritage / "design_questions.json").is_file()
    manifest = json.loads((heritage / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["at"] == "design_freeze"
    assert manifest["run_id"] == "r1"
    assert set(manifest["files"].keys()) == {
        "art_bible.md", "gm_worldscan.json", "design_questions.json"}
    # aucun build s9 n'existe encore : la preuve que le freeze n'attend pas project.godot
    assert not (d.game_dir / "project.godot").exists()


# =====================================================================
# (b) une boucle sans metric_propre -> PROPOSED nommée, HALTED
# =====================================================================


def test_b_boucle_sans_metric_propre_proposed_halted(tmp_path):
    run_dir = tmp_path / "run"
    d = _driver_for_gate(run_dir)
    gm = _valid_gm_nine_loops()
    del gm["game_master"]["loops"]["skill_loop"]["metric_propre"]
    _write_gm(run_dir, gm)
    _write_questions(run_dir, _empty_questions())

    state = {"steps": {"s1-prisme": {"status": "PENDING"}}}
    report = d._design_freeze_gate(state)

    assert report is not None
    assert report["status"] == "HALTED"
    assert state["design_freeze"]["passed"] is False
    skill = state["design_freeze"]["loops"]["skill_loop"]
    assert skill["status"] == "PROPOSED"
    assert "metric_propre absent" in skill["reasons"]
    assert "skill_loop: PROPOSED(metric_propre absent)" in report["reason"]
    # les 8 autres boucles restent COMPLETE : seule skill_loop est nommée
    for name in _LOOPS_9:
        if name != "skill_loop":
            assert state["design_freeze"]["loops"][name]["status"] == "COMPLETE"


def test_b_bis_metric_propre_partage_proposed(tmp_path):
    run_dir = tmp_path / "run"
    d = _driver_for_gate(run_dir)
    gm = _valid_gm_nine_loops()
    gm["game_master"]["loops"]["quest_loop"]["metric_propre"] = \
        gm["game_master"]["loops"]["meta_loop"]["metric_propre"]
    _write_gm(run_dir, gm)
    _write_questions(run_dir, _empty_questions())

    state = {"steps": {"s1-prisme": {"status": "PENDING"}}}
    report = d._design_freeze_gate(state)

    assert report is not None
    quest = state["design_freeze"]["loops"]["quest_loop"]
    assert quest["status"] == "PROPOSED"
    assert "metric_propre partagé" in quest["reasons"]


# =====================================================================
# (c) question bloquante loop_id=world_loop sans réponse -> world OPEN(1), HALTED
# =====================================================================


def test_c_question_bloquante_non_repondue_world_loop_open(tmp_path):
    run_dir = tmp_path / "run"
    d = _driver_for_gate(run_dir)
    _write_gm(run_dir, _valid_gm_nine_loops())
    _write_questions(run_dir, {
        "schema_version": 1, "round": 1,
        "questions": [
            {"id": "q_gm_1", "from": "GM", "to": "ART", "round": 1,
             "loop_id": "world_loop", "about": "x", "missing": [], "why": "y",
             "blocking": True, "answer": None},
        ],
        "declarations": {
            "ART": {"round": 1, "ready_for_freeze": True, "open_to_gm": 0},
            "GM": {"round": 1, "ready_for_freeze": True, "open_to_art": 1},
        },
    })

    state = {"steps": {"s1-prisme": {"status": "PENDING"}}}
    report = d._design_freeze_gate(state)

    assert report is not None
    assert report["status"] == "HALTED"
    assert state["design_freeze"]["loops"]["world_loop"]["status"] == "OPEN(1)"
    assert "world_loop: OPEN(1)" in report["reason"]


# =====================================================================
# (d) deferred_loops.json (7 boucles) + core/gameplay COMPLETE -> freeze PASSE,
#     pct calculé sur 2
# =====================================================================


def test_d_deferred_7_boucles_core_gameplay_completes_pct_sur_2(tmp_path):
    run_dir = tmp_path / "run"
    d = _driver_for_gate(run_dir)
    _write_gm(run_dir, _valid_gm_nine_loops())
    _write_questions(run_dir, _empty_questions())
    seven = [name for name in _LOOPS_9 if name not in ("core_loop", "gameplay_loop")]
    assert len(seven) == 7
    _write_json(run_dir / "design" / "deferred_loops.json", {
        "schema_version": 1, "ratified_by": "Pierre", "date": "2026-08-24",
        "deferred": [{"loop": name, "reason": "phase 1 : hors périmètre"} for name in seven],
    })

    state = {"steps": {"s1-prisme": {"status": "PENDING"}}}
    result = d._design_freeze_gate(state)

    assert result is None
    assert state["design_freeze"]["passed"] is True
    assert state["design_freeze"]["shared_design_pct"] == 100  # 2 COMPLETE / (9-7) = 100 %
    assert state["design_freeze"]["loops"]["core_loop"]["status"] == "COMPLETE"
    assert state["design_freeze"]["loops"]["gameplay_loop"]["status"] == "COMPLETE"
    for name in seven:
        assert state["design_freeze"]["loops"][name]["status"] == "DEFERRED"
        assert state["design_freeze"]["loops"][name]["reason"] == "phase 1 : hors périmètre"


def test_d_bis_driver_ne_lit_jamais_ecrit_deferred_loops(tmp_path):
    """Le driver LIT `design/deferred_loops.json` — il ne l'écrit JAMAIS, même
    quand la gate passe ou halte (fichier HUMAIN uniquement)."""
    run_dir = tmp_path / "run"
    d = _driver_for_gate(run_dir)
    _write_gm(run_dir, _valid_gm_nine_loops())
    _write_questions(run_dir, _empty_questions(ready_art=False))
    state = {"steps": {"s1-prisme": {"status": "PENDING"}}}
    d._design_freeze_gate(state)
    assert not (run_dir / "design" / "deferred_loops.json").exists()


# =====================================================================
# (e) R3-lite : réponse bloquante fermée sans modification de la boucle vs
#     l'archive r1 -> HALTED « théâtre » ; boucle modifiée -> passe
# =====================================================================


def _answered_blocking_questions(loop_id="world_loop"):
    return {
        "schema_version": 1, "round": 2,
        "questions": [
            {"id": "q_1", "from": "GM", "to": "ART", "round": 1, "loop_id": loop_id,
             "about": "x", "missing": [], "why": "y", "blocking": True,
             "answer": {"round": 2, "by": "ART", "ref": "r", "text": "répondu"}},
        ],
        "declarations": {
            "ART": {"round": 2, "ready_for_freeze": True, "open_to_gm": 0},
            "GM": {"round": 2, "ready_for_freeze": True, "open_to_art": 0},
        },
    }


def test_e_reponse_sans_modification_theatre_de_questions(tmp_path):
    run_dir = tmp_path / "run"
    d = _driver_for_gate(run_dir)
    gm = _valid_gm_nine_loops()
    _write_gm(run_dir, gm)
    # archive round 1 : EXACTEMENT le même contenu pour world_loop
    _write_json(run_dir / "artifacts" / "gm_worldscan-r1.json", gm)
    _write_questions(run_dir, _answered_blocking_questions("world_loop"))

    state = {"steps": {"s1-prisme": {"status": "PENDING"}}}
    report = d._design_freeze_gate(state)

    assert report is not None
    assert report["status"] == "HALTED"
    assert "théâtre de questions" in report["reason"]
    assert "world_loop" in report["reason"]
    assert state["design_freeze"]["loops"]["world_loop"]["status"] == \
        "OPEN(réponse sans modification)"


def test_e_bis_boucle_modifiee_r3_lite_ne_bloque_pas(tmp_path):
    run_dir = tmp_path / "run"
    d = _driver_for_gate(run_dir)
    gm = _valid_gm_nine_loops()
    # archive round 1 : world_loop avait un texte différent -> la réponse A modifié la boucle
    archive = _valid_gm_nine_loops()
    archive["game_master"]["loops"]["world_loop"]["transformation_perceptible"]["text"] = \
        "ancien texte pré-réponse"
    _write_gm(run_dir, gm)
    _write_json(run_dir / "artifacts" / "gm_worldscan-r1.json", archive)
    _write_questions(run_dir, _answered_blocking_questions("world_loop"))

    state = {"steps": {"s1-prisme": {"status": "PENDING"}}}
    result = d._design_freeze_gate(state)

    assert result is None
    assert state["design_freeze"]["passed"] is True
    assert state["design_freeze"]["loops"]["world_loop"]["status"] == "COMPLETE"


def test_e_ter_archive_absente_premiere_ronde_non_applicable(tmp_path):
    """1ʳᵉ ronde : aucune archive `-r1.json` -> R3-lite non applicable, ne bloque
    jamais (même boucle répondue, mais rien à comparer)."""
    run_dir = tmp_path / "run"
    d = _driver_for_gate(run_dir)
    _write_gm(run_dir, _valid_gm_nine_loops())
    _write_questions(run_dir, _answered_blocking_questions("world_loop"))

    state = {"steps": {"s1-prisme": {"status": "PENDING"}}}
    result = d._design_freeze_gate(state)

    assert result is None
    assert state["design_freeze"]["passed"] is True


# =====================================================================
# (f) R1 étendu : pilier ready avec une bloquante ÉMISE sans réponse -> HALTED
# =====================================================================


def test_f_pilier_ready_avec_bloquante_emise_sans_reponse_halted(tmp_path):
    """Une question bloquante non fermée relie TOUJOURS les deux piliers (elle a
    un `from` ET un `to`) : ÉMISE par ART, elle est simultanément REÇUE par GM —
    R1 étendu refuse donc les deux déclarations `ready_for_freeze`, même si les 2
    piliers s'étaient déclarés prêts. C'est le point du lot : plus aucun pilier
    ne peut se déclarer prêt tant qu'une bloquante qui le touche traîne, qu'il en
    soit l'auteur ou le destinataire."""
    run_dir = tmp_path / "run"
    d = _driver_for_gate(run_dir)
    _write_gm(run_dir, _valid_gm_nine_loops())
    _write_questions(run_dir, {
        "schema_version": 1, "round": 1,
        "questions": [
            # ÉMISE par ART (from=ART) vers GM, jamais répondue, bloquante.
            # loop_id absent volontairement pour isoler le test sur R1 étendu
            # (pas de contamination du statut par boucle via open_by_loop).
            {"id": "q_art_1", "from": "ART", "to": "GM", "round": 1,
             "about": "x", "missing": [], "why": "y", "blocking": True,
             "answer": None},
        ],
        "declarations": {
            # les deux piliers se déclarent ready_for_freeze malgré la question ouverte.
            "ART": {"round": 1, "ready_for_freeze": True, "open_to_gm": 1},
            "GM": {"round": 1, "ready_for_freeze": True, "open_to_art": 0},
        },
    })

    state = {"steps": {"s1-prisme": {"status": "PENDING"}}}
    report = d._design_freeze_gate(state)

    assert report is not None
    assert report["status"] == "HALTED"
    assert "R1 étendu" in report["reason"]
    assert "ART" in report["reason"]
    assert "GM" in report["reason"]
    assert state["design_freeze"]["passed"] is False


# =====================================================================
# (g) heritage post-s9 devient additif : art_response ajouté sans écraser ;
#     sans build, le heritage du freeze reste intact
# =====================================================================


def _driver_with_game(run_dir: Path, game_dir: Path) -> ForgeDriver:
    d = ForgeDriver.__new__(ForgeDriver)
    d.run_id = "r1"
    d.run_dir = run_dir
    d.game_dir = game_dir
    return d


def test_g_fin_de_run_avec_build_ajoute_art_response_sans_ecraser(tmp_path):
    run_dir = tmp_path / "run"
    game_dir = tmp_path / "game"
    run_dir.mkdir(parents=True)
    game_dir.mkdir(parents=True)
    d = _driver_with_game(run_dir, game_dir)

    (run_dir / "art_bible.md").write_text("# art bible fige au freeze", encoding="utf-8")
    (run_dir / "gm_worldscan.json").write_text('{"genre": "clicker"}', encoding="utf-8")
    (run_dir / "design_questions.json").write_text('{"questions": []}', encoding="utf-8")
    d._write_heritage_at_freeze_best_effort()

    manifest_before = json.loads(
        (run_dir / "heritage" / "manifest.json").read_text(encoding="utf-8"))
    assert manifest_before["at"] == "design_freeze"
    assert set(manifest_before["files"].keys()) == {
        "art_bible.md", "gm_worldscan.json", "design_questions.json"}

    # s9 matérialise un build + un art_response.json
    (game_dir / "project.godot").write_text('[application]\n', encoding="utf-8")
    (game_dir / "04_ASSETS").mkdir()
    (game_dir / "04_ASSETS" / "art_response.json").write_text(
        '{"schema_version": 1, "responses": []}', encoding="utf-8")

    d._write_heritage_best_effort()

    heritage = run_dir / "heritage"
    # art_bible/gm_worldscan NE SONT PAS écrasés (contenu figé au freeze intact)
    assert (heritage / "art_bible.md").read_text(encoding="utf-8") == "# art bible fige au freeze"
    assert (heritage / "gm_worldscan.json").read_text(encoding="utf-8") == '{"genre": "clicker"}'
    assert (heritage / "art_response.json").read_text(encoding="utf-8") == \
        '{"schema_version": 1, "responses": []}'

    manifest_after = json.loads((heritage / "manifest.json").read_text(encoding="utf-8"))
    assert manifest_after["at"] == "design_freeze"  # préservé
    assert set(manifest_after["files"].keys()) == {
        "art_bible.md", "gm_worldscan.json", "design_questions.json", "art_response.json"}
    assert manifest_after["files"]["art_bible.md"] == manifest_before["files"]["art_bible.md"]


def test_g_bis_sans_build_heritage_du_freeze_reste_intact(tmp_path):
    run_dir = tmp_path / "run"
    game_dir = tmp_path / "game"
    run_dir.mkdir(parents=True)
    game_dir.mkdir(parents=True)  # pas de project.godot
    d = _driver_with_game(run_dir, game_dir)

    (run_dir / "art_bible.md").write_text("# art bible fige au freeze", encoding="utf-8")
    d._write_heritage_at_freeze_best_effort()
    manifest_before = json.loads(
        (run_dir / "heritage" / "manifest.json").read_text(encoding="utf-8"))

    d._write_heritage_best_effort()  # no-op : pas de project.godot

    manifest_after = json.loads(
        (run_dir / "heritage" / "manifest.json").read_text(encoding="utf-8"))
    assert manifest_after == manifest_before
    assert (run_dir / "heritage" / "art_bible.md").read_text(encoding="utf-8") == \
        "# art bible fige au freeze"


def test_g_ter_profil_sans_boucle_heritage_post_s9_reste_complet_historique(tmp_path):
    """Sans écriture au freeze (aucun manifest `design_freeze` préexistant, cas
    d'un profil sans boucle design) : `_write_heritage_best_effort` garde son
    comportement HISTORIQUE — copie les 3 sources ensemble."""
    run_dir = tmp_path / "run"
    game_dir = tmp_path / "game"
    run_dir.mkdir(parents=True)
    game_dir.mkdir(parents=True)
    d = _driver_with_game(run_dir, game_dir)

    (run_dir / "art_bible.md").write_text("# art bible", encoding="utf-8")
    (run_dir / "gm_worldscan.json").write_text('{"genre": "clicker"}', encoding="utf-8")
    (game_dir / "project.godot").write_text('[application]\n', encoding="utf-8")
    (game_dir / "04_ASSETS").mkdir()
    (game_dir / "04_ASSETS" / "art_response.json").write_text('{"responses": []}', encoding="utf-8")

    d._write_heritage_best_effort()

    heritage = run_dir / "heritage"
    manifest = json.loads((heritage / "manifest.json").read_text(encoding="utf-8"))
    assert "at" not in manifest
    assert set(manifest["files"].keys()) == {
        "art_bible.md", "gm_worldscan.json", "art_response.json"}


# =====================================================================
# Run 11b (2026-08-24, kitten_clicker-20260824f) : R2a par NOM de boucle,
# jamais par chaine `produces`. Le gm REEL (accepte par game_master_schema.mjs,
# semantique canonique : `consumes` = noms de boucles) etait degrade PROPOSED
# par la gate (« produces non consomme ») car le driver comparait la CHAINE
# produces aux noms -- l'oracle se mesurait lui-meme via sa propre fixture.
# =====================================================================

_RUN11B_GM = Path(__file__).resolve().parent / "fixtures" / "run11b_gm_worldscan_real.json"


def _deferred_seven(run_dir: Path) -> None:
    deferred = {
        "schema_version": 1, "ratified_by": "Pierre", "date": "2026-08-24",
        "required_complete": ["core_loop", "gameplay_loop"],
        "deferred": [
            {"loop": n, "reason": "phase 1"} for n in (
                "progression_loop", "content_loop", "economy_loop", "skill_loop",
                "world_loop", "quest_loop", "meta_loop")],
    }
    _write_json(run_dir / "design" / "deferred_loops.json", deferred)


def test_gm_reel_run11b_core_et_gameplay_completes_sous_semantique_nom_de_boucle(tmp_path):
    run_dir = tmp_path / "run"
    d = _driver_for_gate(run_dir)
    d.run_index_path = run_dir / "run_index.json"
    d.lessons_path = run_dir / "lessons.jsonl"
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "art_bible.md").write_text("# art bible", encoding="utf-8")
    (run_dir / "gm_worldscan.json").write_text(
        _RUN11B_GM.read_text(encoding="utf-8"), encoding="utf-8")
    _write_questions(run_dir, _empty_questions(round_=2))
    _deferred_seven(run_dir)

    state = {"steps": {"s1-prisme": {"status": "PENDING"}}}
    result = d._design_freeze_gate(state)

    loops = state["design_freeze"]["loops"]
    # gameplay_loop.consumes = ['core_loop'] : le NOM suffit (semantique mjs)
    assert loops["core_loop"]["status"] == "COMPLETE", loops["core_loop"]
    assert loops["gameplay_loop"]["status"] == "COMPLETE", loops["gameplay_loop"]
    assert state["design_freeze"]["passed"] is True
    assert result is None
