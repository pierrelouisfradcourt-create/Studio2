# victory.gd — LA SEULE PLACE ou vit une regle de MODE.
#
# Aucun autre systeme ne connait le nom d'un mode : `game_loop` ordonne, `damage` tue,
# `victory` decide. Ajouter un mode = ajouter une VictoryDefinition ici et la nommer dans
# une carte, jamais une branche dans la boucle.
# Logique PURE.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")


# Statut de partie derive de l'etat. Rend TOUJOURS une des 4 valeurs declarees.
static func evaluer(state) -> int:
	if int(state.ticks) >= P.DUREE_MAX_TICKS:
		return P.NUL
	var vivants: Array = state.vivants()
	match state.regle_victoire:
		P.VICTOIRE_LAST_STANDING:
			return _last_standing(state, vivants)
		P.VICTOIRE_CLEAR_ALL_BOTS:
			return _clear_all_bots(state, vivants)
		_:
			# Regle inconnue : la partie ne peut pas se terminer honnetement. On ne fabrique
			# ni victoire ni defaite — map_validator refuse deja cette carte en amont, donc
			# ce chemin n'est atteignable qu'en contournant le point de passage oblige.
			return P.EN_COURS


# Dernier acteur vivant. Zero vivant = match nul (mort simultanee), jamais une victoire
# attribuee a personne.
static func _last_standing(state, vivants: Array) -> int:
	if state.acteurs.size() <= 1:
		return P.EN_COURS
	if vivants.is_empty():
		return P.NUL
	if vivants.size() > 1:
		return P.EN_COURS
	return P.GAGNE if vivants[0] == P.INDEX_JOUEUR else P.PERDU


# Tous les bots morts. La mort du joueur prime : elle est une defaite meme si elle survient
# au meme tick que celle du dernier bot.
static func _clear_all_bots(state, vivants: Array) -> int:
	if not state.acteurs[P.INDEX_JOUEUR]["vivant"]:
		return P.PERDU
	return P.GAGNE if vivants.size() == 1 else P.EN_COURS
