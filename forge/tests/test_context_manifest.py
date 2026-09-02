"""Context Manifest (docs/forge/CONTEXT_LOOP_V1_1_FRESHNESS.md §7) — mesure du
contexte réellement servi à un agent Forge. Deux kinds ("dispatch" écrit par
prepare_dispatch, "execution" écrit par claude_executor), JSONL append-only,
HMAC-signés (même mécanisme que forge.verdict).
"""
from __future__ import annotations

import json
import tempfile
from dataclasses import dataclass
from pathlib import Path

import pytest

from forge import context_manifest as cm
from forge.contract import DispatchPayload, build_dispatch_payload, load_contract

KEY = Path(tempfile.mkdtemp()) / "k"


def _payload(etape: str = "s4-archi") -> DispatchPayload:
    contract = load_contract(etape)
    return build_dispatch_payload(contract, etape=etape, run_id="test-run")


# --- kind "dispatch" -----------------------------------------------------------

def test_dispatch_line_is_signed_and_valid(tmp_path):
    contract = load_contract("s4-archi")
    payload = _payload("s4-archi")
    rec = cm.append_dispatch_manifest(
        "s4-archi", "test-run", payload, contract, run_dir=tmp_path, key_file=KEY,
    )
    assert rec["schema"] == "forge.context_manifest.v1"
    assert rec["kind"] == "dispatch"
    assert rec["claim_verdict"] == "NO_CLAIM_ALLOWED"
    assert cm.verify_manifest_record(rec, key_file=KEY) is True

    path = cm.manifest_path(tmp_path, "s4-archi")
    line = path.read_text(encoding="utf-8").strip()
    on_disk = json.loads(line)
    assert on_disk == rec


def test_dispatch_activation_increments_per_step(tmp_path):
    contract = load_contract("s4-archi")
    payload = _payload("s4-archi")
    r1 = cm.append_dispatch_manifest("s4-archi", "run-a", payload, contract,
                                     run_dir=tmp_path, key_file=KEY)
    r2 = cm.append_dispatch_manifest("s4-archi", "run-b", payload, contract,
                                     run_dir=tmp_path, key_file=KEY)
    r3 = cm.append_dispatch_manifest("s4-archi", "run-c", payload, contract,
                                     run_dir=tmp_path, key_file=KEY)
    assert (r1["activation"], r2["activation"], r3["activation"]) == (1, 2, 3)


def test_dispatch_activation_is_scoped_per_step(tmp_path):
    """Une autre étape a son propre compteur (fichier manifest distinct)."""
    contract4 = load_contract("s4-archi")
    contract5 = load_contract("s5-wiremap")
    payload4 = _payload("s4-archi")
    payload5 = _payload("s5-wiremap")
    cm.append_dispatch_manifest("s4-archi", "run-a", payload4, contract4,
                                run_dir=tmp_path, key_file=KEY)
    cm.append_dispatch_manifest("s4-archi", "run-b", payload4, contract4,
                                run_dir=tmp_path, key_file=KEY)
    r5 = cm.append_dispatch_manifest("s5-wiremap", "run-a", payload5, contract5,
                                     run_dir=tmp_path, key_file=KEY)
    assert r5["activation"] == 1


def test_dispatch_sources_include_contract_mandatory_read_and_registry(tmp_path):
    contract = load_contract("s4-archi")
    payload = _payload("s4-archi")
    rec = cm.append_dispatch_manifest("s4-archi", "test-run", payload, contract,
                                      run_dir=tmp_path, key_file=KEY)
    roles = {s["role"] for s in rec["sources"]}
    assert "contract" in roles
    assert "mandatory_read" in roles
    assert "registry" in roles
    contract_src = next(s for s in rec["sources"] if s["role"] == "contract")
    assert contract_src["path"] == "forge/contracts/s4-archi.yaml"
    assert contract_src["exists"] is True
    assert contract_src["sha256"]


