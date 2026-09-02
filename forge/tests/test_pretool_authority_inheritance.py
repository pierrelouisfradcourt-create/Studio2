"""Oracle de la couche 2 du hook PreToolUse : héritage d'autorité de délégation.

Règle sous test (`.claude/hooks/pretool_forge_guard.py`) :

    effective_authority(agent) = capabilities(type) ∩ permissions(control-plane)
    délégation valide ⟺ effective_authority(enfant) ⊆ effective_authority(parent)

Cas A→L du charter. ISOLATION STRICTE : toute la lignée (transcripts, sidecars
`.meta.json`) et le control-plane sous test sont fabriqués sous `tmp_path`.
Aucune écriture dans les transcripts réels, les `.meta.json` réels, RUN_INDEX.md
ni aucun artefact de production. Les DEUX sources qui ne sont jamais écrites —
`.claude/agents/` et `.claude/hooks/agent_authority_allowlist_v0.json` — sont
lues À LEUR VRAIE PLACE, volontairement : ce sont les producteurs réels des
capacités, et les tester par copie testerait la copie.

Injection de chemins : `AuthorityConfig` est passé explicitement. Une cible
invalide lève `AuthorityConfigError` (testé) — jamais de repli silencieux.

claim_verdict: NO_CLAIM_ALLOWED
"""
from __future__ import annotations

import importlib.util
import io
import json
import sys
import time
import uuid
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
HOOK_PATH = REPO_ROOT / ".claude" / "hooks" / "pretool_forge_guard.py"
REAL_AGENTS_DIR = REPO_ROOT / ".claude" / "agents"
REAL_ALLOWLIST = REPO_ROOT / ".claude" / "hooks" / "agent_authority_allowlist_v0.json"


def _load_hook():
    spec = importlib.util.spec_from_file_location("pretool_forge_guard_authority_under_test",
                                                  HOOK_PATH)
    # EXACTEMENT le patron de test_spawn_authority_repair.py : module chargé SANS
    # enregistrement dans sys.modules. C'est le patron réel des consommateurs du
    # hook, donc c'est celui sous lequel il doit rester chargeable.
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


mod = _load_hook()


# --- fabrique de lignée sous tmp_path ----------------------------------------
class Session:
    """Réplique EXACTE de la topologie mesurée le 2026-08-09 :
        <projects>/<session_uuid>.jsonl
        <projects>/<session_uuid>/subagents/agent-<id>.jsonl
        <projects>/<session_uuid>/subagents/agent-<id>.meta.json
    """

    def __init__(self, root: Path):
        self.sid = str(uuid.uuid4())
        self.projects = root / "projects"
        self.projects.mkdir(parents=True, exist_ok=True)
        self.main = self.projects / f"{self.sid}.jsonl"
        self.main.write_text('{"type":"user"}\n', encoding="utf-8")
        self.subagents = self.projects / self.sid / "subagents"
        self.subagents.mkdir(parents=True, exist_ok=True)

    def agent(self, agent_id: str, meta, transcript: str = '{"type":"assistant"}\n') -> Path:
        """`meta` = dict (écrit en JSON) ou str brute (pour tester la corruption).
        `meta=None` -> aucun sidecar (parent introuvable)."""
        tp = self.subagents / f"agent-{agent_id}.jsonl"
        tp.write_text(transcript, encoding="utf-8")
        if meta is not None:
            raw = meta if isinstance(meta, str) else json.dumps(meta)
            (self.subagents / f"agent-{agent_id}.meta.json").write_text(raw, encoding="utf-8")
        return tp


@pytest.fixture
def session(tmp_path):
    return Session(tmp_path)


@pytest.fixture
def settings(tmp_path):
    """Control-plane sous test — fixture, JAMAIS le vrai .claude/settings.json."""
    def _write(deny):
        p = tmp_path / f"settings_{uuid.uuid4().hex[:8]}.json"
        p.write_text(json.dumps({"permissions": {"deny": deny}}), encoding="utf-8")
        return p
    return _write


