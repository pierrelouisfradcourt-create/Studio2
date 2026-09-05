---
styles: [flat-cute-2d, cozy-storybook, warm-pastel]
mood_keywords: [cozy, warm, cute, wholesome, calm, soft, adorable, pastel, safe, charming]
---

# Kitten Clicker — Art Bible (Art Director, s2.5)

*Identité visuelle du produit décrit dans `product_snapshot.md` (s1). Ancre unique : le Prisme
Produit (ce que le joueur VOIT / FAIT / RESSENT + les 15 règles observables R1–R15). Cet
artefact ne génère ni ne télécharge aucun octet : il fixe le style et traduit chaque entité
visuelle en `asset_request` structurée (Asset Contract V0.1). Aucun jugement esthétique n'est
certifié ici — seule la couverture besoin↔requête est mécanique (cf. `check_artbible.mjs`).*

## 1. IDENTITÉ VISUELLE

**Direction** : un refuge à chats en 2D vectoriel, chaleureux et lisible à **640×480**. Tout est
dessiné en **SVG** (formes simples, aplats, contours doux) que le builder écrit lui-même et que
Godot 4 importe comme texture — aucun générateur d'image 2D n'existe dans le studio.

**Palette** — bois clair et laine, tons chauds et rassurants :
- Fonds / refuge : crème `#FFF3E0`, bois `#D7A86E`, ombre douce `#C98A5E`.
- Laine / accents : corail `#F4978E`, rose poudré `#F7C5CC`, moutarde douce `#F6C453`.
- Texte / contours : brun chaud `#5A3E2B` (jamais du noir pur — cohérence « calme »).
- Rareté (halo/badge des chatons, échelle froide→précieuse) : commun gris `#B8B8B8`,
  peu-commun vert `#8BC48A`, rare bleu `#6FA8DC`, épique violet `#B07CC6`, légendaire or `#F2B705`.

