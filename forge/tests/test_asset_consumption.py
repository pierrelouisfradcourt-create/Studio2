"""FICHE 2 (GO Pierre 2026-08-29) : gate fail-closed de CONSOMMATION des
asset_requests produits par s2.5-artbible.

Chaque `asset_requests.json.requests[].id` doit être `resolved` (fichier réel,
non vide, sous src_root) ou `blocked` (raison non vide) dans
`asset_resolution.json` (écrit par le builder s9) — sinon FAIL, quelle que soit
la cause (id non consommé, résolution orpheline, entrée malformée). Aucun LLM,
aucune exception ne doit remonter : entrée malformée => FAIL honnête.
"""
from forge.static_oracles import check_asset_consumption


def _write(root, rel, content=b"x"):
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(content)
    return p


# --- cas légitime : rien à produire ---

def test_no_assets_needed_with_reason_passes(tmp_path):
    asset_requests = {"requests": [], "no_assets_needed": True,
                       "reason": "jeu 100% procédural, aucun asset externe requis"}
    rep = check_asset_consumption(asset_requests, {}, tmp_path)
    assert rep["passed"] is True
    assert rep["raisons"] == []
    assert rep["resolved"] == 0
    assert rep["blocked"] == 0
    assert rep["missing"] == []
    assert rep["checked"] is True


def test_empty_requests_without_no_assets_needed_fails(tmp_path):
    asset_requests = {"requests": [], "no_assets_needed": False, "reason": ""}
    rep = check_asset_consumption(asset_requests, {}, tmp_path)
    assert rep["passed"] is False
    assert rep["resolved"] == 0
    assert rep["blocked"] == 0


# --- resolved ---

def test_resolved_with_real_file_passes(tmp_path):
    _write(tmp_path, "art/cat.svg", b"<svg></svg>")
    asset_requests = {"requests": [{"id": "r1", "entity_role": "cat", "type": "sprite",
                                     "style": "flat", "acceptance_tests": []}]}
    resolution = {"requests": [{"id": "r1", "status": "resolved", "path": "art/cat.svg"}]}
    rep = check_asset_consumption(asset_requests, resolution, tmp_path)
    assert rep["passed"] is True
    assert rep["raisons"] == []
    assert rep["resolved"] == 1
    assert rep["blocked"] == 0
    assert rep["missing"] == []


def test_resolved_missing_file_fails(tmp_path):
    asset_requests = {"requests": [{"id": "r1"}]}
    resolution = {"requests": [{"id": "r1", "status": "resolved", "path": "art/absent.svg"}]}
    rep = check_asset_consumption(asset_requests, resolution, tmp_path)
    assert rep["passed"] is False
    assert rep["resolved"] == 0
    assert rep["blocked"] == 0
    assert any("resolved sans fichier" in r for r in rep["raisons"])


def test_resolved_empty_file_fails(tmp_path):
    _write(tmp_path, "art/empty.svg", b"")
    asset_requests = {"requests": [{"id": "r1"}]}
    resolution = {"requests": [{"id": "r1", "status": "resolved", "path": "art/empty.svg"}]}
    rep = check_asset_consumption(asset_requests, resolution, tmp_path)
    assert rep["passed"] is False
    assert rep["resolved"] == 0
    assert rep["blocked"] == 0
    assert any("resolved sans fichier" in r for r in rep["raisons"])


# --- blocked ---

def test_blocked_with_reason_passes(tmp_path):
    asset_requests = {"requests": [{"id": "r1"}]}
    resolution = {"requests": [{"id": "r1", "status": "blocked",
                                    "reason": "hors budget artbible, reporté"}]}
    rep = check_asset_consumption(asset_requests, resolution, tmp_path)
    assert rep["passed"] is True
    assert rep["raisons"] == []
    assert rep["resolved"] == 0
    assert rep["blocked"] == 1


def test_blocked_without_reason_fails(tmp_path):
    asset_requests = {"requests": [{"id": "r1"}]}
    resolution = {"requests": [{"id": "r1", "status": "blocked", "reason": ""}]}
    rep = check_asset_consumption(asset_requests, resolution, tmp_path)
    assert rep["passed"] is False
    assert rep["resolved"] == 0
    assert rep["blocked"] == 0
    assert any("blocked sans 'reason'" in r for r in rep["raisons"])


