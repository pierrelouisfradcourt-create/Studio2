# player_movement.gd — file de direction, direction effectuee, pas ou butee
# (lignes player.direction_queue, player.resolved_direction, player.step_or_block,
# player.budget_and_wall_rule).
#
# V2 : la carte est RECUE en argument, et le pas consomme un BUDGET DE CASES fourni par
# le tick — une en temps normal, davantage pendant un dash. La regle de butee est la
# MEME quel que soit le budget : c'est la raison STRUCTURELLE pour laquelle le
# comportement face aux murs est declare inchange par conception, et non une observation
# empirique.
#
# Logique PURE : ne connait ni scene, ni noeud, ni Input.
extends RefCounted

const Maze = preload("res://05_SYSTEMS/maze/maze.gd")


# File de direction de PROFONDEUR 1 (ligne player.direction_queue). Une demande hors
# du vocabulaire ferme est ignoree sans effet de bord.
static func demander(s, direction: Vector2i) -> void:
	if direction == Maze.AUCUNE:
		return
	if not Maze.DIRECTIONS.has(direction):
		return
	s.pac_attente = direction


# Direction EFFECTUEE du tick (ligne player.resolved_direction) : la demande est
# retenue si et seulement si le virage est praticable ; sinon elle RESTE en attente et
# la direction courante est conservee, sans effet de bord.
static func direction_resolue(carte, position: Vector2i, courante: Vector2i, attente: Vector2i) -> Dictionary:
	if attente != Maze.AUCUNE and carte.praticable(carte.case_suivante(position, attente)):
		return {"direction": attente, "attente": Maze.AUCUNE}
	return {"direction": courante, "attente": attente}


# Pas ou butee (ligne player.step_or_block) : exactement une case adjacente, ou aucune.
# Aucun saut, aucune case non adjacente, bouclage de tunnel applique par la carte.
static func avancer(carte, position: Vector2i, direction: Vector2i) -> Vector2i:
	if direction == Maze.AUCUNE:
		return position
	var cible: Vector2i = carte.case_suivante(position, direction)
	if carte.praticable(cible):
		return cible
	return position


# Avance de `budget` cases AU PLUS, la MEME regle de butee etant appliquee a CHAQUE
# case : un budget de 3 face a un mur ne franchit pas plus qu'un budget de 1.
static func avancer_budget(carte, position: Vector2i, direction: Vector2i, budget: int) -> Vector2i:
	var p: Vector2i = position
	for _i in range(budget):
		var suivant: Vector2i = avancer(carte, p, direction)
		if suivant == p:
			return p
		p = suivant
	return p


# Applique le tick de deplacement du joueur a l'etat, pour le budget de cases donne.
static func pas(s, budget: int) -> void:
	var r: Dictionary = direction_resolue(s.carte, s.pac, s.pac_dir, s.pac_attente)
	s.pac_dir = r["direction"]
	s.pac_attente = r["attente"]
	s.pac = avancer_budget(s.carte, s.pac, s.pac_dir, budget)
