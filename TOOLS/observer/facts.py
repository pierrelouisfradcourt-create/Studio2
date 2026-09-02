"""Table de faits a provenance obligatoire.

Regle unique de ce module : **aucune affirmation sans provenance**. Un fait qui
ne peut pas nommer son fichier et son emplacement exact (numero de ligne pour un
`.jsonl`, chemin de champ pour un `.json`, portee explicite sinon) n'est pas
produit. Il devient `NOT_OBSERVABLE`, avec les quatre renseignements exiges :
pourquoi, quelle donnee manque, ou elle devrait exister, quel composant la
detient probablement.

Statuts :
  RECONSTRUIT     le fait est etabli par au moins une trace mecanique localisee.
  PARTIEL         une partie du fait est etablie, une autre ne l'est pas.
  NOT_OBSERVABLE  aucune trace du perimetre ne porte cette donnee.

Ce module ne juge pas la campagne. Il dit ce que les traces permettent d'affirmer.
"""

from __future__ import annotations

from collections import Counter, defaultdict
from dataclasses import asdict, dataclass, field
from typing import Any, Iterable, Optional

RECONSTRUIT = "RECONSTRUIT"
PARTIEL = "PARTIEL"
NOT_OBSERVABLE = "NOT_OBSERVABLE"

# Les 21 categories demandees pour la reconstruction de campagne.
CATEGORIES: tuple[str, ...] = (
    "timeline",
    "dispatch",
    "agents",
    "modeles",
    "contexte_injecte",
    "contrats",
    "tools_utilises",
    "fichiers_lus",
    "fichiers_ecrits",
    "commandes",
    "tokens",
    "couts",
    "retry",
    "tests",
    "mutation",
    "solvabilite",
    "failure_events",
    "captures",
    "verdict",
    "commits",
    "artefacts",
)


@dataclass
class Provenance:
    """Ou lire ce fait a la main. Au moins un localisateur est obligatoire."""

    path: str
    line: Optional[int] = None       # .jsonl : numero de ligne 1-indexe
    field: Optional[str] = None      # .json  : chemin de champ
    scope: Optional[str] = None      # sinon  : portee explicite assumee
    event_id: Optional[str] = None

    def valid(self) -> bool:
        return bool(self.path) and any((self.line is not None, self.field, self.scope))

    def to_dict(self) -> dict[str, Any]:
        return {k: v for k, v in asdict(self).items() if v is not None}


@dataclass
class Fact:
    id: str
    category: str
    label: str
    value: Any
    status: str
    proof: Optional[str] = None
    run_id: Optional[str] = None
    etape: Optional[str] = None
    provenance: list[Provenance] = field(default_factory=list)
    # Renseignements obligatoires quand le fait n'est pas observable.
    why: Optional[str] = None
    missing_data: Optional[str] = None
    should_exist_in: Optional[str] = None
    likely_owner: Optional[str] = None
    note: Optional[str] = None

    def to_dict(self) -> dict[str, Any]:
        out = {
            "id": self.id,
            "category": self.category,
            "label": self.label,
            "value": self.value,
            "status": self.status,
            "proof": self.proof,
            "run_id": self.run_id,
            "etape": self.etape,
            "provenance": [p.to_dict() for p in self.provenance],
            "why": self.why,
            "missing_data": self.missing_data,
            "should_exist_in": self.should_exist_in,
            "likely_owner": self.likely_owner,
            "note": self.note,
        }
        return {k: v for k, v in out.items() if v not in (None, [], "")}


# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #


def _prov(ev: dict[str, Any], field_path: str | None = None,
          scope: str | None = None) -> Provenance:
    """Provenance derivee d'un evenement.

    Un evenement issu d'un `.jsonl` apporte son numero de ligne. Un evenement
    issu d'un `.json` n'en a pas : le localisateur devient le chemin de champ,
    que l'appelant doit fournir — c'est lui qui sait quel champ il a lu.
    """
    src = ev.get("source", {})
    return Provenance(
        path=src.get("path", ""),
        line=src.get("line"),
        field=field_path or src.get("field"),
        scope=scope if (src.get("line") is None and not field_path
                        and not src.get("field")) else None,
        event_id=ev.get("event_id"),
    )


