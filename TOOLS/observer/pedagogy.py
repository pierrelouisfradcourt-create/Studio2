"""Vue PÉDAGOGIE + Accueil de Forge Observer V0 — « le cockpit doit enseigner la Forge ».

Directive ratifiée (Pierre, 2026-08-02) : quand on clique sur un bloc ou un agent, on veut
un petit encart — pourquoi cette pièce existe, à quoi elle sert, ce qui casse si elle casse,
quelles autres pièces en dépendent. Ce module produit ces encarts (`build_pedagogy`) et la
pièce 🏠 Accueil (`view_accueil`) qui les résume au format « ce que je dois savoir ce matin ».

RÈGLE D'HONNÊTETÉ NON NÉGOCIABLE (identique aux autres vues Observer, resserrée ici) : aucune
phrase pédagogique n'est inventée. Chaque rubrique `pourquoi` / `a_quoi_sert` / `si_casse`
porte soit :
  - une reformulation courte (2-3 phrases), ANCRÉE sur un extrait réel (`base_textuelle`,
    200 caractères max) d'une source de doctrine lisible via `ObserverContext`
    (`scripts/forge/contracts/*.yaml`, `scripts/forge/contracts/SCHEMA.md`,
    `docs/forge/STUDIO_MASTER_SCHEMA.html`, `docs/forge/FORGE_V2_PILOTAGE.html`,
    `knowledge_base/README.md`), CITÉE (`src`) ;
  - soit `NOT_OBSERVABLE` avec sa raison, quand aucune doctrine lisible ne documente la pièce
    (cas mesuré : Observer lui-même — sa propre doctrine vit sous `docs/observer/`, hors des
    racines lisibles d'`ObserverContext` ; `.claude/skills/`, `lab/reports/` idem).

« Quelles pièces en dépendent » (`depend_de` / `dependants`) n'est JAMAIS rédigé : c'est
DÉRIVÉ mécaniquement d'un graphe construit à partir (1) des marqueurs de nom de fichier
réellement trouvés dans les champs de contrat (`mandatory_read`, `memoire`, `objectif`,
`gardeFou`, `in_scope`, `out_of_scope`), (2) de la table `_BLOCK_ETAPES` (arêtes du pipeline
standard, la même que `system_artefacts._WORKFLOW_BLOCKS`), et (3) d'une poignée d'arêtes
producteur non inférables depuis `mandatory_read` seul, chacune assertée depuis un champ de
contrat explicitement cité (`_PRODUCER_EDGES`). Voir `_build_graph` pour le détail.

Trois familles de pièces (32 cartes) :
  - 9 blocs du workflow standard (World Scan → Knowledge Base → Architect → WireMap →
    Builder → Runtime → Observer → Lessons → retour KB), id `bloc:<label>`.
  - les rôles d'agent actifs du pipeline, une carte par `capability_role` distinct trouvé
    dans `scripts/forge/contracts/*.yaml`, id `agent:<role>`.
  - les 10 catégories d'artefacts (même liste que `system_artefacts.view_artefacts`),
    id `artefact:<categorie>`.

Ce module ne lit rien lui-même en dehors d'`ObserverContext` (`ctx.read_text` / `ctx.iter_files`),
qui lève `BlindnessViolation` si une racine non déclarée est touchée. Cette exception n'est
JAMAIS rattrapée ici. Aucune écriture.
"""

from __future__ import annotations

import logging
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any, Optional

_HERE = Path(__file__).resolve().parent
if str(_HERE.parent) not in sys.path:  # rend `import observer` possible sans install
    sys.path.insert(0, str(_HERE.parent))

LOG = logging.getLogger("observer.pedagogy")

NOT_OBSERVABLE = "NOT_OBSERVABLE"

# --------------------------------------------------------------------------- #
# Constantes de structure — dupliquées volontairement depuis system_artefacts.py
# (pas importées) : ce sont deux modules de VUE indépendants, chacun charge ses
# propres sources via ObserverContext ; importer une table privée d'un autre
# module de vue coupleraity la pédagogie aux internes de system_artefacts au
# lieu de la doctrine elle-même. La table ci-dessous reflète la même structure
# ratifiée (les 9 blocs du pipeline standard) — si elle diverge un jour de
# system_artefacts._WORKFLOW_BLOCKS, c'est un drift à corriger, pas un secret.
# --------------------------------------------------------------------------- #

_BLOCK_ETAPES: dict[str, tuple[str, ...]] = {
    "World Scan": ("s2-worldscan",),
    "Knowledge Base": (),
    "Architect": ("s4-archi",),
    "WireMap": ("wm1-wiremap-breakout", "s5-wiremap"),
    "Builder": ("s9-build-godot-standard", "s9-build", "s9-build-standard", "s9-build-godot"),
    "Runtime": (),
    "Observer": (),
    "Lessons": (),
    "retour KB": (),
}
_BLOCK_LABELS: tuple[str, ...] = tuple(_BLOCK_ETAPES.keys())

# Même liste, même ordre que system_artefacts._category_roots(ctx, project).keys().
_ARTEFACT_CATEGORIES: tuple[str, ...] = (
    "Charters", "Wiremaps", "World Scan", "Knowledge", "Skills",
    "Contracts", "Lessons", "Reports", "Games", "Runtime",
)

_ROLE_HUMAN_NAMES: dict[str, str] = {
    "contract_author": "Rédacteur du Contrat",
    "run_orchestrator": "Orchestrateur de run",
    "prisme": "Prisme Produit",
    "worldscan": "Éclaireur World Scan",
    "decompose": "Décomposeur fonctionnel",
    "architect": "Architecte",
    "art_director": "Directeur artistique",
    "wiremap": "Cartographe WireMap",
    "game_forger": "Forgeron de jeu (Godot)",
    "builder": "Builder générique",
    "deterministic": "Oracle déterministe",
    "redteam_reviewer": "Red-team du plan",
    "redteam_code": "Red-team du code",
    "forge_toolsmith": "Artisan-outilleur Forge",
}

_KB_README_PATH = "knowledge_base/README.md"
_PILOTAGE_PATH = "docs/forge/FORGE_V2_PILOTAGE.html"
_SCHEMA_PATH = "scripts/forge/contracts/SCHEMA.md"
_LESSONS_PATH = "lab/reports/lessons.jsonl"


# --------------------------------------------------------------------------- #
# Cellule {v, src?, base_textuelle?, why?, derive_du_graphe?}
# --------------------------------------------------------------------------- #


def _short(text: Any, limit: int = 200) -> str:
    text = " ".join(str(text).split())
    return text if len(text) <= limit else text[:limit].rstrip() + "…"


def _r(
    value: Any,
    src: Optional[dict[str, Any]] = None,
    base_textuelle: Optional[str] = None,
    why: Optional[str] = None,
    derive_du_graphe: bool = False,
) -> dict[str, Any]:
    out: dict[str, Any] = {"v": value}
    if src:
        out["src"] = src
    if base_textuelle:
        out["base_textuelle"] = _short(base_textuelle)
    if value == NOT_OBSERVABLE and why:
        out["why"] = why
    if derive_du_graphe:
        out["derive_du_graphe"] = True
    return out