@pytest.fixture
def cfg(settings):
    def _cfg(deny=None):
        return mod.AuthorityConfig(
            agents_dir=REAL_AGENTS_DIR,
            allowlist_path=REAL_ALLOWLIST,
            settings_paths=(settings(deny or []),),
        )
    return _cfg


def payload(transcript: Path | str, child_type=..., tool="Task", tool_use_id="toolu_TEST"):
    ti = {"prompt": "p", "description": "d"}
    if child_type is not ...:
        ti["subagent_type"] = child_type
    return {
        "hook_event_name": "PreToolUse",
        "tool_name": tool,
        "tool_input": ti,
        "tool_use_id": tool_use_id,
        "transcript_path": str(transcript),
        "session_id": "s",
    }


def _decide(session, cfg, parent_type, child_type=..., **kw):
    tp = session.agent("a" + uuid.uuid4().hex[:16],
                       {"agentType": parent_type, "description": "x",
                        "toolUseId": "toolu_PARENT", "spawnDepth": 1})
    return mod.evaluate_inheritance(payload(tp, child_type, **kw), cfg)


def _show(r):
    """Preuve lisible imposée par le charter : input · parent · types · autorités
    · décision · raison."""
    # ensure_ascii=True : la console Windows de la suite est en cp1252 ; une preuve
    # qui plante a l'affichage n'est pas une preuve.
    return json.dumps(r, ensure_ascii=True, indent=2)


# =============================================================================
# A — Explore -> general-purpose : DENY (élargissement d'autorité)
# =============================================================================
def test_A_explore_vers_general_purpose_est_refuse(session, cfg):
    r = _decide(session, cfg(), "Explore", "general-purpose")
    assert r["decision"] == "DENY", _show(r)
    assert r["reason_kind"] == "AUTHORITY_ESCALATION", _show(r)
    assert r["parent_type"] == "Explore" and r["child_type"] == "general-purpose"
    # l'autorité du parent est bien amputée des outils d'écriture/spawn
    assert "Write" in r["parent_authority"] and "Agent" in r["parent_authority"]
    assert r["child_authority"] == "ALL_TOOLS"
    print(_show(r))


# =============================================================================
# B — general-purpose -> general-purpose : ALLOW (autorité égale)
# =============================================================================
def test_B_general_purpose_vers_general_purpose_est_autorise(session, cfg):
    r = _decide(session, cfg(), "general-purpose", "general-purpose")
    assert r["decision"] == "ALLOW", _show(r)
    assert r["reason_kind"] == "SUBSET"
    assert r["parent_authority"] == r["child_authority"] == "ALL_TOOLS"
    print(_show(r))


# =============================================================================
# C — general-purpose -> Explore : ALLOW (réduction stricte)
# =============================================================================
def test_C_general_purpose_vers_explore_est_autorise(session, cfg):
    r = _decide(session, cfg(), "general-purpose", "Explore")
    assert r["decision"] == "ALLOW", _show(r)
    assert r["parent_authority"] == "ALL_TOOLS"
    assert "Write" in r["child_authority"]
    print(_show(r))


# =============================================================================
# D — type d'enfant inconnu : DENY (allowlist auto-limitante)
# =============================================================================
def test_D_type_enfant_inconnu_est_refuse(session, cfg):
    r = _decide(session, cfg(), "general-purpose", "agent-qui-nexiste-pas")
    assert r["decision"] == "DENY", _show(r)
    assert r["reason_kind"] == "CHILD_AUTHORITY_UNKNOWN", _show(r)
    assert r["child_authority"] == "UNKNOWN"
    print(_show(r))


def test_D2_agent_custom_non_enregistre_est_refuse(session, cfg):
    """`economy-designer.md` existe sur disque mais n'a pas de `description` : il
    n'est PAS enregistré par le harnais (absent de la liste de types du runtime).
    created != registered => UNKNOWN => DENY."""
    assert (REAL_AGENTS_DIR / "economy-designer.md").is_file()
    r = _decide(session, cfg(), "general-purpose", "economy-designer")
    assert r["decision"] == "DENY" and r["reason_kind"] == "CHILD_AUTHORITY_UNKNOWN", _show(r)
    assert "NON enregistré" in r["reason"]