def _by_kind(events: Iterable[dict[str, Any]], kind: str,
             run_id: str | None = None) -> list[dict[str, Any]]:
    out = [e for e in events if e["kind"] == kind]
    if run_id:
        out = [e for e in out if e.get("run_id") == run_id]
    return out


def _fact(fid: str, category: str, label: str, value: Any, status: str,
          provenance: list[Provenance], **kw: Any) -> Fact:
    kept = [p for p in provenance if p.valid()]
    if status != NOT_OBSERVABLE and not kept:
        # Regle dure : pas de provenance valide => le fait n'est pas affirmable.
        return Fact(
            id=fid, category=category, label=label, value=None,
            status=NOT_OBSERVABLE,
            why="des traces existent mais aucune ne fournit de localisateur "
                "exploitable (ni ligne, ni chemin de champ)",
            missing_data="localisation precise de la donnee dans sa source",
            should_exist_in="l'adaptateur qui a produit l'evenement",
            likely_owner="scripts/observer/adapters/",
            **{k: v for k, v in kw.items() if k in ("run_id", "etape", "note")},
        )
    return Fact(fid, category, label, value, status, provenance=kept, **kw)


# --------------------------------------------------------------------------- #
# Extracteurs par categorie
# --------------------------------------------------------------------------- #


def _timeline(events: list[dict], run_id: str) -> list[Fact]:
    dated = [e for e in _run_events(events, run_id) if e.get("ts")]
    if not dated:
        return [Fact(
            id=f"{run_id}:timeline", category="timeline",
            label="fenetre temporelle du run", value=None, status=NOT_OBSERVABLE,
            run_id=run_id,
            why="aucun evenement date n'est rattache a ce run",
            missing_data="horodatages",
            should_exist_in="state.json (created_ts/updated_ts) et les .jsonl de contexte",
            likely_owner="scripts/forge/driver.py",
        )]
    first, last = min(dated, key=lambda e: e["ts"]), max(dated, key=lambda e: e["ts"])
    naive = sum(1 for e in dated if e.get("ts_format") in ("iso_naive", "log_naive"))
    return [_fact(
        f"{run_id}:timeline", "timeline", "fenetre temporelle du run",
        {"debut": first.get("ts_iso"), "fin": last.get("ts_iso"),
         "duree_s": round(last["ts"] - first["ts"], 1),
         "evenements_dates": len(dated),
         "horodatages_sans_fuseau": naive},
        RECONSTRUIT if naive == 0 else PARTIEL,
        [_prov(first), _prov(last)], run_id=run_id, proof="MECHANICAL",
        note=None if naive == 0 else
        f"{naive} horodatages sont sans fuseau (ISO nu ou log local) : leur "
        f"conversion en UTC est une hypothese, pas une lecture",
    )]


def _run_events(events: list[dict], run_id: str) -> list[dict]:
    return [e for e in events if e.get("run_id") == run_id]


def _dispatch(events: list[dict], run_id: str) -> list[Fact]:
    prepared = _by_kind(events, "dispatch.prepared", run_id)
    executed = _by_kind(events, "dispatch.executed", run_id)
    facts: list[Fact] = []
    if prepared or executed:
        facts.append(_fact(
            f"{run_id}:dispatch", "dispatch", "dispatches prepares et executes",
            {"prepared": len(prepared), "executed": len(executed),
             "etapes": sorted({e.get("etape") for e in prepared + executed if e.get("etape")})},
            RECONSTRUIT if len(prepared) == len(executed) else PARTIEL,
            [_prov(e) for e in (prepared + executed)[:6]],
            run_id=run_id, proof="SIGNED",
            note=None if len(prepared) == len(executed) else
            f"{len(prepared)} prepares pour {len(executed)} executes : l'ecart "
            f"n'est pas explique par les traces",
        ))
    return facts


