# route_planner.gd — planification d'itineraire du bot de solvabilite
# (lignes solvability.route_plan, bot.solvability_per_map). Adaptateur : il consomme les
# systemes purs, jamais l'inverse.
#
# V2 : le planificateur ne connait AUCUNE carte en propre. Toutes ses tables sont
# construites depuis la CARTE PORTEE PAR L'ETAT, et mises en cache par identifiant de
# carte : la meme politique s'applique donc a chaque carte du catalogue, sans qu'aucune
# constante de topologie soit ecrite ici.
#
# CORRECTION B1 (red-team s6) : la planification est en BOUCLE FERMEE. Aucun itineraire
# n'est calcule une fois pour toutes — a CHAQUE tick le planificateur relit l'etat
# courant (positions ET etats des quatre fantomes compris) et recalcule son pas. C'est
# ce qui lui permet de constater une perte de vie (les entites reviennent au depart, les
# pastilles consommees restent consommees) sans aucun index d'itineraire a resynchroniser.
#
# Determinisme : ordre de voisins FIXE (maze.DIRECTIONS), parcours en largeur sur des
# tableaux PLATS indexes par carte.index_de — jamais un parcours de Dictionary, jamais
# un randi(). Meme etat -> meme pas, toujours.
extends RefCounted

const Maze = preload("res://05_SYSTEMS/maze/maze.gd")
const Pellets = preload("res://05_SYSTEMS/pellets/pellets.gd")
const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")

# Marge de securite : une case n'est empruntee que si le bot y arrive au moins
# MARGE_SECURITE pas avant le poursuivant le plus proche. Valeur MESUREE sur les 50
# graines de l'oracle V1 : 1 -> 45 victoires, 3 -> 46, 2 -> 49. Trop prudent, le bot se
# prive de couloirs praticables et finit acule ; trop confiant, il se fait prendre.
# V2 : la meme valeur est appliquee a CHAQUE carte du catalogue, et le resultat est
# MESURE carte par carte plutot que suppose transposable.
const MARGE_SECURITE: int = 2
# Distance maximale a laquelle le bot detourne son itineraire pour croquer un fantome
# Effraye (le fantome bouge : au-dela, la poursuite gaspille des ticks).
const PORTEE_CHASSE_EFFRAYE: int = 6
# En deca de cette distance a un poursuivant, une super-pastille atteignable devient
# prioritaire sur la pastille la plus proche : elle RETOURNE la menace au lieu de la fuir.
const MENACE_PRIORITE_SUPER: int = 10
# En deca de cette distance a un poursuivant, le pas glouton est VERIFIE par simulation
# du vrai tick du jeu. Au-dela, la verification ne changerait rien et couterait cher.
const SEUIL_VERIFICATION: int = 12
# Profondeur de la simulation de verification, en ticks.
const PROFONDEUR_ROLLOUT: int = 10

const INACCESSIBLE: int = -1
const NB_DIRECTIONS: int = 4

# Tables pre-calculees UNE fois PAR CARTE depuis la carte elle-meme (qui reste la source
# unique de topologie) : _voisins[i * 4 + k] = index de la case atteinte depuis i par la
# direction k, ou INACCESSIBLE si elle n'est pas praticable ; _praticables = liste des
# index de cases praticables. Sans ces tables, le parcours en largeur refait a chaque
# arete un calcul de Vector2i et une lecture de type : le bot joue des centaines de
# milliers de pas par partie, la difference se mesure en minutes.
static var _cache: Dictionary = {}


static func _tables_de(carte) -> Dictionary:
	if _cache.has(carte.ID):
		return _cache[carte.ID]
	var nb: int = carte.nb_cases()
	var v := PackedInt32Array()
	v.resize(nb * NB_DIRECTIONS)
	v.fill(INACCESSIBLE)
	var libres := PackedInt32Array()
	for i in range(nb):
		var c: Vector2i = carte.case_de(i)
		if not carte.praticable(c):
			continue
		libres.append(i)
		for k in range(NB_DIRECTIONS):
			var n: Vector2i = carte.case_suivante(c, Maze.DIRECTIONS[k])
			if carte.praticable(n):
				v[i * NB_DIRECTIONS + k] = carte.index_de(n)
	var t: Dictionary = {"voisins": v, "praticables": libres, "nb_cases": nb}
	_cache[carte.ID] = t
	return t