# =============================================================================
# E — parent introuvable : DENY
# =============================================================================
def test_E_parent_introuvable_est_refuse(session, cfg):
    tp = session.agent("aORPHELIN", meta=None)  # transcript présent, sidecar absent
    r = mod.evaluate_inheritance(payload(tp, "Explore"), cfg())
    assert r["decision"] == "DENY", _show(r)
    assert r["reason_kind"] == "PARENT_NOT_FOUND", _show(r)
    assert r["parent_authority"] == "UNKNOWN" and r["child_authority"] == "UNKNOWN"
    print(_show(r))


# =============================================================================
# F — enfant inconnu (subagent_type absent) : DENY, aucun défaut silencieux
# =============================================================================
def test_F_subagent_type_absent_est_refuse(session, cfg):
    r = _decide(session, cfg(), "general-purpose")  # child_type non fourni
    assert r["decision"] == "DENY", _show(r)
    assert r["reason_kind"] == "CHILD_TYPE_MISSING", _show(r)
    assert r["child_authority"] == "UNKNOWN"
    # le parent, lui, a bien été résolu : le refus porte sur l'enfant, pas sur la lignée
    assert r["parent_authority"] == "ALL_TOOLS"
    print(_show(r))


def test_F2_subagent_type_vide_est_refuse(session, cfg):
    r = _decide(session, cfg(), "general-purpose", "")
    assert r["decision"] == "DENY" and r["reason_kind"] == "CHILD_AUTHORITY_UNKNOWN", _show(r)


# =============================================================================
# G — transcript absent : DENY
# =============================================================================
def test_G_transcript_inexistant_est_refuse(session, cfg, tmp_path):
    r = mod.evaluate_inheritance(payload(tmp_path / "nulle-part.jsonl", "Explore"), cfg())
    assert r["decision"] == "DENY" and r["reason_kind"] == "PARENT_NOT_FOUND", _show(r)
    print(_show(r))


def test_G2_transcript_path_absent_du_payload_est_refuse(cfg):
    p = payload("", "Explore")
    p.pop("transcript_path")
    r = mod.evaluate_inheritance(p, cfg())
    assert r["decision"] == "DENY" and r["reason_kind"] == "PARENT_NOT_FOUND", _show(r)


def test_G3_forme_de_transcript_non_reconnue_est_refusee(tmp_path, cfg):
    bizarre = tmp_path / "pas-un-transcript.log"
    bizarre.write_text("x", encoding="utf-8")
    r = mod.evaluate_inheritance(payload(bizarre, "Explore"), cfg())
    assert r["decision"] == "DENY" and r["reason_kind"] == "PARENT_UNRECOGNIZED", _show(r)


# =============================================================================
# H — sidecar de lignée corrompu : DENY (jamais interprété « au mieux »)
# =============================================================================
def test_H_sidecar_corrompu_est_refuse(session, cfg):
    tp = session.agent("aCORROMPU", meta="{ ceci n'est pas du JSON")
    r = mod.evaluate_inheritance(payload(tp, "Explore"), cfg())
    assert r["decision"] == "DENY" and r["reason_kind"] == "PARENT_CORRUPT", _show(r)
    print(_show(r))


def test_H2_sidecar_sans_agentType_est_refuse(session, cfg):
    tp = session.agent("aSANSTYPE", {"description": "x", "spawnDepth": 1})
    r = mod.evaluate_inheritance(payload(tp, "Explore"), cfg())
    assert r["decision"] == "DENY" and r["reason_kind"] == "PARENT_CORRUPT", _show(r)


def test_H3_sidecar_non_objet_est_refuse(session, cfg):
    tp = session.agent("aLISTE", "[1, 2, 3]")
    r = mod.evaluate_inheritance(payload(tp, "Explore"), cfg())
    assert r["decision"] == "DENY" and r["reason_kind"] == "PARENT_CORRUPT", _show(r)


