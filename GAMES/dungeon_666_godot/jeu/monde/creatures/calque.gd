extends Node2D
## Base d'un calque de créatures (sol, ennemis, héros, statuts) : un Node2D qui se redessine à
## chaque image en LISANT la partie. Aucun calque ne modifie la simulation.

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const Pinceau = preload("res://jeu/monde/creatures/pinceau.gd")
const PAL: Dictionary = Couleurs.PAL
const HEROS_VISUEL := 1.18 # le héros est dessiné un peu plus grand que son cercle de collision
const BOND_HAUTEUR := 46.0 # u : hauteur dessinée du Bond du bourreau

## La racine `Entites` (jeu/monde/entites.gd) : elle porte `partie`, `temps` et la traînée de dash.
var entites: Node2D
var p: Pinceau

func _init() -> void:
	p = Pinceau.new(self)

## Appelé à chaque image par Entites. Par défaut le calque se redessine en entier ; celui des
## ennemis (ennemis.gd) garde ses dessins et ne fait que les déplacer.
func actualiser(_delta: float) -> void:
	queue_redraw()

## L'état de la simulation, ou null hors partie.
func jeu():
	if entites == null or entites.partie == null:
		return null
	return entites.partie.game

func temps() -> float:
	return entites.temps

func lieu(e: Dictionary) -> Vector2:
	return entites.partie.position_dessin(e)

func lieu_heros(g: Dictionary) -> Vector2:
	return entites.partie.position_dessin(g.player, true)

func vivants(g: Dictionary) -> Array:
	return g.enemies.filter(func(e): return not D6Js.truthy(e.get("dead")))

## Nombre lu dans un champ que la simulation ne pose pas à la naissance (`e.exposed ?? 0`).
static func nombre(e: Dictionary, cle: String) -> float:
	var v = e.get(cle)
	return float(v) if v is float or v is int else 0.0

## Opacité du héros : il s'efface à sa mort, clignote tant qu'il est invulnérable après un coup.
func alpha_heros(h: Dictionary) -> float:
	if h.state == "dead":
		return maxf(0.0, 1.0 - h.stateTime)
	if h.iframes > 0.0 and h.state != "dash" and h.hurtFlash <= 0.0 and int(temps() * 15.0) % 2 == 0:
		return 0.4
	return 1.0

## Part du Bond déjà sautée, en cloche (0 au sol, 1 au sommet) ; 0 hors Bond.
func envol_heros(g: Dictionary) -> float:
	var h: Dictionary = g.player
	var lance = h.get("cast")
	if h.state != "cast" or not (lance is Dictionary) or lance.get("kind") != "bond":
		return 0.0
	var sort = D6Loadout.cast_def(g)
	var duree: float = maxf(1e-3, nombre(sort, "leapTime") if sort is Dictionary else 0.0)
	return sin(PI * clampf(1.0 - h.castT / duree, 0.0, 1.0))

## Hauteur relative d'un Gardien en plein bond (Cerbère) : 0 au sol, 1 au sommet.
static func envol(e: Dictionary) -> float:
	if not D6Js.truthy(e.get("airborne")):
		return 0.0
	return sin(PI * clampf(nombre(e, "leapK"), 0.0, 1.0))
