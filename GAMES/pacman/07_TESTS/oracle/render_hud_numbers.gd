# render_hud_numbers.gd — ligne render.hud_numbers, capacite F46.
# Releve d'ecran et etat expose au MEME tick : les trois nombres LUS a l'ecran sont
# EGAUX aux trois valeurs de l'etat, et aucun des trois n'est represente uniquement par
# des formes ou des pips.
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())

const Hud = preload("res://06_RUNTIME/adapters/presentation/hud.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_driver.gd")


func run(h) -> void:
	# Les trois grandeurs sont ecrites en CHIFFRES, precedees d'une etiquette lisible.
	h.eq(Hud.texte_score(0), "SCORE 0", "render.hud: le score est ecrit en chiffres")
	h.eq(Hud.texte_vies(3), "VIES 3", "render.hud: les vies sont ecrites en chiffres")
	h.eq(Hud.texte_restantes(244), "PASTILLES 244", "render.hud: les restantes sont ecrites en chiffres")

	# La relecture du texte affiche rend EXACTEMENT le nombre : c'est ce qui rend
	# l'egalite « ecran == etat » verifiable mecaniquement, et pas par relecture humaine.
	h.eq(Hud.relire("SCORE 1234    VIES 2    PASTILLES 7", Hud.ETIQUETTE_SCORE), 1234,
		"render.hud: relecture du score")
	h.eq(Hud.relire("SCORE 1234    VIES 2    PASTILLES 7", Hud.ETIQUETTE_VIES), 2,
		"render.hud: relecture des vies")
	h.eq(Hud.relire("SCORE 1234    VIES 2    PASTILLES 7", Hud.ETIQUETTE_RESTANTES), 7,
		"render.hud: relecture des restantes")
	h.eq(Hud.relire("SCORE 1234", "ABSENT "), -1, "render.hud: etiquette absente -> -1, jamais 0")

	# AUCUN des trois n'est represente uniquement par des formes ou des pips : chaque
	# valeur est presente comme suite de chiffres dans le texte.
	var s = State.initial(Maze, 1)
	var ligne: String = Hud.ligne(Observable.projeter(s))
	h.ok(ligne.contains("0"), "render.hud: le score 0 est ecrit en chiffres")
	# TRIAGE V6 : COUNT_FROZEN (5 -> 3). `s` est construit sans reglages, donc dans le mode
	# par defaut, qui accorde trois vies depuis la decision Pierre du 2026-08-06. Ce que
	# l'assertion protege — « la valeur est ecrite en chiffres, pas en pips » — est inchange.
	h.ok(ligne.contains("3"), "render.hud: les 3 vies sont ecrites en chiffres")
	h.ok(ligne.contains("244"), "render.hud: les 244 restantes sont ecrites en chiffres")

	# AU MEME TICK, sur une partie pilotee : les trois nombres lus egalent l'etat.
	var jeu = State.initial(Maze, 1)
	var divergences: int = 0
	var ticks: int = 0
	for _t in range(300):
		if jeu.statut != State.Statut.EN_COURS:
			break
		jeu = Loop.step(jeu, Bot.choisir_action(jeu))["etat"]
		ticks += 1
		var releve: Dictionary = Observable.projeter(jeu)
		var texte: String = Hud.ligne(releve)
		if Hud.relire(texte, Hud.ETIQUETTE_SCORE) != jeu.score:
			divergences += 1
		if Hud.relire(texte, Hud.ETIQUETTE_VIES) != jeu.vies:
			divergences += 1
		if Hud.relire(texte, Hud.ETIQUETTE_RESTANTES) != jeu.total_pose - jeu.consommees:
			divergences += 1
	h.eq(ticks, 300, "render.hud: la partie a bien tourne 300 ticks")
	h.eq(divergences, 0, "render.hud: 0 divergence entre l'ecran et l'etat sur 300 ticks")
	h.gt(jeu.score, 0, "render.hud: le score affiche a reellement varie")

	# CONTRE-EPREUVE de la relecture : elle DETECTE une valeur differente.
	h.ok(Hud.relire("SCORE 41", Hud.ETIQUETTE_SCORE) != 42, "render.hud: la relecture detecte l'ecart")
