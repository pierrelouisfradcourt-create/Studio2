# app_state.gd — LA BOUCLE D'APPLICATION : menu -> partie -> resultat -> rejouer.
#
# Distincte de `game_state`, et la distinction est le point : `game_state` detient UNE
# partie, `app_state` detient ce qui SURVIT a une partie (l'ecran courant, la carte
# choisie, la derniere issue). Les melanger rendrait le rejeu impossible a prouver propre,
# parce qu'on ne saurait plus ce qui doit etre remis a zero et ce qui doit persister.
#
# Logique PURE : aucune scene, aucun noeud, aucune horloge. Les transitions sont des
# FONCTIONS de (etat, action), jamais des effets de bord.
extends RefCounted

# REGLE DE NAVIGATION, ratifiee Pierre 2026-08-12 (P8) :
#
#     ECHAP remonte d'EXACTEMENT un niveau  --  SAUF depuis EN_JEU.
#     EN_JEU doit passer par PAUSE :   EN_JEU --P--> PAUSE --ECHAP--> SELECTION_CARTE
#
# L'exception est VOULUE, pas un oubli : deux chemins concurrents pour quitter une partie
# seraient une source de sortie accidentelle, et `P` reste le point d'entree explicite de la
# pause. L'assertion historique « RETOUR_MENU est sans effet pendant la partie » est donc
# CONSERVEE telle quelle plutot que reecrite pour satisfaire la regle generale.
# La table de remontee est ainsi 6 remontees + 1 exception documentee, jamais 7 remontees.
#
# ABANDON, et non suspension : remonter depuis PAUSE termine la partie courante. C'est ce que
# `doit_arreter` generalise applique — l'arene ne survit pas derriere l'ecran de selection.


const P = preload("res://05_SYSTEMS/params/params.gd")

# Ecrans — enumeration GELEE.
const MENU: int = 0
const EN_JEU: int = 1
const RESULTAT: int = 2
# PAUSE est un ECRAN, pas un statut de partie. Snake place sa pause dans le statut de
# jeu (`pause.gd`, EN_COURS <-> EN_PAUSE) ; ici l'enumeration de statut est GELEE a
# quatre valeurs par les regles de victoire, et y ajouter EN_PAUSE obligerait chaque
# systeme de regles a connaitre un etat qui n'est pas de son ressort. La pause suspend
# l'APPLICATION, elle ne change pas la partie.
const PAUSE: int = 3
# OPTIONS SONORES. Un ECRAN de plus dans la MEME machine a etats, jamais un second systeme
# de menu : il se declare ici, se rend par le meme `ui_shell`, et se quitte par la meme
# action RETOUR_MENU que le resultat et la pause.
const OPTIONS: int = 4
# P8 — NAVIGATION PAR ECRANS (arbre ratifie Pierre, 2026-08-12).
#
#   MENU (racine)
#     JOUER     -> SELECTION_CARTE -> (VALIDER) -> EN_JEU -> PAUSE
#     CONTROLES
#     OPTIONS
#     QUITTER
#
# Les deux ecrans ci-dessous s'AJOUTENT en fin d'enumeration : les valeurs 0..4 restent
# gelees, aucun etat deja ecrit ailleurs ne change de sens.
#
# SELECTION_CARTE existe parce que le MENU faisait DEUX choses a la fois (choisir une carte
# ET lancer). Un menu racine choisit une DESTINATION ; le choix de carte est un niveau en
# dessous, et c'est ce qui donne a ECHAP un sens uniforme : remonter d'un cran.
const SELECTION_CARTE: int = 5
const CONTROLES: int = 6

# Entrees du MENU racine. Vocabulaire FERME, dans l'ordre d'affichage : `curseur_menu` est
# un INDEX dans cette liste, jamais un ecran deguise.
const MENU_JOUER: int = 0
const MENU_CONTROLES: int = 1
const MENU_OPTIONS: int = 2
const MENU_QUITTER: int = 3
const MENU_NB: int = 4

# Actions — vocabulaire FERME. Une action inconnue ne fait RIEN (elle ne casse pas l'appli).
# P8 N'EN AJOUTE AUCUNE : la navigation reutilise les trois actions existantes
# (CARTE_SUIVANTE = deplacer le choix, VALIDER = descendre d'un cran, RETOUR_MENU = remonter
# d'un cran). Une action « CURSEUR_BAS » de plus aurait double le vocabulaire pour exprimer
# exactement le meme geste sur un ecran de plus.
const RIEN: int = 0
const VALIDER: int = 1          # menu : ouvrir l'entree choisie ; selection : lancer ; resultat : rejouer
const CARTE_SUIVANTE: int = 2   # menu : entree suivante ; selection de carte : carte suivante
const RETOUR_MENU: int = 3      # ECHAP : remonte d'EXACTEMENT un niveau
const BASCULER_PAUSE: int = 4   # en jeu et pause
const OUVRIR_OPTIONS: int = 5   # menu seulement (raccourci secondaire, conserve)
const CYCLE_VOL_MUSIQUE: int = 6
const CYCLE_VOL_EFFETS: int = 7

