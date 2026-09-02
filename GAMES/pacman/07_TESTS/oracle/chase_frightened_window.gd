# chase_frightened_window.gd — ligne chase.frightened_window, capacites F27 et F28.
# [F27] Au tick de consommation d'une super-pastille : les QUATRE fantomes sont en etat
# Effraye au MEME tick. [F28] Au tick d'expiration DECLARE : aucun fantome n'est plus en
# Effraye — l'etat prend TOUJOURS fin.
extends RefCounted

const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Pellets = preload("res://05_SYSTEMS/pellets/pellets.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")


# Fixture de couloir droit : un seul fantome dehors, dans le couloir du bas, direction
# DROITE, fenetre Effraye reglee pour expirer (ou non) au tick voulu. Pac-Man est bute
# contre un mur a l'autre bout de la carte : il n'interfere ni par sa position ni par un
# contact.
func _fixture_couloir(depart: Vector2i, effraye_restant: int) -> Object:
	var s = State.initial(Maze, 1)
	s.pac = Vector2i(1, 4)
	s.pac_dir = Maze.HAUT
	s.pac_attente = Maze.AUCUNE
	s.fantomes[0] = depart
	s.dirs_fantomes[0] = Maze.DROITE
	s.dehors[0] = true
	for i in range(1, 4):
		s.dehors[i] = false
		s.fantomes[i] = Maze.PLACES_MAISON[i]
		s.sorties_maison[i] = 99999
	Chase.armer_effraye(s)
	s.effraye_restant = effraye_restant
	Chase.rafraichir_etats(s)
	return s


