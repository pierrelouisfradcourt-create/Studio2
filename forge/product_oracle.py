"""Oracle PRODUIT (n3-oracle-produit-minimal) — trois volets déterministes non-LLM
qui couvrent ce que le gate mutation ne peut structurellement pas juger : les
fichiers `system.adapter` (présentation/runtime, 06_RUNTIME/adapters/) sortis du
périmètre mutation par la décision U-2 (voir `forge.mutation_proof`,
`MOTIF_EXCLUSION_PRESENTATION_RUNTIME`) — « à couvrir par l'oracle produit ; le
juge change, la couche n'est pas abandonnée ».

Contexte mesuré qui motive ce module (re-vérifié, pas cru) : Pong n'avait JAMAIS
booté dans un vrai navigateur (deux modules importés par `browser/main.mjs`
levaient à l'évaluation : `audio.mjs` important `node:fs`/`node:path`/`node:url`
en statique, `exit.mjs` référençant `process` sans garde) — aucun des 50 tests
existants ne pouvait le voir, et `capture_browser.mjs` ne charge JAMAIS
`browser/main.mjs` (il rastérise en Node via `loop`/`draw`/`raster` directement).

Trois volets, chacun HONNÊTE sur ce qu'il ne prouve pas :

- ``check_browser_import_safety`` (3a) — STATIQUE : parcourt le graphe d'imports
  ES depuis l'entrée navigateur et refuse tout specifier ``node:*`` atteignable
  ou toute référence ``process`` non gardée. Ne lance AUCUN navigateur : ça ne
  prouve pas que le jeu s'affiche, seulement que son graphe de modules ne
  contient plus la classe de défaut qui l'empêchait de charger.
- ``check_auto_session`` (3b) — joue une partie automatique complète sur la
  LOGIQUE PURE (boot/step, comme `solvability.mjs`) et asserte score-évolue +
  partie-finit + zéro-exception + durée bornée. Le bot a une latence de
  réaction NULLE : borne supérieure de performance, jamais une preuve de
  jouabilité humaine.
- ``check_visual_capture`` (3c) — APPELLE les captures existantes
  (`capture_browser.mjs`, `capture_godot.mjs`, jamais réimplémentées) et
  asserte deux images différentes et non monochromes. Runtime absent (binaire
  Godot, fenêtre GPU) => NOT_MEASURED motivé, JAMAIS un vert.

Advisory (n3-oracle-produit-minimal, garde-fou explicite) : ces trois volets ne
gate JAMAIS `oracle_ok` dans cette mission — ils voyagent dans le reçu signé de
s10a (comme reuse_ratio_wired/search_consulted), pour une décision de passage en
gate dur PLUS TARD, par Pierre, au vu des chiffres. Déterministe, non-LLM,
encoding utf-8. claim_verdict: NO_CLAIM_ALLOWED.

ADDENDUM (contrat `s1-brancher-le-lecteur.yaml`, 2026-07-27) : quatre volets
supplémentaires — ``check_restart_offer_wiring``, ``check_exit_stop_wiring``,
``check_playable_speed_band``, ``check_solo_ai_session`` — EXÉCUTENT (jamais ne
réimplémentent) les 7 fichiers de preuve neufs du run pong_r3 (`ai.test.mjs`,
`end_screen.test.mjs`, `exit_stop.test.mjs`, `playable_speed.test.mjs`,
`restart_offer.test.mjs`, `score_readout.test.mjs`, `solo_session.mjs`), pour
fermer le trou de lecteur mesuré par `check_observable_coverage`
(`standard_oracles.py`) : ces fichiers passaient, mais aucun oracle ne les
appelait. Même discipline ADVISORY, même honnêteté sur ce qui n'est PAS prouvé
(voir la clé `limites` de chaque volet).
"""
from __future__ import annotations

import json
import logging
import re
import subprocess
from pathlib import Path

logger = logging.getLogger(__name__)

# --- helpers partagés (comment-stripping JS minimal — mêmes deux regex que
# forge.static_oracles._strip_js_comments, dupliquées ici volontairement pour ne
# pas coupler ce module à un symbole privé d'un autre module) -------------------
_JS_BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.S)
_JS_LINE_COMMENT = re.compile(r"(?<!:)//[^\n]*")


def _strip_js_comments(text: str) -> str:
    return _JS_LINE_COMMENT.sub(" ", _JS_BLOCK_COMMENT.sub(" ", text))


def _read_text(path: Path) -> str | None:
    """Lit un fichier texte. None (PAS "") sur échec : un texte vide serait
    indiscernable d'un fichier réellement vide et n'a « aucun défaut » que par
    construction — None force l'appelant à traiter l'absence de mesure comme
    telle (contre-vérification P7, 2026-07-27 : un dossier/fichier illisible
    convertissait silencieusement une absence de lecture en `""`, donc en
    « zéro import node:/process trouvé », donc en `passed: true` — exactement
    ce que le garde-fou 2 interdit)."""
    try:
        if not path.is_file():
            return None
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        logger.warning("product_oracle: lecture échouée sur %s (%s)", path, exc)
        return None


# ============================================================================
# 3a — browser_import_safety (STATIQUE)
# ============================================================================

