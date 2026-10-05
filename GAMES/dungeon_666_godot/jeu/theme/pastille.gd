extends Control
## Une PASTILLE à nombre : un disque d'or et son chiffre, pour dire « il y a N choses à faire ici »
## (points de compétence à dépenser : sur l'onglet Grimoire, sur le bouton d'entrée de la Ville,
## en tête de l'arbre). Elle se cache d'elle-même à zéro. Elle ne lit rien : on lui pose `nombre`.
##   const Pastille = preload("res://jeu/theme/pastille.gd")
##   var p := Pastille.new()   bouton.add_child(p)   p.accrocher()   p.nombre = 3
## Coût : un lot de triangles (un appel) et son chiffre.

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const Triangles = preload("res://jeu/theme/triangles.gd")
const ThemeJeu = preload("res://jeu/theme/theme.gd")

const BATTEMENT := 3.2 # rad/s
const HALO := 3.0 # px du halo qui bat
const DEBORD := Vector2(-5.0, -6.0) # accrochée au coin haut-droit de son parent : ce qu'elle en dépasse
const RETRAIT := 6.0 # accrochée DANS son parent, à droite : ce qui la sépare du bord

@export var rayon := 9.0:
	set(v):
		rayon = v
		custom_minimum_size = Vector2.ONE * (v + HALO) * 2.0
		queue_redraw()
## Vrai : un halo bat autour (quelque chose attend le joueur).
@export var bat := true

var nombre := 0:
	set(v):
		if v != nombre:
			nombre = v
			visible = v > 0
			queue_redraw()

var _temps := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2.ONE * (rayon + HALO) * 2.0
	visible = nombre > 0

## Pose la pastille sur son parent (un bouton) : `au_coin`, à cheval sur son coin haut-droit ;
## sinon DANS le bouton, à droite, à mi-hauteur (son texte lui laisse la place).
func accrocher(au_coin: bool = true) -> void:
	var cote := (rayon + HALO) * 2.0
	if not au_coin:
		set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		offset_left = -cote - RETRAIT
		offset_right = -RETRAIT
		offset_top = -cote / 2.0
		offset_bottom = cote / 2.0
		return
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -cote - DEBORD.x
	offset_right = -DEBORD.x
	offset_top = DEBORD.y
	offset_bottom = DEBORD.y + cote

func _process(delta: float) -> void:
	if bat and is_visible_in_tree():
		_temps += delta
		queue_redraw()

func _draw() -> void:
	var c := size / 2.0
	var lot := Triangles.new()
	if bat:
		lot.disque(c, rayon + HALO, Color(Couleurs.UI.gold, 0.15 + 0.25 * (0.5 + 0.5 * sin(_temps * BATTEMENT))))
	lot.disque(c, rayon + 1.5, Couleurs.UI["void"])
	lot.disque(c, rayon, Couleurs.UI.gold)
	lot.tracer(self)
	var police: Font = ThemeJeu.police_grasse()
	var taille := int(rayon * 1.3)
	var texte := str(nombre)
	var mesure := police.get_string_size(texte, HORIZONTAL_ALIGNMENT_LEFT, -1, taille)
	var base := c + Vector2(-mesure.x / 2.0, (police.get_ascent(taille) - police.get_descent(taille)) / 2.0)
	draw_string(police, base, texte, HORIZONTAL_ALIGNMENT_LEFT, -1, taille, Couleurs.UI["void"])
