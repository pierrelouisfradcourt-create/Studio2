extends RefCounted
## L'ambiance de chaque Cercle de l'Enfer : la pierre, l'appareil des dalles, la lave. La TEINTE
## (lueurs, flammes, braises) reste celle de la palette (Couleurs.CIRCLE_TINTS) ; ici on règle la
## matière, pour que deux Cercles ne se ressemblent pas. Présentation pure : aucune règle n'en dépend.
##   const Ambiance = preload("res://jeu/monde/ambiance.gd")   puis   Ambiance.du_cercle(3)
##
## pierre / pierre_b : les deux tons de dalle ; joint : le fond des joints ; mur : la maçonnerie.
## dalle : taille d'une dalle (u) ; decale : décalage d'un rang sur l'autre (0.5 = appareil de
## briques) ; tourne : rotation du dallage (rad) ; lave : part du sol parcourue de fissures qui
## rougeoient (0..1) ; seches : part de craquelures éteintes ; souffle : cadence de la pulsation ;
## braises : nombre de braises en suspension.

const Couleurs = preload("res://jeu/theme/couleurs.gd")

const CERCLES: Array[Dictionary] = [
	{"nom": "Limbes", "pierre": Color("#33232a"), "pierre_b": Color("#21161c"), "joint": Color("#0d0709"), "mur": Color("#4a2f38"),
		"dalle": Vector2(88, 88), "decale": 0.0, "tourne": 0.0, "lave": 0.33, "seches": 0.5, "souffle": 1.0, "braises": 26},
	{"nom": "Luxure", "pierre": Color("#361a30"), "pierre_b": Color("#221021"), "joint": Color("#0e0510"), "mur": Color("#52264a"),
		"dalle": Vector2(74, 74), "decale": 0.0, "tourne": 0.7854, "lave": 0.27, "seches": 0.2, "souffle": 0.7, "braises": 30},
	{"nom": "Gourmandise", "pierre": Color("#2c2c1a"), "pierre_b": Color("#1b1c10"), "joint": Color("#090a05"), "mur": Color("#45462a"),
		"dalle": Vector2(72, 54), "decale": 0.5, "tourne": 0.0, "lave": 0.4, "seches": 0.6, "souffle": 0.6, "braises": 20},
	{"nom": "Avarice", "pierre": Color("#352a18"), "pierre_b": Color("#21190e"), "joint": Color("#0b0804"), "mur": Color("#584526"),
		"dalle": Vector2(124, 62), "decale": 0.5, "tourne": 0.0, "lave": 0.3, "seches": 0.3, "souffle": 0.8, "braises": 22},
	{"nom": "Colère", "pierre": Color("#341717"), "pierre_b": Color("#1f0d0e"), "joint": Color("#0c0304"), "mur": Color("#5a2424"),
		"dalle": Vector2(104, 104), "decale": 0.0, "tourne": 0.0, "lave": 0.48, "seches": 0.5, "souffle": 1.6, "braises": 44},
	{"nom": "Hérésie", "pierre": Color("#2b2338"), "pierre_b": Color("#1a1524"), "joint": Color("#09070d"), "mur": Color("#43365a"),
		"dalle": Vector2(136, 68), "decale": 0.5, "tourne": 0.0, "lave": 0.26, "seches": 0.7, "souffle": 0.5, "braises": 18},
	{"nom": "Violence", "pierre": Color("#362217"), "pierre_b": Color("#21140d"), "joint": Color("#0c0603"), "mur": Color("#5a3622"),
		"dalle": Vector2(96, 96), "decale": 0.0, "tourne": 0.7854, "lave": 0.44, "seches": 0.6, "souffle": 1.3, "braises": 38},
	{"nom": "Fraude", "pierre": Color("#172c33"), "pierre_b": Color("#0e1c21"), "joint": Color("#04090b"), "mur": Color("#24474d"),
		"dalle": Vector2(58, 58), "decale": 0.0, "tourne": 0.0, "lave": 0.33, "seches": 0.4, "souffle": 0.9, "braises": 24},
	{"nom": "Trahison", "pierre": Color("#1c2a3a"), "pierre_b": Color("#111b27"), "joint": Color("#05080c"), "mur": Color("#31475f"),
		"dalle": Vector2(150, 150), "decale": 0.0, "tourne": 0.0, "lave": 0.42, "seches": 0.9, "souffle": 0.35, "braises": 30},
	{"nom": "L'Abîme", "pierre": Color("#17161d"), "pierre_b": Color("#0c0b10"), "joint": Color("#000000"), "mur": Color("#33313f"),
		"dalle": Vector2(112, 112), "decale": 0.0, "tourne": 0.7854, "lave": 0.46, "seches": 0.3, "souffle": 1.1, "braises": 40},
]

## L'ambiance du Cercle `cercle` (1..10), avec sa `teinte`.
static func du_cercle(cercle: int) -> Dictionary:
	var rang := posmod(cercle - 1, CERCLES.size())
	var ambiance: Dictionary = CERCLES[rang].duplicate()
	var teintes: Array[Color] = Couleurs.CIRCLE_TINTS
	ambiance["teinte"] = teintes[posmod(cercle - 1, teintes.size())]
	return ambiance

## Même couleur, plus claire ou plus sombre (facteur sur la lumière, l'opacité est gardée).
static func eclaire(couleur: Color, facteur: float) -> Color:
	return Color(minf(1.0, couleur.r * facteur), minf(1.0, couleur.g * facteur), minf(1.0, couleur.b * facteur), couleur.a)
