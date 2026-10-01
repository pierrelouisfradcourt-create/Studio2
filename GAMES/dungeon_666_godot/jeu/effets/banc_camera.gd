extends Camera2D
## Caméra du BANC d'Effets (provisoire : la vraie est jeu/monde/camera.gd). Centrée sur le héros,
## avec les trois appels du contrat — secouer, recul, coup_de_zoom — portés de addTrauma, kick et
## zoomKick de GAMES/dungeon_666/src/render/camera.mjs, et un compteur d'appels pour la vérification.

const ECHELLE := 1.143 # 960 × 540 px pour ≈ 840 × 472 u
const SECOUSSE_MAX := 16.0
const SECOUSSE_ROT := 0.03
const TRAUMA_DECLIN := 1.8
const TRAUMA_HEROS_MAX := 0.55
const RECUL_RETOUR := 16.0
const RECUL_MAX := 12.0
const SECOUSSE_RYTHME := 55.0
const ZOOM_RYTHME := 9.0

var app: Node
var partie: Node
var trauma := 0.0
## Appels reçus depuis la dernière remise à zéro : {secouer, recul, coup_de_zoom} -> somme des forces.
var appels := {"secouer": 0.0, "recul": 0.0, "coup_de_zoom": 0.0}

var _recul := Vector2.ZERO
var _zoom := 1.0
var _zoom_cible := 1.0
var _t := 0.0

func brancher(p_app: Node, p_partie: Node) -> void:
	app = p_app
	partie = p_partie

func secouer(force: float, du_heros: bool = false) -> void:
	appels.secouer += force
	var ajout: float = force * app.reglages.shake
	if du_heros:
		if trauma < TRAUMA_HEROS_MAX:
			trauma = minf(TRAUMA_HEROS_MAX, trauma + ajout)
		return
	trauma = minf(1.0, trauma + ajout)

func recul(dir: Vector2, force: float) -> void:
	appels.recul += force
	_recul = (_recul + dir * force * app.reglages.shake).limit_length(RECUL_MAX)

func coup_de_zoom(force: float) -> void:
	appels.coup_de_zoom += force
	_zoom_cible = maxf(_zoom_cible, 1.0 + force)

func remettre_a_zero() -> void:
	appels = {"secouer": 0.0, "recul": 0.0, "coup_de_zoom": 0.0}

static func _bruit(t: float, graine: float) -> float:
	return sin(t + graine) * 0.5 + sin(t * 2.3 + graine * 1.7) * 0.3 + sin(t * 4.1 + graine * 2.9) * 0.2

func _process(delta: float) -> void:
	if partie == null or partie.game == null:
		return
	var dt := minf(0.1, delta)
	_t += dt
	trauma = maxf(0.0, trauma - TRAUMA_DECLIN * dt)
	var s := trauma * trauma
	var ft := _t * SECOUSSE_RYTHME
	_recul *= exp(-RECUL_RETOUR * dt)
	_zoom += (_zoom_cible - _zoom) * (1.0 - exp(-ZOOM_RYTHME * dt))
	_zoom_cible += (1.0 - _zoom_cible) * (1.0 - exp(-ZOOM_RYTHME * 0.6 * dt))
	var heros: Vector2 = partie.position_dessin(partie.game.player, true)
	position = heros - Vector2(_bruit(ft, 1.0), _bruit(ft, 7.0)) * SECOUSSE_MAX * s + _recul
	rotation = SECOUSSE_ROT * s * _bruit(ft, 13.0)
	zoom = Vector2.ONE * ECHELLE * _zoom