# =============================================================================
# I — capacité du type interdite par settings.json : hors autorité effective,
#     puis child ⊄ parent => DENY
# =============================================================================
def test_I_deny_control_plane_retire_la_capacite_puis_refus(session, cfg):
    """Deux assertions distinctes sur le MÊME cas :
    1. `WebSearch` est déclaré par le control-plane (règle SANS argument) : il
       disparaît de l'autorité effective des DEUX agents, alors qu'aucun des deux
       types ne l'interdit — preuve que l'étape ∩ permissions a bien tourné.
    2. `Write(.claude/settings.json)` est une règle À PORTÉE DE CHEMIN : elle ne
       supprime PAS la capacité `Write` (sinon parent et enfant seraient tous deux
       amputés et le test ne mesurerait plus rien).
    3. La décision reste DENY parce que l'enfant (general-purpose, ALL) déborde le
       parent (ai-programmer, ALL - {Write, Edit}).
    """
    c = cfg(["WebSearch", "Write(.claude/settings.json)", "Bash(rm -rf *)"])
    r = _decide(session, c, "ai-programmer", "general-purpose")

    assert r["global_denies"] == ["WebSearch"], _show(r)          # portée-chemin ignorée
    assert "WebSearch" in r["parent_authority"], _show(r)          # retiré des deux côtés
    assert "WebSearch" in r["child_authority"], _show(r)
    assert "Write" in r["parent_authority"] and "Edit" in r["parent_authority"]
    assert "Write" not in r["child_authority"].replace("WebSearch", "")

    assert r["decision"] == "DENY" and r["reason_kind"] == "AUTHORITY_ESCALATION", _show(r)
    print(_show(r))


def test_I2_capacite_du_type_absente_apres_deny_global(session, cfg):
    """Vérification directe de l'égalité du modèle : une capacité présente dans le
    type mais interdite globalement ne fait PAS partie de l'autorité effective."""
    c = cfg(["WebSearch"])
    allowlist = c.load_allowlist()
    denies = mod.global_tool_denies(c)
    caps = mod.capabilities_for_type("general-purpose", c, allowlist)
    eff = mod.effective_authority("general-purpose", c, allowlist, denies)
    assert caps.describe() == "ALL_TOOLS"
    assert eff.describe() == "ALL_TOOLS - {WebSearch}"
    # et pour un type à capacités FINIES, la capacité est retirée de l'ensemble
    c2 = cfg(["Edit"])
    eff2 = mod.effective_authority("statusline-setup", c2, c2.load_allowlist(),
                                   mod.global_tool_denies(c2))
    assert eff2.describe() == "{Read}"


# =============================================================================
# J — réduction d'autorité : ALLOW
# =============================================================================
def test_J_reduction_d_autorite_est_autorisee(session, cfg):
    r = _decide(session, cfg(), "general-purpose", "ai-programmer")
    assert r["decision"] == "ALLOW", _show(r)
    assert r["child_authority"] == "ALL_TOOLS - {Edit, Write}"
    print(_show(r))


def test_J2_reduction_entre_deux_agents_custom_identiques(session, cfg):
    r = _decide(session, cfg(), "ai-programmer", "qa-tester")
    assert r["decision"] == "ALLOW", _show(r)


def test_J3_elargissement_depuis_un_agent_custom_est_refuse(session, cfg):
    r = _decide(session, cfg(), "qa-tester", "claude")
    assert r["decision"] == "DENY" and r["reason_kind"] == "AUTHORITY_ESCALATION", _show(r)


# =============================================================================
# K — lignée ambiguë : DENY
# =============================================================================
def test_K_profondeur_2_sans_parentAgentId_est_refusee(session, cfg):
    tp = session.agent("aORPHELIN2", {"agentType": "general-purpose", "spawnDepth": 2})
    r = mod.evaluate_inheritance(payload(tp, "Explore"), cfg())
    assert r["decision"] == "DENY" and r["reason_kind"] == "PARENT_AMBIGUOUS", _show(r)
    print(_show(r))