def _rien(why: str) -> dict[str, Any]:
    """Raccourci pour une pièce sans aucune source de doctrine trouvée : les trois
    rubriques valent NOT_OBSERVABLE avec la même raison, jamais une prose inventée."""
    return {
        "pourquoi": _r(NOT_OBSERVABLE, why=why),
        "a_quoi_sert": _r(NOT_OBSERVABLE, why=why),
        "si_casse": _r(NOT_OBSERVABLE, why=why),
    }


def _cite_field(path: str, field: str) -> dict[str, str]:
    return {"path": path, "field": field}


def _find_line(text: Optional[str], needle: str) -> Optional[int]:
    if text is None or needle not in text:
        return None
    return text[: text.index(needle)].count("\n") + 1


def _cite_doc(path: str, text: Optional[str], needle: str) -> dict[str, Any]:
    """Cite un document prose (SCHEMA.md, README.md, un .html) au meilleur endroit
    trouvable : localise `needle` DANS le texte réellement lu, jamais un numéro de
    ligne devine à la main — si `needle` n'y est plus (le doc a changé), la citation
    retombe sur le chemin seul plutôt que de mentir sur la ligne."""
    out: dict[str, Any] = {"path": path}
    line = _find_line(text, needle)
    if line is not None:
        out["line"] = line
    return out


# --------------------------------------------------------------------------- #
# Chargement des contrats — même mécanique que system_artefacts._load_contracts
# et system_agents.view_agents, réécrite ici en petit pour ne dépendre que
# d'ObserverContext (pas d'un import privé cross-module).
# --------------------------------------------------------------------------- #


def _load_all_contracts(ctx: Any) -> dict[str, dict[str, Any]]:
    contracts_dir = ctx.repo_root / "scripts" / "forge" / "contracts"
    out: dict[str, dict[str, Any]] = {}
    files = ctx.iter_files(contracts_dir, "*.yaml")
    if not files:
        return out
    try:
        import yaml
    except ImportError:
        LOG.warning("PyYAML indisponible dans cet interpreteur : contrats non parses, "
                    "pedagogie degradee a NOT_OBSERVABLE pour les cartes issues de contrats")
        return out
    for path in files:
        if path.name == "roles.yaml":
            continue
        text = ctx.read_text(path)
        if text is None:
            continue
        try:
            data = yaml.safe_load(text)
        except yaml.YAMLError as exc:
            LOG.warning("contrat illisible %s: %s", ctx.rel(path), exc)
            continue
        if isinstance(data, dict):
            out[path.stem] = {"data": data, "path": ctx.rel(path).replace("\\", "/")}
    return out


def _read_docs(ctx: Any) -> dict[str, Optional[str]]:
    return {
        "kb_readme": ctx.read_text(ctx.repo_root / "knowledge_base" / "README.md"),
        "pilotage": ctx.read_text(ctx.repo_root / "docs" / "forge" / "FORGE_V2_PILOTAGE.html"),
        "schema": ctx.read_text(ctx.repo_root / "scripts" / "forge" / "contracts" / "SCHEMA.md"),
    }


# --------------------------------------------------------------------------- #
# Graphe de dépendance mécanique — voir docstring de module pour la règle.
# --------------------------------------------------------------------------- #

_CONSUMER_MARKERS: tuple[tuple[str, str], ...] = (
    ("GAME_REFERENCE", "artefact:World Scan"),
    ("knowledge_packet.json", "artefact:World Scan"),
    ("knowledge_base/", "artefact:Knowledge"),
    ("catalog.json", "artefact:Knowledge"),
    ("wiremap.json", "artefact:Wiremaps"),
    ("charter.yaml", "artefact:Charters"),
    ("lessons.jsonl", "artefact:Lessons"),
    ("SCHEMA.md", "artefact:Contracts"),
    ("06_RUNTIME", "artefact:Runtime"),
)

# Arêtes producteur non inférables depuis mandatory_read seul (« qui écrit cette
# catégorie », pas « qui la lit ») — chacune assertée depuis un champ de contrat
# explicitement cité dans build_pedagogy au moment où la carte de la catégorie
# est construite (output_contract de s9-build-godot-standard pour Games/Runtime,
# objectif de s0-contrat pour Charters, objectif de s5-wiremap pour Wiremaps,
# objectif de s2-worldscan pour World Scan). Jamais une supposition.
_PRODUCER_EDGES: dict[str, tuple[str, ...]] = {
    "artefact:Charters": ("agent:contract_author",),
    "artefact:Wiremaps": ("agent:wiremap", "bloc:WireMap"),
    "artefact:World Scan": ("agent:worldscan", "bloc:World Scan"),
    "artefact:Games": ("agent:game_forger", "bloc:Builder"),
    "artefact:Runtime": ("agent:game_forger", "bloc:Builder"),
    "artefact:Lessons": ("bloc:Lessons",),
    "bloc:retour KB": ("bloc:Lessons", "artefact:Knowledge"),
}

_SCAN_FIELDS: tuple[str, ...] = (
    "mandatory_read", "memoire", "objectif", "gardeFou", "in_scope", "out_of_scope",
)


def _field_texts(data: dict[str, Any], field: str) -> list[str]:
    value = data.get(field)
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        return [x for x in value if isinstance(x, str)]
    return []


def _scan_text(data: dict[str, Any]) -> str:
    parts: list[str] = []
    for field in _SCAN_FIELDS:
        parts.extend(_field_texts(data, field))
    return "\n".join(parts)


def _stem_blocks(stem: str) -> list[str]:
    return [label for label, stems in _BLOCK_ETAPES.items() if stem in stems]


def _build_graph(contracts: dict[str, dict[str, Any]]) -> dict[str, set[str]]:
    depend_de: dict[str, set[str]] = defaultdict(set)

    for stem, entry in contracts.items():
        data = entry["data"]
        role = data.get("capability_role")
        owners = [f"bloc:{label}" for label in _stem_blocks(stem)]
        if role:
            owners.append(f"agent:{role}")

        text = _scan_text(data)
        for marker, artefact_id in _CONSUMER_MARKERS:
            if marker in text:
                for owner in owners:
                    if owner != artefact_id:
                        depend_de[owner].add(artefact_id)

        for label in _stem_blocks(stem):
            if role:
                depend_de[f"bloc:{label}"].add(f"agent:{role}")

    for piece_id, producers in _PRODUCER_EDGES.items():
        depend_de[piece_id].update(producers)

    return depend_de


def _invert(depend_de: dict[str, set[str]]) -> dict[str, set[str]]:
    dependants: dict[str, set[str]] = defaultdict(set)
    for owner, deps in depend_de.items():
        for dep in deps:
            dependants[dep].add(owner)
    return dependants


# --------------------------------------------------------------------------- #
# Les 9 blocs du workflow — une fonction par bloc, chacune ancrée sur SA source
# la plus pertinente. Retourne {"pourquoi":.., "a_quoi_sert":.., "si_casse":..}
# (depend_de/dependants/liens_vues/nom_humain/id sont ajoutés par l'appelant,
# uniformément, à partir du graphe et des tables ci-dessus).
# --------------------------------------------------------------------------- #


