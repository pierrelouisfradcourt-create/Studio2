# bot_policy.gd — politique DETERMINISTE de decision, pour le bot teste comme pour ses
# adversaires. Ne modifie JAMAIS l'etat : elle rend une intention, que la boucle applique
# par le MEME canal public que le clavier. Un bot qui ecrirait dans l'etat ne prouverait
# rien du jeu.
#
# Consomme la brique copiee `05_SYSTEMS/grid_nav/grid_nav.gd` (CODE_COPIE, sha256
# f064870f...) : le danger s'exprime en INJECTANT les cases menacees dans `walls`, ce qui
# transforme un BFS statique en fuite. C'est le deuxieme consommateur reel de la brique
# dans ce jeu, apres map_validator.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const GridNav = preload("res://05_SYSTEMS/grid_nav/grid_nav.gd")
const Explosion = preload("res://05_SYSTEMS/explosion/explosion.gd")
const SuddenDeath = preload("res://05_SYSTEMS/sudden_death/sudden_death.gd")

# Rayon de recherche d'une case sure. Au-dela, le bot renonce et tient sa position.
const PORTEE_FUITE: int = 8

# Combien de ticks a l'avance le bot voit tomber les blocs de mort subite. Doit couvrir
# plusieurs pas de deplacement, sinon il decouvre le bloc quand il est deja dessous.
# Exprime en PAS, pas en ticks bruts : recalibrer la vitesse ne doit pas rendre le bot
# aveugle par effet de bord (defaut evite lors du recalibrage humain du 2026-08-10).
# Espace vital sous lequel un ennemi est considere comme sous PRESSION suffisante pour
# justifier une pose. 0 = certitude (jamais atteinte) ; une petite valeur = jeu reel.
const SEUIL_ESPACE_VITAL: int = 3

const PAS_D_ANTICIPATION: int = 15
const HORIZON_MORT_SUBITE: int = PAS_D_ANTICIPATION * P.MOVE_COOLDOWN_BASE


# Cases MENACEES : celles que les bombes en cours couvriront, plus celles qui brulent deja.
# Approximation assumee et NOMMEE : la chaine n'est pas anticipee. Un bot qui simulerait la
# chaine complete serait plus fort, mais ce module doit rester une politique lisible — et
# l'oracle mesure le RESULTAT, pas l'elegance de la politique.
static func cases_menacees(state) -> Dictionary:
	var d: Dictionary = {}
	for c in state.flammes.keys():
		d[c] = true

	# MORT SUBITE : les cases qui vont tomber sous peu sont un danger AU MEME TITRE qu'une
	# flamme. Mesure du 2026-08-10 : sans cette ligne, la mort subite terminait bien les
	# parties (1305-1481 ticks au lieu de 5000) mais le bot les perdait TOUTES — il se
	# tenait tranquillement sous le bloc suivant. Un danger que la politique ne voit pas
	# n'est pas un danger difficile, c'est un danger invisible.
	var horizon: int = int(state.ticks) + HORIZON_MORT_SUBITE
	var dus: int = SuddenDeath.blocs_dus(horizon)
	if dus > int(state.blocs_tombes):
		var spirale: Array = SuddenDeath.ordre_spirale(state.arene.largeur, state.arene.hauteur)
		for i in range(int(state.blocs_tombes), min(dus, spirale.size())):
			d[spirale[i]] = true
	for b in state.bombes:
		var centre: Vector2i = b["cellule"]
		d[centre] = true
		for dir in Explosion.BRAS:
			for r in range(1, int(b["rayon"]) + 1):
				var c: Vector2i = centre + dir * r
				if state.arene.est_solide(c):
					break
				d[c] = true
				if state.arene.est_destructible(c):
					break
	return d


