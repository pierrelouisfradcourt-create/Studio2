"""Tests du capteur de synchronisation contrat-de-système <-> skill.md (`forge.contract_sync`).

Fichier NEUF — n'altère aucun test existant (zone protégée `tests/**` non concernée :
ce module vit dans `forge/tests/`, régime studio normal, cf. CLAUDE.md).

Convention : chaque test fabrique un mini repo isolé sous `tmp_path` (contrat YAML +
fichiers source + skill.md) et appelle `check_contract_sync` avec des chemins relatifs
custom — jamais le vrai contrat/skill du dépôt (ceux-là sont audités séparément par le
capteur lancé en CLI, voir le rapport de mission).
"""
from __future__ import annotations

import io
import json
import sys
from pathlib import Path

from forge.contract_sync import check_contract_sync, main

CONTRACT_REL = "forge/FORGE_SYSTEM_CONTRACT.yaml"
SKILL_REL = ".claude/skills/forge/skill.md"


def _write(root: Path, rel: str, content: str) -> Path:
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content, encoding="utf-8")
    return p


def _run(root: Path) -> dict:
    return check_contract_sync(root, contract_path=CONTRACT_REL, skill_path=SKILL_REL)


# ======================================================================================
# 1. symbole cité -> aucune violation
# ======================================================================================


def test_symbole_cite_aucune_violation(tmp_path: Path) -> None:
    _write(tmp_path, "forge/escalate.py", "def escalation_decision():\n    pass\n")
    _write(tmp_path, CONTRACT_REL, """
regles_canoniques:
  - regle: escalade de tier
    source: forge/escalate.py::escalation_decision
""")
    _write(tmp_path, SKILL_REL, "On appelle `escalation_decision(payload.model, ...)` ici.\n")

    r = _run(tmp_path)
    assert r["checked"] is True
    assert r["passed"] is True
    assert r["violations"] == []
    assert r["regles"][0]["cite"] is True
    assert r["regles"][0]["cited_symbol"] == "escalation_decision"


# ======================================================================================
# 2. symbole cité nulle part -> regle_non_citee, nommant la règle
# ======================================================================================


def test_symbole_non_cite_produit_regle_non_citee(tmp_path: Path) -> None:
    _write(tmp_path, "forge/pool.py", "def pool_decision():\n    pass\n")
    _write(tmp_path, CONTRACT_REL, """
regles_canoniques:
  - regle: decision de pool / re-tentative au meme tier
    source: forge/pool.py::pool_decision
""")
    _write(tmp_path, SKILL_REL, "Ce skill ne parle jamais de cette fonction.\n")

    r = _run(tmp_path)
    assert r["checked"] is True
    assert r["passed"] is False
    violations = [v for v in r["violations"] if v["type"] == "regle_non_citee"]
    assert len(violations) == 1
    assert violations[0]["regle"] == "decision de pool / re-tentative au meme tier"
    assert "pool_decision" in violations[0]["symboles_attendus"]


def test_symbole_partiel_ne_matche_pas_un_identifiant_plus_long(tmp_path: Path) -> None:
    """`pool_decision` ne doit PAS être considéré cité par une sous-chaîne d'un autre
    identifiant (ex. `my_pool_decision_helper`) — frontières de mot strictes."""
    _write(tmp_path, "forge/pool.py", "def pool_decision():\n    pass\n")
    _write(tmp_path, CONTRACT_REL, """
regles_canoniques:
  - regle: decision de pool
    source: forge/pool.py::pool_decision
""")
    _write(tmp_path, SKILL_REL, "Utilise `my_pool_decision_helper()` ailleurs dans la doc.\n")

    r = _run(tmp_path)
    assert r["passed"] is False
    assert any(v["type"] == "regle_non_citee" for v in r["violations"])


# ======================================================================================
# 3. sources multiples, UNE seule citée -> aucune violation
# ======================================================================================


def test_sources_multiples_une_citee_aucune_violation(tmp_path: Path) -> None:
    _write(tmp_path, "forge/verdict.py", "def make_signed_receipt():\n    pass\n")
    _write(tmp_path, "forge/verify_run.py", "def verify_run():\n    pass\n")
    _write(tmp_path, CONTRACT_REL, """
regles_canoniques:
  - regle: verdict signe et sa re-verification
    source: [forge/verdict.py, forge/verify_run.py]
""")
    # Cite seulement le module verify_run (verdict.py jamais mentionné, et le mot
    # "verdict" lui-même volontairement absent pour ne pas fausser le test) :
    _write(tmp_path, SKILL_REL, "Lance `python -m forge.verify_run EVIDENCE/runs/<run>/RUN_OUTPUT.json`.\n")

    r = _run(tmp_path)
    assert r["checked"] is True
    assert r["passed"] is True
    assert r["violations"] == []
    assert r["regles"][0]["cited_symbol"] == "verify_run"


