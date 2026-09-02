# maze_view.gd — rendu du labyrinthe et des entites par PRIMITIVES DU MOTEUR
# (ligne render.maze_and_entities). ZERO asset importe : aucune image, aucune texture,
# aucune police, aucun son. Lit l'etat, ne le modifie jamais, ne consulte aucun systeme
# de regles.
#
# V3 — DEUX causes racines corrigees ici.
#
# P4, ENVELOPPE : la taille de case etait une CONSTANTE (20). La carte de reference
# (28x36) remplissait donc exactement la fenetre, et toute autre carte (21x24) occupait
# un coin. La taille de case DERIVE desormais de la carte ET de l'enveloppe, et la carte
# est CENTREE : la propriete vaut pour N cartes, pas pour deux.
#
# P2, IDENTITE VISUELLE : le rendu etait fait d'aplats pleins — un rectangle par case, un
# disque par entite. Aucun fichier n'est autorise a entrer (charter_v2.hors_scope[10],
# invariant zero asset), donc l'identite est PROCEDURALE : murs a arete et creux, joueur
# a bouche animee et orientee, fantomes a silhouette (dome, jupe festonnee, yeux qui
# suivent la direction), collectibles a halo et super-pastille pulsante, clignotement de
# fin d'effroi. Toutes ces grandeurs sont DETERMINISTES : elles derivent du tick de
# l'etat, jamais d'une horloge de plateforme ni d'un alea.
#
# Aucune couleur n'est declaree ici : toutes viennent du descripteur de palette unique.
extends RefCounted

const Maze = preload("res://05_SYSTEMS/maze/maze.gd")
const Pellets = preload("res://05_SYSTEMS/pellets/pellets.gd")
const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const Palette = preload("res://06_RUNTIME/adapters/palette/palette.gd")

# --- GEOMETRIE ---------------------------------------------------------------------
# COTE_CASE est la taille de case de la carte DE REFERENCE : c'est elle qui DEFINIT
# l'enveloppe (la fenetre), pas la taille a laquelle une carte quelconque est dessinee.
# Les deux roles etaient confondus avant V3, et c'etait exactement le defaut P4.
const COTE_CASE: int = 20
const COTE_CASE_MIN: int = 1

const RAYON_PASTILLE: float = 2.0
const RAYON_SUPER: float = 6.0
const RAYON_PACMAN: float = 8.0
const RAYON_FANTOME: float = 8.0

# --- ANIMATION (deterministe, derivee du tick de l'etat) ---------------------------
# Periode de la bouche, en ticks. Valeur de PRESENTATION, jamais un reglage de jeu.
const PERIODE_BOUCHE: int = 8
const OUVERTURE_BOUCHE_MAX: float = 0.9
# Periode du battement des collectibles majeurs.
const PERIODE_PULSATION: int = 12
const AMPLITUDE_PULSATION: float = 0.25
# Sous ce reste d'effroi, les fantomes CLIGNOTENT : la reprise s'annonce visuellement.
const SEUIL_CLIGNOTEMENT: int = 40
const PERIODE_CLIGNOTEMENT: int = 6

# --- FORME DES MURS ----------------------------------------------------------------
# Part du cote consacree a l'arete du mur. Un mur devient un TRACE (arete claire, creux
# sombre) au lieu d'un aplat : c'est ce qui distingue un labyrinthe dessine d'une grille.
const PART_ARETE: float = 0.18
# Part du cote consacree au festonnage de la jupe des fantomes.
const DENTS_FANTOME: int = 3
# Part du rayon occupee par l'oeil, et decalage de la pupille dans la direction du regard.
const PART_OEIL: float = 0.30
const PART_PUPILLE: float = 0.15
const PART_ECART_YEUX: float = 0.38
const PART_HAUTEUR_YEUX: float = 0.22
# Rayon du halo, en multiples du rayon de l'objet, et son opacite.
const FACTEUR_LUEUR: float = 2.2
const OPACITE_LUEUR: float = 0.16

