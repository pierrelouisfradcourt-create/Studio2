# params.gd — BLOC UNIQUE des constantes nommees de REGLE DE JEU (ligne params.rules_only).
#
# V2 : ce bloc PERD les grandeurs qui decrivaient UNE carte — largeur, hauteur, ligne de
# tunnel, bornes de la zone jouable. Elles sont desormais DERIVEES du descripteur de
# carte par map_schema / maze. Deuxieme des quatre causes mesurees de la baseline V1 :
# ajouter une carte ne rouvre plus ce fichier.
#
# Ne restent ici que les constantes vraies pour TOUTES les cartes : baremes de score,
# valeurs de capture, cadences de base, durees des segments de l'horloge, vies initiales,
# parametres du dash, valeur de repli du parametre de progression.
#
# Feuille du graphe : ne depend de RIEN. RefCounted, aucune API de moteur.
extends RefCounted

# ============================================================================
# COLLECTIBLES — valeurs de VERIFICATION de la carte de reference
# ============================================================================
# Comptes ATTENDUS du labyrinthe classique (worldscan : 240 + 4 = 244). Ce sont des
# valeurs de VERIFICATION d'une carte nommee, jamais le total qui definit la victoire :
# celui-la est PRODUIT par pellets.total_pose(), carte par carte.
const PASTILLES_ATTENDUES: int = 240
const SUPER_ATTENDUES: int = 4
const COLLECTIBLES_ATTENDUS: int = 244

# ============================================================================
# SCORE  (worldscan#systems[Scoring & Persistence])
# ============================================================================
const POINTS_PASTILLE: int = 10
const POINTS_SUPER: int = 50
const VALEURS_CAPTURE: Array = [200, 400, 800, 1600]

# ============================================================================
# HORLOGE DES ETATS DE POURSUITE
# (worldscan#ghost_states.mode_timing_levels_1_4 : 20/7/20/7/20/5 s puis poursuite)
# ============================================================================
# Cadence de reference : 150 ms par case (charter#parametres_de_design, A_EQUILIBRER).
const PERIODE_TICK_MS: float = 150.0
# Durees des six segments en TICKS (secondes / 0,150). La logique pure ne lit jamais
# d'horloge de plateforme : le tick EST son unite de temps.
const SEGMENT_POURSUITE_TICKS: int = 133  # 20 s
const SEGMENT_DISPERSION_LONG_TICKS: int = 47  # 7 s
const SEGMENT_DISPERSION_COURT_TICKS: int = 33  # 5 s
# Duree de la fenetre Effraye en ticks (worldscan : ~6 s aux niveaux 1-4).
const DUREE_EFFRAYE_TICKS: int = 40

# ============================================================================
# CIBLAGE DES FANTOMES  (worldscan#ghost_targeting)
# ============================================================================
const AVANCE_ROSE: int = 4       # Pinky vise 4 cases devant Pac-Man
const AVANCE_CYAN: int = 2       # Inky pivote sur la case 2 devant Pac-Man
const SEUIL_ORANGE: int = 8      # Clyde bascule au-dela de 8 cases de distance

# ============================================================================
# CADENCE RELATIVE DES FANTOMES
# ============================================================================
# CONTRAINTE DURE, structurelle et non negociable : un fantome est TOUJOURS
# strictement plus lent que Pac-Man. Un fantome aussi rapide ou plus rapide rendrait la
# victoire 50/50 impossible a prouver, donc casserait le critere SOLVABILITE PROUVEE.
#
# Realisation en grille DISCRETE : Pac-Man avance a chaque tick ; un fantome saute
# exactement un tick sur CADENCE_FANTOME_PERIODE. Le ratio effectif est donc
# (CADENCE_FANTOME_PERIODE - 1) / CADENCE_FANTOME_PERIODE = 19/20 = 0,95.
# Consequence a connaitre pour les tests : l'ecart ne se creuse que d'UNE case tous les
# 20 ticks — toute fenetre de mesure plus courte rend l'assertion fausse ou tautologique.
#
# V2 : cette valeur est la VALEUR DE REPLI du parametre de progression. La valeur
# EFFECTIVE d'un niveau est DECLAREE dans le catalogue (03_WORLD/rules/level_catalog) et
# PASSEE EN ARGUMENT a ghost_movement : aucune table indexee par niveau ne vit ici,
# sans quoi ajouter un niveau rouvrirait ce fichier.
const CADENCE_FANTOME_PERIODE: int = 20
const RATIO_VITESSE_FANTOME: float = 0.95
# En etat Effraye le fantome ne bouge qu'un tick sur deux (ratio 0,50).
const CADENCE_EFFRAYE_PERIODE: int = 2
const RATIO_VITESSE_EFFRAYE: float = 0.5
# Fenetre minimale d'observation d'un ecart de vitesse, en ticks : au moins une periode
# complete, sinon le fantome n'a saute aucun tick et l'ecart mesure vaut 0.
const FENETRE_MESURE_ECART_TICKS: int = 24

# ============================================================================
# MAISON CENTRALE
# ============================================================================
# Ticks de sortie, STRICTEMENT CROISSANTS : le rouge est deja dehors au tick 0.
const DELAIS_SORTIE_MAISON: Array = [0, 30, 60, 90]
# Delai avant qu'un fantome capture ne ressorte de la maison.
const DELAI_RETOUR_MAISON: int = 40

# ============================================================================
# VIES — LA GRANDEUR QUE LE MODE DE JEU GOUVERNE
# ============================================================================
# V6 (decision de design Pierre, 2026-08-06). MESURE QUI A DECLENCHE CE CHANGEMENT : au
# lot V5, la mesure differentielle des deux modes de jeu a compte 0 divergence sur 200
# ticks. Le mode etait un PRODUCTEUR SANS CONSOMMATEUR — un reglage que le joueur peut
# changer et qui ne change rien. Il gouverne desormais UNE grandeur, et une seule : le
# nombre de vies de depart.
#
# Les deux valeurs sont NOMMEES PAR CE QU'ELLES SONT, jamais par le mode qui les choisit :
#   - le DEFI          : peu de marge, la partie se merite ;
#   - la MARGE D'ERREUR : de quoi voir toutes les cartes en apprenant.
# Elles vivent ICI parce que ce sont des regles de jeu. La CORRESPONDANCE mode -> valeur
# vit dans settings, SEUL module qui detienne le vocabulaire ferme des modes : aucun des
# deux ne recopie l'autre, et le nombre affiche au joueur est toujours LU, jamais ecrit.
#
# AUCUNE constante `VIES_INITIALES` ne subsiste, et c'est voulu : un nombre de vies unique
# serait desormais FAUX dans l'un des deux modes. Un appelant doit dire de QUEL mode il
# parle — la signature l'y oblige.
#
# CE QUE LE MODE NE GOUVERNE PAS : le dash. Il reste un reglage SEPARE, actif dans les
# deux modes (decision Pierre explicite). Les deux aides ne sont pas fusionnees.
const VIES_MODE_DEFI: int = 3
const VIES_MODE_MARGE: int = 5

# ============================================================================
# DASH  (mode d'accessibilite — ligne dash.declared_effects)
# ============================================================================
# Budget de pas d'un tick de dash : le joueur avance PAS_DASH cases au lieu d'une. La
# regle de butee contre les murs est INCHANGEE, quel que soit le budget.
const PAS_NORMAL: int = 1
const PAS_DASH: int = 3
# Delai, en ticks, avant qu'un dash suivant soit disponible.
const RECHARGE_DASH_TICKS: int = 24
