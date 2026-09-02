"""Oracle du correctif d'horodatage des reçus/verdicts signés (lot A, réparation 4).

Post-mortem pacman (studio_brain/journal/2026-08-07_postmortem_pacman_forge.md §0) :
`EVIDENCE/runs/pacman/verdict.json` et `verdict_v2.json` portent `ts: 0.0` au sommet
ET sur les trois reçus d'oracle — l'Observer reconstruit une fenêtre 1970->2026
(56 ans) sans garde-fou. Racine mesurée : `make_signed_receipt`/`build_aggregate_verdict`
(forge/verdict.py) défautaient `ts` à `0.0` quand l'appelant omettait
l'argument ; `ForgeDriver._receipt` (forge/driver.py) défautait aussi à
`0.0` un pas dont l'état ne portait pas encore de "ts".

Ce fichier prouve DEUX choses distinctes :
  1. l'OMISSION de `ts` produit désormais un epoch réel (proche de `time.time()`),
     jamais `0.0` ;
  2. un reçu/verdict HISTORIQUE signé avec `ts=0.0` EXPLICITE reste vérifiable tel
     quel (rétro-compatibilité — le correctif ne retouche aucun reçu existant, il
     ferme seulement le trou pour la PRODUCTION FUTURE).

Fichier NOUVEAU : ne touche à aucun test existant. claim_verdict: NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import tempfile
import time
from pathlib import Path

from forge.driver import ForgeDriver
from forge.verdict import (
    build_aggregate_verdict,
    make_signed_receipt,
    new_nonce,
    verify_aggregate,
    verify_receipt,
)

KEY = Path(tempfile.mkdtemp()) / "k"


def _receipt(oracle_id="archi", status="OK", **kw):
    return make_signed_receipt(oracle_id, "run1", status, {}, key_file=KEY, **kw)


# --- 1. omission => epoch réel, jamais 0.0 -----------------------------------------

def test_make_signed_receipt_without_ts_uses_real_epoch():
    before = time.time()
    sr = _receipt()
    after = time.time()
    assert sr.receipt.ts != 0.0
    assert before - 1 <= sr.receipt.ts <= after + 1


def test_build_aggregate_verdict_without_ts_uses_real_epoch():
    code = _receipt("code", "OK")
    archi = _receipt("archi", "SKIPPED")
    wiremap = _receipt("wiremap", "SKIPPED")
    before = time.time()
    agg = build_aggregate_verdict(
        "proj", "run1", code, archi, wiremap, "aucun",
        redteam_ran=False, nonce=new_nonce(), key_file=KEY,
    )
    after = time.time()
    assert agg.ts != 0.0
    assert before - 1 <= agg.ts <= after + 1


# --- 2. explicit ts is honored (never overridden), incl. ts=0.0 for retro-compat --

def test_make_signed_receipt_explicit_ts_is_honored():
    sr = _receipt(ts=12345.5)
    assert sr.receipt.ts == 12345.5


def test_make_signed_receipt_explicit_zero_ts_is_preserved_and_still_verifies():
    """Simule un reçu HISTORIQUE (ts=0.0 explicite, comme pacman) : reste
    vérifiable tel quel — le correctif ne retouche jamais un reçu déjà signé."""
    sr = _receipt(ts=0.0)
    assert sr.receipt.ts == 0.0
    assert verify_receipt(sr.receipt, sr.signature, key_file=KEY) is True


def test_build_aggregate_verdict_explicit_zero_ts_is_preserved_and_still_verifies():
    code = _receipt("code", "OK")
    archi = _receipt("archi", "SKIPPED")
    wiremap = _receipt("wiremap", "SKIPPED")
    agg = build_aggregate_verdict(
        "proj", "run1", code, archi, wiremap, "aucun",
        redteam_ran=False, nonce=new_nonce(), ts=0.0, key_file=KEY,
    )
    assert agg.ts == 0.0
    from forge.verdict import sign_aggregate
    sig = sign_aggregate(agg, key_file=KEY)
    assert verify_aggregate(agg, sig, key_file=KEY) is True


# --- 3. ForgeDriver._receipt : un pas sans "ts" enregistré n'écrit plus 0.0 -------

def test_driver_receipt_falls_back_to_real_epoch_when_step_ts_missing(tmp_path):
    """Un pas d'état sans champ "ts" (jamais passé par _finish_step) doit produire
    un reçu horodaté RÉEL, jamais 0.0 — c'est le chemin exact qui a produit
    `verdict.json` ts=0.0 sur le run pacman (état construit hors du cycle normal
    de ForgeDriver, cf. post-mortem §1 : « dispatch manuel étape par étape »)."""
    d = ForgeDriver(
        "proj", "proj-1", run_dir=tmp_path / "run", profile="patch", key_file=KEY,
    )
    state = {"steps": {e: {"status": "PENDING", "attempts": 0} for e in d.order}}
    # "archi" est SKIPPED (hors profil `patch`) -> chemin "etape not in self.order",
    # déjà couvert par ts=time.time() explicite (inchangé par ce correctif) ; on
    # cible ici "wiremap", pareillement hors profil `patch`, pour la même raison —
    # donc on force plutôt une étape DANS l'ordre sans "ts" pour isoler le
    # fallback réparé : s10a-oracle-code, marquée FAIL sans jamais avoir été
    # persistée par _finish_step (pas de champ "ts").
    state["steps"]["s10a-oracle-code"] = {"status": "FAIL", "attempts": 1, "detail": {}}
    before = time.time()
    sr = d._receipt(state, "code", "s10a-oracle-code")
    after = time.time()
    assert sr.receipt.ts != 0.0
    assert before - 1 <= sr.receipt.ts <= after + 1