# Reglage par PALIERS plutot que continu : quatre paliers se lisent et se prouvent, un
# curseur continu demanderait un widget que ce shell n'a pas. Le cycle repasse par 0, donc
# « couper le son » est atteignable sans touche dediee.
const VOLUME_PAS: int = 25
const VOLUME_MAX: int = 100

const ISSUE_AUCUNE: int = -1


static func initial(nb_cartes: int) -> Dictionary:
	return {
		"ecran": MENU,
		"carte": 0,
		"nb_cartes": max(1, nb_cartes),
		"issue": ISSUE_AUCUNE,
		"parties_jouees": 0,
		# Position du choix dans le MENU racine. Un INDEX, pas un ecran : le menu doit pouvoir
		# survoler « QUITTER » sans quitter.
		"curseur_menu": MENU_JOUER,
		# DRAPEAU de sortie. `app_state` est pur : il ne connait ni OS, ni SceneTree, ni
		# `quit()`. Il DECLARE l'intention, le runtime seul l'execute — sinon la machine a
		# etats deviendrait impossible a tester sans tuer le harnais de test.
		"quitter": false,
		# Volumes en POURCENTAGE, portee SESSION. Aucune persistance : le depot n'en a pour
		# l'instant que sur le meilleur score (`score_store`), et en inventer une ici
		# ajouterait un fichier de configuration que rien ne demande.
		"vol_musique": VOLUME_MAX,
		"vol_effets": VOLUME_MAX,
	}


# Palier suivant, cyclique : 100 -> 0 -> 25 -> 50 -> 75 -> 100. PURE.
static func volume_suivant(v: int) -> int:
	return (int(v) + VOLUME_PAS) % (VOLUME_MAX + VOLUME_PAS)


# Transition. `statut_partie` est le statut de la partie en cours (params.EN_COURS...),
# ignore hors de l'ecran EN_JEU. Rend TOUJOURS un nouvel etat, jamais null.
static func appliquer(app: Dictionary, action: int, statut_partie: int) -> Dictionary:
	var a: Dictionary = app.duplicate()
	match int(a["ecran"]):
		MENU:
			# La MEME action deplace le choix : au menu elle bouge le curseur, a l'ecran
			# suivant elle bouge la carte. Un seul geste clavier, deux sens selon l'ecran.
			if action == CARTE_SUIVANTE:
				a["curseur_menu"] = (int(a["curseur_menu"]) + 1) % MENU_NB
			elif action == OUVRIR_OPTIONS:
				a["ecran"] = OPTIONS
			elif action == VALIDER:
				match int(a["curseur_menu"]):
					MENU_JOUER:
						a["ecran"] = SELECTION_CARTE
					MENU_CONTROLES:
						a["ecran"] = CONTROLES
					MENU_OPTIONS:
						a["ecran"] = OPTIONS
					MENU_QUITTER:
						# On POSE le drapeau, on ne quitte pas : voir `doit_quitter`.
						a["quitter"] = true
			# ECHAP au MENU ne fait rien : c'est la RACINE, il n'y a pas de niveau au-dessus.
		SELECTION_CARTE:
			# Corps HERITE de l'ancien cas MENU, deplace tel quel : choisir une carte puis la
			# lancer est exactement le comportement d'avant, il vit simplement un cran plus bas.
			if action == CARTE_SUIVANTE:
				a["carte"] = (int(a["carte"]) + 1) % int(a["nb_cartes"])
			elif action == VALIDER:
				a["ecran"] = EN_JEU
				a["issue"] = ISSUE_AUCUNE
			elif action == RETOUR_MENU:
				a["ecran"] = MENU
		CONTROLES:
			# Ecran de LECTURE : il n'a rien a regler, donc rien a valider. Seul le retour agit.
			if action == RETOUR_MENU:
				a["ecran"] = MENU
		OPTIONS:
			# Les reglages n'existent QUE sur cet ecran : une touche de volume pressee en
			# pleine partie ne doit pas changer le son sous les doigts du joueur.
			if action == RETOUR_MENU or action == VALIDER:
				a["ecran"] = MENU
			elif action == CYCLE_VOL_MUSIQUE:
				a["vol_musique"] = volume_suivant(int(a["vol_musique"]))
			elif action == CYCLE_VOL_EFFETS:
				a["vol_effets"] = volume_suivant(int(a["vol_effets"]))
		EN_JEU:
			# La sortie de partie est decidee par les REGLES, pas par une touche : c'est le
			# statut qui fait passer a l'ecran de resultat. La fin PRIME sur la pause : on
			# ne met pas en pause une partie deja terminee.
			if statut_partie != P.EN_COURS:
				a["ecran"] = RESULTAT
				a["issue"] = statut_partie
				a["parties_jouees"] = int(a["parties_jouees"]) + 1
			elif action == BASCULER_PAUSE:
				a["ecran"] = PAUSE
		PAUSE:
			# Reprendre par la MEME touche qui met en pause, ou par VALIDER. Quitter reste
			# possible : c'est le seul ecran d'ou l'on peut abandonner une partie.
			#
			# ECHAP remonte d'UN niveau, donc vers SELECTION_CARTE et non vers la racine. Ce
			# n'est PAS une partie suspendue : `doit_arreter` reste vrai, la partie est
			# ABANDONNEE — on remonte a l'ecran d'ou elle a ete lancee, prete a en relancer une.
			if action == BASCULER_PAUSE or action == VALIDER:
				a["ecran"] = EN_JEU
			elif action == RETOUR_MENU:
				a["ecran"] = SELECTION_CARTE
				a["issue"] = ISSUE_AUCUNE
		RESULTAT:
			if action == VALIDER:
				a["ecran"] = EN_JEU
				a["issue"] = ISSUE_AUCUNE
			elif action == RETOUR_MENU:
				a["ecran"] = SELECTION_CARTE
				a["issue"] = ISSUE_AUCUNE
	return a


