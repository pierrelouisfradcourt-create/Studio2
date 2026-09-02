"""Forge Observer — console live (lecture seule), stdlib uniquement.

    python scripts/observer/live.py --project breakout_v2 [--port 8771] [--interval 5]

Sert une reconstruction Observer sur HTTP pendant qu'un run Forge tourne encore.
Aucune dependance externe (pas de Flask/FastAPI/websockets/SQL) : uniquement
`http.server`, `socketserver` (via `ThreadingHTTPServer`), `json`, `threading`.

Garanties tenues ici :

  * LECTURE SEULE. Aucune route d'ecriture. POST/PUT/DELETE/PATCH -> 405.
  * CECITE. `/api/source` reutilise la garde de `ObserverContext` (racines
    autorisees). Un chemin hors racines -> 403, jamais rattrape en succes.
  * RESILIENCE. Le thread de veille ne meurt jamais sur une analyse en echec :
    il journalise, garde le dernier etat valide, et l'expose via `/api/health`.
  * ATOMICITE. Chaque nouvel etat est construit entierement a part, puis
    echange en un seul geste (`Snapshot` immuable) : jamais de mutation en
    place d'un etat en cours de lecture par une requete concurrente.
  * LOCAL SEULEMENT. Ecoute sur 127.0.0.1 uniquement, jamais 0.0.0.0.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Optional
from urllib.parse import parse_qs, urlsplit

_HERE = Path(__file__).resolve().parent
if str(_HERE.parent) not in sys.path:  # rend `import observer` possible sans install
    sys.path.insert(0, str(_HERE.parent))

from observer.cli import DEFAULT_REPO, DEFAULT_TRANSCRIPTS, collect_all  # noqa: E402
from observer.correlate import prompt_drift, reconstruct  # noqa: E402
from observer.facts import build_facts, summarize  # noqa: E402
from observer.sources import ENCODING, BlindnessViolation, ObserverContext  # noqa: E402
from observer.views import build_views  # noqa: E402

LOG = logging.getLogger("observer.live")

# --------------------------------------------------------------------------- #
# Constantes (pas de magic numbers epars)
# --------------------------------------------------------------------------- #

DEFAULT_PORT = 8771
DEFAULT_INTERVAL_S = 5.0
DEFAULT_HOST = "127.0.0.1"  # jamais 0.0.0.0

DEFAULT_CONTEXT = 8
MAX_CONTEXT = 50
MAX_SOURCE_LINES = 400
MAX_SOURCE_CHARS = 200_000
MAX_LINE_CHARS = 2000

DEFAULT_EVENTS_LIMIT = 100
MAX_EVENTS_LIMIT = 500


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


# --------------------------------------------------------------------------- #
# Instantane immuable — l'etat servi bascule d'un bloc a l'autre, jamais mute
# --------------------------------------------------------------------------- #


@dataclass(frozen=True)
class Snapshot:
    """Un etat complet et coherent : `state` (pour /api/state) et l'index plat
    des evenements (pour /api/events), batis ensemble et echanges ensemble."""

    state: dict[str, Any]
    events_sorted: list[dict[str, Any]]
    version: int
    built_at: str


def _empty_state(project: str) -> dict[str, Any]:
    return {
        "schema": "observer.run.v0",
        "project": project,
        "observed_at": None,
        "version": 0,
        "runs": [],
        "counts": {},
        "drift": [],
        "facts_summary": {},
        "views": {},
    }


# --------------------------------------------------------------------------- #
# Empreinte de surveillance — mtime + taille, jamais de lecture de contenu
# --------------------------------------------------------------------------- #


def _list_dir_recursive(path: Path) -> list[tuple[str, int, int]]:
    """Liste recursive (fichiers seulement). Reserve aux arbres bornes par
    projet (`lab/forge_runs/<projet>/**`), jamais a l'arbre des transcripts."""
    if not path.is_dir():
        return []
    out: list[tuple[str, int, int]] = []
    try:
        for entry in path.rglob("*"):
            if not entry.is_file():
                continue
            try:
                st = entry.stat()
            except OSError:
                continue
            rel = str(entry.relative_to(path)).replace("\\", "/")
            out.append((rel, st.st_mtime_ns, st.st_size))
    except OSError:
        return []
    return sorted(out)


def _list_glob_shallow(path: Path, pattern: str) -> list[tuple[str, int, int]]:
    if not path.is_dir():
        return []
    out: list[tuple[str, int, int]] = []
    try:
        for entry in path.glob(pattern):
            if not entry.is_file():
                continue
            try:
                st = entry.stat()
            except OSError:
                continue
            out.append((entry.name, st.st_mtime_ns, st.st_size))
    except OSError:
        return []
    return sorted(out)


