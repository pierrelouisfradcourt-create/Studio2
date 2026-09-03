---
name: forge
description: Boucle d'ingénierie Forge — enchaîne les étapes-agents, chacune bornée par son contrat (aucun agent sans contrat validé), oracles non-LLM aux points de preuve, verdict signé → HumanGate. Registry local résout le modèle. NO_CLAIM_ALLOWED.
---

# /forge <projet-ou-objectif>

Enchaîne la chaîne d'ingénierie Forge. **Invariant central : aucun sous-agent n'est lancé sans passer par son contrat validé.** Le contrat est la porte de contrôle ; il borne le rôle, force le runtime, limite les permissions et impose la règle de restitution.

> Règles absolues (CLAUDE.md + ADR-002) : `claim_verdict: NO_CLAIM_ALLOWED` ; séparer `software_verdict`/`evidence_verdict`/`claim_verdict` ; **HumanGate (Pierre) décide** merge/reject ; zones protégées `tests/**` jamais modifiées. Modèles = full Claude (producteurs) + **Qwen = red-team indépendant** ; oracles = déterministes non-LLM.

> **Résolution rôle → runtime : source unique `forge/contracts/roles.yaml`** (lue par `forge.contract`). Ne déduis jamais un modèle d'ici — ce fichier fait foi, y compris pour le rôle `orchestrator` et pour l'échelle d'escalade des builders. Le contrat de système (`forge/FORGE_SYSTEM_CONTRACT.yaml`) interdit de réécrire cette règle ailleurs ; le capteur `forge.contract_sync` vérifie que ce fichier la CITE au lieu de la redire.

> **Deux rôles distincts, ne jamais les confondre** (séparation ratifiée Pierre 2026-07-23, source : `roles.yaml`) :
> **`orchestrator`** = la SESSION qui pilote /forge (Fable, mode superpowers) — entrée purement DESCRIPTIVE de `roles.yaml`, jamais résolue par le code : c'est Pierre qui choisit son modèle en ouvrant la session.
> **`run_orchestrator`** = l'AGENT SPAWNÉ sous contrat (`contracts/orchestrator.yaml`, résolu par le registry → Opus) qui conduit UN run de bout en bout. C'est lui qui a un coût réel et une trace de dispatch.
> Dans les deux cas : démarrer et piloter, ne coder aucune étape, spawn via la porte `prepare_dispatch`, aiguiller (A2), décider l'escalade. Aucun des deux n'est un tier de build.

---

## Entrée

`/forge [--patch|--review] <description du projet ou de l'objectif>`. Si l'objectif est flou (pas de périmètre, pas de « produit fini » imaginable), **arrête-toi et pose 2-3 questions de cadrage** avant de lancer la chaîne (c'est ce que fait l'étape 0, ne la court-circuite pas).

**Profils de chaîne — la liste fait foi dans `forge.dispatch.PROFILES`, pas ici.** Ne te fie jamais à cette énumération pour savoir ce qui existe : lance le `--dry-run` ci-dessous, qui lit la source. Repères d'usage :
- `full` (défaut) : projet greenfield complet (Prisme → … → WireMap → build → oracles → verdict).
- `patch` : un fix sur un projet **existant**. Les oracles archi/wiremap n'y sont pas applicables : au verdict, émets pour eux des reçus **`SKIPPED`** signés (jamais un faux OK). C'est le mode quotidien.
- `micro` : tâche triviale (fonction pure, one-liner) — proportionnalité, pas de cérémonie 13 étapes.
- `increment` : incrément sur un projet dont les bibles sont déjà la source de vérité (refait archi/wiremap, contrairement à `patch`).
- `standard` : **curriculum de jeux sur squelette gelé** — voir la section dédiée plus bas.
- `review` / `artbible` : une étape isolée, sans verdict signé.

## Le socle (déjà câblé, à réutiliser — ne pas réimplémenter)

