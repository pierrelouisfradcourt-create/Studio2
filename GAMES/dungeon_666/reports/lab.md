# Labo du feel — mesure comparée des variantes D5 / D8 / D9

Généré par `node tools/playtest.mjs --lab-report` le 2026-10-01T13:30:20.258Z. Graines 1 à 20 par variante et par joueur, objectif : battre la section 1 (Gardien à l'étage 18), limite 30 min de temps simulé, arrêt à la première mort. 260 parties jouées en 20.9 s.

**Ce rapport ne tranche pas D5, D8 ni D9.** Les bots mesurent des conséquences — dégâts reçus, rythme, durée des salles, temps passé figé. Ils ne mesurent pas le plaisir, la lisibilité ressentie, ni la sensation d'impact : ce sont des questions de pouce et d'œil humains. Les décisions restent ouvertes ; ces chiffres servent à repérer une variante qui casserait le jeu (dégâts reçus qui explosent, rythme effondré), pas à choisir la plus agréable.

Une seule variante change à la fois ; les deux autres axes restent à leur référence (Fin du dash · Global · Mobile). Entre parenthèses : l'écart à la référence, pour le même joueur. « min réelle » = minute d'images affichées (gel compris), seule base comparable entre gel global et gel local. « Temps figé » = part des images où le héros est figé par un gel d'impact.

## D5 · Frappe de dash

- **Fin du dash** — Attaquer dans le dernier 45 % du dash ou juste après.
- **Tout le dash** — Attaquer à n'importe quel moment du dash le coupe en frappe.
- **Après le dash** — Le dash va au bout ; une attaque juste après devient frappe.

| Variante | Joueur | Section battue | Morts | Dégâts / salle | Dégâts / min réelle | Coups reçus / min réelle | Salle (s réelles, méd.) | Gardien (s, méd.) | Attaques / min | Frappes de dash / min | Dash / min | Temps figé |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Fin du dash (réf.) | skilled | 100 % | 0 % | 2.3 | 7.2 | 0.36 | 15.1 | 51.2 | 57.1 | 8.76 | 30.2 | 7.4 % |
| Fin du dash (réf.) | dashFrappe | 60 % | 40 % | 11.7 | 47.8 | 1.71 | 13.8 | 25.9 | 78.0 | 27.37 | 27.5 | 9.1 % |
| Tout le dash | skilled | 100 % | 0 % | 2.3 (=) | 7.2 (=) | 0.36 (=) | 15.1 (=) | 51.2 (=) | 57.1 (=) | 8.76 (=) | 30.2 | 7.4 % |
| Tout le dash | dashFrappe | 20 % | 80 % | 15.0 (+28 %) | 65.5 (+37 %) | 2.35 (+37 %) | 12.8 (-7 %) | 19.8 (-24 %) | 81.9 (+5 %) | 27.07 (-1 %) | 27.2 | 9.4 % |
| Après le dash | skilled | 100 % | 0 % | 2.3 (=) | 7.2 (=) | 0.36 (=) | 15.1 (=) | 51.2 (=) | 57.1 (=) | 8.76 (=) | 30.2 | 7.4 % |
| Après le dash | dashFrappe | 90 % | 10 % | 5.3 (-55 %) | 20.7 (-57 %) | 0.92 (-46 %) | 13.5 (-2 %) | 28.0 (+8 %) | 74.8 (-4 %) | 25.87 (-5 %) | 28.3 | 8.6 % |

Lecture : Le bot skilled ne presse jamais l'attaque PENDANT un dash : pour lui les trois variantes doivent donner des chiffres identiques (c'est un contrôle, pas un résultat). La ligne « dash puis frappe » mesure le prix et le gain de chaque variante pour un joueur qui enchaîne vite : « Tout le dash » coupe la ruée plus tôt (esquive plus courte, frappe plus tôt), « Après le dash » garde toute l'esquive et frappe plus tard. Attention : l'habitude scriptée tape l'attaque au début de CHAQUE dash, y compris les dash d'esquive — c'est le pire cas pour une variante qui coupe la ruée ; un joueur humain choisit quand frapper, et peut apprendre à ne pas taper pendant une esquive.

## D8 · Gel d'impact

- **Global** — Toute la scène se fige à l'impact.
- **Local** — Seuls le héros et ses cibles se figent ; le reste continue.

