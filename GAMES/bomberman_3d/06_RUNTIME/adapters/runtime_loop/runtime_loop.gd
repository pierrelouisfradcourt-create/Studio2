# runtime_loop.gd — POINT D'ENTREE PRODUIT (res://main.tscn). Le seul endroit qui possede
# une horloge, un clavier et des noeuds.
#
# N'implemente AUCUNE regle : il lit le clavier, appelle App.appliquer et Loop.step, et
# donne les etats a la presentation. Toute la logique reste dans 05_SYSTEMS, testable sans
# moteur.
extends Node3D

const P = preload("res://05_SYSTEMS/params/params.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Validator = preload("res://05_SYSTEMS/map_validator/map_validator.gd")
const Content = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_policy.gd")
const View = preload("res://06_RUNTIME/adapters/presentation_3d/arena_view_3d.gd")
const Shell = preload("res://06_RUNTIME/adapters/ui_shell/ui_shell.gd")
const Audio = preload("res://06_RUNTIME/adapters/audio/audio.gd")
const Store = preload("res://06_RUNTIME/adapters/score_store/score_store.gd")

# La base de temps est DERIVEE de params, jamais redeclaree ici. C'est ce couplage manquant
# qui avait rendu invisible un jeu tournant a 10 cases/seconde : les durees vivaient dans
# params, leur unite dans ce fichier, et personne ne pouvait les convertir en secondes.
const TICK_S := 1.0 / float(P.TICKS_PAR_SECONDE)
const NB_ACTEURS := 4

var _app: Dictionary = {}
var _partie = null
var _vue = null
var _shell = null
var _accu := 0.0
# CATALOGUE charge UNE fois : les descripteurs eux-memes, pas seulement leurs noms. L'ecran
# de selection a besoin du plan et du theme ; extraire les noms ici et jeter le reste aurait
# oblige l'interface a relire le disque ou, pire, a redeclarer les cartes.
var _cartes: Array = []
var _touche_relachee := true
var _audio = null
var _meilleur: int = 0
var _note: int = 0
var _prochaine_note: int = 0


func _ready() -> void:
	_app = App.initial(Content.nb_cartes())
	for i in range(Content.nb_cartes()):
		_cartes.append(Content.descripteur(i))
	_audio = Audio.new()
	add_child(_audio)
	_meilleur = Store.lire()
	_shell = Shell.new()
	add_child(_shell)
	_shell.rafraichir(_app, null, _cartes)


# Action d'INTERFACE, distincte de l'intention de jeu. Anti-repetition : une touche
# maintenue ne doit pas enchainer dix transitions d'ecran.
func _action_ui() -> int:
	var brute: int = App.RIEN
	if Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_KP_ENTER):
		brute = App.VALIDER
	elif Input.is_key_pressed(KEY_TAB):
		brute = App.CARTE_SUIVANTE
	# HAUT / BAS deplacent le choix — HORS PARTIE UNIQUEMENT. La garde n'est pas une precaution
	# de style : les memes fleches sont l'intention de deplacement du joueur, et sans elle
	# marcher vers le haut changerait la carte selectionnee sous la partie en cours.
	elif int(_app["ecran"]) != App.EN_JEU and (
			Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_DOWN)):
		brute = App.CARTE_SUIVANTE
	elif Input.is_key_pressed(KEY_P):
		brute = App.BASCULER_PAUSE
	elif Input.is_key_pressed(KEY_O):
		brute = App.OUVRIR_OPTIONS
	elif Input.is_key_pressed(KEY_M):
		brute = App.CYCLE_VOL_MUSIQUE
	elif Input.is_key_pressed(KEY_B):
		brute = App.CYCLE_VOL_EFFETS
	elif Input.is_key_pressed(KEY_ESCAPE):
		brute = App.RETOUR_MENU
	if brute == App.RIEN:
		_touche_relachee = true
		return App.RIEN
	if not _touche_relachee:
		return App.RIEN
	_touche_relachee = false
	return brute


# Intention de JEU, depuis le clavier. Le meme canal public que celui du bot.
func _intention_joueur() -> int:
	if Input.is_key_pressed(KEY_SPACE):
		return P.POSER
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_W):
		return P.HAUT
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		return P.DROITE
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		return P.BAS
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_A):
		return P.GAUCHE
	return P.AUCUNE


