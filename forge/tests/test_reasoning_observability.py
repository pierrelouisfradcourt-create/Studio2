"""Oracle de `forge.reasoning_observability` — étape 5 du charter V2
(RAISONNEMENT OBSERVABLE, docs/fvl/FVL_PHASE_0_5_CHARTER.md §4).

Quatre maillons, un test négatif CONSTRUIT (fixture contrôlée) par maillon, et
une mesure de PRODUCTION séparée sur les fichiers réels du dépôt — jamais
mélangées, jamais un seul test qui ferait les deux à la fois.

Aucun appel réseau/modèle dans ce fichier : les 3 appels réels autorisés par la
mission ont déjà été faits (2026-07-30, coût divulgué dans le rapport de
mission) et leurs sorties sont figées dans tests/fixtures/
reasoning_observability/call{1,2,3}_*.jsonl — ce fichier les REJOUE.

NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

from pathlib import Path

import pytest

import forge.run_real as run_real
from forge import reasoning_observability as ro

FIXTURES = Path(__file__).resolve().parent / "fixtures" / "reasoning_observability"


# --- Maillon 1 — déclaré ------------------------------------------------------------

class TestMaillon1Declare:
    def test_classify_toutes_les_valeurs_cli_compatibles(self):
        for value in ro.EFFORT_CLI_VALUES:
            assert ro.classify_declared_reasoning(value) == ro.DECLARED_KIND_CLI_COMPATIBLE
            # insensible à la casse (roles.yaml pourrait écrire 'High' un jour)
            assert ro.classify_declared_reasoning(value.upper()) == ro.DECLARED_KIND_CLI_COMPATIBLE

    def test_classify_false_est_not_applicable(self):
        assert ro.classify_declared_reasoning(False) == ro.DECLARED_KIND_NOT_APPLICABLE

    def test_classify_absent_est_absent(self):
        assert ro.classify_declared_reasoning(None) == ro.DECLARED_KIND_ABSENT

    def test_classify_valeur_inventee_est_unknown_NEGATIF(self):
        """Test NÉGATIF construit (maillon 1) : une valeur qui n'est NI dans le
        vocabulaire CLI NI `False` NI absente doit être rejetée en `unknown` —
        jamais classée `cli_compatible` par erreur (un typo ne doit jamais
        passer pour une déclaration valide)."""
        assert ro.classify_declared_reasoning("extreme") == ro.DECLARED_KIND_UNKNOWN
        assert ro.classify_declared_reasoning("true") == ro.DECLARED_KIND_UNKNOWN
        assert ro.classify_declared_reasoning(1) == ro.DECLARED_KIND_UNKNOWN

    def test_read_declared_reasoning_sur_fixture_controlee(self):
        """Cas CONTRÔLÉ (valeur injectée) : couvre les 4 kinds en un seul
        fichier, exactement comme prescrit par la mission avant toute mesure
        de production."""
        declared = ro.read_declared_reasoning(FIXTURES / "roles_controlled.yaml")
        by_role = {d.roles[0]: d for d in declared}
        assert by_role["role_high"].kind == ro.DECLARED_KIND_CLI_COMPATIBLE
        assert by_role["role_low"].kind == ro.DECLARED_KIND_CLI_COMPATIBLE
        assert by_role["role_na"].kind == ro.DECLARED_KIND_NOT_APPLICABLE
        assert by_role["role_unknown"].kind == ro.DECLARED_KIND_UNKNOWN
        assert by_role["role_absent"].kind == ro.DECLARED_KIND_ABSENT

    def test_declared_reasoning_for_role_resout_le_bon_modele(self):
        d = ro.declared_reasoning_for_role("role_low", FIXTURES / "roles_controlled.yaml")
        assert d is not None and d.model_id == "test/model-low"

    def test_declared_reasoning_for_role_inconnu_rend_none(self):
        assert ro.declared_reasoning_for_role("role_n_existe_pas",
                                               FIXTURES / "roles_controlled.yaml") is None

    # --- mesure de PRODUCTION (roles.yaml réel), séparée du cas contrôlé -----------

    def test_PRODUCTION_roles_yaml_reel(self):
        """Mesure de production, en chiffres bruts (preuve exigée #4). Valeurs
        gelées le 2026-07-30 : 6 modèles déclarés, 4 cli_compatible (Fable,
        Opus, Haiku, Sonnet-toolsmith), 2 not_applicable (Qwen, déterministe) —
        ZÉRO 'unknown', ZÉRO 'absent' : le vocabulaire réellement utilisé en
        production est un SOUS-ENSEMBLE cohérent du vocabulaire CLI, pas une
        divergence. Ce test casse si roles.yaml change de forme — c'est voulu :
        la mesure de production doit rester à jour, jamais figée dans un
        commentaire qui diverge en silence."""
        declared = ro.read_declared_reasoning()  # défaut = FORGE_ROLES réel
        assert len(declared) == 6
        counts: dict[str, int] = {}
        for d in declared:
            counts[d.kind] = counts.get(d.kind, 0) + 1
        assert counts == {
            ro.DECLARED_KIND_CLI_COMPATIBLE: 4,
            ro.DECLARED_KIND_NOT_APPLICABLE: 2,
        }
        # Chaque valeur CLI-compatible réellement déclarée est un sous-ensemble
        # strict du vocabulaire CLI (high/low seulement, jamais medium/xhigh/max).
        cli_values_used = {d.raw for d in declared if d.kind == ro.DECLARED_KIND_CLI_COMPATIBLE}
        assert cli_values_used == {"high", "low"}


# --- Maillon 2 — effectivement lu ---------------------------------------------------

class TestMaillon2EffectivementLu:
    def test_scan_detecte_un_lecteur_reel_POSITIF(self):
        rec = ro._scan_one_file(FIXTURES / "reader_positive_snippet.txt")
        assert rec["exists"] is True
        assert rec["reads_reasoning"] is True
        assert len(rec["matches"]) >= 2  # .get("reasoning" + ["reasoning"] + reasoning=

    def test_scan_ne_signale_rien_sur_du_code_propre_NEGATIF(self):
        """Test NÉGATIF construit (maillon 2) : un fichier qui PARLE de
        raisonnement en prose, sans jamais accéder au champ `reasoning`, ne
        doit produire AUCUN faux positif — sinon le scan serait inutilisable
        (il crierait au loup sur n'importe quel commentaire)."""
        rec = ro._scan_one_file(FIXTURES / "reader_negative_snippet.txt")
        assert rec["exists"] is True
        assert rec["reads_reasoning"] is False
        assert rec["matches"] == ()

    def test_scan_fichier_absent_ne_leve_pas(self):
        rec = ro._scan_one_file(FIXTURES / "n_existe_pas.py")
        assert rec == {"path": str(FIXTURES / "n_existe_pas.py"), "exists": False,
                        "reads_reasoning": False, "matches": ()}

    def test_scan_reasoning_readers_rend_un_enregistrement_par_cible(self):
        recs = ro.scan_reasoning_readers(
            scripts_forge_dir=FIXTURES, registry_path=FIXTURES / "reader_negative_snippet.txt",
            targets=("reader_positive_snippet.txt", "reader_negative_snippet.txt"),
        )
        assert len(recs) == 3  # 2 targets + le registry_path dédié
        assert recs[0]["reads_reasoning"] is True
        assert recs[1]["reads_reasoning"] is False
        assert recs[2]["reads_reasoning"] is False

    # --- mesure de PRODUCTION (fichiers Forge réels), séparée du cas contrôlé ------

    def test_PRODUCTION_un_seul_lecteur_dans_la_forge_reelle(self):
        """Mesure de production, en chiffres bruts (preuve exigée #4).

        Valeur gelée le 2026-07-29 (audit initial de ce module) : ZÉRO lecteur
        de `reasoning` sur 12 fichiers réels. Valeur mise à jour le 2026-07-30
        (mission d'outillage « rendre le mécanisme effectif ») : EXACTEMENT UN
        lecteur — `control_plane/registry.py` (`get_reasoning_for_model`,
        `.get("reasoning")`), ajouté par ce chantier pour transmettre le
        réglage `--effort` à `forge.run_real._claude_call_raw`. C'est le
        résultat ATTENDU du chantier RAISONNEMENT, pas une régression : ce test
        casse (volontairement) si un AUTRE fichier se met à lire `reasoning`
        sans qu'on le décide, exactement comme `test_PRODUCTION_roles_yaml_reel`
        casse si roles.yaml change de forme — c'est voulu, pas figé par accident.
        Tous les fichiers existent (exists=True partout) : un 'False' ici n'est
        jamais dû à un chemin cassé, la couverture est complète."""
        recs = ro.scan_reasoning_readers()
        assert len(recs) == len(ro.READER_SCAN_TARGETS) + 1  # + control_plane/registry.py
        assert all(r["exists"] for r in recs), [r for r in recs if not r["exists"]]
        readers = [r for r in recs if r["reads_reasoning"]]
        assert [r["path"] for r in readers] == [str(ro.REPO_ROOT / "control_plane" / "registry.py")], (
            f"lecteur(s) inattendu(s) : {readers}")


# --- Maillon 3 — réellement exécuté (capacité, puis câblage réel) ------------------

class TestMaillon3ReellementExecute:
    def test_capacite_a_documentee_sur_fixture_reelle(self):
        """(a) CAPACITÉ, établie sur une capture RÉELLE de `claude --help`
        (2026-07-30, commande locale, 0 $ — aucun appel modèle) : le binaire
        invoqué par `_claude_call_raw` documente bien un réglage d'effort."""
        help_text = (FIXTURES / "claude_help.txt").read_text(encoding="utf-8")
        assert ro.effort_flag_documented(help_text) is True
        assert "--effort <level>" in help_text
        assert "low, medium, high, xhigh, max" in help_text

    def test_capacite_a_NEGATIF_sur_aide_sans_effort(self):
        """Test NÉGATIF construit (maillon 3a) : un texte d'aide qui ne
        documente aucun réglage d'effort doit être classé absent — sinon la
        fonction serait vraie par construction (toujours True)."""
        assert ro.effort_flag_documented("Options:\n  --model <model>\n") is False

    def test_cablage_b_pur_POSITIF_et_NEGATIF(self):
        assert ro.effort_flag_present_in_cmd(
            ["claude", "-p", "--model", "sonnet", "--effort", "high"]) is True
        assert ro.effort_flag_present_in_cmd(
            ["claude", "-p", "--model", "sonnet", "--output-format", "json"]) is False

    def test_cablage_b_PRODUCTION_cmd_reelle_de_claude_call_raw(self, tmp_path, monkeypatch):
        """Mesure de production, MÉCANIQUE, sur la fonction RÉELLE (jamais
        modifiée) : capture la commande TELLE QUE `_claude_call_raw` la
        construit aujourd'hui (seam identique à `capture_cmd` de
        tests/test_run_real_hardening.py — monkeypatch de `subprocess.run`,
        aucun spawn réel), pour CHAQUE famille d'appel (avec outils / sans
        outils, panel Prisme compris). `--effort` est ABSENT des deux — c'est
        la mesure, pas une supposition sur la lecture du code source."""
        import json as _json

        captured = []

        class FakeCompleted:
            returncode = 0
            stdout = _json.dumps({"result": "ok", "usage": {}, "total_cost_usd": 0.0})
            stderr = ""

        def fake_run(cmd, **kwargs):
            captured.append(list(cmd))
            return FakeCompleted()

        monkeypatch.setattr(run_real.subprocess, "run", fake_run)

        run_real._claude_call_raw("prompt", "sonnet", add_dir=tmp_path,
                                   tools=("Write", "Read"))
        run_real._claude_call_raw("prompt", "haiku", add_dir=tmp_path, tools=())

        assert len(captured) == 2
        for cmd in captured:
            assert ro.effort_flag_present_in_cmd(cmd) is False


# --- Maillon 4 — effectivement utilisé ----------------------------------------------

class TestMaillon4EffectivementUtilise:
    def test_synthetic_sans_thinking_NEGATIF(self):
        """Test NÉGATIF construit (maillon 4) : une sortie sans bloc thinking
        doit rendre NO_EVIDENCE, jamais un faux THINKING_BLOCK_PRESENT."""
        text = (FIXTURES / "synthetic_no_thinking.jsonl").read_text(encoding="utf-8")
        result = ro.classify_reasoning_evidence(text)
        assert result["status"] == ro.REASONING_EVIDENCE_NONE
        assert result["thinking_blocks"] == 0

    def test_synthetic_avec_thinking_POSITIF(self):
        text = (FIXTURES / "synthetic_with_thinking.jsonl").read_text(encoding="utf-8")
        result = ro.classify_reasoning_evidence(text)
        assert result["status"] == ro.REASONING_EVIDENCE_THINKING_BLOCK
        assert result["thinking_blocks"] == 1
        assert result["result_output_tokens"] == 500  # ligne corrompue ignorée, résultat lu

    def test_texte_vide_ne_leve_pas(self):
        result = ro.classify_reasoning_evidence("")
        assert result["status"] == ro.REASONING_EVIDENCE_NONE
        assert result["result_output_tokens"] is None

    # --- évidence RÉELLE (3 appels réels, 2026-07-30, coût divulgué au rapport) ----

    def test_REEL_effort_low_tache_triviale_aucune_evidence(self):
        """Appel réel 1/3 : sonnet, --effort low, tâche arithmétique triviale,
        --output-format stream-json --verbose. Aucun bloc thinking observé."""
        text = (FIXTURES / "call1_effort_low_stream.jsonl").read_text(encoding="utf-8")
        result = ro.classify_reasoning_evidence(text)
        assert result["status"] == ro.REASONING_EVIDENCE_NONE
        assert result["thinking_blocks"] == 0

    def test_REEL_effort_high_tache_triviale_aucune_evidence(self):
        """Appel réel 2/3 : même tâche triviale, --effort high. STRUCTURELLEMENT
        IDENTIQUE à l'appel low (aucun bloc thinking, même forme d'usage) —
        c'est la mesure : sur cette tâche, low et high ne se distinguent par
        RIEN d'observable dans la sortie."""
        text = (FIXTURES / "call2_effort_high_stream.jsonl").read_text(encoding="utf-8")
        result = ro.classify_reasoning_evidence(text)
        assert result["status"] == ro.REASONING_EVIDENCE_NONE
        assert result["thinking_blocks"] == 0

    def test_REEL_effort_max_tache_difficile_evidence_presente(self):
        """Appel réel 3/3 : sonnet, --effort max, énigme logique à plusieurs
        contraintes. UN bloc `type: thinking` apparaît (contenu redacted par
        le produit — 'thinking': '' + 'signature' présente — mais le TYPE de
        bloc, lui, est une évidence structurelle réelle), avec un profil
        output_tokens/durée/coût radicalement différent des deux appels
        triviaux. Confondu avec la difficulté de la tâche (budget épuisé avant
        d'isoler la variable) — voir SKIPPED_VALIDATION du rapport de mission."""
        text = (FIXTURES / "call3_effort_max_stream.jsonl").read_text(encoding="utf-8")
        result = ro.classify_reasoning_evidence(text)
        assert result["status"] == ro.REASONING_EVIDENCE_THINKING_BLOCK
        assert result["thinking_blocks"] == 1
        assert result["result_output_tokens"] > 1000  # vs 4 tokens pour les appels triviaux


# --- trace par run (signature HMAC, lecture, robustesse) ---------------------------

class TestTraceParRun:
    CONTRACT = {"capability_role": "architect"}

    def test_build_record_resout_le_role_reel(self):
        rec = ro.build_reasoning_observability_record("s4-archi", "run-x", self.CONTRACT)
        assert rec["capability_role"] == "architect"
        assert rec["declared_status"] == "RESOLVED"
        assert rec["declared"]["kind"] == ro.DECLARED_KIND_CLI_COMPATIBLE
        assert rec["schema"] == ro.SCHEMA
        assert rec["claim_verdict"] == "NO_CLAIM_ALLOWED"

    def test_build_record_role_non_resolu_NEGATIF(self):
        """Test NÉGATIF construit (trace) : un `capability_role` que le
        registry ne résout à AUCUN modèle doit produire UNRESOLVED, jamais
        planter ni inventer une déclaration."""
        rec = ro.build_reasoning_observability_record(
            "x", "run-x", {"capability_role": "role_n_existe_pas"})
        assert rec["declared_status"] == "UNRESOLVED"
        assert rec["declared"] is None

    def test_append_sign_read_verify_roundtrip(self, tmp_path):
        ro.append_reasoning_observability_record("s4-archi", "run-y", self.CONTRACT,
                                                   run_dir=tmp_path)
        recs = ro.read_reasoning_observability_records(tmp_path, "s4-archi")
        assert len(recs) == 1
        assert ro.verify_reasoning_observability_record(recs[0]) is True

    def test_read_sur_fichier_absent_rend_tuple_vide(self, tmp_path):
        assert ro.read_reasoning_observability_records(tmp_path, "jamais-ecrit") == ()

    def test_read_ignore_ligne_corrompue(self, tmp_path):
        path = ro.reasoning_observability_manifest_path(tmp_path, "s4-archi")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("pas du json\n", encoding="utf-8")
        assert ro.read_reasoning_observability_records(tmp_path, "s4-archi") == ()
