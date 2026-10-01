extends Camera2D
## Caméra du Monde : suivi lissé du héros avec avance dans la direction de visée ou de marche,
## bornée à la salle, cadrage du duel contre un Gardien, tremblement par « trauma »
## (amplitude = trauma², Vlambeer / Squirrel Eiserloh), recul directionnel et coups de zoom.
## Portage de GAMES/dungeon_666/src/render/camera.mjs. Présentation pure : lit la partie, ne la
## modifie jamais.
##
## Contrat (jeu/ARCHITECTURE.md) : secouer(), recul(), coup_de_zoom().

const AIRE_CIBLE := 840.0 * 472.0 # unités² visibles (≈ 840 × 472 en 16:9)
const VISIBLE_MIN := 400.0 # la plus petite dimension visible ne descend pas sous ce seuil
const MARGE_COTE := 40.0 # u de « hors salle » autorisées à l'écran
const MARGE_HAUT := 110.0 # plus large en haut : le HUD ne recouvre jamais le héros
const MARGE_BAS := 70.0
const SUIVI := 10.0 # 1/s : lissage exponentiel du suivi
const AVANCE := 70.0 # u : avance vers la visée
const SECOUSSE_MAX := 16.0 # u : amplitude maximale du tremblement
const ROTATION_MAX := 0.03 # rad
const TRAUMA_PERTE := 1.8 # trauma perdu par seconde
const TRAUMA_HEROS_MAX := 0.55 # les coups du héros ne poussent pas le trauma au-delà
const RECUL_RETOUR := 16.0 # 1/s : retour exponentiel du recul directionnel
const RECUL_MAX := 12.0 # u : somme des reculs plafonnée
const SECOUSSE_CADENCE := 55.0 # rad/s du bruit de tremblement
const ZOOM_CADENCE := 9.0
const CADRE_GARDIEN := 0.35 # part de l'écart héros → Gardien intégrée au cadrage
const ZOOM_GARDIEN := 0.88 # léger recul de caméra pendant un combat de Gardien
const CADRE_GARDIEN_CADENCE := 3.0
const POUCES := 0.05 # part de la hauteur visible : héros cadré au-dessus du centre (pouces en bas)
const POUCES_PORTRAIT := 0.16
const BANDE_POUCES := 0.1 # part de la vue « hors salle » permise en bas (paysage)
const BANDE_POUCES_PORTRAIT := 0.4
const MARGE_HEROS := 40.0 # u : marge entre le héros et le groupe de boutons (paysage tactile)

var app: Node
var partie: Node
## Largeur d'écran (unités d'interface) occupée à droite par les boutons tactiles : le héros est
## cadré au centre de la zone libre. Posée par la vue qui dessine ces boutons ; 0 sinon.
var retrait_droit := 0.0

## Centre visé (sans tremblement ni recul), échelle écran / monde et étendue visible, en unités.
var centre := Vector2.ZERO
var echelle := 1.0
var vue := Vector2(840.0, 472.0)

var _trauma := 0.0
var _secousse := Vector2.ZERO
var _roulis := 0.0
var _zoom := 1.0
var _zoom_cible := 1.0
var _zoom_base := 1.0
var _temps := 0.0
var _calee := false
var _recul := Vector2.ZERO
var _part_gardien := 0.0
var _salle = null

func brancher(p_app: Node, p_partie: Node) -> void:
	app = p_app
	partie = p_partie
	partie.partie_demarree.connect(recaler)

## Tremblement : `force` s'ajoute au trauma (0..1). `du_heros` : plafonné, ses coups ne secouent
## jamais autant que ceux qu'il reçoit.
func secouer(force: float, du_heros: bool = false) -> void:
	var ajout := force * _intensite()
	if du_heros:
		if _trauma < TRAUMA_HEROS_MAX:
			_trauma = minf(TRAUMA_HEROS_MAX, _trauma + ajout)
		return
	_trauma = minf(1.0, _trauma + ajout)

## Recul directionnel : c'est lui qui fait sentir les coups légers.
func recul(dir: Vector2, force: float) -> void:
	_recul = (_recul + dir * force * _intensite()).limit_length(RECUL_MAX)

func coup_de_zoom(force: float) -> void:
	_zoom_cible = maxf(_zoom_cible, 1.0 + force)

## Oublie le suivi en cours : la caméra se pose d'un coup sur sa cible (nouvelle salle).
func recaler() -> void:
	_calee = false
	_trauma = 0.0
	_recul = Vector2.ZERO

func vers_ecran(p: Vector2) -> Vector2:
	return (p - position).rotated(_roulis) * (echelle * _zoom) + get_viewport_rect().size / 2.0

func vers_monde(p: Vector2) -> Vector2:
	return ((p - get_viewport_rect().size / 2.0) / (echelle * _zoom)).rotated(-_roulis) + position

func _intensite() -> float:
	if app == null or not (app.get("reglages") is Dictionary):
		return 1.0
	return float(app.reglages.get("shake", 1.0))