# Murs pour la navigation : terrain solide + destructibles + bombes + AUTRES ACTEURS.
# Les destructibles sont des murs POUR L'INSTANT — le bot ne traverse pas ce qu'il n'a pas
# encore detruit.
#
# DEFAUT REEL CORRIGE (mesure du 2026-08-10, 3 graines) : cette table ignorait les autres
# acteurs alors que `movement.traversable` les bloque. Le bot planifiait donc des fuites A
# TRAVERS LES CORPS, son pas etait refuse au dernier moment, et il mourait dans sa propre
# explosion — diagnostic : `morts:1, kills_du_bot:0, vivants:3` sur les 3 graines. Une carte
# de navigation qui ment sur les obstacles ne produit pas un bot maladroit, elle produit un
# bot qui se suicide.
static func murs(state, index: int) -> Dictionary:
	var m: Dictionary = {}
	for y in range(state.arene.hauteur):
		for x in range(state.arene.largeur):
			var c := Vector2i(x, y)
			if not state.arene.est_libre(c):
				m[c] = true
	for b in state.bombes:
		if not (b["cellule"] == state.acteurs[index]["cellule"]):
			m[b["cellule"]] = true
	for j in range(state.acteurs.size()):
		if j == index or not state.acteurs[j]["vivant"]:
			continue
		m[state.acteurs[j]["cellule"]] = true
	return m


static func _intention_vers(depuis: Vector2i, vers: Vector2i) -> int:
	var d: Vector2i = vers - depuis
	if d == Vector2i(0, -1):
		return P.HAUT
	if d == Vector2i(1, 0):
		return P.DROITE
	if d == Vector2i(0, 1):
		return P.BAS
	if d == Vector2i(-1, 0):
		return P.GAUCHE
	return P.AUCUNE


# Nombre de cases SURES atteignables pour un acteur, sous une carte de menace donnee.
# Mesure l'ESPACE VITAL restant. C'est la grandeur qui manquait : le declencheur de pose
# etait « l'ennemi n'a plus AUCUNE issue », condition qui ne survient quasi jamais sur une
# arene ouverte (mesure : 0 elimination sur 6 graines x 5000 ticks). Un joueur humain ne
# vise pas la certitude, il vise la REDUCTION de l'espace vital.
static func nb_cases_sures(state, index: int, menace: Dictionary) -> int:
	var depart: Vector2i = state.acteurs[index]["cellule"]
	var m: Dictionary = murs(state, index)
	var n: int = 0
	for y in range(state.arene.hauteur):
		for x in range(state.arene.largeur):
			var c := Vector2i(x, y)
			if menace.has(c) or m.has(c):
				continue
			var d: int = GridNav.path_length(depart, c, m)
			if d >= 0 and d <= PORTEE_FUITE:
				n += 1
	return n


# Case sure la plus proche, en BFS sur les murs AUGMENTES du danger. Rend la cellule
# courante si aucune n'est trouvee — renoncer explicitement vaut mieux que fuir au hasard.
static func case_sure(state, index: int, menace: Dictionary) -> Vector2i:
	var depart: Vector2i = state.acteurs[index]["cellule"]
	var m: Dictionary = murs(state, index)
	var meilleure: Vector2i = depart
	var meilleure_dist: int = 99999
	for y in range(state.arene.hauteur):
		for x in range(state.arene.largeur):
			var c := Vector2i(x, y)
			if menace.has(c) or m.has(c):
				continue
			var d: int = GridNav.path_length(depart, c, m)
			if d < 0 or d > PORTEE_FUITE:
				continue
			if d < meilleure_dist:
				meilleure_dist = d
				meilleure = c
	return meilleure


# Case atteignable qui sera ecrasee le PLUS TARD par la mort subite, hors flamme allumee.
# Repli de fin de partie : quand plus aucune case n'est sure, le meilleur coup est celui qui
# achete le plus de temps. Rend la cellule courante si rien de mieux n'est atteignable.
static func case_la_plus_tardive(state, index: int) -> Vector2i:
	var depart: Vector2i = state.acteurs[index]["cellule"]
	var m: Dictionary = murs(state, index)
	var spirale: Array = SuddenDeath.ordre_spirale(state.arene.largeur, state.arene.hauteur)
	var rang: Dictionary = {}
	for i in range(spirale.size()):
		rang[spirale[i]] = i
	var meilleure: Vector2i = depart
	var meilleur_rang: int = int(rang.get(depart, -1))
	for y in range(state.arene.hauteur):
		for x in range(state.arene.largeur):
			var c := Vector2i(x, y)
			if m.has(c) or state.flammes.has(c):
				continue
			var r: int = int(rang.get(c, -1))
			if r <= meilleur_rang:
				continue
			if GridNav.path_length(depart, c, m) < 0:
				continue
			meilleur_rang = r
			meilleure = c
	return meilleure