# V2/V3 : AUCUN litteral de couleur ici. Toutes les couleurs viennent du DESCRIPTEUR DE
# PALETTE UNIQUE — changer l identite visuelle n ouvre donc que palette.gd.
const COULEUR_MUR := Palette.MUR
const COULEUR_MUR_ARETE := Palette.MUR_ARETE
const COULEUR_MUR_CREUX := Palette.MUR_CREUX
const COULEUR_COULOIR := Palette.COULOIR
const COULEUR_MAISON := Palette.MAISON
const COULEUR_TUNNEL := Palette.TUNNEL
const COULEUR_HORS_JEU := Palette.HORS_JEU
const COULEUR_PASTILLE := Palette.PASTILLE
const COULEUR_SUPER := Palette.SUPER_PASTILLE
const COULEUR_LUEUR := Palette.LUEUR
const COULEUR_PACMAN := Palette.PACMAN
const COULEUR_EFFRAYE := Palette.FANTOME_EFFRAYE
const COULEUR_EFFRAYE_FIN := Palette.FANTOME_EFFRAYE_FIN
const COULEUR_OEIL := Palette.FANTOME_OEIL
const COULEUR_PUPILLE := Palette.FANTOME_PUPILLE
const COULEURS_FANTOMES: Array = Palette.FANTOMES


static func couleur_case(type: int) -> Color:
	if type == Maze.Type.MUR:
		return COULEUR_MUR
	if type == Maze.Type.MAISON:
		return COULEUR_MAISON
	if type == Maze.Type.TUNNEL:
		return COULEUR_TUNNEL
	return COULEUR_COULOIR


static func couleur_fantome(index: int, mode: int) -> Color:
	if mode == Chase.Mode.EFFRAYE:
		return COULEUR_EFFRAYE
	return COULEURS_FANTOMES[index]


# COULEUR ANIMEE d'un fantome : identique a la precedente, sauf en fin d'effroi ou la
# teinte ALTERNE. Le clignotement est la seule information qui dit « ca va reprendre ».
static func couleur_fantome_animee(index: int, mode: int, restant: int, tick: int) -> Color:
	if mode != Chase.Mode.EFFRAYE:
		return COULEURS_FANTOMES[index]
	if restant > SEUIL_CLIGNOTEMENT:
		return COULEUR_EFFRAYE
	if clignote(tick):
		return COULEUR_EFFRAYE_FIN
	return COULEUR_EFFRAYE


static func clignote(tick: int) -> bool:
	return (posmod(tick, PERIODE_CLIGNOTEMENT * 2)) < PERIODE_CLIGNOTEMENT


# Rayon d'un collectible : la super-pastille est VISIBLEMENT plus grande.
static func rayon_collectible(contenu: int) -> float:
	if contenu == Pellets.Contenu.SUPER:
		return RAYON_SUPER
	return RAYON_PASTILLE


static func couleur_collectible(contenu: int) -> Color:
	if contenu == Pellets.Contenu.SUPER:
		return COULEUR_SUPER
	return COULEUR_PASTILLE


# --- PULSATION ---------------------------------------------------------------------
# Facteur de battement au tick donne : une sinusoide echantillonnee sur PERIODE_PULSATION
# ticks. Fonction PURE du tick — deux lectures du meme tick rendent la meme valeur.
static func facteur_pulsation(tick: int) -> float:
	var phase: float = float(posmod(tick, PERIODE_PULSATION)) / float(PERIODE_PULSATION)
	return 1.0 + AMPLITUDE_PULSATION * sin(TAU * phase)


# Rayon ANIME d'un collectible. Seule la super-pastille bat : une pastille ordinaire qui
# respirerait rendrait le labyrinthe illisible.
static func rayon_collectible_anime(contenu: int, tick: int, cote: int) -> float:
	var base: float = rayon_collectible(contenu) * echelle(cote)
	if contenu == Pellets.Contenu.SUPER:
		return base * facteur_pulsation(tick)
	return base