# Statement d'import ES STATIQUE complet, borné au `;` de fin de statement (le
# `[^;]` couvre les imports multi-lignes sans jamais déborder sur le statement
# suivant). `(?!\.)` exclut `import.meta.url` ; `(?!\()` exclut l'import
# DYNAMIQUE `import(...)` — celui-ci est ÉVALUÉ SEULEMENT à l'appel (guardable
# par un `if`, cf. audio.mjs `if (!IS_BROWSER) { ... await import('node:fs') }`),
# alors qu'un import statique est évalué IMMÉDIATEMENT au chargement du module
# (c'est exactement le défaut réel corrigé le 2026-07-26 : un import statique de
# `node:fs` fait échouer TOUT le graphe de modules dans un navigateur, avant même
# que la moindre garde runtime ne puisse s'exécuter).
_STATIC_IMPORT = re.compile(
    r"^[ \t]*import(?!\.)(?!\()\b[^;]*?['\"]([^'\"]+)['\"][^;]*;", re.M)

_PROCESS_TOKEN = re.compile(r"\bprocess\b")
_PROCESS_GUARD_PHRASE = re.compile(r"typeof\s+process\s*!==?\s*['\"]undefined['\"]")

_JS_RESOLVE_EXTS = (".mjs", ".js", ".cjs")


def _resolve_relative_import(spec: str, from_file: Path) -> Path | None:
    """Résout un specifier RELATIF (`./x`, `../y/z`) en chemin de fichier réel.
    None pour un specifier non relatif (package/bare — `node:fs`, `node:path`...
    ce sont justement CEUX-LÀ qu'on veut détecter, pas suivre) ou introuvable."""
    if not spec.startswith("."):
        return None
    target = from_file.parent / spec
    candidates: list[Path] = []
    if target.suffix:
        candidates.append(target)
    else:
        candidates.extend(target.with_suffix(ext) for ext in _JS_RESOLVE_EXTS)
        candidates.append(target / "index.mjs")
    for cand in candidates:
        try:
            resolved = cand.resolve()
        except OSError:
            continue
        if resolved.exists() and resolved.is_file():
            return resolved
    return None


def _guarded_process_regions(text: str) -> list[tuple[int, int]]:
    """Portées `{...}` (ou fin de statement pour un garde sans bloc) ouvertes par
    un garde `typeof process !== 'undefined'` détecté dans le texte. Heuristique de
    profondeur d'accolades (pas un vrai parseur JS) : suffisant pour un code non
    adversarial, documenté comme limite (cf. `limites` du reçu)."""
    regions: list[tuple[int, int]] = []
    for m in _PROCESS_GUARD_PHRASE.finditer(text):
        brace_pos = text.find("{", m.end())
        semi_pos = text.find(";", m.end())
        if brace_pos != -1 and (semi_pos == -1 or brace_pos < semi_pos):
            depth = 0
            i = brace_pos
            end = len(text)
            while i < len(text):
                if text[i] == "{":
                    depth += 1
                elif text[i] == "}":
                    depth -= 1
                    if depth == 0:
                        end = i
                        break
                i += 1
            regions.append((m.start(), end))
        else:
            regions.append((m.start(), semi_pos if semi_pos != -1 else len(text)))
    return regions


def _process_non_gardes(text: str, label: str) -> list[dict]:
    regions = _guarded_process_regions(text)
    lines = text.splitlines()
    hits: list[dict] = []
    for m in _PROCESS_TOKEN.finditer(text):
        pos = m.start()
        if any(s <= pos <= e for s, e in regions):
            continue
        line_no = text.count("\n", 0, pos) + 1
        extrait = lines[line_no - 1].strip() if 0 <= line_no - 1 < len(lines) else ""
        hits.append({"fichier": label, "ligne": line_no, "extrait": extrait[:160]})
    return hits