# Cibles dans la croix depuis `c` au `rayon`.
# Rend {"bloc": bool, "ennemis": Array[int]} — les deux ne se confondent pas : casser un
# bloc fait progresser, pieger un ennemi fait gagner.
static func cibles_en_croix(state, index: int, c: Vector2i, rayon: int) -> Dictionary:
	var bloc := false
	var ennemis: Array = []
	for dir in Explosion.BRAS:
		for r in range(1, rayon + 1):
			var q: Vector2i = c + dir * r
			if state.arene.est_solide(q):
				break
			if state.arene.est_destructible(q):
				bloc = true
				break
			for j in range(state.acteurs.size()):
				if j != index and state.acteurs[j]["vivant"] and state.acteurs[j]["cellule"] == q:
					ennemis.append(j)
	return {"bloc": bloc, "ennemis": ennemis}


# Cases que couvrirait une bombe posee en `c` au `rayon`, sur le terrain COURANT.
static func souffle_hypothetique(state, c: Vector2i, rayon: int) -> Dictionary:
	var d: Dictionary = {c: true}
	for dir in Explosion.BRAS:
		for r in range(1, rayon + 1):
			var q: Vector2i = c + dir * r
			if state.arene.est_solide(q):
				break
			d[q] = true
			if state.arene.est_destructible(q):
				break
	return d


# Cible la plus proche a rejoindre : un ennemi vivant d'abord, un destructible sinon.
static func _cap(state, index: int, m: Dictionary) -> Vector2i:
	var depart: Vector2i = state.acteurs[index]["cellule"]
	var meilleure: Vector2i = depart
	var meilleure_dist: int = 99999
	for j in range(state.acteurs.size()):
		if j == index or not state.acteurs[j]["vivant"]:
			continue
		# REGLE STRUCTURELLE : UNE CIBLE DE ROUTAGE DOIT ETRE OCCUPABLE.
		#
		# La version precedente rendait la CASE DE L'ENNEMI. On ne peut jamais y poser le
		# pied — `movement.traversable` refuse toute case occupee par un acteur vivant. Le
		# bot demandait donc un pas refuse a chaque tick. Mesure du 2026-08-11, graine 1 :
		# acteur 1 en (8,1) demande GAUCHE vers (7,1) ; acteur 2 en (7,1) demande DROITE
		# vers (8,1) ; (7,1) est du SOL LIBRE, sans bombe — le refus vient UNIQUEMENT de
		# l'occupant. Blocage mutuel de 1979 ticks, soit 33 secondes.
		#
		# C'est la TROISIEME manifestation de la meme confusion (routable / occupable / sur).
		# On la traite ici a la racine plutot qu'une fois de plus au cas par cas : la branche
		# DESTRUCTIBLE ci-dessous visait deja un VOISIN LIBRE ; la branche ENNEMI etait la
		# seule incoherente. Les deux visent desormais une case ou l'on peut se tenir.
		for dir in Explosion.BRAS:
			var voisin: Vector2i = state.acteurs[j]["cellule"] + dir
			if not state.arene.est_libre(voisin):
				continue
			# QUATRIEME manifestation de la meme confusion, mesuree le 2026-08-12 :
			# quand deux bots sont DEJA voisins, la case du bot EST un voisin libre de
			# l'ennemi. `path_length` y rend 0, distance imbattable, donc `meilleure`
			# devenait `depart` — et la ligne « if cap == depart: return AUCUNE » plus bas
			# figeait les deux. Mesure : J2 (13,4) et J4 (13,5), colonne x=13 large d'une
			# case, cap == cellule pour les DEUX, intention AUCUNE des deux cotes,
			# blocage mutuel de ~1 100 ticks (18 s) sur 4 graines de 5.
			#
			# « Je suis deja arrive » n'est pas une cible de routage : c'est l'absence de
			# cible. La distinguer rend la main aux branches suivantes (destructible), qui
			# produisent un desengagement REEL au lieu d'une immobilite.
			# EFFET DE BORD MESURE, ET NON MASQUE (2026-08-12, 18 runs, 3 cartes x 6 graines) :
			#   sans cette ligne  13/18 victoires, 3 suicides du bot teste
			#   avec cette ligne  12/18 victoires, 6 suicides
			# Le bot cesse de se figer, donc il BOUGE — et bouger pendant la mort subite le
			# tue plus souvent avec sa propre bombe. Le defaut se deplace vers un axe voisin
			# au lieu de disparaitre. Arbitrage HumanGate : le blocage de 26 s etait visible
			# au playtest, le suicide du bot ne l'est pas. Retirer cette ligne suffit a
			# revenir a la baseline.
			var d: int = GridNav.path_length(depart, voisin, m)
			if d >= 0 and d < meilleure_dist:
				meilleure_dist = d
				meilleure = voisin
	if meilleure_dist < 99999:
		return meilleure
	for y in range(state.arene.hauteur):
		for x in range(state.arene.largeur):
			var c := Vector2i(x, y)
			if not state.arene.est_destructible(c):
				continue
			for dir in Explosion.BRAS:
				var voisin: Vector2i = c + dir
				if not state.arene.est_libre(voisin):
					continue
				var d2: int = GridNav.path_length(depart, voisin, m)
				if d2 >= 0 and d2 < meilleure_dist:
					meilleure_dist = d2
					meilleure = voisin
	return meilleure


