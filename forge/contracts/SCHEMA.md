# Contrat d'agent Forge — schéma canonique

> **Date** : 2026-07-09
> **Source** : session de conception `/forge` (Pierre + Claude Code), consolidée depuis
> `docs/superpowers/specs/2026-07-09-forge-autonomous-engineering-loop-design.md`
> et l'itération « planète = contrat de travail d'un agent ».
> **Statut** : DESIGN — schéma de référence. Le dispatcher qui l'applique est spécifié
> séparément (voir `/plan`).

---

## Principe

Une **planète** (nœud agent llm-lego + ses satellites) **est le contrat de travail d'un
sous-agent**. Un agent ne se lance **jamais** sans contrat complet. Au dispatch, le contrat
est traduit en cadre borné (system prompt + modèle forcé + permissions + oracle de sortie) :
c'est ce qui donne **anti-drift**, **ciblage de capacité** et **guardrail**.

Doctrine sœur déjà en place : `verdict.py` sépare `software_verdict` / `evidence_verdict` /
`claim_verdict` (`NO_CLAIM_ALLOWED`) ; `gate.py` bloque sur oracle rouge. Ce schéma ajoute
la **porte d'entrée** (contrat au dispatch) en miroir de la **porte de sortie** (verdict signé).

---

## Les 3 états d'un champ

Chaque champ a **trois** états possibles — jamais deux :

| État | Sens | Impératif (Critique) | Optionnel (Important/Recommandé) |
|---|---|---|---|
| **rempli** | contenu réel | ✅ | ✅ |
| **déclaré vide** (`aucun`) | décision assumée : ce champ ne s'applique pas | ❌ refus | ✅ |
| **absent** | non déclaré = oubli | ❌ refus | ❌ refus |

> La distinction clé : `skill: aucun` est une **décision** (l'agent n'a pas besoin de skill).
> Un champ *absent* est un **oubli** → refus. On ne peut pas « oublier » de penser un champ ;
> il faut au minimum écrire `aucun`. C'est l'anti-drift à la racine.

---

## Le schéma (16 champs · 10 catégories)

| # | Catégorie | Champ | Rôle | Niveau | Couche |
|---|---|---|---|---|---|
| 1 | Identité / posture cognitive | `role` | Point de vue imposé : reviewer senior, architecte, expert IA, CEO, backend, auditeur sécurité… (injecté dans le prompt) | **Critique** | `prompt` |
| 2a | Identité / posture cognitive | `capability_role` | **Clé de résolution runtime** — jamais un modèle en dur. Résolu par le registry local (ADR-002 gate 1) | **Critique** | `dispatch` |
| 2b | Identité / posture cognitive | `exigences_cognitives` | Exigences de raisonnement/effort/capacité attendues (lisible humain) | **Critique** | `prompt` |
| 3 | Contexte projet | `memoire` | Navigation projet, architecture, conventions, historique, sources de vérité (*advisory*) | **Critique** | `prompt` |
| 4 | Contexte projet | `mandatory_read` | Sources **obligatoires** à lire avant toute action (*précondition dure*) | **Critique** | `prompt` |
| 5 | Mission | `objectif` | But précis de l'intervention | **Critique** | `prompt` |
| 6 | Frontières | `in_scope` | Zone d'action autorisée | **Critique** | `prompt` |
| 7 | Frontières | `out_of_scope` | Limites explicites (≠ garde-fou : frontière de périmètre) | **Critique** | `prompt` |
| 8 | Autorisation | `permissions` | Droits techniques réels : read / write / run / create / delete + dossiers autorisés/interdits | **Critique** | `prompt` |
| 9 | Gouvernance | `gardeFou` | Règles, interdictions, contraintes d'architecture (≠ hors-scope : frontière comportementale) | **Critique** | `prompt` |
| 10 | Validation & auditabilité | `success_criteria` | Conditions **objectives** de réussite | **Critique** | `prompt` |
| 11 | Validation & auditabilité | `tests_oracles` | Tests, métriques, preuves, oracles/ancres non-LLM utilisés | **Critique** | `prompt` |
| 12 | Validation & auditabilité | `final_report` | Rapport structuré : preuves, claims, écarts, risques (voir Règle de restitution) | **Critique** | `prompt` |
| 13 | Restitution | `output_contract` | Structure obligatoire de la réponse/livrable | **Critique** | `prompt` |
| 14 | Capacités | `skill` | Compétences spécialisées | Important | `dispatch` |
| 15 | Capacités | `plugin` | Outils externes | Important | `dispatch` |
| 16 | Traçabilité | `parent_agent` / `delegation_context` | Pourquoi l'agent existe, qui l'a mandaté | Recommandé | `documentation` |