def test_source_groupee_virgule_une_symbole_cite_aucune_violation(tmp_path: Path) -> None:
    """Cas réel du contrat : plusieurs symboles groupés après `::` dans UNE source
    (`dispatch.py::ORDER, PROFILES, order_for_profile`). Un seul cité suffit."""
    _write(tmp_path, "forge/dispatch.py",
           "ORDER = []\nPROFILES = {}\n\ndef order_for_profile():\n    pass\n")
    _write(tmp_path, CONTRACT_REL, """
regles_canoniques:
  - regle: ordre des etapes et profils de chaine
    source: forge/dispatch.py::ORDER, PROFILES, order_for_profile
""")
    _write(tmp_path, SKILL_REL, "Pour chaque etape dans l'ordre `forge.dispatch.ORDER` :\n")

    r = _run(tmp_path)
    assert r["passed"] is True
    assert r["regles"][0]["cited_symbol"] == "ORDER"


# ======================================================================================
# 4. source pointant vers un fichier inexistant -> source_introuvable
# ======================================================================================


def test_fichier_source_inexistant_produit_source_introuvable(tmp_path: Path) -> None:
    _write(tmp_path, CONTRACT_REL, """
regles_canoniques:
  - regle: regle fantome
    source: forge/ce_fichier_n_existe_pas.py::une_fonction
""")
    _write(tmp_path, SKILL_REL, "Peu importe ce que dit ce fichier, `une_fonction` y est citee.\n")

    r = _run(tmp_path)
    assert r["checked"] is True
    assert r["passed"] is False
    intro = [v for v in r["violations"] if v["type"] == "source_introuvable"]
    assert len(intro) == 1
    assert "ce_fichier_n_existe_pas.py" in intro[0]["detail"]


# ======================================================================================
# 5. fichier::symbole où le symbole n'existe pas dans le fichier -> source_introuvable
# ======================================================================================


def test_symbole_absent_du_fichier_produit_source_introuvable(tmp_path: Path) -> None:
    _write(tmp_path, "forge/escalate.py", "def une_autre_fonction():\n    pass\n")
    _write(tmp_path, CONTRACT_REL, """
regles_canoniques:
  - regle: escalade de tier
    source: forge/escalate.py::escalation_decision
""")
    _write(tmp_path, SKILL_REL, "Le skill cite quand meme `escalation_decision` dans sa prose.\n")

    r = _run(tmp_path)
    assert r["checked"] is True
    assert r["passed"] is False
    intro = [v for v in r["violations"] if v["type"] == "source_introuvable"]
    assert len(intro) == 1
    assert "escalation_decision" in intro[0]["detail"]
    # La citation, elle, est bien présente : c'est le fichier qui ment sur son contenu.
    assert r["regles"][0]["cite"] is True


# ======================================================================================
# 6. robustesse : jamais d'exception
# ======================================================================================


def test_contrat_absent(tmp_path: Path) -> None:
    r = _run(tmp_path)
    assert r["checked"] is False
    assert r["passed"] is False
    assert "introuvable" in r["raison"]


def test_yaml_illisible(tmp_path: Path) -> None:
    _write(tmp_path, CONTRACT_REL, "regles_canoniques: [\n  - ceci: n'est pas: du yaml valide: [[[\n")
    r = _run(tmp_path)
    assert r["checked"] is False
    assert r["passed"] is False
    assert "YAML illisible" in r["raison"]


def test_regles_canoniques_absent(tmp_path: Path) -> None:
    _write(tmp_path, CONTRACT_REL, "identite:\n  nom: Forge\n")
    r = _run(tmp_path)
    assert r["checked"] is False
    assert r["passed"] is False
    assert "regles_canoniques" in r["raison"]


def test_regles_canoniques_type_inattendu(tmp_path: Path) -> None:
    _write(tmp_path, CONTRACT_REL, "regles_canoniques: \"pas une liste\"\n")
    r = _run(tmp_path)
    assert r["checked"] is False
    assert r["passed"] is False


def test_regles_canoniques_vide(tmp_path: Path) -> None:
    _write(tmp_path, CONTRACT_REL, "regles_canoniques: []\n")
    r = _run(tmp_path)
    assert r["checked"] is False
    assert r["passed"] is False


def test_entree_regle_malformee_pas_un_mapping(tmp_path: Path) -> None:
    _write(tmp_path, CONTRACT_REL, "regles_canoniques:\n  - juste une chaine, pas un mapping\n")
    _write(tmp_path, SKILL_REL, "peu importe\n")
    r = _run(tmp_path)
    assert r["checked"] is True
    assert r["passed"] is False
    assert any(v["type"] == "regle_malformee" for v in r["violations"])