func _process(delta: float) -> void:
	if partie == null or partie.game == null:
		return
	var g: Dictionary = partie.game
	if not is_same(g.room, _salle):
		_salle = g.room
		recaler()
	_ajuster(get_viewport_rect().size)
	if not partie.en_pause or not _calee:
		_suivre(g, minf(0.1, delta))
		_animer(minf(0.1, delta))
	position = centre - _secousse + _recul
	rotation = -_roulis
	zoom = Vector2.ONE * (echelle * _zoom)

## Échelle écran / monde selon la taille de la vue (fitCamera).
func _ajuster(ecran: Vector2) -> void:
	var e := sqrt(ecran.x * ecran.y / AIRE_CIBLE)
	if minf(ecran.x, ecran.y) / e < VISIBLE_MIN:
		e = minf(ecran.x, ecran.y) / VISIBLE_MIN
	echelle = e
	vue = ecran / e

func _suivre(g: Dictionary, dt: float) -> void:
	var cible := _borner(g, _cible(g, dt))
	if not _calee:
		centre = cible
		_calee = true
	else:
		centre += (cible - centre) * (1.0 - exp(-SUIVI * dt))

## Point visé avant bornage : le héros, l'avance vers sa visée, et le duel contre le Gardien.
func _cible(g: Dictionary, dt: float) -> Vector2:
	var p: Dictionary = g.player
	var heros: Vector2 = partie.position_dessin(p, true)
	var dir := Vector2.from_angle(p.facing)
	if p.moveX * p.moveX + p.moveY * p.moveY > 0.04:
		dir = Vector2(p.moveX, p.moveY)
	var portrait := vue.y > vue.x
	var retrait := _retrait()
	var cible := heros + dir * AVANCE + Vector2(retrait / 2.0, vue.y * (POUCES_PORTRAIT if portrait else POUCES))
	var gardien = _gardien(g)
	var voulu := 1.0 if gardien != null else 0.0
	_part_gardien += (voulu - _part_gardien) * (1.0 - exp(-CADRE_GARDIEN_CADENCE * dt))
	if gardien != null:
		cible += (partie.position_dessin(gardien) - heros) * CADRE_GARDIEN * _part_gardien
	# Le cadrage du duel ne pousse jamais le héros sous les boutons.
	if retrait > 0.0:
		cible.x = maxf(cible.x, heros.x - vue.x / (2.0 * _zoom) + retrait + MARGE_HEROS)
	_zoom_base = 1.0 + (ZOOM_GARDIEN - 1.0) * _part_gardien
	return cible

## La salle reste cadrée ; si elle est plus petite que la vue, on la centre.
func _borner(g: Dictionary, cible: Vector2) -> Vector2:
	var room: Dictionary = g.room
	var demi := vue / (2.0 * _zoom)
	var retrait := _retrait()
	var portrait := vue.y > vue.x
	if room.w + 2.0 * MARGE_COTE + retrait <= 2.0 * demi.x:
		cible.x = (room.w + retrait) / 2.0
	else:
		cible.x = clampf(cible.x, demi.x - MARGE_COTE, room.w + MARGE_COTE + retrait - demi.x)
	# Sous la salle, la caméra peut montrer du mur : c'est là que les pouces couvrent l'écran.
	var bas := MARGE_BAS + vue.y * (BANDE_POUCES_PORTRAIT if portrait else BANDE_POUCES)
	if room.h + MARGE_HAUT + bas <= 2.0 * demi.y:
		cible.y = room.h / 2.0
	else:
		cible.y = clampf(cible.y, demi.y - MARGE_HAUT, room.h + bas - demi.y)
	return cible

## Bande droite prise par les boutons tactiles, en unités de jeu (paysage seulement).
func _retrait() -> float:
	return retrait_droit / (echelle * _zoom) if vue.x > vue.y else 0.0

func _gardien(g: Dictionary):
	for e in g.enemies:
		if D6Js.truthy(e.get("boss")) and not D6Js.truthy(e.get("dead")):
			return e
	return null

## Tremblement, retour du recul, zoom.
func _animer(dt: float) -> void:
	_temps += dt
	_trauma = maxf(0.0, _trauma - TRAUMA_PERTE * dt)
	var s := _trauma * _trauma
	var t := _temps * SECOUSSE_CADENCE
	_secousse = Vector2(_bruit(t, 1.0), _bruit(t, 7.0)) * SECOUSSE_MAX * s
	_roulis = ROTATION_MAX * s * _bruit(t, 13.0)
	_recul *= exp(-RECUL_RETOUR * dt)
	_zoom += (_zoom_cible * _zoom_base - _zoom) * (1.0 - exp(-ZOOM_CADENCE * dt))
	_zoom_cible += (1.0 - _zoom_cible) * (1.0 - exp(-ZOOM_CADENCE * 0.6 * dt))

## Bruit pseudo-continu bon marché (somme de sinus) : pas d'aléa image par image.
func _bruit(t: float, graine: float) -> float:
	return sin(t + graine) * 0.5 + sin(t * 2.3 + graine * 1.7) * 0.3 + sin(t * 4.1 + graine * 2.9) * 0.2
