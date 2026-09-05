I now have the complete, exact contract from the four oracle sources:

- **`check_prisme_manifest`** (s1 verdict): gates on chain (`observation`≠`claim`≠`enonce`) + provenance (`EXPECTED`→address / `ADDITIONS`→`null`) + `expected_proof{kind,statement}` + valid `destination` + ≥1 actionable + unique ids. Reference-anchoring is **reported-only, non-blocking**, and only knows worldscan tokens.
- **`check_prisme.mjs`** (panel form): 4 headers, ≥40 chars each, ≥1 `- **Rn` rule, no placeholders.
- **`upstream_schema.validateLoopFields`** + **`loop_spec.checkLoopSpec`**: the full G→H→I→J + DECISION per-link rules the executor derives `loop.json` against.

I've verified my planned 21 exigences pass every rule (all 10 loop roles, G≥2 same-hud new_distinct, F affordance+appears, H replay∈B..F, I prestige affordance, J replay_ref∈B + `increases_more_than:b_click`, DECISION options/policies/metric=`ronrons`/horizon=300/hud=`objectif`). Emitting now.

---

# Kitten Clicker — Product Snapshot (Prisme Produit)

*Le produit fini de `kitten_clicker`, décrit tel que le joueur le vit sur Godot 4.6.3 desktop. Ancre : `charter.yaml` (objectif, criteres_demo M1–M5 / a–h, hors_scope), `worldscan` (Cookie Clicker + Neko Atsume), `story_bible.json`, `gm_worldscan.json`. Aucun chemin de fabrication décrit — seulement l'expérience jouée.*

## 1. CE QUE LE JOUEUR VOIT

Au centre de l'écran, une **pelote** de laine ronde et douce, posée dans un **refuge** cosy en 2D aux couleurs chaudes. En haut, un **compteur de ronrons** (la monnaie) en gros chiffres, et sous lui un **taux de production automatique** (ronrons/seconde). Sur le côté, un **panneau d'achats** : adopter un chaton, améliorer la pelote, et — plus tard — un bouton de **prestige**. Une bande **objectif** affiche en clair la prochaine cible à atteindre, en texte lisible.

Quand le joueur clique, la pelote **rebondit** et un petit **+N flottant** s'élève depuis le point de clic ; des particules de laine s'échappent. Chaque chaton adopté **apparaît réellement à l'écran** sous forme de sprite animé (il dort, joue, ronronne), pas seulement comme une ligne de compteur. Les chatons portent une **identité visuelle distincte selon leur rareté** (teinte dominante, halo, badge) : un chaton commun et un chaton rare ne se confondent jamais au premier regard. Au fil de la progression, un **second lieu** se dévoile dans le refuge, agrandissant l'espace visible. Des **objets** décoratifs et utilitaires meublent la scène, et une courte liste de **quêtes** montre leurs objectifs à l'écran.

## 2. CE QUE LE JOUEUR FAIT

Le joueur **caresse la pelote** en cliquant : c'est l'action première, tactile, qui convertit chaque clic en ronrons. Avec ses ronrons, il **adopte des chatons** (chaque chaton produit ensuite des ronrons tout seul, sans clic) et **améliore la pelote** (chaque clic rapporte davantage). Très vite il rencontre une **vraie décision** : dépenser dans un chaton (revenu passif, patient) ou dans l'amélioration de la pelote (récompense l'activité au clic) — et le meilleur choix dépend de sa façon de jouer, pas d'un simple « le moins cher d'abord ».

Il **poursuit des objectifs** qui se renouvellent : atteindre un premier chaton, puis un palier, puis le seuil de prestige. En franchissant un palier il **débloque un nouveau lieu**. Au sommet de la boucle, il **accomplit un prestige** : il remet sa réserve de ronrons à zéro en échange d'un **bonus permanent**, puis **recommence la boucle** — clic, adoption, amélioration — dans un état où chaque geste rend plus qu'avant. Un **bot déterministe** peut jouer cette même boucle sans main humaine jusqu'au 3ᵉ palier et au-delà (jusqu'à l'avantage post-prestige).

## 3. CE QUE LE JOUEUR RESSENT

Une **satisfaction immédiate** au clic : la réponse visuelle et sonore est instantanée, le geste « répond ». Puis le **soulagement du premier automatisme** — « ça tourne sans moi » — quand le premier chaton fait monter le compteur seul. Vient l'**arbitrage** : le sentiment agréable d'un choix qui compte, où deux dépenses tirent la partie dans deux directions cohérentes. La **fierté de collection** monte à mesure que des chatons nommés, mignons et distincts s'accumulent et qu'un nouveau lieu s'ouvre. Le prestige procure la tension familière du genre — **sacrifier maintenant pour aller plus vite ensuite** — puis la récompense tangible de sentir la boucle **accélérer**. Rien n'inspire de peur : pas de combat, pas de game-over, pas d'échec puni ; le monde reste **calme, sûr et attachant**.