def check_browser_import_safety(entry_file: Path) -> dict:
    """3a. Depuis l'entrée navigateur, parcourt le graphe d'imports STATIQUES ES
    (relatifs, résolus récursivement) et refuse :
      - tout specifier ``node:*`` atteignable (import statique — évalué à l'
        évaluation du module, casse tout le graphe dans un navigateur) ;
      - toute référence ``process`` non gardée par ``typeof process !== 'undefined'``.

    Retourne {passed, checked, entry, fichiers_analyses[], node_imports_atteignables[],
    process_non_gardes[], limites[]}. PASS = aucun des deux défauts sur AUCUN
    fichier atteint depuis l'entrée.

    LIMITE ASSUMÉE (garde-fou 4 du contrat) : analyse STATIQUE par regex, jamais un
    vrai parseur JS et JAMAIS une exécution de navigateur — ça ne prouve PAS que le
    jeu s'affiche réellement (aucun Chrome/Playwright n'est lancé ici), seulement
    que son graphe de modules ne contient plus la classe de défaut qui l'empêchait
    de charger.
    """
    entry_file = Path(entry_file)
    if not entry_file.is_file():
        return {
            "passed": False, "checked": False,
            "reason": f"entrée navigateur absente, illisible ou pas un fichier: {entry_file}",
            "entry": str(entry_file), "fichiers_analyses": [],
            "node_imports_atteignables": [], "process_non_gardes": [],
        }

    seen: set[str] = set()
    analyzed: list[str] = []
    unreadable: list[str] = []
    queue: list[Path] = [entry_file.resolve()]
    node_hits: list[dict] = []
    process_hits: list[dict] = []

    while queue:
        current = queue.pop(0)
        key = str(current)
        if key in seen:
            continue
        seen.add(key)
        raw = _read_text(current)
        if raw is None:
            unreadable.append(key)
            continue
        analyzed.append(key)
        text = _strip_js_comments(raw)
        specs = _STATIC_IMPORT.findall(text)
        for spec in specs:
            if spec.startswith("node:"):
                node_hits.append({"fichier": key, "specifier": spec})
            target = _resolve_relative_import(spec, current)
            if target is not None and str(target) not in seen:
                queue.append(target)
        process_hits.extend(_process_non_gardes(text, key))

    if not analyzed:
        # Garde-fou 2 (contre-vérification P7) : ZÉRO fichier effectivement lu
        # ne peut jamais valoir « aucun défaut trouvé » — absence de mesure,
        # jamais un vert. Ne devrait plus être atteignable depuis la garde
        # `is_file()` ci-dessus pour l'entrée elle-même, mais reste la protection
        # de dernier recours si un fichier devient illisible EN COURS DE ROUTE
        # (permission changée, disque qui se dérobe, etc.).
        return {
            "passed": False, "checked": False,
            "reason": ("aucun fichier n'a pu être lu depuis l'entrée navigateur "
                       f"(illisible(s): {sorted(unreadable)}) — absence de mesure, "
                       "jamais un vert"),
            "entry": str(entry_file), "fichiers_analyses": [],
            "fichiers_illisibles": sorted(unreadable),
            "node_imports_atteignables": [], "process_non_gardes": [],
        }

    passed = not node_hits and not process_hits
    return {
        "passed": passed,
        "checked": True,
        "entry": str(entry_file),
        "fichiers_analyses": sorted(analyzed),
        "fichiers_illisibles": sorted(unreadable),
        "node_imports_atteignables": node_hits,
        "process_non_gardes": process_hits,
        "limites": [
            "analyse STATIQUE (regex) du graphe d'imports ES depuis l'entrée "
            "navigateur, pas un parseur JS complet ni une exécution réelle — "
            "ne prouve PAS que le jeu s'affiche dans un navigateur.",
        ],
    }


# ============================================================================
# 3b — auto_session (logique pure, boot/step)
# ============================================================================

# Script Node embarqué : dynamic-imports les 3 modules de logique pure par leur
# chemin ABSOLU (converti en file:// URL côté Python) — indépendant de l'endroit
# où ce script temporaire est écrit sur le disque, jamais besoin de le placer
# sous le dépôt. Bot "suiveur/fuyard" IDENTIQUE en esprit à
# `07_TESTS/oracle/solvability.mjs` (garantit la terminaison : le camp fuyard
# encaisse), mais réimplémenté ICI pour échantillonner le score À INTERVALLES
# (pas seulement au résultat final) — c'est ce qui distingue "le score évolue"
# de la simple tautologie "la partie finit => le score a bougé".
_AUTO_SESSION_DRIVER = r"""
import { pathToFileURL } from 'node:url';

const [, , loopPath, statePath, inputPath, maxTicksArg] = process.argv;
const maxTicks = parseInt(maxTicksArg, 10);

const result = { finished: false, ticks: 0, duration_ms: 0, error: null,
                  final_score: null, score_samples: [], status: null };
const t0 = Date.now();
try {
  const { boot, step } = await import(pathToFileURL(loopPath).href);
  const { isOver, PADDLE_H } = await import(pathToFileURL(statePath).href);
  const { translate } = await import(pathToFileURL(inputPath).href);

  const mid = PADDLE_H / 2;
  function trackerDir(paddleY, ballY) {
    const c = paddleY + mid;
    if (ballY < c - 0.5) return 'up';
    if (ballY > c + 0.5) return 'down';
    return null;
  }
  function fleeDir(paddleY, ballY) {
    const c = paddleY + mid;
    return ballY > c ? 'up' : 'down';
  }

  let s = boot(1);
  let ticks = 0;
  const distinct = new Set([0]);   // score total au premier instant (0+0)
  const preview = [0];
  while (!isOver(s) && ticks < maxTicks) {
    const raw = { p1: trackerDir(s.p1.y, s.ball.y), p2: fleeDir(s.p2.y, s.ball.y) };
    const { state: ns } = step(s, translate(raw));
    s = ns;
    ticks += 1;
    const total = s.score.p1 + s.score.p2;
    distinct.add(total);
    if (preview.length < 40) preview.push(total);
  }

  result.finished = isOver(s);
  result.ticks = ticks;
  result.final_score = s.score;
  result.score_samples = preview;          // aperçu borné, jamais tronqué en aval
  result.distinct_scores = [...distinct];  // TOUS les paliers de score REELLEMENT vus
  result.status = s.status;
} catch (e) {
  result.error = String((e && e.stack) || e);
}
result.duration_ms = Date.now() - t0;
process.stdout.write(JSON.stringify(result));
"""


