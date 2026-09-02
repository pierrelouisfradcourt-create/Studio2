# sudden_death.gd — MORT SUBITE : l'arene se referme.
#
# POURQUOI CE SYSTEME EXISTE, et ce n'est pas une preference esthetique. Mesure du
# 2026-08-10, 6 graines x 5000 ticks sur l'arene ouverte : 0 victoire, 0 elimination. Un
# adversaire qui fuit correctement ne meurt jamais, et la partie ne se termine pas. C'est
# exactement la raison pour laquelle le genre (Super Bomberman R 2) fait tomber des blocs :
# sans fermeture de l'espace, un match a somme non nulle n'a pas de fin.
#
# Des `MORT_SUBITE_DEBUT` ticks, une case interieure devient SOLIDE toutes les
# `MORT_SUBITE_PERIODE` ticks, en SPIRALE RENTRANTE deterministe. Ce qui se trouve dessous
# est ecrase : acteur tue, bombe detruite, power-up perdu.
#
# Logique PURE. Depend de params.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")


# Ordre de chute : spirale RENTRANTE sur les cases interieures, sens horaire depuis le coin
# haut-gauche. Fonction PURE de la geometrie — deux parties de memes dimensions ecrasent
# leurs cases dans le meme ordre, ce qui garde le rejeu exact.
static func ordre_spirale(largeur: int, hauteur: int) -> Array:
	var out: Array = []
	var x0: int = 1
	var y0: int = 1
	var x1: int = largeur - 2
	var y1: int = hauteur - 2
	while x0 <= x1 and y0 <= y1:
		for x in range(x0, x1 + 1):
			out.append(Vector2i(x, y0))
		for y in range(y0 + 1, y1 + 1):
			out.append(Vector2i(x1, y))
		if y0 < y1:
			for x in range(x1 - 1, x0 - 1, -1):
				out.append(Vector2i(x, y1))
		if x0 < x1:
			for y in range(y1 - 1, y0, -1):
				out.append(Vector2i(x0, y))
		x0 += 1
		y0 += 1
		x1 -= 1
		y1 -= 1
	return out


static func active(ticks: int) -> bool:
	return ticks >= P.MORT_SUBITE_DEBUT


# Nombre de blocs qui DOIVENT etre tombes a ce tick. Derive du temps, jamais compte a part :
# un compteur parallele pourrait deriver du temps, cette formule ne le peut pas.
static func blocs_dus(ticks: int) -> int:
	if not active(ticks):
		return 0
	return (ticks - P.MORT_SUBITE_DEBUT) / P.MORT_SUBITE_PERIODE + 1


# Fait tomber les blocs en retard. Rend la liste des cases NOUVELLEMENT solidifiees.
# Ecrase ce qui s'y trouve : l'acteur meurt (tueur -1 — la mort subite n'a pas d'auteur,
# et lui en inventer un fausserait le comptage des eliminations actives), la bombe est
# detruite et son credit rendu, le power-up disparait.
static func appliquer(state) -> Array:
	var cible: int = blocs_dus(int(state.ticks))
	var spirale: Array = ordre_spirale(state.arene.largeur, state.arene.hauteur)
	var tombes: Array = []
	while int(state.blocs_tombes) < cible and int(state.blocs_tombes) < spirale.size():
		var c: Vector2i = spirale[int(state.blocs_tombes)]
		state.blocs_tombes = int(state.blocs_tombes) + 1
		if state.arene.est_solide(c):
			continue
		state.arene.solidifier(c)
		tombes.append(c)
		state.powerups.erase(c)
		var b: int = state.bombe_sur(c)
		if b >= 0:
			var proprio: int = int(state.bombes[b]["proprietaire"])
			if proprio >= 0 and proprio < state.acteurs.size():
				var a: Dictionary = state.acteurs[proprio]
				a["bombes_actives"] = max(0, int(a["bombes_actives"]) - 1)
			state.bombes.remove_at(b)
		for i in range(state.acteurs.size()):
			var acteur: Dictionary = state.acteurs[i]
			if acteur["vivant"] and acteur["cellule"] == c:
				acteur["vivant"] = false
				state.morts.append({"victime": i, "tueur": -1, "tick": int(state.ticks)})
	return tombes