# DECISION. `agressif` faux = adversaire : il fuit le danger et se deplace, mais ne pose
# JAMAIS de bombe. C'est ce qui rend le critere « elimination active » discriminant : si le
# bot teste gagne, ce ne peut pas etre parce que les autres se sont entretues.
static func decider(state, index: int, agressif: bool) -> int:
	var a: Dictionary = state.acteurs[index]
	if not a["vivant"]:
		return P.AUCUNE
	var depart: Vector2i = a["cellule"]
	var menace: Dictionary = cases_menacees(state)

	# (1) En danger : fuir, toujours. Rien d'autre ne compte.
	if menace.has(depart):
		var refuge: Vector2i = case_sure(state, index, menace)
		if refuge == depart:
			# Aucune case SURE a portee. En fin de partie l'arene se referme et ce cas
			# devient la norme : rester immobile revient a se faire ecraser. On joue alors
			# la case qui tombera le PLUS TARD — survivre plus longtemps est une decision,
			# l'immobilite n'en est pas une. Mesure du 2026-08-10 : sans ce repli, le bot
			# perdait 4 graines sur 6 en tenant sa position sous le bloc suivant.
			refuge = case_la_plus_tardive(state, index)
			if refuge == depart:
				return P.AUCUNE
		var m: Dictionary = murs(state, index)
		for c in menace.keys():
			m[c] = true
		# EXPERIENCE A — filtre de securite sur la sortie de la branche FUITE.
		# Mesure du 2026-08-11, graine 3 : le bot en (1,7), menace par sa propre bombe,
		# emettait BAS vers (1,8) qui BRULAIT depuis le tick precedent. Les flammes n'etaient
		# pas des murs ici (elles le sont dans la branche POURSUITE), et aucun test de
		# letalite ne gardait cette sortie. 15 suicides sur 20 graines passent par ce chemin.
		for c in state.flammes.keys():
			m[c] = true
		var pas: Vector2i = GridNav.next_step(depart, refuge, m)
		if pas == depart:
			pas = GridNav.next_step(depart, refuge, murs(state, index))
		if state.case_letale(pas):
			return P.AUCUNE
		return _intention_vers(depart, pas)

	# (2) Poser. Deux motifs DISTINCTS, et c'est la distinction qui fait gagner :
	#     - PIEGER un ennemi : on ne pose que si, apres la pose, l'ennemi n'a PLUS AUCUNE
	#       case sure atteignable. Poser des que quelqu'un est « en vue » ne tue jamais
	#       personne — mesure du 2026-08-10 : 0 elimination sur 5000 ticks, parce qu'un
	#       adversaire qui fuit s'echappe toujours d'une bombe posee au hasard.
	#     - OUVRIR le terrain : casser un bloc pour progresser.
	# Dans les deux cas, ne jamais poser sans issue POUR SOI.
	if agressif and int(a["bombes_actives"]) < int(a["bombes_max"]):
		var cibles: Dictionary = cibles_en_croix(state, index, depart, int(a["rayon"]))
		var souffle: Dictionary = souffle_hypothetique(state, depart, int(a["rayon"]))
		var apres: Dictionary = menace.duplicate()
		for c in souffle.keys():
			apres[c] = true
		var issue_pour_soi: bool = case_sure(state, index, apres) != depart
		if issue_pour_soi:
			# ASYMETRIE, et non agressivite. Deux mesures precedentes :
			#   exiger ZERO issue chez l'ennemi  -> 2/8 (il n'attaque presque jamais)
			#   exiger seulement « peu d'issues » -> 1/8 (il attaque et meurt avec)
			# Ce qu'un joueur exploite n'est ni l'un ni l'autre : c'est un ECART. On ne pose
			# que si l'ennemi est sous pression ET que MON espace vital reste strictement
			# plus grand que le sien apres la pose.
			var mon_espace: int = nb_cases_sures(state, index, apres)
			var piege := false
			for j in cibles["ennemis"]:
				var son_espace: int = nb_cases_sures(state, int(j), apres)
				if son_espace <= SEUIL_ESPACE_VITAL and mon_espace > son_espace:
					piege = true
					break
			if piege or cibles["bloc"]:
				return P.POSER

	# (3) Avancer vers la cible. La case de la cible est retiree des murs pour le meme
	# motif qu'en (2) de `_cap` : on ne peut pas rejoindre ce qu'on declare infranchissable.
	# Le pas reste refuse par `movement` si la case est encore occupee au moment de bouger —
	# c'est la boucle qui tranche, pas la politique.
	var m2: Dictionary = murs(state, index)
	var cap: Vector2i = _cap(state, index, m2)
	if cap == depart:
		return P.AUCUNE
	var m3: Dictionary = m2.duplicate()
	m3.erase(cap)
	# DEFAUT REEL CORRIGE (mesure du 2026-08-10) : cette navigation ignorait `menace`. Le
	# bot n'etait donc prudent QUE lorsqu'il etait deja en danger — en avancant, il entrait
	# tranquillement dans une flamme encore allumee. Diagnostic : mort a t=318,
	# `tueur: -1` (flamme residuelle). Eviter le danger en fuyant et l'ignorer en marchant
	# n'est pas une politique, c'est une contradiction.
	# DEUX NOTIONS DISTINCTES, et c'est tout le correctif.
	#
	# FRANCHISSABILITE — « puis-je router ici ? » : murs + menace, AVEC exemption de la
	# cible. L'exemption est conservee : viser un ennemi exige de pouvoir calculer une route
	# jusqu'a sa case, qui est un obstacle par ailleurs.
	#
	# LETALITE — « puis-je survivre ici ? » : les cases qui BRULENT, SANS aucune exemption.
	# Elle est reappliquee APRES l'exemption, donc rien ne peut la lever.
	#
	# DEFAUT MESURE QUE CECI CORRIGE (graine 1, acteur 1, ticks 678-688) : `erase(cap)`
	# operait sur un graphe deja augmente du danger et retirait, du meme geste, l'obstacle
	# ET la menace. Mesure : cap = (11,3), menacee ET letale ; le graphe la contenait AVANT
	# l'erase et plus APRES ; `next_step` rendait (11,3) au lieu de « pas de chemin » ; le
	# bot y entrait des que le cooldown le permettait, et mourait a t=688.
	var m4: Dictionary = m3.duplicate()
	for c in menace.keys():
		m4[c] = true
	m4.erase(cap)
	for c in state.flammes.keys():
		m4[c] = true
	var pas2: Vector2i = GridNav.next_step(depart, cap, m4)
	# Garde de survie, independante du routage : meme si un chemin existe, on ne pose jamais
	# le pied sur une case qui brule. Le contrefactuel a montre qu'un graphe sans exemption
	# rend « pas de chemin » et immobilise le bot — l'exemption reste donc, la letalite aussi.
	if state.case_letale(pas2):
		return P.AUCUNE
	if pas2 == depart:
		# Aucun chemin sur : attendre vaut mieux que traverser le feu.
		return P.AUCUNE
	return _intention_vers(depart, pas2)