- Contrats : `forge/contracts/<etape>.yaml` (schéma `SCHEMA.md`, 17 champs).
- Dispatch gouverné : `forge/dispatch.py` — `prepare_dispatch(etape, run_id)` valide le contrat, fabrique le payload borné, trace l'audit. **Ne spawn pas** : c'est TOI (l'orchestrateur) qui spawnes avec le payload.
- Oracle / gate / verdict : `forge/{oracle,gate,verdict}.py` (déterministes, HMAC).

## Étape préliminaire — planifier (obligatoire)

```bash
./.venv/Scripts/python.exe -m forge.dispatch --dry-run [--profile patch]
```

Affiche les étapes du profil et leur runtime résolu (13 en `full`, 4 en `patch`). Si une étape lève `ContractIncomplete`/`RoleUnresolved`, **STOP** : un contrat est cassé, corrige-le avant de lancer quoi que ce soit.

## Pré-mortem (avant l'étape 0 — connecteur 6)

Lis les erreurs des runs précédents pour que l'étape 0 en tienne compte (le « PILOU ») :
```python
from forge.studio_link import premortem
rappels = premortem("<projet>", domain="html")   # JEU -> "html" ; tout le reste -> "forge"
```
`domain` est **obligatoire** ici : sans lui, `premortem` reste en mode rétrocompat et ne
lit QUE les leçons globales/playtest — les leçons DU PROJET restent invisibles en silence
(comportement du mode domaine de `journal_path=None`, cf. `studio_link.py::premortem`).
La règle « quel domaine pour quel projet » a une source UNIQUE, ne la redécide pas ici :
`driver.py::ForgeDriver._domain` — `"html"` pour un JEU (le cas courant de la Forge),
`"forge"` sinon.
Injecte `rappels` dans le contexte de l'étape 0 (via son `mandatory_read`).

## Oracle charter (R7, après l'étape 0 — obligatoire)

Dès que s0 rend `charter.yaml`, valide-le mécaniquement AVANT s1 :
```python
from forge.static_oracles import check_charter
r = check_charter(charter_dict)   # 7 champs requis dont plateforme_cible · reference_jeu · criteres_demo[]
```
`passed` faux → re-spawn s0 avec les raisons (jamais un charter incomplet vers l'aval). `reference_jeu`
vient de PIERRE (design-intent) — un agent ne l'invente jamais : absent = fog HumanGate.

## Profil `standard` — curriculum de jeux sur squelette gelé

Variante pour le curriculum (Pong → …), où le jeu n'est pas décrit en langage libre mais **gelé
en amont** dans un squelette : chaque exigence y a déjà une adresse, un état attendu et une preuve
attendue. Le forgeron ne reçoit donc pas « fais un Pong » — il reçoit une carte à remplir, et il
n'a **pas le droit d'ajouter hors plan**.

Ne redis rien du format ici : la spécification est `forge/standard/SCHEMA.md`, et les
tables figées qu'elle utilise sont `forge/standard/{core_requirements,repo_map,capabilities}.yaml`.

- **Étape de build** : `s9-build-standard` (rôle `game_forger`, résolu par `roles.yaml` — pas un
  `builder`, cf. son contrat pour la proportionnalité rôle/effort).
- **Étape d'oracle** : `s10s-oracle-standard`, déterministe, qui exécute `forge.standard_oracles`.
  C'est là que vit la **loi d'empilement** (`forge.standard_oracles.check_budget` : ce qu'un jeu a
  le droit de déposer en bibliothèque) — n'en juge jamais toi-même, lis le reçu.
- `s10a-oracle-code` (mutation / e2e / solvabilité) reste applicable et **n'est pas remplacé**.

Un oracle du standard rouge se traite comme les autres oracles (3. ci-dessous) : il alimente le
pool puis l'escalade, il ne se contourne pas.

## Boucle d'orchestration

Pour chaque `etape` dans l'ordre `forge.dispatch.ORDER` :

1. **Prépare le dispatch** (la porte) :
   ```python
   # via un court script PYTHONPATH=scripts python :
   from forge.dispatch import prepare_dispatch
   payload = prepare_dispatch(etape, run_id="<projet>-<horodatage>")
   ```
   Si ça lève → le contrat est incomplet → **STOP**, ne lance pas l'agent.

2. **Étape LLM** (`etape` ∉ `forge.dispatch.DETERMINISTIC`) : **aiguille d'abord selon le provider du contrat**, puis exécute. Ne spawne jamais « en dur » sur Claude sans passer par l'aiguilleur — c'est lui qui honore le contrat à l'exécution (A2).
   ```python
   from forge.runtime import route_step, run_qwen_step
   d = route_step(payload)   # décision : qwen | claude | claude-blind | oracle
   ```
   - **`d.runner == "qwen"`** (provider `lmstudio`, LM Studio :1234 UP) : exécute le **reviewer indépendant Qwen** en Python (pas de sous-agent Claude) :
     ```python
     res = run_qwen_step(payload)     # {ok, reviewer, output|reason}
     ```
     Si `res["ok"]` → utilise `res["output"]` comme artefact. Si `res["ok"]` est faux (Qwen a lâché en cours d'appel) → **bascule sur le fallback claude-blind** ci-dessous.
   - **`d.runner == "claude-blind"`** (provider `lmstudio` mais :1234 down) : spawne un sous-agent Claude **en contexte vierge** — prompt adversarial `payload.prompt`, aucun contexte d'auteur du plan, aucune mémoire de run partagée. C'est un fallback assumé, **pas** un reviewer indépendant : `d.reason` dit pourquoi.
   - **`d.runner == "claude"`** (provider `claude-local`) : spawne un sous-agent Claude normal.
   - Dans **tous** les cas de spawn Claude : `prompt` = `payload.prompt` **+ le marqueur `FORGE_DISPATCH:<etape>:<run_id>`** (le hook dur `pretool_forge_guard` bloque tout spawn Forge sans dispatch validé enregistré ; comme tu viens d'appeler `prepare_dispatch`, l'audit contient le dispatch → le spawn passe), et outils = `payload.allowed_tools` uniquement.
   Le producteur (Qwen ou sous-agent) rend l'artefact décrit par le contrat (`output_contract`). Récupère-le.
   **Après le retour** (connecteurs 3+6) : trace le **reviewer réel** (`d.reviewer` ou `res["reviewer"]`, ex. `qwen2.5-14b-instruct` ou `claude-blind (fallback)`), pas le modèle contracté :
   `studio_link.record_telemetry(run_id, etape, reviewer_reel, tokens, duree)`. Ce `reviewer` sera **plié dans le verdict signé** (A3). Si l'agent a échoué/signalé une faille : `studio_link.record_error(run_id, etape, msg, project)`.

   > **Gel du jeu de règles (renfort 2026-07-11, axe 2) — post-étape `s5-wiremap` UNIQUEMENT.** Le `if` ci-dessous garde le bloc scopé : il ne s'exécute qu'à s5 (les autres étapes LLM n'ont pas de `wiremap`). Dès que la WireMap est produite, fige l'ensemble des règles (immuable pour tout le reste du run) :
   > ```python
   > if etape == "s5-wiremap":
   >     import json
   >     from pathlib import Path
   >     from forge.static_oracles import frozen_features_from_wiremap
   >     run_dir = Path("EVIDENCE/runs/<projet>")   # même run_dir qu'à s10c
   >     (run_dir / "wiremap_frozen.json").write_text(
   >         json.dumps({"features": frozen_features_from_wiremap(wiremap)}, ensure_ascii=False),
   >         encoding="utf-8")
   > ```
   > Le builder (s9) met à jour les COLONNES de la WireMap (fonction/fichiers/…) mais ne touche JAMAIS `wiremap_frozen.json`. C'est l'ancre de traçabilité (quelles règles doivent exister), dérivée du product_snapshot (R1..R12).

   **Escalade de modèle** (builders Claude uniquement — pas Qwen ni oracles) : un sous-agent trop juste pour sa tâche finit son rapport par `ESCALATE_REQUEST: <raison>`. Après le build **et son oracle** (s10a), décide :
   ```python
   from forge.escalate import parse_agent_escalation, escalation_decision
   requested, why = parse_agent_escalation(agent_output)
   # Les oracles sont calculés D'ABORD (3. s10a/s10c ci-dessous), PUIS on décide l'escalade.
   # oracle_ok est assigné en UN SEUL endroit (bloc s10c, une fois e2e_guard/mgate/wire connus) :
   #   non-jeu : oracle_ok = code.ok and wire["passed"]
   #   JEU     : oracle_ok = code.ok and e2e_guard["passed"] and wire["passed"] and mgate["passed"]
   # (le gel du jeu de règles est un STOP séparé, cf. s10c).
   d = escalation_decision(payload.model, oracle_ok=oracle_ok, agent_requested=requested,
                           agent_reason=why, escalations_so_far=n)
   ```
   **Avant d'escalader, le pool : re-tentative au MÊME tier.** Un oracle rouge n'est pas une preuve que le tier est trop faible — ça peut être un aléa de tirage. La décision est prise par `forge.pool.pool_decision` (`oracle_ok`, `attempts_at_current_tier`, `pool_size`), **pas par ton jugement** : elle ne s'applique que sur un FAIL d'oracle, jamais sur un `ESCALATE_REQUEST` explicite (l'agent, lui, sait que son tier ne suffit pas). Pool épuisé → seulement alors, escalade de modèle. Ne saute pas cette étape : escalader dès le premier rouge dépense un tier supérieur là où un même-tier aurait suffi.

   Si `d.escalate` : **ré-spawne LE MÊME contrat** (marqueur `FORGE_DISPATCH` compris) avec l'outil Agent `model=d.next_model`, échelle et cap résolus par `forge.escalate` + `roles.yaml`, incrémente `n`, trace l'escalade (`record_telemetry`). Le verdict signera le **tier réel** qui a produit l'artefact (honnêteté, comme le reviewer). Au sommet avec échec → `d.escalate` est faux et `d.reason` renvoie à HumanGate : **ne boucle pas**, remonte à Pierre.

   > **Jugement d'agent — lire-d'abord / écrire-si-nouveau (avant toute re-tentative).** L'écriture-sur-échec est DÉJÀ automatique côté driver (`record_error`/`record_fix` câblés dans `_halt_step`/`_finish_step`). Ce bloc-ci n'est PAS une écriture de plus : c'est la RECONNAISSANCE côté agent, avant de re-spawner une étape échouée. Dans l'ordre :
   > 1. **Lis d'abord** le journal du domaine — le pré-mortem l'a déjà surfacé (`premortem("<projet>", domain="<domaine>")` à l'étape 0, entrées « → ✅ RÉPARÉ: … »). Ne re-cherche pas à l'aveugle : la réparation de CE même échec y est peut-être déjà.
   > 2. Si une **erreur connue + sa résolution** matche l'échec courant → **applique le fix connu** au lieu de ré-explorer. Guide le ré-spawn (`payload.prompt` + rappel du fix) avec cette réparation.
   > 3. **N'écris une NOUVELLE entrée que si l'échec est NOUVEAU** (pas déjà au journal). Le dédoublonnage est un **jugement de l'agent** (reconnaissance en langage naturel « c'est le même problème que … »), pas un match déterministe. L'échec brut est déjà capté automatiquement ; ce que tu ajoutes à la main, c'est la 2e colonne d'une réparation NOUVELLE — `record_fix(run_id, etape, error, resolution, "<projet>", domain="<domaine>")`. Un échec déjà connu ne se ré-écrit pas.

3. **Étape déterministe** (`etape` ∈ `forge.dispatch.DETERMINISTIC`) : **ne spawne pas d'agent**. Lance l'oracle correspondant :
   - `s10a-oracle-code` → `forge.gate.forge_gate("<projet>")` (commande via `oracles.json`, verdict signé). Garde `code = forge_gate(...)`.
     > **Oracle d'un JEU à UI = click-through Playwright**, pas des tests unitaires. La commande `oracles.json` du jeu lance un e2e qui **clique chaque bouton et parcourt chaque chemin** (déterministe, `returncode` = pass/fail, captures sous `e2e-shots/`). Il mappe 1:1 le Prisme (s1) : *le joueur voit/fait* → clique X, vérifie Y. Harnais de référence : `llm-lego/experiments/belote-claude/web/e2e-lib.mjs` (`startServer` + clics DOM `page.click(...)` + assertions d'état). **Claude-in-Chrome = exploratoire, PAS l'oracle** (LLM, non déterministe).
     > **Oracle d'un JEU = AUSSI la SOLVABILITÉ, pas seulement les mécaniques.** Un jeu aux objectifs inatteignables passe TOUS les tests de mécanique en isolation (« collectCoin marche SI on place le joueur sur la pièce ») tout en étant injouable — prouvé 2× (survival_arena tir/poursuite non testés ; collect_runner pièces hors de portée de saut, 14 tests + e2e verts, injouable au playtest). L'oracle code d'un jeu **inclut obligatoirement** un volet `solvability.mjs` (câblé dans `run-oracle.mjs`) qui : **(1)** mesure l'enveloppe d'action RÉELLE du moteur (ex. hauteur de saut — mesurée, pas hardcodée), **(2)** vérifie que chaque objectif requis y est, **(3)** fait **jouer un bot déterministe qui doit GAGNER**. Modèle à copier : `forge/templates/solvability.template.mjs` ; réf. vivante : `games/collect_runner/solvability.mjs`. Contractualisé en s9 (`success_criteria`/`tests_oracles`/`output_contract`).
     > **Renforcer/valider les oracles** (au-delà des exemples à seed fixe, qui ratent les mutants) : **(1) property-based** — invariants sur beaucoup de seeds + inputs aléatoires seedés (déterminisme, bornes, monotonies) ; réf. `games/collect_runner/properties.test.mjs`, câblé dans `run-oracle.mjs`. **(2) mutation testing** — le MÉTA-oracle « tes tests attrapent-ils un bug ? » : `PYTHONPATH=scripts python -m forge.mutation <src> --cwd <dir> -- node --test <tests>` mute le code (`>=`→`>`, `&&`→`||`…) et rend un **score de tués/total** + la liste des mutants **survivants** (bugs non détectés) à corriger. Un `>=` tautologique survit → signal direct.
     > **Gate e2e déterministe (renfort 2026-07-11) — la doctrine Playwright ci-dessus est désormais APPLIQUÉE.** Pour un JEU, avant de conclure l'oracle-code, lance la garde structurelle non-LLM :
     > ```python
     > from pathlib import Path
     > from forge.static_oracles import check_e2e_harness
     > e2e_guard = check_e2e_harness(Path("games/<projet>"))   # contribue à l'oracle_ok combiné (consolidé après s10c)
     > ```
     > Si `not e2e_guard["passed"]` : traite l'oracle comme ÉCHOUÉ (raisons = `e2e_guard["raisons"]`), ce qui alimente la boucle d'escalade (2. ci-dessus, `oracle_ok` combiné) → ré-spawn du contrat s9, modèle ↑, cap `MAX_ESCALATIONS`. Au sommet toujours rouge : verdict BLOCKED + `humangate_flags: ["e2e non prouvé"]`. La garde rejette : `e2e.mjs` absent, non câblé dans `run-oracle.mjs`, ou coquille (< 3 observations de `window.__game`/`#overlay`/`#restart`). Cf. `forge/contracts/PLAYABLE_CONTRACT.md`.
     > **Gate mutation (renfort 2026-07-11, axe 3) — « 100% ou survivant justifié ».** Pour un JEU, après l'oracle-code, mute **les fichiers logiques déclarés par la WireMap** (pas seulement `game.mjs` : la logique est répartie — `game.mjs`, `level.mjs`, … ; les fichiers `.mjs` non-test cités dans `wiremap["features"][*]["fichiers"]`) et agrège les résultats :
     > ```python
     > from forge.mutation import run_mutation_test
     > from forge.static_oracles import check_mutation_gate, load_mutation_triage
     > logic_files = sorted({f for feat in wiremap["features"] for f in feat.get("fichiers", [])
     >                       if f.endswith(".mjs") and "test" not in f})   # ex. game.mjs, level.mjs
     > survivors, total = [], 0
     > for src in logic_files:
     >     r = run_mutation_test(src, ["node", "--test", "logic.test.mjs", "properties.test.mjs"],
     >                           cwd="games/<projet>")
     >     survivors += r["survivors"]; total += r["total"]
     > mgate = check_mutation_gate({"total": total, "survivors": survivors},
     >                             load_mutation_triage("games/<projet>"))   # contribue à l'oracle_ok combiné
     > ```
     > `not mgate["passed"]` alimente la boucle d'escalade (2. ci-dessus) → ré-spawn s9 « tue le survivant `name@line` par un test, OU triage-le équivalent avec justification dans `mutation_triage.json` », cap `MAX_ESCALATIONS`. Fini le 68% qui passe en silence. Cas `total==0` (aucun fichier logique mutable) : escalade-guidée « déclare/mute les vrais fichiers logiques » — jamais un vert (pas un faux vert), mais pas un cul-de-sac non plus.
   - `s10b-oracle-archi` → `archi = forge.static_oracles.check_architecture(blueprint, src_root)`.
   - `s10c-oracle-wiremap` → `wire = forge.static_oracles.check_wiremap(wiremap, src_root)`.
     > **Auto-correction traçabilité (renfort 2026-07-11, axe 2).** Après `check_wiremap`, vérifie le gel du jeu de règles puis décide :
     > ```python
     > from pathlib import Path
     > from forge.static_oracles import check_feature_set_frozen, load_frozen_features
     > run_dir = Path("EVIDENCE/runs/<projet>")   # même run_dir qu'à s5
     > frozen = check_feature_set_frozen(wiremap, load_frozen_features(run_dir))
     > if not frozen["passed"]:
     >     # NON auto-corrigeable => verdict BLOCKED, NE BOUCLE PAS. Flag honnête selon la cause :
     >     if not frozen["checked"]:
     >         flag = "snapshot de gel absent (s5 n'a pas figé le jeu de règles)"
     >     else:
     >         flag = f"jeu de règles modifié (ajoutées={frozen['ajoutees']}, supprimées={frozen['supprimees']})"
     >     # humangate_flags: [flag]
     >     ...
     > else:
     >     # fonctions renommées/manquantes mais règles intactes => AUTO-CORRIGEABLE.
     >     # ⇒ DÉFINITION UNIQUE de oracle_ok (ici e2e_guard/mgate de s10a ET wire de s10c
     >     #    sont tous disponibles ; c'est le seul endroit qui l'assigne pour un JEU) :
     >     oracle_ok = code.ok and e2e_guard["passed"] and wire["passed"] and mgate["passed"]
     >     # (non-jeu : oracle_ok = code.ok and wire["passed"] — pas d'e2e/mutation)
     >     # oracle_ok alimente escalation_decision (2. ci-dessus) → ré-spawn s9 avec le rapport
     >     # cumulé (carte↔code isomorphes + survivants mutation + e2e), cap MAX_ESCALATIONS.
     > ```
     > `wire` rouge n'est donc plus un cul-de-sac : jeu de règles intact + fonction renommée (ou survivant mutation, ou e2e coquille) → re-build ciblé au lieu d'un BLOCKED sec. Une règle disparue (ou un snapshot de gel absent) reste un STOP dur (jugement humain). **Note : `oracle_ok` n'est assigné qu'ICI** (après que les 3 gardes e2e/mutation/wiremap soient calculées) — les blocs s10a calculent `e2e_guard`/`mgate` mais ne l'assignent pas, pour éviter toute écrasure d'ordre.
   - `s12-verdict` → **agrégation signée** (voir 4).
   Oracle rouge (`ok is False` / `passed is False`) → **STOP**, ne passe pas les étapes suivantes — **SAUF les cas d'auto-correction bornée** (renfort 2026-07-11) : (a) garde e2e rouge (s10a), (b) WireMap rouge à **jeu de règles gelé intact** (s10c) et (c) gate mutation rouge à **survivant non justifié** (s10a) alimentent la boucle d'escalade `escalation_decision` (ré-spawn s9, cap `MAX_ESCALATIONS`) au lieu de STOP. Le gate mutation `total==0` (aucun fichier logique mutable) alimente aussi l'escalade, avec la consigne « déclare/mute les vrais fichiers logiques » (jamais un vert, mais pas un STOP dur). Restent des STOP durs : oracle-code/archi rouges, gel du jeu de règles violé (règle ajoutée/supprimée), snapshot de gel absent, et sommet d'escalade atteint.

4. **Verdict final** (`s12-verdict`) : chaque oracle émet un **reçu signé** (preuve d'exécution, pas narration) ; l'agrégat **vérifie** ces reçus — un `OK` sans reçu valide sur ce `run_id` est **impossible** sans la clé. L'identité réelle du reviewer (A2) et `redteam_ran` (structuré) sont signés — un fallback ne peut pas se faire passer pour Qwen actif :
   ```python
   from forge.verdict import (make_signed_receipt, status_from_passed, sha256_file,
                              build_aggregate_verdict, signed_aggregate_record,
                              current_git_head, new_nonce)
   run_id = "<projet>-<horodatage>"   # LE MÊME que celui des dispatch de ce run
   code_r  = make_signed_receipt("code", run_id, code.verdict.software_verdict,
                                 {"returncode": code.verdict.returncode},
                                 evidence_path=str(code.verdict.evidence_path))  # RE-LU à la vérif
   # ⚠ un reçu code SANS evidence_path => provenance rompue => BLOCKED (exécution non prouvable).
   archi_r = make_signed_receipt("archi",   run_id, status_from_passed(archi["passed"]), archi)
   wire_r  = make_signed_receipt("wiremap", run_id, status_from_passed(wire["passed"]),  wire)
   agg = build_aggregate_verdict(
       project, run_id, code_r, archi_r, wire_r, reviewer_reel,
       redteam_ran=(d.runner == "qwen" and res["ok"]),   # le reviewer INDÉPENDANT a-t-il tourné ?
       redteam_findings=findings, redteam_blocked=redteam_a_bloque,
       git_head=current_git_head(), nonce=new_nonce(),   # anti-rejeu : lie le verdict au run/code
   )
   record = signed_aggregate_record(agg)        # {..., "decision", "provenance_ok", "hmac"} -> verdict.json
   ```
   `software_verdict` vient **UNIQUEMENT** des reçus d'oracle vérifiés ; provenance rompue (reçu absent/altéré/`run_id` discordant) → `software_verdict=BLOCKED`. Le red-team est **advisory** (lève des `humangate_flags`, ne juge jamais le code). `claim_verdict` = `NO_CLAIM_ALLOWED` **toujours**. `decision` ∈ {`HUMANGATE_READY`, `BLOCKED`} n'est **pas** une décision de merge (c'est Pierre).

## Fin de chaîne — restitution studio + HumanGate

Avant de présenter à Pierre, dépose les propositions **propose-only** (connecteurs 4+5, aucune écriture durable) et l'agrégat de coût (connecteur 3) :
```python
from forge.studio_link import run_cost, propose_ledger_entry, propose_project_record
cout = run_cost(run_id)                                   # {calls, total_tokens, total_duration_s}
propose_ledger_entry(run_id, project, verdict)            # lane AUDIT_REQUIRED, PROPOSED
propose_project_record(project, stage, folder)            # PROPOSED
```
**Avant de présenter à Pierre, VÉRIFIE mécaniquement le verdict** — ne dis jamais « HMAC OK » sans avoir lancé la commande :
```bash
./.venv/Scripts/python.exe -m forge.verify_run EVIDENCE/runs/<projet>/verdict.json
```
Trois issues, trois lectures — ne les confonds jamais. Depuis V1 (2026-07-26, séparation intégrité/verdict — mémoire pong_r2), le code de sortie répond à UNE seule question, l'**authenticité**, jamais à la couleur du verdict logiciel : la sortie porte deux lignes distinctes, `INTÉGRITÉ : AUTHENTIQUE|REJET` et `VERDICT LOGICIEL : <software_verdict> / <decision>`.
- **Exit 0** = **intégrité authentique** (HMAC re-signé + évidence re-lue + preuve mutation authentique + git_head comparé), **quel que soit le verdict logiciel affiché** → un FAIL/BLOCKED honnête (gate mutation rouge légitime, ex. pong_r2) sort désormais exit 0 avec `VERDICT LOGICIEL : FAIL / BLOCKED` : ce n'est PAS un succès, c'est un constat authentique à remonter tel quel à **Pierre**. Le seul cas où un gate mutation rouge fait encore échouer l'intégrité (exit 2) est un verdict qui **prétend** `software_verdict=OK` alors que son propre reçu mutation embarqué ne l'est pas (vert non prouvé — gate de cohérence, jamais relâché).
- **Exit 2** = intégrité **REJET** : falsifié/altéré (HMAC, évidence, preuve mutation périmée) OU incohérent (OK affiché sur un gate mutation rouge) → **STOP**, remonte à Pierre le **rejet**.
- **Exit 3** = verdict **absent ou illisible** — il n'y a rien à vérifier, donc rien n'a été signé, donc rien à présenter comme preuve. **Ce n'est PAS un rejet et encore moins un succès** : ne dis jamais « le run a réussi » ni « le run a échoué » sur cette seule base — le run n'a simplement produit AUCUN verdict exploitable. **STOP**, ne présente rien à Pierre : remonte-lui que la chaîne s'est arrêtée avant `s12-verdict` (ou que le chemin donné est faux) et qu'il n'existe aucun artefact à ratifier.

Dans tous les cas hors exit 0 : **Tu ne décides jamais** merge/reject/freeze, et tu ne promeus jamais une proposition en mémoire de référence (ledger, projets) sans son go. Si une étape n'a pas d'oracle pour appuyer une affirmation → remonte un besoin HumanGate (fog), pas un claim (RÈGLE DE RESTITUTION).

## Avant TOUTE escalade humaine — vérifier l'architecture d'abord

Ratifié Pierre 2026-08-03 (`FORGE_AUTONOMY_V1`, decision-log). Leçons KB :
`forge.architecture_check_before_human_escalation` · `forge.broken_loop_repair_not_report` ·
`forge.diagnosis_is_not_workflow_end` · `forge.escalation_costs_avoid_default_route`.

**Règle : avant toute escalade humaine, vérifier dans le Master Schéma
(`docs/forge/STUDIO_MASTER_SCHEMA.html`) si la solution existe déjà mais n'est pas câblée.**

Ordre obligatoire, ne saute aucune marche :

```
Blocage détecté
   ↓ la boucle est-elle PRÉVUE au Master Schéma ?
   ↓ diagnostic : composant non buildé ? construit mais non câblé ? mal câblé ?
     consommateur absent ? contrat incomplet ?
   ↓ cause racine identifiée + solution déterminée + risque acceptable ?
   ↓ OUI aux trois → RÉPARER · TESTER · PROUVER · DOCUMENTER
   ↓ NON → escalade, en nommant le CHOIX qui reste à faire
```

**Première hypothèse obligatoire** : la capacité existe déjà dans l'architecture mais n'est pas
branchée. Ne remonte jamais un « manque de capacité » sans avoir cherché l'écart entre le design et
l'implémentation. Cas typiques déjà rencontrés : KB inconnue → vérifier la boucle fouille → web → KB
→ builder *avant* de déclarer une limite de connaissance · oracle incorrect → vérifier l'aiguillage
moteur *avant* de modifier l'oracle · validation sans producteur → créer ou reconnecter le
producteur *avant* de discuter du validateur · artefact sans lecteur → chercher le consommateur
prévu par l'architecture.

Un diagnostic n'est PAS une fin de workflow. La sortie attendue est
`PROBLEM / CAUSE / ACTION / VALIDATION / ESCALADE-si-choix-restant`, jamais `PROBLEM / CAUSE /
QUESTION`. Une escalade coûte (interruption, contexte, temps, dilution) : elle doit être justifiée
par une **nécessité de décision** — décision de conception, changement d'invariant, choix produit,
ou plusieurs solutions valides — jamais par une incapacité à appliquer une solution déjà trouvée.
**L'humain tranche les choix ; la Forge exécute les corrections connues.**

Ce qui reste HumanGate malgré tout (invariants ADR-002, inchangés) : merge/reject/freeze · toute
décision de conception ouverte · tout changement d'invariant.

### Classer AVANT de demander (ratifié Pierre 2026-08-03)

**Avant de demander une décision, classe le problème.** Quatre classes sur cinq se traitent sans
l'humain :

| classe | situation | action |
|---|---|---|
| **A** | boucle cassée | **réparer directement** |
| **B** | composant prévu mais non construit | **planifier la construction** — jamais traiter comme un bug |
| **C** | composant construit mais non câblé | **brancher** |
| **D** | composant mal câblé | **corriger** |
| **D'** | composant **bloqué** (appelé, prédicat/condition jamais vraie) | **rendre l'état observable** avec sa raison ; ne desserrer le prédicat que sur décision |
| **D''** | **erreur d'utilisation** (l'outil marche, on s'en sert mal) | **corriger l'usage**, pas l'outil |
| **E** | vraie décision d'architecture ou produit | **HumanGate** |

Seul **E** remonte. Annonce la classe quand tu rends compte — « (C) construit mais non câblé,
branché » vaut mieux qu'un paragraphe.

**Un symptôme cherche toujours sa boucle responsable** (ratifié Pierre 2026-08-03) :

```
Symptôme → chercher la boucle PRÉVUE au Master Schéma → classer
        → réparer si cause connue + solution connue + risque maîtrisé
        → sinon escalade, en nommant le choix restant
```

Ne remonte jamais un constat simple. « Le standard ne connaît pas ce jeu » n'est pas un fait à
rapporter, c'est la trace d'une boucle d'acquisition qui ne s'est pas déclenchée.

**État de référence** : `docs/forge/FORGE_STATE_V2_0.md` — snapshot canonique du 2026-08-03,
séparant strictement *réparé* / *construit non exploité* / *non construit*. Consulte-le avant de
déclarer qu'une capacité manque : elle y est peut-être listée comme volontairement non exploitée ou
comme chantier futur.

### Ce que l'autonomie ne peut JAMAIS fabriquer (ratifié Pierre 2026-08-03)

L'autonomie **peut** : détecter · analyser · proposer · réparer des boucles cassées · apprendre.

Elle ne peut **jamais fabriquer** :
- une **validation humaine** ;
- une **ratification** ;
- une **décision attribuée à une personne**.

Concrètement : ne remplis jamais un champ du type `ratifie_par` / `validated_by` / `approved_by`
avec le nom d'un humain qui n'a pas explicitement approuvé **ce contenu précis**. Autoriser un
mécanisme n'est pas ratifier ce qu'il produira. Quand une écriture automatique a besoin d'une
provenance, écris la provenance **réelle** : la décision qui autorise, le `run_id`, l'oracle, la
preuve — et dis explicitement ce qui n'a PAS été relu par un humain.

Incident fondateur (2026-08-03, faute de l'orchestrateur) : 8 leçons récupérées de Pong et Snake ont
été ingérées avec `validated_by: "Pierre"` parce que le prompt de mission disait
`--ratifie-par "Pierre"`. Pierre avait autorisé la **récupération rétroactive** et l'ingestion
automatique sous validation mécanique ; il n'avait jamais lu ces 8 leçons. Une autorisation
fabriquée est persistante : toutes les sessions suivantes l'auraient tenue pour un fait validé.
Corrigé le jour même. Même famille que la file de revue peuplée d'un `run_id` synthétique, écartée
quelques heures plus tôt.

Règle de contrôle : avant toute écriture durable, demande-toi **quel acte humain cette trace
prétend-elle enregistrer**, et si cet acte a réellement eu lieu.

### Où est la vérité système

**La vérité système vient de l'exécution observable, pas de la lecture du code.** Le Master Schéma
est la carte de référence ; l'Observer mesure le terrain ; l'écart carte↔terrain est le signal.
La lecture statique du code reste un outil d'audit ponctuel — **jamais la preuve finale**, sinon on
mesure une intention et on retombe dans « déclaré ≠ exécuté ».

Cela n'autorise pas à perdre la détection. La chaîne
`prévu → construit → câblé → actif → consommé → preuve` doit rester capable de nommer les trois
ruptures classiques : **prévu mais jamais construit** · **construit mais jamais appelé** ·
**appelé mais jamais consommé**. Un composant se juge par les artefacts qu'il produit, pas par sa
source — une ligne entièrement `NOT_OBSERVABLE` n'est pas de la prudence, c'est une perte de mesure.

Corollaire (décision Pierre) : **ne fabrique jamais un lecteur artificiel** pour justifier
l'existence d'un artefact. Le consommateur légitime peut être la session orchestratrice elle-même —
`Master Schéma → Observer → décision → action` est une boucle réelle. Si un artefact n'a de lecteur
ni humain ni machine, la question honnête est d'arrêter de l'écrire, pas de lui inventer un public.

## Rapport obligatoire

```
software_verdict: OK|FAIL|BLOCKED
evidence_verdict: MECHANICAL_VALIDATION_ONLY
claim_verdict: NO_CLAIM_ALLOWED
```

---

## Limites v0 (à dire honnêtement, ne pas surjouer)

- **Étapes contractualisées** : la chaîne canonique `full` couvre s0→s12 ; les contrats vivent dans `forge/contracts/`. Compte exact et profils : `--dry-run` (ci-dessus), jamais une liste recopiée ici.
- **Contrats orphelins connus** (écrits, référencés dans AUCUN profil ni aucun code — vérifié 2026-07-23) : `s10d-oracle-visual`, `s9-build-godot`, `redteam-artdirector`. Ne les invoque pas en croyant qu'ils sont câblés ; leur existence sur disque ne prouve rien (« déclaré ≠ exécuté »).
- **Synchronisation de ce fichier avec le code** : contrôlée mécaniquement par `forge.contract_sync`, agrégée dans `node forge/studio_selfaudit.mjs`. Limite déclarée : elle détecte l'ABSENCE de citation d'une règle canonique, **pas** une prose qui cite sa source tout en la contredisant. Ce n'est pas une preuve de non-divergence.
- **Connecteurs studio branchés** (ADR-002) : télémétrie (3), Kaizen-propose (4), mémoire projet (5), pré-mortem (6) via `forge.studio_link`, tous **propose-only**. **Connecteur 2 (hook dur) ACTIF** depuis 2026-07-10 (MAJ ADR-002 §7) : `pretool_forge_guard` (`PreToolUse`/`Task`, câblé dans `.claude/settings.json`) bloque tout spawn portant le marqueur `FORGE_DISPATCH:<etape>:<run_id>` sans ligne d'audit HMAC valide — **fail-CLOSED en périmètre Forge**, fail-open hors-forge. Portée honnête : contrôle la présence d'un dispatch signé, pas la conformité modèle/outils/prompt. L'enforcement passage-par-contrat combine donc **le hook (technique) + la porte Python** `dispatch.prepare_dispatch` + la discipline de ce skill.
- Forge **propose**, n'écrit jamais seul dans les mémoires de référence (ledger, projets) : toute écriture durable = HumanGate.
