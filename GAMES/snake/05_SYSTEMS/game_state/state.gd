# state.gd — etat de partie PUR (lignes core.game_state + core.error_handling).
# RefCounted, aucune I/O, aucune horloge, aucun alea non seede, aucune API de rendu.
# Le MEILLEUR SCORE n'en fait PAS partie (il vit hors de l'etat de partie).
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")

# --- Enumeration GELEE des 4 statuts, exclusifs et exhaustifs (gameplayprog R23) ---
enum Statut { EN_COURS, EN_PAUSE, TERMINE_PERDU, TERMINE_GAGNE }
const STATUTS_VALIDES := [Statut.EN_COURS, Statut.EN_PAUSE, Statut.TERMINE_PERDU, Statut.TERMINE_GAGNE]

# --- Vocabulaire ferme de directions (aussi porte par input_rules) ---
const HAUT := Vector2i(0, -1)
const BAS := Vector2i(0, 1)
const GAUCHE := Vector2i(-1, 0)
const DROITE := Vector2i(1, 0)

# --- Champs de l'etat de partie ---
var segments: Array = []        # Array[Vector2i], tete = segments[0], queue = dernier
var dir_effectuee: Vector2i     # derniere direction REELLEMENT appliquee
var dir_en_attente: Vector2i    # direction demandee, profondeur 1 (ecrasable)
var nourriture: Vector2i
var score: int = 0
var longueur: int = 0
var periode: float = 0.0
var fruits: int = 0             # nombre de nourritures mangees (pilote les paliers)
var palier: int = 0            # compteur de paliers franchis
var ticks: int = 0             # compteur de ticks
var statut: int = Statut.EN_COURS
var rng_state: int = 0          # etat du PRNG seede (unique consommateur d'alea)

# Reconstruit un etat initial neuf a partir d'une graine (deterministe).
static func initial(seed_val: int) -> Object:
	var s = load("res://05_SYSTEMS/game_state/state.gd").new()
	var centre := int(P.TAILLE_GRILLE / 2)
	# Serpent horizontal, tete a droite, corps a gauche. Longueur initiale exacte.
	s.segments = []
	for i in range(P.LONGUEUR_INITIALE):
		s.segments.append(Vector2i(centre - i, centre))
	s.dir_effectuee = DROITE
	s.dir_en_attente = DROITE
	s.score = 0
	s.longueur = P.LONGUEUR_INITIALE
	s.fruits = 0
	s.palier = 0
	s.ticks = 0
	s.periode = P.VITESSE_INITIALE_MS
	s.statut = Statut.EN_COURS
	s.rng_state = seed_val
	# La premiere nourriture est posee par food_spawn (unique consommateur d'alea).
	var FoodSpawn = load("res://05_SYSTEMS/food_spawn/food_spawn.gd")
	var tirage = FoodSpawn.tirer(s)
	s.nourriture = tirage["cellule"]
	s.rng_state = tirage["rng_state"]
	return s

# Copie profonde independante (les tests et le tick ne mutent jamais l'entree).
func clone() -> Object:
	var c = load("res://05_SYSTEMS/game_state/state.gd").new()
	c.segments = segments.duplicate()
	c.dir_effectuee = dir_effectuee
	c.dir_en_attente = dir_en_attente
	c.nourriture = nourriture
	c.score = score
	c.longueur = longueur
	c.periode = periode
	c.fruits = fruits
	c.palier = palier
	c.ticks = ticks
	c.statut = statut
	c.rng_state = rng_state
	return c

func tete() -> Vector2i:
	return segments[0]

# Validation STRUCTURELLE (ligne core.error_handling). Aucune I/O.
# Un etat valide : statut parmi les 4, longueur == nombre de segments, aucune
# position hors grille, exactement une nourriture presente hors du corps.
func est_valide() -> bool:
	if not (statut in STATUTS_VALIDES):
		return false
	if longueur != segments.size():
		return false
	for seg in segments:
		if seg.x < 0 or seg.x >= P.TAILLE_GRILLE or seg.y < 0 or seg.y >= P.TAILLE_GRILLE:
			return false
	if nourriture.x < 0 or nourriture.x >= P.TAILLE_GRILLE or nourriture.y < 0 or nourriture.y >= P.TAILLE_GRILLE:
		return false
	if nourriture in segments:
		return false
	return true

# Egalite profonde sur tous les champs de l'etat de partie (utilisee par les
# oracles de replay, de pause et de non-fuite).
func egal_profond(autre: Object) -> bool:
	return (segments == autre.segments
		and dir_effectuee == autre.dir_effectuee
		and dir_en_attente == autre.dir_en_attente
		and nourriture == autre.nourriture
		and score == autre.score
		and longueur == autre.longueur
		and periode == autre.periode
		and fruits == autre.fruits
		and palier == autre.palier
		and ticks == autre.ticks
		and statut == autre.statut
		and rng_state == autre.rng_state)
