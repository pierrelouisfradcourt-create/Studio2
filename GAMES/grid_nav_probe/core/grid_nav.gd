# GridNav — navigation déterministe en grille par BFS.
# Interface : next_step(from, to, walls) et path_length(from, to, walls).
# Pureté : aucune modification de walls, aucun état global, aucun appel aléatoire.
# Déterminisme : l'ordre d'exploration des voisins est FIXE (haut, droite, bas, gauche).
extends RefCounted

# Directions en ordre FIXE pour garantir le déterminisme.
# Haut (nord), Droite (est), Bas (sud), Gauche (ouest).
const DIRECTIONS := [
	Vector2i(0, -1),  # nord
	Vector2i(1, 0),   # est
	Vector2i(0, 1),   # sud
	Vector2i(-1, 0),  # ouest
]

# Borne d'exploration PARTAGEE par les deux BFS de ce module.
#
# Pourquoi elle existe : `walls` est un Dictionary CREUX, sans bords de grille — le
# plan est donc infini. Sur une cible inatteignable, un BFS non borne explore
# indefiniment et ne rend JAMAIS la main.
#
# Defaut reel corrige le 2026-07-21 : `path_length` portait cette borne (en local),
# `_bfs_next_step` ne la portait PAS. `next_step` gelait donc sur toute cible
# inatteignable en grille ouverte, alors que le catalogue declare l'affordance
# « rend from si to est inatteignable ». Le bug etait MASQUE par une tautologie du
# generateur de labyrinthe (il demandait a path_length si un chemin existait avant de
# rendre le labyrinthe, donc aucune cible n'etait jamais inatteignable). Retirer la
# tautologie l'a expose. La constante est desormais unique et partagee : l'asymetrie
# entre les deux fonctions ne peut plus se reintroduire silencieusement.
const MAX_CELLS_EXPLORED := 10000

## Calcule un pas depuis from vers to, en évitant les murs.
## Retourne la position après un pas du chemin le plus court, ou from si impossible.
static func next_step(from: Vector2i, to: Vector2i, walls: Dictionary) -> Vector2i:
	return _bfs_next_step(from, to, walls)["step"]

## Comme next_step, mais retourne aussi le nombre d'expansions de nœuds (nombre
## de fois où le corps de la boucle de voisinage a tourné) effectuées par le
## BFS sous-jacent. Fonction pure, déterministe, aucun état partagé entre
## appels : le compteur est une valeur locale renvoyée, pas une variable
## globale. Existe pour rendre observable le TRAVAIL du BFS (pas seulement son
## résultat) — sans ça, une marque `visited` cassée qui ferait ré-explorer les
## mêmes cellules ne serait pas testable autrement que par le résultat final,
## qui peut rester correct malgré le travail gaspillé.
static func next_step_expansions(from: Vector2i, to: Vector2i, walls: Dictionary) -> int:
	return _bfs_next_step(from, to, walls)["expansions"]

## Implémentation partagée de next_step/next_step_expansions. Retourne
## {"step": Vector2i, "expansions": int}. Un seul chemin de code : toute
## mutation du marquage `visited` affecte next_step ET next_step_expansions
## de la même façon, puisque les deux appellent cette fonction.
static func _bfs_next_step(from: Vector2i, to: Vector2i, walls: Dictionary) -> Dictionary:
	if from == to:
		return {"step": from, "expansions": 0}

	# BFS pour trouver le chemin le plus court, puis retourner le premier pas.
	var queue: Array = [from]
	var parent := {}
	parent[from] = null  # from n'a pas de parent
	var visited := {}
	visited[from] = true

	var expansions := 0
	var head := 0
	var found := false
	# Borne d'exploration OBLIGATOIRE (cf. MAX_CELLS_EXPLORED) : sans elle, une cible
	# inatteignable sur ce plan infini fait tourner ce BFS indefiniment. Quand la borne
	# est atteinte sans avoir trouve, `found` reste false et la fonction rend `from` —
	# ce qui honore l'affordance declaree au catalogue.
	while head < queue.size() and not found and visited.size() < MAX_CELLS_EXPLORED:
		var current = queue[head]
		head += 1

		for direction in DIRECTIONS:
			expansions += 1
			var neighbor = current + direction

			# Déjà visité ? skip.
			if visited.has(neighbor):
				continue

			# C'est un mur ? skip.
			if walls.has(neighbor) and walls[neighbor]:
				continue

			# Ajouter à la queue.
			visited[neighbor] = true
			parent[neighbor] = current
			queue.append(neighbor)

			# Avons-nous trouvé la cible ?
			if neighbor == to:
				found = true
				break

	# Si la cible n'a pas été trouvée, retourner from.
	if not found:
		return {"step": from, "expansions": expansions}

	# Reconstituer le chemin en remontant les parents.
	var current = to
	while parent[current] != from:
		current = parent[current]

	return {"step": current, "expansions": expansions}

## Calcule la longueur du chemin le plus court depuis from vers to.
## Retourne -1 si inatteignable. Explore au maximum 10000 cellules pour éviter boucles infinies.
static func path_length(from: Vector2i, to: Vector2i, walls: Dictionary) -> int:
	if from == to:
		return 0

	# BFS classique avec queue FIFO et visited set.
	var queue: Array = [from]
	var visited := {}
	visited[from] = 0  # distance de from à from

	var head := 0  # pointeur sur la queue
	# Meme borne partagee que _bfs_next_step (cf. MAX_CELLS_EXPLORED).

	while head < queue.size() and visited.size() < MAX_CELLS_EXPLORED:
		var current = queue[head]
		head += 1
		var current_dist = visited[current]

		# Arrêt prématuré si on a trouvé la cible.
		if current == to:
			return current_dist

		# Explore les voisins en ordre FIXE pour déterminisme.
		for direction in DIRECTIONS:
			var neighbor = current + direction

			# Déjà visité ? skip.
			if visited.has(neighbor):
				continue

			# C'est un mur ? skip.
			if walls.has(neighbor) and walls[neighbor]:
				continue

			# Ajouter à la queue et marquer comme visité.
			visited[neighbor] = current_dist + 1
			queue.append(neighbor)

	# Cible non trouvée ou limite atteinte.
	return -1