static func tables(carte) -> PackedInt32Array:
	return _tables_de(carte)["voisins"]


static func cases_praticables(carte) -> PackedInt32Array:
	return _tables_de(carte)["praticables"]


static func nb_cases(carte) -> int:
	return _tables_de(carte)["nb_cases"]


# Parcours en largeur MULTI-SOURCE sur les cases praticables (bouclage de tunnel
# compris). Rend un tableau plat de distances ; INACCESSIBLE la ou rien n'atteint.
static func distances_depuis(carte, sources: Array) -> PackedInt32Array:
	var voisins: PackedInt32Array = tables(carte)
	var d := PackedInt32Array()
	d.resize(nb_cases(carte))
	d.fill(INACCESSIBLE)
	var file := PackedInt32Array()
	for p in sources:
		if not carte.praticable(p):
			continue
		var i: int = carte.index_de(p)
		if d[i] == INACCESSIBLE:
			d[i] = 0
			file.append(i)
	var tete: int = 0
	while tete < file.size():
		var i: int = file[tete]
		tete += 1
		var suivant: int = d[i] + 1
		for k in range(NB_DIRECTIONS):
			var j: int = voisins[i * NB_DIRECTIONS + k]
			if j == INACCESSIBLE or d[j] != INACCESSIBLE:
				continue
			d[j] = suivant
			file.append(j)
	return d


# Cases des poursuivants ACTUELS : fantomes hors maison qui ne sont PAS Effrayes.
static func poursuivants(s) -> Array:
	var sortie: Array = []
	for i in range(s.fantomes.size()):
		if s.dehors[i] and s.etats_fantomes[i] != Chase.Mode.EFFRAYE:
			sortie.append(s.fantomes[i])
	return sortie


# Cases des fantomes Effrayes hors maison (proies, pas menaces).
static func proies(s) -> Array:
	var sortie: Array = []
	for i in range(s.fantomes.size()):
		if s.dehors[i] and s.etats_fantomes[i] == Chase.Mode.EFFRAYE:
			sortie.append(s.fantomes[i])
	return sortie


# Parcours en largeur SUR depuis Pac-Man : une case n'est franchie que si le bot y
# arrive strictement plus tot qu'un poursuivant, avec la marge declaree. Rend les
# distances et, pour chaque case, l'INDEX de la premiere direction a jouer pour y aller.
static func exploration_sure(carte, depart: Vector2i, menace: PackedInt32Array, marge: int) -> Dictionary:
	var voisins: PackedInt32Array = tables(carte)
	var nb: int = nb_cases(carte)
	var d := PackedInt32Array()
	d.resize(nb)
	d.fill(INACCESSIBLE)
	var premier := PackedInt32Array()
	premier.resize(nb)
	premier.fill(INACCESSIBLE)
	var file := PackedInt32Array()
	var depart_i: int = carte.index_de(depart)
	if not carte.praticable(depart):
		return {"distance": d, "premier": premier}
	# Une carte de menace VIDE signifie « aucun filtre de securite » : l'exploration
	# couvre alors tout le labyrinthe atteignable (cas du dernier recours).
	var filtre: bool = not menace.is_empty()
	d[depart_i] = 0
	file.append(depart_i)
	var tete: int = 0
	while tete < file.size():
		var i: int = file[tete]
		tete += 1
		var cout: int = d[i] + 1
		for k in range(NB_DIRECTIONS):
			var j: int = voisins[i * NB_DIRECTIONS + k]
			if j == INACCESSIBLE or d[j] != INACCESSIBLE:
				continue
			if filtre and menace[j] != INACCESSIBLE and menace[j] <= cout + marge:
				continue
			d[j] = cout
			premier[j] = k if i == depart_i else premier[i]
			file.append(j)
	return {"distance": d, "premier": premier}


