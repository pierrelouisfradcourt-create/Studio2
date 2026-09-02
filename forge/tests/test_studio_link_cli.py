"""Oracle des sous-commandes CLI de `studio_link.main` — tâche B/C (commande de
fabrication « brancher quatre fonctions Forge qui n'ont aucun appelant »).

`record_playtest` / `record_global_lesson` / `propose_bible_entry` avaient déjà un
consommateur prouvé (error_journal relu par `premortem` ; `pending_review.mjs` pour
la bible) mais AUCUN appelant — consigner un playtest ou une leçon de méthode est un
acte HUMAIN, ces sous-commandes sont l'appelant (un terminal, pas de la prose perdue
dans un document).

Garanties testées :
  - chaque sous-commande écrit RÉELLEMENT (via les fonctions existantes, testées par
    ailleurs dans test_studio_link.py) et affiche où ;
  - des arguments manquants/invalides -> code de sortie non nul, message d'usage sur
    stderr, JAMAIS d'écriture partielle ni de trace Python nue ;
  - l'entrée CLI PRÉ-EXISTANTE (`--write`, sans sous-commande) reste inchangée
    (couverte par ailleurs dans test_journal_index_autowire.py::test_cli_write_reste_fonctionnel,
    non dupliquée ici).
"""
import json

import pytest

from forge import studio_link as sl


# --- playtest --------------------------------------------------------------------

def test_playtest_subcommand_ecrit_et_rapporte_le_chemin(tmp_path, capsys):
    journal = tmp_path / "playtest.jsonl"
    rc = sl.main([
        "playtest",
        "--project", "shmup_slice",
        "--constat", "le boss 3 est invisible sur fond noir",
        "--regle-observable", "contour >= 2px contrastant sur tout sprite ennemi",
        "--run-id", "playtest-test",
        "--journal-path", str(journal),
    ])
    assert rc == 0
    out = capsys.readouterr().out
    assert str(journal) in out
    assert journal.exists()
    row = json.loads(journal.read_text(encoding="utf-8").strip())
    assert row["project"] == "shmup_slice"
    assert row["error"] == "le boss 3 est invisible sur fond noir"
    assert row["resolution"] == "contour >= 2px contrastant sur tout sprite ennemi"
    assert row["run_id"] == "playtest-test"
    assert row["status"] == "fixed"


def test_playtest_subcommand_argument_manquant_code_non_nul_pas_d_ecriture(tmp_path, capsys):
    journal = tmp_path / "playtest.jsonl"
    rc = sl.main([
        "playtest",
        "--project", "shmup_slice",
        "--constat", "sans regle observable",
        # --regle-observable manquant volontairement
        "--journal-path", str(journal),
    ])
    assert rc != 0
    assert not journal.exists(), "argument manquant -> AUCUNE écriture partielle"
    err = capsys.readouterr().err
    assert "usage" in err.lower()
    assert "regle-observable" in err.lower()


# --- lesson ------------------------------------------------------------------------

def test_lesson_subcommand_ecrit_et_rapporte_le_chemin(tmp_path, capsys):
    journal = tmp_path / "global.jsonl"
    rc = sl.main([
        "lesson",
        "--etape", "s9-build",
        "--lesson", "toujours vérifier la lisibilité d'un sprite sur son fond avant merge",
        "--journal-path", str(journal),
    ])
    assert rc == 0
    out = capsys.readouterr().out
    assert str(journal) in out
    row = json.loads(journal.read_text(encoding="utf-8").strip())
    assert row["etape"] == "s9-build"
    assert row["project"] == sl.GLOBAL_SCOPE
    assert row["run_id"] == "_method_"


def test_lesson_subcommand_argument_manquant_code_non_nul(tmp_path, capsys):
    journal = tmp_path / "global.jsonl"
    rc = sl.main(["lesson", "--etape", "s9-build", "--journal-path", str(journal)])
    assert rc != 0
    assert not journal.exists()
    assert "usage" in capsys.readouterr().err.lower()


def test_lesson_atteint_le_premortem_de_tout_projet(tmp_path, capsys):
    """Ferme la boucle bout-en-bout : la leçon écrite par la CLI est bien relue par
    `premortem` (le consommateur déjà prouvé), pour un projet QUELCONQUE."""
    journal = tmp_path / "global.jsonl"
    sl.main(["lesson", "--etape", "s9-build", "--lesson", "leçon via CLI",
             "--journal-path", str(journal)])
    pm = sl.premortem("un_projet_quelconque", journal_path=journal)
    assert any("leçon via CLI" in x for x in pm)


