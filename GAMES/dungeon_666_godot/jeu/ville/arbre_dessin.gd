extends RefCounted
## Le DESSIN de l'arbre de compétences (jeu/ville/arbre.gd), dans un lot de triangles : tout part
## en UN appel. Ici, seulement des formes et des couleurs de la palette ; qui dessiner, où et dans
## quel état, c'est arbre.gd qui le dit (et lui le lit dans D6Profile.tree_view).
##
## Ce qu'un médaillon dit, sans texte :
##   forme        rond = compétence · losange = passif · écusson = déplacement, ultime
##   « ferme »    l'étage est fermé : éteint, cerné de gris, pictogramme à peine visible
##   « attente »  l'étage est ouvert mais rien à dépenser : cerne clair, pictogramme gris
##   « acquis »   au moins un rang : fond de braise, cerne et pictogramme clairs
##   « achetable » cerné d'OR, il BAT : un halo autour, une lueur dedans (acquis ou non)
##   « max »      tout est en or, plus rien ne bat
##   rangs        compétence : l'anneau, coupé en autant de segments que de rangs ;
##                autres : des pastilles sous la forme
##   choisi       un cercle clair (le blanc du héros) autour

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const Triangles = preload("res://jeu/theme/triangles.gd")
const Icones = preload("res://jeu/interface/icones.gd")
const IconesArbre = preload("res://jeu/ville/icones_arbre.gd")

const ANNEAU := 4.5 # écart entre le médaillon et l'anneau des rangs
const EP_ANNEAU := 3.0
const ECART := 0.2 # rad entre deux segments de rang
const HALO := 7.0 # écart du halo d'un nœud achetable (il tient dans la place du nœud : arbre.gd, RETRAIT)
const CHOISI := 10.5 # écart du cercle du nœud choisi
const ANGULEUX := 0.62 # losange, écusson : leurs pointes vont plus loin, leur tour se tient plus près
const LUEUR := 0.3 # part d'or qui monte dans le fond d'un nœud achetable, au sommet du battement
const PASTILLE := 2.6 # rayon d'une pastille de rang
const PAS_PASTILLE := 8.0
const FOURCHE := Vector2(0.72, 16.0) # améliorations : écart en x (part du rayon), descente sous le médaillon (px)
const RAYON_CHOIX := 6.0
const TRONC := 3.0
const NOEUD_TRONC := 5.0 # demi-diagonale du losange qui marque l'entrée d'un étage
const BANDE := 0.035 # voile clair d'un étage ouvert
const CADENAS := 4.5 # demi-largeur du cadenas d'un étage fermé

static func or_() -> Color:
	return Couleurs.UI.gold

static func encre(a: float = 1.0) -> Color:
	return Color(Couleurs.UI.ink, a)

static func gris(a: float = 1.0) -> Color:
	return Color(Couleurs.UI.ink_dim, a)

# ---------------------------------------------------------------- étages, tronc, branches

## La bande d'un étage (ouvert : un voile clair), sur toute la largeur.
static func bande(lot: Triangles, r: Rect2, ouvert: bool) -> void:
	lot.rect(r, Color(1.0, 1.0, 1.0, BANDE if ouvert else BANDE * 0.3))
	lot.rect(Rect2(r.position, Vector2(r.size.x, 1.0)), Color(Couleurs.UI.ink, 0.1 if ouvert else 0.05))

## Un morceau du tronc, de `haut` à `bas` : en or jusqu'à la part `plein` (0..1), éteint ensuite.
static func tronc(lot: Triangles, haut: Vector2, bas: Vector2, plein: float) -> void:
	var milieu := haut.lerp(bas, clampf(plein, 0.0, 1.0))
	if plein < 1.0:
		lot.ligne(milieu, bas, gris(0.3), TRONC)
	if plein > 0.0:
		lot.ligne(haut, milieu, Color(or_(), 0.7), TRONC)

## La branche d'une rangée : un trait du tronc à ses nœuds, et le losange d'entrée sur le tronc.
static func branche(lot: Triangles, gauche: Vector2, droite: Vector2, ouvert: bool) -> void:
	lot.ligne(gauche, droite, Color(or_(), 0.45) if ouvert else gris(0.25), 2.0)