def test_source_type_inattendu_entier(tmp_path: Path) -> None:
    _write(tmp_path, CONTRACT_REL, """
regles_canoniques:
  - regle: regle avec source cassee
    source: 42
""")
    _write(tmp_path, SKILL_REL, "peu importe\n")
    r = _run(tmp_path)
    assert r["checked"] is True
    assert r["passed"] is False
    assert any(v["type"] == "source_malformee" for v in r["violations"])


def test_source_type_inattendu_dict(tmp_path: Path) -> None:
    _write(tmp_path, CONTRACT_REL, """
regles_canoniques:
  - regle: regle avec source cassee
    source: {chemin: forge/x.py}
""")
    _write(tmp_path, SKILL_REL, "peu importe\n")
    r = _run(tmp_path)
    assert r["checked"] is True
    assert r["passed"] is False
    assert any(v["type"] == "source_malformee" for v in r["violations"])


def test_source_absente_du_tout(tmp_path: Path) -> None:
    _write(tmp_path, CONTRACT_REL, """
regles_canoniques:
  - regle: regle sans champ source
""")
    _write(tmp_path, SKILL_REL, "peu importe\n")
    r = _run(tmp_path)
    assert r["checked"] is True
    assert r["passed"] is False
    assert any(v["type"] == "source_malformee" for v in r["violations"])


def test_liste_source_avec_element_non_string(tmp_path: Path) -> None:
    _write(tmp_path, CONTRACT_REL, """
regles_canoniques:
  - regle: regle avec liste source cassee
    source: [forge/verdict.py, 7]
""")
    _write(tmp_path, SKILL_REL, "peu importe\n")
    r = _run(tmp_path)
    assert r["checked"] is True
    assert r["passed"] is False
    assert any(v["type"] == "source_malformee" for v in r["violations"])


# ======================================================================================
# 7. fichier de pilotage absent -> motivé, jamais d'exception
# ======================================================================================


def test_fichier_pilotage_absent(tmp_path: Path) -> None:
    _write(tmp_path, "forge/escalate.py", "def escalation_decision():\n    pass\n")
    _write(tmp_path, CONTRACT_REL, """
regles_canoniques:
  - regle: escalade de tier
    source: forge/escalate.py::escalation_decision
""")
    # skill.md volontairement absent.
    r = _run(tmp_path)
    assert r["checked"] is False
    assert r["passed"] is False
    assert "pilotage" in r["raison"]

# ======================================================================================
# 9. sortie machine --json (ajout : câblage studio_selfaudit.mjs) — stdout = UNIQUEMENT
# le JSON, aucune prose ; ordre des arguments indifférent ; codes de sortie inchangés ;
# le mode prose (sans --json) reste, lui, strictement inchangé.
# ======================================================================================


def test_json_flag_stdout_est_exactement_le_json_du_check(tmp_path: Path, capsys) -> None:
    _write(tmp_path, "forge/pool.py", "def pool_decision():\n    pass\n")
    _write(tmp_path, CONTRACT_REL, """
regles_canoniques:
  - regle: decision de pool
    source: forge/pool.py::pool_decision
""")
    _write(tmp_path, SKILL_REL, "Ce skill ne parle jamais de cette fonction.\n")

    expected = check_contract_sync(tmp_path, contract_path=CONTRACT_REL, skill_path=SKILL_REL)

    code = main([str(tmp_path), "--json"])
    captured = capsys.readouterr()

    assert code == 1  # checked=True, passed=False (regle_non_citee)
    # stdout ne contient QUE le JSON — une seule ligne, parsable intégralement.
    stdout_lines = [l for l in captured.out.splitlines() if l.strip()]
    assert len(stdout_lines) == 1
    parsed = json.loads(stdout_lines[0])
    # Le CLI résout `repo_root` en absolu (Path(...).resolve()) ; check_contract_sync
    # direct ci-dessus reçoit `tmp_path` déjà absolu — les deux doivent donc coïncider,
    # seuls les chemins internes (contract_path/skill_path, déjà relatifs) comparent tel quel.
    assert parsed == expected


def test_json_flag_avant_ou_apres_repo_root_meme_resultat(tmp_path: Path, capsys) -> None:
    _write(tmp_path, "forge/escalate.py", "def escalation_decision():\n    pass\n")
    _write(tmp_path, CONTRACT_REL, """
regles_canoniques:
  - regle: escalade de tier
    source: forge/escalate.py::escalation_decision
""")
    _write(tmp_path, SKILL_REL, "On appelle `escalation_decision(...)` ici.\n")

    code_avant = main(["--json", str(tmp_path)])
    out_avant = capsys.readouterr().out.strip()

    code_apres = main([str(tmp_path), "--json"])
    out_apres = capsys.readouterr().out.strip()

    assert code_avant == code_apres == 0  # synchronisé
    assert json.loads(out_avant) == json.loads(out_apres)
    # le chemin passé en positionnel n'a JAMAIS été confondu avec le drapeau --json :
    # les deux invocations doivent avoir résolu la même racine et donc le même contrat audité.
    assert json.loads(out_avant)["passed"] is True