def _write_temp_driver(tmp_dir: Path) -> Path:
    driver_path = tmp_dir / "_auto_session_driver.mjs"
    driver_path.write_text(_AUTO_SESSION_DRIVER, encoding="utf-8")
    return driver_path


def check_auto_session(
    loop_file: Path, state_file: Path, input_file: Path,
    *, max_ticks: int = 20000, timeout_s: int = 30, node_bin: str = "node",
    tmp_dir: Path | None = None,
) -> dict:
    """3b. Joue une partie automatique complète sur la logique pure et asserte :
    le score ÉVOLUE, la partie SE TERMINE, aucune exception, durée BORNÉE.

    Retourne {passed, checked, finished, score_evolves, no_exception, duration_bounded,
    ticks, duration_ms, final_score, error, limites[]}.

    LIMITE ASSUMÉE (garde-fou 5 du contrat) : le bot a une latence de réaction
    NULLE (aucune I/O, aucun temps réel) — c'est une borne SUPÉRIEURE de
    performance mécanique, jamais une preuve de jouabilité humaine.
    """
    import tempfile

    for f, label in ((loop_file, "loop"), (state_file, "state"), (input_file, "input")):
        # `.is_file()` (PAS `.exists()`, contre-vérification P7) : un DOSSIER
        # existe mais n'est pas un fichier logique lisible — sans ce garde
        # explicite, le rejet ne survenait qu'« accidentellement », via l'erreur
        # ESM que Node lève en aval (ERR_UNSUPPORTED_DIR_IMPORT) plutôt que par
        # une vérification déterministe assumée ici.
        if not Path(f).is_file():
            return {
                "passed": False, "checked": False,
                "reason": f"fichier logique {label} absent, illisible ou pas un fichier: {f}",
            }

    owns_tmp = tmp_dir is None
    tmp_ctx = tempfile.TemporaryDirectory(prefix="forge_auto_session_") if owns_tmp else None
    try:
        driver_dir = Path(tmp_ctx.name) if owns_tmp else Path(tmp_dir)
        driver_dir.mkdir(parents=True, exist_ok=True)
        driver_path = _write_temp_driver(driver_dir)
        argv = [node_bin, str(driver_path), str(Path(loop_file).resolve()),
                str(Path(state_file).resolve()), str(Path(input_file).resolve()),
                str(int(max_ticks))]
        try:
            proc = subprocess.run(argv, capture_output=True, text=True,
                                  timeout=timeout_s)
        except subprocess.TimeoutExpired:
            return {
                "passed": False, "checked": True,
                "reason": f"session auto-jouée non bornée (timeout {timeout_s}s dépassé)",
                "finished": False, "score_evolves": False, "no_exception": False,
                "duration_bounded": False,
            }
        except OSError as exc:
            return {
                "passed": False, "checked": False,
                "reason": f"exécuteur node introuvable/inexécutable: {exc}",
            }
        try:
            payload = json.loads(proc.stdout) if proc.stdout.strip() else None
        except ValueError:
            payload = None
        if not isinstance(payload, dict):
            return {
                "passed": False, "checked": True,
                "reason": "sortie JSON illisible depuis le driver auto_session",
                "returncode": proc.returncode,
                "stdout_tail": proc.stdout[-500:], "stderr_tail": proc.stderr[-500:],
                "finished": False, "score_evolves": False, "no_exception": False,
                "duration_bounded": False,
            }
    finally:
        if tmp_ctx is not None:
            tmp_ctx.cleanup()

    finished = bool(payload.get("finished"))
    no_exception = payload.get("error") is None
    samples = payload.get("score_samples") or []
    distinct_scores = payload.get("distinct_scores") or list(set(samples))
    score_evolves = len(set(distinct_scores)) > 1
    ticks = int(payload.get("ticks", 0))
    duration_bounded = ticks < int(max_ticks)  # cap interne JAMAIS atteint
    passed = finished and no_exception and score_evolves and duration_bounded

    return {
        "passed": passed,
        "checked": True,
        "finished": finished,
        "no_exception": no_exception,
        "score_evolves": score_evolves,
        "duration_bounded": duration_bounded,
        "ticks": ticks,
        "max_ticks": int(max_ticks),
        "duration_ms": payload.get("duration_ms"),
        "final_score": payload.get("final_score"),
        "score_samples": samples,
        "distinct_scores": sorted(set(distinct_scores)),
        "error": payload.get("error"),
        "limites": [
            "bot à latence de réaction NULLE (logique pure, aucune I/O, aucun temps "
            "réel) — borne SUPÉRIEURE de performance mécanique, jamais une preuve "
            "de jouabilité humaine.",
        ],
    }


# ============================================================================
# 3c — visual_capture (appelle les captures EXISTANTES, jamais réimplémentées)
# ============================================================================

def _run_capture_script(script: Path, node_bin: str, timeout_s: int) -> dict:
    if not script.exists():
        return {"ran": False, "error": f"{script} absent", "json": None}
    try:
        proc = subprocess.run(
            [node_bin, script.name], cwd=str(script.parent),
            capture_output=True, text=True, timeout=timeout_s,
        )
    except subprocess.TimeoutExpired:
        return {"ran": False, "error": f"timeout ({timeout_s}s)", "json": None}
    except OSError as exc:
        return {"ran": False, "error": str(exc), "json": None}
    payload = None
    if proc.stdout.strip():
        try:
            payload = json.loads(proc.stdout)
        except ValueError:
            payload = None
    return {
        "ran": True, "returncode": proc.returncode, "json": payload,
        "stdout_tail": proc.stdout[-800:], "stderr_tail": proc.stderr[-800:],
    }