static func entree(lot: Triangles, c: Vector2, ouvert: bool) -> void:
	var d := NOEUD_TRONC
	var pts := PackedVector2Array([Vector2(0, -d), Vector2(d, 0), Vector2(0, d), Vector2(-d, 0)])
	lot.polygone(pts, Couleurs.UI["void"], Transform2D(0.0, Vector2(1.5, 1.5), 0.0, c))
	lot.polygone(pts, or_() if ouvert else gris(0.6), Transform2D(0.0, c))

## Le cadenas d'un étage fermé (devant son nom).
static func cadenas(lot: Triangles, c: Vector2) -> void:
	var d := CADENAS
	lot.arc(c + Vector2(0.0, -d * 0.4), d * 0.62, PI, TAU, 10, gris(0.9), 1.6)
	lot.rect(Rect2(c.x - d, c.y - d * 0.4, 2.0 * d, d * 1.5), gris(0.9))

# ---------------------------------------------------------------- un médaillon

## `d` : {sorte, icone, etat, acquis, rang, rangs, choisi, survol} ; `pouls` : 0..1, le battement.
static func medaillon(lot: Triangles, c: Vector2, r: float, d: Dictionary, pouls: float) -> void:
	var etat: String = d.etat
	var forme: PackedVector2Array = IconesArbre.forme(d.sorte, r)
	var pres := 1.0 if forme.is_empty() else ANGULEUX
	if d.get("choisi", false):
		_tour(lot, c, r + CHOISI * pres, d.sorte, Color(Couleurs.PAL.hero, 0.95), 2.0)
	if etat == "achetable":
		_tour(lot, c, r + HALO * pres, d.sorte, Color(or_(), 0.2 + 0.7 * pouls), 2.2)
	var fond: Color = Couleurs.UI.panel.lerp(Couleurs.UI.ember, 0.3) if d.acquis else Color(Couleurs.PAL.floorB, 1.0)
	if etat == "achetable":
		fond = fond.lerp(or_(), LUEUR * pouls)
	if d.get("survol", false):
		fond = fond.lightened(0.12)
	var bord := _bord(etat, d.acquis)
	if forme.is_empty():
		lot.disque(c, r, Color(fond, 1.0))
		lot.arc(c, r, 0.0, TAU, 40, bord, 3.0 if etat == "max" else 2.0)
		_anneau(lot, c, r + ANNEAU, int(d.rang), int(d.rangs), etat == "ferme")
	else:
		var place := Transform2D(0.0, c)
		lot.polygone(forme, Color(fond, 1.0), place)
		lot.contour(forme, bord, 3.0 if etat == "max" else 2.0, true, place)
		_pastilles(lot, c + Vector2(0.0, _bas(forme) + PASTILLE + 4.0), int(d.rang), int(d.rangs), etat == "ferme")
	_picto(lot, c, r, d)

## Le point le plus bas d'une forme (les pastilles de rang se posent dessous).
static func _bas(forme: PackedVector2Array) -> float:
	var bas := 0.0
	for p in forme:
		bas = maxf(bas, p.y)
	return bas

## Cerne du médaillon selon l'état.
static func _bord(etat: String, acquis: bool) -> Color:
	match etat:
		"max", "achetable":
			return or_()
		"ferme":
			return gris(0.75) if acquis else gris(0.35)
		"acquis":
			return encre(0.92)
	return encre(0.5)

static func _picto(lot: Triangles, c: Vector2, r: float, d: Dictionary) -> void:
	var col := encre(0.95)
	match d.etat:
		"max":
			col = or_()
		"ferme":
			col = gris(0.75) if d.acquis else gris(0.4)
		"attente":
			col = gris(0.9)
		"achetable":
			col = encre(0.95) if d.acquis else encre(0.8)
	var nom: String = d.icone
	if Icones.connue(nom):
		Icones.ajouter(lot, nom, c, r * 1.1, col)
	else:
		IconesArbre.ajouter(lot, nom, c, r * 1.15, col)

