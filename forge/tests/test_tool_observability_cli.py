"""CLI de forge.tool_observability — patron `forge.reference_guard` (capsys,
appel direct de `main([...])`). Deux sous-commandes : `scan-contracts` (maillon
1, mesure de production) et `read` (maillon 5, LE lecteur — sans test, la
preuve de non-dormance du maillon 5 reposerait sur une démonstration manuelle
uniquement, jamais rejouée automatiquement)."""
from __future__ import annotations

import json
import tempfile
from pathlib import Path

from forge import tool_observability as obs
from forge.contract import load_contract


def test_cli_scan_contracts_prints_real_counts(capsys):
    assert obs.main(["scan-contracts"]) == 0
    out = json.loads(capsys.readouterr().out)
    assert out["schema"] == obs.SCHEMA
    assert out["claim_verdict"] == "NO_CLAIM_ALLOWED"
    assert out["contracts_scanned"] > 0
    counts = out["field_kind_counts"]
    assert counts["empty"] + counts["identifier"] + counts["prose"] == out["contracts_scanned"] * 2
    # Trouvaille de production stable (s4-archi.yaml, trou I4 réel) : au moins
    # UN exemple de prose déclarée dans un champ 'important'.
    assert any(e["etape"] == "s4-archi" and e["field"] == "plugin"
              for e in out["prose_examples"])


def test_cli_read_roundtrips_a_real_written_record(tmp_path, capsys):
    contract = load_contract("s4-archi")
    key = Path(tempfile.mkdtemp()) / "k"
    obs.append_tool_observability_record(
        "s4-archi", "cli-run", contract, run_dir=tmp_path, key_file=key,
    )
    assert obs.main(["read", "--run-dir", str(tmp_path), "--etape", "s4-archi",
                     "--key-file", str(key)]) == 0
    out = json.loads(capsys.readouterr().out)
    assert len(out) == 1
    assert out[0]["record"]["run_id"] == "cli-run"
    assert out[0]["hmac_valid"] is True


def test_cli_read_sur_run_dir_sans_trace_rend_liste_vide(tmp_path, capsys):
    assert obs.main(["read", "--run-dir", str(tmp_path), "--etape", "jamais-dispatchee"]) == 0
    assert json.loads(capsys.readouterr().out) == []


def test_cli_sans_sous_commande_rend_2(capsys):
    assert obs.main([]) == 2