def _list_dir_shallow(path: Path) -> list[tuple[str, int, int]]:
    """Un seul niveau, sans recursion : suffisant comme heuristique de
    changement pour un dossier de centaines de transcripts (ne pas les
    enumerer un par un a chaque tour)."""
    if not path.is_dir():
        return []
    out: list[tuple[str, int, int]] = []
    try:
        with os.scandir(path) as it:
            for entry in it:
                try:
                    st = entry.stat(follow_symlinks=False)
                except OSError:
                    continue
                is_file = entry.is_file(follow_symlinks=False)
                out.append((entry.name, st.st_mtime_ns, st.st_size if is_file else -1))
    except OSError:
        return []
    return sorted(out)


def _fingerprint_size(fingerprint: dict[str, list[Any]]) -> int:
    return sum(len(v) for v in fingerprint.values())


# --------------------------------------------------------------------------- #
# Service : etat partage, thread de veille, reconstruction
# --------------------------------------------------------------------------- #


class ObserverService:
    """Detient l'etat servi et le fait evoluer en arriere-plan.

    Un seul thread de veille mute cet objet ; les threads HTTP ne font que
    lire `get_snapshot()` / `health()`. Le verrou protege uniquement les
    quelques scalaires et la reference d'instantane, jamais la reconstruction
    elle-meme (qui se fait hors verrou, potentiellement longue)."""

    def __init__(self, project: str, repo_root: Path, transcripts_root: Path,
                 interval_s: float) -> None:
        self.project = project
        self.repo_root = repo_root
        self.transcripts_root = transcripts_root
        self.interval_s = interval_s

        self._lock = threading.RLock()
        self._analysis_lock = threading.Lock()
        self._stop_event = threading.Event()
        self._thread: Optional[threading.Thread] = None

        self._version = 0
        self._last_fingerprint: Optional[dict[str, Any]] = None
        self._last_error: Optional[str] = None
        self._last_duration_s: Optional[float] = None
        self._last_analysis_ts: Optional[str] = None
        self._sources_watched = 0
        self._changes_detected = 0
        self._snapshot = Snapshot(
            state=_empty_state(project), events_sorted=[], version=0, built_at=_now_iso(),
        )

    # ------------------------------------------------------------------ #
    # API publique consommee par les handlers HTTP
    # ------------------------------------------------------------------ #

    def get_snapshot(self) -> Snapshot:
        with self._lock:
            return self._snapshot

    def health(self) -> dict[str, Any]:
        with self._lock:
            return {
                "status": "ok" if self._last_error is None else "error",
                "version": self._version,
                "derniere_analyse": self._last_analysis_ts,
                "duree_analyse_s": self._last_duration_s,
                "sources_surveillees": self._sources_watched,
                "changements_detectes": self._changes_detected,
                "derniere_erreur": self._last_error,
            }

    def bootstrap(self) -> float:
        """Premiere reconstruction, synchrone, bloquante. Retourne sa duree."""
        elapsed = self._maybe_refresh(force=True)
        return elapsed if elapsed is not None else 0.0

    def start_watcher(self) -> None:
        if self._thread is not None:
            return
        self._stop_event.clear()
        self._thread = threading.Thread(
            target=self._watcher_loop, name="observer-watcher", daemon=True,
        )
        self._thread.start()

    def stop_watcher(self) -> None:
        self._stop_event.set()
        if self._thread is not None:
            self._thread.join(timeout=5.0)
            self._thread = None

    # ------------------------------------------------------------------ #
    # Boucle de veille
    # ------------------------------------------------------------------ #

    def _watcher_loop(self) -> None:
        while not self._stop_event.is_set():
            try:
                self._maybe_refresh(force=False)
            except Exception:  # noqa: BLE001 - le thread de veille ne meurt jamais
                LOG.error("boucle de veille : erreur inattendue", exc_info=True)
            self._stop_event.wait(self.interval_s)

    def _compute_fingerprint(self) -> dict[str, Any]:
        forge_runs_dir = self.repo_root / "lab" / "forge_runs" / self.project
        forge_evidence_dir = self.repo_root / "lab" / "forge_evidence"
        return {
            "forge_runs": _list_dir_recursive(forge_runs_dir),
            "forge_evidence": _list_glob_shallow(forge_evidence_dir, "*.jsonl"),
            "transcripts": _list_dir_shallow(self.transcripts_root),
        }

    def _maybe_refresh(self, force: bool) -> Optional[float]:
        if not self._analysis_lock.acquire(blocking=False):
            LOG.debug("analyse deja en cours : ce tour est ignore (jamais en parallele)")
            return None
        try:
            try:
                fingerprint = self._compute_fingerprint()
            except Exception:  # noqa: BLE001 - une empreinte cassee ne doit pas tuer le thread
                LOG.error("echec du calcul d'empreinte de surveillance", exc_info=True)
                fingerprint = None

            changed = (
                fingerprint is None
                or self._last_fingerprint is None
                or fingerprint != self._last_fingerprint
            )
            if not force and not changed:
                return None

            if not force and self._last_fingerprint is not None:
                with self._lock:
                    self._changes_detected += 1

            t0 = time.perf_counter()
            try:
                ctx = ObserverContext.build(self.repo_root, self.project, self.transcripts_root)
                result, event_dicts = self._build_full_state(ctx)
            except Exception as exc:  # noqa: BLE001 - garder le dernier etat valide
                elapsed = time.perf_counter() - t0
                LOG.error("reconstruction en echec : %s", exc, exc_info=True)
                with self._lock:
                    self._last_error = f"{type(exc).__name__}: {exc}"
                    self._last_duration_s = round(elapsed, 3)
                    self._last_analysis_ts = _now_iso()
                    if fingerprint is not None:
                        self._sources_watched = _fingerprint_size(fingerprint)
                return elapsed

            elapsed = time.perf_counter() - t0
            events_sorted = sorted(
                event_dicts,
                key=lambda e: (
                    e["ts"] if e.get("ts") is not None else float("inf"),
                    e.get("event_id") or "",
                ),
            )
            with self._lock:
                self._version += 1
                state = {
                    "schema": result["schema"],
                    "project": result["project"],
                    "observed_at": result["observed_at"],
                    "version": self._version,
                    "runs": result["runs"],
                    "counts": result["counts"],
                    "drift": result["drift"],
                    "prompts": result.get("prompts", []),
                    "facts": result.get("facts", []),
                    "facts_summary": result["facts_summary"],
                    "views": result["views"],
                }
                self._snapshot = Snapshot(
                    state=state, events_sorted=events_sorted,
                    version=self._version, built_at=_now_iso(),
                )
                self._last_fingerprint = fingerprint
                self._last_error = None
                self._last_duration_s = round(elapsed, 3)
                self._last_analysis_ts = _now_iso()
                if fingerprint is not None:
                    self._sources_watched = _fingerprint_size(fingerprint)
            LOG.info(
                "reconstruction terminee en %.3fs (version=%d, evenements=%d)",
                elapsed, self._version, len(event_dicts),
            )
            return elapsed
        finally:
            self._analysis_lock.release()

    def _build_full_state(self, ctx: ObserverContext) -> tuple[dict[str, Any], list[dict[str, Any]]]:
        events, adapters = collect_all(ctx)
        result = reconstruct(events, ctx.project, ctx.read_paths)
        result["adapters"] = adapters
        result["observed_at"] = _now_iso()

        # Les prompts sont collectes AVANT les faits : ils qualifient le fait
        # « contexte injecte » et alimentent une regle de drift. Les collecter
        # apres produirait un etat servi different de celui de la CLI — deux
        # Observer pour le meme run, ce qui viderait l'outil de son sens.
        prompts = self._collect_prompts_safe(ctx) or []
        result["prompts"] = prompts
        result["drift"].extend(prompt_drift(prompts))

        event_dicts = [e.to_dict() for e in events]
        facts = build_facts(event_dicts, result["runs"], prompts)
        result["facts"] = [f.to_dict() for f in facts]
        result["facts_summary"] = summarize(facts)

        result["views"] = build_views(result, event_dicts, prompts=prompts, ctx=ctx)
        return result, event_dicts

    @staticmethod
    def _collect_prompts_safe(ctx: ObserverContext) -> Optional[list[Any]]:
        """`scripts/observer/prompt.py` est optionnel. S'il n'existe pas ou
        leve, on continue avec `prompts=None` — consigne explicite du mandat,
        propre a ce point d'integration (pas une derogation generale a la
        garde de cecite des adaptateurs)."""
        try:
            from observer.prompt import collect_prompts  # type: ignore
        except Exception:
            return None
        try:
            return collect_prompts(ctx)
        except Exception:
            LOG.warning("collect_prompts() a leve : prompts=None", exc_info=True)
            return None