# --- BOUCHE DU JOUEUR --------------------------------------------------------------
# Demi-angle d'ouverture de la bouche au tick donne : ouverte, puis fermee, en boucle.
# La valeur PARCOURT son intervalle — une bouche a valeur constante serait un disque, et
# la mesure de variance le verrait (regle ratifiee Pierre 2026-07-21).
static func ouverture_bouche(tick: int) -> float:
	var phase: float = float(posmod(tick, PERIODE_BOUCHE)) / float(PERIODE_BOUCHE)
	return OUVERTURE_BOUCHE_MAX * absf(sin(PI * phase))


# ANGLE DU REGARD : quatre directions cardinales, quatre angles DEUX A DEUX DIFFERENTS.
# Une direction nulle regarde a droite — valeur declaree, jamais un angle indefini.
static func angle_regard(direction: Vector2i) -> float:
	if direction == Maze.HAUT:
		return -PI / 2.0
	if direction == Maze.BAS:
		return PI / 2.0
	if direction == Maze.GAUCHE:
		return PI
	return 0.0


# SILHOUETTE DU JOUEUR : un secteur circulaire dont l'echancrure suit la direction et
# s'ouvre au rythme du tick. C'est cette forme, et non un disque, qui fait lire « le
# joueur » sans legende.
static func polygone_pacman(centre: Vector2, rayon: float, direction: Vector2i, tick: int) -> PackedVector2Array:
	var ouverture: float = ouverture_bouche(tick)
	var axe: float = angle_regard(direction)
	var pts := PackedVector2Array()
	pts.append(centre)
	var segments: int = 20
	var debut: float = axe + ouverture
	var fin: float = axe + TAU - ouverture
	for i in range(segments + 1):
		var a: float = debut + (fin - debut) * float(i) / float(segments)
		pts.append(centre + Vector2(cos(a), sin(a)) * rayon)
	return pts


