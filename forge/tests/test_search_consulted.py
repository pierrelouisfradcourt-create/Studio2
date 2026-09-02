"""Phase 1b (bibliothèque de code) : check_search_consulted lit search_log.jsonl en
Python (miroir de searchLogSince en JS) — advisory, ne gate jamais oracle_ok."""
import json

from forge.static_oracles import check_search_consulted, utc_iso_now


def _write_log(path, records):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        for r in records:
            fh.write(json.dumps(r) + "\n")


def test_absence_de_fichier_est_un_fail_informatif(tmp_path):
    r = check_search_consulted("2026-07-19T00:00:00.000Z", log_path=tmp_path / "absent.jsonl")
    assert r["passed"] is False
    assert r["count"] == 0
    assert "absent" in r["raisons"][0]


def test_entree_apres_le_seuil_est_comptee(tmp_path):
    log = tmp_path / "search_log.jsonl"
    _write_log(log, [{"query": "poursuite", "matchCount": 2, "ts": "2026-07-19T10:00:00.000Z"}])
    r = check_search_consulted("2026-07-19T09:00:00.000Z", log_path=log)
    assert r["passed"] is True
    assert r["count"] == 1


def test_entree_avant_le_seuil_est_exclue(tmp_path):
    log = tmp_path / "search_log.jsonl"
    _write_log(log, [{"query": "vieille recherche", "matchCount": 1, "ts": "2026-07-19T08:00:00.000Z"}])
    r = check_search_consulted("2026-07-19T09:00:00.000Z", log_path=log)
    assert r["passed"] is False
    assert r["count"] == 0


def test_ligne_corrompue_est_ignoree_pas_fatale(tmp_path):
    log = tmp_path / "search_log.jsonl"
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_text(
        "pas du json valide\n"
        + json.dumps({"query": "ok", "matchCount": 1, "ts": "2026-07-19T10:00:00.000Z"}) + "\n",
        encoding="utf-8",
    )
    r = check_search_consulted("2026-07-19T09:00:00.000Z", log_path=log)
    assert r["passed"] is True
    assert r["count"] == 1


def test_utc_iso_now_meme_format_que_js_toisostring(tmp_path):
    ts = utc_iso_now()
    assert ts.endswith("Z")
    assert "+00:00" not in ts
    # comparaison lexicale valide : une entrée écrite juste après utc_iso_now() doit
    # être >= la référence (round-trip minimal).
    assert ts <= utc_iso_now()
