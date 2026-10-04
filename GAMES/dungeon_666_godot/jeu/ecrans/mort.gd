extends VBoxContainer
## L'écran de mort : le bilan, ce que la mort a PRIS (temporaire) et ce qui RESTE (permanent),
## puis repartir du checkpoint ou rentrer en Ville (buildDeath du web). En arène et à
## l'entraînement, rien n'est perdu : pas de récapitulatif, on recommence sur place.
## Les nombres viennent de `game.run.deathRecap`, `game.telemetry` et `game.meta`.

signal commande(cmd: Dictionary)
signal action(nom: String, args: Array)

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const Accords = preload("res://jeu/theme/accords.gd")

const LARGEUR := 760.0
const TITRE_PART := 0.078 # clamp(30px, 6vw, 56px) du web, rapporté au panneau
const TITRE_MIN := 30
const TITRE_MAX := 56
const TITRE_PART_HAUTEUR := 0.13 # sur un écran bas (téléphone en paysage), le titre cède la place
const SEP := " · "
const GARDE := "Classe, armes, équipement et coffre, compétences, améliorations de la Ville, checkpoints."

@onready var _titre: Label = %Titre
@onready var _bilan: Label = %Bilan
@onready var _recap: GridContainer = %Recap
@onready var _perdu: PanelContainer = %Perdu
@onready var _garde: PanelContainer = %Garde
@onready var _repartir: Button = %Repartir
@onready var _ville: Button = %Ville

var _place_y := 1000.0

func _ready() -> void:
	resized.connect(_tailler_titre)

func ouvrir(_app: Node, partie: Node) -> void:
	var g: Dictionary = partie.game
	var t: Dictionary = g.telemetry
	_bilan.text = SEP.join(["Étage " + D6Js.num_str(g.run.floor), _compte(t.kills, "démon abattu", "démons abattus"), _compte(t.dodges, "esquive au dash", "esquives au dash")])
	var etage: float = g.run.floor
	if D6Js.truthy(g.get("practice")) or D6Js.truthy(g.get("sandbox")):
		_recap.visible = false
		_repartir.text = "Réessayer le Gardien" if D6Js.truthy(g.get("practice")) else "Recommencer l'arène"
	else:
		var r: Dictionary = _recapitulatif(g)
		etage = r.checkpoint
		_remplir_recap(r)
		_repartir.text = "Repartir du checkpoint" + SEP + "étage " + D6Js.num_str(etage)
	_repartir.pressed.connect(func() -> void: commande.emit({"type": "respawn", "floor": etage}))
	_ville.pressed.connect(func() -> void: commande.emit({"type": "returnToTown"}))
	_tailler_titre()

func largeur() -> float:
	return LARGEUR

func premier_focus() -> Control:
	return _repartir

## Le récapitulatif posé par la simulation à la mort ; à défaut, un récapitulatif vide.
func _recapitulatif(g: Dictionary) -> Dictionary:
	var r = g.run.get("deathRecap")
	if r is Dictionary:
		return r
	return {"boonsLost": 0.0, "boonNames": [], "goldLost": 0.0, "souls": g.meta.souls, "soulsEarned": 0.0, "checkpoint": 1.0}

func _remplir_recap(r: Dictionary) -> void:
	var lignes: Array = []
	if not r.boonNames.is_empty():
		lignes.append(SEP.join(r.boonNames))
	lignes.append("Charon a prélevé %s or." % D6Js.num_str(r.goldLost))
	_perdu.decrire({
		"accent": Couleurs.UI.blood.lightened(0.15), "surtitre": "Perdu · temporaire",
		"titre": _compte(r.boonsLost, "bénédiction", "bénédictions"), "lignes": lignes,
	})
	_garde.decrire({
		"accent": Couleurs.UI.cyan, "surtitre": "Gardé · permanent",
		"titre": "◆ %s (+%s)" % [Accords.compte(r.souls, "Âme", "Âmes"), D6Js.num_str(r.soulsEarned)], "lignes": [GARDE],
	})

static func _compte(n: float, singulier: String, pluriel: String) -> String:
	return D6Js.num_str(n) + " " + (pluriel if n > 1.0 else singulier)

## La place offerte au panneau (posée par Ecrans) : le titre s'y mesure.
func tenir_dans(place: Vector2) -> void:
	if not is_equal_approx(place.y, _place_y):
		_place_y = place.y
		_tailler_titre()

func _tailler_titre() -> void:
	var taille := minf(size.x * TITRE_PART, _place_y * TITRE_PART_HAUTEUR)
	_titre.add_theme_font_size_override("font_size", clampi(int(taille), TITRE_MIN, TITRE_MAX))
