# speed_band_report.gd — oracle de la ligne speed.band_reporting (+ meta.metric_variance).
# SceneTree headless : rapporte DEUX grandeurs SEPAREMENT nommees, en valeurs BRUTES,
# jamais agregees :
#   (1) bande_regle_pure  : [plancher declare, periode initiale declaree] — la plage
#       theorique de periode fixee par params.
#   (2) bande_bot_mesuree : [periode min, periode max] REELLEMENT traversees par le bot
#       sur une partie complete.
# Preuve de VARIANCE (regle Pierre 2026-07-21) : chaque bande porte >= 2 valeurs distinctes,
# sinon la grandeur ne mesure rien. Sortie : "FORGE_ORACLE speed_band_report {json}", exit 0.
extends SceneTree

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_policy.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

const GRAINE := 1
const BORNE_TICKS := 2000

func _initialize() -> void:
	var fails: Array = []
	# (1) Bande de la regle pure — valeurs brutes, sans calcul derive.
	var bande_regle := [P.PERIODE_PLANCHER_MS, P.VITESSE_INITIALE_MS]
	# (2) Bande reellement mesuree par le bot.
	var s = State.initial(GRAINE)
	var periode_min: float = s.periode
	var periode_max: float = s.periode
	var periodes_distinctes := {}
	var t := 0
	while t < BORNE_TICKS and s.statut == State.Statut.EN_COURS:
		periode_min = min(periode_min, s.periode)
		periode_max = max(periode_max, s.periode)
		periodes_distinctes[s.periode] = true
		var action: Vector2i = Bot.choisir_action(s)
		s = Loop.step(s, action)["etat"]
		t += 1
	periode_min = min(periode_min, s.periode)
	periode_max = max(periode_max, s.periode)
	periodes_distinctes[s.periode] = true
	var bande_bot := [periode_min, periode_max]
	# VARIANCE : la bande de regle porte 2 bornes distinctes.
	if bande_regle[0] == bande_regle[1]:
		fails.append("bande regle a variance nulle")
	# VARIANCE : le bot a REELLEMENT traverse >= 2 periodes distinctes (acceleration reelle).
	if periodes_distinctes.size() < 2:
		fails.append("bot n'a traverse qu'une seule periode (acceleration non observee)")
	print("FORGE_ORACLE speed_band_report " + JSON.stringify({
		"ok": fails.is_empty(), "fails": fails,
		"bande_regle_pure": bande_regle,
		"bande_bot_mesuree": bande_bot,
		"periodes_distinctes_bot": periodes_distinctes.size(),
	}))
	quit(0 if fails.is_empty() else 1)
