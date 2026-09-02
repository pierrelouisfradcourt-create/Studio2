# v6_p2_lives_single_source.gd — POINT P2 DU LOT DE VALIDATION.
#
# La regle a change de NATURE : « les vies sont une valeur » (V5) devient « les vies sont
# une fonction du mode » (V6). Une regle qui devient une fonction est exactement le moment
# ou une valeur en dur cesse d'etre juste sans que rien ne le signale.
#
# CE QUE CETTE PREUVE MESURE :
# (1) SOURCE UNIQUE, constatee sur le TEXTE des fichiers comme le ferait un lecteur
#     exterieur : les deux nombres n'existent qu'au bloc de parametres, une seule table
#     les lie aux modes, et l'ancienne constante unique n'a laisse aucun reste ;
# (2) AUCUN TEXTE EN DUR ne contredit la regle : aucun nombre de vies ecrit a la main dans
#     un gabarit joueur, ni dans l'ecran d'options ;
# (3) LE HUD AFFICHE LE VRAI COMPTE DANS LES DEUX MODES, relu en chiffres, sur une partie
#     REELLEMENT JOUEE et non sur un etat construit a la main ;
# (4) LA DESCENTE est d'exactement UN cran par perte, jusqu'a zero, DANS LES DEUX MODES,
#     et la defaite tombe a zero — jamais avant ;
# (5) LE DOMAINE encadre le compteur sans dependre du mode courant, parce que le mode d'une
#     partie en cours peut changer.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const End = preload("res://05_SYSTEMS/end_conditions/end_conditions.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const Reglages = preload("res://05_SYSTEMS/settings/settings.gd")
const Hud = preload("res://06_RUNTIME/adapters/presentation/hud.gd")
const Options = preload("res://06_RUNTIME/adapters/shell_view/options_screen.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_driver.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))

# Fichiers ou la regle de vies pourrait se dupliquer : le bloc de parametres, la table de
# correspondance, et les deux surfaces qui l'affichent.
const CHEMIN_PARAMS := "res://05_SYSTEMS/params/params.gd"
const CHEMIN_SETTINGS := "res://05_SYSTEMS/settings/settings.gd"
const CHEMIN_OPTIONS := "res://06_RUNTIME/adapters/shell_view/options_screen.gd"
const CHEMIN_END := "res://05_SYSTEMS/end_conditions/end_conditions.gd"
const CHEMIN_STATE := "res://05_SYSTEMS/game_state/game_state.gd"


func _texte(chemin: String) -> String:
	var f := FileAccess.open(chemin, FileAccess.READ)
	if f == null:
		return ""
	var t: String = f.get_as_text()
	f.close()
	return t


# CODE SEUL : le commentaire est retire avant comptage. Une PROSE qui parle de la regle
# n'est pas une DUPLICATION de la regle — meme convention que le gate de mutation, qui
# traite `#` comme un commentaire.
func _code_seul(texte: String) -> String:
	var sortie: Array = []
	for ligne in texte.split("\n"):
		var i: int = ligne.find("#")
		sortie.append(ligne if i < 0 else ligne.substr(0, i))
	return "\n".join(sortie)


func run(h) -> void:
	# --- (1) SOURCE UNIQUE, CONSTATEE SUR LE TEXTE. ---
	var params: String = _code_seul(_texte(CHEMIN_PARAMS))
	h.ok(params.contains("const VIES_MODE_DEFI"), "v6.p2: la valeur du defi est declaree au bloc de parametres")
	h.ok(params.contains("const VIES_MODE_MARGE"), "v6.p2: celle de la marge aussi")
	# L'ANCIENNE CONSTANTE UNIQUE N'A LAISSE AUCUN RESTE. Un alias oublie serait un second
	# nombre, donc un endroit ou la regle peut diverger.
	var restes: Array = []
	for chemin in [CHEMIN_PARAMS, CHEMIN_SETTINGS, CHEMIN_OPTIONS, CHEMIN_END, CHEMIN_STATE]:
		if _code_seul(_texte(chemin)).contains("VIES_INITIALES"):
			restes.append(chemin)
	h.eq(restes.size(), 0, "v6.p2: 0 fichier porte encore l'ancienne constante unique")
	# UNE SEULE TABLE lie un mode a un nombre, et elle est dans settings.
	var reglages_src: String = _code_seul(_texte(CHEMIN_SETTINGS))
	h.ok(reglages_src.contains("const VIES_PAR_MODE"), "v6.p2: la table de correspondance vit dans settings")
	h.eq(params.contains("VIES_PAR_MODE"), false, "v6.p2: le bloc de parametres ignore le vocabulaire des modes")
	# Les valeurs de la table NE SONT PAS RECOPIEES : elles nomment les constantes.
	h.ok(reglages_src.contains("P.VIES_MODE_DEFI"), "v6.p2: la table nomme la constante du defi")
	h.ok(reglages_src.contains("P.VIES_MODE_MARGE"), "v6.p2: et celle de la marge")

	# --- (2) AUCUN NOMBRE DE VIES ECRIT A LA MAIN DANS UN TEXTE JOUEUR. ---
	var gabarits_en_dur: int = 0
	for g in Reglages.GABARITS_EXPLICATION:
		var s: String = String(g)
		if s.contains("3 vies") or s.contains("5 vies"):
			gabarits_en_dur += 1
	h.eq(gabarits_en_dur, 0, "v6.p2: 0 gabarit d'explication qui ecrit un nombre de vies a la main")
	var options_src: String = _code_seul(_texte(CHEMIN_OPTIONS))
	h.eq(options_src.contains("VIES_MODE_DEFI"), false, "v6.p2: l'ecran d'options ne recompose pas la regle")
	h.eq(options_src.contains("VIES_MODE_MARGE"), false, "v6.p2: pas davantage pour l'autre valeur")
	# Et le texte PRODUIT n'annonce jamais le nombre de l'autre mode.
	var confusions: int = 0
	for m in Reglages.MODES_VALIDES:
		var autre: int = Reglages.mode_suivant(m)
		var t: String = Options.explication_du_mode({"mode": m})
		if not t.contains(str(Reglages.vies_initiales(m))):
			confusions += 1
		if t.contains(str(Reglages.vies_initiales(autre))):
			confusions += 1
	h.eq(confusions, 0, "v6.p2: 0 mode dont le texte annonce le nombre de l'autre mode")

	# --- (3) LE HUD AFFICHE LE VRAI COMPTE DANS LES DEUX MODES. ---
	# Etat NEUF, releve par le canal d'observation public, relu en chiffres.
	var divergences_neuf: int = 0
	for m in Reglages.MODES_VALIDES:
		var neuf = State.initial(Maze, 1, 0, {"mode": m})
		var releve: Dictionary = Observable.projeter(neuf)
		if int(releve["vies"]) != Reglages.vies_initiales(m):
			divergences_neuf += 1
		if Hud.relire(Hud.ligne(releve), Hud.ETIQUETTE_VIES) != Reglages.vies_initiales(m):
			divergences_neuf += 1
	h.eq(divergences_neuf, 0, "v6.p2: 0 mode ou le releve ou le HUD annonce autre chose que la regle")
	h.eq(Hud.relire(Hud.ligne(Observable.projeter(State.initial(Maze, 1, 0,
		{"mode": Reglages.Mode.NORMAL}))), Hud.ETIQUETTE_VIES), 3,
		"v6.p2: le HUD du mode du defi affiche trois vies")
	h.eq(Hud.relire(Hud.ligne(Observable.projeter(State.initial(Maze, 1, 0,
		{"mode": Reglages.Mode.TEST}))), Hud.ETIQUETTE_VIES), 5,
		"v6.p2: le HUD du mode de la marge affiche cinq vies")

	# SUR UNE PARTIE REELLEMENT JOUEE, tick par tick, dans les DEUX modes : le nombre lu a
	# l'ecran EGALE le compteur de l'etat. Un etat construit a la main ne prouverait rien
	# du chemin reellement emprunte.
	var divergences_jouees: int = 0
	var ticks_joues: int = 0
	for m in Reglages.MODES_VALIDES:
		var jeu = State.initial(Maze, 1, 0, {"mode": m})
		for _t in range(150):
			if jeu.statut != State.Statut.EN_COURS:
				break
			jeu = Loop.step(jeu, Bot.choisir_action(jeu))["etat"]
			ticks_joues += 1
			if Hud.relire(Hud.ligne(Observable.projeter(jeu)), Hud.ETIQUETTE_VIES) != jeu.vies:
				divergences_jouees += 1
	h.eq(ticks_joues, 300, "v6.p2: les deux modes ont ete joues sur la fenetre declaree")
	h.eq(divergences_jouees, 0, "v6.p2: 0 tick ou le HUD diverge du compteur de l'etat")

	# --- (4) UN CRAN PAR PERTE, JUSQU'A ZERO, DANS LES DEUX MODES. ---
	var mauvais_crans: int = 0
	var defaites_prematurees: int = 0
	var arrivees_a_zero: int = 0
	for m in Reglages.MODES_VALIDES:
		var jeu = State.initial(Maze, 1, 0, {"mode": m})
		if jeu.vies != Reglages.vies_initiales(m):
			mauvais_crans += 1
		for _pas in range(Reglages.vies_initiales(m)):
			var avant: int = jeu.vies
			if End.defaite(jeu.vies):
				defaites_prematurees += 1
			End.perdre_une_vie(jeu)
			if jeu.vies != avant - 1:
				mauvais_crans += 1
		if jeu.vies == 0:
			arrivees_a_zero += 1
	h.eq(mauvais_crans, 0, "v6.p2: 0 perte qui ne retire pas exactement une vie")
	h.eq(defaites_prematurees, 0, "v6.p2: aucune defaite declaree avant zero, dans aucun mode")
	h.eq(arrivees_a_zero, Reglages.MODES_VALIDES.size(), "v6.p2: chaque mode arrive a zero")
	h.eq(End.defaite(0), true, "v6.p2: la defaite est declaree a zero")
	h.eq(End.defaite(1), false, "v6.p2: elle ne l'est pas a une vie")
	h.eq(End.defaite(P.VIES_MODE_DEFI), false, "v6.p2: ni a la valeur du defi")
	h.eq(End.defaite(P.VIES_MODE_MARGE), false, "v6.p2: ni a celle de la marge")

	# --- (5) LE DOMAINE ENCADRE, SANS DEPENDRE DU MODE COURANT. ---
	var neuf_defi = State.initial(Maze, 1, 0, {"mode": Reglages.Mode.NORMAL})
	var neuf_marge = State.initial(Maze, 1, 0, {"mode": Reglages.Mode.TEST})
	h.eq(neuf_defi.est_valide(), true, "v6.p2: une partie neuve du defi est valide")
	h.eq(neuf_marge.est_valide(), true, "v6.p2: une partie neuve de la marge aussi")
	neuf_defi.vies = Reglages.vies_maximales() + 1
	h.eq(neuf_defi.est_valide(), false, "v6.p2: une vie de plus que le maximum declare est refusee")
	neuf_defi.vies = Reglages.vies_maximales()
	h.eq(neuf_defi.est_valide(), true, "v6.p2: le maximum lui-meme reste valide")
	neuf_defi.vies = -1
	h.eq(neuf_defi.est_valide(), false, "v6.p2: un compteur negatif est refuse")
	# LA RAISON de cette borne, mesuree et non supposee : basculer le mode d'une partie EN
	# COURS ne doit pas rendre son etat invalide ni rejuster ses vies au milieu du jeu.
	var en_cours = State.initial(Maze, 1, 0, {"mode": Reglages.Mode.TEST})
	h.eq(en_cours.vies, P.VIES_MODE_MARGE, "v6.p2: la partie part avec les vies de son mode")
	en_cours.mode = Reglages.Mode.NORMAL
	h.eq(en_cours.vies, P.VIES_MODE_MARGE, "v6.p2: basculer le mode ne rejuste pas le compteur")
	h.eq(en_cours.est_valide(), true, "v6.p2: et ne rend pas l'etat invalide")
