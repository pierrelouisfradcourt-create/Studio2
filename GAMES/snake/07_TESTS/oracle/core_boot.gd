# core_boot.gd — oracle de la ligne core.boot. SceneTree headless : verifie que l'etat
# initial declare est ATTEINT au boot sans aucune intervention et avance au premier tick
# sans geste. Sortie : "FORGE_ORACLE core_boot {json}", exit 0 si vert.
extends SceneTree

const Boot = preload("res://06_RUNTIME/adapters/runtime_loop/boot.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const DR = preload("res://05_SYSTEMS/input_rules/direction_rules.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

func _initialize() -> void:
	var fails: Array = []
	if Boot.GESTES_AVANT_DEMARRAGE != 0:
		fails.append("gestes avant demarrage != 0")
	if Boot.ECRANS_INTERCALES != 0:
		fails.append("ecrans intercales != 0")
	var s = Boot.etat_initial(1)
	if s.statut != State.Statut.EN_COURS:
		fails.append("statut initial != EN_COURS")
	if s.longueur != P.LONGUEUR_INITIALE:
		fails.append("longueur initiale != declaree")
	var tete = s.segments[0]
	var apres = Loop.step(s, Loop.AUCUNE)["etat"]
	if apres.segments[0] != tete + DR.DROITE:
		fails.append("n'avance pas au 1er tick sans geste")
	var data := {"statut": s.statut, "longueur": s.longueur, "tete_apres": [apres.segments[0].x, apres.segments[0].y]}
	print("FORGE_ORACLE core_boot " + JSON.stringify({"ok": fails.is_empty(), "fails": fails, "data": data}))
	quit(0 if fails.is_empty() else 1)
