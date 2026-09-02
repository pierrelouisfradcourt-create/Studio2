# v2_runtime_title_boot_no_game.gd — ligne runtime.title_boot_no_game, capacite F64.
# L'application amorce SUR L'ECRAN TITRE : aucune partie n'est construite au demarrage.
# Consequence MECANIQUE — le compteur de ticks vaut 0 parce qu'aucune partie n'existe,
# PAS parce qu'un rendu la masque.
extends RefCounted

const Boot = preload("res://06_RUNTIME/adapters/runtime_loop/boot.gd")
const RuntimeLoop = preload("res://06_RUNTIME/adapters/runtime_loop/runtime_loop.gd")
const Probe = preload("res://06_RUNTIME/adapters/debug_probe/debug_probe.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Sess = preload("res://05_SYSTEMS/session/session.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")


func run(h) -> void:
	var sess: Dictionary = Boot.session_initiale()
	h.eq(int(sess["app"]), App.Etat.TITRE, "runtime.titre: l'amorcage est l'ecran titre")
	h.eq(sess["partie"] == null, true, "runtime.titre: aucune partie construite")
	h.eq(Sess.ticks_de_partie(sess), 0, "runtime.titre: le compteur de ticks vaut 0")
	h.ok(Sess.statut_de_partie(sess) != State.Statut.EN_COURS, "runtime.titre: le statut n'est pas EN COURS")
	h.eq(RuntimeLoop.tick_autorise(sess), false, "runtime.titre: aucun tick n'est autorise")

	# LE LECTEUR EXTERIEUR le constate sans acces a l'etat interne.
	var releve: Dictionary = Probe.projeter_session(sess)
	h.eq(releve["app_nom"], "TITRE", "runtime.titre: l'etat d'application est expose")
	h.eq(releve["ticks_partie"], 0, "runtime.titre: le compteur expose vaut 0")
	h.eq(releve["releve"].is_empty(), true, "runtime.titre: aucun releve de partie a exposer")

	# LA FENETRE est dimensionnee sans qu'aucune partie soit lancee.
	h.gt(Boot.largeur_fenetre(), 0, "runtime.titre: largeur de fenetre declaree")
	h.gt(Boot.hauteur_fenetre(), 0, "runtime.titre: hauteur de fenetre declaree")
	h.eq(Boot.fenetre_contient_grille(Boot.largeur_fenetre(), Boot.hauteur_fenetre()), true,
		"runtime.titre: la fenetre contient la grille entiere")
	h.ok(Boot.carte_de_reference() != null, "runtime.titre: la carte de reference est validee")

	# Deux amorcages donnent la MEME session : rien n'est herite.
	var bis: Dictionary = Boot.session_initiale()
	h.eq(int(bis["app"]), int(sess["app"]), "runtime.titre: deux amorcages donnent le meme etat")
	h.eq(bis["partie"] == null, true, "runtime.titre: et toujours aucune partie")
