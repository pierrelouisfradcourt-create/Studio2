# core_scoring.gd — oracle produit de la ligne core.scoring. SceneTree headless.
# Observable : le bareme est SUPERLINEAIRE — un quadruple rapporte plus PAR LIGNE qu'un simple.
# Sortie : "FORGE_ORACLE core_scoring {json}", exit 0 si vert.
extends SceneTree

const Scoring = preload("res://05_SYSTEMS/scoring/scoring.gd")

func _initialize() -> void:
	var fails: Array = []
	var data: Dictionary = {}
	var s1: int = Scoring.score_for(1)
	var s4: int = Scoring.score_for(4)
	if Scoring.score_for(0) != 0:
		fails.append("0 ligne rapporte des points")
	if s1 <= 0:
		fails.append("un simple ne rapporte rien")
	if float(s4) / 4.0 <= float(s1):
		fails.append("bareme NON superlineaire (quad/4=%.1f <= simple=%d)" % [float(s4) / 4.0, s1])
	var croissant := true
	var prec := -1
	for n in range(1, 5):
		var v: int = Scoring.score_for(n)
		if v <= prec:
			croissant = false
		prec = v
	if not croissant:
		fails.append("bareme non strictement croissant")
	data = {"simple": s1, "quad": s4, "par_ligne_quad": float(s4) / 4.0}
	_emit(fails, data)

func _emit(fails: Array, data: Dictionary) -> void:
	print("FORGE_ORACLE core_scoring " + JSON.stringify({"ok": fails.is_empty(), "fails": fails, "data": data}))
	quit(0 if fails.is_empty() else 1)