## 4. RÈGLES OBSERVABLES

- **R1** — À chaque clic sur la pelote (`pelote`), le HUD `ronrons` augmente d'au moins 1, de façon visible (charter M1). Testable : delta strict positif par clic.
- **R2** — Après l'achat d'un chaton (`acheter_chaton`), un sprite de chaton devient visible à l'écran, pas seulement un compteur qui change (charter M2). Testable : différence de pixels sur la scène.
- **R3** — Dès qu'au moins un chaton est présent, le compteur `ronrons` monte sans aucun clic (charter M3). Testable : croissance sur N frames sans input.
- **R4** — Acheter une amélioration (`acheter_amelioration`) fait monter le taux de production affiché à l'écran (charter M4). Testable : taux affiché avant < après.
- **R5** — Le jeu contient au moins 6 chatons nommés, chacun avec une identité visuelle distincte par rareté, visibles à l'écran (charter a). Testable : registre + captures distinctes par rareté.
- **R6** — Il existe au moins 2 lieux : le refuge de départ et au moins 1 lieu débloqué par la méta-progression (charter b). Testable : apparition du groupe visuel `lieu_2`.
- **R7** — Au moins 3 objets distincts sont présents et utilisables dans le jeu (charter c). Testable : registre d'objets à ≥ 3 entrées.
- **R8** — Au moins 3 petites quêtes existent, leurs objectifs visibles à l'écran dans le HUD `objectif` (charter d). Testable : registre de quêtes à ≥ 3 entrées.
- **R9** — Un son distinct se déclenche pour le clic, l'achat, le déblocage et le prestige, sur l'événement correspondant (charter e). Testable : journal de déclenchements à 4 identifiants de son distincts.
- **R10** — Le clic produit un feedback visuel (rebond de la pelote, particules ou animation) dans la même frame (charter f). Testable : différence de pixels pré/post clic sur la zone pelote.
- **R11** — La courbe de paliers porte au moins 3 valeurs de coût distinctes et strictement croissantes (charter g, règle de variance ratifiée Pierre 2026-07-21). Testable : ≥ 3 coûts distincts, variance non nulle.
- **R12** — Un bot déterministe atteint le 3ᵉ palier de progression en un nombre de ticks fini, sans intervention humaine (charter h / M5). Testable : exécution du bot, palier 3 atteint.
- **R13** — Le prestige (`prestige`) remet le compteur `ronrons` à zéro de façon visible et active un bonus permanent affiché. Testable : `ronrons` retombe à 0 et un indicateur de bonus augmente.
- **R14** — Après un prestige, rejouer le même clic sur la pelote rapporte strictement plus de ronrons qu'avant le prestige (maillon ADVANTAGE). Testable : delta/clic après > delta/clic avant.
- **R15** — Le texte du HUD `objectif` change textuellement (pas seulement en valeur) au fil de la progression, présentant des objectifs successifs distincts (maillon NEXT_GOAL). Testable : ≥ 2 textes d'objectif distincts.

## 5. PROVENANCE, ORACLE & VALIDATION

**Ancre.** `charter.yaml` (objectif : clicker de chatons mignons, boucle clic→ronrons→chatons→production auto→améliorations→lieux + méta-progression prestige, solvable par bot ; criteres_demo M1–M5 et a–h ; hors_scope : pas de combat, pas de 3D, pas de LLM au runtime, assets originaux). Sources d'exigences amont réellement présentes dans le run_dir : `worldscan`, `story_bible.json` (s2.6), `gm_worldscan.json` (s2.7) — les trois injectés et lus.

