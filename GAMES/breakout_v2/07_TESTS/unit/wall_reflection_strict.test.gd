# wall_reflection_strict.test.gd — ligne physics.wall_reflection. Detection de face et
# INVERSION STRICTE de la composante perpendiculaire (valeurs exactes, aucun epsilon). La
# limite BASSE n'est jamais un mur.
extends RefCounted

const Wall = preload("res://05_SYSTEMS/wall_collision/wall_reflection.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

func run(h) -> void:
	var r := P.BALLE_RAYON

	# --- detection de face (une seule, direction de vitesse prise en compte) ---
	h.eq(Wall.face_touchee(Vector2(r, 100.0), Vector2(-5.0, 3.0)), Wall.GAUCHE, "bord gauche + vx<0 -> GAUCHE")
	h.eq(Wall.face_touchee(Vector2(r, 100.0), Vector2(5.0, 3.0)), Wall.AUCUN, "bord gauche mais vx>0 -> AUCUN")
	h.eq(Wall.face_touchee(Vector2(P.TERRAIN_LARGEUR - r, 100.0), Vector2(5.0, 3.0)), Wall.DROITE, "bord droit + vx>0 -> DROITE")
	h.eq(Wall.face_touchee(Vector2(100.0, r), Vector2(3.0, -5.0)), Wall.PLAFOND, "plafond + vy<0 -> PLAFOND")
	h.eq(Wall.face_touchee(Vector2(320.0, 240.0), Vector2(5.0, 5.0)), Wall.AUCUN, "interieur -> AUCUN")
	# la limite BASSE n'est PAS un mur (aucune face meme en descendant sous le terrain).
	h.eq(Wall.face_touchee(Vector2(320.0, P.TERRAIN_HAUTEUR), Vector2(0.0, 5.0)), Wall.AUCUN, "limite basse -> jamais un mur")

	# --- inversion STRICTE de la composante perpendiculaire ---
	h.eq(Wall.reflechir_vitesse(Vector2(5.0, -3.0), Wall.GAUCHE), Vector2(-5.0, -3.0), "GAUCHE inverse vx (strict)")
	h.eq(Wall.reflechir_vitesse(Vector2(-5.0, -3.0), Wall.DROITE), Vector2(5.0, -3.0), "DROITE inverse vx (strict)")
	h.eq(Wall.reflechir_vitesse(Vector2(5.0, -3.0), Wall.PLAFOND), Vector2(5.0, 3.0), "PLAFOND inverse vy (strict)")
	h.eq(Wall.reflechir_vitesse(Vector2(5.0, -3.0), Wall.AUCUN), Vector2(5.0, -3.0), "AUCUN -> vitesse inchangee")

	# --- correction de position : au contact exact du mur, jamais au-dela ---
	h.eq(Wall.corriger_position(Vector2(-2.0, 100.0), Wall.GAUCHE), Vector2(r, 100.0), "GAUCHE -> x = rayon")
	h.eq(Wall.corriger_position(Vector2(700.0, 100.0), Wall.DROITE), Vector2(P.TERRAIN_LARGEUR - r, 100.0), "DROITE -> x = largeur - rayon")
	h.eq(Wall.corriger_position(Vector2(100.0, -2.0), Wall.PLAFOND), Vector2(100.0, r), "PLAFOND -> y = rayon")

	# ============================================================================
	# DURCISSEMENT MUTATION — face_touchee : le PLAFOND exige les DEUX conditions
	# (au plafond ET vy<0), borne AND stricte. Une seule condition vraie -> AUCUN.
	# ============================================================================
	# interieur (pas au plafond) mais montant (vy<0) : AND -> AUCUN (un OR dirait PLAFOND).
	h.eq(Wall.face_touchee(Vector2(P.TERRAIN_LARGEUR / 2.0, P.TERRAIN_HAUTEUR / 2.0), Vector2(0.0, -100.0)), Wall.AUCUN, "interieur en montant -> AUCUN (borne AND, pas OR)")
	# au plafond mais descendant (vy>0) : AND -> AUCUN (un OR dirait PLAFOND).
	h.eq(Wall.face_touchee(Vector2(P.TERRAIN_LARGEUR / 2.0, P.BALLE_RAYON), Vector2(0.0, 100.0)), Wall.AUCUN, "au plafond mais descendant -> AUCUN (borne AND, pas OR)")
