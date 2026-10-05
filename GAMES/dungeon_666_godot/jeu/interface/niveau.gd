extends HBoxContainer
## Le BANDEAU DE NIVEAU : « NIVEAU 7 · +1 point », quand la classe passe un
## niveau en pleine descente (événement `levelUp`), ou gagne le point d'un Gardien vaincu pour la
## première fois (`treePoint`). Même manière que les bannières (jeu/interface/banniere.gd : fondu,
## léger élan), mais PETIT, sur une ligne, dans le coin du héros : sous sa vie et sa barre
## d'expérience, à la place des losanges des bénédictions (le HUD les efface le temps qu'il passe).
## Il reste dans la bande du haut : jamais sur le combat, ni sur les flèches des ennemis hors champ ;
## il ne retient aucune consigne et ne prend aucun toucher.
## Il ne calcule rien : le niveau et les points à dépenser sont ceux que portent les événements ;
## le « +N » est l'écart entre deux nombres de points rendus par les règles.

signal montre(texte: String) ## un bandeau vient de s'afficher (la barre d'expérience brille)

const Accords = preload("res://jeu/theme/accords.gd")
const DUREE := 2.8 # s
const ENTREE := 0.18 # s d'apparition
const SORTIE := 0.5 # s de fondu final
const GLISSE := 14.0 # px : il arrive de la gauche
const OPACITE := 0.97

@onready var _titre: Label = $Titre
@onready var _sous: Label = $Sous

var _partie
var _vie := 0.0
var _points := -1.0 # points à dépenser connus (-1 : pas encore lus)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func brancher(partie) -> void:
	_partie = partie
	partie.evenements.connect(_sur_evenements)
	partie.partie_demarree.connect(_sur_demarrage)

## Le texte montré ("" : rien à l'écran), pour les essais.
func texte() -> String:
	return "%s · %s" % [_titre.text, _sous.text] if _vie > 0.0 else ""

func _sur_demarrage() -> void:
	_vie = 0.0
	visible = false
	var g = _partie.game
	_points = D6Profile.tree_points(g.meta, g.tuning, g.meta.loadout.classId) if g != null else -1.0

func _sur_evenements(liste: Array) -> void:
	for ev in liste:
		if ev.type == "levelUp":
			_afficher("NIVEAU %s" % D6Js.num_str(ev.level), ev.points)
		elif ev.type == "treePoint":
			_afficher("POINT DE COMPÉTENCE", ev.points)

func _afficher(titre: String, points: float) -> void:
	var gain := points - _points if _points >= 0.0 else 0.0
	_points = points
	_titre.text = titre
	_sous.text = "+%s" % Accords.compte(gain, "point", "points") if gain > 0.0 else "%s à dépenser" % Accords.compte(points, "point", "points")
	_vie = DUREE
	montre.emit(texte())

## Son opacité (0 : rien à l'écran), pour que le HUD efface ce qu'il recouvre.
func opacite() -> float:
	return modulate.a if visible else 0.0

## Appelé par le HUD à chaque image : `coin` est l'endroit où se poser (sous la vie), repère du parent.
func actualiser(delta: float, coin: Vector2) -> void:
	if _vie <= 0.0:
		visible = false
		return
	_vie -= delta
	var age := DUREE - _vie
	var a := age / ENTREE if age < ENTREE else (_vie / SORTIE if _vie < SORTIE else 1.0)
	modulate.a = clampf(a, 0.0, 1.0) * OPACITE
	size = get_combined_minimum_size()
	position = coin - Vector2(GLISSE * (1.0 - clampf(age / ENTREE, 0.0, 1.0)), 0.0)
	visible = _vie > 0.0