def _piece_world_scan(contracts: dict[str, dict[str, Any]]) -> dict[str, Any]:
    entry = contracts.get("s2-worldscan")
    if not entry:
        return _rien("aucun contrat s2-worldscan.yaml lisible dans ce périmètre")
    data, path = entry["data"], entry["path"]
    return {
        "pourquoi": _r(
            "Observe des jeux comparables pour comprendre leur assemblage (systèmes, "
            "boucles, rétention) — une caméra d'architecte, jamais un scraper de texte. "
            "Reste advisory : n'impose aucune décision, ne biaise jamais le council.",
            _cite_field(path, "role"), data.get("role"),
        ),
        "a_quoi_sert": _r(
            "Sert à produire un dossier GAME_REFERENCE/ sur au moins 2 jeux comparables : "
            "mécaniques, progression, économie, flux UX, architecture supposée, avec des "
            "sources citées (URL + timestamp) et zéro média local téléchargé.",
            _cite_field(path, "objectif"), data.get("objectif"),
        ),
        "si_casse": _r(
            "Advisory-only par construction (garde-fou explicite du contrat) : si ce bloc "
            "casse ou n'a jamais tourné, aucune étape avale n'est bloquée mécaniquement — "
            "seules les pièces qui le citent en mandatory_read (ex. knowledge_packet.json) "
            "perdent un repère externe, jamais une précondition dure.",
            _cite_field(path, "gardeFou"), data.get("gardeFou"),
            derive_du_graphe=True,
        ),
    }


def _piece_knowledge_base(docs: dict[str, Optional[str]]) -> dict[str, Any]:
    kb = docs.get("kb_readme")
    if kb is None:
        return _rien("knowledge_base/README.md illisible ou absent dans ce périmètre")
    needle_gate = "elle existe **si le validateur l'accepte**"
    needle_tier = "prouvé en jeu"
    return {
        "pourquoi": _r(
            "Mémoire de production du studio : ingestion, classification et orchestration "
            "de composants open source, consommés par la Forge pour ASSEMBLER des jeux. "
            "Aucune entrée n'existe « parce qu'on l'a écrite » — elle existe si le "
            "validateur déterministe l'accepte.",
            _cite_doc(_KB_README_PATH, kb, needle_gate),
            "Aucune entrée n'existe « parce qu'on l'a écrite » : elle existe si le "
            "validateur l'accepte. Le validateur est déterministe, non-LLM, sans réseau.",
        ),
        "a_quoi_sert": _r(
            "Sert de bibliothèque réutilisable à deux tiers : `candidate` (admis, non "
            "prouvé en jeu) et `validated` (prouvé en jeu par un run-oracle vert qui "
            "l'importe réellement) — sans preuve d'usage, une entrée reste candidate ou "
            "est rejetée.",
            _cite_doc(_KB_README_PATH, kb, needle_tier),
            "validated | prouvé en jeu | proof_of_use = chemin d'un run-oracle vert d'un "
            "jeu qui l'importe/l'affiche réellement",
        ),
        "si_casse": _r(
            "Si le validateur (`kb-validate.mjs`) casse ou est contourné, le studio perd "
            "sa seule porte d'admission : n'importe quel composant pourrait entrer sans "
            "schéma, licence ni provenance vérifiés — la garantie que consomme le Builder "
            "(SEARCH obligatoire avant d'écrire une pièce réutilisable) devient vide.",
            _cite_doc(_KB_README_PATH, kb, "Le validateur est la porte"),
            "Le validateur est la porte. node knowledge_base/kb-validate.mjs "
            "knowledge_base/catalog.json — exit 0 = conforme",
            derive_du_graphe=True,
        ),
    }


def _piece_architect(contracts: dict[str, dict[str, Any]]) -> dict[str, Any]:
    entry = contracts.get("s4-archi")
    if not entry:
        return _rien("aucun contrat s4-archi.yaml lisible dans ce périmètre")
    data, path = entry["data"], entry["path"]
    wm_entry = contracts.get("s5-wiremap")
    if wm_entry:
        si_casse = _r(
            "Le WireMap (étape suivante) ne peut pas commencer sans blueprint valide : la "
            "wiremap est isomorphe au blueprint (section = module = dossier). Un blueprint "
            "manquant ou cyclique bloque toute la carte en aval avant qu'elle n'existe.",
            _cite_field(wm_entry["path"], "objectif"), wm_entry["data"].get("objectif"),
            derive_du_graphe=True,
        )
    else:
        si_casse = _r(
            NOT_OBSERVABLE,
            why="aucun contrat s5-wiremap.yaml lisible pour confirmer la dépendance aval",
        )
    return {
        "pourquoi": _r(
            "Découpe le jeu en modules par responsabilité, pas par confort, et fixe le "
            "graphe de dépendances autorisées/interdites avant que quiconque n'écrive du "
            "code — la structure physique du code est une CONSÉQUENCE du blueprint, jamais "
            "un réflexe « au feeling ».",
            _cite_field(path, "gardeFou"), data.get("gardeFou"),
        ),
        "a_quoi_sert": _r(
            "Sert à produire blueprint.yaml : modules et responsabilités, dépendances "
            "autorisées/interdites, ownership par module, invariants d'architecture.",
            _cite_field(path, "objectif"), data.get("objectif"),
        ),
        "si_casse": si_casse,
    }


def _piece_wiremap(contracts: dict[str, dict[str, Any]]) -> dict[str, Any]:
    # s5-wiremap est le contrat GÉNÉRIQUE du schéma standard ; wm1-wiremap-breakout est
    # la mission ad hoc du projet observé. On préfère s5-wiremap comme source canonique
    # (schéma stable), s'il existe — sinon on retombe sur la mission ad hoc réellement lue.
    entry = contracts.get("s5-wiremap") or contracts.get("wm1-wiremap-breakout")
    if not entry:
        return _rien("aucun contrat de wiremap (s5-wiremap.yaml / wm1-wiremap-breakout.yaml) "
                     "lisible dans ce périmètre")
    data, path = entry["data"], entry["path"]
    schema_ref = contracts.get("s5-wiremap") is not None
    return {
        "pourquoi": _r(
            "La wiremap est une CARTE À REMPLIR pour le Builder : chaque exigence reçoit "
            "une adresse, un état attendu, une preuve attendue. Le Builder n'a pas le "
            "droit d'ajouter quoi que ce soit hors de cette carte.",
            _cite_field(path, "role"), data.get("role"),
        ),
        "a_quoi_sert": _r(
            "Sert à produire la wiremap isomorphe au blueprint (ou au charter quand aucun "
            "blueprint n'existe) : section = module = dossier, chaque feature mappée à ses "
            "fichiers/fonctions avec une preuve attendue falsifiable et un statut.",
            _cite_field(path, "objectif"), data.get("objectif"),
        ),
        "si_casse": _r(
            "`mandatory_read` est une précondition DURE (pas un simple repère advisory, "
            "cf. SCHEMA.md) : le Builder cite la wiremap gelée dans son mandatory_read, "
            "donc une wiremap absente ou corrompue empêche le Builder de démarrer, elle ne "
            "se contourne pas.",
            {"path": _SCHEMA_PATH},
            "mandatory_read *bloque* (fichiers qui doivent être ouverts avant d'agir — "
            "précondition dure)" if schema_ref else None,
            derive_du_graphe=True,
        ),
    }