| Variante | Joueur | Section battue | Morts | Dégâts / salle | Dégâts / min réelle | Coups reçus / min réelle | Salle (s réelles, méd.) | Gardien (s, méd.) | Attaques / min | Frappes de dash / min | Dash / min | Temps figé |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Global (réf.) | skilled | 100 % | 0 % | 2.3 | 7.2 | 0.36 | 15.1 | 51.2 | 57.1 | 8.76 | 30.2 | 7.4 % |
| Global (réf.) | masher | 5 % | 95 % | 39.1 | 204.9 | 9.38 | 10.4 | 28.9 | 136.1 | 5.85 | 9.0 | 12.0 % |
| Local | skilled | 95 % | 5 % | 3.4 (+48 %) | 11.4 (+57 %) | 0.55 (+53 %) | 14.4 (-5 %) | 48.2 (-6 %) | 58.6 (+3 %) | 9.17 (+5 %) | 30.9 | 7.7 % |
| Local | masher | 0 % | 100 % | 28.9 (-26 %) | 191.9 (-6 %) | 10.41 (+11 %) | 8.4 (-19 %) | — | 138.8 (+2 %) | 5.95 (+2 %) | 9.5 | 12.3 % |

Lecture : En gel GLOBAL, le temps de la simulation s'arrête : les durées sont donc comparées en temps RÉEL (images affichées). En gel LOCAL, projectiles et autres ennemis continuent pendant que le héros est figé : la part de temps figé et les dégâts reçus disent ce que coûte ce gel, pas s'il est plus agréable.

## D9 · Mobilité du combo

- **Ancré** — 20 % de vitesse, annulations tardives.
- **Mobile** — 50 % de vitesse, annulations de référence.
- **Fluide** — 75 % de vitesse, annulations très tôt.

| Variante | Joueur | Section battue | Morts | Dégâts / salle | Dégâts / min réelle | Coups reçus / min réelle | Salle (s réelles, méd.) | Gardien (s, méd.) | Attaques / min | Frappes de dash / min | Dash / min | Temps figé |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Ancré | skilled | 100 % | 0 % | 3.0 (+33 %) | 9.7 (+35 %) | 0.51 (+41 %) | 15.3 (+1 %) | 43.1 (-16 %) | 57.1 (=) | 9.33 (+7 %) | 30.6 | 7.3 % |
| Ancré | masher | 0 % | 100 % | 25.7 (-34 %) | 154.1 (-25 %) | 8.70 (-7 %) | 9.1 (-12 %) | — | 130.4 (-4 %) | 5.76 (-2 %) | 9.0 | 11.0 % |
| Mobile (réf.) | skilled | 100 % | 0 % | 2.3 | 7.2 | 0.36 | 15.1 | 51.2 | 57.1 | 8.76 | 30.2 | 7.4 % |
| Mobile (réf.) | masher | 5 % | 95 % | 39.1 | 204.9 | 9.38 | 10.4 | 28.9 | 136.1 | 5.85 | 9.0 | 12.0 % |
| Fluide | skilled | 100 % | 0 % | 1.3 (-43 %) | 4.6 (-36 %) | 0.31 (-15 %) | 14.2 (-6 %) | 35.5 (-31 %) | 56.5 (-1 %) | 7.85 (-10 %) | 27.5 | 7.5 % |
| Fluide | masher | 15 % | 85 % | 35.0 (-10 %) | 209.8 (+2 %) | 9.30 (-1 %) | 9.2 (-12 %) | 23.6 (-18 %) | 149.2 (+10 %) | 4.38 (-25 %) | 8.9 | 11.9 % |

Lecture : Ancré : 20 % de vitesse en frappant et annulations tardives ; Fluide : 75 % et annulations très tôt. Les attaques par minute mesurent le rythme du combo, les dégâts reçus mesurent ce que la mobilité en frappant rapporte (ou coûte) à un joueur qui lit — et à un joueur qui martèle.

## Limites de la mesure

- Les bots ont un temps de réaction fixe (0,15 s) et lisent parfaitement les télégraphes : un écart de quelques pourcents entre variantes est en deçà du bruit de 20 graines.
- Le bot skilled n'exploite pas délibérément la frappe de dash : la ligne « dash puis frappe » est une habitude scriptée (un tap d'attaque au début de chaque dash), pas une stratégie optimisée.
- Aucun chiffre ici ne dit si un coup « pèse », si le gel local paraît plus net ou plus confus, ni si le combo fluide est plus grisant : il faut jouer (pause → Labo du feel, ou Ville → Labo du feel ; l'arène d'essai s'y prête).
