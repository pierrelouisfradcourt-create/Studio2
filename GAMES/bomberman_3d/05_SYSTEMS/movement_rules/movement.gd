# movement.gd — traduit une INTENTION deja formee en deplacement LEGAL, ou la refuse.
#
# Ne connait ni le clavier ni un bot : il recoit une intention entiere. Ne decide d'aucune
# mort — marcher dans une flamme est legal, c'est `damage` qui en tire les consequences.
# Logique PURE.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")


# Une case est-elle traversable par l'acteur `index` ? Trois obstacles distincts, et ils ne
# se confondent pas : le TERRAIN (arene), les BOMBES, les autres ACTEURS.
static func traversable(state, index: int, cellule: Vector2i) -> bool:
	if not state.arene.est_libre(cellule):
		return false
	var b: int = state.bombe_sur(cellule)
	if b >= 0:
		# Regle de genre : une bombe ne bloque pas son poseur TANT QU'IL N'A PAS QUITTE sa
		# case. Sans elle, poser une bombe reviendrait a se murer soi-meme, et le jeu
		# n'aurait aucune sortie apres la premiere pose.
		if not (state.bombes[b]["proprietaire"] == index
				and state.acteurs[index]["cellule"] == cellule):
			return false
	for j in range(state.acteurs.size()):
		if j == index:
			continue
		if state.acteurs[j]["vivant"] and state.acteurs[j]["cellule"] == cellule:
			return false
	return true


# Applique une intention de deplacement. Rend true si l'acteur a REELLEMENT change de case.
# L'orientation, elle, suit toujours l'intention : un acteur qui pousse contre un mur
# regarde le mur — c'est ce qui rend le refus lisible a l'ecran.
static func appliquer(state, index: int, intention: int) -> bool:
	var a: Dictionary = state.acteurs[index]
	if not a["vivant"]:
		return false
	if intention < P.HAUT or intention > P.GAUCHE:
		return false
	a["direction"] = intention
	if int(a["cd_restant"]) > 0:
		return false
	var cible: Vector2i = a["cellule"] + P.DIRECTIONS[intention]
	if not traversable(state, index, cible):
		return false
	a["cellule"] = cible
	a["cd_restant"] = int(a["cooldown"])
	return true


# Decompte des cooldowns, un tick. Separe de `appliquer` : le temps s'ecoule pour tout le
# monde, y compris pour qui n'a rien demande.
static func decompter(state) -> void:
	for a in state.acteurs:
		if int(a["cd_restant"]) > 0:
			a["cd_restant"] = int(a["cd_restant"]) - 1