def _piece_builder(contracts: dict[str, dict[str, Any]]) -> dict[str, Any]:
    entry = contracts.get("s9-build-godot-standard") or contracts.get("s9-build-standard") \
        or contracts.get("s9-build")
    if not entry:
        return _rien("aucun contrat de builder standard lisible dans ce périmètre")
    data, path = entry["data"], entry["path"]
    return {
        "pourquoi": _r(
            "Remplit une carte DÉJÀ arrêtée, il ne conçoit pas. La discipline de périmètre "
            "prime sur l'initiative : ne discute pas le squelette, ne l'améliore pas de sa "
            "propre initiative — il l'exécute et remonte ce qui bloque.",
            _cite_field(path, "role"), data.get("role"),
        ),
        "a_quoi_sert": _r(
            "Sert à produire, pour CHAQUE ligne du squelette gelé, le code à l'adresse "
            "qu'elle déclare, jusqu'à ce que sa preuve attendue soit satisfaite par un "
            "oracle réellement exécuté — chaque ligne passe de REQUIRED à IMPLEMENTED (ou "
            "BLOCKED, motivé).",
            _cite_field(path, "objectif"), data.get("objectif"),
        ),
        "si_casse": _r(
            "Le harnais de test porte une garde anti-faux-vert (EXPECTED_ASSERTS) : sans "
            "elle, un cœur qui ne compile pas produirait un vert silencieux — c'est le "
            "contrat lui-même qui nomme ce risque de casse. En aval, les oracles (10a/10s), "
            "le red-team (11) et le verdict (12) n'ont plus rien à vérifier si le Builder "
            "ne produit rien : ils dépendent tous de son code.",
            _cite_field(path, "gardeFou"), data.get("gardeFou"),
        ),
    }


def _piece_runtime(contracts: dict[str, dict[str, Any]]) -> dict[str, Any]:
    entry = contracts.get("s9-build-godot-standard") or contracts.get("s9-build-standard")
    if not entry:
        return _rien("aucun contrat de builder standard lisible pour ancrer la doctrine "
                     "de séparation logique/présentation")
    data, path = entry["data"], entry["path"]
    return {
        "pourquoi": _r(
            "N'est pas de la logique de jeu : c'est la couche de présentation (scène, "
            "nœuds, Input, rendu) qui DÉPEND de la logique pure, jamais l'inverse — "
            "dépendances à sens unique, imposées par le contrat du Builder.",
            _cite_field(path, "gardeFou"), data.get("gardeFou"),
        ),
        "a_quoi_sert": _r(
            "Sert à héberger tout ce qui affiche, sonne, lit l'input ou quitte le jeu — "
            "les adaptateurs de présentation — pendant que la logique pure (règles, état, "
            "collisions) reste ailleurs, testable en headless sans fenêtre GPU.",
            _cite_field(path, "permissions"), data.get("permissions"),
        ),
        "si_casse": _r(
            "Si la séparation casse (logique pure qui connaît une scène ou un nœud), "
            "l'oracle headless devient impossible à faire tourner sans fenêtre GPU réelle, "
            "et la garde de déterminisme (aucune source d'aléa non seedée) devient invérifiable.",
            _cite_field(path, "gardeFou"), data.get("gardeFou"),
            derive_du_graphe=True,
        ),
    }


def _piece_observer() -> dict[str, Any]:
    # Auto-référence assumée : la doctrine d'Observer vit sous docs/observer/, qui n'est
    # PAS dans les racines lisibles d'ObserverContext (voir sources.py ALLOWED_ROOTS —
    # docs/ n'y figure que pour deux fichiers .html précis, ni l'un ni l'autre du domaine
    # Observer). Vérifié : ni STUDIO_MASTER_SCHEMA.html ni FORGE_V2_PILOTAGE.html ne
    # mentionnent "Observer" ou "cockpit" (grep fait au moment d'écrire ce module).
    # Honnêteté avant tout : NOT_OBSERVABLE plutôt qu'une prose non ancrée.
    return _rien(
        "aucune doctrine lisible ne documente cette pièce : sa propre documentation vit "
        "sous docs/observer/, hors des racines lisibles d'ObserverContext (cécité "
        "structurelle, cf. sources.py) ; STUDIO_MASTER_SCHEMA.html et FORGE_V2_PILOTAGE.html "
        "— les deux seuls fichiers docs/ lisibles ici — ne mentionnent ni « Observer » ni "
        "« cockpit »"
    )


def _piece_lessons(docs: dict[str, Optional[str]]) -> dict[str, Any]:
    pilotage = docs.get("pilotage")
    if pilotage is None:
        return _rien("docs/forge/FORGE_V2_PILOTAGE.html illisible ou absent dans ce périmètre")
    needle_partiel = "leçon revient au prochain run"
    needle_absent = "lessons.jsonl n'existe pas : seules 3 leçons legacy de fallback circulent"
    return {
        "pourquoi": _r(
            "Le pré-mortem d'un run injecte réellement des leçons passées dans le prompt "
            "d'un agent — c'est le mécanisme qui devrait éviter de refaire deux fois la "
            "même erreur d'un run au suivant.",
            _cite_doc(_PILOTAGE_PATH, pilotage, needle_partiel),
            "[M] partiel — la leçon revient au prochain run · _premortem() injecte "
            "réellement",
        ),
        "a_quoi_sert": _r(
            "Sert à accumuler, ligne par ligne dans lab/reports/lessons.jsonl, les leçons "
            "candidates puis validées d'un run — matière première du pré-mortem du run "
            "suivant et, en principe, de la Knowledge Base (voir retour KB).",
            {"path": _LESSONS_PATH},
            None,
        ),
        "si_casse": _r(
            "État mesuré, pas une hypothèse : lessons.jsonl n'existait pas au moment de "
            "cette doctrine — seules 3 leçons legacy de fallback circulaient, plus le "
            "journal de playtest lu par les runs jeu. Le pré-mortem tourne quand même, mais "
            "sur un stock appauvri.",
            _cite_doc(_PILOTAGE_PATH, pilotage, needle_absent),
            "lessons.jsonl n'existe pas : seules 3 leçons legacy de fallback circulent + "
            "journal playtest lu par les runs jeu (P2)",
        ),
    }


