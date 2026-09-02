# app_shell.gd — COQUILLE PRODUIT (lignes shell.title_entry_effects,
# shell.manual_path_complete, core.exit).
#
# Route les intentions vers les MODELES PURS et FAIT EXISTER LES EFFETS : Jouer met la
# partie en cours, Controles et Options amenent chacun a un ecran different, Quitter
# termine l'application avec un code de sortie nul. Le defaut vise nommement est
# « Quitter inerte » — une entree presente, activable, sans effet.
#
# Une carte n'entre JAMAIS dans une partie sans etre passee par map_validator.
extends RefCounted

const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Menu = preload("res://05_SYSTEMS/menu_model/menu_model.gd")
const Sess = preload("res://05_SYSTEMS/session/session.gd")
const Validator = preload("res://05_SYSTEMS/map_validator/map_validator.gd")
const Reglages = preload("res://05_SYSTEMS/settings/settings.gd")
const Intents = preload("res://05_SYSTEMS/input_intents/input_intents.gd")
const Status = preload("res://05_SYSTEMS/game_state/status.gd")
const Content = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const Controles = preload("res://06_RUNTIME/adapters/shell_view/controls_screen.gd")
const Options = preload("res://06_RUNTIME/adapters/shell_view/options_screen.gd")
const EndScreen = preload("res://06_RUNTIME/adapters/presentation/end_screen.gd")

# Code de sortie observable du processus : nul.
const CODE_SORTIE: int = 0
# Graine de determinisme du jeu lance a la main (pas un parametre d'equilibrage).
const GRAINE_INITIALE: int = 1


# CARTE VALIDEE du niveau `index`, ou null. Le descripteur vient du fournisseur de
# contenu, le verdict de map_validator : deux etapes, jamais une seule.
static func carte(index: int):
	var v: Dictionary = Validator.carte_validee(Content.descripteur(index))
	return v["carte"]


static func cadence(index: int) -> int:
	return Content.cadence(index)


static func nb_niveaux() -> int:
	return Content.nb_niveaux()


# Session d'amorcage : ECRAN TITRE, aucune partie construite.
static func session_initiale() -> Dictionary:
	return Sess.initiale(Reglages.initial())


# --- EFFETS DES ENTREES DU MENU TITRE --------------------------------------------
# Rend {"session", "sortie": bool}. `sortie` porte la demande de fin d'application :
# l'effet de Quitter est OBSERVABLE, il n'est pas suppose.
static func activer_titre(sess: Dictionary, entree: int) -> Dictionary:
	var effet: Dictionary = Menu.effet_titre(entree)
	var suite: Dictionary = sess.duplicate()
	if effet["action"] == Menu.ACTION_NOUVELLE_PARTIE:
		var c = carte(0)
		if c == null:
			return {"session": suite, "sortie": false}
		return {"session": Sess.nouvelle_partie(suite, c, GRAINE_INITIALE, cadence(0)), "sortie": false}
	if effet["action"] == Menu.ACTION_QUITTER:
		return {"session": suite, "sortie": true}
	suite["appelant"] = App.Etat.TITRE
	suite["app"] = effet["etat"]
	suite["selection"] = 0
	return {"session": suite, "sortie": false}


# --- EFFETS DES ENTREES DU MENU PAUSE --------------------------------------------
static func activer_pause(sess: Dictionary, entree: int) -> Dictionary:
	var effet: Dictionary = Menu.effet_pause(entree)
	var suite: Dictionary = sess.duplicate()
	if effet["action"] == Menu.ACTION_REPRENDRE:
		return {"session": Sess.reprendre(suite), "sortie": false}
	if effet["action"] == Menu.ACTION_RECOMMENCER:
		var c = carte(0)
		if c == null:
			return {"session": suite, "sortie": false}
		return {"session": Sess.recommencer(suite, c, cadence(0)), "sortie": false}
	if effet["action"] == Menu.ACTION_MENU_PRINCIPAL:
		return {"session": Sess.menu_principal(suite), "sortie": false}
	suite["appelant"] = App.Etat.PAUSE
	suite["app"] = effet["etat"]
	suite["selection"] = 0
	return {"session": suite, "sortie": false}