# --------------------------------------------------------------------------- #
# /api/source — lecture bornee d'une fenetre de lignes
# --------------------------------------------------------------------------- #


def read_source_window(resolved: Path, line: Optional[int],
                        context: int) -> tuple[list[dict[str, Any]], int, bool]:
    """Lit une fenetre de lignes autour de `line` (ou le debut du fichier si
    `line` est absent), bornee en nombre de lignes et en caracteres."""
    if line is not None and line >= 1:
        start, end = max(1, line - context), line + context
    else:
        start, end = 1, MAX_SOURCE_LINES

    lines: list[dict[str, Any]] = []
    total = 0
    total_chars = 0
    truncated = False
    with resolved.open("r", encoding=ENCODING, errors="replace") as handle:
        for idx, raw in enumerate(handle, start=1):
            total = idx
            if idx < start or idx > end:
                continue
            if len(lines) >= MAX_SOURCE_LINES:
                truncated = True
                continue
            text = raw.rstrip("\r\n")
            if len(text) > MAX_LINE_CHARS:
                text = text[:MAX_LINE_CHARS]
                truncated = True
            if total_chars + len(text) > MAX_SOURCE_CHARS:
                truncated = True
                continue
            lines.append({"n": idx, "text": text})
            total_chars += len(text)
    return lines, total, truncated


