# debug_probe.gd — expose le releve observable a un lecteur EXTERIEUR au runtime
# (ligne probe.observable_stream). Sans ce point de sortie, toute exigence formulee
# « etat expose » n'a aucun observateur et n'est pas verifiable.
# Ne calcule RIEN : il recopie la projection pure de game_state/observable.gd.
extends RefCounted

const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Sess = preload("res://05_SYSTEMS/session/session.gd")
const Reglages = preload("res://05_SYSTEMS/settings/settings.gd")

# Prefixe du canal declare : une ligne par tick sur la sortie standard.
const PREFIXE := "PACMAN_STATE "


# Ligne du canal pour un releve donne.
static func ligne(releve: Dictionary) -> String:
	return PREFIXE + JSON.stringify(releve)


# Emet le releve de l'etat courant sur le canal declare.
static func emettre(s) -> void:
	print(ligne(Observable.projeter(s)))


# Relit une ligne du canal — c'est ce qui rend le lecteur EXTERIEUR possible : il n'a
# besoin d'aucun acces a l'etat interne.
static func relire(ligne_texte: String) -> Dictionary:
	if not ligne_texte.begins_with(PREFIXE):
		return {}
	# Analyse par instance (et non JSON.parse_string) : une charge illisible rend un code
	# d'erreur au lieu de pousser une erreur moteur — le refus est une valeur de retour,
	# pas un bruit dans la sortie de l'oracle.
	var lecteur := JSON.new()
	if lecteur.parse(ligne_texte.substr(PREFIXE.length())) != OK:
		return {}
	var brut = lecteur.data
	if brut == null or not (brut is Dictionary):
		return {}
	return brut


# --- V2 (ligne probe.exposes_app_state) --------------------------------------------
# Expose l'ETAT D'APPLICATION, le compteur de ticks de PARTIE et le MODE DE JEU a un
# lecteur EXTERIEUR au runtime. Sans ce point de sortie, « au moment ou l'ecran titre
# est affiche, le compteur vaut 0 » n'a AUCUN observateur et l'exigence n'est pas
# verifiable. Ne calcule RIEN : il recopie la projection pure — l'autorite des valeurs
# reste a app_state et game_state.
const CLES_SESSION: Array = ["app_etat", "app_nom", "ticks_partie", "statut_partie", "mode_jeu"]


static func projeter_session(sess: Dictionary) -> Dictionary:
	var etat: int = int(sess.get("app", App.ETAT_INITIAL))
	var reglages: Dictionary = Reglages.normaliser(sess.get("reglages", {}))
	var releve: Dictionary = {}
	if sess.get("partie", null) != null:
		releve = Observable.projeter(sess["partie"])
	return {
		"app_etat": etat,
		"app_nom": App.nom(etat),
		"ticks_partie": Sess.ticks_de_partie(sess),
		"statut_partie": Sess.statut_de_partie(sess),
		"mode_jeu": Reglages.nom(reglages["mode"]),
		"releve": releve,
	}


static func ligne_session(sess: Dictionary) -> String:
	return PREFIXE + JSON.stringify(projeter_session(sess))


static func emettre_session(sess: Dictionary) -> void:
	print(ligne_session(sess))


# Trace complete d'une partie : une entree par tick, lisible sans toucher a l'etat.
static func trace(etats: Array) -> Array:
	var sortie: Array = []
	for s in etats:
		sortie.append(Observable.projeter(s))
	return sortie