**Formes** : rondeurs partout (pas d'angle vif), contour de 2–3 px brun chaud pour la lisibilité
à basse résolution, silhouettes reconnaissables **au premier regard** (un chaton ≠ un objet ≠ un
bouton même en 32–64 px). Chaque tier de rareté se distingue par **teinte dominante + halo +
badge** (R5), jamais par un simple détail — la différence doit survivre à la réduction de taille.

**Contraintes techniques communes à tous les assets** : `format: 2D`, `runtime: godot`,
type `sprite`/`icon` (SVG importé en texture), licence `CC0-1.0` (assets originaux, charter
`hors_scope`), pas de plafond de taille (SVG texte = trivial). Vue de face / 3/4 douce (le jeu
n'a ni défilement ni navigation spatiale).

## 2. RATIONALE

Chaque choix découle d'une section du Prisme, jamais d'un goût libre :

- **« calme, sûr, attachant » · « rien n'inspire de peur »** (§3 RESSENT) → palette chaude
  pastel, contours bruns et non noirs, rondeurs, zéro imagerie de conflit. Le style *porte* le
  ressenti visé, il ne le contredit pas.
- **« satisfaction immédiate au clic », « la pelote rebondit », « +N flottant », « particules
  de laine »** (§1/§3, R10) → un asset d'**effet** dédié (touffe de laine + chiffre flottant)
  pour que le feedback de clic soit un objet visuel réel, pas une supposition du builder.
- **« identité visuelle distincte selon leur rareté … ne se confondent jamais »** (§1, R5) →
  **un asset par tier de rareté** (5), chacun avec sa teinte/halo/badge — refuser une requête
  générique « un chaton » qui masquerait l'exigence de distinction.
- **« un second lieu se dévoile », « débloque un nouveau lieu »** (§1/§2, R6) → deux assets
  d'environnement distincts (refuge de départ + lieu_2), pour que le déblocage soit un vrai
  changement visible d'espace.
- **« des objets décoratifs et utilitaires meublent la scène »** (§1, R7 ≥3) → trois objets
  concrets et distincts (gamelle, griffoir, coussin), thématiquement cohérents avec un refuge.
- **« compteur de ronrons », « panneau d'achats », « bande objectif », « bouton de prestige »,
  « indicateur de bonus »** (§1, R1/R4/R8/R13/R15) → un kit UI cohérent (icône monnaie, cadre
  de stats, boutons d'action, bannière d'objectif) partageant palette et rondeurs, pour que le
  HUD lise à 640×480 et appartienne au même monde que la scène.

**Lisibilité à 640×480 = contrainte de premier ordre**, pas un raffinement : silhouettes
simples, fort contraste teinte/contour, aucun détail qui disparaît sous 32 px. Le son (R9)
n'est **pas** une entité visuelle : hors périmètre de cet Art Bible (traité par le volet audio
du build), signalé en SKIPPED_VALIDATION.

**Garde-fou honnêteté** : aucune de ces requêtes n'est censée « résoudre » contre le catalogue
existant — le studio n'a pas d'asset SVG chat original catalogué. La statistique de résolution
sera donc `BLOCKED` (advisory), ce qui est **légitime** (le builder écrira les SVG) et n'est
jamais confondu avec la couverture besoin↔requête, seule dimension qui conditionne le verdict.

## 3. BESOINS VISUELS

Chaque entité visuelle distincte du Prisme, avec son `entity_role` et si sa couverture est
`required` (une entité citée par une règle R ou centrale au score/à la boucle → `required:true` ;
seul le décor véritablement cosmétique → `required:false`).

```json
{
  "visual_requirements": [
    { "id": "pelote", "entity_role": "item", "required": true, "description": "Pelote de laine ronde au centre : cible de clic première (R1, R10). Boule douce en aplat corail/rose, quelques brins de laine, contour brun. Doit lire comme 'cliquable' et supporter un état 'rebond'." },
    { "id": "kitten_common", "entity_role": "collectible", "required": true, "description": "Chaton commun (R2, R5) : silhouette ronde mignonne, teinte grise dominante, halo/badge gris #B8B8B8. Assis/endormi, vue de face." },
    { "id": "kitten_uncommon", "entity_role": "collectible", "required": true, "description": "Chaton peu-commun (R5) : même base mais teinte et halo/badge vert #8BC48A, un accent distinctif (col, marque) pour ne jamais le confondre avec le commun." },
    { "id": "kitten_rare", "entity_role": "collectible", "required": true, "description": "Chaton rare (R5) : teinte et halo/badge bleu #6FA8DC, motif plus marqué (rayures/étoile). Distinction immédiate à petite taille." },
    { "id": "kitten_epic", "entity_role": "collectible", "required": true, "description": "Chaton épique (R5) : teinte et halo/badge violet #B07CC6, halo plus lumineux, petit ornement (nœud, gemme)." },
    { "id": "kitten_legendary", "entity_role": "collectible", "required": true, "description": "Chaton légendaire (R5) : teinte et halo/badge or #F2B705, halo doré marqué, ornement précieux (couronne/étoiles) — le plus prestigieux du set." },
    { "id": "refuge", "entity_role": "environment", "required": true, "description": "Lieu de départ (R6) : intérieur cosy en 2D, bois clair et crème, sol/mur chauds servant de fond au refuge. Cadre pour poser pelote, chatons et objets, lisible à 640x480." },
    { "id": "lieu_2", "entity_role": "environment", "required": true, "description": "Second lieu débloqué par la méta-progression (R6) : fond distinct du refuge (ex. véranda/jardin ensoleillé) agrandissant l'espace visible, même langage chaud mais reconnaissable comme un NOUVEL endroit." },
    { "id": "obj_food_bowl", "entity_role": "item", "required": true, "description": "Objet utilitaire (R7) : gamelle/écuelle ronde de croquettes, aplats chauds, silhouette simple lisible en petit." },
    { "id": "obj_scratching_post", "entity_role": "item", "required": true, "description": "Objet utilitaire (R7) : arbre à chat / griffoir en bois et corde, vertical, distinct de la gamelle et du coussin." },
    { "id": "obj_cushion_bed", "entity_role": "item", "required": true, "description": "Objet (R7) : coussin/panier moelleux où un chaton peut dormir, forme ronde molletonnée, teinte pastel distincte." },
    { "id": "fx_click_feedback", "entity_role": "effect", "required": true, "description": "Feedback de clic (R10) : petite touffe/particules de laine qui s'échappent + chiffre '+N' flottant montant depuis le point de clic. Éphémère, lisible, non intrusif." },
    { "id": "icon_ronrons", "entity_role": "icon", "required": true, "description": "Icône de la monnaie 'ronrons' (R1) : petit glyphe (patte/cœur/note de ronron) affiché à côté du compteur, reconnaissable à 24-32 px." },
    { "id": "ui_stats_hud", "entity_role": "ui", "required": true, "description": "Cadre HUD haut (R1, R4, R13) : zone affichant le compteur de ronrons, le taux de production/seconde et l'indicateur de bonus de prestige. Panneau doux à coins ronds, fort contraste texte/fond." },
    { "id": "ui_action_buttons", "entity_role": "ui", "required": true, "description": "Boutons d'action du panneau d'achats (R2, R4, R13) : adopter un chaton, améliorer la pelote, prestige. Fond de bouton arrondi + emplacement d'icône, états normal/hover/désactivé implicites par le style." },
    { "id": "ui_objectif_banner", "entity_role": "ui", "required": true, "description": "Bande 'objectif' et liste de quêtes (R8, R15) : bannière lisible affichant la cible courante et jusqu'à 3 quêtes. Fond doux, hiérarchie de texte claire, se relit quand l'objectif change." },
    { "id": "ambient_decor", "entity_role": "environment", "required": false, "description": "Fioritures d'ambiance purement cosmétiques (plantes en pot, rai de lumière à la fenêtre, tapis) — agréables mais NON citées par une règle observable ; leur absence ne casse aucun R. Optionnel assumé, aucune requête produite." }
  ]
}
```
