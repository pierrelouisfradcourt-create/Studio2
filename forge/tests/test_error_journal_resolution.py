"""Oracle de la « 2e colonne » du journal d'erreurs PILOU (connecteur 6).

Le journal ne capture plus seulement l'échec mais AUSSI sa réparation (`resolution`),
pour que le run suivant apprenne la RÉPARATION et pas juste l'erreur. Ce fichier est
NOUVEAU : il ne touche à aucun test existant. Tout est écrit dans un journal tmp_path.
"""
import json

from forge import studio_link as sl


def test_record_fix_writes_fixed_status_and_resolution(tmp_path):
    """record_fix consigne l'erreur ET sa réparation en une entrée status=fixed."""
    j = tmp_path / "journal.jsonl"
    sl.record_fix("r1", "s9-build", "oracle rouge : import manquant",
                  "ajout de l'import dans main.ts", project="leviathan", journal_path=j)
    rows = [json.loads(l) for l in j.read_text(encoding="utf-8").splitlines() if l.strip()]
    assert len(rows) == 1
    assert rows[0]["status"] == "fixed"
    assert rows[0]["resolution"] == "ajout de l'import dans main.ts"
    assert rows[0]["error"] == "oracle rouge : import manquant"


def test_record_error_without_resolution_is_open(tmp_path):
    """record_error sans resolution → status=open, resolution=None."""
    j = tmp_path / "journal.jsonl"
    sl.record_error("r1", "s4-archi", "cycle de deps détecté", project="leviathan", journal_path=j)
    rows = [json.loads(l) for l in j.read_text(encoding="utf-8").splitlines() if l.strip()]
    assert len(rows) == 1
    assert rows[0]["status"] == "open"
    assert rows[0]["resolution"] is None


def test_record_error_with_resolution_is_fixed(tmp_path):
    """record_error avec resolution renseignée → status=fixed (chemin paramétrique)."""
    j = tmp_path / "journal.jsonl"
    sl.record_error("r1", "s9-build", "test qui casse", project="leviathan",
                    journal_path=j, resolution="corrigé le sélecteur e2e")
    rows = [json.loads(l) for l in j.read_text(encoding="utf-8").splitlines() if l.strip()]
    assert rows[0]["status"] == "fixed"
    assert rows[0]["resolution"] == "corrigé le sélecteur e2e"


def test_premortem_surfaces_repair_for_fixed_entry(tmp_path):
    """premortem fait apparaître « → ✅ RÉPARÉ: … » pour une entrée fixed, pas pour une open."""
    j = tmp_path / "journal.jsonl"
    sl.record_fix("r1", "s9-build", "oracle rouge : import manquant",
                  "ajout de l'import dans main.ts", project="leviathan", journal_path=j)
    sl.record_error("r1", "s4-archi", "cycle de deps détecté", project="leviathan", journal_path=j)
    pm = sl.premortem("leviathan", journal_path=j)
    fixed_line = next(x for x in pm if "import manquant" in x)
    open_line = next(x for x in pm if "cycle de deps" in x)
    assert "✅ RÉPARÉ: ajout de l'import dans main.ts" in fixed_line
    assert "RÉPARÉ" not in open_line


def test_premortem_backward_compatible_with_legacy_entries(tmp_path):
    """Rétrocompat : une entrée à l'ancienne (sans resolution/status) est surfacée sans exception."""
    j = tmp_path / "journal.jsonl"
    # Entrée écrite « à la main » au format historique : ni resolution ni status.
    legacy = {"run_id": "old-1", "etape": "s10a", "project": "leviathan",
              "error": "vieux bug sans colonne resolution", "ts": 1.0}
    j.write_text(json.dumps(legacy, ensure_ascii=False) + "\n", encoding="utf-8")
    # Ne doit lever aucune exception et surfacer l'erreur telle quelle (sans RÉPARÉ).
    pm = sl.premortem("leviathan", journal_path=j)
    legacy_line = next(x for x in pm if "vieux bug sans colonne resolution" in x)
    assert "RÉPARÉ" not in legacy_line


def test_premortem_shows_repair_on_global_lesson_with_resolution(tmp_path):
    """Une leçon globale porteuse d'une réparation garde ⚑ ET montre la 2e colonne."""
    j = tmp_path / "journal.jsonl"
    sl.record_error("_method_", "s10a", "oracle vert ≠ jeu solvable",
                    project=sl.GLOBAL_SCOPE, journal_path=j,
                    resolution="ajouter un test de solvabilité (un bot gagne)")
    pm = sl.premortem("nimporte_quel_projet", journal_path=j)
    line = next(x for x in pm if "oracle vert" in x)
    assert line.startswith("⚑ ")
    assert "✅ RÉPARÉ: ajouter un test de solvabilité" in line