# Case-cible retenue : la case SURE la plus proche portant un collectible ; a defaut,
# une proie Effrayee a portee ; a defaut, INACCESSIBLE.
static func cible_utile(s, exploration: Dictionary, menace_courante: int) -> int:
	var carte = s.carte
	var d: PackedInt32Array = exploration["distance"]
	var meilleure: int = INACCESSIBLE
	var meilleure_d: int = 0
	for p in proies(s):
		var ip: int = carte.index_de(p)
		if d[ip] == INACCESSIBLE or d[ip] > PORTEE_CHASSE_EFFRAYE:
			continue
		if d[ip] >= s.effraye_restant:
			continue
		if meilleure == INACCESSIBLE or d[ip] < meilleure_d:
			meilleure = ip
			meilleure_d = d[ip]
	if meilleure != INACCESSIBLE:
		return meilleure
	var libres: PackedInt32Array = cases_praticables(carte)
	# Sous la menace, une super-pastille atteignable prime sur la pastille la plus
	# proche : elle RETOURNE la situation (les poursuivants deviennent des proies) au
	# lieu de la subir. Hors menace, elle n'a aucune priorite — sinon le bot irait
	# gaspiller ses quatre fenetres Effraye au calme.
	var menace_ici: int = menace_courante
	if menace_ici != INACCESSIBLE and menace_ici <= MENACE_PRIORITE_SUPER:
		for n in range(libres.size()):
			var i: int = libres[n]
			if s.pastilles[i] != Pellets.Contenu.SUPER or d[i] == INACCESSIBLE:
				continue
			if meilleure == INACCESSIBLE or d[i] < meilleure_d:
				meilleure = i
				meilleure_d = d[i]
		if meilleure != INACCESSIBLE:
			return meilleure
	for n in range(libres.size()):
		var i: int = libres[n]
		if s.pastilles[i] == Pellets.Contenu.VIDE:
			continue
		if d[i] == INACCESSIBLE:
			continue
		if meilleure == INACCESSIBLE or d[i] < meilleure_d:
			meilleure = i
			meilleure_d = d[i]
	return meilleure


# Repli : la case SURE la plus eloignee des poursuivants. Rend INACCESSIBLE si aucune.
static func case_de_repli(carte, exploration: Dictionary, menace: PackedInt32Array) -> int:
	var d: PackedInt32Array = exploration["distance"]
	var meilleure: int = INACCESSIBLE
	var meilleure_m: int = -2
	var libres: PackedInt32Array = cases_praticables(carte)
	var nb: int = nb_cases(carte)
	for n in range(libres.size()):
		var i: int = libres[n]
		if d[i] == INACCESSIBLE:
			continue
		var m: int = menace[i]
		var valeur: int = nb if m == INACCESSIBLE else m
		if valeur > meilleure_m:
			meilleure_m = valeur
			meilleure = i
	return meilleure


# Dernier recours, quand AUCUNE case sure n'existe. Un choix a UN pas est presque
# toujours fatal ici : le bot regarde donc le labyrinthe entier SANS filtre de securite
# et vise la case qui maximise la marge atteignable (distance du poursuivant moins la
# sienne). Egalites departagees par l'ordre fixe des directions, puis par index.
static func pas_desespere(s, menace: PackedInt32Array) -> Vector2i:
	var carte = s.carte
	var nb: int = nb_cases(carte)
	var libre: Dictionary = exploration_sure(carte, s.pac, PackedInt32Array(), 0)
	var d: PackedInt32Array = libre["distance"]
	var premier: PackedInt32Array = libre["premier"]
	var cibles: PackedInt32Array = cases_praticables(carte)
	var meilleure: int = INACCESSIBLE
	var meilleure_marge: int = -nb
	for n in range(cibles.size()):
		var i: int = cibles[n]
		if d[i] == INACCESSIBLE or premier[i] == INACCESSIBLE:
			continue
		var m: int = menace[i]
		var valeur: int = nb if m == INACCESSIBLE else m
		var marge: int = valeur - d[i]
		if marge > meilleure_marge:
			meilleure_marge = marge
			meilleure = i
	if meilleure != INACCESSIBLE:
		return Maze.DIRECTIONS[premier[meilleure]]
	# Aucune case atteignable : on reste sur place plutot que d'inventer un deplacement.
	return Maze.AUCUNE


