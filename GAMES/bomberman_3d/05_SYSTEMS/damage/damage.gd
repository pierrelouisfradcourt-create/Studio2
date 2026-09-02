# damage.gd — QUI MEURT ce tick. Ne termine aucune partie (c'est `victory`).
#
# La mort est une CONSEQUENCE D'ETAT : un acteur vivant qui occupe une case letale meurt.
# Jamais un compteur qui expire, jamais un evenement qu'on oublie d'emettre.
# Logique PURE.
extends RefCounted


# Tue les acteurs situes sur une case letale et ATTRIBUE chaque mort, en lisant
# `state.flammes_auteur` — table qui vit AUSSI LONGTEMPS que la flamme.
#
# L'attribution n'est pas de la comptabilite : c'est elle qui permet a l'oracle d'exiger
# une victoire par ELIMINATION ACTIVE. Sans elle, un bot qui attend que les autres se
# tuent est indiscernable d'un bot qui joue.
#
# Une case sans auteur connu donne un tueur -1 : jamais un auteur invente.
static func appliquer(state) -> Array:
	var morts: Array = []
	for i in range(state.acteurs.size()):
		var a: Dictionary = state.acteurs[i]
		if not a["vivant"]:
			continue
		var c: Vector2i = a["cellule"]
		if not state.case_letale(c):
			continue
		a["vivant"] = false
		var tueur: int = -1
		if state.flammes_auteur.has(c):
			tueur = int(state.flammes_auteur[c])
		var mort := {"victime": i, "tueur": tueur, "tick": int(state.ticks)}
		morts.append(mort)
		state.morts.append(mort)
	return morts


# Decompte de la letalite, un tick. Une case dont le compteur atteint zero cesse d'etre
# letale et disparait de la table : la table ne grossit jamais indefiniment.
static func decompter_flammes(state) -> void:
	var restantes: Dictionary = {}
	var auteurs: Dictionary = {}
	for c in state.flammes.keys():
		var t: int = int(state.flammes[c]) - 1
		if t > 0:
			restantes[c] = t
			if state.flammes_auteur.has(c):
				auteurs[c] = state.flammes_auteur[c]
	state.flammes = restantes
	# L'auteur s'eteint EXACTEMENT avec sa flamme : les deux tables ne divergent jamais.
	state.flammes_auteur = auteurs
