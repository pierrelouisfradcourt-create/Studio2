extends RefCounted
## Harnais des tests de RÈGLES (tests/regles/*.gd) : l'équivalent de `node:test` + `assert` pour
## les tests portés de GAMES/dungeon_666/tests/*.test.mjs.
##
## Un fichier de tests est un script sans class_name qui expose :
##     static func tests(h) -> void:
##         h.test("dash : invulnérable pendant les i-frames", func():
##             var g = h.partie({"seed": 3.0})
##             ...
##             h.ok(g.player.iframes > 0.0, "i-frames posées")
##             h.egal(g.player.state, "dash"))
## Chaque `h.test` est UN test ; une affirmation fausse le marque rouge et note son message.
## (Une lambda GDScript ne peut pas s'interrompre comme une exception JavaScript : les
## affirmations suivantes du même test s'exécutent encore ; seule la première fausse est gardée.)
##
## Garde anti-faux-vert : un test sans aucune affirmation est ROUGE.

const TOL := 1e-9

var fichier := ""
var total := 0
var rouges: Array = [] # [{fichier, nom, message}]
var affirmations := 0
var _nom := ""
var _echec := ""
var _compte := 0

func test(nom: String, corps: Callable) -> void:
	_nom = nom
	_echec = ""
	_compte = 0
	total += 1
	corps.call()
	if _compte == 0 and _echec == "":
		_echec = "aucune affirmation exécutée"
	if _echec != "":
		rouges.append({"fichier": fichier, "nom": nom, "message": _echec})
		print("  ROUGE — %s · %s : %s" % [fichier, nom, _echec])

func _noter(condition: bool, message: String) -> bool:
	_compte += 1
	affirmations += 1
	if not condition and _echec == "":
		_echec = message if message != "" else "affirmation fausse"
	return condition

## assert.ok
func ok(condition, message: String = "") -> bool:
	return _noter(D6Js.truthy(condition), message)

## assert.equal / strictEqual / deepEqual : égalité de valeur, tableaux et dictionnaires compris
## (2 et 2.0 sont égaux ; les nombres à TOL près seulement si `tol` est donné).
func egal(obtenu, attendu, message: String = "", tol: float = 0.0) -> bool:
	var d := D6Comparer.diff(obtenu, attendu, tol, "")
	return _noter(d == "", "%s%s" % [message + " — " if message != "" else "", d])

## assert.notEqual
func different(obtenu, autre, message: String = "") -> bool:
	return _noter(D6Comparer.diff(obtenu, autre, 0.0, "") != "", message if message != "" else "valeurs égales : %s" % str(obtenu))

## Nombres proches (remplace les `Math.abs(a - b) < eps` des tests web).
func proche(obtenu: float, attendu: float, eps: float = TOL, message: String = "") -> bool:
	return _noter(absf(obtenu - attendu) <= eps, "%s%s au lieu de %s (±%s)" % [message + " — " if message != "" else "", str(obtenu), str(attendu), str(eps)])

## assert.throws n'a pas d'équivalent : GDScript n'a pas d'exceptions. Un test web qui attendait
## une exception se porte en vérifiant la valeur de refus (false, null, {ok: false}) ; s'il n'y
## en a pas, le noter ici pour qu'il reste visible.
func non_portable(raison: String) -> void:
	_noter(true, "")
	print("  (non portable) %s · %s : %s" % [fichier, _nom, raison])

# ---------------------------------------------------------------- outillage commun des tests

func ticks(secondes: float) -> int:
	return int(ceilf(secondes / D6Data.DT))

func entree(sur: Dictionary = {}) -> Dictionary:
	var input: Dictionary = D6Game.empty_input()
	input.merge(sur, true)
	return input

## Avance de n pas avec la même entrée (ou une Callable(i) -> entrée) ; rend les événements.
func avancer(g: Dictionary, n: int, sur = null) -> Array:
	var evs: Array = []
	for i in n:
		var input: Dictionary = entree(sur.call(i)) if sur is Callable else entree(sur if sur is Dictionary else {})
		D6Game.step_game(g, input)
		evs.append_array(g.events)
		g.events.clear()
	return evs

func partie(options: Dictionary = {}) -> Dictionary:
	return D6Game.create_game(options)

## Partie de test : salle vidée (aucune vague, aucun obstacle, ni porte ni récompense), héros au centre.
func bac_a_sable(options: Dictionary = {}) -> Dictionary:
	var g: Dictionary = D6Game.create_game(options)
	g.spawns.clear()
	g.enemies.clear()
	g.room.waves = []
	g.room.waveIndex = 0.0
	g.room.obstacles = []
	g.room.cleared = true
	g.room.interact = null
	g.room.doors = []
	g.player.x = g.room.w / 2.0
	g.player.y = g.room.h / 2.0
	g.events.clear()
	return g