## Un tour autour du médaillon, à sa forme (cercle, losange, écusson).
static func _tour(lot: Triangles, c: Vector2, r: float, sorte: String, col: Color, ep: float) -> void:
	var forme: PackedVector2Array = IconesArbre.forme(sorte, r)
	if forme.is_empty():
		lot.arc(c, r, 0.0, TAU, 40, col, ep)
	else:
		lot.contour(forme, col, ep, false, Transform2D(0.0, c))

## L'anneau des rangs d'une compétence : un segment par rang, en or s'il est pris.
static func _anneau(lot: Triangles, c: Vector2, rr: float, rang: int, rangs: int, ferme: bool) -> void:
	if rangs <= 0:
		return
	var seg := TAU / rangs
	var ecart := ECART if rangs > 1 else 0.0
	for i in rangs:
		var a0 := -PI / 2.0 + i * seg + ecart / 2.0
		var col := (gris(0.7) if ferme else or_()) if i < rang else encre(0.16)
		lot.arc(c, rr, a0, a0 + seg - ecart, 12, col, EP_ANNEAU)

## Les pastilles de rang d'un passif, d'un déplacement, d'un ultime : en rangée, sous la forme.
static func _pastilles(lot: Triangles, c: Vector2, rang: int, rangs: int, ferme: bool) -> void:
	var x0 := -(rangs - 1) * PAS_PASTILLE / 2.0
	for i in rangs:
		var p := c + Vector2(x0 + i * PAS_PASTILLE, 0.0)
		if i < rang:
			lot.disque(p, PASTILLE, gris(0.7) if ferme else or_())
		else:
			lot.arc(p, PASTILLE, 0.0, TAU, 10, encre(0.3), 1.2)

# ---------------------------------------------------------------- améliorations exclusives

## Où pendent les deux améliorations d'un médaillon centré en `c`.
static func places_des_choix(c: Vector2, r: float, nombre: int) -> Array:
	var places: Array = []
	for i in nombre:
		var cote := (i - (nombre - 1) / 2.0) * 2.0
		places.append(c + Vector2(cote * r * FOURCHE.x, r + FOURCHE.y))
	return places

## La fourche : un trait par amélioration, et son petit nœud. `etats` : pour chacune, « attente »
## (pas encore offerte), « offerte » (elle bat), « prise » (pleine, en or), « barree » (l'autre est prise).
static func fourche(lot: Triangles, c: Vector2, r: float, etats: Array, pouls: float) -> void:
	var places := places_des_choix(c, r, etats.size())
	for i in etats.size():
		var p: Vector2 = places[i]
		var depart := c + (p - c).normalized() * (r + ANNEAU + EP_ANNEAU)
		var etat: String = etats[i]
		lot.ligne(depart, p, or_() if etat == "prise" else (Color(or_(), 0.6) if etat == "offerte" else gris(0.4)), 1.6)
		_choix(lot, p, etat, pouls)

static func _choix(lot: Triangles, p: Vector2, etat: String, pouls: float) -> void:
	var rc := RAYON_CHOIX
	lot.disque(p, rc, Color(Couleurs.PAL.floorB, 1.0))
	match etat:
		"prise":
			lot.disque(p, rc, or_())
			lot.disque(p, rc * 0.4, Couleurs.UI["void"])
		"offerte":
			lot.arc(p, rc + 3.5, 0.0, TAU, 16, Color(or_(), 0.2 + 0.6 * pouls), 2.0)
			lot.arc(p, rc, 0.0, TAU, 16, or_(), 1.8)
		"barree":
			lot.arc(p, rc, 0.0, TAU, 16, gris(0.45), 1.4)
			lot.ligne(p + Vector2(-rc, rc) * 0.9, p + Vector2(rc, -rc) * 0.9, gris(0.8), 1.6)
		_:
			lot.arc(p, rc, 0.0, TAU, 16, gris(0.55), 1.4)

## La pastille « emplacement N » d'une compétence placée (le chiffre est une étiquette, posée par-dessus).
static func emplacement(lot: Triangles, c: Vector2, rayon: float) -> void:
	lot.disque(c, rayon + 1.5, Couleurs.UI["void"])
	lot.disque(c, rayon, Couleurs.PAL.heroCape.darkened(0.25))
