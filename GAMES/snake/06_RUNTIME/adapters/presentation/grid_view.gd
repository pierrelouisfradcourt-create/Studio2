# grid_view.gd — lignes core.render + render.grid. Projection VISUELLE de l'etat vers une
# grille de categories (mur, tete, corps, nourriture, vide) et une table de couleurs
# DISTINCTES par categorie. La categorisation est PURE et testable en headless ; le rendu
# reel (Node2D / _draw) est fait par le pilote de scene qui lit cette projection. Les
# couleurs sont des valeurs de PRESENTATION (pas du gameplay) : elles vivent legitimement
# ici, hors du bloc params (params n'isole que les litteraux de GAMEPLAY). RefCounted.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")

# Categories visuelles exclusives. VIDE = case jouable libre ; MUR = cadre hors grille.
enum Cat { VIDE, MUR, TETE, CORPS, NOURRITURE }

# Les 4 categories de GAMEPLAY dont l'oracle exige des couleurs distinctes.
const CATEGORIES_JOUABLES := [Cat.MUR, Cat.TETE, Cat.CORPS, Cat.NOURRITURE]

# Couleur par categorie. Distinctes deux a deux (verifie par couleurs_distinctes()).
const COULEURS := {
	Cat.VIDE: Color(0.10, 0.11, 0.13),
	Cat.MUR: Color(0.44, 0.46, 0.51),
	Cat.TETE: Color(0.19, 0.91, 0.34),
	Cat.CORPS: Color(0.13, 0.61, 0.24),
	Cat.NOURRITURE: Color(0.93, 0.27, 0.29),
}

# Categorie d'une cellule du plan etendu (le cadre hors [0, TAILLE_GRILLE) = MUR).
static func categorie_cellule(state, cellule: Vector2i) -> int:
	if cellule.x < 0 or cellule.x >= P.TAILLE_GRILLE or cellule.y < 0 or cellule.y >= P.TAILLE_GRILLE:
		return Cat.MUR
	if cellule == state.segments[0]:
		return Cat.TETE
	if cellule in state.segments:
		return Cat.CORPS
	if cellule == state.nourriture:
		return Cat.NOURRITURE
	return Cat.VIDE

# Couleur de rendu d'une categorie.
static func couleur(categorie: int) -> Color:
	return COULEURS[categorie]

# Nombre de PAIRES de categories de gameplay partageant EXACTEMENT la meme couleur.
# L'oracle exige 0 : les 4 categories doivent etre visuellement discernables.
static func categories_couleur_partagee() -> int:
	var partages := 0
	for i in range(CATEGORIES_JOUABLES.size()):
		for j in range(i + 1, CATEGORIES_JOUABLES.size()):
			if COULEURS[CATEGORIES_JOUABLES[i]] == COULEURS[CATEGORIES_JOUABLES[j]]:
				partages += 1
	return partages
