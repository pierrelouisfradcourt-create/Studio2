# v6_p1_mode_governs_lives.gd — POINT P1 DU LOT DE VALIDATION.
#
# DEFAUT MESURE (lot V5, mesure differentielle) : le mode de jeu ne changeait RIEN. Deux
# parties jouees en parallele par le meme bot, une par mode, sur 200 ticks : 0 divergence.
# Le mode etait un PRODUCTEUR SANS CONSOMMATEUR — un reglage offert au joueur, sans effet.
# Aucun oracle de la chaine ne l'avait signale : godot_oracle etait VERT a 2612 assertions.
# C'est la MESURE qui l'a trouve, pas la garde.
#
# DECISION (Pierre, 2026-08-06) : le mode gouverne LES VIES, et elles seules.
#   NORMAL / Arcade     -> le defi
#   TEST   / Decouverte -> la marge d'erreur
#
# CE QUE CETTE PREUVE MESURE :
# (1) la declaration : chaque mode annonce EXACTEMENT UN effet de regle, nomme ;
# (2) la source unique : une seule table lie un mode a un nombre, et ses valeurs viennent
#     du bloc de parametres — aucune n'est recopiee ;
# (3) LA MESURE DIFFERENTIELLE REFAITE, avec son CONTROLE : le meme instrument, applique
#     a deux parties du MEME mode, doit trouver 0 divergence ; applique a deux parties de
#     modes DIFFERENTS, il doit trouver une divergence, et sur les VIES SEULES. Sans le
#     controle, « ca diverge » ne prouverait pas que l'instrument sait aussi dire non ;
# (4) LE DASH RESTE INDEPENDANT DU MODE : c'est une decision de design explicite, donc une
#     propriete a mesurer, pas une absence a supposer ;
# (5) le texte joueur annonce le VRAI nombre, lu a la source.
extends RefCounted

