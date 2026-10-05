extends VBoxContainer
## L'écran de victoire : le dernier Gardien est tombé. Une seule issue, le retour en Ville
## (buildVictory du web).

signal commande(cmd: Dictionary)
signal action(nom: String, args: Array)

const LARGEUR := 760.0
const TITRE_PART := 0.09
const TITRE_MIN := 30
const TITRE_MAX := 64
const ACCROCHE := "Vous avez atteint le %se étage."
const EXPERIENCE := "
Expérience de classe : +%s · niveau %s."

@onready var _titre: Label = %Titre
@onready var _accroche: Label = %Accroche
@onready var _ville: Button = %Ville

func _ready() -> void:
	resized.connect(_tailler_titre)

func ouvrir(_app: Node, partie: Node) -> void:
	var arbre: Dictionary = D6Run.tree_recap(partie.game)
	_accroche.text = ACCROCHE % D6Js.num_str(partie.game.run.floor) + EXPERIENCE % [D6Js.num_str(arbre.xpEarned), D6Js.num_str(arbre.level)]
	_ville.pressed.connect(func() -> void: commande.emit({"type": "returnToTown"}))
	_tailler_titre()

func largeur() -> float:
	return LARGEUR

func premier_focus() -> Control:
	return _ville

func _tailler_titre() -> void:
	_titre.add_theme_font_size_override("font_size", clampi(int(size.x * TITRE_PART), TITRE_MIN, TITRE_MAX))