def test_dispatch_sources_ignore_narrative_mandatory_read_entries(tmp_path):
    """Les entrées NARRATIVES de mandatory_read (phrases à plusieurs mots) ne
    deviennent jamais des sources ; les entrées-CHEMIN le deviennent toutes.

    ÉVOLUTION 2026-08-06 (gate Pierre) — cette assertion figeait `len == 1`,
    nombre qui décrivait l'état de s4-archi.yaml au moment de son écriture. Un
    contrat qui gagne légitimement une entrée-chemin (ici `repo_map.yaml`, pour
    que la table figée des adresses soit PROUVÉE par sha256 et pas seulement
    transmise au prompt) la faisait rougir sans qu'aucun défaut n'existe.

    La version ci-dessous dérive l'attendu DU CONTRAT LUI-MÊME au lieu de le
    figer. Elle protège strictement plus : elle attrape l'inclusion d'un
    narratif (défaut visé à l'origine) ET l'oubli d'une entrée-chemin, sur
    n'importe quel contenu de contrat, présent ou futur.
    """
    contract = load_contract("s4-archi")
    payload = _payload("s4-archi")
    rec = cm.append_dispatch_manifest("s4-archi", "test-run", payload, contract,
                                      run_dir=tmp_path, key_file=KEY)
    mandatory = [s for s in rec["sources"] if s["role"] == "mandatory_read"]

    attendus = [e.strip() for e in contract["mandatory_read"] if cm._looks_like_path(e)]
    narratifs = [e for e in contract["mandatory_read"] if not cm._looks_like_path(e)]
    assert narratifs, "fixture caduque : s4-archi doit porter au moins une entrée narrative"

    # 1. aucune source retenue ne porte d'espace — c'est CE trait qui distingue
    #    une entrée-chemin d'une phrase, et donc le défaut réellement protégé.
    for s in mandatory:
        assert " " not in s["path"], f"entrée narrative devenue une source : {s['path']!r}"
    # 2. toutes les entrées-chemin sont là, aucune oubliée, aucune en trop.
    assert [s["path"] for s in mandatory] == attendus
    # 3. le contrat de base reste présent (ancrage historique de ce test).
    assert "forge/contracts/SCHEMA.md" in attendus


def test_missing_source_never_raises_and_reports_exists_false(tmp_path):
    """Un artefact amont absent (run_dir vide) => exists:false, sha256:null,
    jamais d'exception — même pour une étape qui EN attend (s9-build)."""
    contract = load_contract("s9-build")
    payload = _payload("s9-build")
    rec = cm.append_dispatch_manifest("s9-build", "test-run", payload, contract,
                                      run_dir=tmp_path, key_file=KEY)
    upstream = [s for s in rec["sources"] if s["role"] == "upstream"]
    assert upstream, "s9-build doit avoir des sources amont déclarées (_UPSTREAM_BY_STEP)"
    for s in upstream:
        assert s["exists"] is False
        assert s["sha256"] is None


def test_upstream_sources_resolved_relative_to_run_dir_when_present(tmp_path):
    (tmp_path / "blueprint.json").write_text('{"modules": ["a"]}', encoding="utf-8")
    contract = load_contract("s9-build")
    payload = _payload("s9-build")
    rec = cm.append_dispatch_manifest("s9-build", "test-run", payload, contract,
                                      run_dir=tmp_path, key_file=KEY)
    upstream = {s["path"]: s for s in rec["sources"] if s["role"] == "upstream"}
    bp = next(v for k, v in upstream.items() if k.endswith("blueprint.json"))
    assert bp["exists"] is True
    assert bp["sha256"]


def test_dispatch_sources_with_no_run_dir_omit_upstream_but_never_raise():
    contract = load_contract("s9-build")
    payload = _payload("s9-build")
    sources = cm.resolve_dispatch_sources("s9-build", contract, run_dir=None)
    assert not any(s["role"] == "upstream" for s in sources)


# --- run_id -> run_dir par défaut -----------------------------------------------

def test_derive_project_from_run_id_with_date_suffix():
    assert cm.derive_project_from_run_id("shmup_slice-20260714a") == "shmup_slice"
    assert cm.derive_project_from_run_id("card_engine-20260701") == "card_engine"


def test_derive_project_from_run_id_indecidable():
    assert cm.derive_project_from_run_id("t1") is None
    assert cm.derive_project_from_run_id("dryrun") is None


def test_default_run_dir_uses_derived_project():
    rd = cm.default_run_dir("shmup_slice-20260714a")
    assert rd == cm.REPO_ROOT / "EVIDENCE" / "runs" / "shmup_slice"


def test_default_run_dir_orphan_when_indecidable():
    rd = cm.default_run_dir("t1")
    assert rd == cm.REPO_ROOT / "EVIDENCE" / "runs" / "_orphan_context" / "t1"


# --- kind "execution" ------------------------------------------------------------