def test_K2_lignee_bouclee_est_refusee(session, cfg):
    """Un cycle est toujours REFUSÉ, mais mesure honnête de QUI l'attrape :
    l'invariant de profondeur (elle doit décroître de 1) le voit avant le
    détecteur de cycle. Le jeu `seen` reste une borne de sûreté — il ne peut
    jamais être le seul rempart tant que l'invariant de profondeur tient."""
    session.agent("aX", {"agentType": "general-purpose", "spawnDepth": 2, "parentAgentId": "aY"})
    session.agent("aY", {"agentType": "general-purpose", "spawnDepth": 2, "parentAgentId": "aX"})
    r = mod.evaluate_inheritance(payload(session.subagents / "agent-aX.jsonl", "Explore"), cfg())
    assert r["decision"] == "DENY" and r["reason_kind"] == "PARENT_AMBIGUOUS", _show(r)
    assert "profondeur incoh" in r["reason"], _show(r)


def test_K3_profondeur_qui_ne_decroit_pas_est_refusee(session, cfg):
    session.agent("aP", {"agentType": "general-purpose", "spawnDepth": 3})
    tp = session.agent("aC", {"agentType": "general-purpose", "spawnDepth": 2,
                              "parentAgentId": "aP"})
    r = mod.evaluate_inheritance(payload(tp, "Explore"), cfg())
    assert r["decision"] == "DENY" and r["reason_kind"] == "PARENT_AMBIGUOUS", _show(r)


def test_K4_profondeur_1_qui_declare_un_parent_est_refusee(session, cfg):
    tp = session.agent("aD1", {"agentType": "general-purpose", "spawnDepth": 1,
                               "parentAgentId": "aZ"})
    r = mod.evaluate_inheritance(payload(tp, "Explore"), cfg())
    assert r["decision"] == "DENY" and r["reason_kind"] == "PARENT_AMBIGUOUS", _show(r)


def test_K5_chaine_valide_de_profondeur_3_intersecte_toute_la_lignee(session, cfg):
    """Lignée réelle observée (profondeur max mesurée = 3). L'autorité du parent
    est l'intersection de TOUTE la chaîne : un ancêtre Explore borne un
    descendant general-purpose."""
    session.agent("aG1", {"agentType": "Explore", "spawnDepth": 1})
    session.agent("aG2", {"agentType": "general-purpose", "spawnDepth": 2,
                          "parentAgentId": "aG1"})
    tp = session.agent("aG3", {"agentType": "general-purpose", "spawnDepth": 3,
                               "parentAgentId": "aG2"})
    r = mod.evaluate_inheritance(payload(tp, "general-purpose"), cfg())
    assert r["parent_chain"] == ["general-purpose", "general-purpose", "Explore"], _show(r)
    assert r["decision"] == "DENY" and r["reason_kind"] == "AUTHORITY_ESCALATION", _show(r)
    r2 = mod.evaluate_inheritance(payload(tp, "Explore"), cfg())
    assert r2["decision"] == "ALLOW", _show(r2)


# =============================================================================
# L — performance : la résolution + décision reste sous 10 ms
# =============================================================================
def test_L_performance_sous_10ms(session, cfg):
    session.agent("aP1", {"agentType": "Explore", "spawnDepth": 1})
    session.agent("aP2", {"agentType": "general-purpose", "spawnDepth": 2,
                          "parentAgentId": "aP1"})
    tp = session.agent("aP3", {"agentType": "general-purpose", "spawnDepth": 3,
                               "parentAgentId": "aP2"})
    c = cfg()
    p = payload(tp, "Explore")
    mod.evaluate_inheritance(p, c)  # warm-up (cache FS)
    n = 50
    t0 = time.perf_counter()
    for _ in range(n):
        mod.evaluate_inheritance(p, c)
    moyenne_ms = (time.perf_counter() - t0) / n * 1000
    print(f"authority_inheritance: {moyenne_ms:.3f} ms/décision (lignée profondeur 3)")
    assert moyenne_ms < 10.0, f"{moyenne_ms:.3f} ms >= 10 ms"


# =============================================================================
# Session principale = racine de lignée
# =============================================================================
def test_session_principale_est_la_racine(session, cfg):
    r = mod.evaluate_inheritance(payload(session.main, "Explore"), cfg())
    assert r["decision"] == "ALLOW", _show(r)
    assert r["parent_kind"] == "main_session" and r["parent_type"] == "__main_session__"
    assert r["parent_chain"] == []


