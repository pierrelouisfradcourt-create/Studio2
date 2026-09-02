# v2_session_new_game_on_play.gd — ligne session.new_game_on_play, capacite F65.
# Il n'y a AUCUNE partie a l'ecran titre — c'est cette ABSENCE, et non un rendu
# par-dessus, qui satisfait la premiere demande du brief. Une partie neuve est construite
# a la SEULE activation de Jouer.
extends RefCounted

const Sess = preload("res://05_SYSTEMS/session/session.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Menu = preload("res://05_SYSTEMS/menu_model/menu_model.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Shell = preload("res://06_RUNTIME/adapters/app_shell/app_shell.gd")


func run(h) -> void:
	var titre: Dictionary = Shell.session_initiale()
	h.eq(titre["partie"] == null, true, "session.play: aucune partie a l'ecran titre")
	h.eq(Sess.ticks_de_partie(titre), 0, "session.play: 0 tick de partie")
	h.eq(Sess.partie_en_cours(titre), false, "session.play: aucune partie en cours")
	h.eq(int(titre["app"]), App.Etat.TITRE, "session.play: l'application est au titre")

	# Les autres entrees NE construisent PAS de partie.
	for entree in [Menu.Titre.CONTROLES, Menu.Titre.OPTIONS]:
		var r: Dictionary = Shell.activer_titre(titre, entree)
		h.eq(r["session"]["partie"] == null, true, "session.play: cette entree ne lance aucune partie")

	# SEULE l'activation de Jouer construit une partie.
	var jouant: Dictionary = Shell.activer_titre(titre, Menu.Titre.JOUER)["session"]
	h.ok(jouant["partie"] != null, "session.play: Jouer construit une partie")
	h.eq(int(jouant["app"]), App.Etat.PARTIE, "session.play: l'application passe en partie")
	h.eq(jouant["partie"].statut, State.Statut.EN_COURS, "session.play: le statut vaut EN COURS")
	h.eq(Sess.ticks_de_partie(jouant), 0, "session.play: la partie neuve part de 0 tick")

	# LE COMPTEUR PROGRESSE STRICTEMENT une fois la partie lancee.
	var avance = jouant["partie"]
	var precedent: int = avance.ticks
	var croissances: int = 0
	for _t in range(5):
		avance = Loop.step(avance, avance.carte.DEPART_DIRECTION)["etat"]
		if avance.ticks > precedent:
			croissances += 1
		precedent = avance.ticks
	h.eq(croissances, 5, "session.play: le compteur progresse strictement a chaque tick")
	h.eq(avance.ticks, 5, "session.play: cinq ticks joues")
	h.eq(avance.niveau, State.PREMIER_NIVEAU, "session.play: la partie neuve commence au premier niveau")
	h.eq(avance.score >= 0, true, "session.play: le score est defini des le depart")
	# --- GATE MUTATION : les DEUX membres de « une partie tourne-t-elle ? » ----------
	# Une partie TERMINEE existe mais ne tourne plus. Une partie EN COURS tourne. Sans
	# ces deux releves, la conjonction pourrait etre remplacee par l'un ou l'autre de
	# ses membres sans qu'aucune assertion ne bouge.
	var en_cours: Dictionary = Shell.activer_titre(titre, Menu.Titre.JOUER)["session"]
	h.eq(Sess.partie_en_cours(en_cours), true, "session.play: une partie neuve tourne")
	var terminee: Dictionary = en_cours.duplicate()
	terminee["partie"] = en_cours["partie"].clone()
	terminee["partie"].statut = State.Statut.GAGNE
	h.eq(Sess.partie_en_cours(terminee), false, "session.play: une partie gagnee ne tourne plus")
	var perdue: Dictionary = en_cours.duplicate()
	perdue["partie"] = en_cours["partie"].clone()
	perdue["partie"].statut = State.Statut.PERDU
	h.eq(Sess.partie_en_cours(perdue), false, "session.play: une partie perdue non plus")
	h.eq(Sess.partie_en_cours(titre), false, "session.play: et sans partie, rien ne tourne")

	# COMPTEUR DE TICKS : hors partie il vaut 0, EN PARTIE il vaut celui de la partie.
	# Les deux releves sont necessaires : un compteur qui rendrait toujours 0 passerait
	# le premier sans que le second ne le voie.
	var sess_avancee: Dictionary = en_cours.duplicate()
	var jeu_avance = en_cours["partie"]
	for _t in range(7):
		jeu_avance = Loop.step(jeu_avance, jeu_avance.carte.DEPART_DIRECTION)["etat"]
	sess_avancee["partie"] = jeu_avance
	h.eq(Sess.ticks_de_partie(sess_avancee), 7, "session.play: le compteur rend les ticks de la partie")
	h.gt(Sess.ticks_de_partie(sess_avancee), 0, "session.play: il est strictement positif en partie")
	h.eq(Sess.ticks_de_partie(titre), 0, "session.play: et nul hors partie")
