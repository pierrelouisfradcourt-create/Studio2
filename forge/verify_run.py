"""Vérification MÉCANIQUE d'un verdict Forge — le maillon que `/gate` doit appeler.

Avant, `verify_*` n'était appelé que par les tests ; `/gate`/`/verdict` demandaient
à un agent de *dire* « HMAC OK ». Ici c'est une commande qui CALCULE :
  1. re-signe le corps du verdict et compare au `hmac` stocké (toute altération de
     contenu casse la signature — inclut les reçus d'oracle embarqués),
  2. RE-LIT chaque fichier d'évidence et confronte son sha256 au champ signé
     (scellé non décoratif),
  3. compare `git_head` signé au HEAD courant (dérive = avertissement TOCTOU).

Usage :
    PYTHONPATH=scripts python -m forge.verify_run EVIDENCE/runs/<projet>/verdict.json
Exit 0 = verdict authentique et évidence intacte ; 2 = falsification/altération ;
3 = verdict absent ou illisible (rien à vérifier — ni authentique ni falsifié, ce
sont deux états distincts qu'un instrument de confiance ne doit jamais confondre).

Limite honnête : sur un poste mono-utilisateur, un producteur qui LIT `.forge_key`
peut re-signer un faux verdict cohérent (fichiers d'évidence fabriqués compris).
Fermer ça exige une isolation du signataire (autre identité/process) — infra, pas
code. `verify_run` élève fortement la barre (il faut désormais falsifier le log ET
le hash ET re-signer) et rend la vérification mécanique au lieu de narrative.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

import yaml

from forge.context_manifest import verify_manifest_record
from forge.mutation_proof import verify_descriptor_mutation_receipt, verify_mutation_receipt
from forge.verdict import _verify_mapping, current_git_head, sha256_file

# R3 (FORGE_V2_CONSOLIDATION.md §4-A, ferme AM1) : script + timeout du recoupement
# knowledge_trace. forge/verify_run.py -> parent == forge (même
# dossier que knowledge_trace.mjs).
_KNOWLEDGE_TRACE_SCRIPT = Path(__file__).resolve().parent / "knowledge_trace.mjs"
_KNOWLEDGE_TRACE_TIMEOUT_S = 60


def _read_yaml_dict(path: Path) -> dict:
    """Lecture best-effort d'un YAML -- absent/illisible/mal formé => {} (jamais
    lever ; `verify_run` ne doit jamais planter sur un game_contract.yaml
    manquant, même discipline que `ForgeDriver._read_yaml`)."""
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError):
        return {}
    return data if isinstance(data, dict) else {}


def _read_json_dict(path: Path) -> dict:
    """Lecture best-effort d'un JSON -- absent/illisible => {} (même discipline
    que `_read_yaml_dict` ci-dessus, symétrique de `ForgeDriver._read_json`)."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def _check_mutation_proof(data: dict, key_file: Path | None, *,
                          require_green: bool = True) -> dict:
    """P0.3 — redescend dans le reçu mutation embarqué du reçu code.

    Un verdict de JEU (marqueur e2e OU mutation dans le detail du reçu code) doit
    porter une preuve mutation qui se re-vérifie contre l'état PRÉSENT du jeu
    (signature, run_id, hash code/tests/triage, baseline). La game-ness est
    dérivée AVANT le statut : un verdict de jeu non-OK sans preuve embarquée ne
    doit pas non plus passer overall=True (le court-circuit sur status==OK rendait
    cette garde inatteignable — finding 2 de la revue P0.3).

    V1 (séparation intégrité/verdict) — `require_green` (défaut True, comportement
    historique) est transmis tel quel à `verify_mutation_receipt`. Retourne
    {problems, status, checked} : `status` est le statut BRUT du reçu (None si
    aucun reçu n'a pu être lu — absence structurelle de preuve, jamais assimilé à
    "vert"), `checked` indique si `verify_mutation_receipt` a bien été appelée
    (False sur les deux branches structurelles : non-jeu, ou jeu sans preuve
    embarquée du tout — ces deux cas ne dépendent PAS de `require_green`)."""
    code_r = (data.get("oracles") or {}).get("code")
    if not isinstance(code_r, dict):
        return {"problems": [], "status": None, "checked": False}
    detail = code_r.get("detail") or {}
    mut = detail.get("mutation")
    # Marqueurs de game-ness durables : preuve mutation, garde e2e, garde
    # SOLVABILITÉ (F5c, 2026-07-14 : aligné sur driver._effective_is_game — le
    # driver marque 'solvability' dans le detail du reçu code d'un jeu, l'omettre
    # ici laissait un angle mort), OU la trace de dégradation laissée par le
    # driver quand il a invalidé une preuve mutation (mutation_verification) —
    # cette dernière survit au retrait de e2e/mutation dans un state.json falsifié
    # (finding 1 : le verdict BLOCKED reste détecté comme jeu, donc jamais
    # overall=True sans preuve).
    inferred_game = (isinstance(mut, dict) or detail.get("e2e") is not None
                     or detail.get("solvability") is not None
                     or "mutation_verification" in detail)
    # Lot 1 ADR-003 (P0-2) : la game-ness est d'abord le champ SIGNÉ `is_game` du
    # verdict (déclaré par le producteur, cf. verdict.AggregateVerdict.is_game).
    # L'inférence par clés facultatives du detail reste en FILET (verdicts
    # historiques sans le champ, producteur qui omet la déclaration) et ne peut
    # JAMAIS être désarmée par un `is_game` déclaré False/absent : OR strict —
    # sinon déclarer non-jeu redeviendrait le contournement exact que ce champ
    # ferme (recette minimale {"returncode": ...} classée non-jeu => AUTHENTIQUE
    # sans preuve mutation).
    declared_game = data.get("is_game")
    is_game = bool(declared_game) or inferred_game
    if not is_game:
        return {"problems": [], "status": None, "checked": False}  # non-jeu
    if not isinstance(mut, dict):
        # Reçu de jeu (déclaré is_game=True et/ou marqueur e2e/mutation) sans preuve
        # embarquée : non ratifiable, quel que soit le statut ET quel que soit
        # require_green (absence structurelle de preuve, pas une couleur de gate).
        why = ("déclaré is_game=True dans le verdict signé" if declared_game
               else "marqueur e2e/mutation")
        return {"problems": [f"reçu code de JEU ({why}) sans preuve mutation embarquée"],
                "status": None, "checked": False}
    receipt = mut.get("receipt") or {}
    receipt_detail = receipt.get("detail") or {}
    game_dir = receipt_detail.get("game_dir", "")
    # CONTRAT_PREUVE_MUTATION_V1.md §6/§7, PHASE ③ ÉTAPE 4 (go Pierre 2026-07-28) :
    # `verify_run` doit suivre le MÊME routage que le driver (`ForgeDriver._receipt`,
    # driver.py) -- `regime_preuve` du reçu code tranche entre les deux
    # vérificateurs DÉDIÉS, jamais une fusion. Absent (reçu antérieur à cette
    # mission, ou tout reçu du régime historique qui n'a jamais porté ce champ)
    # => "historique", exactement le même appel qu'avant cette mission --
    # bit-identique (Pong en dépend).
    regime = receipt_detail.get("regime_preuve", "historique")
    if regime == "descripteur":
        game_dir_path = Path(game_dir) if game_dir else Path()
        game_contract = _read_yaml_dict(game_dir_path / "00_CHARTER" / "game_contract.yaml")
        wiremap = _read_json_dict(game_dir_path / "09_WIREMAP" / "wiremap.json")
        chk = verify_descriptor_mutation_receipt(
            receipt, mut.get("signature", ""),
            data.get("run_id", ""), game_dir, game_contract, wiremap,
            key_file=key_file, require_green=require_green,
        )
    else:
        chk = verify_mutation_receipt(receipt, mut.get("signature", ""),
                                      data.get("run_id", ""), game_dir, key_file=key_file,
                                      require_green=require_green)
    return {"problems": [] if chk["passed"] else list(chk["raisons"]),
            "status": chk.get("status") or None, "checked": True}