def test_execution_line_ok_status(tmp_path):
    rec = cm.append_execution_manifest(
        "test-run", "s9-build", tmp_path, "petit prompt", model="claude-sonnet-5",
        key_file=KEY,
    )
    assert rec["kind"] == "execution"
    assert rec["final_prompt_chars"] == len("petit prompt")
    assert rec["final_prompt_sha256"]
    assert rec["premortem_sha256"] is None
    assert rec["prompt_budget"]["status"] == "OK"
    assert rec["prompt_budget"]["model_window_tokens"] == 200000
    assert cm.verify_manifest_record(rec, key_file=KEY) is True


def test_execution_line_unknown_window(tmp_path):
    rec = cm.append_execution_manifest(
        "test-run", "s9-build", tmp_path, "prompt", model="some-unlisted-model",
        key_file=KEY,
    )
    assert rec["prompt_budget"]["status"] == "UNKNOWN_WINDOW"
    assert rec["prompt_budget"]["model_window_tokens"] is None


def test_execution_line_overflow_risk(tmp_path):
    huge_prompt = "x" * 900_000  # ~225000 tokens estimés > 0.9*200000
    rec = cm.append_execution_manifest(
        "test-run", "s9-build", tmp_path, huge_prompt, model="claude-sonnet-5",
        key_file=KEY,
    )
    assert rec["prompt_budget"]["status"] == "OVERFLOW_RISK"
    assert rec["prompt_budget"]["estimated_tokens"] > 0.9 * 200000


def test_execution_line_premortem_hash_present_when_section_given(tmp_path):
    rec = cm.append_execution_manifest(
        "test-run", "s9-build", tmp_path, "prompt", model="claude-sonnet-5",
        premortem_section="## PRÉ-MORTEM\n- erreur passée", key_file=KEY,
    )
    assert rec["premortem_sha256"] is not None
    assert rec["premortem_sha256"] == cm._sha256_text("## PRÉ-MORTEM\n- erreur passée")


def test_lookup_model_window_is_tolerant_to_provider_prefix():
    """payload.model (résolu par le registry) est un nom COURT ('claude-opus-4-8'),
    la table model_windows.json porte des clés préfixées ('anthropic/claude-opus-4-8')
    — le lookup doit tolérer les deux styles."""
    assert cm.lookup_model_window("claude-opus-4-8") == 200000
    assert cm.lookup_model_window("anthropic/claude-opus-4-8") == 200000
    assert cm.lookup_model_window("qwen2.5-14b-instruct") == 32768
    assert cm.lookup_model_window("") is None
    assert cm.lookup_model_window("modele-inconnu") is None


# --- model_executed (0.5.d : le modèle réellement exécuté dans la provenance) ---

def test_dispatch_line_model_executed_defaults_to_declared_model(tmp_path):
    """Sans override connu (cas nominal, aucune escalade), `model_executed` est
    présent et ÉGAL à `model` — jamais None, jamais ambigu."""
    contract = load_contract("s4-archi")
    payload = _payload("s4-archi")
    rec = cm.append_dispatch_manifest("s4-archi", "test-run", payload, contract,
                                      run_dir=tmp_path, key_file=KEY)
    assert rec["model_executed"] == rec["model"] == payload.model


def test_dispatch_line_model_executed_differs_after_escalation(tmp_path):
    """NÉGATIF (ce que la correction 0.5.d referme) : si `model_executed` n'était
    JAMAIS distinct de `model`, cette assertion échouerait — c'est exactement le
    défaut D-3 du charter (« la ligne signée enregistre le modèle du contrat,
    jamais celui exécuté après escalade »)."""
    contract = load_contract("s9-build")
    payload = _payload("s9-build")
    assert payload.model != "claude-opus-4-8"  # s9-build résout un tier de base, pas opus
    rec = cm.append_dispatch_manifest("s9-build", "test-run", payload, contract,
                                      run_dir=tmp_path, key_file=KEY,
                                      model_executed="claude-opus-4-8")
    assert rec["model"] == payload.model            # déclaré (contrat) — inchangé
    assert rec["model_executed"] == "claude-opus-4-8"  # réellement exécuté (escalade)
    assert rec["model"] != rec["model_executed"]
    assert cm.verify_manifest_record(rec, key_file=KEY) is True