def _piece_retour_kb(ctx: Any, result: dict[str, Any], docs: dict[str, Optional[str]]) -> dict[str, Any]:
    pilotage = docs.get("pilotage")
    if pilotage is None:
        return _rien("docs/forge/FORGE_V2_PILOTAGE.html illisible ou absent dans ce périmètre")
    needle_zero_ref = "zéro référence à knowledge_base"
    needle_lecture = "0 correspondance sur 5 recherches"

    # Fait mesuré EN PLUS de la doctrine (pas à la place) : combien de leçons validées sont
    # rattachées au projet observé, et si catalog.json le mentionne — même mécanique que
    # command.view_docloop / system_artefacts « retour KB », recalculée ici pour porter sa
    # propre citation sans dépendre de result["views"] (pas garanti disponible pour tout
    # appelant de build_pedagogy).
    project = result.get("project") or ctx.project
    run_ids = {r.get("run_id") for r in result.get("runs", [])}
    validees = 0
    for _lineno, obj in ctx.read_jsonl(ctx.repo_root / "lab" / "reports" / "lessons.jsonl"):
        supporting = obj.get("supporting_runs") or []
        if obj.get("status") == "validated" and any(r in run_ids for r in supporting):
            validees += 1
    catalog_text = ctx.read_text(ctx.repo_root / "knowledge_base" / "catalog.json")
    mentionne = bool(catalog_text and project and str(project).lower() in catalog_text.lower())

    return {
        "pourquoi": _r(
            "Censé fermer la boucle : ce que la Forge apprend sur un jeu devrait revenir "
            "nourrir la Knowledge Base pour le jeu suivant — sinon chaque jeu repart de "
            "zéro sur des erreurs déjà commises ailleurs.",
            _cite_doc(_PILOTAGE_PATH, pilotage, "La KB n'est pas un bloc extérieur"),
            "La KB n'est pas un bloc extérieur à la boucle : les jeux devraient l'alimenter "
            "ET la consommer.",
        ),
        "a_quoi_sert": _r(
            "Sert, en principe, à faire passer une leçon `validated` de lessons.jsonl vers "
            "une entrée réutilisable de knowledge_base/catalog.json — propose-only, "
            "ratification Pierre, jamais une écriture automatique.",
            {"path": _LESSONS_PATH},
            None,
        ),
        "si_casse": _r(
            f"CASSÉ, PROUVÉ, pas supposé : « zéro référence à knowledge_base dans "
            f"learning_memory.py » (sens « alimenter » inexistant) et 0 correspondance sur "
            f"5 recherches côté consommation. Conséquence directe : les leçons ne nourrissent "
            f"pas les jeux suivants, la bibliothèque n'apprend pas de l'expérience de jeu. "
            f"Mesuré sur ce run : {validees} leçon(s) validée(s) rattachée(s) au projet "
            f"« {project} », catalog.json {'mentionne' if mentionne else 'ne mentionne PAS'} "
            f"ce projet.",
            _cite_doc(_PILOTAGE_PATH, pilotage, needle_zero_ref),
            "zéro référence à knowledge_base dans learning_memory.py",
        ),
    }


_BLOCK_BUILDERS = {
    "World Scan": lambda contracts, docs, ctx, result: _piece_world_scan(contracts),
    "Knowledge Base": lambda contracts, docs, ctx, result: _piece_knowledge_base(docs),
    "Architect": lambda contracts, docs, ctx, result: _piece_architect(contracts),
    "WireMap": lambda contracts, docs, ctx, result: _piece_wiremap(contracts),
    "Builder": lambda contracts, docs, ctx, result: _piece_builder(contracts),
    "Runtime": lambda contracts, docs, ctx, result: _piece_runtime(contracts),
    "Observer": lambda contracts, docs, ctx, result: _piece_observer(),
    "Lessons": lambda contracts, docs, ctx, result: _piece_lessons(docs),
    "retour KB": lambda contracts, docs, ctx, result: _piece_retour_kb(ctx, result, docs),
}


# --------------------------------------------------------------------------- #
# Rôles d'agent — une table de reformulations courtes par capability_role,
# ancrée dynamiquement sur le premier contrat (ordre alphabétique de stem, pour
# un choix reproductible) qui déclare ce rôle.
# --------------------------------------------------------------------------- #

_ROLE_POURQUOI: dict[str, str] = {
    "contract_author": (
        "Rédige le charter du jeu — le document qui doit fermer tous les points « à "
        "définir » avant que quiconque commence à concevoir. Sans lui, rien n'a de cadre."
    ),
    "run_orchestrator": (
        "Conduit UN run Forge de bout en bout sans jamais fabriquer lui-même le livrable. "
        "Son rôle est la retenue : lancer la chaîne, la laisser boucler, puis vérifier."
    ),
    "prisme": (
        "Décrit le produit fini tel que le joueur le vivra — ce qu'il voit, fait, ressent — "
        "en Règles observables testables, avant que quiconque ne code quoi que ce soit."
    ),
    "worldscan": (
        "Observe des jeux comparables pour comprendre leur assemblage. Purement advisory : "
        "il ne décide jamais, il éclaire."
    ),
    "decompose": (
        "Énumère l'arbre Système→Feature→capacité du jeu, chaque feuille reliée à une "
        "preuve attendue, avant que l'Architecte ne découpe le code."
    ),
    "architect": (
        "Découpe le jeu en modules et fixe le graphe de dépendances autorisées/interdites "
        "— la structure physique du code est une conséquence de son blueprint."
    ),
    "art_director": (
        "Fixe l'identité visuelle du jeu et la traduit en demandes d'assets structurées et "
        "vérifiables, jamais un simple générateur d'adjectifs esthétiques."
    ),
    "wiremap": (
        "Transforme le blueprint en carte exécutable ligne par ligne : chaque exigence "
        "reçoit une adresse, une preuve attendue, un état. Le Builder n'a plus le droit "
        "d'improviser au-delà."
    ),
    "game_forger": (
        "Remplit la carte déjà arrêtée par le Cartographe — il ne conçoit rien, il exécute "
        "avec une discipline de périmètre supérieure à l'initiative. Godot-first."
    ),
    "builder": (
        "Produit le code borné à un ownership précis, WireMap tenue à jour, en réutilisant "
        "d'abord ce que la Knowledge Base propose avant d'écrire quoi que ce soit de neuf."
    ),
    "deterministic": (
        "Prouve mécaniquement, jamais de jugement : exécute un oracle non-LLM et rend "
        "PASS/FAIL déterministe et reproductible."
    ),
    "redteam_reviewer": (
        "Attaque le PLAN (archi + wiremap) avant que le code n'existe, pour trouver où il "
        "casserait — critique les décisions, jamais un substitut aux oracles techniques."
    ),
    "redteam_code": (
        "Audite le code déjà écrit à contexte vierge, sans voir les justifications du "
        "Builder, pour ne pas se laisser convaincre par son raisonnement."
    ),
    "forge_toolsmith": (
        "Rédige des propositions ratifiables sur l'outillage de la Forge elle-même — "
        "jamais un artefact vivant modifié directement, toujours une proposition en "
        "attente de ratification."
    ),
}

