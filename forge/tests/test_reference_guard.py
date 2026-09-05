"""forge.reference_guard — détection mécanique de modification des arbres protégés
(mission FVL Phase 0.5, volet DÉTECTION uniquement). Couvre :

  - la configuration (fichier de DONNÉES, jamais un chemin en dur) ;
  - l'énumération du témoin via `git ls-files --cached --others --exclude-standard`
    (respecte .gitignore, catch le bruit .godot/__pycache__ comme un vrai run le
    ferait — incident témoin Pong déjà ratifié 2026-07-28) ;
  - l'empreinte (déterminisme, fichier illisible rapporté sans lever, fichier
    disparu classé SUPPRIMÉ et non « illisible ») ;
  - la baseline (enregistrer / charger) ;
  - la comparaison typée AJOUTÉ/MODIFIÉ/SUPPRIMÉ ;
  - la dérogation humaine (lecture seule, best-effort) ;
  - `verify`/`advisory_check` (jamais de gate, jamais de verdict, best-effort STRICT) ;
  - la CLI (compute/record/verify).

Aucun test de ce fichier n'écrit dans `GAMES/pong/**` ni `tests/**` du dépôt réel :
chaque test construit son propre petit dépôt git jetable sous `tmp_path` — l'objet
même que ce module protège n'est jamais touché pour le tester (le contraire aurait
invalidé la baseline réelle que ce chantier a pour but de protéger)."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest
import yaml

from forge import reference_guard as rg


# --- fixtures : un petit dépôt git jetable, jamais le dépôt réel --------------------

def _git(repo: Path, *args: str) -> None:
    subprocess.run(["git", *args], cwd=str(repo), check=True,
                    capture_output=True, timeout=30)


def _commit_all(repo: Path, message: str = "snapshot") -> None:
    _git(repo, "add", "-A")
    _git(repo, "-c", "user.email=test@example.com", "-c", "user.name=Test",
         "commit", "-q", "-m", message)


def _make_repo(tmp_path: Path) -> Path:
    """Dépôt git jetable : GAMES/pong/** + tests/** minimal, PLUS du bruit gitignoré
    (cache .godot/, __pycache__) — même profil que le vrai dépôt, pour prouver que ce
    bruit n'entre jamais dans l'empreinte."""
    repo = tmp_path / "repo"
    (repo / "GAMES" / "pong" / "sub").mkdir(parents=True)
    (repo / "tests").mkdir(parents=True)
    (repo / "GAMES" / "pong" / "main.gd").write_text("extends Node\n", encoding="utf-8")
    (repo / "GAMES" / "pong" / "sub" / "ball.gd").write_text("extends Area2D\n", encoding="utf-8")
    (repo / "tests" / "test_x.py").write_text("def test_x():\n    assert True\n", encoding="utf-8")
    (repo / ".gitignore").write_text("__pycache__/\n.godot/\n", encoding="utf-8")

    noise_dir = repo / "GAMES" / "pong" / ".godot" / "shader_cache"
    noise_dir.mkdir(parents=True)
    (noise_dir / "junk.cache").write_bytes(b"\x00\x01\x02")
    pycache = repo / "tests" / "__pycache__"
    pycache.mkdir()
    (pycache / "test_x.cpython-312.pyc").write_bytes(b"\x00")

    _git(repo, "init", "-q")
    _commit_all(repo, "init")
    return repo


def _config_path(tmp_path: Path, protected=None, derogation_path=".derogation.json",
                  name="reference_protected_test.yaml") -> Path:
    cfg = tmp_path / name
    protected = protected if protected is not None else ["GAMES/pong/**", "tests/**"]
    cfg.write_text(
        yaml.safe_dump({"protected": protected, "derogation_path": derogation_path}),
        encoding="utf-8",
    )
    return cfg


# --- configuration --------------------------------------------------------------------

def test_load_config_valid(tmp_path):
    cfg_path = _config_path(tmp_path)
    config = rg.load_config(cfg_path)
    assert config["protected"] == ["GAMES/pong/**", "tests/**"]
    assert config["derogation_path"] == ".derogation.json"
    assert config["source_path"] == str(cfg_path)


def test_load_config_missing_file_raises(tmp_path):
    with pytest.raises(rg.ReferenceGuardError, match="introuvable"):
        rg.load_config(tmp_path / "nope.yaml")


def test_load_config_empty_protected_list_raises(tmp_path):
    cfg = tmp_path / "empty.yaml"
    cfg.write_text(yaml.safe_dump({"protected": []}), encoding="utf-8")
    with pytest.raises(rg.ReferenceGuardError, match="vide"):
        rg.load_config(cfg)


def test_load_config_protected_missing_key_raises(tmp_path):
    cfg = tmp_path / "no_key.yaml"
    cfg.write_text(yaml.safe_dump({"derogation_path": "x.json"}), encoding="utf-8")
    with pytest.raises(rg.ReferenceGuardError):
        rg.load_config(cfg)


def test_load_config_non_string_item_raises(tmp_path):
    cfg = tmp_path / "bad_item.yaml"
    cfg.write_text(yaml.safe_dump({"protected": ["GAMES/pong/**", 42]}), encoding="utf-8")
    with pytest.raises(rg.ReferenceGuardError):
        rg.load_config(cfg)


def test_load_config_malformed_yaml_raises(tmp_path):
    cfg = tmp_path / "malformed.yaml"
    cfg.write_text("protected: [unclosed\n", encoding="utf-8")
    with pytest.raises(rg.ReferenceGuardError):
        rg.load_config(cfg)


def test_load_config_root_not_object_raises(tmp_path):
    cfg = tmp_path / "root_list.yaml"
    cfg.write_text(yaml.safe_dump(["GAMES/pong/**"]), encoding="utf-8")
    with pytest.raises(rg.ReferenceGuardError):
        rg.load_config(cfg)


def test_load_config_default_derogation_when_absent(tmp_path):
    cfg = tmp_path / "no_derog.yaml"
    cfg.write_text(yaml.safe_dump({"protected": ["GAMES/pong/**"]}), encoding="utf-8")
    config = rg.load_config(cfg)
    assert config["derogation_path"] == ".claude/HUMAN_GIT_OVERRIDE.json"


# --- énumération du témoin (git) -------------------------------------------------------

def test_resolve_protected_files_respects_gitignore_and_untracked(tmp_path):
    repo = _make_repo(tmp_path)
    files = rg.resolve_protected_files(["GAMES/pong/**", "tests/**"], repo)
    assert files == sorted(files)  # trié
    assert "GAMES/pong/main.gd" in files
    assert "GAMES/pong/sub/ball.gd" in files
    assert "tests/test_x.py" in files
    # le bruit gitignoré ne doit JAMAIS apparaître
    assert not any(".godot" in f for f in files)
    assert not any("__pycache__" in f for f in files)


def test_resolve_protected_files_includes_untracked_not_ignored(tmp_path):
    """Un fichier neuf, jamais `git add`é, DOIT apparaître (c'est exactement le cas
    d'un sous-processus qui écrit sans jamais committer)."""
    repo = _make_repo(tmp_path)
    (repo / "GAMES" / "pong" / "rogue.gd").write_text("extends Node\n", encoding="utf-8")
    files = rg.resolve_protected_files(["GAMES/pong/**"], repo)
    assert "GAMES/pong/rogue.gd" in files


def test_resolve_protected_files_nonexistent_path_raises(tmp_path):
    repo = _make_repo(tmp_path)
    with pytest.raises(rg.ReferenceGuardError, match="inexistant"):
        rg.resolve_protected_files(["GAMES/nope/**"], repo)


def test_resolve_protected_files_zero_coverage_raises(tmp_path):
    """Un chemin qui EXISTE sur disque mais ne couvre aucun fichier (suivi ou
    présent-non-ignoré) est une ERREUR — jamais une liste vide silencieuse."""
    repo = _make_repo(tmp_path)
    (repo / "GAMES" / "pong" / "emptyish").mkdir()
    with pytest.raises(rg.ReferenceGuardError, match="AUCUN fichier"):
        rg.resolve_protected_files(["GAMES/pong/emptyish/**"], repo)


def test_resolve_protected_files_deterministic(tmp_path):
    repo = _make_repo(tmp_path)
    a = rg.resolve_protected_files(["GAMES/pong/**", "tests/**"], repo)
    b = rg.resolve_protected_files(["GAMES/pong/**", "tests/**"], repo)
    assert a == b


# --- empreinte --------------------------------------------------------------------------

def test_compute_fingerprint_deterministic(tmp_path):
    repo = _make_repo(tmp_path)
    protected = ["GAMES/pong/**", "tests/**"]
    fp1 = rg.compute_fingerprint(protected, repo)
    fp2 = rg.compute_fingerprint(protected, repo)
    assert fp1["combined_sha256"] == fp2["combined_sha256"]
    assert fp1["file_count"] == fp2["file_count"] == 3
    assert fp1["complete"] is True
    assert fp1["unreadable"] == []


def test_compute_fingerprint_detects_uncommitted_disk_change(tmp_path):
    """Le coeur de la garantie : un contenu modifié sur disque SANS commit (le cas
    nommé par la doctrine — sous-processus, build Godot, exécuteur, script) change
    l'empreinte, parce que le hash lit le DISQUE, jamais l'objet git."""
    repo = _make_repo(tmp_path)
    protected = ["GAMES/pong/**", "tests/**"]
    before = rg.compute_fingerprint(protected, repo)
    (repo / "GAMES" / "pong" / "main.gd").write_text("extends Node2D  # modifié\n",
                                                      encoding="utf-8")
    after = rg.compute_fingerprint(protected, repo)
    assert before["combined_sha256"] != after["combined_sha256"]
    assert before["files"]["GAMES/pong/main.gd"] != after["files"]["GAMES/pong/main.gd"]


def test_compute_fingerprint_unreadable_file_reported_not_raised(tmp_path, monkeypatch):
    repo = _make_repo(tmp_path)
    protected = ["GAMES/pong/**", "tests/**"]

    real_sha256 = rg._sha256_of

    def _boom(path):
        if path.name == "main.gd":
            raise PermissionError("simulé : accès refusé")
        return real_sha256(path)

    monkeypatch.setattr(rg, "_sha256_of", _boom)
    fp = rg.compute_fingerprint(protected, repo)
    assert fp["complete"] is False
    assert any(u["path"] == "GAMES/pong/main.gd" for u in fp["unreadable"])
    assert "GAMES/pong/main.gd" not in fp["files"]


def test_compute_fingerprint_deleted_file_is_removed_not_unreadable(tmp_path):
    """Un fichier SUIVI (git add) mais supprimé du disque sans `git rm` doit être
    absent de `files` (donc SUPPRIMÉ via compare_to_baseline) SANS polluer
    `unreadable` — le sort du fichier est connu avec certitude, ce n'est pas une
    incertitude de lecture."""
    repo = _make_repo(tmp_path)
    protected = ["GAMES/pong/**", "tests/**"]
    (repo / "GAMES" / "pong" / "main.gd").unlink()
    fp = rg.compute_fingerprint(protected, repo)
    assert fp["complete"] is True
    assert fp["unreadable"] == []
    assert "GAMES/pong/main.gd" not in fp["files"]


# --- baseline -----------------------------------------------------------------------

def test_record_and_load_baseline_roundtrip(tmp_path):
    repo = _make_repo(tmp_path)
    cfg_path = _config_path(tmp_path)
    baseline_path = tmp_path / "baseline.json"
    record = rg.record_baseline(config_path=cfg_path, baseline_path=baseline_path,
                                 repo_root=repo)
    assert baseline_path.exists()
    assert record["file_count"] == 3
    loaded = rg.load_baseline(baseline_path)
    assert loaded["combined_sha256"] == record["combined_sha256"]
    assert loaded["schema"] == rg.BASELINE_SCHEMA


def test_load_baseline_none_when_absent(tmp_path):
    assert rg.load_baseline(tmp_path / "nope.json") is None


def test_load_baseline_raises_on_corrupt_json(tmp_path):
    path = tmp_path / "corrupt.json"
    path.write_text("{not json", encoding="utf-8")
    with pytest.raises(rg.ReferenceGuardError):
        rg.load_baseline(path)


def test_record_baseline_refuses_incomplete_fingerprint(tmp_path, monkeypatch):
    repo = _make_repo(tmp_path)
    cfg_path = _config_path(tmp_path)
    monkeypatch.setattr(
        rg, "compute_fingerprint",
        lambda protected, repo_root=None: {
            "schema": rg.FINGERPRINT_SCHEMA, "files": {}, "unreadable": [{"path": "x", "error": "e"}],
            "file_count": 0, "combined_sha256": "x", "complete": False,
        },
    )
    with pytest.raises(rg.ReferenceGuardError, match="incomplète"):
        rg.record_baseline(config_path=cfg_path, baseline_path=tmp_path / "b.json", repo_root=repo)


# --- comparaison typée -----------------------------------------------------------------

def test_compare_to_baseline_added_modified_removed():
    baseline = {"files": {"a.txt": "hash_a", "b.txt": "hash_b"}}
    current = {"files": {"a.txt": "hash_a_MODIFIED", "c.txt": "hash_c"}}
    diffs = rg.compare_to_baseline(current, baseline)
    by_path = {d["path"]: d["kind"] for d in diffs}
    assert by_path["a.txt"] == rg.KIND_MODIFIED
    assert by_path["b.txt"] == rg.KIND_REMOVED
    assert by_path["c.txt"] == rg.KIND_ADDED


def test_compare_to_baseline_no_diff_when_identical():
    same = {"files": {"a.txt": "hash_a"}}
    assert rg.compare_to_baseline(same, same) == []


# --- dérogation humaine ------------------------------------------------------------------

def test_read_derogation_absent_file(tmp_path):
    result = rg._read_derogation(tmp_path / "nope.json")
    assert result == {"paths": set(), "reason": "", "present": False}


def test_read_derogation_malformed_json_is_no_derogation(tmp_path):
    path = tmp_path / "bad.json"
    path.write_text("{not json", encoding="utf-8")
    result = rg._read_derogation(path)
    assert result["present"] is False
    assert result["paths"] == set()


def test_read_derogation_valid_file(tmp_path):
    path = tmp_path / "derog.json"
    path.write_text(json.dumps({"reason": "hotfix ratifié Pierre",
                                "paths": ["GAMES/pong/main.gd"],
                                "timestamp_epoch": 0}), encoding="utf-8")
    result = rg._read_derogation(path)
    assert result["present"] is True
    assert result["paths"] == {"GAMES/pong/main.gd"}
    assert result["reason"] == "hotfix ratifié Pierre"


# --- vérification bout-en-bout ----------------------------------------------------------

def test_verify_no_baseline_is_not_an_error(tmp_path):
    repo = _make_repo(tmp_path)
    cfg_path = _config_path(tmp_path)
    report = rg.verify(config_path=cfg_path, baseline_path=tmp_path / "no_baseline.json",
                        repo_root=repo)
    assert report["status"] == rg.STATUS_NO_BASELINE
    assert report["diffs"] == []


def test_verify_clean_when_unchanged(tmp_path):
    repo = _make_repo(tmp_path)
    cfg_path = _config_path(tmp_path)
    baseline_path = tmp_path / "baseline.json"
    rg.record_baseline(config_path=cfg_path, baseline_path=baseline_path, repo_root=repo)
    report = rg.verify(config_path=cfg_path, baseline_path=baseline_path, repo_root=repo)
    assert report["status"] == rg.STATUS_CLEAN
    assert report["diffs"] == []


def test_verify_drift_on_unauthorized_change(tmp_path):
    repo = _make_repo(tmp_path)
    cfg_path = _config_path(tmp_path)
    baseline_path = tmp_path / "baseline.json"
    rg.record_baseline(config_path=cfg_path, baseline_path=baseline_path, repo_root=repo)
    (repo / "GAMES" / "pong" / "main.gd").write_text("extends Node2D  # hack\n",
                                                      encoding="utf-8")
    report = rg.verify(config_path=cfg_path, baseline_path=baseline_path, repo_root=repo)
    assert report["status"] == rg.STATUS_DRIFT
    assert len(report["diffs"]) == 1
    assert report["diffs"][0]["kind"] == rg.KIND_MODIFIED
    assert report["diffs"][0]["path"] == "GAMES/pong/main.gd"
    assert report["diffs"][0]["authorized"] is False


def test_verify_authorized_when_derogation_covers_the_path(tmp_path):
    repo = _make_repo(tmp_path)
    derog_path = repo / ".derogation.json"
    derog_path.write_text(
        json.dumps({"reason": "correction ratifiée Pierre", "paths": ["GAMES/pong/main.gd"],
                    "timestamp_epoch": 0}),
        encoding="utf-8",
    )
    cfg_path = _config_path(tmp_path, derogation_path=".derogation.json")
    baseline_path = tmp_path / "baseline.json"
    rg.record_baseline(config_path=cfg_path, baseline_path=baseline_path, repo_root=repo)
    (repo / "GAMES" / "pong" / "main.gd").write_text("extends Node2D  # ratifié\n",
                                                      encoding="utf-8")
    report = rg.verify(config_path=cfg_path, baseline_path=baseline_path, repo_root=repo)
    assert report["status"] == rg.STATUS_AUTHORIZED
    assert report["diffs"][0]["authorized"] is True
    assert report["diffs"][0]["derogation_reason"] == "correction ratifiée Pierre"


def test_verify_drift_when_derogation_covers_a_different_path(tmp_path):
    repo = _make_repo(tmp_path)
    derog_path = repo / ".derogation.json"
    derog_path.write_text(
        json.dumps({"reason": "x", "paths": ["GAMES/pong/sub/ball.gd"], "timestamp_epoch": 0}),
        encoding="utf-8",
    )
    cfg_path = _config_path(tmp_path, derogation_path=".derogation.json")
    baseline_path = tmp_path / "baseline.json"
    rg.record_baseline(config_path=cfg_path, baseline_path=baseline_path, repo_root=repo)
    (repo / "GAMES" / "pong" / "main.gd").write_text("extends Node2D  # hack\n",
                                                      encoding="utf-8")
    report = rg.verify(config_path=cfg_path, baseline_path=baseline_path, repo_root=repo)
    assert report["status"] == rg.STATUS_DRIFT
    assert report["diffs"][0]["authorized"] is False


def test_verify_incomplete_takes_precedence_over_drift(tmp_path, monkeypatch):
    repo = _make_repo(tmp_path)
    cfg_path = _config_path(tmp_path)
    baseline_path = tmp_path / "baseline.json"
    rg.record_baseline(config_path=cfg_path, baseline_path=baseline_path, repo_root=repo)

    real = rg.compute_fingerprint

    def _partial(protected, repo_root=None):
        fp = real(protected, repo_root)
        fp = dict(fp)
        fp["unreadable"] = [{"path": "GAMES/pong/main.gd", "error": "simulé"}]
        fp["complete"] = False
        return fp

    monkeypatch.setattr(rg, "compute_fingerprint", _partial)
    report = rg.verify(config_path=cfg_path, baseline_path=baseline_path, repo_root=repo)
    assert report["status"] == rg.STATUS_INCOMPLETE


def test_verify_error_on_bad_config(tmp_path):
    report = rg.verify(config_path=tmp_path / "nope.yaml", repo_root=tmp_path)
    assert report["status"] == rg.STATUS_ERROR
    assert "error" in report


def test_verify_error_on_corrupt_baseline(tmp_path):
    repo = _make_repo(tmp_path)
    cfg_path = _config_path(tmp_path)
    bad_baseline = tmp_path / "bad_baseline.json"
    bad_baseline.write_text("{not json", encoding="utf-8")
    report = rg.verify(config_path=cfg_path, baseline_path=bad_baseline, repo_root=repo)
    assert report["status"] == rg.STATUS_ERROR


# --- advisory_check : best-effort STRICT, jamais d'exception -----------------------------

def test_advisory_check_never_raises_on_internal_exception(monkeypatch):
    def _boom(**kwargs):
        raise RuntimeError("panne simulée")

    monkeypatch.setattr(rg, "verify", _boom)
    report = rg.advisory_check("open")
    assert report["status"] == rg.STATUS_ERROR
    assert report["phase"] == "open"
    assert "panne simulée" in report["error"]


def test_advisory_check_tags_phase(tmp_path):
    repo = _make_repo(tmp_path)
    cfg_path = _config_path(tmp_path)
    report = rg.advisory_check("close", config_path=cfg_path,
                               baseline_path=tmp_path / "nope.json", repo_root=repo)
    assert report["phase"] == "close"
    assert report["status"] == rg.STATUS_NO_BASELINE


# --- intégration réelle (lecture seule) : le vrai dépôt, jamais écrit -------------------

def test_compute_fingerprint_on_real_repo_is_nonempty_and_readable():
    """Sanity check d'intégration : calcule (lecture seule, n'écrit RIEN) l'empreinte
    réelle de GAMES/pong/** + tests/** du dépôt courant."""
    config = rg.load_config()  # config PRODUCTION réelle (forge/reference_protected.yaml)
    fp = rg.compute_fingerprint(config["protected"])
    assert fp["file_count"] > 0
    assert fp["complete"] is True
    assert len(fp["combined_sha256"]) == 64


# --- CLI ----------------------------------------------------------------------------------

def test_cli_compute_prints_fingerprint(tmp_path, capsys, monkeypatch):
    repo = _make_repo(tmp_path)
    cfg_path = _config_path(tmp_path)  # défaut inchangé : GAMES/pong/** + tests/** existent dans le jetable
    # compute() n'expose pas --repo-root : on pointe REPO_ROOT du module sur le dépôt
    # jetable, même isolement que test_cli_record_then_verify_roundtrip — le dépôt RÉEL
    # n'entre pas dans ce test (son intégration est couverte par
    # test_compute_fingerprint_on_real_repo_is_nonempty_and_readable). GO Pierre 2026-09-05 (U6).
    monkeypatch.setattr(rg, "REPO_ROOT", repo)
    rc = rg.main(["compute", "--config", str(cfg_path)])
    assert rc == 0
    out = capsys.readouterr().out
    payload = json.loads(out)
    assert payload["schema"] == rg.FINGERPRINT_SCHEMA
    assert "combined_sha256" in payload
    assert payload["file_count"] == 3  # main.gd, sub/ball.gd, tests/test_x.py : la fixture est réellement lue
    assert payload["complete"] is True


def test_cli_compute_bad_config_exits_nonzero(tmp_path, capsys):
    rc = rg.main(["compute", "--config", str(tmp_path / "nope.yaml")])
    assert rc == 2
    assert "erreur" in capsys.readouterr().err


def test_cli_record_then_verify_roundtrip(tmp_path, capsys, monkeypatch):
    repo = _make_repo(tmp_path)
    cfg_path = _config_path(tmp_path)
    baseline_path = tmp_path / "baseline.json"
    # `record`/`verify` CLI passent par REPO_ROOT réel en interne (compute_fingerprint
    # sans repo_root) ; on isole donc en monkeypatchant REPO_ROOT du module pour cette
    # invocation CLI, seule façon de pointer la CLI sur le dépôt jetable de test.
    monkeypatch.setattr(rg, "REPO_ROOT", repo)
    rc_record = rg.main(["record", "--config", str(cfg_path), "--baseline", str(baseline_path)])
    assert rc_record == 0
    assert baseline_path.exists()
    out = capsys.readouterr().out
    assert str(baseline_path) in out

    rc_verify = rg.main(["verify", "--config", str(cfg_path), "--baseline", str(baseline_path)])
    assert rc_verify == 0
    report = json.loads(capsys.readouterr().out)
    assert report["status"] == rg.STATUS_CLEAN


def test_cli_no_subcommand_prints_usage(capsys):
    rc = rg.main([])
    assert rc == 2
    assert "usage" in capsys.readouterr().err.lower()
