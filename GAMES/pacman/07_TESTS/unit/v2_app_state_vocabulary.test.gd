# v2_app_state_vocabulary.test.gd — ligne app.state_vocabulary, capacite F63.
# L'etat d'APPLICATION est un vocabulaire ferme, exclusif et exhaustif, DISTINCT du
# statut de PARTIE qu'il n'absorbe pas : fusionner les deux rendrait indecidable la
# question « une partie tourne-t-elle derriere ce menu ? ».
extends RefCounted

const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Sess = preload("res://05_SYSTEMS/session/session.gd")


func run(h) -> void:
	h.eq(App.ETATS_VALIDES.size(), 6, "app.vocab: six etats d'application")
	h.eq(App.NOMS.size(), App.ETATS_VALIDES.size(), "app.vocab: un nom par etat")
	h.eq(App.ETAT_INITIAL, App.Etat.TITRE, "app.vocab: l'amorcage est l'ecran titre")

	# EXCLUSIF : aucun etat en double, chacun a un nom propre.
	var noms: Array = []
	var doublons: int = 0
	for e in App.ETATS_VALIDES:
		if noms.has(App.nom(e)):
			doublons += 1
		noms.append(App.nom(e))
	h.eq(doublons, 0, "app.vocab: six noms deux a deux differents")
	h.eq(App.valide(App.Etat.PAUSE), true, "app.vocab: la pause appartient au vocabulaire")
	h.eq(App.valide(42), false, "app.vocab: une valeur hors vocabulaire est refusee")
	h.eq(App.nom(42), "", "app.vocab: un etat inconnu n'a pas de nom, jamais un nom par defaut")

	# JAMAIS VIDE : chaque etat valide porte un nom non vide.
	var vides: int = 0
	for e in App.ETATS_VALIDES:
		if App.nom(e) == "":
			vides += 1
	h.eq(vides, 0, "app.vocab: aucun etat sans nom")

	# DISTINCT du statut de partie : a l'ecran titre, il n'y a PAS de statut EN COURS.
	var sess: Dictionary = Sess.initiale()
	h.eq(int(sess["app"]), App.Etat.TITRE, "app.vocab: l'application est a l'ecran titre")
	h.eq(Sess.statut_de_partie(sess), Sess.AUCUN_STATUT, "app.vocab: aucun statut de partie hors partie")
	h.ok(Sess.statut_de_partie(sess) != State.Statut.EN_COURS,
		"app.vocab: le statut de partie n'est pas EN COURS a l'ecran titre")
	h.eq(Sess.partie_en_cours(sess), false, "app.vocab: aucune partie ne tourne derriere le titre")
	# --- GATE MUTATION : les DEUX membres de la garde d'ecran de consultation --------
	# La transition doit accepter EXACTEMENT les deux ecrans de consultation et refuser
	# tous les autres. Une garde a un seul membre, ou disjonctive, laisserait passer
	# n'importe quelle cible ou renverrait a l'appelant une cible legitime.
	h.eq(App.vers_consultation(App.Etat.CONTROLES, App.Etat.TITRE)["etat"], App.Etat.CONTROLES,
		"app.vocab: l'ecran Controles est une cible de consultation")
	h.eq(App.vers_consultation(App.Etat.OPTIONS, App.Etat.PAUSE)["etat"], App.Etat.OPTIONS,
		"app.vocab: l'ecran Options aussi")
	h.eq(App.vers_consultation(App.Etat.PARTIE, App.Etat.TITRE)["etat"], App.Etat.TITRE,
		"app.vocab: une cible qui n'est pas un ecran de consultation renvoie a l'appelant")
	h.eq(App.vers_consultation(App.Etat.FIN, App.Etat.PAUSE)["etat"], App.Etat.PAUSE,
		"app.vocab: idem depuis la pause")
	h.eq(App.vers_consultation(App.Etat.CONTROLES, App.Etat.PAUSE)["appelant"], App.Etat.PAUSE,
		"app.vocab: l'appelant est memorise tel quel")
