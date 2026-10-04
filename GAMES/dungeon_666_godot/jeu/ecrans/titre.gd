extends VBoxContainer
## L'écran titre : le logo, l'accroche, l'entrée en Ville, la descente au dernier checkpoint,
## l'arène d'essai, et le rappel des contrôles du périphérique en main (buildTitle du web).

signal commande(cmd: Dictionary)
signal action(nom: String, args: Array)

const LARGEUR := 760.0
## Taille du logo : une part de la largeur du panneau, bornée (clamp(40px, 9vw, 84px) du web).
const LOGO_PART := 0.11
const LOGO_MIN := 40
const LOGO_MAX := 84
const CONTROLES_DOIGTS := "Pouce gauche : se déplacer. Pouce droit, le gros bouton : attaquer (tapez = visée auto ; glissez pour viser, relâchez pour frapper). Jauge pleine : gardez-le appuyé pour l'ultime. Les trois boutons autour : vos compétences. À droite de l'attaque : DASH — invulnérable pendant la ruée."
const CONTROLES_CLAVIER := "ZQSD / WASD : se déplacer · Souris : viser · Clic gauche : attaquer (maintenu, jauge pleine : ultime) · Espace : DASH (invulnérable) · Clic droit, E, F : les trois compétences · Échap : pause"
const CONTROLES_MANETTE := "Manette — stick gauche : se déplacer · stick droit : viser · X / RT : attaquer (maintenu, jauge pleine : ultime) · A / LB : DASH · B, Y, RB : les trois compétences · Start : pause"
const RECORD := "Meilleur étage : %s. Paysage conseillé sur téléphone."
const DESCENDRE := "Descendre · étage %s"

@onready var _logo: Label = %Logo
@onready var _entrer: Button = %Entrer
@onready var _descendre: Button = %Descendre
@onready var _arene: Button = %Arene
@onready var _controles: Label = %Controles
@onready var _record: Label = %Record

var _app: Node

func _ready() -> void:
	resized.connect(_tailler_logo)
	Input.joy_connection_changed.connect(func(_appareil: int, _branchee: bool) -> void: _ecrire_controles())

func ouvrir(app: Node, _partie: Node) -> void:
	_app = app
	# Le dernier checkpoint ouvert (le premier étage tant qu'aucun Gardien n'est tombé).
	var checkpoints: Array = app.profil.get("checkpoints", [])
	var etage: float = checkpoints.max() if not checkpoints.is_empty() else 1.0
	_descendre.text = DESCENDRE % D6Js.num_str(etage)
	_record.text = RECORD % D6Js.num_str(app.profil.get("bestFloor", 1.0))
	_entrer.pressed.connect(func() -> void: action.emit("ville", []))
	_descendre.pressed.connect(func() -> void: action.emit("descendre", [etage]))
	_arene.pressed.connect(func() -> void: action.emit("arene", []))
	_ecrire_controles()
	_tailler_logo()

func largeur() -> float:
	return LARGEUR

func premier_focus() -> Control:
	return _entrer

func _ecrire_controles() -> void:
	if _tactile():
		_controles.text = CONTROLES_DOIGTS
	elif Input.get_connected_joypads().is_empty():
		_controles.text = CONTROLES_CLAVIER
	else:
		_controles.text = CONTROLES_CLAVIER + "\n" + CONTROLES_MANETTE

func _tactile() -> bool:
	var entrees = _app.vues.get("entrees") if _app != null else null
	if entrees != null and entrees.has_method("tactile"):
		return entrees.tactile()
	return DisplayServer.is_touchscreen_available()

func _tailler_logo() -> void:
	_logo.add_theme_font_size_override("font_size", clampi(int(size.x * LOGO_PART), LOGO_MIN, LOGO_MAX))
