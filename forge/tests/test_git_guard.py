"""Tests du garde MÉCANIQUE anti-git-destructif (mission P2, contrat
forge/contracts/p2-garde-git-mecanique.yaml).

Patron repris de forge/tests/test_hook_guard.py : on teste la LOGIQUE
PURE (forge.git_guard), pas le fichier hook mince
(.claude/hooks/pretool_git_guard.py) qui ne fait que du wiring stdin/JSON/exit-code
-- exactement comme .claude/hooks/pretool_forge_guard.py n'est pas testé
directement, seul forge.hook_guard l'est. Même justification : le hook mince n'a
aucune branche logique propre à couvrir, toute sa logique vit dans le module.

Les 3 premiers tests reprennent les FORMES EXACTES des 3 incidents réels
(EVIDENCE/runs/RUN_INDEX.md) :
  V4    -> revert de hunks driver.py (checkout du fichier concerné)
  N1-1  -> `git stash push` / `git stash pop` sur run_real.py
  N1-3  -> `git checkout -- knowledge_base/learning_curve.jsonl`
"""
from __future__ import annotations

import time
from pathlib import Path

from forge.git_guard import evaluate_command, find_blocked_invocations


# --- les 3 incidents réels : DOIVENT être bloqués -----------------------------

def test_incident_v4_checkout_driver_bloque():
    blocked, reason = evaluate_command("git checkout -- forge/driver.py")
    assert blocked is True
    assert "checkout" in reason


def test_incident_n1_1_stash_push_bloque():
    blocked, _ = evaluate_command("git stash push -- forge/run_real.py")
    assert blocked is True


def test_incident_n1_1_stash_pop_bloque():
    blocked, _ = evaluate_command("git stash pop")
    assert blocked is True


def test_incident_n1_3_checkout_learning_curve_bloque():
    blocked, reason = evaluate_command(
        "git checkout -- knowledge_base/learning_curve.jsonl")
    assert blocked is True
    assert "learning_curve.jsonl" in reason


# --- lecture : ne DOIVENT jamais être bloquées (liste blanche explicite) ------

def test_git_status_passe():
    blocked, _ = evaluate_command("git status")
    assert blocked is False


def test_git_status_porcelain_passe():
    blocked, _ = evaluate_command("git status --porcelain")
    assert blocked is False


def test_git_diff_passe():
    blocked, _ = evaluate_command("git diff -- .claude/settings.json")
    assert blocked is False


def test_git_log_passe():
    blocked, _ = evaluate_command("git log --oneline -5")
    assert blocked is False


def test_git_show_passe():
    blocked, _ = evaluate_command("git show HEAD:forge/driver.py")
    assert blocked is False


def test_commande_non_git_passe_sans_analyse():
    blocked, reason = evaluate_command("npm test")
    assert blocked is False
    assert "aucune invocation git" in reason


# --- variantes exigées par le garde-fou 3 -------------------------------------

def test_variante_dash_c_repertoire_puis_checkout_bloque():
    blocked, _ = evaluate_command("git -C EVIDENCE/runs/pong checkout -- state.json")
    assert blocked is True


def test_variante_restore_simple_bloque():
    blocked, _ = evaluate_command("git restore knowledge_base/learning_curve.jsonl")
    assert blocked is True


def test_variante_restore_staged_bloque():
    blocked, _ = evaluate_command("git restore --staged forge/driver.py")
    assert blocked is True


def test_variante_stash_list_bloque_aussi():
    """`stash` est bloqué quelle que soit la sous-sous-commande -- y compris
    `list`/`show`, qui semblent inoffensives mais restent la même famille de
    commande que push/pop/apply/drop/clear (le contrat dit "stash (toutes
    sous-commandes)")."""
    blocked, _ = evaluate_command("git stash list")
    assert blocked is True


def test_variante_stash_sans_argument_bloque():
    blocked, _ = evaluate_command("git stash")
    assert blocked is True


def test_variante_options_avant_sous_commande_bloquee():
    blocked, _ = evaluate_command("git --no-pager checkout -- foo.txt")
    assert blocked is True


def test_variante_commande_chainee_git_diff_puis_checkout_bloque():
    """Une commande composée (&&) doit être analysée segment par segment :
    le premier segment lisible ne doit pas masquer un second segment destructeur."""
    blocked, reason = evaluate_command(
        "git diff -- foo.txt && git checkout -- foo.txt")
    assert blocked is True
    assert "checkout" in reason