**Règle d'activation** : un champ **Critique** vide ou absent → **l'agent n'est pas activable**.
Un champ **Important**/**Recommandé** peut être `aucun` **mais jamais absent** — à l'exception de
`delegation_context`, dont la présence n'est plus exigée (voir amendement layer ci-dessous).

### Couche par champ — table complète (consommateur nommé)

Un champ peut être **valide** (rempli, au bon niveau) sans jamais **agir** sur quoi que ce soit :
la couche dit PAR QUEL CANAL le champ produit un effet, pour ne plus présenter un champ validé
comme une capacité injectée par défaut.

| Couche | Définition | Champs | Consommateur réel |
|---|---|---|---|
| `prompt` | Rendu comme section de texte dans le prompt de l'agent | `role`, `exigences_cognitives`, `memoire`, `mandatory_read`, `objectif`, `in_scope`, `out_of_scope`, `permissions`, `gardeFou`, `success_criteria`, `tests_oracles`, `output_contract`, `final_report` | `contract.py::_render_prompt` (une section par champ rempli) |
| `dispatch` | Consommé pour construire le payload de dispatch (modèle, provider, outils), **jamais** rendu comme texte | `capability_role`, `skill`, `plugin` | `capability_role` → `contract.py::resolve_runtime` (modèle/provider) ; `skill`/`plugin` → `contract.py::_declared_tools` → `payload.allowed_tools`. **Note honnête** : consommateur faible sur `skill`/`plugin` — la majorité des contrats les déclarent `aucun`, l'audit outillage signe alors `allowed_tools=()` ; sous-déclaration connue, à ne pas blanchir |
| `documentation` | Traçabilité humaine — pourquoi l'agent existe, qui l'a mandaté | `delegation_context`, `parent_agent` | **Aucun consommateur d'exécution.** Lu par un humain (ou par Observer, en lecture seule, pour affichage). `parent_agent` n'a de plus jamais été observé rempli dans un contrat réel — c'est un repli théorique de `observer.system_agents._delegation_value_and_field` |

### Amendement layer — ratifié Pierre 2026-08-02

> « Un champ sans consommateur déclaré ne doit pas être présenté comme une capacité injectée.
> `delegation_context` devient explicitement documentaire tant qu'aucun consommateur réel
> n'existe. Objectif : corriger la vérité du modèle, pas créer une nouvelle mécanique. »

Conséquences mécaniques de cet amendement (implémentées le même jour, mêmes fichiers) :

- `contract.py` : `delegation_context` sort de l'exigence de présence (n'est plus exigé "rempli
  ou `aucun`, jamais absent") — un champ **documentation** ne peut pas bloquer le dispatch. S'il
  est présent, il reste type-vérifié (`str`/liste), jamais silencieusement toléré malformé. En
  contrepartie, `contract.py` gagne une garde mécanique NEUVE sur la couche `prompt` : un champ
  `prompt` **rempli** dont le texte n'apparaît pas dans le prompt réellement rendu par
  `_render_prompt` lève `ContractIncomplete` — l'invariant « tout champ prompt rempli est
  rendu », qui existait par construction mais n'était vérifié par personne, est désormais vérifié.
- `system_agents.py` (Observer, lecture seule) : la matrice Declare/Injecte/Consomme/Prouve ne
  classe plus `skill`/`plugin`/`delegation_context` non retrouvés dans le texte du prompt comme
  `DECLARED_NOT_INJECTED` (le drift « contrat sans effet réel », réservé aux vrais champs
  `prompt` manquants) — ils reçoivent leur propre statut FERMÉ : `CONFORME_DISPATCH` pour
  `skill`/`plugin` (preuve = attestation dispatch, allowed_tools/audit) et
  `CONFORME_DOCUMENTAIRE` pour `delegation_context`/`parent_agent` (hors matrice d'exécution par
  construction). Aucun statut historique n'est supprimé.

### Amendement `verification` — ratifié Pierre 2026-09-02 (décision P3, sas 2)

> Un message opposé à une capacité (amendement, objection, question) n'est acquitté que si la
> capacité en a incorporé la référence **dans sa propre production**. Encore faut-il savoir
> **quel artefact fait foi** pour cette capacité — sinon la vérification cherche partout, et
> « trouver » ne prouve plus rien.

**Ce n'est pas un 18e champ du contrat d'entrée** — au même titre que `SKIPPED_VALIDATION[]`, il ne
s'ajoute ni à Critique, ni à Important, ni à Recommandé, et **ne touche pas** le compte des champs
ci-dessus. Mais il s'en distingue sur un point qui a décidé sa forme : `SKIPPED_VALIDATION` est une
exigence sur ce que l'agent **produit**, uniforme pour tous, donc injectable verbatim par
`RESTITUTION_RULE` sans éditer un seul YAML. `consumption_evidence` est **une déclaration de
l'auteur du contrat** — l'agent ne l'écrit jamais, la vérification la lit après coup, et **sa valeur
diffère par capacité** (`s2.5-artbible` produit `art_bible.md`, `asset_requests.json` et
`gm_worldscan.json` : lequel fait foi ?). Une règle uniforme ne peut pas porter une valeur qui varie.
Le chemin bon marché de 2026-07-26 est donc mécaniquement indisponible ici.

| Couche | Définition | Champs | Consommateur réel |
|---|---|---|---|
| `verification` | Lu par la vérification **après production**, jamais rendu à l'agent, jamais dans le payload | `consumption_evidence` | `contract.py::consumption_evidence_status` et `::consumption_evidence_adoption` (**ADVISORY**) |

Conséquences mécaniques (implémentées le même jour, mêmes fichiers) :

- `contract.py` : `VERIFICATION` et `LAYER_VERIFICATION`. Le champ est **OPTIONNEL** — hors des
  trois niveaux d'exigence, donc son absence ne peut rien bloquer (**0 contrat sur 28 le portait au
  jour de l'amendement** ; l'exiger les aurait tous invalidés d'un coup). Présent, il est
  type-vérifié — précédent `delegation_context` : une décision assumée n'a jamais le droit d'être
  malformée. Il est tenu **hors de `LAYER_PROMPT`** par construction, donc
  `_verify_prompt_layer_rendered` reste intact, **sans exception ajoutée**.
- **Le point de mesure arrive avec le champ**, pas après : `consumption_evidence_status(contract)`
  rend `filled` / `declared_empty` / `absent`, et `consumption_evidence_adoption()` balaie tout un
  répertoire de contrats. C'est la condition posée en 2026-07-26 — *« le corpus Codex est mort
  d'avoir été déclaratif sans lecteur »*.
- **ADVISORY, et seulement advisory** : aucun verdict lu ou modifié, aucun gate touché. Le passage
  en gate dur est une **décision Pierre distincte et ultérieure**, prise au vu des chiffres
  d'adoption — jamais déduite de l'existence du champ.

---

## Relations à ne pas confondre (le schéma n'est pas redondant)

- **`memoire` vs `mandatory_read`** : `memoire` *oriente* (carte des conventions, advisory) ;
  `mandatory_read` *bloque* (fichiers qui **doivent** être ouverts avant d'agir — précondition dure).
- **`out_of_scope` vs `gardeFou`** : `out_of_scope` = frontière de **périmètre** (« ne touche pas au shop ») ;
  `gardeFou` = frontière **comportementale** (« pas de `unwrap()` sans `// SAFETY:` »). Un agent peut
  respecter ses garde-fous et déborder le scope — d'où deux champs.
- **La chaîne de validation** (11→12→10→13, pipeline, pas doublon) :
  `success_criteria` (ce que « réussi » veut dire) → `tests_oracles` (avec quoi on le mesure) →
  `final_report` (ce qu'on a réellement trouvé) → `output_contract` (la forme imposée du livrable).

---

## RÈGLE DE RESTITUTION (invariant dur)

Tout `final_report` doit **citer l'oracle/l'ancre** qui appuie chaque affirmation.

- Affirmation appuyée par un **oracle non-LLM** (cargo test, pytest, import-linter, HMAC,
  ancre Lichess, oracle wiremap AST…) → `software_verdict` (OK/FAIL/BLOCKED) +
  `evidence_verdict: MECHANICAL_VALIDATION_ONLY` autorisés.
- Affirmation **sans oracle disponible** → l'agent **n'a pas le droit de claim**. Il émet à la
  place un **besoin HumanGate** : `claim_verdict: NO_CLAIM_ALLOWED` + `fog: <ce qui relève du
  jugement de Pierre>`.

> Effet : un sous-agent ne peut **jamais** livrer une affirmation auto-certifiée sans preuve
> mécanique. Soit il prouve avec un oracle, soit il **remonte à Pierre** (fog → HumanGate).
> Ferme la faille « techniquement correct mais non vérifiable / impossible à auditer ».

Vocabulaire de verdict **unique** : `OK` / `FAIL` / `BLOCKED` (jamais PASS/CONCERNS/FAIL).

---

## `SKIPPED_VALIDATION[]` (exigence de SORTIE, ratification Pierre 2026-07-26)

> Ce n'est **pas** un 18e champ du contrat d'entrée — il ne s'ajoute ni à Critique, ni à
> Important, ni à Recommandé, et **ne touche pas** le compte des 17 champs ci-dessus. C'est une
> exigence sur ce que l'agent **produit** dans son `final_report`, au même titre que le
> vocabulaire de verdict unique.

Primitive 1 du salvage Codex (`studio_brain/decisions/PROPOSED_2026-07-26_ratifications.md`) :
généralise aux 21 contrats une pratique déjà présente en prose dans un seul
(`contracts/orchestrator.yaml` : « ce que je n'ai PAS prouvé »). Injectée verbatim par
`contract.RESTITUTION_RULE` (donc dans les 21 prompts, sans éditer les 21 YAML) :

- Une section finale `SKIPPED_VALIDATION`, structurée, pour **chaque** validation non faite :
  l'**item** de validation (quoi), le **périmètre** concerné (où), le **statut** (non fait /
  partiel / hors délai…) et la **raison** (pourquoi).
- Rien sauté → sentinelle `aucun` (`SKIPPED_VALIDATION: aucun`) — même logique de « déclaré vide »
  que les 3 états de champ ci-dessus : une décision assumée, jamais un silence.

**ADVISORY UNIQUEMENT** : ceci ne bloque rien, ne change aucun `software_verdict`, aucun gate.
Le garde-fou de la ratification (le corpus Codex est mort d'avoir été déclaratif sans lecteur)
impose que la primitive arrive avec **son point de mesure** : `forge.skipped_validation.
skipped_validation_status(agent_output)` classe la sortie texte d'un agent en trois états —
`filled` / `declared_empty` / `absent` — pour mesurer l'adoption réelle, sans jamais lever
d'exception ni consulter/modifier un verdict. Le passage en gate dur, si l'adoption le justifie,
est une décision Pierre distincte et ultérieure.

---

## Application — le principe de la porte unique

L'enforcement ne repose pas sur une consigne « promise ». Il repose sur **une seule porte** :

> Tout appel de sous-agent Forge passe par **une unique fonction** `dispatch(étape)`.
> Il n'existe pas d'autre chemin pour lancer un agent.

Cette porte, **avant** de laisser passer quoi que ce soit :

1. **Vérifie le contrat.** Un Critique vide/absent, ou un optionnel non déclaré → lève
   `CONTRACT_INCOMPLETE` et s'arrête. Aucun agent ne démarre.
2. **Fabrique le prompt** à partir du contrat (role + objectif + in/out_of_scope + gardeFou,
   force le `modele`, applique les `permissions`, charge **seulement** les `skill`/`plugin` listés,
   injecte `success_criteria` + `output_contract` + la Règle de restitution).

Conséquence : **on ne peut pas obtenir le prompt sans passer par la porte, et la porte ne
fabrique pas de prompt si le contrat est incomplet.** Pas de contrat valide → pas de prompt →
pas d'agent. Mécanique, pas déclaratif.

---

## Résolution du runtime (ADR-002 gate 1 — jamais de modèle en dur)

Le contrat **ne fixe pas de modèle**. Il déclare `capability_role` (+ `exigences_cognitives`) ;
le **registry local** résout le runtime via `control_plane.registry.get_model_for_role(role,
caps_path=forge/contracts/roles.yaml)`. Un rôle non résolu ⇒ `RoleUnresolved`
(sous-classe de `ContractIncomplete`) ⇒ contrat non activable.

- Phase actuelle : full Claude pour les producteurs, **Qwen = red-team / reviewer indépendant**
  (gate 4 — Qwen critique les décisions, ne remplace jamais les oracles techniques).
- `roles.yaml` est **Forge-scopé** et constitue la **seule** source de résolution de rôle de la Forge
  (`contract.resolve_runtime` passe toujours `caps_path=FORGE_ROLES`). Il ne touche pas
  `openclaw/capabilities.yaml`, qui n'est **plus** le « SSOT studio » : openclaw est **legacy**
  depuis le 2026-07-23 (Pierre : « on travaille que claude et forge »). Ce chemin n'est que le
  défaut du module partagé `control_plane/registry.py:15`, consommé par la lane STUDIO gelée.

## Gouvernance du dispatch (ADR-002 gate 2)

Le spawn d'un sous-agent ne part **jamais** directement de l'agent exécutant : il passe par le
contrat validé **puis** par `scripts/dispatch_bridge.py` (délégation gouvernée). Claude reste le
moteur d'orchestration/exécution ; le contrat est la **porte de contrôle**. (Câblage = connecteur 2,
incrément ultérieur ; C1/C2 ne spawnent rien.)

## Champs — source de vérité

Un contrat par étape vit dans `forge/contracts/<etape>.yaml` (testable, découplé).
La carte llm-lego (`llm-lego/library/chain-forge.json`) en est le **miroir visuel** : les
satellites d'une planète reflètent les champs du contrat. La vérité est le YAML ; le dessin suit.
