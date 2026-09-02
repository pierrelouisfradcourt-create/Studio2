# core_error_guard.test.gd — ligne CORE core.error_handling, capacite F12.
# Sur les entrees HORS DOMAINE, l'etat obtenu apres tick reste STRUCTURELLEMENT VALIDE :
# statut parmi les 3 valeurs, aucune entite sur une case de mur,
# consommes + restants == total pose, vies dans [0, valeur initiale].
# Le nombre d'etats invalides produits est EXACTEMENT 0.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const Player = preload("res://05_SYSTEMS/player_movement/player_movement.gd")
# V6 : le preload de end_conditions a disparu avec la constante `VIES_INITIALES` qu'il
# servait a lire. La borne du domaine se demande desormais a settings, source unique de la
# correspondance mode -> vies.
const Reglages = preload("res://05_SYSTEMS/settings/settings.gd")


func run(h) -> void:
	# Jeu d'entrees HORS DOMAINE, chacune nommee.
	var hors_domaine: Array = [
		Maze.AUCUNE,                 # action nulle
		Vector2i(7, 7),              # vecteur qui n'est pas une direction
		Vector2i(-3, 0),             # direction de norme > 1
		Vector2i(1, 1),              # diagonale
		Vector2i(0, -99),            # amplitude absurde
	]
	var invalides: int = 0
	for action in hors_domaine:
		var s = State.initial(Maze, 1)
		for _t in range(30):
			s = Loop.step(s, action)["etat"]
			if not s.est_valide():
				invalides += 1
				break
	h.eq(invalides, 0, "core.error_guard: 0 etat invalide sur les entrees hors domaine")

	# Une direction hors vocabulaire n'est PAS mise en attente : aucun effet de bord.
	var s2 = State.initial(Maze, 1)
	Player.demander(s2, Vector2i(3, 3))
	h.eq(s2.pac_attente, Maze.AUCUNE, "core.error_guard: une direction invalide n'entre pas en file")
	Player.demander(s2, Maze.AUCUNE)
	h.eq(s2.pac_attente, Maze.AUCUNE, "core.error_guard: l'action nulle n'entre pas en file")

	# DEUX directions au meme tick : la file est de profondeur 1, la derniere gagne, et
	# l'etat reste valide.
	var s3 = State.initial(Maze, 1)
	Player.demander(s3, Maze.HAUT)
	Player.demander(s3, Maze.BAS)
	h.eq(s3.pac_attente, Maze.BAS, "core.error_guard: profondeur 1, la derniere demande gagne")
	var apres3 = Loop.step(s3, Maze.GAUCHE)["etat"]
	h.eq(apres3.est_valide(), true, "core.error_guard: etat valide apres demandes multiples")

	# N appuis dans un meme intervalle : rafale de directions, etat toujours valide.
	var s4 = State.initial(Maze, 1)
	var rafale: Array = [Maze.HAUT, Maze.BAS, Maze.GAUCHE, Maze.DROITE, Maze.HAUT, Maze.DROITE]
	var invalides4: int = 0
	for _r in range(20):
		for d in rafale:
			s4 = Loop.step(s4, d)["etat"]
			if not s4.est_valide():
				invalides4 += 1
	h.eq(invalides4, 0, "core.error_guard: 0 etat invalide sur 120 ticks de rafale")

	# Direction IMPRATICABLE : elle reste en attente, Pac-Man conserve sa direction.
	var s5 = State.initial(Maze, 1)
	var mur_dessous: Vector2i = Maze.BAS
	h.eq(Maze.praticable(Maze.case_suivante(s5.pac, mur_dessous)), false,
		"core.error_guard: fixture — la case sous le depart est un mur")
	var apres5 = Loop.step(s5, mur_dessous)["etat"]
	h.eq(apres5.pac_attente, mur_dessous, "core.error_guard: la demande impraticable reste en attente")
	h.eq(apres5.pac_dir, Maze.DEPART_DIRECTION, "core.error_guard: la direction courante est conservee")
	h.eq(apres5.est_valide(), true, "core.error_guard: etat valide malgre la demande impraticable")

	# Invariants structurels, un par un, sur un etat de partie avance.
	var s6 = State.initial(Maze, 1)
	for _t in range(80):
		s6 = Loop.step(s6, Maze.GAUCHE)["etat"]
	h.eq(Maze.praticable(s6.pac), true, "core.error_guard: Pac-Man n'est jamais dans un mur")
	var fantomes_dans_mur: int = 0
	for i in range(s6.fantomes.size()):
		if s6.dehors[i] and not Maze.praticable(s6.fantomes[i]):
			fantomes_dans_mur += 1
	h.eq(fantomes_dans_mur, 0, "core.error_guard: aucun fantome dehors dans un mur")
	# TRIAGE V6 : DECISION_OBSOLETE sur le SYMBOLE, pas sur la garde. `End.VIES_INITIALES`
	# n'existe plus — le nombre de vies depend du mode depuis la decision Pierre du
	# 2026-08-06. La borne utilisee ici est celle DU MODE de l'etat mesure, donc STRICTEMENT
	# plus serree que l'ancienne : l'assertion est renforcee, pas affaiblie.
	h.ok(s6.vies >= 0 and s6.vies <= Reglages.vies_initiales(s6.mode),
		"core.error_guard: vies dans le domaine de leur mode")
	h.ok(s6.statut in State.STATUTS_VALIDES, "core.error_guard: statut dans le vocabulaire")
	h.eq(s6.est_valide(), true, "core.error_guard: etat structurellement valide apres 80 ticks")

	# CONTRE-EPREUVE du validateur : un etat volontairement casse doit etre REFUSE.
	# Sans elle, est_valide pourrait rendre vrai en toutes circonstances.
	var casse = State.initial(Maze, 1)
	casse.pac = Vector2i(0, 0)
	h.eq(casse.est_valide(), false, "core.error_guard: un Pac-Man dans un mur est refuse")
	var casse2 = State.initial(Maze, 1)
	# TRIAGE V6 : DECISION_OBSOLETE sur le symbole. La borne du DOMAINE est desormais la
	# plus grande valeur qu'un mode puisse accorder — c'est elle que le validateur applique,
	# et c'est donc elle qu'il faut depasser pour exercer le refus.
	casse2.vies = Reglages.vies_maximales() + 1
	h.eq(casse2.est_valide(), false, "core.error_guard: un compteur de vies hors domaine est refuse")
	var casse3 = State.initial(Maze, 1)
	casse3.consommees = 5
	h.eq(casse3.est_valide(), false, "core.error_guard: une comptabilite de collectibles rompue est refusee")

	# --- LES TROIS REFUS QUI N'ETAIENT PAS EXERCES -----------------------------------
	# Le gate de mutation a montre que trois `return false` de est_valide() pouvaient
	# devenir `return true` sans qu'aucun test ne bronche : leurs conditions n'etaient
	# jamais violees par une fixture. Un validateur dont on n'observe jamais le refus ne
	# valide rien. Chaque cas est exerce ISOLEMENT, sur un etat par ailleurs conforme.

	# (1) Statut hors du vocabulaire ferme.
	var statut_inconnu = State.initial(Maze, 1)
	statut_inconnu.statut = 99
	h.eq(statut_inconnu.statut in State.STATUTS_VALIDES, false,
		"core.error_guard: fixture — 99 n'appartient pas au vocabulaire de statuts")
	h.eq(statut_inconnu.est_valide(), false, "core.error_guard: un statut hors vocabulaire est REFUSE")

	# (2) Fantome DEHORS pose sur une case de mur.
	var fantome_dans_mur = State.initial(Maze, 1)
	fantome_dans_mur.dehors[0] = true
	fantome_dans_mur.fantomes[0] = Vector2i(0, 0)
	h.eq(Maze.praticable(Vector2i(0, 0)), false, "core.error_guard: fixture — (0,0) est bien un mur")
	h.eq(fantome_dans_mur.est_valide(), false, "core.error_guard: un fantome dehors dans un mur est REFUSE")

	# Le meme fantome, DANS la maison, est legitime : le refus porte sur `dehors`, pas
	# sur la position seule — sans cette contre-epreuve, un validateur trop severe
	# passerait pour correct.
	var fantome_en_maison = State.initial(Maze, 1)
	fantome_en_maison.dehors[1] = false
	h.eq(Maze.praticable(fantome_en_maison.fantomes[1]), false,
		"core.error_guard: fixture — la place de maison n'est pas praticable")
	h.eq(fantome_en_maison.est_valide(), true, "core.error_guard: un fantome EN MAISON reste valide")

	# (3) Etat expose d'un fantome hors du vocabulaire ferme des trois modes.
	var mode_inconnu = State.initial(Maze, 1)
	mode_inconnu.etats_fantomes[2] = 99
	h.eq(mode_inconnu.est_valide(), false, "core.error_guard: un mode de fantome hors vocabulaire est REFUSE")
	var mode_inconnu_dernier = State.initial(Maze, 1)
	mode_inconnu_dernier.etats_fantomes[3] = -1
	h.eq(mode_inconnu_dernier.est_valide(), false,
		"core.error_guard: le refus porte sur les QUATRE fantomes, pas seulement le premier")