def _agents_models(events: list[dict], run_id: str) -> list[Fact]:
    facts: list[Fact] = []
    dispatches = _by_kind(events, "dispatch.prepared", run_id)
    roles: Counter = Counter()
    for ev in dispatches:
        role = ev.get("actor", {}).get("capability_role") or ev["payload"].get("capability_role")
        if role:
            roles[role] += 1
    if roles:
        facts.append(_fact(
            f"{run_id}:agents", "agents", "roles de capacite actives",
            dict(roles), RECONSTRUIT,
            [_prov(e) for e in dispatches[:6]], run_id=run_id, proof="SIGNED",
        ))

    declared: Counter = Counter()
    for ev in dispatches:
        model = ev["payload"].get("model") or ev.get("actor", {}).get("model")
        if model:
            declared[model] += 1
    observed: Counter = Counter()
    usage = _by_kind(events, "llm.usage", run_id)
    for ev in usage:
        model = ev["payload"].get("model") or ev.get("actor", {}).get("model")
        if model and model != "<synthetic>":
            observed[model] += 1

    if declared or observed:
        concordant = bool(set(declared) & set(observed)) or not observed
        facts.append(_fact(
            f"{run_id}:modeles", "modeles",
            "modele declare par la Forge vs modele mesure dans les transcripts",
            {"declare": dict(declared), "mesure": dict(observed)},
            RECONSTRUIT if concordant else PARTIEL,
            [_prov(e) for e in dispatches[:3]] + [_prov(e) for e in usage[:3]],
            run_id=run_id, proof="SIGNED+MECHANICAL",
            note=None if concordant else
            "le modele signe dans l'audit n'apparait dans aucun message du "
            "transcript : la signature protege la declaration, elle ne mesure "
            "pas l'execution",
        ))
    return facts


def _contracts_context(events: list[dict], run_id: str,
                       prompts: list[dict] | None = None) -> list[Fact]:
    facts: list[Fact] = []
    manifests = _by_kind(events, "dispatch.context_manifest", run_id)
    if manifests:
        shas = sorted({m["payload"].get("contract_sha256") for m in manifests
                       if m["payload"].get("contract_sha256")})
        facts.append(Fact(
            id=f"{run_id}:contrats", category="contrats",
            label="contrats actives (identite seulement)",
            value={"contract_sha256": shas, "activations": len(manifests)},
            status=PARTIEL, run_id=run_id, proof="SIGNED",
            provenance=[_prov(m, "contract_sha256") for m in manifests[:6]],
            why="l'empreinte du contrat est tracee, son TEXTE ne l'est pas",
            missing_data="le contenu du contrat tel qu'active au moment du run",
            should_exist_in="une copie du contrat dans le run_dir, ou un magasin "
                            "adressable par contract_sha256",
            likely_owner="scripts/forge/contract.py (qui calcule l'empreinte) et "
                         "scripts/forge/contracts/*.yaml (qui detient le texte, "
                         "mais mutable apres coup)",
            note="si le fichier de contrat a change depuis, le texte exact active "
                 "est irrecuperable a posteriori",
        ))

    # Le prompt FINAL reellement recu par l'agent est integralement present dans
    # son transcript, et son empreinte se verifie contre celle que la Forge a
    # signee. C'est un chainon declare<->execute reellement ferme : ne pas le
    # sous-declarer sous pretexte que la Forge, seule, n'en garde que le SHA.
    mine = [p for p in (prompts or []) if p.get("run_id") == run_id]
    if mine:
        verifs = Counter(p.get("verification") for p in mine)
        verifies = verifs.get("MATCH", 0)
        facts.append(_fact(
            f"{run_id}:prompt_reel", "contexte_injecte",
            "prompt final reellement recu par l'agent (texte integral)",
            {"activations": len(mine),
             "verification": dict(verifs),
             "caracteres": {p.get("etape"): p.get("chars") for p in mine}},
            RECONSTRUIT if verifies == len(mine) else PARTIEL,
            [Provenance(path=p.get("source", {}).get("path", ""),
                        line=p.get("source", {}).get("line"))
             for p in mine[:6]],
            run_id=run_id, proof="MECHANICAL+SIGNED",
            note="le SHA-256 du texte (fins de ligne normalisees) reproduit "
                 "`final_prompt_sha256` declare par la Forge : le prompt recu est "
                 "prouve identique au prompt declare"
            if verifies == len(mine) else
            "une ou plusieurs activations n'ont pas d'empreinte declaree a "
            "comparer : le texte est lisible, sa conformite n'est pas prouvee",
        ))

    mission_prompts = _by_kind(events, "run.task_prompt", run_id)
    facts.append(Fact(
        id=f"{run_id}:contexte_ambiant", category="contexte_injecte",
        label="contexte AMBIANT ajoute par le harnais autour du prompt",
        value=None, status=NOT_OBSERVABLE, run_id=run_id,
        provenance=[_prov(m, "ambient_context_note") for m in manifests[:2]],
        why="le prompt de la Forge est integralement observable, mais ce que le "
            "harnais Claude Code ajoute autour (hooks de demarrage, CLAUDE.md, "
            "regles de projet) ne l'est pas ; la Forge elle-meme le declare non "
            "mesure dans `ambient_context_note`",
        missing_data="le texte du contexte ambiant effectivement charge",
        should_exist_in="le manifeste de contexte du run, a cote de "
                        "`ambient_context_note`",
        likely_owner="le harnais Claude Code (hors depot) et les hooks declares "
                     "dans .claude/settings.json",
        note=f"{len(mission_prompts)} prompt(s) de mission existent par ailleurs "
             f"en clair dans tasks_run*.json",
    ))
    return facts


