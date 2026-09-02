# brick_collision_strict.test.gd — ligne physics.brick_collision. Au contact : UNE brique
# detruite, rebond STRICT selon la face (inversion exacte de la composante), pas de double
# contact. Aucune brique -> aucun hit.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Brick = preload("res://05_SYSTEMS/brick_collision/brick_collision.gd")
const BrickField = preload("res://05_SYSTEMS/game_state/brick_field.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

func run(h) -> void:
	var s = State.initial(1)
	var sy: float = s.start_y

	# --- contact par le DESSUS de la brique (0,0) : face horizontale -> inverse vy (strict) ---
	# rect(0,0) : x in [0,64], y in [sy, sy+20]. Balle au centre horizontal, en haut.
	var pos_h := Vector2(P.BRIQUE_LARGEUR / 2.0, sy)
	var vel_h := Vector2(0.0, 120.0)
	var rh: Dictionary = Brick.resoudre(s.bricks, sy, pos_h, vel_h)
	h.eq(rh["hit"], true, "contact dessus -> hit")
	h.eq(rh["index"], BrickField.index(0, 0), "contact dessus -> brique (0,0)")
	h.eq(rh["face"], Brick.FACE_HORIZONTALE, "contact dessus -> face horizontale")
	h.eq(rh["vel"], Vector2(0.0, -120.0), "face horizontale -> vy inverse (strict)")

	# --- contact par le COTE GAUCHE de la brique (0,0) : face verticale -> inverse vx (strict) ---
	var pos_v := Vector2(0.0, sy + P.BRIQUE_HAUTEUR / 2.0)
	var vel_v := Vector2(120.0, 0.0)
	var rv: Dictionary = Brick.resoudre(s.bricks, sy, pos_v, vel_v)
	h.eq(rv["hit"], true, "contact cote -> hit")
	h.eq(rv["face"], Brick.FACE_VERTICALE, "contact cote gauche -> face verticale")
	h.eq(rv["vel"], Vector2(-120.0, 0.0), "face verticale -> vx inverse (strict)")

	# --- aucun contact : balle loin sous le bloc de briques ---
	var loin := Vector2(320.0, P.TERRAIN_HAUTEUR - 1.0)
	var r0: Dictionary = Brick.resoudre(s.bricks, sy, loin, Vector2(0.0, 50.0))
	h.eq(r0["hit"], false, "balle loin -> aucun hit")
	h.eq(r0["index"], -1, "aucun hit -> index -1")
	h.eq(r0["vel"], Vector2(0.0, 50.0), "aucun hit -> vitesse inchangee")

	# --- destruction : le compte decroit de EXACTEMENT 1, la brique disparait ---
	var avant: int = s.briques_restantes
	var ok := BrickField.detruire(s, rh["index"])
	h.eq(ok, true, "detruire l'index touche reussit")
	h.eq(s.briques_restantes, avant - 1, "compte -1 exact apres destruction")
	h.eq(BrickField.est_presente(s, rh["index"]), false, "brique touchee absente apres destruction")
	# re-resoudre au meme endroit ne retouche PAS la brique detruite (pas de contact fantome).
	var r2: Dictionary = Brick.resoudre(s.bricks, sy, pos_h, vel_h)
	h.eq(r2["index"] == BrickField.index(0, 0), false, "brique (0,0) detruite n'est plus touchee")

	# ============================================================================
	# DURCISSEMENT MUTATION — brick_collision.gd : bornes STRICTES du chevauchement
	# (borne <=), de la correction de position selon la FACE (borne ==), et du garde
	# d'index (borne >=). Regles durables, jamais des valeurs figees.
	# ============================================================================
	var rect00 := BrickField.rect(0, 0, sy)   # Rect2(0, sy, BRIQUE_LARGEUR, BRIQUE_HAUTEUR)
	# (borne <=) contact au rayon EXACT depuis le bord gauche -> chevauchement (pas <).
	var pos_bord := Vector2(-P.BALLE_RAYON, sy + P.BRIQUE_HAUTEUR / 2.0)
	h.eq(Brick._chevauche(pos_bord, P.BALLE_RAYON, rect00), true, "distance == rayon -> chevauchement (borne <=)")
	var pos_hors := Vector2(-P.BALLE_RAYON - 1.0, sy + P.BRIQUE_HAUTEUR / 2.0)
	h.eq(Brick._chevauche(pos_hors, P.BALLE_RAYON, rect00), false, "distance > rayon -> pas de chevauchement")
	# (borne == sur la face) verticale -> repousse sur X ; horizontale -> repousse sur Y.
	var pos_face_v := Vector2(P.BALLE_RAYON, sy + P.BRIQUE_HAUTEUR / 2.0)   # a gauche du centre
	h.eq(Brick._corriger(pos_face_v, P.BALLE_RAYON, rect00, Brick.FACE_VERTICALE), Vector2(-P.BALLE_RAYON, sy + P.BRIQUE_HAUTEUR / 2.0), "face verticale -> repousse sur X (gauche)")
	var pos_face_h := Vector2(P.BRIQUE_LARGEUR / 2.0, sy + 2.0)   # au-dessus du centre
	h.eq(Brick._corriger(pos_face_h, P.BALLE_RAYON, rect00, Brick.FACE_HORIZONTALE), Vector2(P.BRIQUE_LARGEUR / 2.0, sy - P.BALLE_RAYON), "face horizontale -> repousse sur Y (haut)")
	# (borne >=) champ de briques plus court que la grille : aucun hit, aucun acces hors borne.
	var court: Array = []
	for _c in range(P.GRILLE_COLONNES):
		court.append(true)   # une seule rangee presente : indices 0..COLONNES-1
	var pos_court := Vector2(P.BRIQUE_LARGEUR / 2.0, sy + P.BRIQUE_HAUTEUR + P.BRIQUE_HAUTEUR / 2.0)  # rangee 1, hors du tableau court
	var rc: Dictionary = Brick.resoudre(court, sy, pos_court, Vector2(0.0, 90.0))
	h.eq(rc["hit"], false, "champ plus court que la grille -> aucun hit (garde idx >= size)")