# Pas GLOUTON : cible utile sure, sinon repli, sinon dernier recours. Fonction PURE de
# l'etat, sans aucune simulation — c'est la politique de base.
static func pas_glouton(s) -> Vector2i:
	var carte = s.carte
	var menace: PackedInt32Array = distances_depuis(carte, poursuivants(s))
	var exploration: Dictionary = exploration_sure(carte, s.pac, menace, MARGE_SECURITE)
	var cible: int = cible_utile(s, exploration, menace[carte.index_de(s.pac)])
	if cible == INACCESSIBLE:
		cible = case_de_repli(carte, exploration, menace)
	var premier: PackedInt32Array = exploration["premier"]
	if cible != INACCESSIBLE and premier[cible] != INACCESSIBLE:
		return Maze.DIRECTIONS[premier[cible]]
	return pas_desespere(s, menace)


# Une direction coute-t-elle une vie dans les PROFONDEUR_ROLLOUT ticks qui suivent ?
# Le pas glouton raisonne sur des distances a l'instant t ; il ne voit pas deux
# poursuivants qui se referment. Ici le bot fait JOUER le vrai tick du jeu (jamais un
# modele approche du moteur) et LIT le compteur de vies : une direction qui coute une
# vie est rejetee avant d'etre emise.
static func coute_une_vie(s, direction: Vector2i) -> bool:
	var Loop = load("res://05_SYSTEMS/game_loop/game_loop.gd")
	var vies_depart: int = s.vies
	var courant = Loop.step(s, direction)["etat"]
	if courant.vies < vies_depart:
		return true
	for _t in range(PROFONDEUR_ROLLOUT - 1):
		if courant.statut != 0:
			break
		courant = Loop.step(courant, pas_glouton(courant))["etat"]
		if courant.vies < vies_depart:
			return true
	return false


# LE pas du tick : direction du vocabulaire ferme, ou AUCUNE. Fonction PURE et
# DETERMINISTE de l'etat — meme etat, meme pas, toujours.
static func prochain_pas(s) -> Vector2i:
	var carte = s.carte
	var menace: PackedInt32Array = distances_depuis(carte, poursuivants(s))
	var glouton: Vector2i = pas_glouton(s)
	# La verification par simulation ne se declenche qu'a proximite d'un poursuivant :
	# hors danger elle ne changerait rien et couterait le prix fort a chaque tick.
	var menace_ici: int = menace[carte.index_de(s.pac)]
	if menace_ici == INACCESSIBLE or menace_ici > SEUIL_VERIFICATION:
		return glouton
	if not coute_une_vie(s, glouton):
		return glouton
	# Le pas glouton est fatal : on essaie les autres directions praticables dans
	# l'ordre FIXE, et l'on garde la premiere qui ne coute pas de vie.
	for dir in Maze.DIRECTIONS:
		if dir == glouton:
			continue
		if not carte.praticable(carte.case_suivante(s.pac, dir)):
			continue
		if not coute_une_vie(s, dir):
			return dir
	# Aucune direction ne sauve : le bot joue quand meme son pas glouton, sans pretendre
	# qu'il est sur. La perte de vie est alors CONSTATEE, pas masquee.
	return glouton


# Couverture de l'itineraire REELLEMENT parcouru, pour la preuve F53 : le bot est
# joue en boucle fermee sur un budget de ticks DECLARE en entree, et l'on constate
# combien de collectibles il a effectivement couverts.
static func couverture(s_depart, budget: int) -> Dictionary:
	var Loop = load("res://05_SYSTEMS/game_loop/game_loop.gd")
	var s = s_depart.clone()
	var t: int = 0
	while t < budget and s.statut == 0:
		s = Loop.step(s, prochain_pas(s))["etat"]
		t += 1
	return {"consommees": s.consommees, "total_pose": s.total_pose, "ticks": t, "etat": s}
