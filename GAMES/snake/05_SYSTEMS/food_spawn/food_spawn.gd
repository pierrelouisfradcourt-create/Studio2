# food_spawn.gd — ligne core.food_spawn. UNIQUE consommateur d'alea du produit.
# PRNG entier SEEDE (LCG deterministe, jamais randi/randf du moteur) + tirage sur
# la LISTE des cases libres (jamais par rejet). RefCounted, pur.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")

# LCG deterministe (Numerical Recipes). Avance l'etat et renvoie le nouvel etat.
static func _prochain(etat: int) -> int:
	return (1103515245 * etat + 12345) & 0x7fffffff

# Liste ORDONNEE (x puis y) des cases libres : l'ordre ne depend JAMAIS d'un
# Dictionary, il est reconstruit deterministiquement a chaque appel.
static func cases_libres(state) -> Array:
	var occupees := {}
	for seg in state.segments:
		occupees[seg] = true
	var libres: Array = []
	for x in range(P.TAILLE_GRILLE):
		for y in range(P.TAILLE_GRILLE):
			var c := Vector2i(x, y)
			if not occupees.has(c):
				libres.append(c)
	return libres

# Tire une nouvelle nourriture. Renvoie {cellule, rng_state, grille_pleine}.
# Sur 0 case libre : renvoie l'etat de grille pleine SANS boucler (grille_pleine=true).
static func tirer(state) -> Dictionary:
	var libres := cases_libres(state)
	if libres.size() == 0:
		return {"cellule": Vector2i(-1, -1), "rng_state": state.rng_state, "grille_pleine": true}
	var nouvel_etat := _prochain(state.rng_state)
	var index := nouvel_etat % libres.size()
	return {"cellule": libres[index], "rng_state": nouvel_etat, "grille_pleine": false}