func run(h) -> void:
	h.eq(Chase.DUREE_EFFRAYE, P.DUREE_EFFRAYE_TICKS, "chase.frightened: duree lue du bloc de parametres")

	# Fixture : Pac-Man a une case d'une super-pastille, les fantomes tous dehors.
	var s = State.initial(Maze, 1)
	var supers: Array = Pellets.positions_super(Maze, s.pastilles)
	var cible: Vector2i = supers[0]
	s.pac = Maze.case_suivante(cible, Maze.BAS)
	s.pac_dir = Maze.HAUT
	s.pac_attente = Maze.AUCUNE
	for i in range(4):
		s.dehors[i] = true
		s.fantomes[i] = Vector2i(21, 8)
		s.sorties_maison[i] = 0
	h.eq(Maze.praticable(s.pac), true, "chase.frightened: fixture — la case de depart est praticable")

	# F27 — au tick de consommation, les QUATRE sont Effrayes au MEME tick.
	var avant: Dictionary = Observable.projeter(s)
	var effrayes_avant: int = 0
	for e in avant["etats_fantomes"]:
		if e == "EFFRAYE":
			effrayes_avant += 1
	h.eq(effrayes_avant, 0, "chase.frightened: aucun Effraye avant la consommation")

	s = Loop.step(s, Maze.HAUT)["etat"]
	h.eq(s.pac, cible, "chase.frightened: Pac-Man a consomme la super-pastille")
	var apres: Dictionary = Observable.projeter(s)
	var effrayes: int = 0
	for e in apres["etats_fantomes"]:
		if e == "EFFRAYE":
			effrayes += 1
	h.eq(effrayes, 4, "chase.frightened: les QUATRE sont Effrayes au meme tick")
	h.eq(apres["effraye_restant"], Chase.DUREE_EFFRAYE, "chase.frightened: la fenetre est armee a sa duree")
	h.eq(apres["rang_capture"], 0, "chase.frightened: le rang de capture repart a zero")

	# F28 — expiration au tick DECLARE : juste avant, encore Effraye ; au tick, plus aucun.
	var tick_expiration: int = s.ticks + Chase.DUREE_EFFRAYE
	var effrayes_juste_avant: int = -1
	var effrayes_au_tick: int = -1
	# Boucle BORNEE : un tick joue sur une partie terminee n'avance pas le compteur, une
	# boucle « tant que ticks < seuil » ne rendrait donc jamais la main.
	for _t in range(Chase.DUREE_EFFRAYE + 5):
		if s.ticks >= tick_expiration:
			break
		var precedent: Dictionary = Observable.projeter(s)
		s = Loop.step(s, Maze.AUCUNE)["etat"]
		if s.ticks == tick_expiration:
			effrayes_juste_avant = 0
			for e in precedent["etats_fantomes"]:
				if e == "EFFRAYE":
					effrayes_juste_avant += 1
			effrayes_au_tick = 0
			for e in Observable.projeter(s)["etats_fantomes"]:
				if e == "EFFRAYE":
					effrayes_au_tick += 1
	h.eq(effrayes_juste_avant, 4, "chase.frightened: encore Effrayes au tick qui precede l'expiration")
	h.eq(effrayes_au_tick, 0, "chase.frightened: PLUS AUCUN Effraye au tick d'expiration declare")
	h.eq(s.effraye_restant, 0, "chase.frightened: la fenetre est refermee")

	# --- LE TICK D'EXPIRATION EST UN TICK DE BASCULE ---------------------------------
	# Le gate de mutation a montre que `bascule = true` (chase_state.gd, fin de fenetre
	# Effraye) pouvait devenir `false` sans qu'aucun test ne bronche. Ce drapeau est ce
	# qui declenche l'inversion de direction des fantomes a la fin de la fenetre : sans
	# lui, la sortie de l'etat Effraye n'est PERCEPTIBLE nulle part.
	var f = State.initial(Maze, 1)
	Chase.armer_effraye(f)
	f.effraye_restant = 5
	h.eq(Chase.avancer(f), false, "chase.frightened: aucune bascule en plein milieu de la fenetre")
	h.eq(f.effraye_restant, 4, "chase.frightened: la fenetre se decompte d'un tick")
	f.effraye_restant = 1
	h.eq(Chase.avancer(f), true, "chase.frightened: le tick d'expiration EST un tick de bascule")
	h.eq(f.effraye_restant, 0, "chase.frightened: la fenetre est refermee au meme tick")
	h.eq(Chase.avancer(f), false, "chase.frightened: le tick suivant n'est plus une bascule")

	# CONSEQUENCE OBSERVABLE de cette bascule : dans un couloir droit, un fantome hors
	# maison REPART EN SENS INVERSE au tick d'expiration. Fixture : couloir du bas
	# (ligne 32), ou la seule sortie est l'avant ou l'arriere — le sens du deplacement
	# est donc entierement determine par l'inversion.
	var couloir := Vector2i(13, 32)
	h.eq(Maze.praticable(Vector2i(13, 31)), false, "chase.frightened: fixture — couloir droit, pas de sortie en haut")
	h.eq(Maze.praticable(Vector2i(13, 33)), false, "chase.frightened: fixture — ni en bas")

	var avec_expiration = _fixture_couloir(couloir, 2)
	var sans_expiration = _fixture_couloir(couloir, 10)
	for _t in range(2):
		avec_expiration = Loop.step(avec_expiration, Maze.AUCUNE)["etat"]
		sans_expiration = Loop.step(sans_expiration, Maze.AUCUNE)["etat"]
	h.eq(avec_expiration.effraye_restant, 0, "chase.frightened: la fenetre a bien expire dans le premier cas")
	h.gt(sans_expiration.effraye_restant, 0, "chase.frightened: elle est encore ouverte dans le temoin")
	h.lt(avec_expiration.fantomes[0].x, couloir.x,
		"chase.frightened: a l'expiration, le fantome repart EN SENS INVERSE")
	h.gt(sans_expiration.fantomes[0].x, couloir.x,
		"chase.frightened: sans expiration, il poursuit son sens initial")

	# L'etat prend TOUJOURS fin : sur 200 ticks de plus, aucun retour spontane en Effraye.
	var retours: int = 0
	for _t in range(200):
		s = Loop.step(s, Maze.AUCUNE)["etat"]
		for e in s.etats_fantomes:
			if e == Chase.Mode.EFFRAYE:
				retours += 1
	h.eq(retours, 0, "chase.frightened: aucun retour spontane en Effraye sur 200 ticks")