**Chaîne de falsifiabilité.** Les 21 exigences portent chacune `observation → claim → enonce → expected_proof → destination`, les trois premiers maillons distincts (contrôle `validateChaine`, lu dans `scripts/forge/upstream_schema.mjs:324`). Provenance : 17 `EXPECTED` (adresse résolvable) + 4 `ADDITIONS` (`reference: null` explicite — objets et quêtes, que ni le worldscan ni la story_bible n'ont authorés, cf. RETURN_REASON DISCOVERED de s2.6).

**Familles couvertes** (task concrète) : GAMEPLAY (boucle A→J complète, 10 rôles + DECISION `d_first_spend`), CONTENT (`content_kittens`, `content_places`, `content_objects`, `content_quests`), VISUAL (`visual_rarity`, `visual_click_feedback`), AUDIO (`audio_events`, volet `07_TESTS/oracle/core_audio.gd` + journal), LONGUEUR (`longueur_curve`, `gm_worldscan:progression`, bot au 3ᵉ palier).

**Boucle joueur.** Les 10 rôles sont chacun servis ; per-maillon vérifié contre `loop_spec.checkLoopSpec` (lu, `scripts/forge/loop_spec.mjs:162`) : G = 2 `NEXT_GOAL` `new_distinct` sur `objectif` ; F = `acheter_chaton` + `observe.appears: lieu_2` ; H = `replay:[b_click,c_response,d_reward,p_buy_kitten]` (tous rôle B..F) ; I = `prestige` + `observe.predicate: resets` ; J = `replay_ref: b_click` + `increases_more_than:b_click` ; DECISION = `options:[p_buy_kitten,p_upgrade_click]` (affordances distinctes), `policies:[idle,actif]`, `metric: ronrons`, `horizon_frames: 300`, `observe.hud: objectif`.

**Verdicts.**
- **software_verdict: OK** — appuyé sur une conformité ligne-à-ligne du bloc `prisme.json` émis à `checkPrismeDoc` / `validateChaine` / `validateProvenance` / `validateExpectedProof` (lus dans `check_prisme_manifest.mjs` et `upstream_schema.mjs`) et à `checkLoopSpec` (lu dans `loop_spec.mjs`), et de ce document aux 4 règles de forme de `check_prisme.mjs`.
- **evidence_verdict: MECHANICAL_VALIDATION_ONLY** — conformité à des oracles déterministes non-LLM.
- **claim_verdict: NO_CLAIM_ALLOWED** — aucun claim sur la qualité produit ; le reçu **faisant autorité** est celui de l'exécuteur (`run_real.py` matérialise puis lance `check_prisme_manifest`, `check_prisme`, `loop_spec`), pas produit ici.

**Références classées non ancrées (mesuré, non bloquant).** 5 références `EXPECTED` pointent vers `story_bible:` (`content_kittens`, `content_places`, `visual_rarity`, `f_unlock`) ou `gm_worldscan:` (`longueur_curve`). L'oracle `check_prisme_manifest` n'extrait des jetons d'ancrage QUE du worldscan (`worldscanTokens`, l.51) : ces 5 seront donc reportées `references_non_ancrees` là — mais elles RÉSOLVENT dans `check_amont_traversal.canonicalize` (l.88, multi-artefacts). C'est un écart entre deux oracles, pas une adresse fantôme.

**Exigences classées non actionnables.** Aucune : les 21 portent un `expected_proof{kind,statement}` valide et une `destination` ∈ {s3-decompo, s4-archi, s9-build}.

**SKIPPED_VALIDATION :**
- item : *exécution* de `check_prisme_manifest` / `check_prisme` / `loop_spec` · périmètre : `prisme.json` + ce document · statut : non fait · raison : `run: aucun` (périmètre s1-prisme) — l'exécuteur matérialise puis valide ; conformité ici vérifiée par LECTURE des sources d'oracle, pas par exécution.
- item : ancrage réel de chaque `reference` au passage cité · périmètre : 17 EXPECTED · statut : partiel · raison : `check_prisme_manifest` ne l'ancre que pour worldscan ; l'ancrage story_bible/gm_worldscan relève de `check_amont_traversal` (advisory), lancé en aval par l'exécuteur.

software_verdict: OK
evidence_verdict: MECHANICAL_VALIDATION_ONLY
claim_verdict: NO_CLAIM_ALLOWED

why_task_existed:
- problem: le charter mande une boucle clicker A→J complète et solvable pour `kitten_clicker`, dont les exigences produit falsifiables n'existaient pas encore comme artefact consommable en aval.
- oracle: activation par décision humaine (dispatch `FORGE_DISPATCH:s1-prisme:kitten_clicker-20260823a:1`) ; oracle de sortie = `check_prisme_manifest` + `check_prisme` + `loop_spec`.
- root_cause: non transmis (activation amont, pas un échec mesuré) — le run part de zéro pour ce jeu.
- action_reason: le Prisme est le producteur des lignes candidates (wiremap v2 §3) que s3/s4/s5/s9 consomment ; sans lui la chaîne n'a rien à décomposer.
- result: 21 exigences émises (17 EXPECTED / 4 ADDITIONS), boucle A→J + DECISION complète, 5 familles couvertes, 0 exigence non actionnable.
- proof: lecture de `check_prisme_manifest.mjs`, `upstream_schema.mjs`, `check_prisme.mjs`, `loop_spec.mjs`, `charter.yaml` ; conformité tracée règle par règle ci-dessus. Exécution des oracles = ressort de l'exécuteur (`run: aucun` dans mon périmètre).
- learning: l'ancrage des références dans `check_prisme_manifest` est worldscan-only alors que le contrat V4 mande des adresses `story_bible:`/`gm_worldscan:` — écart d'oracles à connaître pour ne pas lire un `references_non_ancrees` comme un défaut du Prisme.
- next_reason: chaîne ouverte vers s3-decompo (l'exécuteur dérive `loop.json` puis route les exigences) ; escalade légère : l'écart d'ancrage worldscan-only mérite un regard humain/aval, il n'invalide aucune exigence mais fausse la métrique d'ancrage.