def test_session_principale_reste_bornee_par_le_control_plane(session, cfg):
    r = mod.evaluate_inheritance(payload(session.main, "general-purpose"), cfg(["WebSearch"]))
    assert r["parent_authority"] == "ALL_TOOLS - {WebSearch}"
    assert r["decision"] == "ALLOW", _show(r)


# =============================================================================
# Corroboration tool_use_id — ADVISORY, jamais décisionnelle
# =============================================================================
def test_tool_use_id_corrobore_sans_jamais_decider(session, cfg):
    tp = session.agent("aTUID", {"agentType": "general-purpose", "spawnDepth": 1},
                       transcript='{"tool_use_id":"toolu_PRESENT"}\n')
    present = mod.evaluate_inheritance(payload(tp, "Explore", tool_use_id="toolu_PRESENT"), cfg())
    absent = mod.evaluate_inheritance(payload(tp, "Explore", tool_use_id="toolu_JAMAIS"), cfg())
    assert present["tool_use_id_corroboration"] == "PRESENT"
    assert absent["tool_use_id_corroboration"] == "ABSENT"
    # l'absence de corroboration ne change PAS la décision (le transcript peut ne
    # pas être encore vidé sur disque au moment du hook)
    assert present["decision"] == absent["decision"] == "ALLOW"


# =============================================================================
# Algèbre d'autorité — les 4 combinaisons d'inclusion
# =============================================================================
def test_algebre_inclusion_quatre_combinaisons():
    A = mod.Authority
    assert A.all_except(["Write"]).is_subset_of(A.all_except([]))
    assert not A.all_except([]).is_subset_of(A.all_except(["Write"]))
    assert A.only(["Read"]).is_subset_of(A.all_except(["Write"]))
    assert not A.only(["Write"]).is_subset_of(A.all_except(["Write"]))
    assert not A.all_except([]).is_subset_of(A.only(["Read"]))  # co-fini ⊄ fini
    assert A.only(["Read"]).is_subset_of(A.only(["Read", "Grep"]))


# =============================================================================
# Injection de chemins : cible invalide => ERREUR EXPLICITE, jamais un repli
# =============================================================================
def test_cible_invalide_leve_une_erreur_explicite(tmp_path, settings):
    bad = mod.AuthorityConfig(agents_dir=tmp_path / "absent",
                              allowlist_path=REAL_ALLOWLIST,
                              settings_paths=(settings([]),))
    with pytest.raises(mod.AuthorityConfigError, match="agents_dir introuvable"):
        bad.validate()
    bad2 = mod.AuthorityConfig(agents_dir=REAL_AGENTS_DIR,
                               allowlist_path=tmp_path / "absent.json",
                               settings_paths=(settings([]),))
    with pytest.raises(mod.AuthorityConfigError, match="allowlist builtin introuvable"):
        bad2.validate()


def test_erreur_de_config_donne_DENY_jamais_ALLOW(session, tmp_path, settings):
    bad = mod.AuthorityConfig(agents_dir=tmp_path / "absent",
                              allowlist_path=REAL_ALLOWLIST,
                              settings_paths=(settings([]),))
    tp = session.agent("aCFG", {"agentType": "general-purpose", "spawnDepth": 1})
    r = mod.evaluate_inheritance(payload(tp, "Explore"), bad)
    assert r["decision"] == "DENY" and r["reason_kind"] == "CONFIG_ERROR", _show(r)


# =============================================================================
# Périmètre : la couche ne juge QUE Task/Agent
# =============================================================================
@pytest.mark.parametrize("tool", ["Bash", "Write", "Read", "PowerShell"])
def test_hors_task_agent_la_couche_ne_juge_pas(session, cfg, tool):
    r = mod.evaluate_inheritance(payload(session.main, "general-purpose", tool=tool), cfg())
    assert r["decision"] == "NOT_APPLICABLE" and r["reason_kind"] == "OUT_OF_SCOPE"