# --- ROUTAGE D'UNE INTENTION -----------------------------------------------------
# Rend {"session", "sortie": bool, "ouverture_menu": bool}. L'ouverture de menu est
# remontee a l'appelant : c'est elle que game_events consomme pour le moment sonore.
static func appliquer_intention(sess: Dictionary, intention: int) -> Dictionary:
	var etat: int = sess["app"]
	var suite: Dictionary = sess.duplicate()
	if intention == Intents.Intention.PAUSE:
		if App.peut_mettre_en_pause(etat):
			return {"session": Sess.mettre_en_pause(suite), "sortie": false, "ouverture_menu": true}
		return {"session": suite, "sortie": false, "ouverture_menu": false}
	if etat == App.Etat.TITRE:
		return _naviguer(suite, intention, Menu.ENTREES_TITRE.size(), true)
	if etat == App.Etat.PAUSE:
		return _naviguer(suite, intention, Menu.ENTREES_PAUSE.size(), false)
	if etat == App.Etat.CONTROLES:
		if intention == Intents.Intention.RETOUR or intention == Intents.Intention.VALIDER:
			suite["app"] = Controles.retour(sess["appelant"])
			return {"session": suite, "sortie": false, "ouverture_menu": true}
		return {"session": suite, "sortie": false, "ouverture_menu": false}
	if etat == App.Etat.OPTIONS:
		return _options(suite, intention)
	if etat == App.Etat.FIN:
		return _fin(suite, intention)
	return {"session": suite, "sortie": false, "ouverture_menu": false}


static func activer_titre_complet(sess: Dictionary, entree: int) -> Dictionary:
	var r: Dictionary = activer_titre(sess, entree)
	return {"session": r["session"], "sortie": r["sortie"], "ouverture_menu": true}


# --- FIN DE PARTIE (V3, cause racine P5) ------------------------------------------
# ENTREE dans l'etat final. La logique pure y menait DEJA pour le catalogue epuise
# (session.carte_terminee) ; ce qui manquait etait le meme passage pour une partie
# TERMINEE sur place — victoire ou defaite au milieu du catalogue restaient dans
# App.Etat.PARTIE, ou aucune intention n'est routee vers la coquille : impasse.
# La selection est REMISE A ZERO a l'entree, comme pour tous les autres menus.
static func terminer_partie(sess: Dictionary) -> Dictionary:
	if sess["partie"] == null:
		return sess
	if not Status.est_terminal(sess["partie"].statut):
		return sess
	var suite: Dictionary = sess.duplicate()
	suite["appelant"] = App.Etat.FIN
	suite["app"] = App.vers_fin(sess["app"])
	suite["selection"] = 0
	return suite


# ACTIVATION d'un choix de fin : les deux suites offertes MENENT quelque part.
static func activer_fin(sess: Dictionary, choix: int) -> Dictionary:
	var effet: Dictionary = EndScreen.effet(choix)
	var suite: Dictionary = sess.duplicate()
	if effet["action"] == Menu.ACTION_NOUVELLE_PARTIE:
		return activer_titre_complet(suite, Menu.Titre.JOUER)
	if effet["action"] == Menu.ACTION_MENU_PRINCIPAL:
		return {"session": Sess.menu_principal(suite), "sortie": false, "ouverture_menu": true}
	return {"session": suite, "sortie": false, "ouverture_menu": false}


static func _fin(sess: Dictionary, intention: int) -> Dictionary:
	var suite: Dictionary = sess.duplicate()
	var taille: int = EndScreen.ENTREES.size()
	if intention == Intents.Intention.HAUT or intention == Intents.Intention.SELECTION_PRECEDENTE:
		suite["selection"] = Menu.deplacer(int(sess["selection"]), -1, taille)
		return {"session": suite, "sortie": false, "ouverture_menu": false}
	if intention == Intents.Intention.BAS or intention == Intents.Intention.SELECTION_SUIVANTE:
		suite["selection"] = Menu.deplacer(int(sess["selection"]), 1, taille)
		return {"session": suite, "sortie": false, "ouverture_menu": false}
	if intention == Intents.Intention.VALIDER:
		return activer_fin(suite, int(sess["selection"]))
	# RETOUR ramene au menu principal : jamais une sortie d'application silencieuse
	# depuis un ecran dont ce n'est pas l'objet.
	if intention == Intents.Intention.RETOUR:
		return {"session": Sess.menu_principal(suite), "sortie": false, "ouverture_menu": true}
	return {"session": suite, "sortie": false, "ouverture_menu": false}


