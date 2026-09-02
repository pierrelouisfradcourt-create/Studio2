# solo_session.gd — oracle de la ligne play.solo_full_loop. SceneTree headless : depuis
# l'ouverture, une sequence d'entrees BORNEE mene successivement a AVANCER, MANGER, GRANDIR,
# TERMINER, puis a un ECRAN DE FIN actif. Le bot pilote le MEME canal public que le clavier.
# Sortie : "FORGE_ORACLE solo_session {json}", exit 0 si vert.
extends SceneTree

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_policy.gd")
const EndScreen = preload("res://06_RUNTIME/adapters/presentation/end_screen.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

const GRAINE := 1
const BORNE_TICKS := 2000

func _initialize() -> void:
	var fails: Array = []
	var s = State.initial(GRAINE)
	var longueur_initiale: int = s.longueur
	var a_avance := false
	var a_mange := false
	var a_grandi := false
	var tete_precedente: Vector2i = s.segments[0]
	var t := 0
	while t < BORNE_TICKS and s.statut == State.Statut.EN_COURS:
		var action: Vector2i = Bot.choisir_action(s)
		var avant_fruits: int = s.fruits
		s = Loop.step(s, action)["etat"]
		if s.segments[0] != tete_precedente:
			a_avance = true
		if s.fruits > avant_fruits:
			a_mange = true
		if s.longueur > longueur_initiale:
			a_grandi = true
		tete_precedente = s.segments[0]
		t += 1
	# AVANCER
	if not a_avance:
		fails.append("le serpent n'a jamais avance")
	# MANGER
	if not a_mange:
		fails.append("aucune nourriture mangee")
	# GRANDIR
	if not a_grandi:
		fails.append("le serpent n'a jamais grandi")
	# TERMINER (par victoire, cible atteinte)
	if s.statut != State.Statut.TERMINE_GAGNE:
		fails.append("partie non terminee-gagnee dans la borne (%d ticks)" % t)
	# ECRAN DE FIN actif + message non vide, parametre par le statut terminal
	if not EndScreen.est_actif(s.statut):
		fails.append("ecran de fin non actif sur statut terminal")
	if EndScreen.message(s.statut) == "":
		fails.append("message de fin vide")
	print("FORGE_ORACLE solo_session " + JSON.stringify({
		"ok": fails.is_empty(), "fails": fails,
		"ticks": t, "score": s.score, "longueur": s.longueur, "statut": s.statut,
		"message_fin": EndScreen.message(s.statut),
	}))
	quit(0 if fails.is_empty() else 1)