_ROLE_A_QUOI_SERT: dict[str, str] = {
    "contract_author": (
        "Sert à produire charter.yaml sans aucun champ « à définir » : objectif, "
        "hors-scope, critères de succès, actions interdites, plateforme cible, critères "
        "de démo."
    ),
    "run_orchestrator": (
        "Sert à choisir le profil, lancer la chaîne d'étapes, la laisser tourner seule, "
        "puis vérifier et restituer le résultat — jamais à corriger le livrable lui-même."
    ),
    "prisme": (
        "Sert à produire product_snapshot.md : ce que le joueur voit / fait / ressent, "
        "plus les Règles observables — 4 sections obligatoires, aucun flou toléré."
    ),
    "worldscan": (
        "Sert à produire un dossier GAME_REFERENCE/ sur au moins 2 jeux comparables, "
        "sources citées, zéro média local téléchargé."
    ),
    "decompose": (
        "Sert à produire l'arbre Système→Feature→capacité que l'Architecte découpera "
        "ensuite en modules."
    ),
    "architect": (
        "Sert à produire blueprint.yaml : modules, dépendances autorisées/interdites, "
        "ownership, invariants d'architecture."
    ),
    "art_director": (
        "Sert à produire art_bible.md et asset_requests.json (Asset Contract V0.1) en "
        "suivant une procédure imposée, dans l'ordre."
    ),
    "wiremap": (
        "Sert à produire la wiremap isomorphe au blueprint : section = module = dossier, "
        "chaque feature mappée à ses fichiers/fonctions avec preuve attendue."
    ),
    "game_forger": (
        "Sert à faire passer chaque ligne du squelette gelé de REQUIRED à IMPLEMENTED (ou "
        "BLOCKED motivé), avec les champs de constat de la wiremap remplis avec ce qui a "
        "été réellement déposé."
    ),
    "builder": (
        "Sert à produire du code borné à l'ownership déclaré, avec micro-commits et "
        "WireMap tenue à jour au fil de l'eau."
    ),
    "deterministic": (
        "Sert à émettre PASS/FAIL déterministe et à signer les verdicts — sans lui, "
        "aucune affirmation de la Forge n'est vérifiable mécaniquement."
    ),
    "redteam_reviewer": (
        "Sert à produire un rapport d'attaque sur l'archi et la wiremap, avec des "
        "artefacts ajustés en retour — une ré-entrée de boucle avant que le code n'existe."
    ),
    "redteam_code": (
        "Sert à produire un rapport de failles indépendant sur le code déjà écrit, chaque "
        "faille accompagnée d'une reproduction exécutable par un oracle en aval."
    ),
    "forge_toolsmith": (
        "Sert à documenter, auditer ou proposer des correctifs sur l'outillage Forge "
        "(garde-fous, branchements, mutation, findings red-team) — jamais à les appliquer "
        "directement."
    ),
}


def _piece_role(role: str, contracts: dict[str, dict[str, Any]],
                 dependants_of) -> dict[str, Any]:
    stems = sorted(stem for stem, entry in contracts.items()
                    if entry["data"].get("capability_role") == role)
    if not stems:
        return _rien(f"aucun contrat lisible ne déclare capability_role={role!r}")
    primary = stems[0]
    data, path = contracts[primary]["data"], contracts[primary]["path"]
    role_text = data.get("role")
    objectif_text = data.get("objectif")

    piece_id = f"agent:{role}"
    dependants = sorted(dependants_of.get(piece_id, set()))
    blocs_touches = sorted(d for d in dependants if d.startswith("bloc:"))

    if blocs_touches:
        si_casse_v = (
            f"Si roles.yaml ne résout plus ce rôle (RoleUnresolved), aucun des "
            f"{len(stems)} contrat(s) qui le déclarent ne peut être dispatché — le contrat "
            f"n'est plus activable (SCHEMA.md, « Résolution du runtime »). Dans le pipeline "
            f"standard des 9 blocs, cela arrête directement : {', '.join(blocs_touches)}."
        )
    else:
        si_casse_v = (
            f"Si roles.yaml ne résout plus ce rôle (RoleUnresolved), aucun des "
            f"{len(stems)} contrat(s) qui le déclarent ({', '.join(stems)}) ne peut être "
            f"dispatché (SCHEMA.md, « Résolution du runtime »). Aucun de ces contrats ne "
            f"fait partie des 9 blocs du pipeline standard — l'impact reste circonscrit "
            f"aux missions qui le citent nommément."
        )

    return {
        "pourquoi": _r(
            _ROLE_POURQUOI.get(role, NOT_OBSERVABLE),
            _cite_field(path, "role"), role_text,
            why=None if role in _ROLE_POURQUOI else "aucune reformulation curatée pour ce rôle",
        ),
        "a_quoi_sert": _r(
            _ROLE_A_QUOI_SERT.get(role, NOT_OBSERVABLE),
            _cite_field(path, "objectif"), objectif_text,
            why=None if role in _ROLE_A_QUOI_SERT else "aucune reformulation curatée pour ce rôle",
        ),
        "si_casse": _r(
            si_casse_v, {"path": _SCHEMA_PATH},
            "Un rôle non résolu ⇒ RoleUnresolved (sous-classe de ContractIncomplete) ⇒ "
            "contrat non activable.",
            derive_du_graphe=True,
        ),
    }


# --------------------------------------------------------------------------- #
# Catégories d'artefacts — sources hétérogènes par catégorie ; NOT_OBSERVABLE
# honnête pour Skills et Reports (aucune doctrine lisible retrouvée).
# --------------------------------------------------------------------------- #


