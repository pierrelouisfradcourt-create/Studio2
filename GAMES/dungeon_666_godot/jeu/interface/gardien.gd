extends VBoxContainer
## La barre du Gardien : son nom, sa vie, ses seuils de phase marqués d'un trait. Visible
## seulement pendant un combat de Gardien. Portage de la branche « boss » de `drawTopCenter`.

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const LARGEUR_MAX := 420.0
const PART_ECRAN := 0.5
const HAUTEUR := 14.0
const NOM := "◆  %s  ◆"

@onready var nom: Label = $Nom
@onready var barre: Control = $Barre

var _suivi = null # identifiant du Gardien affiché

## Rend vrai si un Gardien est en vie (la barre est alors visible). `largeur` : celle de l'écran.
func actualiser(game: Dictionary, largeur: float) -> bool:
	var boss = _gardien(game)
	visible = boss != null
	if boss == null:
		_suivi = null
		return false
	if _suivi != boss.get("id"):
		_suivi = boss.get("id")
		barre.reinitialiser()
	var def: Dictionary = game.tuning.boss[boss.kind]
	var enchaine := D6Js.truthy(boss.get("shielded"))
	nom.text = "%s — ENCHAÎNÉ : abats ses geôliers" % def.name if enchaine else NOM % def.name
	barre.lisere = Couleurs.PAL.bossTrim
	barre.custom_minimum_size = Vector2(minf(LARGEUR_MAX, largeur * PART_ECRAN), HAUTEUR)
	barre.marques = [def.get("phase2At", 0.66), def.get("phase3At", 0.33)]
	barre.poser(boss.hp / boss.maxHp, _couleur(boss, enchaine))
	return true

func _gardien(game: Dictionary):
	for e in game.enemies:
		if D6Js.truthy(e.get("boss")) and not D6Js.truthy(e.get("dead")):
			return e
	return null

func _couleur(boss: Dictionary, enchaine: bool) -> Color:
	if enchaine:
		return Couleurs.PAL.summon
	return Couleurs.UI.blood if boss.get("phase", 1.0) <= 1.0 else Couleurs.PAL.lava
