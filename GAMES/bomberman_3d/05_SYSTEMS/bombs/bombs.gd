# bombs.gd — POSE et MECHE. Ne propage aucune flamme (c'est `explosion`), ne tue personne
# (c'est `damage`). Logique PURE.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")


# Pose une bombe pour l'acteur `index`. Rend true si une bombe a REELLEMENT ete posee.
# Trois refus possibles, tous silencieux du point de vue du joueur mais explicites ici :
# acteur mort · plafond de bombes atteint · case deja occupee par une bombe.
static func poser(state, index: int) -> bool:
	var a: Dictionary = state.acteurs[index]
	if not a["vivant"]:
		return false
	if int(a["bombes_actives"]) >= int(a["bombes_max"]):
		return false
	var c: Vector2i = a["cellule"]
	if state.bombe_sur(c) >= 0:
		return false
	state.bombes.append({
		"proprietaire": index,
		"cellule": c,
		"meche": P.MECHE_TICKS,
		"rayon": int(a["rayon"]),
	})
	a["bombes_actives"] = int(a["bombes_actives"]) + 1
	return true


# Fait descendre les meches d'un tick et rend les INDICES des bombes arrivees a echeance,
# dans l'ordre de pose croissant. L'ordre est declare ici, une fois : c'est lui qui rend la
# resolution de chaine reproductible.
static func tick_meches(state) -> Array:
	var echues: Array = []
	for i in range(state.bombes.size()):
		state.bombes[i]["meche"] = int(state.bombes[i]["meche"]) - 1
		if int(state.bombes[i]["meche"]) <= 0:
			echues.append(i)
	return echues


# Retire les bombes designees et rend leur credit a leurs proprietaires. Les indices sont
# tries DECROISSANTS avant retrait : retirer par indices croissants decalerait les suivants.
static func retirer(state, indices: Array) -> void:
	var tries: Array = indices.duplicate()
	tries.sort()
	tries.reverse()
	for i in tries:
		var b: Dictionary = state.bombes[i]
		var proprio: int = int(b["proprietaire"])
		if proprio >= 0 and proprio < state.acteurs.size():
			var a: Dictionary = state.acteurs[proprio]
			a["bombes_actives"] = max(0, int(a["bombes_actives"]) - 1)
		state.bombes.remove_at(i)
