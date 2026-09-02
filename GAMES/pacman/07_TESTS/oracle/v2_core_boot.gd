# v2_core_boot.gd — ligne core.boot, capacites F63/F64.
# Le jeu demarre et atteint un etat initial OBSERVABLE. En V2 cet etat initial est
# l'ECRAN TITRE, aucune partie construite : le boot est constate sur l'etat d'application
# expose au lecteur exterieur, jamais sur un rendu.
extends RefCounted

const Boot = preload("res://06_RUNTIME/adapters/runtime_loop/boot.gd")
const Probe = preload("res://06_RUNTIME/adapters/debug_probe/debug_probe.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Sess = preload("res://05_SYSTEMS/session/session.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")


func run(h) -> void:
	var sess: Dictionary = Boot.session_initiale()
	var releve: Dictionary = Probe.projeter_session(sess)
	h.eq(App.valide(int(releve["app_etat"])), true, "core.boot: l'etat expose appartient au vocabulaire ferme")
	h.ok(String(releve["app_nom"]) != "", "core.boot: il n'est jamais vide")
	h.eq(releve["app_nom"], "TITRE", "core.boot: l'etat initial est l'ecran titre")
	h.eq(releve["ticks_partie"], 0, "core.boot: le compteur de ticks de partie vaut 0")
	h.ok(releve["statut_partie"] != State.Statut.EN_COURS, "core.boot: le statut n'est pas EN COURS")
	h.eq(sess["partie"] == null, true, "core.boot: aucune partie n'est construite")
	h.eq(Sess.partie_en_cours(sess), false, "core.boot: aucune partie ne tourne")

	# LE BOOT est atteint SANS aucun geste : zero appui, zero ecran intercale.
	h.eq(int(Boot.session_initiale()["app"]), App.ETAT_INITIAL, "core.boot: amorcage direct sur l'etat declare")
	h.eq(Probe.ligne_session(sess).begins_with(Probe.PREFIXE), true, "core.boot: le canal expose le boot")
	h.eq(Probe.relire(Probe.ligne_session(sess))["app_nom"], "TITRE", "core.boot: relisible de l'exterieur")