def _piece_category(label: str, contracts: dict[str, dict[str, Any]],
                     docs: dict[str, Optional[str]]) -> dict[str, Any]:
    if label == "Charters":
        entry = contracts.get("s0-contrat")
        if not entry:
            return _rien("aucun contrat s0-contrat.yaml lisible dans ce périmètre")
        data, path = entry["data"], entry["path"]
        return {
            "pourquoi": _r(
                "Le charter est le seul document que toutes les étapes du pipeline "
                "peuvent citer comme source amont légitime — sans lui, une ligne de "
                "wiremap n'a nulle part où ancrer sa provenance.",
                _cite_field(path, "role"), data.get("role"),
            ),
            "a_quoi_sert": _r(
                "Sert de référence pour l'objectif, le périmètre, les critères de succès "
                "et de démo, les actions interdites et les paramètres de design — cité en "
                "mandatory_read par la quasi-totalité des étapes avales.",
                _cite_field(path, "objectif"), data.get("objectif"),
            ),
            "si_casse": _r(
                "Un charter avec un champ « à définir » restant est un échec du contrat "
                "lui-même (success_criteria l'exige explicitement) — toute étape avale qui "
                "le cite en mandatory_read hérite du flou au lieu d'une frontière ferme.",
                _cite_field(path, "success_criteria"), data.get("success_criteria"),
                derive_du_graphe=True,
            ),
        }

    if label == "Wiremaps":
        return _piece_wiremap(contracts)

    if label == "World Scan":
        return _piece_world_scan(contracts)

    if label == "Knowledge":
        return _piece_knowledge_base(docs)

    if label == "Skills":
        return _rien(
            "aucune racine lisible n'est déclarée pour .claude/skills/ dans le périmètre "
            "de lecture d'ObserverContext, et aucun contrat ni document de doctrine "
            "accessible ici ne documente cette catégorie"
        )

    if label == "Contracts":
        schema = docs.get("schema")
        if schema is None:
            return _rien("scripts/forge/contracts/SCHEMA.md illisible ou absent")
        needle = "est le contrat de travail d'un"
        return {
            "pourquoi": _r(
                "Un agent ne se lance jamais sans contrat complet. Le contrat, au dispatch, "
                "est traduit en cadre borné (system prompt + modèle forcé + permissions + "
                "oracle de sortie) — c'est ce qui donne anti-drift, ciblage de capacité et "
                "garde-fou.",
                _cite_doc(_SCHEMA_PATH, schema, needle),
                "Une planète (nœud agent llm-lego + ses satellites) est le contrat de "
                "travail d'un sous-agent. Un agent ne se lance jamais sans contrat complet.",
            ),
            "a_quoi_sert": _r(
                "Sert de porte unique : tout appel de sous-agent Forge passe par une "
                "fonction dispatch(étape) qui vérifie le contrat AVANT de fabriquer un "
                "prompt — un Critique vide ou absent lève CONTRACT_INCOMPLETE et arrête "
                "tout.",
                _cite_doc(_SCHEMA_PATH, schema, "Vérifie le contrat"),
                "Vérifie le contrat. Un Critique vide/absent, ou un optionnel non "
                "déclaré → lève CONTRACT_INCOMPLETE et s'arrête. Aucun agent ne démarre.",
            ),
            "si_casse": _r(
                "Pas de contrat valide → pas de prompt → pas d'agent. C'est mécanique, pas "
                "déclaratif : si un contrat perd un champ critique, l'agent correspondant "
                "n'est simplement plus activable, quelle que soit l'intention de l'orchestrateur.",
                _cite_doc(_SCHEMA_PATH, schema, "pas de prompt"),
                "on ne peut pas obtenir le prompt sans passer par la porte, et la porte ne "
                "fabrique pas de prompt si le contrat est incomplet.",
            ),
        }

    if label == "Lessons":
        return _piece_lessons(docs)

    if label == "Reports":
        return _rien(
            "aucun contrat ne cite lab/reports/error_journal/ ni <run_dir>/artifacts/ dans "
            "mandatory_read, memoire, objectif ou gardeFou — catégorie présente dans "
            "l'arbre s5_artefacts mais sans doctrine associée retrouvée dans ce périmètre"
        )

    if label == "Games":
        entry = contracts.get("s9-build-godot-standard") or contracts.get("s9-build-standard")
        if not entry:
            return _rien("aucun contrat de builder standard lisible dans ce périmètre")
        data, path = entry["data"], entry["path"]
        return {
            "pourquoi": _r(
                "C'est le livrable final visible du pipeline : le dépôt du jeu lui-même. "
                "Rien n'existe sous games/<jeu>/ avant que le Builder ne l'écrive.",
                _cite_field(path, "output_contract"), data.get("output_contract"),
            ),
            "a_quoi_sert": _r(
                "Sert à héberger l'arborescence conforme aux adresses de la wiremap "
                "(project.godot, scènes, logique pure, adaptateurs, tests avec "
                "EXPECTED_ASSERTS) — ce que les oracles avals (10a/10s) et le red-team "
                "(11) inspectent ensuite.",
                _cite_field(path, "output_contract"), data.get("output_contract"),
            ),
            "si_casse": _r(
                "Sans arborescence conforme, aucun oracle headless ne peut même démarrer "
                "(il cible res://tests/run_tests.gd) — le pipeline s'arrête net au Builder, "
                "rien n'atteint le red-team ni le verdict.",
                _cite_field(path, "success_criteria"), data.get("success_criteria"),
                derive_du_graphe=True,
            ),
        }

    if label == "Runtime":
        return _piece_runtime(contracts)

    return _rien(f"catégorie « {label} » non reconnue par ce module")


# --------------------------------------------------------------------------- #
# build_pedagogy — assemblage des 3 familles de cartes
# --------------------------------------------------------------------------- #


def build_pedagogy(ctx: Any, result: dict[str, Any], events: list[dict[str, Any]]) -> dict[str, Any]:
    del events  # aucune carte pédagogique n'a besoin des événements bruts à ce jour ;
    # conservé dans la signature pour respecter l'interface imposée et pour un futur
    # enrichissement (ex. « dernière activation » par pièce, déjà porté par s3_agents).

    contracts = _load_all_contracts(ctx)
    docs = _read_docs(ctx)
    depend_de = _build_graph(contracts)
    dependants = _invert(depend_de)

    roles_present = sorted({
        entry["data"].get("capability_role")
        for entry in contracts.values()
        if entry["data"].get("capability_role")
    })

    pieces: dict[str, Any] = {}

    for label in _BLOCK_LABELS:
        piece_id = f"bloc:{label}"
        content = _BLOCK_BUILDERS[label](contracts, docs, ctx, result)
        pieces[piece_id] = {
            "id": piece_id,
            "nom_humain": label,
            "categorie": "bloc",
            **content,
            "depend_de": sorted(depend_de.get(piece_id, set())),
            "dependants": sorted(dependants.get(piece_id, set())),
            "liens_vues": ["s1_workflow", "s7_flow"],
        }

    for role in roles_present:
        piece_id = f"agent:{role}"
        content = _piece_role(role, contracts, dependants)
        pieces[piece_id] = {
            "id": piece_id,
            "nom_humain": _ROLE_HUMAN_NAMES.get(role, role),
            "categorie": "agent",
            **content,
            "depend_de": sorted(depend_de.get(piece_id, set())),
            "dependants": sorted(dependants.get(piece_id, set())),
            "liens_vues": ["s3_agents", "s4_prompt", "s6_injection"],
        }

    for label in _ARTEFACT_CATEGORIES:
        piece_id = f"artefact:{label}"
        content = _piece_category(label, contracts, docs)
        pieces[piece_id] = {
            "id": piece_id,
            "nom_humain": label,
            "categorie": "artefact",
            **content,
            "depend_de": sorted(depend_de.get(piece_id, set())),
            "dependants": sorted(dependants.get(piece_id, set())),
            "liens_vues": ["s5_artefacts"],
        }

    n_not_observable = sum(
        1 for p in pieces.values() if p["pourquoi"]["v"] == NOT_OBSERVABLE
    )
    return {
        "pieces": pieces,
        "resume": (
            f"{len(pieces)} pièce(s) documentée(s) ({len(_BLOCK_LABELS)} blocs, "
            f"{len(roles_present)} rôle(s) d'agent, {len(_ARTEFACT_CATEGORIES)} "
            f"catégorie(s) d'artefact). {n_not_observable} pièce(s) sans doctrine "
            f"trouvée (NOT_OBSERVABLE honnête)."
        ),
        "regle": "chaque rubrique porte soit une reformulation ancrée sur base_textuelle+src, "
                 "soit NOT_OBSERVABLE+why — jamais de prose sans ancrage. depend_de/dependants "
                 "sont dérivés mécaniquement d'un graphe (marqueurs de mandatory_read/memoire/"
                 "objectif/gardeFou + structure du pipeline standard + arêtes producteur citées), "
                 "jamais rédigés.",
    }


# --------------------------------------------------------------------------- #
# view_accueil — la pièce 🏠, recomposée depuis views_partial (aucun recalcul)
# --------------------------------------------------------------------------- #


