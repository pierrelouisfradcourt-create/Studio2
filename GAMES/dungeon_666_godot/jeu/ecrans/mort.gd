extends VBoxContainer
## L'écran de mort : le bilan, ce que la mort a PRIS (temporaire) et ce qui RESTE (permanent),
## puis repartir du checkpoint ou rentrer en Ville (buildDeath du web). En arène et à
## l'entraînement, rien n'est perdu : pas de récapitulatif, on recommence sur place.
## Les nombres viennent de `game.run.deathRecap`, `game.telemetry` et `game.meta`.
## Sous les deux cartes, la PROGRESSION de la classe : son niveau, sa barre d'expérience où la part
## gagnée dans la descente se détache et se remplit à vue, et, si un niveau est passé, la ligne qui
## envoie au Grimoire. Le niveau et la barre sont lus dans D6Profile.tree_view ; rien n'est calculé ici.

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
const EXPERIENCE := "Expérience de classe : +%s."
const NIVEAU := "Niveau %s ! +%s à dépenser au Grimoire."
const CLASSE := "%s · niveau %s · %s"
const AU_SOMMET := "maximum"

@onready var _titre: Label = %Titre
@onready var _bilan: Label = %Bilan
@onready var _recap: GridContainer = %Recap
@onready var _perdu: PanelContainer = %Perdu
@onready var _garde: PanelContainer = %Garde
@onready var _progression: VBoxContainer = %Progression
@onready var _classe: Label = %NiveauClasse
@onready var _barre: Control = %BarreXp
@onready var _gagne: Label = %Gagne
@onready var _niveau: Label = %NiveauGagne
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
		_progression.visible = false
		_repartir.text = "Réessayer le Gardien" if D6Js.truthy(g.get("practice")) else "Recommencer l'arène"
	else:
		var r: Dictionary = _recapitulatif(g)
		etage = r.checkpoint
		_remplir_recap(r)
		_montrer_la_progression(g, r.get("tree"))
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

## La progression de la classe jouée, sur une ligne : « Revenant · niveau 2 · 5 / 65 », la barre
## (la part d'avant la descente, sombre ; la part gagnée, claire, qui se remplit), l'expérience
## gagnée ; dessous, si un niveau est passé, « Niveau 2 ! +1 point à dépenser au Grimoire. ».
## `bilan` : D6Run.tree_recap.
func _montrer_la_progression(g: Dictionary, bilan) -> void:
	_progression.visible = bilan is Dictionary
	if not (bilan is Dictionary):
		return
	var v: Dictionary = D6Profile.tree_view(g.meta, g.tuning, bilan.classId)
	var au_sommet: bool = v.xpNext <= 0.0
	var acquis := AU_SOMMET if au_sommet else "%s / %s" % [D6Js.num_str(v.xp), D6Js.num_str(v.xpNext)]
	_classe.text = CLASSE % [g.tuning.classes[bilan.classId].name, D6Js.num_str(v.level), acquis]
	# Un niveau passé : toute la barre du niveau en cours est du gain ; sinon, ce qui dépasse l'acquis d'avant.
	var avant: float = 0.0 if au_sommet or bilan.levelsGained > 0.0 else maxf(0.0, v.xp - bilan.xpEarned) / v.xpNext
	_barre.poser(1.0 if au_sommet else v.xp / v.xpNext, avant)
	_gagne.text = EXPERIENCE % D6Js.num_str(bilan.xpEarned)
	_niveau.visible = bilan.levelsGained > 0.0
	_niveau.text = NIVEAU % [D6Js.num_str(bilan.level), Accords.compte(bilan.levelsGained, "point", "points")]

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
