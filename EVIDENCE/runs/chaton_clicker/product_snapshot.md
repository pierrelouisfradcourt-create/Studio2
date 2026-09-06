# Product Snapshot — chaton_clicker

*Le produit fini, tel que le joueur le vit. Ancré sur `charter.yaml` (s0) et `worldscan.json` (s2 : Cookie Clicker + Neko Atsume). `story_bible.json`, `gm_worldscan.json`, `design/progression_contract.md` et `design/calibration.md` sont ABSENTS du run_dir — profil web/HTML, non full_godot_narratif : je le dis, je ne compense pas.*

## 1. CE QUE LE JOUEUR VOIT

Une page unique s'ouvre dans le navigateur, sans écran de titre ni tutoriel. Au centre, un **chaton dessiné**, grand et cliquable, occupe la scène. Au-dessus de lui, un **compteur de ronrons** affiche le total courant en gros chiffres, et juste en dessous un **taux de production par seconde** (« ronrons/s ») qui reste à zéro tant qu'aucun producteur n'est acquis.

Sur le côté, une **colonne d'achats** : d'abord un bouton *producteur* (un « panier de chatons ») portant son coût chiffré, puis, plus bas, un bouton *amélioration de caresse*. Chaque bouton est visiblement **grisé quand les ronrons manquent** et **s'allume quand ils suffisent**. En haut, une ligne **objectif** énonce en toutes lettres le but courant (« Atteins 15 ronrons pour ton premier panier de chatons »).

Quand un producteur est acheté, un **panier de chatons apparaît** à l'écran et le taux par seconde cesse d'être nul. Au fil des paliers, un bouton **renouveau de portée** (le prestige) devient visible. Tout ce qui est mesuré par une règle — ronrons, taux, coût, objectif — est lisible directement dans la page, jamais caché dans un état interne.

## 2. CE QUE LE JOUEUR FAIT

Le joueur **caresse le chaton** en cliquant dessus : chaque clic ajoute des ronrons, et le chaton réagit. Il regarde le compteur monter, puis **achète son premier producteur** dès qu'il en a les moyens, d'un clic sur le bouton d'achat. À partir de là, il **laisse produire** : les ronrons montent seuls, sans clic, sous ses yeux.

Très vite il **arbitre une décision** répétée : continuer à caresser pour un gain immédiat, ou investir ses ronrons dans un producteur passif qui paiera dans la durée — les deux trajectoires se voient dans le compteur. Il **achète des améliorations** qui augmentent le gain par caresse, **poursuit les objectifs successifs** affichés (un deuxième producteur, puis une amélioration), et **rejoue les mêmes gestes** dans une économie devenue plus large.

En fin de cycle, il **déclenche le renouveau de portée** : il repart de zéro ronron visible, mais chaque caresse rapporte désormais strictement plus qu'avant. Il ne joue qu'avec la souris, sur les seules cibles visibles à l'écran.

## 3. CE QUE LE JOUEUR RESSENT

D'abord une **prise tactile immédiate** : cliquer le chaton donne un retour instantané, le lien geste → nombre est évident dès la première seconde. Puis la **bascule vers l'automatique** procure un petit soulagement — « ça tourne tout seul » — qui transforme l'attente en récompense plutôt qu'en corvée.

L'arbitrage caresser / investir crée une **tension de choix** légère mais réelle : le joueur sent qu'il pilote une trajectoire, pas qu'il subit un défilement. Les objectifs qui se **renouvellent** entretiennent l'impression que « la suite existe toujours », sans jamais de game over : aucune frustration de défaite, seulement des nombres qui montent.

Le renouveau de portée procure la sensation caractéristique du genre : un **reset assumé et visible** payé par une puissance durable, si bien que la reprise semble plus rapide et plus généreuse que la précédente. L'ensemble reste **mignon et sans enjeu anxiogène** — l'attachement au chaton porte l'émotion, la progression porte la rétention.

## 4. RÈGLES OBSERVABLES

- **R1.** Au chargement, un chaton cliquable et une ligne « objectif » non vide sont visibles à l'écran, sans action préalable du joueur.
- **R2.** Cliquer la cible `caresser_chaton` augmente le compteur de ronrons affiché à chaque clic.
- **R3.** Après une caresse, le chaton réagit visuellement et le total de ronrons se met à jour à l'écran dans la foulée.
- **R4.** Quand les ronrons atteignent le coût du premier producteur, son bouton d'achat passe visiblement d'inactif à actif.
- **R5.** Un point de décision affiché oppose deux dépenses distinctes — caresser pour un gain immédiat ou acheter un producteur passif — et le choix fait diverger la courbe des ronrons.
- **R6.** Cliquer `acheter_producteur` fait apparaître un panier de chatons et fait monter les ronrons sans aucun clic.
- **R7.** Une fois le premier producteur acquis, le texte de l'objectif affiché change pour une cible différente de celle du départ.
- **R8.** Un second objectif, textuellement distinct des précédents, vise ensuite une amélioration qui augmente le gain par caresse.
- **R9.** Le coût affiché d'un producteur augmente visiblement après chacun de ses achats.
- **R10.** Dans l'état enrichi, rejouer les mêmes gestes (caresser, laisser produire, encaisser, acheter) relance la progression des ronrons.
- **R11.** Cliquer `renouveau_portee` fait retomber le compteur de ronrons à zéro à l'écran.
- **R12.** Après un renouveau de portée, une même caresse rapporte strictement plus de ronrons qu'avant le reset, mesuré sur l'action identique.