def _tools(events: list[dict], run_id: str) -> list[Fact]:
    facts: list[Fact] = []
    by_step: dict[str, dict[str, Any]] = defaultdict(
        lambda: {"declared": set(), "observed": Counter(), "prov": [], "measured": None}
    )
    for ev in _by_kind(events, "dispatch.context_manifest", run_id):
        etape = ev.get("etape")
        tools = ev["payload"].get("tools_effective")
        if etape and isinstance(tools, list):
            by_step[etape]["declared"].update(str(t) for t in tools)
            by_step[etape]["prov"].append(_prov(ev, "tools_effective"))
    for ev in _by_kind(events, "dispatch.tools", run_id):
        etape = ev.get("etape")
        loaded = ev["payload"].get("loaded")
        if etape and isinstance(loaded, dict):
            by_step[etape]["measured"] = loaded.get("status")
            by_step[etape]["prov"].append(_prov(ev, "loaded.status"))
    for ev in _by_kind(events, "tool.call", run_id):
        etape = ev.get("etape")
        name = ev["payload"].get("tool_name")
        if etape and name:
            by_step[etape]["observed"][name] += 1
            if len(by_step[etape]["prov"]) < 8:
                by_step[etape]["prov"].append(_prov(ev, "tool_name"))

    for etape, data in sorted(by_step.items()):
        declared, observed = data["declared"], data["observed"]
        extra = sorted(set(observed) - declared) if declared else sorted(observed)
        facts.append(_fact(
            f"{run_id}:{etape}:tools", "tools_utilises",
            "outils declares par la Forge vs outils reellement appeles",
            {"declares": sorted(declared),
             "statut_mesure_forge": data["measured"],
             "observes": dict(observed.most_common()),
             "observes_hors_declaration": extra},
            RECONSTRUIT if not extra else PARTIEL,
            data["prov"], run_id=run_id, etape=etape, proof="SIGNED+MECHANICAL",
            note=None if not extra else
            "des outils appeles ne figurent pas dans la declaration de dispatch ; "
            "le rattachement des appels au run est de niveau session (inference)",
        ))
    return facts