def test_dispatch_line_model_executed_field_is_signed():
    """Falsifier `model_executed` après coup invalide le HMAC, exactement comme
    `model` (test_tampered_dispatch_line_fails_verification, symétrique)."""
    body = {
        "schema": cm.SCHEMA, "kind": "dispatch", "run_id": "r", "etape": "s9-build",
        "activation": 1, "ts": 0.0, "git_head": None, "model": "claude-haiku-4-5-20251001",
        "model_executed": "claude-opus-4-8", "provider": "", "contract_sha256": "x",
        "payload_prompt_sha256": "y", "sources": [], "claim_verdict": "NO_CLAIM_ALLOWED",
    }
    body["hmac"] = cm._sign(body, KEY)
    assert cm.verify_manifest_record(body, key_file=KEY) is True
    tampered = dict(body)
    tampered["model_executed"] = "modele-falsifie"
    assert cm.verify_manifest_record(tampered, key_file=KEY) is False


def test_dispatch_line_without_model_executed_field_still_verifies():
    """Rétro-compat (ligne écrite avant ce chantier, sans le champ) : une ligne
    signée qui ne porte PAS `model_executed` reste vérifiable telle quelle — le
    champ est additif, jamais requis par la vérification HMAC."""
    body = {
        "schema": cm.SCHEMA, "kind": "dispatch", "run_id": "r", "etape": "s9-build",
        "activation": 1, "ts": 0.0, "git_head": None, "model": "claude-haiku-4-5-20251001",
        "provider": "", "contract_sha256": "x", "payload_prompt_sha256": "y",
        "sources": [], "claim_verdict": "NO_CLAIM_ALLOWED",
    }
    body["hmac"] = cm._sign(body, KEY)
    assert "model_executed" not in body
    assert cm.verify_manifest_record(body, key_file=KEY) is True


# --- HMAC / falsification -------------------------------------------------------

def test_tampered_dispatch_line_fails_verification(tmp_path):
    contract = load_contract("s4-archi")
    payload = _payload("s4-archi")
    rec = cm.append_dispatch_manifest("s4-archi", "test-run", payload, contract,
                                      run_dir=tmp_path, key_file=KEY)
    tampered = dict(rec)
    tampered["model"] = "un-autre-modele"
    assert cm.verify_manifest_record(tampered, key_file=KEY) is False


def test_record_without_hmac_field_fails_verification():
    assert cm.verify_manifest_record({"schema": "x"}, key_file=KEY) is False


# --- table amont : anti-divergence avec forge.run_real --------------------------

def test_upstream_table_matches_run_real_exactly():
    """Duplication déclarée (anti import circulaire, cf. docstring du module) :
    toute divergence future entre les deux copies doit casser CE test."""
    from forge import run_real
    assert cm._UPSTREAM_BY_STEP == run_real._UPSTREAM_BY_STEP


# --- best-effort : une écriture manifest ne casse jamais un dispatch -----------

def test_prepare_dispatch_survives_context_manifest_write_failure(tmp_path, monkeypatch):
    from forge.dispatch import prepare_dispatch

    def _boom(*args, **kwargs):
        raise OSError("disque plein (simulé)")

    monkeypatch.setattr(cm, "append_dispatch_manifest", _boom)
    audit = tmp_path / "audit.jsonl"
    payload = prepare_dispatch("s4-archi", run_id="boom-run", audit_path=audit,
                              run_dir=tmp_path / "somewhere")
    assert payload.model  # le dispatch a réussi malgré l'échec du manifest


def test_prepare_dispatch_writes_manifest_under_explicit_run_dir(tmp_path):
    from forge.dispatch import prepare_dispatch

    audit = tmp_path / "audit.jsonl"
    run_dir = tmp_path / "myrun"
    prepare_dispatch("s4-archi", run_id="explicit-run", audit_path=audit, run_dir=run_dir)
    path = cm.manifest_path(run_dir, "s4-archi")
    assert path.exists()
    rec = json.loads(path.read_text(encoding="utf-8").strip().splitlines()[-1])
    assert rec["kind"] == "dispatch"
    assert rec["run_id"] == "explicit-run"


def test_prepare_dispatch_derives_run_dir_when_not_given(tmp_path, monkeypatch):
    from forge.dispatch import prepare_dispatch

    # Redirige la dérivation vers un dossier sous tmp_path pour ne jamais écrire
    # dans le vrai EVIDENCE/runs/ pendant les tests.
    fake_root = tmp_path / "orphan"

    def _fake_default_run_dir(run_id):
        return fake_root / run_id

    monkeypatch.setattr(cm, "default_run_dir", _fake_default_run_dir)
    audit = tmp_path / "audit.jsonl"
    prepare_dispatch("s4-archi", run_id="derived-run", audit_path=audit)
    path = cm.manifest_path(fake_root / "derived-run", "s4-archi")
    assert path.exists()


