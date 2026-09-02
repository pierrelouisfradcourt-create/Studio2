"""Le worker `asset_producer` declare dans roles.yaml correspond-il au reel ?

Mode de panne connu du studio : « declare != execute » — un mecanisme declare pendant
des mois sans jamais tourner. Ces tests refusent qu'une declaration de runtime devienne
de la prose : chaque chemin cite dans `implementation` doit exister, et les contraintes
annoncees doivent etre reellement portees par le code.

Ils ne prouvent PAS qu'un worker a tourne (aucun test ne peut le prouver a posteriori) —
ils prouvent que ce qui est declare est branchable.
"""
from __future__ import annotations

from pathlib import Path

import pytest

yaml = pytest.importorskip("yaml")

REPO = Path(__file__).resolve().parents[2]
ROLES = REPO / "forge" / "contracts" / "roles.yaml"


@pytest.fixture(scope="module")
def contrat() -> dict:
    data = yaml.safe_load(ROLES.read_text(encoding="utf-8"))
    rc = data.get("runtime_contracts") or {}
    assert "asset_producer" in rc, "le worker asset_producer n'est pas declare dans roles.yaml"
    return rc["asset_producer"]


def test_les_chemins_declares_existent_vraiment(contrat):
    """Un `implementation:` qui cite un fichier absent est de la prose, pas un contrat."""
    impl = contrat["implementation"]
    for cle in ("entrypoint", "proposer", "skill"):
        chemin = REPO / impl[cle]
        assert chemin.is_file(), f"{cle} declare mais absent du depot : {impl[cle]}"


def test_le_worker_ne_se_declare_pas_juge(contrat):
    """La regle fondatrice doit etre dans le contrat, pas seulement dans la doc."""
    c = contrat["constraints"]
    assert "no_self_judgement" in c
    assert "no_manifest" in c
    assert "no_catalog_write" in c


def test_le_producteur_n_ecrit_ni_manifeste_ni_catalogue(contrat):
    """Verification sur le CODE, pas sur la declaration : le producteur doit etre muet
    sur `.geometry.json` (ecriture) et sur `catalog.json`."""
    src = (REPO / contrat["implementation"]["entrypoint"]).read_text(encoding="utf-8")
    # Le nom peut apparaitre dans un commentaire expliquant qu'on ne l'ecrit pas ;
    # ce qui est interdit, c'est une ECRITURE.
    for interdit in ("catalog.json",):
        assert interdit not in src.replace("catalog.json (", ""), \
            f"le producteur mentionne {interdit} — il ne doit jamais y toucher"
    assert 'open(glb + ".geometry.json"' not in src
    assert '"manifest_written": False' in src, \
        "le rapport de generation doit declarer explicitement qu'aucun manifeste n'est ecrit"


def test_le_producteur_refuse_une_spec_sans_consommateur(contrat):
    """`consumer_required` doit etre porte par le code, pas seulement annonce."""
    src = (REPO / contrat["implementation"]["entrypoint"]).read_text(encoding="utf-8")
    assert "aucun consumer" in src, "aucun refus explicite d'une spec sans consumer"


def test_les_limites_sont_declarees_et_honnetes(contrat):
    """Un runtime dont les limites disent `production_ready: true` sans preuve mentirait."""
    lim = contrat["limits"]
    assert lim["production_ready"] is False
    assert lim["quality_not_proven"] is True
    assert "PRIMITIVES" in lim["why"] or "primitives" in lim["why"]
    # La faiblesse reelle trouvee le 2026-08-06 doit rester ecrite.
    assert "variants_depend_on_honesty" in lim


def test_l_archetype_hors_liste_est_une_erreur_explicite(contrat):
    src = (REPO / contrat["implementation"]["entrypoint"]).read_text(encoding="utf-8")
    assert "archetype inconnu" in src, "un archetype inconnu doit lever, jamais produire un cube"


def test_invocation_et_io_declares(contrat):
    assert contrat["invocation"] == "spec_file"
    assert set(contrat["outputs"]) == {"glb", "metadata_json", "generation_report_json"}
    for champ in ("asset_id", "archetype", "category", "consumer"):
        assert champ in contrat["inputs"]