def _parse_int(raw: Optional[str], default: int, minimum: Optional[int] = None,
               maximum: Optional[int] = None) -> int:
    try:
        value = int(raw) if raw is not None else default
    except (TypeError, ValueError):
        value = default
    if minimum is not None:
        value = max(minimum, value)
    if maximum is not None:
        value = min(maximum, value)
    return value


# --------------------------------------------------------------------------- #
# Serveur HTTP
# --------------------------------------------------------------------------- #


class ObserverRequestHandler(BaseHTTPRequestHandler):
    """Handler lecture seule. `service` est fixe au niveau classe avant que le
    serveur ne demarre ; il n'est jamais reassigne ensuite (lecture concurrente
    sure entre threads)."""

    service: ObserverService  # affecte dans main() avant ThreadingHTTPServer(...)
    server_version = "ForgeObserverLive/1.0"

    # -- ecriture : jamais --------------------------------------------- #

    def do_POST(self) -> None:
        self._method_not_allowed()

    def do_PUT(self) -> None:
        self._method_not_allowed()

    def do_DELETE(self) -> None:
        self._method_not_allowed()

    def do_PATCH(self) -> None:
        self._method_not_allowed()

    def _method_not_allowed(self) -> None:
        body = json.dumps({"error": "method_not_allowed"}).encode("utf-8")
        self.send_response(405)
        self.send_header("Allow", "GET")
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    # -- lecture ---------------------------------------------------------- #

    def do_GET(self) -> None:  # noqa: N802 - impose par BaseHTTPRequestHandler
        try:
            parsed = urlsplit(self.path)
            route = parsed.path
            qs = parse_qs(parsed.query)
            if route == "/":
                self._serve_console()
            elif route == "/api/state":
                self._serve_state()
            elif route == "/api/source":
                self._serve_source(qs)
            elif route == "/api/events":
                self._serve_events(qs)
            elif route == "/api/health":
                self._serve_health()
            else:
                self._send_json(404, {"error": "not_found", "path": route})
        except Exception as exc:  # noqa: BLE001 - une requete cassee ne doit pas planter le serveur
            LOG.error("erreur non geree sur %s: %s", self.path, exc, exc_info=True)
            try:
                self._send_json(500, {
                    "error": "internal_error",
                    "detail": f"{type(exc).__name__}: {exc}",
                })
            except Exception:  # noqa: BLE001
                pass

    def _serve_console(self) -> None:
        console_path = _HERE / "console.html"
        if console_path.is_file():
            try:
                body = console_path.read_bytes()
            except OSError as exc:
                self._send_json(500, {"error": "console_read_failed", "detail": str(exc)})
                return
            self._send_html(200, body)
            return
        placeholder = (
            "<!doctype html><meta charset=\"utf-8\"><title>Forge Observer</title>"
            "<body style=\"font-family:monospace;padding:2rem\">"
            "<h1>Forge Observer &mdash; console manquante</h1>"
            "<p><code>scripts/observer/console.html</code> n'existe pas encore sur ce "
            "poste. Le serveur live fonctionne normalement : "
            "<a href=\"/api/state\">/api/state</a> &middot; "
            "<a href=\"/api/health\">/api/health</a>.</p>"
            "</body>"
        ).encode("utf-8")
        self._send_html(200, placeholder)

    def _serve_state(self) -> None:
        snap = self.service.get_snapshot()
        self._send_json(200, snap.state)

    def _serve_health(self) -> None:
        self._send_json(200, self.service.health())

    def _serve_events(self, qs: dict[str, list[str]]) -> None:
        since = _parse_int(qs.get("since", [None])[0], default=0, minimum=0)
        limit = _parse_int(
            qs.get("limit", [None])[0], default=DEFAULT_EVENTS_LIMIT,
            minimum=1, maximum=MAX_EVENTS_LIMIT,
        )
        snap = self.service.get_snapshot()
        events = snap.events_sorted
        total = len(events)
        since = min(since, total)
        page = events[since:since + limit]
        next_since = since + len(page)
        self._send_json(200, {"events": page, "next_since": next_since, "total": total})

    def _serve_source(self, qs: dict[str, list[str]]) -> None:
        path_values = qs.get("path")
        if not path_values or not path_values[0]:
            self._send_json(400, {"error": "missing_query_param", "param": "path"})
            return
        path_param = path_values[0]

        line: Optional[int] = None
        if qs.get("line"):
            try:
                line = int(qs["line"][0])
            except ValueError:
                self._send_json(400, {"error": "invalid_query_param", "param": "line"})
                return

        context = DEFAULT_CONTEXT
        if qs.get("context"):
            try:
                context = int(qs["context"][0])
            except ValueError:
                context = DEFAULT_CONTEXT
        context = max(0, min(context, MAX_CONTEXT))

        candidate = Path(path_param)
        if not candidate.is_absolute():
            candidate = self.service.repo_root / path_param

        ctx = ObserverContext.build(
            self.service.repo_root, self.service.project, self.service.transcripts_root,
        )
        try:
            resolved = ctx._check(candidate)  # meme garde de cecite que le reste d'Observer
        except BlindnessViolation as exc:
            LOG.warning("source refusee (hors racines autorisees) : %s", candidate)
            self._send_json(403, {
                "error": "blindness_violation",
                "path": str(candidate),
                "detail": str(exc),
            })
            return

        if not resolved.exists():
            self._send_json(404, {"error": "not_found", "path": ctx.rel(resolved)})
            return
        if not resolved.is_file():
            self._send_json(404, {"error": "not_a_file", "path": ctx.rel(resolved)})
            return

        try:
            lines, total_lines, truncated = read_source_window(resolved, line, context)
        except OSError as exc:
            self._send_json(500, {"error": "read_failed", "detail": str(exc)})
            return

        self._send_json(200, {
            "path": ctx.rel(resolved),
            "line": line,
            "lines": lines,
            "total_lines": total_lines,
            "truncated": truncated,
        })

    # -- reponses ----------------------------------------------------------- #

    def _send_json(self, status: int, payload: Any) -> None:
        body = json.dumps(payload, ensure_ascii=False, default=str).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            LOG.debug("client deconnecte avant reception complete")

    def _send_html(self, status: int, body: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A002 - signature imposee
        LOG.info("%s - %s", self.address_string(), format % args)


class _Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


# --------------------------------------------------------------------------- #
# Point d'entree
# --------------------------------------------------------------------------- #


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Forge Observer — console live (lecture seule, stdlib uniquement)",
    )
    parser.add_argument("--project", default="breakout_v2")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--interval", type=float, default=DEFAULT_INTERVAL_S)
    parser.add_argument("--repo", type=Path, default=DEFAULT_REPO)
    parser.add_argument("--transcripts", type=Path, default=DEFAULT_TRANSCRIPTS)
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.INFO if args.verbose else logging.WARNING,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

    interval_s = max(1.0, args.interval)
    service = ObserverService(
        project=args.project,
        repo_root=args.repo.resolve(),
        transcripts_root=args.transcripts,
        interval_s=interval_s,
    )

    elapsed = service.bootstrap()
    LOG.info("reconstruction initiale : %.3fs (version=%d)", elapsed, service.get_snapshot().version)

    ObserverRequestHandler.service = service

    try:
        httpd = _Server((DEFAULT_HOST, args.port), ObserverRequestHandler)
    except OSError as exc:
        LOG.error("impossible d'ecouter sur %s:%d — %s", DEFAULT_HOST, args.port, exc)
        return 1

    service.start_watcher()

    print(
        f"Forge Observer live — http://{DEFAULT_HOST}:{args.port}/  "
        f"(projet={args.project}, intervalle={interval_s}s)"
    )

    try:
        httpd.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        service.stop_watcher()
        httpd.shutdown()
        httpd.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