# --- verify_run : context_manifest_problems / notes -----------------------------

def _write_minimal_verdict(tmp_path):
    from forge.verdict import build_aggregate_verdict, make_signed_receipt, signed_aggregate_record
    ev = tmp_path / "oracle.log"
    ev.write_text("ok", encoding="utf-8")
    rid = "ctxmanifest-run"
    code = make_signed_receipt("code", rid, "OK", {"returncode": 0},
                               evidence_path=str(ev), key_file=KEY)
    archi = make_signed_receipt("archi", rid, "SKIPPED", {}, key_file=KEY)
    wire = make_signed_receipt("wiremap", rid, "SKIPPED", {}, key_file=KEY)
    agg = build_aggregate_verdict("demo", rid, code, archi, wire, "qwen2.5-14b-instruct",
                                  redteam_ran=True, nonce="n1", key_file=KEY)
    rec = signed_aggregate_record(agg, key_file=KEY)
    vpath = tmp_path / "verdict.json"
    vpath.write_text(json.dumps(rec, ensure_ascii=False, indent=2), encoding="utf-8")
    return vpath


def test_verify_run_no_manifest_dir_is_a_note_not_a_problem(tmp_path):
    from forge.verify_run import verify_run
    vpath = _write_minimal_verdict(tmp_path)
    res = verify_run(vpath, key_file=KEY)
    assert res["context_manifest_problems"] == []
    assert res["context_manifest_notes"]
    assert res["overall"] is True  # jamais affecté par l'absence de manifest


def test_verify_run_valid_manifest_is_zero_problems(tmp_path):
    from forge.verify_run import verify_run
    vpath = _write_minimal_verdict(tmp_path)
    contract = load_contract("s4-archi")
    payload = _payload("s4-archi")
    cm.append_dispatch_manifest("s4-archi", "ctxmanifest-run", payload, contract,
                                run_dir=tmp_path, key_file=KEY)
    res = verify_run(vpath, key_file=KEY)
    assert res["context_manifest_problems"] == []


def test_verify_run_corrupted_hmac_is_a_problem(tmp_path):
    from forge.verify_run import verify_run
    vpath = _write_minimal_verdict(tmp_path)
    contract = load_contract("s4-archi")
    payload = _payload("s4-archi")
    cm.append_dispatch_manifest("s4-archi", "ctxmanifest-run", payload, contract,
                                run_dir=tmp_path, key_file=KEY)
    path = cm.manifest_path(tmp_path, "s4-archi")
    rec = json.loads(path.read_text(encoding="utf-8").strip())
    rec["model"] = "modele-falsifie"
    path.write_text(json.dumps(rec, ensure_ascii=False) + "\n", encoding="utf-8")

    res = verify_run(vpath, key_file=KEY)
    assert res["context_manifest_problems"]
    assert res["overall"] is True  # advisory : n'entre JAMAIS dans le gate existant


# --- C.5 ratifié Pierre 2026-08-25 : la carte de contenu atteint les DEUX piliers ---

def test_c5_content_requirements_injecte_aux_deux_piliers():
    """C.5 (Content Requirements) ratifié Pierre le 2026-08-25 avec sa condition n°1 :
    « non injecté en amont de s2.5/s2.7, C.5 subit le sort de C.3 — prescrit, jamais
    livré ». Mesure de l'audit 2026-08-25 : C.3 n'apparaissait dans AUCUNE ligne de
    _UPSTREAM_BY_STEP, donc aucun agent ne l'a jamais lu. Ce test empêche que C.5
    connaisse le même sort : les 4 étapes des deux piliers (Artiste et Game Master,
    rondes 1 et 2) doivent recevoir `design/content_requirements.md`."""
    from forge import context_manifest as cm

    piliers = ("s2.5-artbible", "s2.5-artbible-r2",
               "s2.7-gm-worldscan", "s2.7-gm-worldscan-r2")
    manquants = [e for e in piliers
                 if "design/content_requirements.md" not in cm._UPSTREAM_BY_STEP[e]]
    assert not manquants, f"C.5 non injecté à : {manquants}"