def _files_and_commands(events: list[dict], run_id: str) -> list[Fact]:
    facts: list[Fact] = []
    for kind, category, label in (
        ("file.read", "fichiers_lus", "fichiers lus par l'agent"),
        ("file.write", "fichiers_ecrits", "fichiers ecrits par l'agent"),
        ("file.edit", "fichiers_ecrits", "fichiers edites par l'agent"),
    ):
        evs = _by_kind(events, kind, run_id)
        if not evs:
            continue
        paths = Counter(e["payload"].get("path") for e in evs if e["payload"].get("path"))
        links = sorted({e.get("link") for e in evs})
        facts.append(_fact(
            f"{run_id}:{kind}", category, label,
            {"chemins_distincts": len(paths), "appels": len(evs),
             "top": dict(paths.most_common(15))},
            RECONSTRUIT, [_prov(e, "path") for e in evs[:8]],
            run_id=run_id, proof="MECHANICAL",
            note=f"rattachement au run par portee de session ({', '.join(links)}) : "
                 f"le run_id n'est present que sur la ligne du marqueur de dispatch, "
                 f"pas sur chaque appel d'outil",
        ))

    shells = _by_kind(events, "shell.exec", run_id)
    if shells:
        facts.append(_fact(
            f"{run_id}:commandes", "commandes", "commandes shell executees",
            {"nombre": len(shells),
             "echantillon": [s["payload"].get("command", "")[:120] for s in shells[:8]]},
            RECONSTRUIT, [_prov(s, "command") for s in shells[:8]],
            run_id=run_id, proof="MECHANICAL",
        ))
    return facts


def _cost_tokens(events: list[dict], run_id: str) -> list[Fact]:
    facts: list[Fact] = []
    telemetry = _by_kind(events, "telemetry.step", run_id)
    builders = _by_kind(events, "builder.attempt", run_id)
    usage = _by_kind(events, "llm.usage", run_id)

    declared_tokens = sum(int(e["payload"].get("tokens") or 0) for e in telemetry)
    declared_tokens += sum(int(e["payload"].get("tokens_estimated") or 0) for e in builders)
    measured = {
        "input": sum(int(e["payload"].get("input_tokens") or 0) for e in usage),
        "output": sum(int(e["payload"].get("output_tokens") or 0) for e in usage),
        "cache_read": sum(int(e["payload"].get("cache_read_input_tokens") or 0) for e in usage),
        "cache_creation": sum(
            int(e["payload"].get("cache_creation_input_tokens") or 0) for e in usage
        ),
    }
    if telemetry or usage:
        billable = measured["input"] + measured["output"] + measured["cache_creation"]
        coherent = not (declared_tokens and billable > declared_tokens * 1.5)
        facts.append(_fact(
            f"{run_id}:tokens", "tokens",
            "tokens declares par la Forge vs mesures dans les transcripts",
            {"declares": declared_tokens, "mesures": measured,
             "mesures_facturables": billable},
            RECONSTRUIT if coherent else PARTIEL,
            ([_prov(e, "tokens") for e in telemetry[:3]] +
             [_prov(e, "usage") for e in usage[:3]]),
            run_id=run_id, proof="MECHANICAL",
            note=None if coherent else
            "les deux comptes divergent d'un facteur superieur a 1,5 ; la lecture "
            "de cache n'est pas comptee du tout par la telemetrie",
        ))

    declared_cost = sum(float(e["payload"].get("cost_usd") or 0) for e in telemetry)
    declared_cost += sum(float(e["payload"].get("cost_estimated") or 0) for e in builders)
    facts.append(Fact(
        id=f"{run_id}:couts", category="couts", label="cout du run",
        value={"declare_usd": round(declared_cost, 4)},
        status=PARTIEL if (telemetry or builders) else NOT_OBSERVABLE,
        run_id=run_id, proof="MECHANICAL",
        provenance=[_prov(e, "cost_usd") for e in telemetry[:3]] +
                   [_prov(e, "cost_estimated") for e in builders[:3]],
        why="le cout declare est un montant sans grille de prix ni detail de "
            "calcul dans les traces ; il ne peut pas etre recalcule ni verifie",
        missing_data="la grille tarifaire et la formule appliquee",
        should_exist_in="forge_telemetry.jsonl, a cote de cost_usd",
        likely_owner="le producteur de forge_telemetry.jsonl (scripts/forge/)",
    ))
    return facts


