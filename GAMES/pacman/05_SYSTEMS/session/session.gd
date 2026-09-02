# session.gd — LA PARTIE EVENTUELLE (lignes session.new_game_on_play,
# session.resume_identical, session.restart_and_quit_to_title).
#
# Il n'y a AUCUNE partie a l'ecran titre — c'est cette ABSENCE, et non un rendu
# par-dessus, qui satisfait la premiere demande du brief : le compteur de ticks vaut 0
# parce qu'aucune partie n'existe.
#
# Les CARTES sont REMISES en argument : ce module n'ouvre aucun fichier et n'enumere
# aucun contenu. Logique PURE.
extends RefCounted

const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Progression = preload("res://05_SYSTEMS/level_progression/level_progression.gd")
const Reglages = preload("res://05_SYSTEMS/settings/settings.gd")

const CLES: Array = ["app", "appelant", "partie", "graine", "cadence", "reglages", "selection"]


# Session d'amorcage : ecran titre, AUCUNE partie construite.
static func initiale(reglages: Dictionary = {}) -> Dictionary:
	return {
		"app": App.ETAT_INITIAL,
		"appelant": App.ETAT_INITIAL,
		"partie": null,
		"graine": 0,
		"cadence": 0,
		"reglages": Reglages.normaliser(reglages),
		"selection": 0,
	}


static func partie_en_cours(sess: Dictionary) -> bool:
	return sess["partie"] != null and sess["partie"].statut == State.Statut.EN_COURS


# Compteur de ticks de PARTIE : 0 quand aucune partie n'existe.
static func ticks_de_partie(sess: Dictionary) -> int:
	if sess["partie"] == null:
		return 0
	return sess["partie"].ticks


# Statut de partie expose. Hors partie, la valeur rendue est AUCUN STATUT — une valeur
# NOMMEE hors du vocabulaire ferme des trois statuts, jamais « EN COURS » par defaut :
# « aucune partie » et « une partie en cours » doivent rester distinguables.
const AUCUN_STATUT: int = -1


static func statut_de_partie(sess: Dictionary) -> int:
	if sess["partie"] == null:
		return AUCUN_STATUT
	return sess["partie"].statut


# NOUVELLE PARTIE, construite a la SEULE activation de Jouer.
static func nouvelle_partie(sess: Dictionary, carte, graine: int, cadence: int) -> Dictionary:
	var suite: Dictionary = sess.duplicate()
	suite["graine"] = graine
	suite["cadence"] = cadence
	suite["partie"] = State.initial(carte, graine, cadence, sess["reglages"])
	suite["app"] = App.Etat.PARTIE
	return suite


# PAUSE : converge vers l'unique transition de app_state, quelle que soit la source.
static func mettre_en_pause(sess: Dictionary) -> Dictionary:
	var suite: Dictionary = sess.duplicate()
	suite["appelant"] = App.Etat.PAUSE
	suite["app"] = App.vers_pause(sess["app"])
	suite["selection"] = 0
	return suite


# REPRENDRE : restitue l'etat GELE sans le modifier. L'effet correct est de NE RIEN
# CHANGER a la partie, puis de laisser le temps de jeu repartir.
static func reprendre(sess: Dictionary) -> Dictionary:
	var suite: Dictionary = sess.duplicate()
	suite["app"] = App.vers_partie(sess["app"])
	return suite


# RECOMMENCER : reconstruction INTEGRALE d'une partie neuve depuis la pause. Aucune
# valeur de la partie interrompue ne survit, parce que RIEN n'est reutilise.
static func recommencer(sess: Dictionary, carte, cadence: int) -> Dictionary:
	var suite: Dictionary = sess.duplicate()
	suite["cadence"] = cadence
	suite["partie"] = State.initial(carte, sess["graine"], cadence, sess["reglages"])
	suite["app"] = App.Etat.PARTIE
	return suite


# MENU PRINCIPAL : la partie est ABANDONNEE et l'application quitte l'etat partie.
static func menu_principal(sess: Dictionary) -> Dictionary:
	var suite: Dictionary = sess.duplicate()
	suite["partie"] = null
	suite["app"] = App.vers_titre(sess["app"])
	suite["selection"] = 0
	return suite


# Suite d'une carte VIDEE : bascule sur la carte remise en argument, ou etat final
# explicite quand le catalogue est epuise. Aucune relance de l'application.
static func carte_terminee(sess: Dictionary, carte_suivante, cadence_suivante: int, nb_niveaux: int) -> Dictionary:
	var suite: Dictionary = sess.duplicate()
	var partie = sess["partie"]
	if partie == null:
		return suite
	if Progression.suite(partie, nb_niveaux) == Progression.SUITE_CATALOGUE_TERMINE:
		suite["partie"] = Progression.etat_final(partie)
		suite["app"] = App.vers_fin(sess["app"])
		return suite
	suite["partie"] = Progression.basculer(partie, carte_suivante, cadence_suivante, sess["graine"])
	suite["cadence"] = cadence_suivante
	suite["app"] = App.Etat.PARTIE
	return suite


# Reglages modifies depuis l'ecran d'options : repercutes dans la partie en cours.
static func appliquer_reglages(sess: Dictionary, reglages: Dictionary) -> Dictionary:
	var suite: Dictionary = sess.duplicate()
	var r: Dictionary = Reglages.normaliser(reglages)
	suite["reglages"] = r
	if suite["partie"] != null:
		suite["partie"] = suite["partie"].clone()
		suite["partie"].mode = r["mode"]
		suite["partie"].dash_actif = r["dash_actif"]
	return suite
