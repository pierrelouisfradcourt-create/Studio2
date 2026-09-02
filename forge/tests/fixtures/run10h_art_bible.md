---
styles: [storybook-flat, warm-pastel]
mood_keywords: [cozy, cute, warm, gentle, hand-drawn, pastel, wholesome, inviting]
---

# Art Bible — kitten_clicker (v0.1, round 1)

> Etape s2.5 Art Director. Identite visuelle HERITEE (World Scan s2 + Story Bible s2.6) et
> DECIDEE (style reel, regles d'assets, silhouettes, affordance, lisibilite UI, etats).
> Oracle : `forge/check_artbible.mjs`. claim_verdict: NO_CLAIM_ALLOWED.

## 1. IDENTITE VISUELLE

Un **livre d'images chaleureux et vivant**, pas un tableau de bord. Style **storybook-flat** :
aplats doux dessines a la main, contours arrondis, palette pastel tiede, zero gradient
metallique, zero chiffre-roi. Le refuge est un petit theatre 2D vu de face/trois-quarts ou
**chaque objet a une place fixe** et **chaque achat transforme visiblement la scene**.

Palette de base (portee 1, saison printemps) : bois miel (#C9A66B), creme (#FBF3E4), vert
tendre du jardin (#A8D5A2), rose pelote (#E8A0B4), bleu-ciel doux (#BFE3F2), accents dores
reserves aux **rares** et aux **coeurs de prestige** (#E7C24A). Chaque **portee** de prestige
change la **saison** (printemps -> ete -> automne) : la palette se decale (chauds pour l'ete,
ambres pour l'automne) sans changer les silhouettes — on VOIT qu'on a change de portee.

Lisibilite avant joliesse : contraste maximal sur l'OBJECTIF (haut de l'ecran), une seule
affordance mise en evidence a la fois, cout ET effet toujours lisibles sous un bouton. La
mignonnerie est un moyen d'attachement (collection de chatons), la clarte est la regle
maitresse.

## 2. RATIONALE

Trois raisons portent chaque choix, toutes tracables a une source ou a une decision produit :

1. **Herite du genre (World Scan).** Neko Atsume prouve qu'une esthetique de chats adorables +
   UI minimaliste + collection soutient la retention (`worldscan:games[1].retention_answer`) ;
   Cookie Clicker que le feedback immediat au clic et les deblocages VISUELS spectaculaires sont
   le carburant (`worldscan:games[0].retention_answer`, `worldscan:games[0].loops.minute_1`).
   Les trois references nomment le MEME risque : *interface statique = plateau = compulsion qui
   chute* (`worldscan:games[0].retention_answer`, `worldscan:games[2].retention_answer`). D'ou
   la regle maitresse produit : **UNLOCK != +X %** — chaque progression doit CHANGER l'ecran.

2. **Herite du monde (Story Bible).** Un monde mignon, non violent, sans etat de defaite
   (`story_bible:coherence_rules`, `story_bible:stakes`) ; une colonie qui s'etend refuge ->
   jardin -> grenier (`story_bible:context`) ; des chatons distingues par rarete, >= 6, sans
   identite individuelle fournie (`story_bible:characters`) — donc l'artiste DECIDE les robes.
   Regle de visibilite absolue : un chaton n'apparait sur la scene QUE s'il est adopte ; sinon
   il n'existe que comme silhouette « ? » dans l'album (`story_bible:coherence_rules`).

3. **Decide par l'art (cette etape).** Le style storybook-flat, la palette, les etats de lieux
   (LOCKED/AVAILABLE/ACTIVE/FULL), les etats de chatons (dort/joue/grimpe/chasse/se frotte/part
   adopte), les silhouettes « ? » de l'album, les regles d'affordance et la hierarchie UI
   OBJECTIF -> ACTION -> CONSEQUENCE -> PROCHAINE POSSIBILITE. La couverture reelle est portee
   par les BESOINS VISUELS structures ci-dessous et les asset_requests — **pas par cette prose**
   (la prose n'est jamais lue par l'oracle ; seule la donnee structuree l'est).

## 3. BESOINS VISUELS

Chaque entite visuelle distincte du jeu, avec son entity_role et si sa couverture est requise.
`required:true` des qu'une entite est citee par une source heritee ou centrale a une condition
de victoire/defaite/score/progression ; `required:false` seulement pour le decor cosmetique.

```json
{
  "visual_requirements": [
    {
      "id": "kitten_tabby",
      "entity_role": "npc",
      "required": true,
      "description": "Chaton commun robe tigree brune (tabby) — le premier accueilli ; sort du panier a l'accueil, etats dort/joue/se frotte."
    },
    {
      "id": "kitten_gris",
      "entity_role": "npc",
      "required": true,
      "description": "Chaton commun robe grise unie — 2e accueilli, joue avec l'arbre du jardin."
    },
    {
      "id": "kitten_calico",
      "entity_role": "npc",
      "required": true,
      "description": "Chaton commun robe calicot tricolore — comportement propre : grimpe."
    },
    {
      "id": "kitten_tuxedo",
      "entity_role": "npc",
      "required": true,
      "description": "Chaton commun robe smoking noir & blanc — chasse les papillons des fleurs."
    },
    {
      "id": "kitten_siamois",
      "entity_role": "npc",
      "required": true,
      "description": "Chaton commun robe siamois creme a points — dort dans la niche la nuit."
    },
    {
      "id": "kitten_roux",
      "entity_role": "npc",
      "required": true,
      "description": "Chaton commun robe rousse unie (orange) — 6e robe de base, complete les 6 silhouettes communes de l'album."
    },
    {
      "id": "kitten_rare_gold",
      "entity_role": "npc",
      "required": true,
      "description": "Chaton rare dore (niveau 2) — 1re silhouette doree de l'album, animation unique, adopte a 400 R + 30 C."
    },
    {
      "id": "kitten_rare_silver",
      "entity_role": "npc",
      "required": true,
      "description": "Chaton rare argente (niveau 2) — 2e silhouette doree, animation unique."
    },
    {
      "id": "kitten_rare_copper",
      "entity_role": "npc",
      "required": true,
      "description": "Chaton rare cuivre (niveau 2) — 3e silhouette doree ; l'adopter complete l'album (fin du jeu)."
    },
    {
      "id": "pelote",
      "entity_role": "item",
      "required": true,
      "description": "Pelote de laine centrale dans le panier — cible du clic (la caresse) ; roule/rebondit au clic ; recoit un ruban apres le 1er prestige (marqueur de portee)."
    },
    {
      "id": "refuge",
      "entity_role": "environment",
      "required": true,
      "description": "Interieur chaleureux du refuge — decor de depart ; contient le panier, 1 coussin, une fenetre vers le jardin ferme."
    },
    {
      "id": "jardin",
      "entity_role": "environment",
      "required": true,
      "description": "Jardin exterieur — lieu 2 ; herbe, 3 emplacements de chatons, 4 emplacements d'objets, lucarne du grenier visible ; etats LOCKED / AVAILABLE / ACTIVE / FULL."
    },
    {
      "id": "grenier",
      "entity_role": "environment",
      "required": true,
      "description": "Grenier — lieu 3 (niveau 2, apres 1er prestige) ; lumiere de lucarne, poussiere ; etat LOCKED (lucarne « ? ») puis ouvert."
    },
    {
      "id": "coussin",
      "entity_role": "item",
      "required": true,
      "description": "Coussin — 1er emplacement de chaton dans le refuge ; vide au depart, occupe quand un chaton s'y couche."
    },
    {
      "id": "banc",
      "entity_role": "item",
      "required": true,
      "description": "Banc de jardin (decision A) — un chaton y dort : production passive lisible."
    },
    {
      "id": "fleurs",
      "entity_role": "item",
      "required": true,
      "description": "Massif de fleurs (objet de jardin) — papillons ; cliquable (les papillons s'envolent)."
    },
    {
      "id": "jouet",
      "entity_role": "item",
      "required": true,
      "description": "Jouet pelote-souris — un chaton le poursuit (course) ; cliquable (le lancer)."
    },
    {
      "id": "niche",
      "entity_role": "item",
      "required": true,
      "description": "Niche — un chaton y dort la nuit (cycle jour/nuit leger global)."
    },
    {
      "id": "gamelle",
      "entity_role": "item",
      "required": true,
      "description": "Gamelle de croquettes (niveau 2, au jardin) — les chatons du jardin mangent ; cliquable (remplir)."
    },
    {
      "id": "arbre",
      "entity_role": "item",
      "required": true,
      "description": "Arbre du jardin — un chaton grimpe / y joue ; element fixe du lieu 2."
    },
    {
      "id": "album",
      "entity_role": "ui",
      "required": true,
      "description": "Panneau album — 9 silhouettes « ? » (6 communes + 3 dorees) au depart, 0 coloree ; une silhouette se colore a l'adoption ; porte l'objectif final « Album complet »."
    },
    {
      "id": "hud",
      "entity_role": "ui",
      "required": true,
      "description": "Bandeau HUD — hierarchie OBJECTIF (haut, plus grande police, contraste max) puis cout+effet puis ronrons/places/coeurs/croquettes puis ligne « Ensuite : … » ; conteneurs VBox/HBox, aucun chevauchement."
    },
    {
      "id": "affordances",
      "entity_role": "ui",
      "required": true,
      "description": "Boutons d'action (accueillir, placer, ouvrir_jardin, amenager, caresse_longue, prestige, adopter_rare…) — un seul mis en evidence a la fois ; cout ET effet lisibles dessous ; etat grise + raison quand indisponible."
    },
    {
      "id": "icon_ronrons",
      "entity_role": "icon",
      "required": true,
      "description": "Icone ronrons (petite note de ronron / coeur) — devant le compteur hud.ronrons."
    },
    {
      "id": "icon_croquettes",
      "entity_role": "icon",
      "required": true,
      "description": "Icone croquettes (niveau 2) — devant hud.croquettes."
    },
    {
      "id": "icon_coeur",
      "entity_role": "icon",
      "required": true,
      "description": "Icone coeur de prestige — devant hud.coeurs (+1 par portee, +25 % additif)."
    },
    {
      "id": "fx_click",
      "entity_role": "effect",
      "required": true,
      "description": "Feedback de clic sur la pelote — pulse / particule / tremblement a CHAQUE clic (critere f)."
    },
    {
      "id": "fx_unlock",
      "entity_role": "effect",
      "required": true,
      "description": "Feedback d'apparition — eclat/sparkle quand une nouvelle affordance ou un nouveau lieu apparait."
    },
    {
      "id": "fx_prestige",
      "entity_role": "effect",
      "required": true,
      "description": "Effet de prestige — depart joyeux des chatons adoptes, album qui se colore, changement de saison de la carte."
    },
    {
      "id": "fx_heart",
      "entity_role": "effect",
      "required": true,
      "description": "Coeur flottant — apparait sur « brosser » (ronron x2 pendant 10 s) et au prestige."
    },
    {
      "id": "ruban",
      "entity_role": "item",
      "required": true,
      "description": "Ruban (skin de portee 2) — accessoire ajoute sur le panier et sur les chatons apres le 1er prestige ; rend « on en est a la 2e portee » visible a l'ecran."
    },
    {
      "id": "ambient_critters",
      "entity_role": "effect",
      "required": false,
      "description": "Petite vie ambiante purement cosmetique — oiseau qui passe, vent dans l'herbe, poussiere dans la lumiere du grenier ; agrement, non lie a une condition de victoire/defaite/score (required:false assume)."
    }
  ]
}
```

## heritage_worldscan

Herite du World Scan (s2), non reinvente — adresses citees :

- **Esthetique cible du genre** : chats adorables, sons mignons, UI minimaliste
  (`worldscan:games[1].retention_answer` — Neko Atsume). Fonde le registre "mignon + lisible".
- **Collection comme moteur de retention** : "quels chats viendront ?", variable reward, Catbook
  (`worldscan:games[1].loops.hour_5`, `worldscan:games[1].objectives[0].player_goal`). Fonde
  l'album a silhouettes « ? » et la promesse visuelle des rares dores.
- **Feedback immediat au clic + deblocages visuels** : "Feedback immediat : compteur augmente",
  "Deblocages spectaculaires visuels" (`worldscan:games[0].loops.minute_1`,
  `worldscan:games[0].retention_answer` — Cookie Clicker). Fonde `fx_click` et `fx_unlock`.
- **Risque nomme = interface statique** : "plateau monotone si interface statique",
  "monotonie du tick-based si interface reste statique"
  (`worldscan:games[0].retention_answer`, `worldscan:games[2].retention_answer`). Fonde la
  regle "chaque achat transforme la scene" et les saisons par portee.
- **Sons de production subtils qui s'intensifient** (`worldscan:games[2].retention_answer` —
  Kittens Game) : herite pour l'audio (procedural, cf. `## asset_rules`), pas un asset visuel.

## heritage_story_bible

Herite de la Story Bible (s2.6), non reinvente — adresses citees :

- **Le monde** : colonie de chatons qui se developpe refuge -> jardin -> grenier ; registre
  mignonnerie (`story_bible:context`). Fonde les 3 lieux (`refuge`, `jardin`, `grenier`).
- **L'enjeu** : croissance/peuplement + completion de l'album, aspirationnel et sans defaite
  (`story_bible:stakes`). Fonde l'album comme objectif final visible et l'absence d'ennemi.
- **Les personnages** : soigneur-adoptant (le joueur) ; chatons par rarete, >= 6 nommes, AUCUNE
  identite individuelle fournie (`story_bible:characters`) — l'artiste decide les 6 robes de
  base (tabby, gris, calicot, smoking, siamois, roux) et 3 rares dores (or, argent, cuivre).
- **Regle de coherence absolue** : un chaton n'apparait sur la scene QUE s'il est adopte, sinon
  silhouette « ? » dans l'album ; ton mignon non violent ; geographie limitee a 3 lieux
  (`story_bible:coherence_rules`). Contrainte dure sur `album` et sur tous les `npc`.
- Sections `story_bible` NOT_GROUNDED (chronology/factions/relations/events) : aucune matiere
  narrative heritee — l'art ne fabrique donc ni faction ni evenement, conforme a l'absence.

## visual_language

DECIDE. Style **storybook-flat 2D** (Godot, sprites du repo). Aplats doux, contours arrondis
2-3 px, ombres portees tres legeres, pas de PBR ni de metal. Vue de face/trois-quarts, scene
en couches (fond lieu > objets > chatons > VFX > HUD). Silhouettes lisibles a petite taille :
un chaton = un blob arrondi + oreilles + queue, reconnaissable a la robe seule. Cohesion : une
seule famille de traits pour tout (chatons, objets, UI). Les chiffres n'ont pas de mise en
scene "epique" — ils sont des mesures discretes (cf. `## ui_readability`).

## affordance_rules

DECIDE. Une affordance = une invitation lisible a agir.
- **Une seule** affordance mise en evidence a la fois (halo/echelle), les autres discretes.
- Un bouton porte TOUJOURS son **cout** et son **effet** dessous, sans chevauchement (VBox).
- **Aucun bouton mort** : indisponible => grise + **raison** ("il te faut 20 ronrons",
  "plus de place — ouvre un lieu") + la possibilite qui la leve.
- Une possibilite qui n'existe pas encore **n'est pas affichee grisee, elle est absente**
  (`placer`, `ouvrir_jardin`, `prestige` apparaissent au moment ou elles deviennent possibles) ;
  son **apparition** declenche `fx_unlock`.
- La pelote n'est pas un bouton : c'est une caresse (surface cliquable) qui fait reagir le monde.

## character_states

DECIDE. Etats visuels par entite (aucune identite individuelle heritee — robes decidees ici).

- **Chatons (npc)** : en_panier (avant accueil) -> sort_du_panier (animation d'accueil) ->
  assis -> place. Comportements de lieu : dort (coussin/banc/niche), joue (arbre), grimpe,
  chasse (papillons), se_frotte (caresse longue), mange (gamelle, N2), part_adopte (prestige).
  Chaque robe (tabby/gris/calicot/smoking/siamois/roux + or/argent/cuivre) = meme squelette,
  texture differente.
- **Album** : chaque chaton a 2 etats — silhouette « ? » (non gagne) et portrait colore (gagne).
  Les 3 rares sont des silhouettes **dorees** « ? ». JAMAIS un chaton non gagne sur la scene.
- **Lieux** : LOCKED (volets clos, « ? », raison visible) / AVAILABLE (entrouvert, cout lisible)
  / ACTIVE (ouvert, emplacements vides) / FULL (emplacements occupes, animations de lieu).
- **Objets** : vide/inactif -> installe -> en_usage (un chaton l'utilise).
- **Saison** (par portee) : re-skin de palette de refuge+jardin+grenier ; skin **ruban** ajoute
  sur panier et chatons des la portee 2.

## ui_readability

DECIDE. Hierarchie de lecture imposee, de haut en bas et par contraste :
1. **OBJECTIF** (`hud.objectif`) — plus grande police, contraste maximal, tout en haut.
2. **PROCHAINE POSSIBILITE** (`hud.ensuite`, ligne « Ensuite : … ») juste sous l'objectif.
3. **ACTION** — l'unique affordance mise en evidence dans la scene.
4. **CONSEQUENCE** — cout ET effet sous le bouton, sans chevauchement.
5. **MESURES** — ronrons / places (occupees/totales) / coeurs / croquettes : petits, en bas ou
   en bandeau, precedes de leur icone ; ce sont des mesures, jamais des progressions.
Contraintes dures : conteneurs VBox/HBox (aucune position absolue) ; texte toujours au-dessus
d'un aplat opaque (jamais sur un motif charge) ; l'album est un panneau lateral toujours visible.

## world_constraints

DECIDE. Limites du monde a respecter par tout asset et toute scene :
- Exactement **3 lieux** (refuge, jardin, grenier), pas au-dela (contenu > niveau 2 differe).
- **2D uniquement** (sprites), cible **Godot 4.6.3 desktop**, fenetre GPU (jamais headless).
- Aucun asset genere par API externe ni telecharge : sprites du repo, audio procedural in-projet.
- Aucun chaton non gagne visible hors album ; aucune violence, aucun etat de defaite.
- Palette et saisons definies ici font foi ; les rares et les coeurs sont les SEULS emplois du dore.

## asset_rules

DECIDE. Regles de production et de nommage des assets :
- **Format** : sprites 2D PNG, fond transparent, un sprite-sheet par chaton (etats/animations),
  un sprite par objet avec ses etats, un fond par lieu et par saison.
- **Style tag** : `storybook-flat` pour tout (declare au frontmatter) ; coherence = un seul style.
- **Icones** : jeu d'icones HUD homogenes (ronrons, croquettes, coeur) memes traits que la scene.
- **VFX** : `fx_click` / `fx_unlock` / `fx_prestige` / `fx_heart` — particules simples, pas de
  post-processing lourd (desktop, mais leger). Aucun VFX ne masque l'objectif ni un bouton.
- **Audio** : **procedural, produit dans le projet** (clic / achat / deblocage / prestige
  distincts), preuve = `07_TESTS/oracle/core_audio.gd` — donc **aucun asset audio a sourcer**,
  aucune `asset_request` de type audio (herite `worldscan:games[2].retention_answer`,
  charter criteres_demo (e)).
- **Resolution catalogue** : le catalogue ne contient aujourd'hui **aucun** asset 2D/godot ; les
  requetes resolvent donc BLOCKED en resolution (advisory) — legitime, pas un manque de couverture.