def _retry(events: list[dict], run_id: str) -> list[Fact]:
    builders = _by_kind(events, "builder.attempt", run_id)
    steps = _by_kind(events, "step.status", run_id)
    vocab = Counter(e.get("attempt_field") for e in _run_events(events, run_id)
                    if e.get("attempt_field"))
    if not builders and not steps:
        return []
    strategies = Counter(e["payload"].get("strategy") for e in builders
                         if e["payload"].get("strategy"))
    return [_fact(
        f"{run_id}:retry", "retry", "tentatives et reprises",
        {"builder_attempts": len(builders), "strategies": dict(strategies),
         "vocabulaires_de_tentative_rencontres": dict(vocab)},
        RECONSTRUIT if len(vocab) <= 1 else PARTIEL,
        [_prov(e, "strategy") for e in builders[:5]], run_id=run_id, proof="MECHANICAL",
        note=None if len(vocab) <= 1 else
        "la notion de tentative est portee par plusieurs champs concurrents "
        "(attempt / activation / retry_number / attempts) : les compter ensemble "
        "melangerait des unites differentes",
    )]


def _proofs(events: list[dict], run_id: str) -> list[Fact]:
    facts: list[Fact] = []
    specs = (
        ("test.result", "tests", "resultat de la suite de tests",
         lambda p: {"passed": p.get("passed"), "failed": p.get("failed"),
                    "fichiers": p.get("files")}, "passed"),
        ("mutation.result", "mutation", "resultat de mutation",
         lambda p: {"killed": p.get("killed"), "total": p.get("total"),
                    "survived": p.get("survived")}, "mutation_execution.killed"),
        ("solvability.result", "solvabilite", "solvabilite R9",
         lambda p: {"won": p.get("won"), "trials": p.get("trials"),
                    "verdict": p.get("verdict")}, "won"),
        ("capture.visual", "captures", "captures visuelles",
         lambda p: {"boot": p.get("boot_png"), "midgame": p.get("midgame_png"),
                    "differentes": p.get("captures_different")}, "boot_png"),
    )
    for kind, category, label, project, field_path in specs:
        evs = _by_kind(events, kind, run_id)
        if not evs:
            continue
        facts.append(_fact(
            f"{run_id}:{category}", category, label,
            project(evs[0]["payload"]), RECONSTRUIT,
            [_prov(e, field_path) for e in evs], run_id=run_id, proof="MECHANICAL",
        ))

    failures = _by_kind(events, "failure.event", run_id)
    if failures:
        facts.append(_fact(
            f"{run_id}:failure_events", "failure_events", "incidents enregistres",
            {"nombre": len(failures),
             "echantillon": [str(f["payload"].get("error") or
                                 f["payload"].get("message") or "")[:140]
                             for f in failures[:5]]},
            RECONSTRUIT, [_prov(f, "error") for f in failures[:6]],
            run_id=run_id, proof="MECHANICAL",
        ))

    verdicts = _by_kind(events, "verdict.signed", run_id)
    if verdicts:
        payload = verdicts[-1]["payload"]
        facts.append(_fact(
            f"{run_id}:verdict", "verdict", "verdict signe",
            {"decision": payload.get("decision"),
             "software_verdict": payload.get("software_verdict"),
             "claim_verdict": payload.get("claim_verdict"),
             "hmac": (payload.get("hmac") or "")[:16] + "...",
             "git_head": payload.get("git_head")},
            RECONSTRUIT, [_prov(verdicts[-1], "decision")],
            run_id=run_id, proof="SIGNED",
            note="Observer constate la presence d'une signature ; il ne la "
                 "reverifie pas (c'est le role de forge.verify_run)",
        ))

    artifacts = _by_kind(events, "artifact.self_declared", run_id)
    if artifacts:
        facts.append(_fact(
            f"{run_id}:artefacts", "artefacts", "rapports d'etape de l'agent",
            {"nombre": len(artifacts),
             "etapes": sorted({a.get("etape") for a in artifacts if a.get("etape")})},
            RECONSTRUIT, [_prov(a, scope="document entier") for a in artifacts],
            run_id=run_id, proof="SELF_DECLARED",
            note="AUTO-DECLARE : l'agent decrit son propre travail. Ce fait atteste "
                 "l'existence du rapport, pas la verite de son contenu",
        ))
    return facts


