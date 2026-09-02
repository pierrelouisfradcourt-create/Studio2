# params.gd — BLOC UNIQUE de constantes nommees de gameplay.
# C'est ICI, et NULLE PART AILLEURS, que vit un litteral numerique de gameplay.
# Feuille du graphe : ne depend de rien. RefCounted (logique pure, aucune API moteur,
# aucune horloge, aucun alea).
#
# reused_from = CONCEPT (games/tetris/05_SYSTEMS/params/params.gd) : on reutilise la FORME
# prouvee (un script de constantes nommees et rien d'autre), jamais les valeurs.
extends RefCounted

# ============================================================================
# TYPES DE CASE — vocabulaire FERME. Un type hors de cette table n'existe pas.
# ============================================================================
const SOL: int = 0
const SOLIDE: int = 1
const DESTRUCTIBLE: int = 2

# ============================================================================
# BASE DE TEMPS. Toutes les durees de ce fichier sont en TICKS ; ce n'est
# qu'ici qu'elles prennent un sens en SECONDES.
#
# DEFAUT REEL CORRIGE (retour Pierre, 2026-08-10 : « c'est trop rapide pour un
# humain »). La base de temps vivait dans `runtime_loop.gd` (TICK_S), pas ici :
# les durees etaient donc calibrees en « pas de fuite » sans que personne ne
# puisse les convertir en secondes. Mesure de ce qui tournait reellement :
# 10 cases/seconde et une meche de 0,50 s — injouable, et invisible tant que la
# base de temps n'etait pas dans le meme fichier que les durees qu'elle definit.
# ============================================================================
const TICKS_PAR_SECONDE: int = 60

# ============================================================================
# DEPLACEMENT. Un acteur occupe UNE case ; il ne peut rebouger qu'apres
# `cooldown` ticks. La fluidite visuelle est l'affaire de la presentation, qui
# interpole entre deux cases a partir du cooldown restant — AUCUN flottant
# n'entre dans les regles. C'est ce qui garde le tick deterministe, donc
# mutable et solvable.
#
# CALIBRAGE HUMAIN : 16 ticks = 3,75 cases/s a vitesse initiale, 8 ticks =
# 7,5 cases/s au plafond de SPEED_UP. Bande verifiee par test_playable_speed.
# ============================================================================
const MOVE_COOLDOWN_BASE: int = 16     # ticks entre deux pas, vitesse initiale
const MOVE_COOLDOWN_MIN: int = 8       # plancher : SPEED_UP ne descend jamais sous ce seuil
const SPEED_STEP: int = 2              # ticks retires par SPEED_UP (4 paliers utiles)

# Intentions de jeu (vocabulaire ferme). AUCUNE = ne rien faire ce tick.
const AUCUNE: int = 0
const HAUT: int = 1
const DROITE: int = 2
const BAS: int = 3
const GAUCHE: int = 4
const POSER: int = 5

# Vecteurs de direction, indexes par l'intention. Ordre FIXE (determinisme).
const DIRECTIONS: Array = [
	Vector2i(0, 0),    # AUCUNE
	Vector2i(0, -1),   # HAUT
	Vector2i(1, 0),    # DROITE
	Vector2i(0, 1),    # BAS
	Vector2i(-1, 0),   # GAUCHE
	Vector2i(0, 0),    # POSER
]

# ============================================================================
# BOMBES.
# ============================================================================
# Duree de la meche : 150 ticks = 2,50 s, la valeur du genre.
#
# ERREUR DE RAISONNEMENT CORRIGEE (2026-08-10). J'avais ramene cette valeur de 90 a 30 en
# la calibrant en PAS DE FUITE (« 5 pas suffisent »), sans jamais la convertir en secondes :
# 30 ticks valaient 0,50 s, injouable. Le diagnostic d'origine etait faux — dans un vrai
# Bomberman on meurt parce que l'ESPACE est contraint (couloirs, blocs, bombes multiples,
# portee accrue), pas parce que la meche est courte. Raccourcir la meche pour rendre le jeu
# letal revenait a rendre le jeu injouable pour obtenir un oracle vert.
const MECHE_TICKS: int = 150

# Duree de letalite d'une case touchee : 30 ticks = 0,50 s.
const DUREE_FLAMME: int = 30
const RAYON_BASE: int = 1              # portee initiale de la flamme, en cases
const RAYON_MAX: int = 8               # plafond de FIRE_UP
const BOMBES_BASE: int = 1             # nombre de bombes simultanees initial
const BOMBES_MAX: int = 8              # plafond de BOMB_UP

# ============================================================================
# POWER-UPS — vocabulaire FERME des identifiants.
# Deux natures seulement dans ce slice : modificateur borne, et drapeau.
# Ajouter un power-up d'une de ces deux natures doit rester une operation de
# DONNEE (table ci-dessous), jamais un nouveau fichier de systeme.
# ============================================================================
const PU_BOMB_UP: String = "BOMB_UP"
const PU_FIRE_UP: String = "FIRE_UP"
const PU_SPEED_UP: String = "SPEED_UP"

# Table des definitions. `nature` ∈ {"stat"} pour ce slice ; `stat` nomme le champ
# de PlayerAbilities modifie, `delta` le pas, `min`/`max` les bornes.
const POWERUP_DEFS: Dictionary = {
	PU_BOMB_UP:  {"nature": "stat", "stat": "bombes_max", "delta": 1,  "min": BOMBES_BASE, "max": BOMBES_MAX},
	PU_FIRE_UP:  {"nature": "stat", "stat": "rayon",      "delta": 1,  "min": RAYON_BASE,  "max": RAYON_MAX},
	PU_SPEED_UP: {"nature": "stat", "stat": "cooldown",   "delta": -SPEED_STEP,
		"min": MOVE_COOLDOWN_MIN, "max": MOVE_COOLDOWN_BASE},
}

# Ordre FIXE des identifiants (determinisme du tirage : jamais l'ordre d'un Dictionary).
const POWERUP_IDS: Array = [PU_BOMB_UP, PU_FIRE_UP, PU_SPEED_UP]

# ============================================================================
# PARTIE.
# ============================================================================
# Duree maximale d une partie : 10800 ticks = 180 s. Au-dela : match nul.
const DUREE_MAX_TICKS: int = 10800

# ============================================================================
# MORT SUBITE. L'arene se referme : une case interieure devient SOLIDE toutes les
# MORT_SUBITE_PERIODE ticks, en spirale rentrante, a partir de MORT_SUBITE_DEBUT.
# Ratifie Pierre 2026-08-10, sur mesure : sans fermeture de l'espace, 6 graines x
# 5000 ticks donnaient 0 victoire et 0 elimination — un adversaire qui fuit
# correctement ne meurt jamais sur une arene ouverte.
# Calibration HUMAINE : debut a 60 s ; 143 cases interieures fermees a raison d une
# toutes les 20 ticks (0,33 s) = 47,7 s de fermeture. Manche bornee a ~108 s.
# ============================================================================
const MORT_SUBITE_DEBUT: int = 3600
const MORT_SUBITE_PERIODE: int = 20

# Statuts de partie — enumeration GELEE, quatre valeurs, jamais indefini.
const EN_COURS: int = 0
const GAGNE: int = 1
const PERDU: int = 2
const NUL: int = 3

# Regles de victoire declarees (vocabulaire ferme).
const VICTOIRE_LAST_STANDING: String = "LAST_STANDING"
const VICTOIRE_CLEAR_ALL_BOTS: String = "CLEAR_ALL_BOTS"

# L'acteur 0 est le joueur ; les suivants sont des bots. Convention unique.
const INDEX_JOUEUR: int = 0