def check_visual_capture(
    presentation_dir: Path, *, node_bin: str = "node", timeout_s: int = 150,
) -> dict:
    """3c. APPELLE `capture_browser.mjs` et `capture_godot.mjs` (existants,
    jamais réimplémentés) et asserte : deux captures différentes, aucune
    monochrome. Runtime absent (binaire Godot non configuré, fenêtre GPU
    indisponible) => NOT_MEASURED motivé pour le volet Godot, JAMAIS un vert
    fabriqué pour ce qui n'a pas été mesuré.

    Retourne {status, passed, not_measured, reason, volets{}, measured_volets[],
    not_measured_volets[], browser{}, godot{}, limites[]}.

    W-2 (GO Pierre 2026-09-02) — `passed` est True SSI status == "OK", et OK signifie
    « **tout volet APPLICABLE (script présent) ET MESURÉ est vert** », jamais « tout a
    été mesuré ». Un moteur dont le script de capture est ABSENT n'existe pas pour ce
    jeu et n'entre pas dans l'agrégat ; un script PRÉSENT mais non mesurable reste
    NOT_MEASURED, figure dans `not_measured_volets`, et n'emporte plus le statut.
    Aucun volet mesuré => NOT_MEASURED (un jeu sans capture ne gagne aucun vert).
    """
    presentation_dir = Path(presentation_dir)
    browser_script = presentation_dir / "capture_browser.mjs"
    godot_script = presentation_dir / "capture_godot.mjs"
    browser = _run_capture_script(browser_script, node_bin, timeout_s)
    godot = _run_capture_script(godot_script, node_bin, timeout_s)

    browser_json = browser.get("json") or {}
    browser_measured = bool(browser.get("ran")) and browser.get("json") is not None
    browser_ok = browser_measured and bool(browser_json.get("passed"))

    godot_json = godot.get("json") or {}
    godot_blocked = bool(godot_json.get("blocked"))
    godot_measured = bool(godot.get("ran")) and godot.get("json") is not None and not godot_blocked
    godot_ok = godot_measured and bool(godot_json.get("passed"))

    # W-2 (GO Pierre 2026-09-02) — DÉCOUPLAGE PAR MOTEUR.
    #
    # AVANT : `passed` exigeait que les DEUX volets soient mesurés ET verts. Conséquence
    # mesurée : un jeu PUREMENT WEB — donc 68 des 79 attentes `expected_proof.kind:
    # visual` du dépôt — ne pouvait JAMAIS atteindre OK, puisque le volet Godot n'y est
    # pas applicable. Une capture navigateur parfaitement verte retombait en
    # NOT_MEASURED. Ce n'était pas malhonnête (le statut le disait), mais cela rendait
    # le volet inutilisable comme source de preuve visuelle pour un jeu web.
    #
    # APRÈS : l'agrégat porte sur les volets APPLICABLES (script présent) ET MESURÉS.
    #   - script ABSENT      -> ce moteur n'existe pas pour ce jeu : n'entre pas dans l'agrégat
    #   - script PRÉSENT mais non mesurable (bloqué/timeout/JSON invalide) -> reste
    #     NOT_MEASURED, est LISTÉ dans `not_measured_volets`, et n'emporte pas le statut
    #   - aucun volet mesuré -> NOT_MEASURED (INCHANGÉ : un jeu sans aucune capture ne
    #     gagne aucun vert — W-2 ne fabrique pas de preuve là où il n'y a pas de producteur)
    #
    # Ce que `passed` signifie désormais, et il faut le lire ainsi : « tout volet
    # applicable ET mesuré est vert ». Jamais « tout a été mesuré ». C'est pourquoi
    # `not_measured_volets` est exposé : moins d'autorité conjonctive, même capacité de
    # détection, absence toujours visible.
    volets = {
        "browser": {"applicable": browser_script.exists(),
                    "measured": browser_measured, "ok": browser_ok},
        "godot": {"applicable": godot_script.exists(),
                  "measured": godot_measured, "ok": godot_ok},
    }
    mesures = [nom for nom, v in volets.items() if v["applicable"] and v["measured"]]
    rouges = [nom for nom in mesures if not volets[nom]["ok"]]
    non_mesures = [nom for nom, v in volets.items() if v["applicable"] and not v["measured"]]

    if rouges:
        status = "FAIL"
        detail_rouge = {
            "browser": "capture_browser.mjs mesuré, critère pixel (differ + non-monochrome) rouge",
            "godot": "capture_godot.mjs exécuté, critère pixel (differ + non-monochrome) rouge",
        }
        reason = " ; ".join(detail_rouge[nom] for nom in rouges)
    elif not mesures:
        # Contre-vérification P7, INCHANGÉE : aucune mesure n'a eu lieu, ce n'est PAS un
        # critère pixel rouge. FAIL affirmerait à tort qu'une exécution a eu lieu et a
        # échoué le critère ; NOT_MEASURED dit honnêtement qu'on ne sait rien ici.
        status = "NOT_MEASURED"
        reason = (browser.get("error") or godot_json.get("reason") or godot.get("error")
                  or "aucun volet de capture applicable et mesurable (scripts absents/"
                     "illisibles/timeout/JSON invalide) — absence de mesure, jamais un vert")
    else:
        status = "OK"
        reason = ""

    return {
        "status": status,
        "passed": status == "OK",
        "not_measured": status == "NOT_MEASURED",
        "reason": reason,
        "volets": volets,
        "measured_volets": mesures,
        "not_measured_volets": non_mesures,
        "browser": browser,
        "godot": godot,
        "limites": [
            "n'appelle QUE les captures existantes (capture_browser.mjs/"
            "capture_godot.mjs) — jamais réimplémentées ici.",
            "le volet Godot exige un binaire configuré ET une fenêtre GPU réelle "
            "(--rendering-driver vulkan) ; son absence rend le volet NOT_MEASURED, "
            "jamais un vert.",
            "W-2 : `passed` signifie « tout volet APPLICABLE ET MESURÉ est vert », "
            "jamais « tout a été mesuré » — lire `not_measured_volets` avant d'en "
            "conclure quoi que ce soit.",
            "le critère pixel détecte un rendu MORT ou FIGÉ (falsification V-2 : "
            "captures identiques et rendu monochrome sont détectés), PAS une "
            "dégradation visuelle (un rendu qui bouge d'un pixel passe).",
        ],
    }


