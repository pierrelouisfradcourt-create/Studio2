# state.gd — ligne core.game_state. Etat de partie PUR. RefCounted : aucune I/O, aucune
# horloge, aucun alea non seede, aucune API de rendu. DETIENT l'etat, N'AGIT pas : toutes
# les regles (physique, collisions, fin) vivent dans d'autres systemes qui operent sur lui.
#
# Le statut est EXACTEMENT une valeur parmi 3 (EN_COURS / GAGNE / PERDU) : exclusifs et
# exhaustifs (charter.criteres_succes CONDITIONS DE FIN ASSERTEES STRICTEMENT).
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const Ball = preload("res://05_SYSTEMS/game_state/ball.gd")
const Level = preload("res://05_SYSTEMS/level_gen/level_gen.gd")

# --- Enumeration GELEE des 3 statuts, exclusifs et exhaustifs ---
enum Statut { EN_COURS, GAGNE, PERDU }
const STATUTS_VALIDES := [Statut.EN_COURS, Statut.GAGNE, Statut.PERDU]

# --- Champs de l'etat de partie (physique CONTINUE : flottants) ---
var ball_pos: Vector2 = Vector2.ZERO
var ball_vel: Vector2 = Vector2.ZERO
var paddle_x: float = 0.0            # centre de la raquette (x)
var bricks: Array = []               # Array[bool], index = rangee * COLONNES + colonne
var start_y: float = 0.0             # y du haut du bloc de briques (partie de la disposition)
var briques_restantes: int = 0
var vies: int = 0
var score: int = 0
var statut: int = Statut.EN_COURS
var seed: int = 0
var niveau: int = 0
var ticks: int = 0

# Reconstruit un etat initial neuf a partir d'une graine (deterministe).
static func initial(seed_val: int) -> Object:
	var s = load("res://05_SYSTEMS/game_state/state.gd").new()
	s.seed = seed_val
	s.niveau = 0
	var dispo: Dictionary = Level.generer(seed_val, s.niveau)
	s.bricks = dispo["bricks"]
	s.start_y = dispo["start_y"]
	s.briques_restantes = s.compter_briques()
	s.paddle_x = P.TERRAIN_LARGEUR / 2.0
	s.ball_pos = Ball.position_service()
	s.ball_vel = Ball.vitesse_service()
	s.vies = P.VIES_INITIALES
	s.score = 0
	s.statut = Statut.EN_COURS
	s.ticks = 0
	return s

# Copie profonde independante (le tick et les tests ne mutent jamais l'entree).
func clone() -> Object:
	var c = load("res://05_SYSTEMS/game_state/state.gd").new()
	c.ball_pos = ball_pos
	c.ball_vel = ball_vel
	c.paddle_x = paddle_x
	c.bricks = bricks.duplicate()
	c.start_y = start_y
	c.briques_restantes = briques_restantes
	c.vies = vies
	c.score = score
	c.statut = statut
	c.seed = seed
	c.niveau = niveau
	c.ticks = ticks
	return c

# Nombre de briques REELLEMENT presentes (source de verite du compte restant).
func compter_briques() -> int:
	var n := 0
	for present in bricks:
		if present:
			n += 1
	return n

# Validation STRUCTURELLE (ligne core.error_handling). Aucune I/O.
func est_valide() -> bool:
	if not (statut in STATUTS_VALIDES):
		return false
	if vies < 0:
		return false
	if briques_restantes < 0:
		return false
	if briques_restantes != compter_briques():
		return false
	if bricks.size() != P.total_briques():
		return false
	var hw := P.raquette_demi_largeur()
	if paddle_x < hw or paddle_x > P.TERRAIN_LARGEUR - hw:
		return false
	return true

# Egalite profonde sur TOUS les champs (oracles de replay et de non-fuite).
func egal_profond(autre: Object) -> bool:
	return (ball_pos == autre.ball_pos
		and ball_vel == autre.ball_vel
		and paddle_x == autre.paddle_x
		and bricks == autre.bricks
		and start_y == autre.start_y
		and briques_restantes == autre.briques_restantes
		and vies == autre.vies
		and score == autre.score
		and statut == autre.statut
		and seed == autre.seed
		and niveau == autre.niveau
		and ticks == autre.ticks)
