# v2_probe_exposes_app_state.gd — ligne probe.exposes_app_state, capacites F63/F81.
# Expose a un lecteur EXTERIEUR au runtime le releve observable ET l'etat d'application,
# le compteur de ticks de partie et le mode de jeu. Sans ce point de sortie, « au moment
# ou l'ecran titre est affiche, le compteur vaut 0 » n'a AUCUN observateur.
extends RefCounted

const Probe = preload("res://06_RUNTIME/adapters/debug_probe/debug_probe.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Sess = preload("res://05_SYSTEMS/session/session.gd")
const Menu = preload("res://05_SYSTEMS/menu_model/menu_model.gd")
const Shell = preload("res://06_RUNTIME/adapters/app_shell/app_shell.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")


func run(h) -> void:
	var titre: Dictionary = Shell.session_initiale()
	var releve: Dictionary = Probe.projeter_session(titre)
	for cle in Probe.CLES_SESSION:
		h.eq(releve.has(cle), true, "probe.app: la cle %s est exposee" % cle)

	h.eq(releve["app_nom"], "TITRE", "probe.app: l'etat d'application est nomme")
	h.eq(releve["ticks_partie"], 0, "probe.app: 0 tick de partie a l'ecran titre")
	h.eq(releve["statut_partie"], Sess.AUCUN_STATUT, "probe.app: aucun statut de partie")
	h.ok(releve["statut_partie"] != State.Statut.EN_COURS, "probe.app: le statut n'est pas EN COURS")
	h.eq(releve["mode_jeu"], "NORMAL", "probe.app: le mode de jeu est expose")
	h.ok(releve["app_nom"] != "", "probe.app: l'etat d'application n'est jamais vide")

	# LE CANAL est relisible par un lecteur EXTERIEUR, sans acces a l'etat interne.
	var ligne: String = Probe.ligne_session(titre)
	h.eq(ligne.begins_with(Probe.PREFIXE), true, "probe.app: la ligne porte le prefixe declare")
	var relu: Dictionary = Probe.relire(ligne)
	h.eq(relu.is_empty(), false, "probe.app: la ligne est relisible")
	h.eq(String(relu["app_nom"]), "TITRE", "probe.app: le lecteur exterieur lit l'etat d'application")
	h.eq(int(relu["ticks_partie"]), 0, "probe.app: il lit le compteur de ticks")
	h.eq(Probe.relire("bruit sans prefixe").is_empty(), true, "probe.app: une ligne etrangere est refusee")

	# APRES Jouer : l'etat expose change, le compteur devient celui de la partie.
	var jouant: Dictionary = Shell.activer_titre(titre, Menu.Titre.JOUER)["session"]
	var r2: Dictionary = Probe.projeter_session(jouant)
	h.eq(r2["app_nom"], "PARTIE", "probe.app: l'etat d'application suit")
	h.eq(r2["statut_partie"], State.Statut.EN_COURS, "probe.app: le statut de partie devient EN COURS")
	h.eq(r2["releve"].is_empty(), false, "probe.app: le releve de partie est expose")

	# LE MODE reste dans l'ensemble des deux valeurs a chaque releve.
	h.eq(r2["mode_jeu"] == "NORMAL" or r2["mode_jeu"] == "TEST", true,
		"probe.app: le mode expose appartient au vocabulaire ferme")