# ============================================================================
# 3d — restart_offer_wiring / exit_stop_wiring / playable_speed_band /
#      solo_ai_session (contrat `s1-brancher-le-lecteur.yaml`, 2026-07-27) —
#      EXÉCUTEURS honnêtes des fichiers de preuve neufs produits par le run
#      pong_r3 (07_TESTS/unit/restart_offer.test.mjs, exit_stop.test.mjs,
#      playable_speed.test.mjs, ai.test.mjs + 07_TESTS/oracle/solo_session.mjs).
#
#      Aucun de ces volets n'invente une assertion : chacun lance le fichier de
#      preuve TEL QUEL (``node --test`` pour les ``*.test.mjs``, ``node`` nu pour
#      le harnais bot_action ``solo_session.mjs`` qui imprime un reçu JSON comme
#      ``solvability.mjs``) et relit son verdict. Ces fichiers ne sont jamais
#      modifiés ni réimplémentés ici (garde-fou 6 du contrat).
#
#      RENOMMAGE HONNÊTE (garde-fou 2 du contrat, exigence centrale) : les
#      wiremap `observable_proof` précédents `browser_restart_click` /
#      `browser_exit_click` promettaient un CLIC NAVIGATEUR RÉEL qui n'a jamais
#      lieu ici — aucun outil d'automatisation navigateur (Playwright/Puppeteer)
#      n'est disponible sur ce poste (confirmé absent, run pong_r3:2). Ces deux
#      volets prouvent le CÂBLAGE (la relance/la sortie fonctionnent au niveau
#      du contrôleur), jamais l'effet visuel d'un clic humain — d'où leur nouveau
#      nom `*_wiring`. `solo_ai_session`/`playable_speed_band_test` gardent leur
#      nom (déjà honnête : aucune promesse de clic) mais n'existaient pas
#      encore comme volets exécutables.
# ============================================================================

_NODE_TEST_SUMMARY = re.compile(r"^[#ℹ]\s+(pass|fail)\s+(\d+)", re.M)


def _run_node_test_file(test_file: Path, *, node_bin: str = "node", timeout_s: int = 60) -> dict:
    """Exécute UN fichier `node:test` existant via `node --test <file>` — jamais
    réimplémenté, jamais modifié. Relit le résumé TAP émis par le runner natif
    de Node (`# pass N` / `# fail N`, ou la variante `ℹ pass N` / `ℹ fail N` des
    versions récentes) pour décider `passed`.

    Retourne {passed, checked, returncode, tests_pass, tests_fail, stdout_tail,
    stderr_tail} ou, sur cas non mesurable (fichier absent, timeout, exécuteur
    introuvable), {passed: False, checked: False, reason}. Jamais d'exception."""
    test_file = Path(test_file)
    if not test_file.is_file():
        return {
            "passed": False, "checked": False,
            "reason": f"fichier de preuve absent, illisible ou pas un fichier: {test_file}",
        }
    try:
        proc = subprocess.run(
            [node_bin, "--test", str(test_file)],
            capture_output=True, text=True, timeout=timeout_s,
            encoding="utf-8", errors="replace",
        )
    except subprocess.TimeoutExpired:
        return {
            "passed": False, "checked": True,
            "reason": f"timeout ({timeout_s}s) sur {test_file}",
        }
    except OSError as exc:
        return {
            "passed": False, "checked": False,
            "reason": f"exécuteur node introuvable/inexécutable: {exc}",
        }
    out = proc.stdout
    n_pass = n_fail = None
    for m in _NODE_TEST_SUMMARY.finditer(out):
        kind, n = m.group(1), int(m.group(2))
        if kind == "pass":
            n_pass = n
        else:
            n_fail = n
    passed = proc.returncode == 0 and n_fail == 0 and (n_pass or 0) > 0
    return {
        "passed": passed,
        "checked": True,
        "returncode": proc.returncode,
        "tests_pass": n_pass,
        "tests_fail": n_fail,
        "stdout_tail": out[-800:],
        "stderr_tail": proc.stderr[-800:],
    }