def test_outil_Agent_est_couvert_comme_Task(session, cfg):
    r = _decide(session, cfg(), "Explore", "general-purpose", tool="Agent")
    assert r["decision"] == "DENY" and r["reason_kind"] == "AUTHORITY_ESCALATION"


# =============================================================================
# Témoin d'activation
# =============================================================================
def test_temoin_par_defaut_off(tmp_path, monkeypatch):
    monkeypatch.delenv(mod.WITNESS_ENV, raising=False)
    assert mod.witness_mode(tmp_path) == "off"


@pytest.mark.parametrize("valeur,attendu", [
    ("off", "off"), ("observe", "observe"), ("enforce", "enforce"),
    ("ENFORCE", "enforce"), ("nimportequoi", "off"), ("", "off"),
])
def test_temoin_par_variable_d_environnement(tmp_path, monkeypatch, valeur, attendu):
    monkeypatch.setenv(mod.WITNESS_ENV, valeur)
    assert mod.witness_mode(tmp_path) == attendu


def test_temoin_par_fichier_et_reversibilite(tmp_path, monkeypatch):
    monkeypatch.delenv(mod.WITNESS_ENV, raising=False)
    w = tmp_path / ".claude" / "hooks" / "authority_witness.json"
    w.parent.mkdir(parents=True)
    w.write_text(json.dumps({"mode": "enforce"}), encoding="utf-8")
    assert mod.witness_mode(tmp_path) == "enforce"
    w.write_text("{ corrompu", encoding="utf-8")
    assert mod.witness_mode(tmp_path) == "off"   # témoin illisible => non activé
    w.unlink()
    assert mod.witness_mode(tmp_path) == "off"   # suppression => réversible


def test_temoin_absent_du_depot(monkeypatch):
    """État livré : le témoin n'existe pas, donc la couche 2 est INACTIVE en
    production tant que Pierre ne l'arme pas."""
    monkeypatch.delenv(mod.WITNESS_ENV, raising=False)
    assert not (REPO_ROOT / ".claude" / "hooks" / "authority_witness.json").exists()
    assert mod.witness_mode(REPO_ROOT) == "off"


# =============================================================================
# Bout en bout par main() — non-régression de la couche 1 comprise
# =============================================================================
def _run_main(monkeypatch, data, mode, cfg_obj=None):
    monkeypatch.setattr(sys, "stdin", io.StringIO(json.dumps(data)))
    monkeypatch.setenv(mod.WITNESS_ENV, mode)
    if cfg_obj is not None:
        monkeypatch.setattr(mod.AuthorityConfig, "from_repo_root",
                            staticmethod(lambda root: cfg_obj))
    return mod.main()


def test_main_off_ne_bloque_pas_une_escalade(session, cfg, monkeypatch, capsys):
    """Témoin `off` : la couche 2 n'est même pas évaluée -> comportement
    strictement identique à l'état commité."""
    c = cfg()
    tp = session.agent("aM1", {"agentType": "Explore", "spawnDepth": 1})
    assert _run_main(monkeypatch, payload(tp, "general-purpose"), "off", c) == 0
    assert "authority-gate" not in capsys.readouterr().err


def test_main_observe_journalise_sans_bloquer(session, cfg, monkeypatch, capsys):
    c = cfg()
    tp = session.agent("aM2", {"agentType": "Explore", "spawnDepth": 1})
    assert _run_main(monkeypatch, payload(tp, "general-purpose"), "observe", c) == 0
    err = capsys.readouterr().err
    assert "[authority-gate] DENY (AUTHORITY_ESCALATION)" in err


def test_main_enforce_bloque_l_escalade(session, cfg, monkeypatch, capsys):
    c = cfg()
    tp = session.agent("aM3", {"agentType": "Explore", "spawnDepth": 1})
    assert _run_main(monkeypatch, payload(tp, "general-purpose"), "enforce", c) == 2
    assert "[authority-gate] DENY" in capsys.readouterr().err