def test_variante_commande_chainee_point_virgule_bloque():
    blocked, _ = evaluate_command("git status; git restore foo.txt")
    assert blocked is True


# --- override humain : présence + fraîcheur, jamais silencieux ----------------

def test_override_absent_ne_change_rien(tmp_path):
    sentinel = tmp_path / "override.json"  # n'existe pas
    blocked, reason = evaluate_command(
        "git checkout -- foo.txt", sentinel_path=sentinel)
    assert blocked is True
    assert "sentinelle absent" in reason.lower()


def test_override_frais_et_valide_laisse_passer(tmp_path):
    sentinel = tmp_path / "override.json"
    now = time.time()
    sentinel.write_text(
        '{"timestamp_epoch": %f, "reason": "Pierre: recuperation manuelle assumee"}'
        % now, encoding="utf-8")
    blocked, reason = evaluate_command(
        "git checkout -- foo.txt", sentinel_path=sentinel, now=now + 5)
    assert blocked is False
    assert "override" in reason.lower()


def test_override_expire_ne_debloque_pas(tmp_path):
    sentinel = tmp_path / "override.json"
    old_ts = time.time() - 999999
    sentinel.write_text(
        '{"timestamp_epoch": %f, "reason": "trop vieux"}' % old_ts,
        encoding="utf-8")
    blocked, reason = evaluate_command(
        "git checkout -- foo.txt", sentinel_path=sentinel)
    assert blocked is True


def test_override_mal_forme_refuse_fail_closed(tmp_path):
    sentinel = tmp_path / "override.json"
    sentinel.write_text("{ceci n'est pas du json", encoding="utf-8")
    blocked, reason = evaluate_command(
        "git checkout -- foo.txt", sentinel_path=sentinel)
    assert blocked is True


def test_override_sans_reason_refuse(tmp_path):
    sentinel = tmp_path / "override.json"
    sentinel.write_text(
        '{"timestamp_epoch": %f}' % time.time(), encoding="utf-8")
    blocked, _ = evaluate_command("git checkout -- foo.txt", sentinel_path=sentinel)
    assert blocked is True


def test_override_ne_debloque_pas_une_commande_de_lecture_car_rien_a_debloquer(tmp_path):
    """L'override ne doit jamais avoir d'effet observable sur une commande qui
    n'était de toute façon pas bloquée -- il ne fait que lever un blocage réel."""
    sentinel = tmp_path / "override.json"
    now = time.time()
    sentinel.write_text(
        '{"timestamp_epoch": %f, "reason": "test"}' % now, encoding="utf-8")
    blocked, reason = evaluate_command("git status", sentinel_path=sentinel, now=now)
    assert blocked is False
    assert "override" not in reason.lower()


# --- fail-closed sur analyse cassée (garde-fou 2) -----------------------------

def test_analyse_cassee_sur_commande_git_bloque(monkeypatch):
    import forge.git_guard as gg

    def boom(_command):
        raise RuntimeError("parseur cassé")

    monkeypatch.setattr(gg, "find_blocked_invocations", boom)
    blocked, reason = evaluate_command("git checkout -- foo.txt")
    assert blocked is True
    assert "fail-closed" in reason.lower() or "refus" in reason.lower()


# --- find_blocked_invocations : détail des segments détectés ------------------

def test_find_blocked_invocations_retourne_le_segment_et_la_sous_commande():
    hits = find_blocked_invocations("git checkout -- foo.txt")
    assert len(hits) == 1
    seg, sub = hits[0]
    assert sub == "checkout"
    assert "foo.txt" in seg


def test_find_blocked_invocations_vide_si_rien_a_bloquer():
    assert find_blocked_invocations("git status && git log") == []


# --- limite documentée : ce que ce garde NE couvre PAS ------------------------

def test_limite_documentee_alias_git_non_couvert():
    """Documente honnêtement une limite (garde-fou 3) : un alias utilisateur
    (`git co` configuré comme alias de `checkout`) n'est PAS reconnu comme
    sous-commande bloquée par ce garde textuel -- seule la forme canonique
    `checkout`/`restore`/`stash` est détectée. Ce test n'est pas un bug à
    corriger, il PROUVE et fige la limite annoncée dans la proposition."""
    blocked, _ = evaluate_command("git co -- foo.txt")
    assert blocked is False  # limite assumée, pas une régression
