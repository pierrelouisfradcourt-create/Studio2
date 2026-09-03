"""`run_oracle` doit lire la sortie d'un oracle quel que soit l'encodage du shell.

DÉFAUT RÉEL, RUN M bis (2026-09-02) — reproduit avant correction :
`forge/oracle.py` était le SEUL de ses quatre `subprocess.run` à ne pas nommer son encodage.
Le jeu produit imprimait un cadre `╔═══╗` ; sous une locale `cp1252`, le thread lecteur de
`subprocess` levait `UnicodeDecodeError` sur l'octet `0x90`, `completed.stdout` devenait `None`,
et `fh.write(None)` faisait tomber `s10a-oracle-code` en `TypeError`.

**La chaîne butait sur sa propre LECTURE de la sortie, jamais sur le produit** : le même oracle,
lancé à la main, rendait `PASS` + `SOLVABLE`. Défaut hérité de V1, latent — il ne se manifestait
que depuis un shell non-UTF-8, et aucun run V1 n'était parti d'un tel shell.

Ces tests figent les deux moitiés : la sortie est LUE, et une preuve n'est jamais perdue.
NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import sys

from forge.oracle import OracleSpec, run_oracle

# Caractères hors cp1252 : cadre semi-graphique (celui du vrai oracle) + accents + symbole.
_HORS_CP1252 = "╔══╗ SOLVABLE ✓ é"


def _spec_qui_imprime(tmp_path, texte: str) -> OracleSpec:
    script = tmp_path / "oracle_bruyant.py"
    script.write_text(
        "import sys\n"
        "sys.stdout.reconfigure(encoding='utf-8')\n"
        f"print({texte!r})\n",
        encoding="utf-8",
    )
    return OracleSpec(project="sonde", cwd=tmp_path,
                      command=[sys.executable, str(script)])


def test_une_sortie_non_cp1252_est_LUE_et_non_perdue(tmp_path):
    """Le cœur du défaut : sans encodage nommé, `stdout` revenait à None."""
    ev = tmp_path / "evidence"
    res = run_oracle(_spec_qui_imprime(tmp_path, _HORS_CP1252), evidence_dir=ev)

    assert res.returncode == 0
    log = (ev / "oracle_sonde.log").read_text(encoding="utf-8", errors="replace")
    assert "SOLVABLE" in log, "la sortie de l'oracle doit atteindre la preuve"
    assert "╔" in log, "les caractères hors cp1252 doivent être LUS, pas perdus"


def test_aucune_preuve_ne_peut_valoir_None(tmp_path):
    """`errors='replace'` : un octet illisible dégrade UN CARACTÈRE, jamais la preuve entière.
    Un `None` écrit dans le journal faisait tomber l'étape ; un caractère de remplacement, non."""
    ev = tmp_path / "evidence"
    res = run_oracle(_spec_qui_imprime(tmp_path, _HORS_CP1252), evidence_dir=ev)

    # `OracleResult` ne porte pas la sortie : la preuve VIT dans le journal d'évidence.
    # C'est donc lui qu'il faut interroger — et c'est exactement là que le `None` frappait.
    contenu = res.evidence_path.read_text(encoding="utf-8", errors="replace")
    assert "None" not in contenu, "une preuve ne doit JAMAIS contenir un None écrit"
    assert contenu.strip(), "une preuve vide n'est pas une preuve"
    assert res.evidence_path.stat().st_size > 0


def test_tous_les_subprocess_de_oracle_py_nomment_leur_encodage():
    """Garde de non-régression STRUCTURELLE, et pas seulement comportementale : le défaut
    venait d'un appel resté en retrait des trois autres. On vérifie la cohérence du fichier,
    pour qu'un cinquième appel ne puisse pas réintroduire le trou en silence."""
    from pathlib import Path

    src = (Path(__file__).resolve().parents[1] / "oracle.py").read_text(encoding="utf-8")
    appels = src.count("subprocess.run(")
    avec_encodage = src.count('encoding="utf-8"')
    assert appels > 0
    assert avec_encodage >= appels, (
        f"{appels} appel(s) subprocess.run pour {avec_encodage} encodage(s) nommé(s) — "
        "un appel sans encodage explicite peut faire disparaître une preuve (règle CLAUDE.md)"
    )