def _real_ecarts(ecart: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """`command.view_humangate` rend soit une liste d'écarts réels ({projet,...}), soit
    un unique repli {"constat": ...} quand decision-log.md est illisible. On ne compte
    que les vrais écarts, jamais le repli lui-même comme s'il en était un."""
    return [e for e in ecart if "projet" in e]


def view_accueil(ctx: Any, result: dict[str, Any], events: list[dict[str, Any]],
                  views_partial: dict[str, Any]) -> dict[str, Any]:
    del ctx, events  # cette vue ne fait que recomposer views_partial, déjà construit

    bandeau = views_partial.get("c0_bandeau") or {}
    humangate = views_partial.get("c4_humangate") or {}
    workflow = views_partial.get("s1_workflow") or {}
    planning = views_partial.get("s8_planning") or {}
    drift = views_partial.get("c2_drift") or {}

    blocs = workflow.get("blocs") or []
    n_actifs = sum(1 for b in blocs if b.get("etat") == "ACTIF")
    n_not_observable = sum(1 for b in blocs if b.get("etat") == NOT_OBSERVABLE)
    blocs_casses = [b.get("bloc") for b in blocs if b.get("etat") == NOT_OBSERVABLE]

    if blocs:
        ou_en_est = _r(
            {
                "resume": workflow.get("resume", NOT_OBSERVABLE),
                "blocs_actifs": n_actifs,
                "blocs_total": len(blocs),
                "blocs_not_observable": n_not_observable,
            },
        )
    else:
        ou_en_est = _r(NOT_OBSERVABLE, why="s1_workflow absente ou vide de views_partial")
    ou_en_est["lien"] = "s1_workflow"

    jeux = ((planning.get("jeux_en_cours") or {}).get("cartes")) or []
    runs_bloques = [c.get("projet") for c in jeux if c.get("etat_lisible") == "BLOQUÉ"]
    drift_high_lignes = [l for l in (drift.get("lignes") or []) if l.get("gravite") == "high"]

    ce_qui_bloque = _r({
        "runs_bloques": runs_bloques,
        "drift_high_count": len(drift_high_lignes),
        "drift_high_ids": [l.get("drift_id") for l in drift_high_lignes],
        "blocs_not_observable": blocs_casses,
    })
    ce_qui_bloque["lien"] = ["s8_planning", "c2_drift", "s1_workflow"]

    en_attente = humangate.get("en_attente") or []
    ecarts = _real_ecarts(humangate.get("ecart") or [])
    chantiers = ((planning.get("backlog_derive") or {}).get("chantiers")) or []
    premiere_tache = chantiers[0] if chantiers else None
    registre = planning.get("registre") or {}
    registre_ratifie = isinstance(registre.get("v"), list) and bool(registre.get("v"))

    a_decider = _r({
        "humangate_en_attente": [
            {"run_id": (e.get("run_id") or {}).get("v"), "projet": (e.get("project") or {}).get("v")}
            for e in en_attente
        ],
        "ecart_registre_decisions": len(ecarts),
        "premiere_tache_backlog_derive": premiere_tache,
        "registre_planning_ratifie": registre_ratifie,
    })
    a_decider["note"] = (
        "registre de planning ratifié présent (studio_brain/planning/planning.yaml) — voir "
        "s8_planning.registre pour la liste complète"
        if registre_ratifie else
        "aucun registre de planning ratifié n'existe encore (studio_brain/planning/"
        "planning.yaml absent) : la première tâche listée ici est une PROPOSITION dérivée "
        "mécaniquement (drift + leçons validées), pas un ordre — la promotion vers le "
        "registre reste un geste Pierre"
    )
    a_decider["lien"] = ["c4_humangate", "s8_planning"]

    ce_qui_tourne = _r({
        "run_en_cours": bandeau.get("run_en_cours"),
        "dernier_verdict": bandeau.get("dernier_verdict"),
        "cout_recent": bandeau.get("cout_recent"),
        "fraicheur_analyse": result.get("observed_at", NOT_OBSERVABLE),
    })
    ce_qui_tourne["lien"] = "c0_bandeau"

    resume = (
        f"{n_actifs}/{len(blocs)} bloc(s) actif(s) dans le pipeline. "
        f"{len(runs_bloques)} jeu(x) bloqué(s), {len(drift_high_lignes)} drift high, "
        f"{len(en_attente)} décision(s) HumanGate en attente."
    )

    return {
        "question": "Que dois-je savoir ce matin ?",
        "resume": resume,
        "ou_en_est_la_forge": ou_en_est,
        "ce_qui_bloque": ce_qui_bloque,
        "a_decider_aujourdhui": a_decider,
        "ce_qui_tourne": ce_qui_tourne,
    }


def build_home_views(ctx: Any, result: dict[str, Any], events: list[dict[str, Any]],
                      views_partial: dict[str, Any]) -> dict[str, Any]:
    return {
        "s0_accueil": view_accueil(ctx, result, events, views_partial),
        "pedagogy": build_pedagogy(ctx, result, events),
    }


# --------------------------------------------------------------------------- #
# Preuve d'exécution
# --------------------------------------------------------------------------- #

if __name__ == "__main__":
    import json

    from observer.sources import ObserverContext, default_repo_root, default_transcripts_root  # noqa: E402

    logging.basicConfig(level=logging.WARNING)

    repo_root = default_repo_root()
    transcripts_root = default_transcripts_root(repo_root)
    project = "breakout_v2"
    ctx = ObserverContext.build(repo_root, project, transcripts_root)

    report_dir = repo_root / "lab" / "reports" / "observer" / project
    with (report_dir / "observer_run.json").open("r", encoding="utf-8-sig") as fh:
        d = json.load(fh)

    events: list[dict[str, Any]] = []
    with (report_dir / "events.jsonl").open("r", encoding="utf-8-sig") as fh:
        for line in fh:
            line = line.strip()
            if line:
                events.append(json.loads(line))

    pedagogy = build_pedagogy(ctx, d, events)
    accueil = view_accueil(ctx, d, events, d.get("views") or {})

    print(f"pieces produites : {len(pedagogy['pieces'])}")
    print(pedagogy["resume"])
    print()

    not_observable_ids = [
        pid for pid, p in pedagogy["pieces"].items() if p["pourquoi"]["v"] == NOT_OBSERVABLE
    ]
    print(f"pieces NOT_OBSERVABLE (faute de doctrine) : {len(not_observable_ids)}")
    for pid in not_observable_ids:
        print(f"  - {pid} : {pedagogy['pieces'][pid]['pourquoi'].get('why')}")
    print()

    for pid in ("bloc:Builder", "bloc:retour KB"):
        piece = pedagogy["pieces"].get(pid)
        print(f"--- {pid} ---")
        if not piece:
            print("  (absente du dict pieces)")
            continue
        print(f"  nom_humain : {piece['nom_humain']}")
        for rubrique in ("pourquoi", "a_quoi_sert", "si_casse"):
            cell = piece[rubrique]
            print(f"  {rubrique}:")
            print(f"    v   : {cell['v']}")
            if cell.get("src"):
                print(f"    src : {cell['src']}")
            if cell.get("base_textuelle"):
                print(f"    base_textuelle : {cell['base_textuelle']}")
            if cell.get("why"):
                print(f"    why : {cell['why']}")
        print(f"  depend_de  : {piece['depend_de']}")
        print(f"  dependants : {piece['dependants']}")
        print()

    print("--- s0_accueil ---")
    print(f"question : {accueil['question']}")
    print(f"resume   : {accueil['resume']}")
    print(f"ou_en_est_la_forge : {accueil['ou_en_est_la_forge']['v']}")
    print(f"ce_qui_bloque      : {accueil['ce_qui_bloque']['v']}")
    print(f"a_decider_aujourdhui : {accueil['a_decider_aujourdhui']['v']}")
    print(f"  note : {accueil['a_decider_aujourdhui']['note']}")
    print(f"ce_qui_tourne      : {accueil['ce_qui_tourne']['v']}")