def test_main_enforce_laisse_passer_une_reduction(session, cfg, monkeypatch):
    c = cfg()
    tp = session.agent("aM4", {"agentType": "general-purpose", "spawnDepth": 1})
    assert _run_main(monkeypatch, payload(tp, "Explore"), "enforce", c) == 0


def test_main_enforce_laisse_passer_general_purpose_vers_general_purpose(session, cfg, monkeypatch):
    c = cfg()
    tp = session.agent("aM5", {"agentType": "general-purpose", "spawnDepth": 1})
    assert _run_main(monkeypatch, payload(tp, "general-purpose"), "enforce", c) == 0


def test_main_enforce_ne_touche_pas_les_autres_outils(session, cfg, monkeypatch):
    c = cfg()
    data = payload(session.main, "general-purpose", tool="Bash")
    assert _run_main(monkeypatch, data, "enforce", c) == 0


def test_main_couche1_reste_prioritaire_et_fail_closed(session, cfg, monkeypatch, capsys):
    """Périmètre Forge SANS dispatch validé : la couche 1 refuse, et elle refuse
    AVANT que la couche 2 ait quoi que ce soit à dire — y compris sur une
    délégation que la couche 2 aurait autorisée (general-purpose -> Explore)."""
    c = cfg()
    tp = session.agent("aM6", {"agentType": "general-purpose", "spawnDepth": 1})
    data = payload(tp, "Explore")
    data["tool_input"]["prompt"] = "FORGE_DISPATCH:s9-build:run-inexistant:1"
    assert _run_main(monkeypatch, data, "enforce", c) == 2
    err = capsys.readouterr().err
    assert "[forge-gate] spawn refusé" in err
    assert "[authority-gate]" not in err


def test_le_hook_reste_chargeable_hors_sys_modules():
    """RÉGRESSION MESURÉE : la première version de cette couche utilisait
    `@dataclass`. `@dataclass` résout ses annotations via
    `sys.modules[cls.__module__]` — or `test_spawn_authority_repair.py` charge le
    hook par `module_from_spec` SANS l'enregistrer dans `sys.modules`, ce qui
    faisait lever `AttributeError: 'NoneType' object has no attribute '__dict__'`
    À L'IMPORT : 3 tests préexistants cassés, et surtout un hook qui ne se charge
    plus. Ce test verrouille la propriété dans le sens qui compte : chargeable
    hors sys.modules, et les trois classes instanciables."""
    nom = "pretool_forge_guard_hors_sys_modules"
    assert nom not in sys.modules
    spec = importlib.util.spec_from_file_location(nom, HOOK_PATH)
    frais = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(frais)          # levait AttributeError avec @dataclass
    assert nom not in sys.modules
    assert frais.Authority.all_except(["Write"]).describe() == "ALL_TOOLS - {Write}"
    assert frais.Caller("main_session", "", (), HOOK_PATH).kind == "main_session"
    assert frais.AuthorityConfig.from_repo_root(REPO_ROOT).agents_dir == REAL_AGENTS_DIR


def test_message_stderr_encodable_en_cp1252(session, cfg):
    """Le hook ecrit sur stderr, que la console Windows decode en cp1252. Un
    message non encodable = un hook qui LEVE au lieu de juger (mesure : les
    symboles mathematiques d'ensemble plantaient a l'affichage)."""
    c = cfg(["WebSearch"])
    tp = session.agent("aENC", {"agentType": "Explore", "spawnDepth": 1})
    cas = [
        payload(tp, "general-purpose"),                  # escalade
        payload(tp, "Explore"),                          # subset
        payload(tp, "type-inconnu"),                     # enfant UNKNOWN
        payload(session.subagents / "agent-aABSENT.jsonl", "Explore"),  # parent absent
    ]
    for p in cas:
        msg = mod._format(mod.evaluate_inheritance(p, c))
        msg.encode("cp1252")  # lève si un caractère n'est pas encodable


def test_main_stdin_illisible_reste_neutre(monkeypatch):
    monkeypatch.setattr(sys, "stdin", io.StringIO("pas du json"))
    monkeypatch.setenv(mod.WITNESS_ENV, "enforce")
    assert mod.main() == 0
