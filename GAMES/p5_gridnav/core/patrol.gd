# Patrol — navigation déterministe sur grille 2D tactique par BFS.
# Interface : next_step(grille, depart, cible) et path_length(grille, depart, cible).
# Pureté : aucune modification de grille, aucun état global, aucun appel aléatoire.
# Déterminisme : l'ordre d'exploration des voisins est FIXE (haut, droite, bas, gauche).
#
# Adaptation de sys-grid-nav-m01 (knowledge_base/systems/navigation/grid_nav.gd):
#   - Signature: grille est Array[Array[bool]] (true=traversable) vs Dictionary de murs
#   - Même garanties de pureté et déterminisme que l'original
extends RefCounted

const DIRECTIONS := [
	Vector2i(0, -1),  # nord
	Vector2i(1, 0),   # est
	Vector2i(0, 1),   # sud
	Vector2i(-1, 0),  # ouest
]

const MAX_CELLS_EXPLORED := 10000

## Retourne true si la position est traversable dans la grille.
## Une cellule est traversable si elle est dans les bornes et marquée true.
static func _is_traversable(grille: Array, pos: Vector2i) -> bool:
	if pos.y < 0 or pos.y >= grille.size():
		return false
	var row = grille[pos.y]
	if pos.x < 0 or pos.x >= row.size():
		return false
	return row[pos.x]

## Calcule le premier pas depuis depart vers cible, en respectant les obstacles.
## Retourne depart si cible est inatteignable ou est depart.
static func next_step(grille: Array, depart: Vector2i, cible: Vector2i) -> Vector2i:
	return _bfs_next_step(grille, depart, cible)["step"]

## Calcule la longueur du chemin le plus court depuis depart vers cible.
## Retourne -1 si inatteignable. Explore au maximum 10000 cellules.
static func path_length(grille: Array, depart: Vector2i, cible: Vector2i) -> int:
	if depart == cible:
		return 0

	var queue: Array = [depart]
	var visited := {}
	visited[depart] = 0

	var head := 0
	while head < queue.size() and visited.size() < MAX_CELLS_EXPLORED:
		var current = queue[head]
		head += 1
		var current_dist = visited[current]

		if current == cible:
			return current_dist

		for direction in DIRECTIONS:
			var neighbor = current + direction

			if visited.has(neighbor):
				continue

			if not _is_traversable(grille, neighbor):
				continue

			visited[neighbor] = current_dist + 1
			queue.append(neighbor)

	return -1

## Implémentation partagée de next_step.
static func _bfs_next_step(grille: Array, depart: Vector2i, cible: Vector2i) -> Dictionary:
	if depart == cible:
		return {"step": depart}

	var queue: Array = [depart]
	var parent := {}
	parent[depart] = null

	var visited := {}
	visited[depart] = true

	var head := 0
	var found := false

	while head < queue.size() and not found and visited.size() < MAX_CELLS_EXPLORED:
		var current = queue[head]
		head += 1

		for direction in DIRECTIONS:
			var neighbor = current + direction

			if visited.has(neighbor):
				continue

			if not _is_traversable(grille, neighbor):
				continue

			visited[neighbor] = true
			parent[neighbor] = current
			queue.append(neighbor)

			if neighbor == cible:
				found = true
				break

	if not found:
		return {"step": depart}

	var current = cible
	while parent[current] != depart:
		current = parent[current]

	return {"step": current}