def check_restart_offer_wiring(test_file: Path, *, node_bin: str = "node", timeout_s: int = 60) -> dict:
    """EXÉCUTE `07_TESTS/unit/restart_offer.test.mjs` (jamais réimplémenté) : le
    contrôleur navigateur (`createController`) ramène l'état à `boot(seed)`
    exactement après `replay()`, y compris après une sortie. Preuve du CÂBLAGE
    de la relance offerte au joueur (bouton "Rejouer" / touche R).

    NE PROUVE PAS : un clic réel sur le bouton "Rejouer" (aucun navigateur
    piloté, aucun Playwright/Puppeteer sur ce poste) ; aucun rendu observé du
    bouton lui-même — seule la fonction `replay()` du contrôleur est exercée."""
    result = _run_node_test_file(test_file, node_bin=node_bin, timeout_s=timeout_s)
    result["limites"] = [
        "exécute 07_TESTS/unit/restart_offer.test.mjs tel quel (node --test), "
        "jamais réimplémenté.",
        "NE PROUVE PAS un clic navigateur réel sur le bouton 'Rejouer' (aucune "
        "automatisation navigateur disponible sur ce poste).",
        "NE PROUVE PAS de rendu observé (aucune capture d'écran ici) — seul le "
        "câblage logique du contrôleur (createController().replay()) est exercé.",
    ]
    return result


def check_exit_stop_wiring(test_file: Path, *, node_bin: str = "node", timeout_s: int = 60) -> dict:
    """EXÉCUTE `07_TESTS/unit/exit_stop.test.mjs` (jamais réimplémenté) :
    `requestExit('browser')` retourne un signal `{stopped:true}` (ne se fie plus
    à `window.close()`, inerte) et `controller.stop()` arrête réellement la
    boucle (`tick()` devient un no-op, l'état se fige). Preuve du CÂBLAGE de la
    sortie observable.

    NE PROUVE PAS : un clic réel sur le bouton "Quitter" (aucun navigateur
    piloté sur ce poste) ; aucun rendu observé de l'état figé à l'écran — seule
    la mécanique du contrôleur est exercée."""
    result = _run_node_test_file(test_file, node_bin=node_bin, timeout_s=timeout_s)
    result["limites"] = [
        "exécute 07_TESTS/unit/exit_stop.test.mjs tel quel (node --test), jamais "
        "réimplémenté.",
        "NE PROUVE PAS un clic navigateur réel sur le bouton 'Quitter' (aucune "
        "automatisation navigateur disponible sur ce poste).",
        "NE PROUVE PAS de rendu observé de l'état figé — seul le câblage logique "
        "(requestExit/stop/tick no-op) est exercé.",
    ]
    return result


def check_playable_speed_band(test_file: Path, *, node_bin: str = "node", timeout_s: int = 60) -> dict:
    """EXÉCUTE `07_TESTS/unit/playable_speed.test.mjs` (jamais réimplémenté) : le
    temps de traversée de service dérivé des constantes (`ballCrossingTimeSeconds`)
    tombe dans la bande jouable déclarée par la Genre Bible Pong, ET l'ancienne
    vitesse (rejetée) reste HORS bande — non-tautologie vérifiée par le fichier
    de preuve lui-même.

    NE PROUVE PAS : une perception humaine de « jouable » (aucun playtest humain
    ici) ; aucun rendu observé — c'est une dérivation purement numérique des
    constantes du moteur."""
    result = _run_node_test_file(test_file, node_bin=node_bin, timeout_s=timeout_s)
    result["limites"] = [
        "exécute 07_TESTS/unit/playable_speed.test.mjs tel quel (node --test), "
        "jamais réimplémenté.",
        "NE PROUVE PAS une perception humaine de jouabilité (aucun playtest humain "
        "ici) — dérivation purement numérique des constantes.",
        "NE PROUVE PAS de rendu observé (aucun clic, aucune capture d'écran).",
    ]
    return result


