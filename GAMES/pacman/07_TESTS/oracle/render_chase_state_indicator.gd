# render_chase_state_indicator.gd — ligne render.chase_state_indicator, capacite F47.
# Releves au tick PRECEDANT le seuil et au tick DU seuil : l'indication d'etat LISIBLE a
# l'ecran DIFFERE entre les deux.
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())

const Banner = preload("res://06_RUNTIME/adapters/presentation/state_banner.gd")
const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_driver.gd")


func run(h) -> void:
	# Trois mentions LISIBLES, deux a deux differentes — jamais une nuance de couleur seule.
	var mentions := {}
	mentions[Banner.MENTION_DISPERSION] = true
	mentions[Banner.MENTION_POURSUITE] = true
	mentions[Banner.MENTION_EFFRAYE] = true
	h.eq(mentions.size(), 3, "render.banner: trois mentions deux a deux differentes")
	var couleurs := {}
	couleurs[Banner.COULEUR_DISPERSION] = true
	couleurs[Banner.COULEUR_POURSUITE] = true
	couleurs[Banner.COULEUR_EFFRAYE] = true
	h.eq(couleurs.size(), 3, "render.banner: trois couleurs deux a deux differentes")

	# La mention se deduit du SEUL releve observable.
	var s = State.initial(Maze, 1)
	var releve: Dictionary = Observable.projeter(s)
	h.eq(Banner.mention(releve), Banner.MENTION_POURSUITE, "render.banner: poursuite au tick 0")
	var effraye: Dictionary = releve.duplicate()
	effraye["effraye_restant"] = 10
	h.eq(Banner.mention(effraye), Banner.MENTION_EFFRAYE, "render.banner: mention Effraye")
	var dispersion: Dictionary = releve.duplicate()
	dispersion["mode"] = "DISPERSION"
	h.eq(Banner.mention(dispersion), Banner.MENTION_DISPERSION, "render.banner: mention dispersion")
	h.eq(Banner.couleur(effraye), Banner.COULEUR_EFFRAYE, "render.banner: couleur Effraye")

	# AU SEUIL : l'indication lisible DIFFERE entre le tick precedent et le tick du seuil.
	var jeu = State.initial(Maze, 1)
	for i in range(4):
		jeu.dehors[i] = true
		jeu.sorties_maison[i] = 0
	var differente: bool = false
	var seuil_atteint: int = -1
	var avant_texte := ""
	var apres_texte := ""
	for _t in range(Chase.seuils()[0] + 60):
		if jeu.statut != State.Statut.EN_COURS:
			break
		var avant: Dictionary = Observable.projeter(jeu)
		jeu = Loop.step(jeu, Bot.choisir_action(jeu))["etat"]
		if Chase.est_seuil(jeu.horloge):
			var apres: Dictionary = Observable.projeter(jeu)
			differente = Banner.indication_differente(avant, apres)
			avant_texte = Banner.mention(avant)
			apres_texte = Banner.mention(apres)
			seuil_atteint = jeu.horloge
			break
	h.eq(seuil_atteint, Chase.seuils()[0], "render.banner: le premier seuil a bien ete atteint")
	h.eq(differente, true, "render.banner: l'indication differe entre les deux releves")
	h.ok(avant_texte != apres_texte, "render.banner: les deux mentions sont textuellement differentes")

	# HORS SEUIL, l'indication ne change pas d'un tick a l'autre.
	var t = State.initial(Maze, 1)
	var r1: Dictionary = Observable.projeter(t)
	t = Loop.step(t, Bot.choisir_action(t))["etat"]
	var r2: Dictionary = Observable.projeter(t)
	h.eq(Banner.indication_differente(r1, r2), false, "render.banner: aucune bascule hors seuil")

	# Le nom lisible d'un mode est stable.
	h.eq(Banner.nom_mode_lisible(Chase.Mode.POURSUITE), Banner.MENTION_POURSUITE,
		"render.banner: nom lisible du mode poursuite")