def test_c5_copie_injectee_ne_derive_pas_du_canon():
    """`design/content_requirements.md` est une COPIE du contrat canonique de
    `studio_brain/gamedesign/`. Leçon mesurée (2026-08-20) : une correction qui ne
    vit qu'en aval régresse au prochain snapshot. Si les deux fichiers divergent,
    les agents lisent une carte périmée sans que rien ne le signale."""
    from pathlib import Path

    repo = Path(__file__).resolve().parents[2]
    canon = repo / "studio_brain/gamedesign/kitten_clicker_content_requirements_contract_v1.md"
    copie = repo / "EVIDENCE/runs/kitten_clicker/design/content_requirements.md"
    if not canon.exists() or not copie.exists():
        import pytest
        pytest.skip("contrat C.5 ou sa copie absent")
    assert copie.read_text(encoding="utf-8") == canon.read_text(encoding="utf-8"), (
        "design/content_requirements.md a DÉRIVÉ du contrat canonique — recopier le canon")


def test_c5_arrive_ENTIER_dans_le_contexte_des_piliers():
    """Mesuré 2026-08-25 : C.5 câblé dans _UPSTREAM_BY_STEP MAIS tronqué à
    UPSTREAM_MAX_CHARS (15 000 car.) alors que la carte en fait ~60 000 — la
    Partie II (la carte elle-même : boucle canonique, inventaires, questions
    ouvertes) ne franchissait pas la frontière. « Injecté » ne veut rien dire si
    l'agent reçoit une carte coupée en deux : c'est le même défaut que C.3 non
    injecté, en plus sournois (le fichier est là, amputé, sans signal).

    Un contrat de design ratifié (design/*.md) est une ENTRÉE humaine bornée, pas
    une sortie d'agent : il s'injecte ENTIER."""
    from pathlib import Path
    from forge.run_real import upstream_artifacts_section

    repo = Path(__file__).resolve().parents[2]
    run_dir = repo / "EVIDENCE/runs/kitten_clicker"
    if not (run_dir / "design/content_requirements.md").exists():
        import pytest
        pytest.skip("carte C.5 absente du run_dir")

    for etape in ("s2.5-artbible", "s2.7-gm-worldscan"):
        section = upstream_artifacts_section(etape, run_dir)
        assert "FAIT APPARAÎTRE UN CHATON" in section, f"{etape} : boucle canonique tronquée"
        assert "R5 — Les sept éléments" in section, f"{etape} : R5 tronquée"
        assert "PARTIE III — GLOSSAIRES" in section, f"{etape} : glossaires tronqués"


def test_c6_blueprint_injecte_et_entier():
    """C.6 (Game Loop Blueprint) — GO Pierre 2026-08-25 « comme base de travail ».
    Même régime que C.5 : injecté aux 4 étapes des deux piliers, et ENTIER (c'est un
    contrat de design, pas une sortie d'agent). Sans cela, C.6 subirait le sort de
    C.3 : prescrit, jamais livré."""
    from pathlib import Path
    from forge import context_manifest as cm
    from forge.run_real import upstream_artifacts_section

    piliers = ("s2.5-artbible", "s2.5-artbible-r2",
               "s2.7-gm-worldscan", "s2.7-gm-worldscan-r2")
    manquants = [e for e in piliers
                 if "design/game_loop_blueprint.md" not in cm._UPSTREAM_BY_STEP[e]]
    assert not manquants, f"C.6 non injecté à : {manquants}"

    repo = Path(__file__).resolve().parents[2]
    run_dir = repo / "EVIDENCE/runs/kitten_clicker"
    if not (run_dir / "design/game_loop_blueprint.md").exists():
        import pytest
        pytest.skip("blueprint C.6 absent du run_dir")
    section = upstream_artifacts_section("s2.7-gm-worldscan", run_dir)
    assert "atelier de paniers" in section, "C.6 tronqué : le premier monde n'arrive pas"


def test_c6_copie_injectee_ne_derive_pas_du_canon():
    """Même garde que pour C.5 : la copie injectée ne doit pas dériver du canon."""
    from pathlib import Path
    import pytest

    repo = Path(__file__).resolve().parents[2]
    canon = repo / "studio_brain/gamedesign/kitten_clicker_game_loop_blueprint_c6.md"
    copie = repo / "EVIDENCE/runs/kitten_clicker/design/game_loop_blueprint.md"
    if not canon.exists() or not copie.exists():
        pytest.skip("C.6 ou sa copie absent")
    assert copie.read_text(encoding="utf-8") == canon.read_text(encoding="utf-8"), (
        "design/game_loop_blueprint.md a DÉRIVÉ du canon — recopier")