# --- consommation manquante / orpheline ---

def test_unconsumed_request_fails(tmp_path):
    asset_requests = {"requests": [{"id": "r1"}, {"id": "r2"}]}
    resolution = {"requests": [{"id": "r1", "status": "blocked", "reason": "reporté"}]}
    rep = check_asset_consumption(asset_requests, resolution, tmp_path)
    assert rep["passed"] is False
    assert rep["resolved"] == 0
    assert rep["blocked"] == 1
    assert rep["missing"] == ["r2"]
    assert any("silencieusement non consommé" in r for r in rep["raisons"])


def test_orphan_resolution_fails(tmp_path):
    _write(tmp_path, "art/cat.svg", b"<svg></svg>")
    asset_requests = {"requests": [{"id": "r1"}]}
    resolution = {"requests": [
        {"id": "r1", "status": "resolved", "path": "art/cat.svg"},
        {"id": "ghost", "status": "resolved", "path": "art/cat.svg"},
    ]}
    rep = check_asset_consumption(asset_requests, resolution, tmp_path)
    assert rep["passed"] is False
    assert rep["resolved"] == 1
    assert rep["blocked"] == 0
    assert any("résolution orpheline" in r for r in rep["raisons"])


# --- entrées malformées : FAIL honnête, jamais d'exception ---

def test_malformed_asset_requests_not_a_mapping_fails_honestly(tmp_path):
    rep = check_asset_consumption(["not", "a", "dict"], {}, tmp_path)
    assert rep["passed"] is False
    assert rep["checked"] is True
    assert any("n'est pas un mapping" in r for r in rep["raisons"])


def test_malformed_asset_resolution_not_a_mapping_fails_honestly(tmp_path):
    asset_requests = {"requests": [{"id": "r1"}]}
    rep = check_asset_consumption(asset_requests, ["not", "a", "dict"], tmp_path)
    assert rep["passed"] is False
    assert rep["checked"] is True
    assert any("n'est pas un mapping" in r for r in rep["raisons"])


def test_malformed_requests_missing_list_fails_honestly(tmp_path):
    rep = check_asset_consumption({"requests": "not-a-list"}, {}, tmp_path)
    assert rep["passed"] is False
    assert rep["checked"] is True
    assert any("'requests' absent ou n'est pas une liste" in r for r in rep["raisons"])


def test_malformed_request_entry_without_exploding(tmp_path):
    asset_requests = {"requests": [{"no_id_field": True}, {"id": "r1"}]}
    resolution = {"requests": [{"id": "r1", "status": "blocked", "reason": "ok"}]}
    rep = check_asset_consumption(asset_requests, resolution, tmp_path)
    assert rep["passed"] is False
    assert rep["blocked"] == 1
    assert any("'id' absent ou vide" in r for r in rep["raisons"])


def test_unknown_status_fails(tmp_path):
    asset_requests = {"requests": [{"id": "r1"}]}
    resolution = {"requests": [{"id": "r1", "status": "maybe"}]}
    rep = check_asset_consumption(asset_requests, resolution, tmp_path)
    assert rep["passed"] is False
    assert rep["resolved"] == 0
    assert rep["blocked"] == 0
    assert any("status" in r and "invalide" in r for r in rep["raisons"])


# --- clé non canonique : décision Pierre 2026-08-29 (Project Input) ----------------

def test_resolutions_key_is_rejected(tmp_path):
    """La tolérance `resolutions|requests` (fiche 2) est levée : SEULE la clé
    `requests` est acceptée dans asset_resolution.json. Un fichier qui porte encore
    `resolutions` (ancienne forme tolérée) doit FAIL nommé, jamais être lu en silence
    — même s'il porte par ailleurs une résolution valide."""
    _write(tmp_path, "art/cat.svg", b"<svg></svg>")
    asset_requests = {"requests": [{"id": "r1"}]}
    resolution = {"resolutions": [{"id": "r1", "status": "resolved", "path": "art/cat.svg"}]}
    rep = check_asset_consumption(asset_requests, resolution, tmp_path)
    assert rep["passed"] is False
    assert rep["resolved"] == 0
    assert rep["blocked"] == 0
    assert any("clé non canonique 'resolutions'" in r for r in rep["raisons"])
