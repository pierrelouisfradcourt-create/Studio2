"""Oracle du chantier n1-findings-redteam-audibles.

Diagnostic (re-vérifié avant ce fichier, cf. rapport de dispatch) : la plomberie
AVAL (driver.py -> verdict.py `redteam_advisory`) est correcte et déjà couverte
par `forge.tests.test_aggregate_verdict` ; le canal était mort À SA SOURCE —
`forge.run_real.claude_executor` ne renseignait JAMAIS `res["findings"]` pour
l'étape s11-redteam-code (`_claude_call_raw` ne rend que
{ok, output, tokens, duration_s, cost_usd}). Preuve : sur pong_r2,
`redteam_advisory: []` dans le verdict signé alors que
`EVIDENCE/runs/pong/rapport_redteam_code.md` (14 382 octets, 6 failles) existe
sur disque.

Ce fichier couvre :
  (a) une section de findings structurée produit une liste NON VIDE ;
  (b) un rapport SANS section (tous les rapports historiques, dont pong_r2 réel)
      produit une liste vide + une note explicite, sans crash ;
  (c) une entrée malformée est rejetée SEULE (jamais tout-ou-rien) ;
  (d) le câblage dans `claude_executor` n'alimente `res["findings"]` QUE pour
      s11-redteam-code — aucune autre étape n'est affectée (non-régression) ;
  (e) `res["blocked"]` n'est JAMAIS posé par ce chantier (garde-fou promotion —
      cf. test_aggregate_verdict pour la preuve bout-en-bout côté verdict).

NO_CLAIM_ALLOWED — aucun appel réseau/claude réel.
"""
from dataclasses import dataclass
from pathlib import Path

import forge.run_real as run_real

REPO_ROOT = Path(__file__).resolve().parents[2]


@dataclass
class FakePayload:
    etape: str
    model: str = "haiku"
    prompt: str = "PROMPT CONTRAT"


def _context(run_dir, **extra):
    ctx = {
        "run_id": "run-1",
        "project": "proj",
        "run_dir": str(run_dir),
        "model_override": None,
        "dispatch_marker": "FORGE_DISPATCH:x:run-1",
        "attempt": 1,
        "premortem": [],
    }
    ctx.update(extra)
    return ctx


def _fenced(findings) -> str:
    import json
    return ("Prose du rapport red-team, inchangée.\n\n```json\n"
            + json.dumps({"findings": findings}) + "\n```")


# --- (a) section structurée valide -> liste NON VIDE --------------------------------

def test_bloc_valide_deux_findings_produit_deux_entrees_formatees():
    output = _fenced([
        {"angle": "collision balayée", "faille": "point fantôme au mauvais camp",
         "severite": "HIGH", "reproduction": "node repro_f1.mjs"},
        {"angle": "rebond vertical", "faille": "état hors-domaine possible",
         "severite": "MEDIUM", "reproduction": "isValidState(ns) === false"},
    ])
    findings, note = run_real.extract_redteam_findings(output)
    assert note == ""
    assert len(findings) == 2
    assert "HIGH" in findings[0] and "collision balayée" in findings[0]
    assert "point fantôme au mauvais camp" in findings[0]
    assert "repro_f1.mjs" in findings[0]
    assert "MEDIUM" in findings[1]


def test_bloc_avec_une_seule_faille():
    output = _fenced([{"angle": "a", "faille": "b", "severite": "low",
                       "reproduction": "r"}])
    findings, note = run_real.extract_redteam_findings(output)
    assert note == ""
    assert len(findings) == 1
    assert "LOW" in findings[0]  # sévérité normalisée en majuscule


# --- (b) rapport SANS section structurée -> liste vide + note, jamais un crash ------

def test_rapport_sans_bloc_json_liste_vide_avec_note():
    output = "Rapport prose classique, sans aucun bloc ```json``` de findings."
    findings, note = run_real.extract_redteam_findings(output)
    assert findings == []
    assert note != ""
    assert "aucune section" in note


def test_rapport_pong_r2_reel_historique_liste_vide_sans_crash():
    """Le VRAI rapport pong_r2 (14 Ko, 6 failles en prose, AUCUN bloc JSON de
    findings — c'est justement le cas que ce chantier corrige pour l'AVENIR,
    pas en rétro-actif). Preuve terrain que l'extraction ne casse jamais sur du
    texte réel volumineux et ne fabrique aucune entrée par accident."""
    # Run pong_r2 ARCHIVÉ en `pong_r2_ref` le 2026-07-27 (libération du run_dir, dérivé de
    # --project). On lit la référence figée, jamais le run courant : un test qui pointe un
    # dossier de run vivant casse au premier archivage.
    rapport = REPO_ROOT / "EVIDENCE" / "runs" / "pong_r2_ref" / "rapport_redteam_code.md"
    assert rapport.exists(), "fixture réelle absente — le rapport pong_r2 doit exister"
    output = rapport.read_text(encoding="utf-8")
    findings, note = run_real.extract_redteam_findings(output)
    assert findings == []          # comportement honnête : rien à inventer
    assert note != ""              # jamais un silence total


def test_bloc_present_mais_findings_absent_liste_vide_avec_note():
    output = 'Prose.\n\n```json\n{"autre_champ": 1}\n```'
    findings, note = run_real.extract_redteam_findings(output)
    assert findings == []
    assert "'findings'" in note


