"""Acceptation : sur le run réel collect_runner (12 règles, fonctions renommées),
le gel du jeu de règles DISCRIMINE renommage (auto-corrigeable) vs suppression (stop)."""
import json
from pathlib import Path

import pytest

from forge.static_oracles import (
    check_feature_set_frozen,
    frozen_features_from_wiremap,
    load_frozen_features,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
RUN = REPO_ROOT / "EVIDENCE" / "runs" / "collect_runner"


def _wiremap():
    p = RUN / "wiremap.json"
    if not p.exists():
        pytest.skip("run réel collect_runner absent")
    return json.loads(p.read_text(encoding="utf-8"))


def test_run_reel_a_douze_regles():
    wm = _wiremap()
    feats = frozen_features_from_wiremap(wm)
    assert len(feats) == 12, feats


def test_snapshot_puis_renommage_reste_auto_corrigeable(tmp_path):
    # Round-trip disque réel : on FIGE les 12 features du run, puis on simule le
    # renommage de fonctions observé (mêmes features, `fonction` changée). Le gel
    # rechargé depuis le disque PASSE => renommage auto-corrigeable, pas un stop dur.
    wm = _wiremap()
    snap = {"features": frozen_features_from_wiremap(wm)}
    (tmp_path / "wiremap_frozen.json").write_text(json.dumps(snap, ensure_ascii=False), encoding="utf-8")
    frozen = load_frozen_features(tmp_path)
    assert frozen is not None and len(frozen) == 12
    renomme = {"features": [{**f, "fonction": f.get("fonction", "") + "_v2"} for f in wm["features"]]}
    res = check_feature_set_frozen(renomme, frozen)
    assert res["passed"] is True and res["checked"] is True


def test_suppression_dune_regle_est_un_stop():
    # Retirer R7 de la WireMap face au snapshot gelé => supprimees non vide => stop dur.
    wm = _wiremap()
    frozen = frozen_features_from_wiremap(wm)
    amputee = {"features": [f for f in wm["features"] if not f["feature"].startswith("R7")]}
    res = check_feature_set_frozen(amputee, frozen)
    assert res["passed"] is False
    assert any(r.startswith("R7") for r in res["supprimees"])