def _commits(events: list[dict]) -> list[Fact]:
    commits = [e for e in events if e["kind"] == "git.commit"]
    if not commits:
        return []
    return [Fact(
        id="campagne:commits", category="commits",
        label="commits touchant le projet",
        value={"nombre": len(commits),
               "sujets": [c["payload"].get("subject") for c in commits
                          if c["payload"].get("subject")]},
        status=PARTIEL, proof="MECHANICAL",
        provenance=[_prov(c, scope="git log --all -- <projet>") for c in commits],
        why="un commit n'est rattache a aucun run_id : rien dans le depot ne relie "
            "un commit a la tentative qui l'a produit",
        missing_data="le lien commit -> run_id",
        should_exist_in="le message de commit, ou une note git, ou le verdict",
        likely_owner="le geste humain de commit (HumanGate), hors de la Forge",
    )]


def _humangate() -> Fact:
    return Fact(
        id="campagne:humangate", category="verdict",
        label="ratification HumanGate de la campagne",
        value=None, status=NOT_OBSERVABLE,
        why="`HUMANGATE_READY` signifie PRET POUR la gate, pas RATIFIE PAR elle ; "
            "aucune trace du perimetre observe ne porte de decision humaine",
        missing_data="la decision de Pierre (merge / reject / freeze) et sa date",
        should_exist_in="studio_brain/decisions/decision-log.md (destination ratifiee "
                        "D4 du 2026-07-26)",
        likely_owner="la skill /gate, hors des racines lisibles par Observer V0",
    )


# --------------------------------------------------------------------------- #
# Assemblage
# --------------------------------------------------------------------------- #


def build_facts(events: list[dict[str, Any]], runs: list[dict[str, Any]],
                prompts: list[dict[str, Any]] | None = None) -> list[Fact]:
    facts: list[Fact] = []
    for run in runs:
        run_id = run["run_id"]
        facts.extend(_timeline(events, run_id))
        facts.extend(_dispatch(events, run_id))
        facts.extend(_agents_models(events, run_id))
        facts.extend(_contracts_context(events, run_id, prompts))
        facts.extend(_tools(events, run_id))
        facts.extend(_files_and_commands(events, run_id))
        facts.extend(_cost_tokens(events, run_id))
        facts.extend(_retry(events, run_id))
        facts.extend(_proofs(events, run_id))
    facts.extend(_commits(events))
    facts.append(_humangate())
    return facts


def summarize(facts: list[Fact]) -> dict[str, Any]:
    by_status = Counter(f.status for f in facts)
    by_category: dict[str, Counter] = defaultdict(Counter)
    for fct in facts:
        by_category[fct.category][fct.status] += 1

    sans_provenance = [
        f.id for f in facts
        if f.status != NOT_OBSERVABLE and not f.provenance
    ]
    localisation = Counter()
    for fct in facts:
        for prov in fct.provenance:
            if prov.line is not None:
                localisation["ligne"] += 1
            elif prov.field:
                localisation["champ"] += 1
            else:
                localisation["portee"] += 1

    manquantes = sorted(set(CATEGORIES) - {f.category for f in facts})

    return {
        "total": len(facts),
        "par_statut": dict(by_status),
        "par_categorie": {k: dict(v) for k, v in sorted(by_category.items())},
        "faits_sans_provenance": sans_provenance,
        "localisateurs": dict(localisation),
        "categories_sans_aucun_fait": manquantes,
        "not_observable": [
            {
                "id": f.id, "label": f.label, "why": f.why,
                "missing_data": f.missing_data,
                "should_exist_in": f.should_exist_in,
                "likely_owner": f.likely_owner,
            }
            for f in facts if f.status == NOT_OBSERVABLE
        ],
        "partiels": [
            {"id": f.id, "label": f.label, "why": f.why or f.note}
            for f in facts if f.status == PARTIEL
        ],
    }