# SILHOUETTE D'UN FANTOME : dome superieur, flancs droits, jupe FESTONNEE. Le feston est
# ce qui distingue un fantome d'un disque, et il ne coute aucun fichier.
static func polygone_fantome(centre: Vector2, rayon: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var segments: int = 16
	# Dome : demi-cercle superieur, de gauche a droite.
	for i in range(segments + 1):
		var a: float = PI + PI * float(i) / float(segments)
		pts.append(centre + Vector2(cos(a), sin(a)) * rayon)
	# Flanc droit puis jupe festonnee, de droite a gauche.
	var bas: float = centre.y + rayon
	var pas: float = (2.0 * rayon) / float(DENTS_FANTOME * 2)
	for i in range(DENTS_FANTOME * 2 + 1):
		var x: float = centre.x + rayon - pas * float(i)
		var y: float = bas if (i % 2) == 0 else bas - rayon * 0.4
		pts.append(Vector2(x, y))
	return pts


# YEUX d'un fantome : deux disques blancs et deux pupilles DECALEES dans la direction du
# regard. Sans eux la silhouette existe mais ne regarde nulle part.
static func centres_yeux(centre: Vector2, rayon: float) -> Array:
	var dx: float = rayon * PART_ECART_YEUX
	var dy: float = rayon * PART_HAUTEUR_YEUX
	return [centre + Vector2(-dx, -dy), centre + Vector2(dx, -dy)]


static func decalage_pupille(direction: Vector2i, rayon: float) -> Vector2:
	return Vector2(direction.x, direction.y) * (rayon * PART_PUPILLE)


# --- ENVELOPPE ET CENTRAGE (cause racine P4) ---------------------------------------
# L'enveloppe est la surface OFFERTE a toutes les cartes. Elle est definie par la carte
# de reference a sa taille de case de reference : la fenetre du jeu ne change donc pas,
# et c'est bien la CARTE qui s'adapte a la fenetre, jamais l'inverse.
static func largeur_enveloppe(carte_reference) -> int:
	return carte_reference.LARGEUR * COTE_CASE


static func hauteur_enveloppe(carte_reference) -> int:
	return carte_reference.HAUTEUR * COTE_CASE


# TAILLE DE CASE d'une carte dans une enveloppe donnee : la plus grande valeur ENTIERE
# qui fait tenir la grille entiere dans les deux dimensions. Entiere pour que les cases
# restent alignees au pixel ; au moins COTE_CASE_MIN pour qu'une carte demesuree reste
# dessinee au lieu de disparaitre.
static func cote_case(carte, largeur_env: int, hauteur_env: int) -> int:
	if carte.LARGEUR <= 0 or carte.HAUTEUR <= 0:
		return COTE_CASE_MIN
	var par_largeur: int = largeur_env / carte.LARGEUR
	var par_hauteur: int = hauteur_env / carte.HAUTEUR
	var c: int = par_largeur if par_largeur < par_hauteur else par_hauteur
	if c < COTE_CASE_MIN:
		return COTE_CASE_MIN
	return c


# ORIGINE du dessin : la marge restante est PARTAGEE entre les deux bords. La carte est
# donc centree, et non ancree en haut a gauche comme avant V3.
static func origine(carte, largeur_env: int, hauteur_env: int) -> Vector2:
	var c: int = cote_case(carte, largeur_env, hauteur_env)
	var reste_x: int = largeur_env - carte.LARGEUR * c
	var reste_y: int = hauteur_env - carte.HAUTEUR * c
	return Vector2(float(reste_x) / 2.0, float(reste_y) / 2.0)


# Debordement de la carte hors de l'enveloppe, en pixels, sur chaque axe. La valeur
# attendue vaut exactement 0 pour toute carte : c'est LA propriete d'enveloppe.
static func debordement(carte, largeur_env: int, hauteur_env: int) -> Vector2i:
	var c: int = cote_case(carte, largeur_env, hauteur_env)
	var dx: int = carte.LARGEUR * c - largeur_env
	var dy: int = carte.HAUTEUR * c - hauteur_env
	return Vector2i(maxi(dx, 0), maxi(dy, 0))


# ECHELLE des rayons d'entites, rapportee a la taille de case de reference : sur une
# carte dessinee en cases plus grandes, le joueur grandit avec elle.
static func echelle(cote: int) -> float:
	return float(cote) / float(COTE_CASE)


# --- REPERES ------------------------------------------------------------------------
static func rect_case_dans(p: Vector2i, cote: int, orig: Vector2) -> Rect2:
	return Rect2(orig.x + p.x * cote, orig.y + p.y * cote, cote, cote)


static func centre_case_dans(p: Vector2i, cote: int, orig: Vector2) -> Vector2:
	return Vector2(orig.x + p.x * cote + cote / 2.0, orig.y + p.y * cote + cote / 2.0)


# REPERE DE REFERENCE (taille de case de reference, origine nulle) : la meme mesure, lue
# dans le cadre qui definit l'enveloppe. Une seule implementation, deux cadres.
static func centre_case(p: Vector2i) -> Vector2:
	return centre_case_dans(p, COTE_CASE, Vector2.ZERO)


static func rect_case(p: Vector2i) -> Rect2:
	return rect_case_dans(p, COTE_CASE, Vector2.ZERO)


static func largeur_pixels(carte) -> int:
	return carte.LARGEUR * COTE_CASE


static func hauteur_pixels(carte) -> int:
	return carte.HAUTEUR * COTE_CASE


# Les quatre couleurs de fantomes sont-elles deux a deux differentes ?
static func couleurs_distinctes() -> bool:
	for i in range(COULEURS_FANTOMES.size()):
		for j in range(i + 1, COULEURS_FANTOMES.size()):
			if COULEURS_FANTOMES[i] == COULEURS_FANTOMES[j]:
				return false
	return true


# --- DESSIN --------------------------------------------------------------------------
# Un MUR en relief : creux plein, puis arete claire au bord interieur. Deux primitives,
# aucune texture. L'epaisseur de l'arete suit la taille de case.
static func dessiner_mur(toile: CanvasItem, r: Rect2, cote: int) -> void:
	var e: float = maxf(1.0, float(cote) * PART_ARETE)
	toile.draw_rect(r, COULEUR_MUR_CREUX)
	toile.draw_rect(r, COULEUR_MUR_ARETE, false, e)


static func dessiner_halo(toile: CanvasItem, centre: Vector2, rayon: float) -> void:
	var c: Color = COULEUR_LUEUR
	c.a = OPACITE_LUEUR
	toile.draw_circle(centre, rayon * FACTEUR_LUEUR, c)


static func dessiner_fantome(toile: CanvasItem, centre: Vector2, rayon: float,
		couleur: Color, direction: Vector2i) -> void:
	toile.draw_colored_polygon(polygone_fantome(centre, rayon), couleur)
	var r_oeil: float = rayon * PART_OEIL
	var d: Vector2 = decalage_pupille(direction, rayon)
	for oeil in centres_yeux(centre, rayon):
		toile.draw_circle(oeil, r_oeil, COULEUR_OEIL)
		toile.draw_circle(oeil + d, r_oeil * 0.5, COULEUR_PUPILLE)


# Dessine la scene entiere sur un CanvasItem, DANS L'ENVELOPPE remise en argument.
# Aucune regle de jeu ici : uniquement la lecture de l'etat deja tenu.
static func dessiner(toile: CanvasItem, s, largeur_env: int, hauteur_env: int) -> void:
	var cote: int = cote_case(s.carte, largeur_env, hauteur_env)
	var orig: Vector2 = origine(s.carte, largeur_env, hauteur_env)
	var ech: float = echelle(cote)
	# Fond HORS-JEU : la marge de centrage se lit comme un hors-champ, pas comme un couloir.
	toile.draw_rect(Rect2(0, 0, largeur_env, hauteur_env), COULEUR_HORS_JEU)
	for y in range(s.carte.HAUTEUR):
		for x in range(s.carte.LARGEUR):
			var p := Vector2i(x, y)
			var t: int = s.carte.type_case(p)
			var r: Rect2 = rect_case_dans(p, cote, orig)
			if t == Maze.Type.MUR:
				dessiner_mur(toile, r, cote)
			else:
				toile.draw_rect(r, couleur_case(t))
	for i in range(s.pastilles.size()):
		var contenu: int = s.pastilles[i]
		if contenu == Pellets.Contenu.VIDE:
			continue
		var centre: Vector2 = centre_case_dans(s.carte.case_de(i), cote, orig)
		var rayon: float = rayon_collectible_anime(contenu, s.ticks, cote)
		if contenu == Pellets.Contenu.SUPER:
			dessiner_halo(toile, centre, rayon)
		toile.draw_circle(centre, rayon, couleur_collectible(contenu))
	for g in range(s.fantomes.size()):
		var dir_g: Vector2i = s.dirs_fantomes[g] if g < s.dirs_fantomes.size() else Maze.AUCUNE
		dessiner_fantome(
			toile,
			centre_case_dans(s.fantomes[g], cote, orig),
			RAYON_FANTOME * ech,
			couleur_fantome_animee(g, s.etats_fantomes[g], s.effraye_restant, s.ticks),
			dir_g)
	var centre_pac: Vector2 = centre_case_dans(s.pac, cote, orig)
	var rayon_pac: float = RAYON_PACMAN * ech
	dessiner_halo(toile, centre_pac, rayon_pac)
	toile.draw_colored_polygon(
		polygone_pacman(centre_pac, rayon_pac, s.pac_dir, s.ticks), COULEUR_PACMAN)
