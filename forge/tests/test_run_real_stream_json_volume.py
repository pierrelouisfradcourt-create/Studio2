"""Mission d'outillage ciblée (2026-07-30, AUCUN appel réel, budget 0,00 $) —
ferme le trou de preuve laissé par `test_run_real_stream_json_capture.py` : la
neutralité du basculement `--output-format stream-json --verbose`
(`forge.run_real._claude_call_raw`, cf. son docstring) n'a été établie QUE sur
une enveloppe étroite (4 appels réels triviaux, la plus grosse capture
existante = 54 Ko / 59 lignes — `fixtures/reasoning_observability/
call3_effort_max_stream.jsonl`). Une étape de build réelle (contrat
`s9-build*`) consomme couramment de l'ordre de 190 000 tokens (input+output) —
un ordre de grandeur AU-DESSUS de tout ce qui a été mesuré. Ce fichier ne
prouve rien de neuf sur `extract_final_result` elle-même (déjà couverte par
`tests/test_tool_observability_capture.py`) : il prouve que le pipeline
COMPLET (`_claude_call_raw` : subprocess -> extraction -> construction du dict
{ok, output, tokens, cost_usd}) se comporte IDENTIQUEMENT sur un flux de
volume réaliste et sur ses cas dégradés — jamais une exception, jamais un
succès silencieux sur un flux tronqué.

Zéro nouvelle capture réelle, zéro fixture lourde committée : chaque flux
synthétique est un ASSEMBLAGE des lignes RÉELLES déjà capturées le 2026-07-30
et présentes dans le dépôt (`fixtures/tool_observability/`,
`fixtures/reasoning_observability/`) — dupliquées/réagencées à l'exécution du
test (jamais un nouveau fichier sur disque), jamais une forme de ligne
inventée. Seule la ligne finale `type: result` est CONSTRUITE par
`_result_line_from` : elle part de la vraie ligne finale de
`call3_effort_max_stream.jsonl` (le plus gros appel réel capturé) et
n'override QUE les champs sur lesquels chaque test fait une assertion —
même jeu de clés que la production, jamais un schéma deviné.

Justification du volume ciblé (test 1) : les 101 lignes de « bruit » réelles
disponibles (bash_echo + no_tools + call3, ligne `result` finale exclue)
pèsent ~94 Ko, soit ~936 octets/ligne en moyenne. 190 000 tokens à ~4
octets/token (ratio conservateur observé sur ce type de contenu — texte +
JSON de code) ≈ 760 Ko. Répéter le pool 10x donne ~944 Ko / ~1010 lignes :
même ordre de grandeur, marge incluse. Ceci SURESTIME probablement le volume
réel de la portion "streamée" (les tokens d'input mis en cache ne sont pas
ré-échoués ligne par ligne) — voir SKIPPED_VALIDATION du rapport de mission :
aucune capture réelle d'une étape de build à 190k tokens n'existe dans ce
dépôt pour calibrer plus finement, et ce chantier n'a pas le droit d'en
produire une (budget 0,00 $).

NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import json
import math
import time
from pathlib import Path

import pytest

import forge.run_real as run_real
from forge import tool_observability as obs

FIXTURES_TOOL = Path(__file__).resolve().parent / "fixtures" / "tool_observability"
FIXTURES_REASONING = Path(__file__).resolve().parent / "fixtures" / "reasoning_observability"

BASH_ECHO = (FIXTURES_TOOL / "probe_bash_echo_real_capture.jsonl").read_text(encoding="utf-8")
NO_TOOLS = (FIXTURES_TOOL / "probe_no_tools_real_capture.jsonl").read_text(encoding="utf-8")
CALL3_MAX = (FIXTURES_REASONING / "call3_effort_max_stream.jsonl").read_text(encoding="utf-8")


# --- seam : même patron que test_run_real_stream_json_capture.py ---------------
# (copie locale volontaire, pas un import croisé entre fichiers de test — chaque
# fichier de test reste lisible seul, patron déjà établi dans ce dossier.)

def _fake_run_with_stdout(monkeypatch, stdout_text: str):
    class FakeCompleted:
        returncode = 0
        stdout = stdout_text
        stderr = ""

    monkeypatch.setattr(run_real.subprocess, "run", lambda cmd, **kw: FakeCompleted())


# --- construction de flux synthétiques, à partir des lignes RÉELLES capturées ---

def _real_noise_lines(text: str) -> "list[str]":
    """Toutes les lignes non-vides d'une capture RÉELLE, SAUF la ligne finale
    `type: result` (retirée : chaque test construit la sienne, contrôlée).
    Une ligne illisible est conservée telle quelle (rejouer le bruit RÉEL, pas
    le filtrer) — seul le type 'result' est identifié et exclu."""
    out = []
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except ValueError:
            out.append(line)
            continue
        if isinstance(rec, dict) and rec.get("type") == "result":
            continue
        out.append(line)
    return out


# Pool RÉEL (3 captures existantes, 2026-07-30, ligne finale exclue de chacune) —
# 101 lignes mesurées, ~94 Ko : cf. justification du docstring de module.
_NOISE_POOL = _real_noise_lines(BASH_ECHO) + _real_noise_lines(NO_TOOLS) + _real_noise_lines(CALL3_MAX)
assert len(_NOISE_POOL) >= 90, "sanity: le pool de bruit réel a rétréci de façon inattendue"

_CALL3_RESULT_LINE = json.loads(CALL3_MAX.splitlines()[-1])
assert _CALL3_RESULT_LINE.get("type") == "result"


def _result_line_from_real(**overrides) -> str:
    """Ligne `type: result` avec EXACTEMENT le jeu de clés de la vraie ligne
    finale de call3 (l'appel réel le plus riche capturé), overrides appliqués
    par-dessus — jamais un schéma deviné."""
    rec = dict(_CALL3_RESULT_LINE)
    rec.update(overrides)
    return json.dumps(rec, ensure_ascii=False)


def _repeat_pool_to_bytes(target_bytes: int) -> "tuple[list[str], int]":
    """Répète `_NOISE_POOL` (lignes RÉELLES) jusqu'à atteindre `target_bytes`
    (encodage utf-8). Retourne (lignes, octets_reels)."""
    pool_bytes = sum(len(l.encode("utf-8")) + 1 for l in _NOISE_POOL)  # +1 = '\n'
    reps = max(1, math.ceil(target_bytes / pool_bytes))
    lines = _NOISE_POOL * reps
    total = sum(len(l.encode("utf-8")) + 1 for l in lines)
    return lines, total


# =================================================================================
# Cas 1 — volume réaliste : nombre de lignes ET taille du result comparables à
# une étape de build réelle (~190 000 tokens).
# =================================================================================

def test_cas1_volume_realiste_flux_de_build_extrait_correctement(tmp_path, monkeypatch):
    noise, noise_bytes = _repeat_pool_to_bytes(760_000)  # ~190k tokens * 4o/token
    # Résumé final réaliste (pas un one-liner de fixture trivial) : un paragraphe
    # de state final répété jusqu'à une taille non triviale (8 Ko).
    final_text = ("Build terminé : 14 fichiers créés sous GAMES/exemple/, 3 tests "
                  "node --test verts, oracle wiremap OK, aucune régression détectée. ")
    final_text = (final_text * (8_000 // len(final_text) + 1))[:8_000]
    result_line = _result_line_from_real(
        is_error=False, result=final_text,
        usage={"input_tokens": 176_000, "output_tokens": 14_000},
        total_cost_usd=1.874321,
    )
    stream = "\n".join(noise + [result_line]) + "\n"
    total_lines = len(noise) + 1
    total_bytes = len(stream.encode("utf-8"))

    # Preuve chiffrée exigée par la mission (cf. rapport) — bornes larges, pas
    # une valeur pile poil fragile : l'ordre de grandeur est ce qui compte.
    assert total_lines >= 900
    assert total_bytes >= 700_000
    assert len(final_text) == 8_000

    _fake_run_with_stdout(monkeypatch, stream)
    res = run_real._claude_call_raw("p", "haiku", add_dir=tmp_path, tools=())

    assert res["ok"] is True
    assert res["output"] == final_text  # égalité EXACTE, pas juste la longueur
    assert res["tokens"] == 176_000 + 14_000
    assert res["cost_usd"] == pytest.approx(1.874321)


# =================================================================================
# Cas 2 — ligne unique très longue : le `result` final tient sur UNE seule ligne
# de plusieurs Mo (cas qui casse un lecteur à buffer fixe).
# =================================================================================

def test_cas2_ligne_finale_unique_tres_longue_extraite_intacte(tmp_path, monkeypatch):
    # Marqueurs distincts en tête/milieu/queue : une troncature à N'IMPORTE QUEL
    # offset serait détectée par l'égalité stricte ci-dessous, pas seulement par
    # une comparaison de longueur.
    head = "BEGIN_MARKER_" + ("A" * 500_000)
    mid = "_MID_MARKER_" + ("B" * 3_000_000)
    tail = "_END_MARKER_TAIL"
    huge_text = head + mid + tail
    assert len(huge_text) > 3_500_000

    result_line = _result_line_from_real(
        is_error=False, result=huge_text,
        usage={"input_tokens": 5, "output_tokens": 900_000},
        total_cost_usd=9.99,
    )
    # Quelques lignes de bruit RÉEL avant, comme un vrai flux (jamais SEULEMENT
    # la ligne géante) — la ligne géante reste la ligne finale, une seule ligne.
    stream = "\n".join(_NOISE_POOL[:10] + [result_line]) + "\n"
    assert result_line.count("\n") == 0  # bien UNE seule ligne physique

    _fake_run_with_stdout(monkeypatch, stream)
    res = run_real._claude_call_raw("p", "haiku", add_dir=tmp_path, tools=())

    assert res["ok"] is True
    assert len(res["output"]) == len(huge_text)
    assert res["output"] == huge_text  # reconstruction bit-à-bit, pas tronquée
    assert res["output"].startswith("BEGIN_MARKER_")
    assert res["output"].endswith("_END_MARKER_TAIL")


# =================================================================================
# Cas 3 — bruit avant la ligne utile : beaucoup de lignes d'événements
# intermédiaires (accent sur le NOMBRE de lignes, pas leur poids individuel).
# =================================================================================

def test_cas3_grand_nombre_de_lignes_de_bruit_avant_la_ligne_utile(tmp_path, monkeypatch):
    # Ligne réelle légère (delta thinking_tokens, ~150-250 o) répétée en masse :
    # stresse le NOMBRE de lignes indépendamment du volume en octets (cas 1
    # stressait déjà le volume combiné).
    light_noise = [l for l in _NOISE_POOL if '"thinking_tokens"' in l] or _NOISE_POOL[:1]
    many_noise = (light_noise * (15_000 // len(light_noise) + 1))[:15_000]
    assert len(many_noise) == 15_000

    result_line = _result_line_from_real(
        is_error=False, result="RESULTAT_APRES_BEAUCOUP_DE_BRUIT",
        usage={"input_tokens": 100, "output_tokens": 50}, total_cost_usd=0.001,
    )
    stream = "\n".join(many_noise + [result_line]) + "\n"

    _fake_run_with_stdout(monkeypatch, stream)
    started = time.time()
    res = run_real._claude_call_raw("p", "haiku", add_dir=tmp_path, tools=())
    elapsed = time.time() - started

    assert res["ok"] is True
    assert res["output"] == "RESULTAT_APRES_BEAUCOUP_DE_BRUIT"
    # Pas d'exigence de perf dure (hors périmètre de cette mission) — seule
    # garantie voulue : pas de blocage/hang visible sur 15 000 lignes.
    assert elapsed < 10.0


# =================================================================================
# Cas 4 — ligne finale ABSENTE en fin d'un flux volumineux : échec honnête,
# jamais une exception, jamais un succès silencieux.
# =================================================================================

def test_cas4_ligne_result_absente_en_fin_de_flux_volumineux_echec_honnete(tmp_path, monkeypatch):
    noise, noise_bytes = _repeat_pool_to_bytes(760_000)
    # AUCUNE ligne `type: result` ajoutée — simule un flux tronqué (crash avant
    # la fin) sur un volume comparable au cas 1.
    stream = "\n".join(noise) + "\n"
    assert noise_bytes >= 700_000
    assert '"type":"result"' not in stream and '"type": "result"' not in stream

    _fake_run_with_stdout(monkeypatch, stream)
    # Ne doit JAMAIS lever, quel que soit le volume.
    res = run_real._claude_call_raw("p", "haiku", add_dir=tmp_path, tools=())

    assert res["ok"] is False
    assert "result" in res["reason"]


# =================================================================================
# Cas 5 — ligne tronquée / JSON invalide AU MILIEU d'un flux volumineux : ne
# doit ni faire perdre la ligne finale valide, ni lever.
# =================================================================================

def test_cas5_ligne_corrompue_au_milieu_dun_flux_volumineux_nempeche_pas_lextraction(tmp_path, monkeypatch):
    noise, _ = _repeat_pool_to_bytes(760_000)
    midpoint = len(noise) // 2
    # Ligne délibérément tronquée en plein milieu d'une chaîne JSON (coupure
    # brute, pas un JSON simplement malformé mais reconnaissable) — le cas
    # réel visé : un flux coupé net par une écriture partielle sur disque.
    corrupted = ('{"type":"assistant","message":{"content":[{"type":"tool_use",'
                 '"name":"Write","input":{"file_path":"GAMES/exemple/x.gd","content":'
                 '"extends Node2D\\nfunc _ready():\\n    pass  # coupe ici sans fermeture')
    result_line = _result_line_from_real(
        is_error=False, result="RESULTAT_MALGRE_CORRUPTION_AU_MILIEU",
        usage={"input_tokens": 42, "output_tokens": 7}, total_cost_usd=0.002,
    )
    lines = noise[:midpoint] + [corrupted] + noise[midpoint:] + [result_line]
    stream = "\n".join(lines) + "\n"
    assert len(lines) > 900

    _fake_run_with_stdout(monkeypatch, stream)
    res = run_real._claude_call_raw("p", "haiku", add_dir=tmp_path, tools=())

    assert res["ok"] is True
    assert res["output"] == "RESULTAT_MALGRE_CORRUPTION_AU_MILIEU"

    # Contrôle croisé maillon 4 (forge.tool_observability, fonction PURE déjà
    # prouvée sur capture réelle — jamais réimplémentée ici) : le même flux
    # corrompu ne fait perdre ni la ligne finale ni les tool_use RÉELS déjà
    # présents dans le pool de bruit (ceux de BASH_ECHO), preuve que la
    # corruption au milieu n'aveugle pas la lecture de part et d'autre.
    assert obs.extract_final_result(stream) is not None
    assert obs.extract_final_result(stream)["result"] == "RESULTAT_MALGRE_CORRUPTION_AU_MILIEU"
    assert "Bash" in obs.tool_names_used(stream)
