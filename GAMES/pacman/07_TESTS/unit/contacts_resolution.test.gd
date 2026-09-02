# contacts_resolution.test.gd — ligne contacts.resolution, capacite F35.
# Au tick du contact avec un fantome Effraye : le compteur de vies est INCHANGE — le
# contact est une capture, pas une mort.
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())

const Contacts = preload("res://05_SYSTEMS/contacts/contacts.gd")
const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const House = preload("res://05_SYSTEMS/ghost_house/ghost_house.gd")


func run(h) -> void:
	# Contact avec un fantome EFFRAYE : capture, vies inchangees.
	var s = State.initial(Maze, 1)
	Chase.armer_effraye(s)
	s.dehors[0] = true
	var vies_avant: int = s.vies
	var issue: Dictionary = Contacts.resoudre(s, [0])
	h.eq(s.vies, vies_avant, "contacts.resolve: Effraye -> vies INCHANGEES")
	h.eq(issue["hostile"], false, "contacts.resolve: Effraye -> issue non hostile")
	h.eq(issue["captures"].size(), 1, "contacts.resolve: Effraye -> une capture")
	h.eq(s.dehors[0], false, "contacts.resolve: le fantome capture rentre a la maison")

	# Contact avec un fantome HOSTILE : signale hostile, aucune capture, score inchange.
	var t = State.initial(Maze, 1)
	t.dehors[0] = true
	var score_avant: int = t.score
	var issue2: Dictionary = Contacts.resoudre(t, [0])
	h.eq(issue2["hostile"], true, "contacts.resolve: hostile -> issue hostile")
	h.eq(issue2["captures"], [], "contacts.resolve: hostile -> aucune capture")
	h.eq(t.score, score_avant, "contacts.resolve: hostile -> score inchange")
	h.eq(t.dehors[0], true, "contacts.resolve: le fantome hostile reste dehors")
	# La perte de vie N'EST PAS appliquee ici : end_conditions en est l'unique proprietaire.
	h.eq(t.vies, State.initial(Maze, 1).vies, "contacts.resolve: contacts ne touche pas au compteur de vies")

	# Rangs successifs dans une MEME fenetre Effraye : 200, puis 400, puis 800, 1600.
	var u = State.initial(Maze, 1)
	Chase.armer_effraye(u)
	for i in range(4):
		u.dehors[i] = true
		u.effrayes[i] = true
	Chase.rafraichir_etats(u)
	var gains: Array = []
	for i in range(4):
		var avant: int = u.score
		Contacts.resoudre(u, [i])
		gains.append(u.score - avant)
	h.eq(gains, [200, 400, 800, 1600], "contacts.resolve: rangs 200/400/800/1600")
	h.eq(u.rang_capture, 4, "contacts.resolve: quatre rangs consommes")

	# Contact MIXTE au meme tick : la capture a lieu ET l'issue hostile est signalee.
	var v = State.initial(Maze, 1)
	Chase.armer_effraye(v)
	v.dehors[0] = true
	v.dehors[1] = true
	v.effrayes[1] = false
	Chase.rafraichir_etats(v)
	var issue3: Dictionary = Contacts.resoudre(v, [0, 1])
	h.eq(issue3["captures"], [0], "contacts.resolve: mixte -> le fantome Effraye est capture")
	h.eq(issue3["hostile"], true, "contacts.resolve: mixte -> l'hostile est signale")

	# Aucun contact : aucune capture, aucune issue hostile, aucun effet de bord.
	var w = State.initial(Maze, 1)
	var score_w: int = w.score
	var issue4: Dictionary = Contacts.resoudre(w, [])
	h.eq(issue4["captures"], [], "contacts.resolve: liste vide -> aucune capture")
	h.eq(issue4["hostile"], false, "contacts.resolve: liste vide -> aucune issue hostile")
	h.eq(w.score, score_w, "contacts.resolve: liste vide -> score inchange")