def test_json_flag_contrat_absent_exit_2_et_json_du_raison(tmp_path: Path, capsys) -> None:
    """Cas « non évaluable » : exit 2 conservé, et le JSON (pas la prose) porte la raison."""
    code = main([str(tmp_path), "--json"])
    captured = capsys.readouterr()

    assert code == 2
    parsed = json.loads(captured.out.strip())
    assert parsed["checked"] is False
    assert "introuvable" in parsed["raison"]


def test_mode_prose_inchange_sans_json(tmp_path: Path, capsys) -> None:
    """Sans --json, comportement STRICTEMENT identique à avant : prose sur stdout,
    pas de JSON parsable, mêmes libellés (VERDICT, Limite déclarée, NO_CLAIM_ALLOWED)."""
    _write(tmp_path, "forge/escalate.py", "def escalation_decision():\n    pass\n")
    _write(tmp_path, CONTRACT_REL, """
regles_canoniques:
  - regle: escalade de tier
    source: forge/escalate.py::escalation_decision
""")
    _write(tmp_path, SKILL_REL, "On appelle `escalation_decision(...)` ici.\n")

    code = main([str(tmp_path)])
    captured = capsys.readouterr()

    assert code == 0
    assert "CAPTEUR DE SYNCHRONISATION" in captured.out
    assert "VERDICT" in captured.out
    assert "NO_CLAIM_ALLOWED" in captured.out
    try:
        json.loads(captured.out)
        parsable = True
    except json.JSONDecodeError:
        parsable = False
    assert parsable is False  # c'est de la prose multi-lignes, pas un objet JSON unique


# Note : ce fichier ne teste PAS le vrai FORGE_SYSTEM_CONTRACT.yaml du dépôt (ça
# rendrait la suite fragile au contenu du contrat, et — trouvaille de mission —
# ce fichier réel n'est aujourd'hui même pas du YAML strict valide, cf. rapport de
# mission). La preuve sur le dépôt réel se fait par invocation CLI, pas ici.


# ======================================================================================
# 8. robustesse console cp1252 (retour coordinateur) — le point d'entrée CLI ne doit
# JAMAIS lever UnicodeEncodeError, ni pour ses propres libellés (⚠, ✅) ni pour du
# CONTENU de contrat (nom de règle, symbole) portant un caractère hors cp1252.
# ======================================================================================


def test_cli_entrypoint_survit_a_une_console_cp1252(tmp_path: Path, monkeypatch) -> None:
    """`main()` sur une console cp1252 stricte : ne lève pas, rend un code entier,
    les accents (cp1252-représentables) traversent intacts, les caractères hors
    cp1252 (venant à la fois des libellés fixes du module ET du CONTENU du
    contrat, ex. `→`) sont remplacés au lieu de faire planter le process."""
    _write(tmp_path, "forge/pool.py", "def pool_decision():\n    pass\n")
    _write(tmp_path, CONTRACT_REL, """
regles_canoniques:
  - regle: règle testée à l'écran → jamais citée
    source: forge/pool.py::pool_decision
""")
    _write(tmp_path, SKILL_REL, "peu importe (le symbole n'est pas cité ici)\n")

    # Émule une VRAIE console Windows cp1252 : errors="strict" reproduit fidèlement
    # le crash rapporté (UnicodeEncodeError) si `main()` ne se durcit pas lui-même.
    out_buf, err_buf = io.BytesIO(), io.BytesIO()
    out_stream = io.TextIOWrapper(out_buf, encoding="cp1252", errors="strict")
    err_stream = io.TextIOWrapper(err_buf, encoding="cp1252", errors="strict")
    monkeypatch.setattr(sys, "stdout", out_stream)
    monkeypatch.setattr(sys, "stderr", err_stream)

    code = main([str(tmp_path)])  # ne doit lever AUCUNE exception

    out_stream.flush()
    err_stream.flush()
    assert isinstance(code, int)
    assert code in (0, 1, 2)

    decoded = out_buf.getvalue().decode("cp1252", errors="replace")
    # accents cp1252-représentables (é, à, è) : intacts, PAS remplacés
    assert "règle testée à l'écran" in decoded
    # le caractère hors cp1252 dans le CONTENU du contrat (→) a bien été neutralisé
    # (remplacé), pas laissé tel quel ni ayant fait planter l'écriture
    assert "→" not in decoded
    assert "jamais citée" in decoded
    # le verdict final (libellé du module lui-même, contient ⚠) est bien sorti
    assert "VERDICT" in decoded