def test_bloc_present_findings_liste_vide_explicite():
    output = _fenced([])
    findings, note = run_real.extract_redteam_findings(output)
    assert findings == []
    assert "vide" in note


def test_findings_pas_une_liste_liste_vide_avec_note():
    output = 'Prose.\n\n```json\n{"findings": "pas une liste"}\n```'
    findings, note = run_real.extract_redteam_findings(output)
    assert findings == []
    assert "n'est pas une liste" in note


def test_json_malforme_dans_le_bloc_ne_crash_pas():
    output = 'Prose.\n\n```json\n{"findings": [invalid json here\n```'
    findings, note = run_real.extract_redteam_findings(output)
    assert findings == []
    assert note != ""


# --- (c) entrée malformée rejetée SEULE (jamais tout-ou-rien) -----------------------

def test_une_entree_malformee_rejetee_les_autres_survivent():
    output = _fenced([
        {"angle": "ok1", "faille": "f1", "severite": "HIGH", "reproduction": "r1"},
        {"angle": "incomplet"},                                   # malformée
        {"angle": "ok2", "faille": "f2", "severite": "LOW", "reproduction": "r2"},
        {"angle": "", "faille": "f3", "severite": "LOW", "reproduction": "r3"},  # vide
    ])
    findings, note = run_real.extract_redteam_findings(output)
    assert len(findings) == 2
    assert any("f1" in f for f in findings)
    assert any("f2" in f for f in findings)
    assert "2 entrée(s) rejetée(s)" in note


def test_toutes_les_entrees_malformees_liste_vide_avec_note():
    output = _fenced([{"angle": "seul"}, {"faille": "sans angle"}])
    findings, note = run_real.extract_redteam_findings(output)
    assert findings == []
    assert "AUCUNE" in note


# --- (d) câblage claude_executor : QUE s11-redteam-code est affecté ------------------

def test_executor_s11_alimente_res_findings(tmp_path, monkeypatch):
    output = _fenced([{"angle": "a", "faille": "b", "severite": "HIGH",
                       "reproduction": "r"}])

    def fake_call_raw(prompt, model, **kwargs):
        return {"ok": True, "output": output, "tokens": 1,
                "duration_s": 0.1, "cost_usd": 0.0}

    monkeypatch.setattr(run_real, "_claude_call_raw", fake_call_raw)
    ex = run_real.claude_executor(add_dir=tmp_path, task_by_step={})
    res = ex(FakePayload("s11-redteam-code"), None, _context(tmp_path / "run"))
    assert res["ok"] is True
    assert res["findings"] == ["[HIGH] a — b (repro: r)"]
    # (e) garde-fou promotion : `blocked` n'est JAMAIS posé par ce chantier.
    assert "blocked" not in res


def test_executor_autres_etapes_ne_recoivent_jamais_findings(tmp_path, monkeypatch):
    """Non-régression : le câblage est borné à s11-redteam-code — s9-build (et
    toute autre étape) n'a jamais `findings` ajouté à son retour, même si sa
    sortie contient accidentellement un bloc ```json``` de la même forme."""
    output = _fenced([{"angle": "a", "faille": "b", "severite": "HIGH",
                       "reproduction": "r"}])

    def fake_call_raw(prompt, model, **kwargs):
        return {"ok": True, "output": output, "tokens": 1,
                "duration_s": 0.1, "cost_usd": 0.0}

    monkeypatch.setattr(run_real, "_claude_call_raw", fake_call_raw)
    ex = run_real.claude_executor(add_dir=tmp_path, task_by_step={})
    # `s6-redteam-plan` plutôt que `s1-prisme` : l'étape est un DÉCOR (n'importe
    # laquelle sauf s11), et depuis le 2026-08-04 s1-prisme matérialise prisme.json —
    # la sortie factice, de forme red-team, y échouerait à la matérialisation et ce
    # test échouerait pour une raison étrangère à ce qu'il vérifie. Le décor choisi
    # est même plus probant : une étape red-team ADJACENTE ne reçoit pas de findings.
    res = ex(FakePayload("s6-redteam-plan"), None, _context(tmp_path / "run"))
    assert res["ok"] is True
    assert "findings" not in res


def test_executor_s11_rapport_sans_bloc_json_res_findings_liste_vide(tmp_path, monkeypatch):
    """Reproduit pong_r2 : un rapport red-team réel réussi (ok=True) mais SANS
    section structurée doit rendre res["findings"] == [] — jamais une absence
    de clé (driver.py fait `res.get("findings", [])`, [] est déjà le défaut,
    mais on la pose explicitement pour que `findings_note` soit visible)."""
    prose = "Rapport red-team sans bloc JSON (cas historique)."

    def fake_call_raw(prompt, model, **kwargs):
        return {"ok": True, "output": prose, "tokens": 1,
                "duration_s": 0.1, "cost_usd": 0.0}

    monkeypatch.setattr(run_real, "_claude_call_raw", fake_call_raw)
    ex = run_real.claude_executor(add_dir=tmp_path, task_by_step={})
    res = ex(FakePayload("s11-redteam-code"), None, _context(tmp_path / "run"))
    assert res["findings"] == []
    assert res["findings_note"] != ""
