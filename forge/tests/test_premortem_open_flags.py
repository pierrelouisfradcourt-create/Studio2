"""Oracle P3 / P3-B (lot dégel) : transmission des points ouverts d'un run au
run suivant — `ForgeDriver._premortem()` injecte les `humangate_flags` du
DERNIER verdict SIGNÉ et VÉRIFIABLE du MÊME projet, préfixés
`[OUVERT run précédent]`.

P3-B élargit la recherche du seul `run_dir` courant au PROJET entier (tous
les run_dir frères sous `self.run_dir.parent`) — cas réel qui a motivé ce
lot : les lots pacman V3→V6 avaient chacun leur propre run_dir, tous vides ;
les verdicts vivaient dans `EVIDENCE/runs/pacman/` (cf.
`test_reconstruction_pacman_v3_projette_les_flags_de_pacman` ci-dessous, la
preuve de sortie exigée par le lot).

Règle ratifiée Pierre, testée telle quelle (ne pas élargir) :
  - seuls les flags du DERNIER verdict SIGNÉ comptent (pas de cumul
    historique, pas de mélange entre plusieurs verdicts) ;
  - aucun registre de résolution, aucune résolution manuelle ;
  - le run courant n'est JAMAIS lu (identifié par `run_id`, pas par
    répertoire) ;
  - le scope projet est décidé par le champ SIGNÉ `project` du verdict, pas
    par un nom de dossier voisin (0 contamination) ;
  - un verdict non signé/invalide est ignoré avec une trace, jamais une
    exception.

Isolation : `run_dir` sous `tmp_path` (jamais le dépôt réel), `journal_path`/
`lessons_path`/`key_file` injectés pour que `_premortem()`/`_open_humangate_
flags()` ne lisent ni n'écrivent le corpus réel ni la clé de signature réelle
(même patron que `test_driver_p2_premortem_playtest.py` et
`test_aggregate_verdict.py`). NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import json
import os
import time
from pathlib import Path

from forge.driver import ForgeDriver
from forge.verdict import _sign_mapping


def _driver(tmp_path: Path, project: str = "pacman", run_id: str | None = None,
            run_dir_name: str = "run") -> ForgeDriver:
    run_dir = tmp_path / run_dir_name
    return ForgeDriver(
        project, run_id or f"{project}-1", run_dir=run_dir, profile="micro",
        journal_path=tmp_path / "journal.jsonl",
        lessons_path=tmp_path / "lessons.jsonl",
        key_file=tmp_path / ".forge_key_test",
    )


def _write_verdict(run_dir: Path, name: str, *, ts: float, flags: list | None,
                    mtime: float | None = None, project: str = "pacman",
                    run_id: str | None = None, key_file: Path | None = None,
                    signed: bool = True) -> Path:
    """Écrit un verdict de test. Signé par défaut (`key_file` requis dans ce
    cas — même clé que celle du driver testé, sinon la vérification échoue
    délibérément). `signed=False` produit un verdict SANS `hmac` (cas de
    preuve « non signé => ignoré »)."""
    run_dir.mkdir(parents=True, exist_ok=True)
    path = run_dir / name
    payload = {"project": project, "run_id": run_id or name, "ts": ts}
    if flags is not None:
        payload["humangate_flags"] = flags
    if signed:
        assert key_file is not None, "key_file requis pour un verdict signé"
        payload["hmac"] = _sign_mapping(payload, key_file)
    path.write_text(json.dumps(payload), encoding="utf-8")
    if mtime is not None:
        os.utime(path, (mtime, mtime))
    return path


_KEY = "forge_key_test"  # nom de fichier clé partagé entre driver et helper


def _key(tmp_path: Path) -> Path:
    return tmp_path / ".forge_key_test"


# --- (1) même run_dir : flags du dernier verdict -----------------------------------

def test_seuls_les_flags_du_verdict_le_plus_recent_sont_injectes(tmp_path):
    d = _driver(tmp_path)
    key = _key(tmp_path)
    now = time.time()
    _write_verdict(d.run_dir, "verdict.json", ts=now - 1000,
                    flags=["flag ANCIEN — ne doit pas apparaître"],
                    run_id="pacman-0", key_file=key)
    _write_verdict(d.run_dir, "verdict_v2.json", ts=now,
                    flags=["flag RECENT — doit apparaître"],
                    run_id="pacman-0b", key_file=key)
    lines = d._premortem()
    assert any("flag RECENT" in l for l in lines)
    assert not any("flag ANCIEN" in l for l in lines)
    assert any(l.startswith("[OUVERT run précédent] flag RECENT") for l in lines)


# --- (2) run_dir FRÈRE du même projet : flags du dernier verdict -------------------

def test_run_dir_frere_du_meme_projet_est_lu(tmp_path):
    d = _driver(tmp_path, run_dir_name="pacman-v3")  # run_dir réel du run courant
    key = _key(tmp_path)
    sibling = tmp_path / "pacman"  # run_dir FRÈRE (même projet, dossier différent)
    _write_verdict(sibling, "verdict_v2.json", ts=time.time(),
                    flags=["flag du run_dir frere"],
                    run_id="pacman-v2-20260805", key_file=key)
    lines = d._open_humangate_flags()
    assert any("flag du run_dir frere" in l for l in lines)


# --- (3) run courant contient un verdict : ne jamais le lire -----------------------

def test_le_run_courant_nest_jamais_lu_meme_si_son_verdict_existe(tmp_path):
    d = _driver(tmp_path, run_id="pacman-CURRENT")
    key = _key(tmp_path)
    now = time.time()
    # Le verdict du run COURANT lui-même (run_id identique à d.run_id), le plus
    # RÉCENT des deux -> s'il était lu, il gagnerait le tri par ts. Il ne doit
    # JAMAIS apparaître.
    _write_verdict(d.run_dir, "verdict.json", ts=now,
                    flags=["FUITE run courant — ne doit jamais apparaître"],
                    run_id="pacman-CURRENT", key_file=key)
    # Un verdict frère, plus ancien mais d'un AUTRE run_id -> doit être choisi.
    sibling = tmp_path / "pacman-prev"
    _write_verdict(sibling, "verdict.json", ts=now - 500,
                    flags=["flag run precedent legitime"],
                    run_id="pacman-PREV", key_file=key)
    lines = d._open_humangate_flags()
    assert not any("FUITE" in l for l in lines)
    assert any("flag run precedent legitime" in l for l in lines)


# --- (4) plusieurs runs frères : dernier valide SEULEMENT (jamais l'union) ---------

def test_plusieurs_runs_freres_seul_le_dernier_valide_compte(tmp_path):
    d = _driver(tmp_path, run_dir_name="pacman-v6")
    key = _key(tmp_path)
    now = time.time()
    for i, (name, ts, flags) in enumerate([
        ("pacman", now - 3000, ["flag v0 — trop vieux"]),
        ("pacman-v2", now - 2000, ["flag v2 — trop vieux"]),
        ("pacman-v4", now - 1000, ["flag v4 — LE dernier valide"]),
    ]):
        rd = tmp_path / name
        _write_verdict(rd, "verdict.json", ts=ts, flags=flags,
                        run_id=f"pacman-hist-{i}", key_file=key)
    lines = d._open_humangate_flags()
    assert any("flag v4" in l for l in lines)
    assert not any("trop vieux" in l for l in lines)
    # Pas d'union : uniquement les flags du verdict le plus récent.
    assert len(lines) == 1


# --- (5) projet voisin au nom proche : 0 contamination -----------------------------

def test_projet_voisin_au_nom_proche_ne_contamine_pas(tmp_path):
    d = _driver(tmp_path, project="pacman", run_dir_name="pacman-v3")
    key = _key(tmp_path)
    now = time.time()
    # Dossier voisin nommé de façon trompeuse ("pacman_v2_autre" commence par
    # "pacman") MAIS son verdict déclare un project DIFFÉRENT -> doit être
    # rejeté même s'il est le plus RÉCENT (gagnerait le tri par ts sinon).
    neighbour = tmp_path / "pacman_v2_autre"
    _write_verdict(neighbour, "verdict.json", ts=now,
                    flags=["CONTAMINATION — projet voisin, ne doit jamais apparaître"],
                    project="pacman_v2_autre", run_id="pacman_v2_autre-1",
                    key_file=key)
    # Le vrai projet "pacman" : verdict légitime, plus ancien.
    legit = tmp_path / "pacman"
    _write_verdict(legit, "verdict.json", ts=now - 100,
                    flags=["flag pacman legitime"],
                    project="pacman", run_id="pacman-legit", key_file=key)
    lines = d._open_humangate_flags()
    assert not any("CONTAMINATION" in l for l in lines)
    assert any("flag pacman legitime" in l for l in lines)

    # Symétrique : le projet voisin ne doit pas non plus aspirer "pacman".
    d2 = _driver(tmp_path, project="pacman_v2_autre", run_dir_name="pacman_v2_autre-run2",
                 run_id="pacman_v2_autre-run2")
    lines2 = d2._open_humangate_flags()
    assert any("CONTAMINATION" in l for l in lines2)  # c'est SON verdict légitime
    assert not any("flag pacman legitime" in l for l in lines2)


# --- (6) aucun verdict => liste vide, non-régression --------------------------------

def test_aucun_verdict_ne_change_rien_au_premortem_existant(tmp_path):
    d = _driver(tmp_path)
    assert d._premortem() == []
    assert d._open_humangate_flags() == []


# --- (6bis) verdict sans humangate_flags / liste vide => rien d'injecté ------------

def test_verdict_sans_humangate_flags_ninjecte_rien(tmp_path):
    d = _driver(tmp_path)
    key = _key(tmp_path)
    _write_verdict(d.run_dir, "verdict.json", ts=time.time(), flags=None,
                    run_id="pacman-x", key_file=key)
    assert d._open_humangate_flags() == []
    assert d._premortem() == []


def test_verdict_avec_liste_de_flags_vide_ninjecte_rien(tmp_path):
    d = _driver(tmp_path)
    key = _key(tmp_path)
    _write_verdict(d.run_dir, "verdict.json", ts=time.time(), flags=[],
                    run_id="pacman-y", key_file=key)
    assert d._open_humangate_flags() == []


# --- (7) verdict illisible/corrompu => best-effort, warning journalisé, pas de crash

def test_verdict_corrompu_est_ignore_sans_exception(tmp_path, caplog):
    d = _driver(tmp_path)
    d.run_dir.mkdir(parents=True, exist_ok=True)
    (d.run_dir / "verdict.json").write_text("{ ceci n'est pas du JSON", encoding="utf-8")
    with caplog.at_level("WARNING"):
        result = d._premortem()
    assert result == []
    assert any("verdict illisible ignoré" in rec.message for rec in caplog.records)


# --- (7bis) verdict SANS hmac (non signé) => ignoré, avec trace --------------------

def test_verdict_non_signe_est_ignore_avec_trace(tmp_path, caplog):
    d = _driver(tmp_path)
    _write_verdict(d.run_dir, "verdict.json", ts=time.time(),
                    flags=["flag jamais transmis — pas de hmac"],
                    run_id="pacman-unsigned", signed=False)
    with caplog.at_level("WARNING"):
        lines = d._open_humangate_flags()
    assert lines == []
    assert any("non signé ignoré" in rec.message for rec in caplog.records)


# --- (7ter) verdict signé avec une MAUVAISE clé (signature invalide) => ignoré -----

def test_verdict_signature_hmac_invalide_est_ignore_avec_trace(tmp_path, caplog):
    d = _driver(tmp_path)
    other_key = tmp_path / "autre_clef_non_reconnue"
    _write_verdict(d.run_dir, "verdict.json", ts=time.time(),
                    flags=["flag jamais transmis — mauvaise signature"],
                    run_id="pacman-badsig", key_file=other_key)
    with caplog.at_level("WARNING"):
        lines = d._open_humangate_flags()
    assert lines == []
    assert any("signature HMAC invalide" in rec.message for rec in caplog.records)


# --- (8) départage ts=0.0 déterministe (mtime du fichier) --------------------------

def test_depart_age_ts_zero_utilise_le_mtime(tmp_path):
    d = _driver(tmp_path)
    key = _key(tmp_path)
    now = time.time()
    # Les deux verdicts portent ts=0.0 (comme les verdicts historiques réels,
    # cf. EVIDENCE/runs/pacman/verdict*.json) : le départage se fait sur le
    # mtime du fichier — le plus récent doit gagner.
    _write_verdict(d.run_dir, "verdict.json", ts=0.0,
                    flags=["flag ANCIEN mtime"], mtime=now - 5000,
                    run_id="pacman-old-mtime", key_file=key)
    _write_verdict(d.run_dir, "verdict_v2.json", ts=0.0,
                    flags=["flag RECENT mtime"], mtime=now,
                    run_id="pacman-new-mtime", key_file=key)
    lines = d._open_humangate_flags()
    assert any("flag RECENT mtime" in l for l in lines)
    assert not any("flag ANCIEN mtime" in l for l in lines)


def test_depart_age_ts_zero_deterministe_entre_deux_run_dir_freres(tmp_path):
    """Même règle de départage (8), mais à travers deux run_dir DIFFÉRENTS
    (portée PROJET) — le mtime décide encore, jamais l'ordre du système de
    fichiers."""
    d = _driver(tmp_path, run_dir_name="pacman-v5")
    key = _key(tmp_path)
    now = time.time()
    older = tmp_path / "pacman"
    newer = tmp_path / "pacman-v2"
    _write_verdict(older, "verdict.json", ts=0.0,
                    flags=["flag frere ANCIEN mtime"], mtime=now - 9000,
                    run_id="pacman-frere-old", key_file=key)
    _write_verdict(newer, "verdict.json", ts=0.0,
                    flags=["flag frere RECENT mtime"], mtime=now,
                    run_id="pacman-frere-new", key_file=key)
    lines = d._open_humangate_flags()
    assert any("flag frere RECENT mtime" in l for l in lines)
    assert not any("flag frere ANCIEN mtime" in l for l in lines)


# --- les lignes ajoutées apparaissent dans _premortem() avec leur préfixe ----------

def test_flags_apparaissent_dans_premortem_avec_prefixe(tmp_path):
    d = _driver(tmp_path)
    key = _key(tmp_path)
    _write_verdict(d.run_dir, "verdict.json", ts=time.time(),
                    flags=["preuve visuelle NOT_MEASURED", "jouabilite non evaluee"],
                    run_id="pacman-z", key_file=key)
    lines = d._premortem()
    assert "[OUVERT run précédent] preuve visuelle NOT_MEASURED" in lines
    assert "[OUVERT run précédent] jouabilite non evaluee" in lines


# --- PREUVE DE SORTIE (rejeu du cas historique réel, cf. commande de fabrication) --

def test_reconstruction_pacman_v3_projette_les_flags_de_pacman(tmp_path):
    """Reproduction ciblée du cas RÉEL qui a motivé P3-B : un `ForgeDriver` du
    projet `pacman` avec `run_dir = EVIDENCE/runs/pacman-v3` (le run_dir réel
    du lot V3, historiquement VIDE de verdict) doit désormais faire remonter
    les flags de `EVIDENCE/runs/pacman/verdict_v2.json` (le run_dir FRÈRE où
    les verdicts vivaient réellement) — 8 flags, ts=0.0 au sommet, exactement
    comme le fichier réel du dépôt. Copie ISOLÉE sous tmp_path, ne touche
    jamais le fichier réel."""
    d = _driver(tmp_path, run_dir_name="pacman-v3")
    key = _key(tmp_path)
    flags = [
        "redteam INDEPENDANT cette fois",
        "metrique 1 ATTEINTE",
        "metrique 2 tenue",
        "preuve VISUELLE (pixel) toujours NOT_MEASURED",
        "jouabilite humaine non evaluee",
        "total mutants 267 -> 263",
        "gate mutation : params.gd exclu",
        "cout V2 = 63 % de V1",
    ]
    pacman_run_dir = tmp_path / "pacman"  # run_dir frère réel : EVIDENCE/runs/pacman
    now = time.time()
    _write_verdict(pacman_run_dir, "verdict.json", ts=0.0,
                    flags=["flag v1 pacman — plus ancien, ne doit pas apparaître"],
                    run_id="pacman-20260805-r1", key_file=key, mtime=now - 1000)
    _write_verdict(pacman_run_dir, "verdict_v2.json", ts=0.0, flags=flags,
                    run_id="pacman-v2-20260805", key_file=key,
                    mtime=now)  # le plus récent par mtime (ts=0.0 historique)
    lines = d._open_humangate_flags()
    assert len(lines) == 8
    for f in flags:
        assert any(f in l for l in lines)