# --- bible ---------------------------------------------------------------------

def test_bible_subcommand_ecrit_et_rapporte_le_chemin(tmp_path, capsys):
    proposals = tmp_path / "bible.jsonl"
    rc = sl.main([
        "bible",
        "--project", "shmup_slice",
        "--kind", "abandoned",
        "--decision", "boss unique par vague",
        "--rationale", "3 boss simultanés illisibles en playtest",
        "--proposals-path", str(proposals),
    ])
    assert rc == 0
    out = capsys.readouterr().out
    assert str(proposals) in out
    row = json.loads(proposals.read_text(encoding="utf-8").strip())
    assert row["project"] == "shmup_slice"
    assert row["kind"] == "abandoned"
    assert row["status"] == "PROPOSED"


def test_bible_subcommand_kind_invalide_rejete_par_argparse_code_non_nul(tmp_path, capsys):
    proposals = tmp_path / "bible.jsonl"
    rc = sl.main([
        "bible",
        "--project", "shmup_slice",
        "--kind", "pas_une_valeur_valide",
        "--decision", "x",
        "--rationale", "y",
        "--proposals-path", str(proposals),
    ])
    assert rc != 0
    assert not proposals.exists()
    err = capsys.readouterr().err
    assert "usage" in err.lower()
    assert "kind" in err.lower()


def test_bible_subcommand_argument_manquant_code_non_nul(tmp_path, capsys):
    proposals = tmp_path / "bible.jsonl"
    rc = sl.main(["bible", "--project", "shmup_slice", "--proposals-path", str(proposals)])
    assert rc != 0
    assert not proposals.exists()


# --- brick (le dépositaire) -----------------------------------------------------

def test_brick_subcommand_ecrit_et_rapporte_le_chemin(tmp_path, capsys):
    proposals = tmp_path / "brick.jsonl"
    rc = sl.main([
        "brick",
        "--project", "shmup_slice",
        "--run-id", "shmup_slice-1",
        "--brick-id", "sys-damage-floor-shield-m01",
        "--kind", "system",
        "--function", "plancher de degats + bouclier partage",
        "--path", "GAMES/shmup_slice/logic/collisions.mjs",
        "--proposals-path", str(proposals),
    ])
    assert rc == 0
    out = capsys.readouterr().out
    assert str(proposals) in out
    row = json.loads(proposals.read_text(encoding="utf-8").strip())
    assert row["project"] == "shmup_slice"
    assert row["brick_id"] == "sys-damage-floor-shield-m01"
    assert row["type"] == "brick"
    assert row["status"] == "PROPOSED"


def test_brick_subcommand_kind_invalide_rejete_par_argparse_code_non_nul(tmp_path, capsys):
    proposals = tmp_path / "brick.jsonl"
    rc = sl.main([
        "brick",
        "--project", "shmup_slice",
        "--run-id", "shmup_slice-1",
        "--brick-id", "b1",
        "--kind", "pas_une_valeur_valide",
        "--function", "f",
        "--path", "GAMES/shmup_slice/x.mjs",
        "--proposals-path", str(proposals),
    ])
    assert rc != 0
    assert not proposals.exists()
    err = capsys.readouterr().err
    assert "usage" in err.lower()
    assert "kind" in err.lower()


def test_brick_subcommand_argument_manquant_code_non_nul_pas_d_ecriture(tmp_path, capsys):
    proposals = tmp_path / "brick.jsonl"
    rc = sl.main([
        "brick",
        "--project", "shmup_slice",
        "--run-id", "shmup_slice-1",
        "--brick-id", "b1",
        "--kind", "system",
        # --function manquant volontairement
        "--path", "GAMES/shmup_slice/x.mjs",
        "--proposals-path", str(proposals),
    ])
    assert rc != 0
    assert not proposals.exists()
    err = capsys.readouterr().err
    assert "usage" in err.lower()
    assert "function" in err.lower()


# --- garde-fou : --write pré-existant toujours accessible sans sous-commande ------

def test_aucune_sous_commande_donnee_comportement_index_inchange(tmp_path, monkeypatch, capsys):
    """Sans sous-commande (juste `--write` ou rien), le comportement historique
    (index des journaux) reste seul actif — pas de sous-commande = pas de branche
    playtest/lesson/bible empruntée."""
    monkeypatch.setattr(sl, "FORGE_REPORTS", tmp_path / "reports")
    rc = sl.main([])
    assert rc == 0
    out = capsys.readouterr().out
    assert "Journaux d'erreurs Forge par domaine" in out