# Construit une partie NEUVE sur la carte selectionnee. Une carte refusee ne renvoie rien :
# le point de passage oblige reste map_validator, meme au demarrage produit.
func _demarrer() -> void:
	# LA CARTE JOUEE EST CELLE QUI A ETE CHOISIE : `_app["carte"]` sert d'index dans le MEME
	# catalogue que celui affiche par l'ecran de selection. Un second chemin d'acces au
	# contenu ici, et l'apercu montrerait une carte pendant qu'une autre se lancerait.
	var desc: Dictionary = Content.descripteur(int(_app["carte"]))
	var carte: Dictionary = Validator.carte_validee(desc)
	if not carte["valide"]:
		push_error("Carte refusee : " + str(carte["motifs"]))
		_app["ecran"] = App.SELECTION_CARTE
		return
	_partie = State.initial(carte, desc, int(_app["carte"]) + 1, NB_ACTEURS)
	if _vue != null:
		remove_child(_vue)
		_vue.queue_free()
	_vue = View.new()
	add_child(_vue)
	# Le THEME est une DONNEE de la carte, pas un choix du moteur de rendu : c'est ce qui
	# donne a chaque carte une identite sans ajouter une ligne de code par carte.
	_vue.batir(_partie, String(desc.get("theme", "")))


# FERME la boucle : retour au menu depuis la pause ou le resultat. Sans cette fonction, la
# partie abandonnee survivait — l'arene precedente restait affichee derriere le menu et
# `_partie` gardait un etat mort qui repartait ensuite dans le HUD.
#
# On detruit la VUE et la PARTIE, jamais `_app` : ce qui doit survivre a une partie (carte
# choisie, meilleur score, parties jouees) vit dans l'etat d'application, et lui seul.
func _arreter() -> void:
	if _vue != null:
		remove_child(_vue)
		_vue.queue_free()
		_vue = null
	_partie = null
	_accu = 0.0
	# La piste musicale repart du debut a la partie suivante, sinon elle reprendrait au
	# milieu d'une phrase d'une partie qui n'existe plus.
	_note = 0
	_prochaine_note = 0


func _process(delta: float) -> void:
	var statut: int = _partie.statut if _partie != null else P.EN_COURS
	var avant: Dictionary = _app
	_app = App.appliquer(_app, _action_ui(), statut)
	# SORTIE DU JEU. Consommee UNE fois, sur le FRONT du drapeau : `app_state` a decide, le
	# runtime execute. C'est le seul point du programme qui touche le SceneTree pour cela, et
	# il est ici parce qu'il n'y a qu'ici une horloge et un arbre de scene.
	if App.doit_quitter(avant, _app):
		get_tree().quit()
		return
	if App.doit_demarrer(avant, _app):
		_demarrer()
	elif App.doit_arreter(avant, _app):
		_arreter()

	# LE REGLAGE ATTEINT LE RUNTIME. Sans cette poussee, les volumes ne seraient qu'un
	# chiffre dans un dictionnaire — un reglage que personne ne consomme.
	_audio.volume_musique = float(_app["vol_musique"]) / 100.0
	_audio.volume_effets = float(_app["vol_effets"]) / 100.0

	if int(_app["ecran"]) == App.EN_JEU and _partie != null:
		# Pas de temps FIXE : le delta du moteur n'entre jamais dans les regles.
		_accu += delta
		while _accu >= TICK_S:
			_accu -= TICK_S
			if _partie.statut != P.EN_COURS:
				break
			var intentions: Array = [_intention_joueur()]
			for i in range(1, _partie.acteurs.size()):
				intentions.append(Bot.decider(_partie, i, true))
			var r: Dictionary = Loop.step(_partie, intentions)
			_partie = r["state"]
			# CONSOMMATION des evenements : jusqu'ici la boucle les emettait et personne ne
			# les lisait. Le joueur ne voyait donc jamais ce qu'il venait de ramasser.
			for e in r["events"]:
				if String(e["kind"]) == "powerup_ramasse" and int(e["acteur"]) == P.INDEX_JOUEUR:
					_shell.signaler_ramassage(String(e["identifiant"]), bool(e["effet"]))
			# Le son consomme les MEMES evenements que l'interface : une seule source de
			# verite sur ce qui s'est passe ce tick.
			_audio.consommer(r["events"], int(_partie.ticks))
			# PISTE MUSICALE : une note toutes les MUSIQUE_NOTE_MS, cadencee par le tick de
			# jeu. Elle s'arrete donc d'elle-meme en pause et au menu, sans code de plus.
			if int(_partie.ticks) >= _prochaine_note:
				_audio.jouer_musique(_note, int(_partie.ticks))
				_note += 1
				_prochaine_note = int(_partie.ticks) + (Audio.MUSIQUE_NOTE_MS * P.TICKS_PAR_SECONDE) / 1000
			if _partie.statut != P.EN_COURS and int(_partie.score) > _meilleur:
				_meilleur = int(_partie.score)
				Store.ecrire(_meilleur)
		if _vue != null:
			_vue.rafraichir(_partie)
	else:
		_accu = 0.0

	# Le HUD ne parle que sur un ecran DE PARTIE. La condition suit `est_ecran_partie` — la
	# meme notion que celle qui commande l'arret — au lieu de la comparaison « != MENU » qui
	# aurait laisse le HUD d'une partie morte s'afficher sur l'ecran de selection.
	var partie_affichee = _partie if App.est_ecran_partie(int(_app["ecran"])) else null
	_shell.rafraichir(_app, partie_affichee, _cartes, _meilleur)