const Reglages = preload("res://05_SYSTEMS/settings/settings.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Dash = preload("res://05_SYSTEMS/dash/dash.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const App = preload("res://05_SYSTEMS/app_state/app_state.gd")
const Options = preload("res://06_RUNTIME/adapters/shell_view/options_screen.gd")
const ShellView = preload("res://06_RUNTIME/adapters/shell_view/shell_view.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_driver.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))

const TICKS_MESURE: int = 200


# CLES du releve sur lesquelles deux traces DIFFERENT, hors le champ de mode lui-meme.
# Rend la LISTE TRIEE, jamais un compte nu : « ca diverge » ne dit pas SUR QUOI, et c'est
# exactement la question que ce lot doit trancher.
func _cles_divergentes(a: Dictionary, b: Dictionary) -> Array:
	var sortie: Array = []
	for c in Observable.CLES:
		if c == "mode_jeu":
			continue
		if a.get(c) != b.get(c):
			sortie.append(c)
	sortie.sort()
	return sortie


# INSTRUMENT DE MESURE, applique tel quel aux deux campagnes (controle et reel) : deux
# parties jouees en parallele par le MEME bot sur la MEME carte et la MEME graine, seuls
# les reglages differant. Rend le nombre de ticks joues, le nombre de ticks divergents et
# l'UNION des cles qui ont diverge.
func _campagne(reglages_a: Dictionary, reglages_b: Dictionary) -> Dictionary:
	var a = State.initial(Maze, 7, 0, reglages_a)
	var b = State.initial(Maze, 7, 0, reglages_b)
	var ticks: int = 0
	var ticks_divergents: int = 0
	var cles: Array = []
	for _t in range(TICKS_MESURE):
		if a.statut != State.Statut.EN_COURS or b.statut != State.Statut.EN_COURS:
			break
		a = Loop.step(a, Bot.choisir_action(a))["etat"]
		b = Loop.step(b, Bot.choisir_action(b))["etat"]
		ticks += 1
		var d: Array = _cles_divergentes(Observable.projeter(a), Observable.projeter(b))
		if not d.is_empty():
			ticks_divergents += 1
		for c in d:
			if not cles.has(c):
				cles.append(c)
	cles.sort()
	return {"ticks": ticks, "ticks_divergents": ticks_divergents, "cles": cles}


func run(h) -> void:
	# --- (1) LA DECLARATION : UN EFFET DE REGLE PAR MODE, NOMME. ---
	h.eq(Reglages.EFFETS_DE_REGLE.size(), Reglages.MODES_VALIDES.size(),
		"v6.p1: une declaration d'effets par mode")
	h.eq(Reglages.effets_de_regle(Reglages.Mode.NORMAL).size(), 1,
		"v6.p1: le mode Arcade declare exactement un effet de regle")
	h.eq(Reglages.effets_de_regle(Reglages.Mode.TEST).size(), 1,
		"v6.p1: le mode Decouverte aussi")
	h.eq(Reglages.effets_de_regle(Reglages.Mode.NORMAL)[0], Reglages.GRANDEUR_VIES,
		"v6.p1: et cet effet est nomme — les vies")
	h.eq(Reglages.effets_de_regle(Reglages.Mode.TEST)[0], Reglages.GRANDEUR_VIES,
		"v6.p1: la meme grandeur pour le second mode")
	h.eq(Reglages.effets_de_regle(9).size(), 0, "v6.p1: un mode inconnu ne declare rien")

	# --- (2) SOURCE UNIQUE : une table, des valeurs qui viennent du bloc de parametres. ---
	h.eq(Reglages.VIES_PAR_MODE.size(), Reglages.MODES_VALIDES.size(),
		"v6.p1: une valeur de vies par mode du vocabulaire ferme")
	h.eq(Reglages.vies_initiales(Reglages.Mode.NORMAL), P.VIES_MODE_DEFI,
		"v6.p1: le mode du defi accorde la valeur declaree du defi")
	h.eq(Reglages.vies_initiales(Reglages.Mode.TEST), P.VIES_MODE_MARGE,
		"v6.p1: le mode de la marge accorde la valeur declaree de la marge")
	h.eq(P.VIES_MODE_DEFI, 3, "v6.p1: le defi vaut trois vies")
	h.eq(P.VIES_MODE_MARGE, 5, "v6.p1: la marge vaut cinq vies")
	h.gt(P.VIES_MODE_MARGE, P.VIES_MODE_DEFI,
		"v6.p1: la marge est STRICTEMENT plus genereuse que le defi")
	# Un mode hors vocabulaire retombe sur le MODE PAR DEFAUT, jamais sur un nombre invente.
	h.eq(Reglages.vies_initiales(9), Reglages.vies_initiales(Reglages.MODE_PAR_DEFAUT),
		"v6.p1: un mode inconnu retombe sur le defaut declare")
	h.eq(Reglages.vies_initiales(-1), Reglages.vies_initiales(Reglages.MODE_PAR_DEFAUT),
		"v6.p1: un mode negatif non plus n'invente pas de valeur")
	# LE MAXIMUM est DERIVE de la table, jamais ecrit a la main.
	h.eq(Reglages.vies_maximales(), P.VIES_MODE_MARGE,
		"v6.p1: la borne haute du domaine est la plus grande valeur declaree")

	# LA PARTIE NEUVE OBEIT AU MODE, carte par carte : c'est une regle, pas une propriete
	# de carte. Le mode par defaut d'une partie sans reglages est le mode du defi.
	var ecarts_defi: int = 0
	var ecarts_marge: int = 0
	for i in range(ContentV2.nb_niveaux()):
		var carte = MazeClass.depuis_descripteur(ContentV2.descripteur(i))
		var cadence: int = ContentV2.cadence(i)
		if State.initial(carte, i + 1, cadence, {"mode": Reglages.Mode.NORMAL}).vies != P.VIES_MODE_DEFI:
			ecarts_defi += 1
		if State.initial(carte, i + 1, cadence, {"mode": Reglages.Mode.TEST}).vies != P.VIES_MODE_MARGE:
			ecarts_marge += 1
	h.gt(ContentV2.nb_niveaux(), 2, "v6.p1: la mesure porte sur plus de deux cartes")
	h.eq(ecarts_defi, 0, "v6.p1: 0 carte ou le mode du defi ne donne pas ses vies")
	h.eq(ecarts_marge, 0, "v6.p1: 0 carte ou le mode de la marge ne donne pas ses vies")
	h.eq(State.initial(Maze, 1).vies, P.VIES_MODE_DEFI,
		"v6.p1: sans reglages, la partie part dans le mode du defi")

	# --- (3) LA MESURE DIFFERENTIELLE, REFAITE, AVEC SON CONTROLE. ---
	var normal: Dictionary = {"mode": Reglages.Mode.NORMAL}
	var test: Dictionary = {"mode": Reglages.Mode.TEST}
	# CONTROLE : le MEME instrument, deux parties du MEME mode. Il doit trouver 0.
	var controle: Dictionary = _campagne(normal, normal)
	# REEL : les deux modes.
	var reel: Dictionary = _campagne(normal, test)
	print("[v6.p1] MESURE DIFFERENTIELLE DU MODE — controle(NORMAL vs NORMAL) ticks=%d divergents=%d cles=%s"
		% [controle["ticks"], controle["ticks_divergents"], str(controle["cles"])])
	print("[v6.p1] MESURE DIFFERENTIELLE DU MODE — reel(NORMAL vs TEST)      ticks=%d divergents=%d cles=%s"
		% [reel["ticks"], reel["ticks_divergents"], str(reel["cles"])])

	h.eq(controle["ticks"], TICKS_MESURE, "v6.p1: le controle a tourne les ticks declares")
	h.eq(controle["ticks_divergents"], 0, "v6.p1: controle — 0 divergence entre deux parties du meme mode")
	h.eq(controle["cles"], [], "v6.p1: controle — aucune cle ne diverge")

	h.eq(reel["ticks"], TICKS_MESURE, "v6.p1: la mesure reelle a tourne les ticks declares")
	h.eq(reel["ticks_divergents"], TICKS_MESURE,
		"v6.p1: le mode diverge a CHAQUE tick — il n'est plus inerte")
	h.gt(reel["ticks_divergents"], controle["ticks_divergents"],
		"v6.p1: le meme instrument distingue le mode du non-mode")
	# ET SUR LES VIES SEULES : c'est le controle que le mode ne gouverne rien d'autre par
	# accident. Egalite STRICTE de la liste, jamais un `has()` qui laisserait passer une
	# seconde divergence.
	h.eq(reel["cles"], [Reglages.GRANDEUR_VIES],
		"v6.p1: la divergence porte sur les vies, et sur elles seules")
	h.eq(Observable.CLES.has(Reglages.GRANDEUR_VIES), true,
		"v6.p1: la grandeur declaree est bien une cle du releve observable")

	# --- (4) LE DASH RESTE INDEPENDANT DU MODE. ---
	# Il n'est PAS dans la table des effets du mode : le mode ne le gouverne pas.
	h.eq(Reglages.effets_de_regle(Reglages.Mode.NORMAL).has("dash"), false,
		"v6.p1: le mode Arcade ne declare aucun effet sur le dash")
	h.eq(Reglages.effets_de_regle(Reglages.Mode.TEST).has("dash"), false,
		"v6.p1: le mode Decouverte non plus")
	# Le dash est ACTIF dans les DEUX modes, et son budget de pas y est le MEME.
	var budgets: Array = []
	for m in Reglages.MODES_VALIDES:
		var s = State.initial(Maze, 3, 0, {"mode": m, "dash_actif": true})
		budgets.append(Dash.appliquer(s, true))
	h.eq(budgets[0], budgets[1], "v6.p1: le budget de dash est le meme dans les deux modes")
	h.eq(budgets[0], P.PAS_DASH, "v6.p1: et c'est bien le budget de dash declare")
	# Desactive, il est inerte dans les DEUX modes.
	var inertes: int = 0
	for m in Reglages.MODES_VALIDES:
		var s = State.initial(Maze, 3, 0, {"mode": m, "dash_actif": false})
		if Dash.appliquer(s, true) != P.PAS_NORMAL:
			inertes += 1
	h.eq(inertes, 0, "v6.p1: dash desactive -> budget normal dans les deux modes")
	# Basculer le MODE ne touche pas au reglage du dash, et reciproquement : deux reglages,
	# deux effets disjoints.
	var r0: Dictionary = Reglages.initial()
	var apres_mode: Dictionary = Options.activer(Options.Entree.MODE, r0)
	h.ok(apres_mode["mode"] != r0["mode"], "v6.p1: basculer le mode change le mode")
	h.eq(apres_mode["dash_actif"], r0["dash_actif"], "v6.p1: et ne touche pas au dash")
	var apres_dash: Dictionary = Options.activer(Options.Entree.DASH, r0)
	h.ok(apres_dash["dash_actif"] != r0["dash_actif"], "v6.p1: basculer le dash change le dash")
	h.eq(apres_dash["mode"], r0["mode"], "v6.p1: et ne touche pas au mode")

	# --- (5) LE TEXTE JOUEUR DIT LA VRAIE DIFFERENCE, LUE A LA SOURCE. ---
	var texte_defi: String = Options.explication_du_mode({"mode": Reglages.Mode.NORMAL})
	var texte_marge: String = Options.explication_du_mode({"mode": Reglages.Mode.TEST})
	h.ok(texte_defi.contains(str(P.VIES_MODE_DEFI)), "v6.p1: le texte du defi annonce ses trois vies")
	h.ok(texte_marge.contains(str(P.VIES_MODE_MARGE)), "v6.p1: celui de la marge annonce ses cinq vies")
	h.ok(texte_defi != texte_marge, "v6.p1: les deux explications different")
	# ELLES SUIVENT LA SOURCE : le nombre affiche est EGAL au compteur d'une partie neuve
	# du meme mode — la preuve que rien n'est ecrit a la main.
	var divergences_texte: int = 0
	for m in Reglages.MODES_VALIDES:
		var neuve = State.initial(Maze, 1, 0, {"mode": m})
		if not Options.explication_du_mode({"mode": m}).contains(str(neuve.vies)):
			divergences_texte += 1
	h.eq(divergences_texte, 0, "v6.p1: 0 mode dont le texte annonce autre chose que ses vies reelles")
	# CONTRE-EPREUVE : le gabarit n'est pas fige — il suit la valeur remise.
	h.ok(Reglages.explication(Reglages.Mode.NORMAL, P.VIES_MODE_DEFI + 1) != texte_defi,
		"v6.p1: le texte suit la valeur remise, il n'est pas ecrit en dur")
	# LE TEXTE V5 EST PARTI : « memes regles » etait vrai quand le mode etait inerte, il ne
	# l'est plus. Une phrase qui survit a la mesure qui la contredit est un defaut.
	var survivances: int = 0
	for m in Reglages.MODES_VALIDES:
		if Reglages.explication(m, Reglages.vies_initiales(m)).contains("Memes regles"):
			survivances += 1
	h.eq(survivances, 0, "v6.p1: 0 texte qui annonce encore « memes regles »")

	# --- MODE ET DASH SONT DISTINGUES POUR LE JOUEUR, ET LA MENTION EST REELLEMENT LUE. ---
	h.ok(Reglages.MENTION_MODE_ET_DASH.contains("Dash"), "v6.p1: la mention nomme le dash")
	h.ok(Reglages.MENTION_MODE_ET_DASH.contains("deux modes"),
		"v6.p1: elle dit qu'il vaut dans les deux modes")
	var contexte: Dictionary = {"selection": 0, "reglages": Reglages.initial(), "releve": {}}
	var ecran: Dictionary = ShellView.ecran(App.Etat.OPTIONS, contexte)
	h.eq(ecran["lignes"].size(), Options.ENTREES.size() + Options.LIGNES_DE_LECTURE,
		"v6.p1: l'ecran porte les entrees plus ses lignes de lecture")
	h.eq(Options.LIGNES_DE_LECTURE, 2, "v6.p1: deux lignes de lecture declarees")
	h.eq(String(ecran["lignes"][Options.ENTREES.size() + 1]), Reglages.MENTION_MODE_ET_DASH,
		"v6.p1: la mention est la derniere ligne de l'ecran d'options")