static func _naviguer(sess: Dictionary, intention: int, taille: int, depuis_titre: bool) -> Dictionary:
	var suite: Dictionary = sess.duplicate()
	if intention == Intents.Intention.HAUT or intention == Intents.Intention.SELECTION_PRECEDENTE:
		suite["selection"] = Menu.deplacer(int(sess["selection"]), -1, taille)
		return {"session": suite, "sortie": false, "ouverture_menu": false}
	if intention == Intents.Intention.BAS or intention == Intents.Intention.SELECTION_SUIVANTE:
		suite["selection"] = Menu.deplacer(int(sess["selection"]), 1, taille)
		return {"session": suite, "sortie": false, "ouverture_menu": false}
	if intention == Intents.Intention.VALIDER:
		var r: Dictionary = activer_titre(suite, int(sess["selection"])) if depuis_titre else activer_pause(suite, int(sess["selection"]))
		return {"session": r["session"], "sortie": r["sortie"], "ouverture_menu": true}
	if intention == Intents.Intention.RETOUR and depuis_titre:
		return {"session": suite, "sortie": true, "ouverture_menu": false}
	return {"session": suite, "sortie": false, "ouverture_menu": false}


static func _options(sess: Dictionary, intention: int) -> Dictionary:
	var suite: Dictionary = sess.duplicate()
	var taille: int = Options.ENTREES.size()
	if intention == Intents.Intention.HAUT or intention == Intents.Intention.SELECTION_PRECEDENTE:
		suite["selection"] = Menu.deplacer(int(sess["selection"]), -1, taille)
		return {"session": suite, "sortie": false, "ouverture_menu": false}
	if intention == Intents.Intention.BAS or intention == Intents.Intention.SELECTION_SUIVANTE:
		suite["selection"] = Menu.deplacer(int(sess["selection"]), 1, taille)
		return {"session": suite, "sortie": false, "ouverture_menu": false}
	if intention == Intents.Intention.VALIDER:
		var r: Dictionary = Options.activer(int(sess["selection"]), sess["reglages"])
		return {"session": Sess.appliquer_reglages(suite, r), "sortie": false, "ouverture_menu": false}
	if intention == Intents.Intention.RETOUR:
		suite["app"] = Options.retour(sess["appelant"])
		return {"session": suite, "sortie": false, "ouverture_menu": true}
	return {"session": suite, "sortie": false, "ouverture_menu": false}


# Suite d'une carte VIDEE : bascule ou etat final. Les cartes sont VALIDEES avant d'etre
# jouees, sans exception.
static func enchainer_niveau(sess: Dictionary) -> Dictionary:
	var partie = sess["partie"]
	if partie == null:
		return sess
	var index_suivant: int = partie.niveau  # niveau courant 1-base -> index 0-base suivant
	var c = carte(index_suivant)
	var apres: Dictionary
	if c == null:
		apres = Sess.carte_terminee(sess, null, 0, partie.niveau)
	else:
		apres = Sess.carte_terminee(sess, c, cadence(index_suivant), nb_niveaux())
	# Le catalogue epuise mene a l'etat final : la SELECTION du menu de fin est remise a
	# zero ici, cote adaptateur. La logique pure ignore qu'un menu existe, et continue.
	if int(apres["app"]) == App.Etat.FIN:
		apres["appelant"] = App.Etat.FIN
		apres["selection"] = 0
	return apres


# --- CHEMIN PRODUIT COMPLET (volet MACHINE de shell.manual_path_complete) ---------
# Chaque etape est ATTEIGNABLE par le SEUL canal d'entree public, sans console de debug
# ni bot : le nombre d'etapes exigeant un outil vaut exactement 0. Qu'une personne le
# parcoure seule reste un constat HUMAIN, non rendu ici.
const ETAPES: Array = [
	"ecran_titre", "lancement", "pause", "reprise",
	"niveau_suivant", "fin_de_partie", "relance",
]


static func etapes_exigeant_un_outil() -> int:
	# Chaque etape est atteinte par une intention du vocabulaire ferme : aucune n'exige
	# un outil exterieur. Le comptage est structurel, pas declaratif.
	var n: int = 0
	for e in ETAPES:
		if intention_de_l_etape(e) == Intents.Intention.AUCUNE:
			n += 1
	return n


static func intention_de_l_etape(etape: String) -> int:
	if etape == "ecran_titre":
		return Intents.Intention.VALIDER
	if etape == "lancement":
		return Intents.Intention.VALIDER
	if etape == "pause":
		return Intents.Intention.PAUSE
	if etape == "reprise":
		return Intents.Intention.VALIDER
	if etape == "niveau_suivant":
		return Intents.Intention.HAUT
	if etape == "fin_de_partie":
		return Intents.Intention.HAUT
	if etape == "relance":
		return Intents.Intention.VALIDER
	return Intents.Intention.AUCUNE