# Faut-il (re)construire une partie neuve ? Vrai exactement au moment ou l'on ENTRE dans
# l'ecran de jeu. C'est ce predicat qui garantit qu'un rejeu repart d'un etat neuf et non
# d'un etat rince a la main — la difference entre « remettre a zero » et « reconstruire ».
static func doit_demarrer(avant: Dictionary, apres: Dictionary) -> bool:
	# REPRENDRE N'EST PAS DEMARRER. Sans l'exclusion de PAUSE, sortir de pause
	# reconstruirait une partie neuve — la pause detruirait la partie qu'elle protege.
	if int(avant["ecran"]) == PAUSE:
		return false
	return int(avant["ecran"]) != EN_JEU and int(apres["ecran"]) == EN_JEU


# Faut-il DETRUIRE la partie en cours ? Vrai exactement au moment ou l'on QUITTE le jeu
# pour le menu. Symetrique de `doit_demarrer`, et pour la meme raison : sans ce predicat,
# l'appelant devrait deviner quand nettoyer, et la partie abandonnee survivait au retour
# menu — l'arene precedente restait dans la scene et l'etat de partie restait en memoire.
#
# RESULTAT -> MENU en fait partie : une partie terminee n'a pas a etre gardee vivante non
# plus. Ce qui doit survivre a une partie vit dans `app_state`, jamais dans `game_state`.
# ECRANS DE PARTIE, enumeres plutot que « tout sauf MENU » : OPTIONS ne porte aucune partie,
# et le raccourci « != MENU » le comptait comme tel — un aller-retour dans les options aurait
# detruit la partie en cours si les options devenaient un jour accessibles depuis la pause.
#
# P8 — LE PIEGE ANNONCE PAR LE COMMENTAIRE CI-DESSUS S'EST REALISE DANS L'AUTRE SENS. La
# cible etait comparee LITTERALEMENT a MENU ; des que la pause remonte vers SELECTION_CARTE
# et non vers la racine, cette comparaison rend faux et la partie abandonnee SURVIT — l'arene
# reste dans la scene derriere l'ecran de selection, exactement le defaut que ce predicat
# avait ete ecrit pour fermer. La condition est donc desormais SYMETRIQUE et generale :
# on quitte le jeu des que l'ecran d'arrivee n'est plus un ecran de partie, quel qu'il soit.
static func est_ecran_partie(ecran: int) -> bool:
	return ecran == EN_JEU or ecran == PAUSE or ecran == RESULTAT


static func doit_arreter(avant: Dictionary, apres: Dictionary) -> bool:
	return est_ecran_partie(int(avant["ecran"])) and not est_ecran_partie(int(apres["ecran"]))


# Faut-il QUITTER l'application ? Vrai exactement au moment ou le drapeau se leve — meme
# patron que `doit_demarrer` : un FRONT, jamais un etat. Sans le front, le runtime appellerait
# `quit()` a chaque frame tant que le drapeau reste haut.
#
# `app_state` ne touche JAMAIS l'OS. Il porte le drapeau ; `runtime_loop` seul appelle
# `get_tree().quit()`. C'est ce qui permet de PROUVER la sortie par une assertion pure au lieu
# de la constater en tuant le processus de test.
static func doit_quitter(avant: Dictionary, apres: Dictionary) -> bool:
	return not bool(avant.get("quitter", false)) and bool(apres.get("quitter", false))


static func libelle_issue(issue: int) -> String:
	match issue:
		P.GAGNE:
			return "VICTOIRE"
		P.PERDU:
			return "DEFAITE"
		P.NUL:
			return "MATCH NUL"
		_:
			return ""
