extends Logger
## Témoin d'erreurs du test de parcours (jeu/essai/test_parcours.gd) : retient chaque erreur que
## le moteur écrit pendant l'essai (erreur de script, `push_error`, erreur du moteur). En GDScript,
## une erreur n'arrête pas le test : sans ce témoin, seul l'oracle la verrait (« SCRIPT ERROR »
## dans la sortie). Les avertissements ne comptent pas.
##   OS.add_logger(temoin) … OS.remove_logger(temoin)

const RETENUES_MAX := 12 # au-delà, on compte sans retenir le texte
## Erreurs du moteur dues à l'absence de fenêtre (--headless), pas au jeu assemblé : elles sont
## comptées et SIGNALÉES avec l'endroit du script qui les provoque, sans rougir le parcours.
const SANS_FENETRE := ["Not supported by this display server"]

var nombre := 0
var retenues: Array[String] = []
var sans_fenetre := 0
var lieux_sans_fenetre := {} # « fichier:ligne (fonction) » -> nombre
var _verrou := Mutex.new()

## Appelé par le moteur, parfois hors du fil principal : d'où le verrou.
func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	var texte := rationale if rationale != "" else code
	var lieu := _lieu_du_script(script_backtraces)
	_verrou.lock()
	if SANS_FENETRE.any(func(motif: String) -> bool: return texte.contains(motif)):
		sans_fenetre += 1
		lieux_sans_fenetre[lieu] = lieux_sans_fenetre.get(lieu, 0) + 1
	else:
		nombre += 1
		if retenues.size() < RETENUES_MAX:
			retenues.append("%s:%d (%s) %s%s" % [file, line, function, texte, " ← " + lieu if lieu != "" else ""])
	_verrou.unlock()

## L'endroit du script qui a provoqué l'erreur (haut de la pile GDScript), "" s'il n'y en a pas.
func _lieu_du_script(piles: Array[ScriptBacktrace]) -> String:
	for pile in piles:
		if pile.get_frame_count() > 0:
			return "%s:%d (%s)" % [pile.get_frame_file(0), pile.get_frame_line(0), pile.get_frame_function(0)]
	return ""