def check_solo_ai_session(
    ai_test_file: Path, session_file: Path,
    *, node_bin: str = "node", timeout_s: int = 30,
) -> dict:
    """EXÉCUTE deux fichiers de preuve neufs (jamais réimplémentés) :
    `07_TESTS/unit/ai.test.mjs` (node --test — la LOGIQUE de l'IA solo est
    distincte du bot de solvabilité à latence nulle, deadzone incluse) ET
    `07_TESTS/oracle/solo_session.mjs` (harnais bot_action — une partie SOLO
    complète, joueur-proxy vs IA de jeu, atteint un état de fin défini). PASS
    ssi les DEUX sont mesurés et verts.

    NE PROUVE PAS : un joueur humain réel derrière le clavier (le camp gauche
    est un proxy déterministe, outil de test, PAS un humain) ; aucun clic réel
    ni rendu observé — logique pure, aucune I/O.

    Retourne {passed, checked, ai_logic{}, session{}, limites[]}."""
    ai_logic = _run_node_test_file(ai_test_file, node_bin=node_bin, timeout_s=timeout_s)

    session_file = Path(session_file)
    if not session_file.is_file():
        session: dict = {
            "passed": False, "checked": False,
            "reason": f"fichier de preuve absent, illisible ou pas un fichier: {session_file}",
        }
    else:
        try:
            proc = subprocess.run(
                [node_bin, str(session_file.resolve())],
                capture_output=True, text=True, timeout=timeout_s,
                encoding="utf-8", errors="replace",
            )
        except subprocess.TimeoutExpired:
            session = {"passed": False, "checked": True,
                       "reason": f"timeout ({timeout_s}s) sur {session_file}"}
        except OSError as exc:
            session = {"passed": False, "checked": False,
                       "reason": f"exécuteur node introuvable/inexécutable: {exc}"}
        else:
            try:
                payload = json.loads(proc.stdout) if proc.stdout.strip() else None
            except ValueError:
                payload = None
            if not isinstance(payload, dict):
                session = {
                    "passed": False, "checked": True,
                    "reason": "sortie JSON illisible depuis solo_session.mjs",
                    "returncode": proc.returncode,
                    "stdout_tail": proc.stdout[-500:], "stderr_tail": proc.stderr[-500:],
                }
            else:
                session = {
                    "passed": proc.returncode == 0 and bool(payload.get("passed")),
                    "checked": True,
                    "returncode": proc.returncode,
                    "report": payload,
                }

    checked = bool(ai_logic.get("checked")) and bool(session.get("checked"))
    passed = checked and bool(ai_logic.get("passed")) and bool(session.get("passed"))
    return {
        "passed": passed,
        "checked": checked,
        "ai_logic": ai_logic,
        "session": session,
        "limites": [
            "exécute 07_TESTS/unit/ai.test.mjs (node --test) et "
            "07_TESTS/oracle/solo_session.mjs (harnais bot_action) tels quels, "
            "jamais réimplémentés.",
            "NE PROUVE PAS qu'un joueur humain réel joue ce mode : le camp gauche "
            "est un proxy déterministe (outil de test), pas un humain au clavier.",
            "NE PROUVE PAS de clic réel ni de rendu observé — logique pure, aucune I/O.",
        ],
    }


# ============================================================================
# Agrégat — appelé par le driver (s10a), ADVISORY (jamais un gate dur ici)
# ============================================================================

def run_product_oracle(
    game_dir: Path, *, node_bin: str = "node",
    auto_session_max_ticks: int = 20000, auto_session_timeout_s: int = 30,
    visual_capture_timeout_s: int = 150, node_test_timeout_s: int = 60,
) -> dict:
    """Agrège les volets pour un jeu de topologie STANDARD (`06_RUNTIME/adapters/
    presentation/`, `05_SYSTEMS/...`, `07_TESTS/...`). ADVISORY : le driver ne
    fait QUE porter ce dict dans le reçu signé de s10a — aucun de ces volets ne
    gate `oracle_ok` dans cette mission (décision de gate dur = HumanGate séparé,
    sur les chiffres). Les 4 volets `restart_offer_wiring`/`exit_stop_wiring`/
    `playable_speed_band_test`/`solo_ai_session` (S1, 2026-07-27) EXÉCUTENT les 7
    fichiers de preuve neufs du run pong_r3 — aucun d'eux n'est réimplémenté."""
    game_dir = Path(game_dir)
    presentation_dir = game_dir / "06_RUNTIME" / "adapters" / "presentation"
    entry = presentation_dir / "browser" / "main.mjs"
    loop_file = game_dir / "05_SYSTEMS" / "game_loop" / "loop.mjs"
    state_file = game_dir / "05_SYSTEMS" / "game_state" / "state.mjs"
    input_file = game_dir / "05_SYSTEMS" / "input" / "input.mjs"
    unit_dir = game_dir / "07_TESTS" / "unit"
    oracle_dir = game_dir / "07_TESTS" / "oracle"

    return {
        "browser_import_safety": check_browser_import_safety(entry),
        "auto_session": check_auto_session(
            loop_file, state_file, input_file,
            max_ticks=auto_session_max_ticks, timeout_s=auto_session_timeout_s,
            node_bin=node_bin,
        ),
        "visual_capture": check_visual_capture(
            presentation_dir, node_bin=node_bin, timeout_s=visual_capture_timeout_s,
        ),
        "restart_offer_wiring": check_restart_offer_wiring(
            unit_dir / "restart_offer.test.mjs",
            node_bin=node_bin, timeout_s=node_test_timeout_s,
        ),
        "exit_stop_wiring": check_exit_stop_wiring(
            unit_dir / "exit_stop.test.mjs",
            node_bin=node_bin, timeout_s=node_test_timeout_s,
        ),
        "playable_speed_band_test": check_playable_speed_band(
            unit_dir / "playable_speed.test.mjs",
            node_bin=node_bin, timeout_s=node_test_timeout_s,
        ),
        "solo_ai_session": check_solo_ai_session(
            unit_dir / "ai.test.mjs", oracle_dir / "solo_session.mjs",
            node_bin=node_bin, timeout_s=auto_session_timeout_s,
        ),
    }