def _check_knowledge_trace(run_dir: Path) -> tuple[list[str], list[str], bool]:
    """R3 — recoupe <run_dir>/knowledge_trace.json via `node knowledge_trace.mjs
    --verify` (ferme AM1) : le lineage de lecture (pré-mortem/knowledge_base/
    mandatory_read/packet servis à un run) était jusqu'ici AUTO-ATTESTÉ, jamais
    recoupé par un tiers mécanique. Retourne (problems, warnings, ok) — jamais ne lève.

    RÉGIME : **ADVISORY** — décision N-2, ratifiée Pierre 2026-09-02.
    Ce contrôle MESURE et RAPPORTE ; il ne bloque plus rien. Motif ratifié : le gate
    dur n'avait pas la mesure d'adoption qui conditionne sa ratification (précédent
    2026-07-26 : advisory + point de mesure d'abord, gate dur = décision ULTÉRIEURE),
    et brancher l'émetteur de traces aurait transformé une anomalie marginale
    (1 run_dir sur 89 portait une trace) en blocage systémique.
    Séquence ratifiée : advisory -> émission réelle -> mesure d'adoption -> décision
    Pierre sur le gate. La sonde (`knowledge_trace.mjs`, `verifyTrace`) est INCHANGÉE :
    cette décision retire une AUTORITÉ, pas une CAPACITÉ.

    - trace ABSENTE : avertissement (tous les runs n'en portent pas encore), `ok` True.
    - trace PRÉSENTE et le sous-processus échoue (exit != 0 : au moins un item
      NOT_FOUND = théâtre, ou trace corrompue/run_dir absent) : `ok` **False** et
      avertissement explicite. Le constat reste VRAI et VISIBLE (jamais un faux vert) ;
      seul son effet bloquant est retiré.
    - node INDISPONIBLE (introuvable, erreur de spawn, timeout) : avertissement
      honnête, `ok` True. L'absence d'outil ne se travestit JAMAIS en vérification
      réussie, ni en échec imputé à la trace.

    `problems` reste retourné et TOUJOURS VIDE sous ce régime : c'est le point de
    ré-armement de la décision ultérieure sur le gate, pas un canal mort.
    """
    problems: list[str] = []
    warnings: list[str] = []
    run_dir = Path(run_dir)
    trace_path = run_dir / "knowledge_trace.json"
    if not trace_path.exists():
        warnings.append(
            "knowledge_trace.json absent — lineage non recoupé (tous les runs "
            "n'en portent pas encore, cf. FORGE_V2_CONSOLIDATION.md R3)")
        return problems, warnings, True

    node_cmd = shutil.which("node") or "node"
    try:
        proc = subprocess.run(
            [node_cmd, str(_KNOWLEDGE_TRACE_SCRIPT), "--verify", str(run_dir.resolve())],
            capture_output=True, text=True, encoding="utf-8",
            timeout=_KNOWLEDGE_TRACE_TIMEOUT_S,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        warnings.append(
            f"knowledge_trace.mjs --verify non exécutable (node indisponible ?) : {exc}")
        return problems, warnings, True

    if proc.returncode != 0:
        detail = "\n".join(part for part in (proc.stderr, proc.stdout) if part).strip()
        # ADVISORY (N-2, 2026-09-02) : le constat part dans `warnings`, JAMAIS dans
        # `problems` — le driver agrège `problems` dans sa liste bloquante.
        warnings.append(
            f"knowledge_trace --verify a échoué (exit {proc.returncode}) "
            f"[ADVISORY, ne bloque pas — décision N-2] : {detail[-2000:]}"
        )
        return problems, warnings, False
    return problems, warnings, True


def _check_context_manifest(run_dir: Path, key_file: Path | None) -> tuple[list[str], list[str]]:
    """Contrôle du Context Manifest (mesure advisory de fraîcheur/traçabilité,
    docs/forge/CONTEXT_LOOP_V1_1_FRESHNESS.md §7) — PAS un gate : cette fonction
    ne fait QUE recouper une mesure déjà écrite, elle ne décide rien et n'entre
    PAS dans les gates existants du driver (hmac_ok/evidence/knowledge_trace).

    - fichier manifest ABSENT (répertoire ``context/`` absent ou vide) : simple
      note informative (les runs antérieurs à cette mesure n'en portent pas) —
      JAMAIS un problème, jamais un échec.
    - ligne présente avec HMAC invalide : problème DUR (la mesure a été altérée
      après coup — la ligne ne prouve plus rien).
    - on ne re-vérifie PAS que les sources listées sont inchangées : elles
      évoluent légitimement après le run (c'est le travail du context_check,
      pas de verify_run).

    Retourne (problems, notes) — n'affecte JAMAIS ``overall``."""
    problems: list[str] = []
    notes: list[str] = []
    ctx_dir = Path(run_dir) / "context"
    if not ctx_dir.is_dir():
        notes.append("context manifest absent (run antérieur à cette mesure, non bloquant)")
        return problems, notes
    manifest_files = sorted(ctx_dir.glob("*.manifest.jsonl"))
    if not manifest_files:
        notes.append("répertoire context/ vide — aucune ligne de manifest à recouper (non bloquant)")
        return problems, notes
    for mf in manifest_files:
        try:
            raw_text = mf.read_text(encoding="utf-8")
        except OSError as exc:
            notes.append(f"{mf.name}: illisible ({exc}) — non bloquant")
            continue
        for i, raw in enumerate(raw_text.splitlines(), start=1):
            raw = raw.strip()
            if not raw:
                continue
            try:
                rec = json.loads(raw)
            except ValueError:
                problems.append(f"{mf.name}:{i}: ligne JSON invalide")
                continue
            if not verify_manifest_record(rec, key_file):
                problems.append(f"{mf.name}:{i}: HMAC invalide (kind={rec.get('kind')!r})")
    return problems, notes


def verify_run(verdict_path: Path | str, key_file: Path | None = None) -> dict:
    """Vérifie un verdict.json. Retourne un dict structuré (jamais ne lève sur contenu)."""
    path = Path(verdict_path)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        # Absent/illisible n'est PAS falsifié : un fichier qui n'existe pas n'a
        # jamais été signé, donc rien à casser. On rend un dict de la MÊME forme
        # que le chemin nominal (toutes les clés que `main()` lit) pour qu'un
        # accès `res["mutation_ok"]` ne lève jamais KeyError sur ce cas — mais
        # marqué `unreadable=True` pour que l'affichage reste honnête (ni "OK",
        # ni "FALSIFIÉ"/"ALTÉRÉE", qui sont des accusations de contenu altéré).
        return {"overall": False, "integrity_ok": False, "unreadable": True,
                "reason": f"verdict absent ou illisible: {exc}",
                "hmac_ok": False, "evidence_ok": False, "evidence_problems": [],
                "mutation_ok": False, "mutation_problems": [],
                "mutation_integrity_problems": [], "mutation_gate_green": None,
                "mutation_status": None, "coherence_problems": [],
                "git_ok": True, "git_stored": "", "git_current": current_git_head(),
                "knowledge_trace_ok": False, "knowledge_trace_problems": [],
                "knowledge_trace_warnings": [],
                "software_verdict": None, "decision": None, "scope": None}

    hmac_stored = data.get("hmac", "")
    body = {k: v for k, v in data.items() if k != "hmac"}
    hmac_ok = bool(hmac_stored) and _verify_mapping(body, hmac_stored, key_file)

    # (2) évidence : re-lire chaque fichier référencé et confronter le hash signé.
    evidence_problems: list[str] = []
    for name, r in (data.get("oracles") or {}).items():
        if not isinstance(r, dict) or r.get("status") == "SKIPPED":
            continue
        ep = r.get("evidence_path") or ""
        exp = r.get("evidence_sha256") or ""
        if ep and exp:
            if sha256_file(ep) != exp:
                evidence_problems.append(f"{name}: évidence altérée/absente ({ep})")
        elif exp and not ep:
            evidence_problems.append(f"{name}: hash signé sans chemin -> non re-vérifiable")
    evidence_ok = not evidence_problems

    # (2ter) preuve mutation embarquée (P0.3) : échec DUR — contrairement à la
    # dérive git (repo-wide), le sceau mutation est spécifique aux fichiers du
    # jeu jugé ; sa divergence signifie que le verdict ne décrit plus la réalité.
    #
    # V1 (2026-07-26, séparation intégrité/verdict — mémoire pong_r2) : DEUX
    # registres, calculés séparément, plus jamais confondus :
    #   - INTÉGRITÉ (`mutation_integrity_*`, require_green=False) : authenticité
    #     du reçu — signature, run_id, empreintes code/tests, triage, évidence.
    #     Un reçu mutation FAIL authentique et à jour ne ment sur RIEN : il reste
    #     `integrity`-clean. C'est ce registre, et lui seul, qui alimente
    #     `overall`/le code de sortie.
    #   - VERDICT (`mutation_ok`/`mutation_problems`, LEGACY, require_green=True,
    #     comportement identique à avant V1) : conservé pour les appelants/tests
    #     existants, n'entre PLUS dans `overall`.
    #   - COHÉRENCE (`coherence_problems`) : le SEUL cas où un gate mutation rouge
    #     doit encore faire échouer l'intégrité — un verdict qui affiche
    #     software_verdict=OK alors que son propre reçu mutation embarqué n'est
    #     pas vert prétend un vert non prouvé (mensonge de provenance, pas
    #     simplement un FAIL honnête). GATE DUR, ne doit jamais régresser.
    _mutation_strict = _check_mutation_proof(data, key_file, require_green=True)
    mutation_problems = _mutation_strict["problems"]  # LEGACY (rétro-compat)
    mutation_ok = not mutation_problems                # LEGACY (rétro-compat)

    _mutation_loose = _check_mutation_proof(data, key_file, require_green=False)
    mutation_integrity_problems = _mutation_loose["problems"]
    mutation_integrity_ok = not mutation_integrity_problems
    mutation_status = _mutation_loose["status"]
    mutation_gate_green = (
        None if not _mutation_loose["checked"] else (mutation_status == "OK")
    )

    software_verdict = data.get("software_verdict")
    coherence_problems: list[str] = []
    # P2 (2026-08-15) : un verdict de périmètre PARTIEL ne peut pas se présenter
    # comme prêt-à-revue — `build_aggregate_verdict` plafonne déjà la décision à
    # WITH_OBJECTION ; cette garde attrape un producteur bogué/complaisant qui
    # signerait quand même un PARTIAL+HUMANGATE_READY (défense en profondeur,
    # même patron que la cohérence mutation ci-dessous). Champ absent = FULL
    # (verdicts historiques, comportement inchangé).
    scope = data.get("scope", "FULL")
    if scope == "PARTIAL" and data.get("decision") == "HUMANGATE_READY":
        coherence_problems.append(
            "verdict de scope PARTIAL avec decision HUMANGATE_READY — un périmètre "
            "incomplet ne peut jamais être présenté comme un run complet prêt à revue")
    if software_verdict == "OK" and _mutation_strict["problems"] and _mutation_loose["checked"]:
        # Le reçu se vérifie (checked=True) mais échoue en mode strict alors que
        # le verdict affiché prétend OK : soit le gate n'est pas vert, soit une
        # autre divergence d'intégrité coexiste — dans les deux cas, un OK
        # affiché ne doit jamais survivre à cette incohérence.
        coherence_problems += [
            f"verdict prétend software_verdict=OK alors que le gate mutation "
            f"embarqué ne le confirme pas: {r}" for r in mutation_problems
        ]

    # (3) dérive git (TOCTOU) : avertissement, pas échec dur.
    git_stored = data.get("git_head", "")
    git_current = current_git_head()
    git_ok = (not git_stored) or (git_current == git_stored)

    # (4) knowledge_trace (R3, ferme AM1) : **ADVISORY** depuis la décision N-2
    # (ratifiée Pierre 2026-09-02). `knowledge_trace_ok` reste un CONSTAT VRAI (False
    # sur théâtre/corruption — ne jamais afficher un faux vert) mais n'entre plus dans
    # `integrity_ok`/`overall` : même patron que le Context Manifest ci-dessous.
    # `knowledge_trace_problems` reste retourné, TOUJOURS VIDE — point de ré-armement
    # de la décision ultérieure, une fois l'adoption réellement mesurée.
    (knowledge_trace_problems, knowledge_trace_warnings,
     knowledge_trace_ok) = _check_knowledge_trace(path.parent)

    # (5) Context Manifest (advisory, jamais un gate) : recoupe les lignes déjà
    # écrites, n'entre PAS dans `overall` — c'est une mesure de fraîcheur, pas
    # un oracle de vérité logicielle (cf. _check_context_manifest ci-dessus).
    context_manifest_problems, context_manifest_notes = _check_context_manifest(path.parent, key_file)

    # `integrity_ok` (== `overall`, conservé pour rétro-compat) NE dépend PLUS de
    # la couleur du gate mutation d'un verdict honnête — seulement de son
    # authenticité (mutation_integrity_ok) et de sa cohérence interne
    # (coherence_problems, gate dur décrit ci-dessus).
    # N-2 (2026-09-02) : `knowledge_trace_ok` RETIRÉ de cette conjonction — un contrôle
    # advisory qui décide encore le code de sortie de la CLI resterait un gate.
    integrity_ok = (hmac_ok and evidence_ok and mutation_integrity_ok
                    and not coherence_problems)
    overall = integrity_ok
    return {
        "overall": overall,
        "integrity_ok": integrity_ok,
        "hmac_ok": hmac_ok,
        "evidence_ok": evidence_ok,
        "evidence_problems": evidence_problems,
        "mutation_ok": mutation_ok,
        "mutation_problems": mutation_problems,
        "mutation_integrity_problems": mutation_integrity_problems,
        "mutation_gate_green": mutation_gate_green,
        "mutation_status": mutation_status,
        "coherence_problems": coherence_problems,
        "git_ok": git_ok,
        "git_stored": git_stored,
        "git_current": git_current,
        "knowledge_trace_ok": knowledge_trace_ok,
        "knowledge_trace_problems": knowledge_trace_problems,
        "knowledge_trace_warnings": knowledge_trace_warnings,
        "context_manifest_problems": context_manifest_problems,
        "context_manifest_notes": context_manifest_notes,
        "software_verdict": data.get("software_verdict"),
        "decision": data.get("decision"),
        "scope": scope,
    }


def _harden_streams() -> None:
    """Robustesse encodage console (P3) : sous Windows cp1252, les caractères
    non encodables (⚠, ✗) levaient UnicodeEncodeError → exit 1 factice sur un
    verdict pourtant AUTHENTIQUE, faussant toute gate automatisée. On garde
    l'encodage natif du flux mais on remplace les caractères non représentables
    (errors='replace') au lieu de crasher. Aucune logique de vérification ni
    exit code sémantique (0/2) n'est modifié."""
    for stream in (sys.stdout, sys.stderr):
        reconf = getattr(stream, "reconfigure", None)
        if reconf is not None:
            try:
                reconf(errors="replace")
            except (OSError, ValueError):
                pass  # flux exotique (fermé, non-buffer) : on n'aggrave pas


def main(argv: list[str] | None = None) -> int:
    _harden_streams()
    argv = argv if argv is not None else sys.argv[1:]
    if not argv:
        print("usage: python -m forge.verify_run <verdict.json>", file=sys.stderr)
        return 2
    res = verify_run(argv[0])
    if res.get("unreadable"):
        # Constat, pas accusation : rien n'a été signé, donc rien n'a pu être
        # falsifié. Ne PAS réutiliser les mots "FALSIFIÉ"/"ALTÉRÉE" plus bas,
        # qui affirment qu'un contenu signé a été trafiqué.
        print(f"verdict          : absent ou illisible ({res.get('reason')})")
        print("\nVÉRIFICATION : IMPOSSIBLE (aucun verdict.json exploitable à cet emplacement)")
        return 3
    # V1 (séparation intégrité/verdict, design imposé pt.5) : deux lectures
    # distinctes, JAMAIS fusionnées. « VERDICT LOGICIEL » est un FAIT RAPPORTÉ
    # (peut être FAIL/BLOCKED sans que ce soit un rejet) ; « INTÉGRITÉ » (en bas)
    # est LA seule ligne qui décide le code de sortie.
    print(f"VERDICT LOGICIEL : {res.get('software_verdict')} / {res.get('decision')}")
    print(f"HMAC             : {'OK' if res['hmac_ok'] else 'FALSIFIÉ'}")
    print(f"évidence intacte : {'OK' if res['evidence_ok'] else 'ALTÉRÉE'}")
    for p in res.get("evidence_problems", []):
        print(f"   ✗ {p}")
    # `mutation_integrity_problems` est la forme V1 ; retombe sur `mutation_problems`
    # (forme historique) pour des appelants/mocks qui ne rendraient encore que
    # l'ancienne clé — jamais de KeyError sur un résultat façonné à la main.
    mutation_integrity_problems = res.get("mutation_integrity_problems")
    if mutation_integrity_problems is None:
        mutation_integrity_problems = res.get("mutation_problems", [])
    print(f"preuve mutation (intégrité) : {'OK' if not mutation_integrity_problems else 'INVALIDE/PÉRIMÉE'}")
    for p in mutation_integrity_problems:
        print(f"   ✗ {p}")
    mutation_status = res.get("mutation_status")
    if mutation_status is not None:
        vert = "vert" if res.get("mutation_gate_green") else "rouge"
        print(f"gate mutation (verdict logiciel, non bloquant) : {vert} (status={mutation_status})")
    for p in res.get("coherence_problems", []):
        print(f"   ✗ [cohérence] {p}")
    print("knowledge_trace  : " + ("OK" if res.get("knowledge_trace_ok", True)
          else "THÉÂTRE/CORROMPU — ADVISORY, n'entre pas dans l'intégrité (N-2)"))
    for p in res.get("knowledge_trace_problems", []):
        print(f"   ✗ {p}")
    for w in res.get("knowledge_trace_warnings", []):
        print(f"   ⚠ {w}")
    if not res["git_ok"]:
        print(f"⚠ dérive git : signé {res['git_stored'][:12]} != courant {res['git_current'][:12]} (TOCTOU)")
    print(f"\nINTÉGRITÉ : {'AUTHENTIQUE' if res['overall'] else 'REJET'}")
    return 0 if res["overall"] else 2


if __name__ == "__main__":
    sys.exit(main())
