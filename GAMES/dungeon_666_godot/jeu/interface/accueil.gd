extends PanelContainer
## L'ACCUEIL DU PREMIER JOUEUR : une consigne à la fois, dans un petit bandeau du HUD, sous le fil
## des étages (loin des pouces, hors du héros et de ses télégraphes). Elle s'efface dès que le
## joueur a FAIT le geste, et ne revient plus : l'acquis est retenu dans les RÉGLAGES
## (`app.reglages.accueil`, fichier `reglages_jeu.json`), jamais dans le profil de la simulation.
##
## La liste des consignes est une table : jeu/interface/consignes.gd. Ici, seulement : laquelle
## montrer, avec quel libellé (celui de l'appareil en main, donné par le HUD), et quand elle est
## acquise (événements de `partie.evenements`, lecture de `partie.game`). Ce nœud n'écrit rien
## dans la simulation, ne met jamais en pause, ne prend aucun clic. Absent de l'arène d'essai et
## de l'entraînement. Sa seule action : `app.regler("accueil", …)` quand une consigne est acquise.

## Une consigne vient d'être acquise (geste fait, ou patience écoulée).
signal acquise(id: String)

const Consignes = preload("res://jeu/interface/consignes.gd")
const Etats = preload("res://jeu/interface/etat_commandes.gd")
const Icones = preload("res://jeu/interface/icones.gd")
const Triangles = preload("res://jeu/theme/triangles.gd")
const Couleurs = preload("res://jeu/theme/couleurs.gd")

const CLE := "accueil" # le champ des réglages
const FONDU := 0.25 # s d'apparition et de disparition
const TENUE := 2.5 # s : une consigne montrée reste au moins ce temps (un télégraphe dure moins)
const GLISSEMENT := 6.0 # px : la consigne descend à sa place en apparaissant
const SAUT := 150.0 # u : au-delà, le héros a changé de salle, il n'a pas marché
const RAYON_PICTO := 19.0 # rayon du « bouton » dont le pictogramme est la réduction
const SANS_PICTO := ["", "move"]

@onready var _texte: Label = %Texte
@onready var _picto: Control = %Picto
@onready var _touche: Label = %Touche

var _app
var _partie
var _actif := true
var _acquis := {} # id -> true
var _montree := "" # la consigne écrite dans le bandeau
var _opacite := 0.0
var _age := 0.0 # s depuis qu'elle est montrée
var _vue := {} # id -> s d'affichage cumulées (patience)
var _contexte := {} # id -> sa lecture `quand` à la dernière image jouée
var _parcours := 0.0
var _position = null # dernière position lue du héros
var _appareil := "clavier"
var _libelles := {}
var _icone := ""

func _ready() -> void:
	_picto.draw.connect(_dessiner_picto)
	modulate.a = 0.0
	visible = false

## Seul point d'entrée (voir jeu/ARCHITECTURE.md) ; appelé par le HUD, qui porte cette vue.
func brancher(app, partie) -> void:
	_app = app
	_partie = partie
	partie.evenements.connect(_sur_evenements)
	partie.partie_demarree.connect(_sur_demarrage)
	if app != null and app.has_signal("reglages_change"):
		app.reglages_change.connect(_relire)
	_relire()

# ---------------------------------------------------------------- ce que la vue expose

## L'identifiant de la consigne montrée ("" : aucune).
func montree() -> String:
	return _montree if _opacite > 0.0 else ""

## La commande que la consigne montrée désigne (son bouton bat à l'écran), ou "".
func commande() -> String:
	return String(Consignes.trouver(montree()).get("commande", ""))

## La phrase et le libellé affichés (pour les essais).
func phrase() -> String:
	return _texte.text

func libelle() -> String:
	return _touche.text if _touche.visible else ""

func est_acquise(id: String) -> bool:
	return _acquis.has(id)

## Appelé par le HUD à chaque image où il est visible. `appareil` : clavier | manette | tactile ;
## `libelles` : {commande: touche ou bouton} de cet appareil ; `retenue` : une bannière occupe la
## place, la consigne attend ; `haut` : où se poser (sous le bloc de l'étage), repère du parent.
func actualiser(game, delta: float, appareil: String, libelles: Dictionary, retenue: bool, haut: float) -> void:
	if appareil != _appareil or libelles != _libelles:
		_appareil = appareil
		_libelles = libelles
		_ecrire(game)
	var voulue := ""
	var ouvert: bool = _actif and Consignes.ouvert(game)
	if ouvert and game.mode == "play" and not _partie.en_pause:
		_mesurer(game, delta)
		voulue = "" if retenue else _choisir()
	else:
		voulue = _montree if ouvert else "" # menu, pause, agonie : rien ne bouge
		_position = null # et le chemin fait pendant ce temps ne compte pas
	_animer(voulue if not _acquis.has(voulue) else "", game, delta)
	_placer(haut)

# ---------------------------------------------------------------- réglages

func _relire() -> void:
	var reglages = _app.get("reglages") if _app != null else null
	var r = reglages.get(CLE) if reglages is Dictionary else null
	if not (r is Dictionary):
		return
	var avant := _acquis.size()
	_actif = r.get("actif") != false
	_acquis.clear()
	for id in r.get("acquis", []):
		_acquis[id] = true
	if _acquis.size() < avant: # « Revoir les consignes » : la patience repart de zéro
		_vue.clear()
		_parcours = 0.0

func _acquerir(id: String) -> void:
	if _acquis.has(id):
		return
	_acquis[id] = true
	acquise.emit(id)
	if _app != null and _app.has_method("regler"):
		var liste: Array = Consignes.ids().filter(func(i: String) -> bool: return _acquis.has(i))
		_app.regler(CLE, {"actif": _actif, "acquis": liste})

# ---------------------------------------------------------------- lecture de la partie

func _sur_demarrage() -> void:
	_position = null
	_parcours = 0.0
	_contexte.clear()

## Un geste fait compte, que sa consigne soit à l'écran ou non : qui sait jouer ne les voit pas.
func _sur_evenements(liste: Array) -> void:
	if not _actif or not Consignes.ouvert(_partie.game):
		return
	for ev in liste:
		for c in Consignes.TABLE:
			if ev.type in c.get("fait", []) and (not c.get("contexte", false) or _contexte.get(c.id, false)):
				_acquerir(c.id)

## À chaque image jouée : le chemin parcouru, la lecture `quand` de chaque consigne, la patience.
func _mesurer(game: Dictionary, delta: float) -> void:
	var ici := Vector2(game.player.x, game.player.y)
	if _position != null and ici.distance_to(_position) < SAUT:
		_parcours += ici.distance_to(_position)
	_position = ici
	for c in Consignes.TABLE:
		_contexte[c.id] = not _acquis.has(c.id) and Consignes.quand(c.quand, game)
		if c.has("parcours") and _parcours >= c.parcours:
			_acquerir(c.id)
	if _montree != "" and _opacite >= 1.0:
		_vue[_montree] = _vue.get(_montree, 0.0) + delta
		var patience: float = Consignes.trouver(_montree).get("patience", 0.0)
		if patience > 0.0 and _vue[_montree] >= patience:
			_acquerir(_montree)

## Laquelle montrer : la première de la table qui a lieu d'être, les urgentes d'abord. Celle qui
## est à l'écran y reste au moins TENUE secondes ; une urgente y reste tant qu'elle a lieu d'être.
func _choisir() -> String:
	var courante: Dictionary = Consignes.trouver(_montree)
	if not courante.is_empty() and not _acquis.has(_montree):
		if _age < TENUE or (courante.get("urgent", false) and _contexte.get(_montree, false)):
			return _montree
	var urgente := _premiere(true)
	return urgente if urgente != "" else _premiere(false)

func _premiere(urgentes: bool) -> String:
	for c in Consignes.TABLE:
		if _contexte.get(c.id, false) and c.get("urgent", false) == urgentes:
			return c.id
	return ""

# ---------------------------------------------------------------- affichage

## Fondu : la consigne montrée s'efface, puis la suivante apparaît. Jamais deux à la fois.
func _animer(voulue: String, game, delta: float) -> void:
	if voulue != _montree:
		_opacite = maxf(0.0, _opacite - delta / FONDU)
		if _opacite <= 0.0:
			_montree = voulue
			_age = 0.0
			_ecrire(game)
	elif _montree != "":
		_opacite = minf(1.0, _opacite + delta / FONDU)
		_age += delta
	modulate.a = _opacite
	visible = _opacite > 0.0

func _ecrire(game) -> void:
	var c: Dictionary = Consignes.trouver(_montree)
	if c.is_empty():
		return
	var cmd := String(c.get("commande", ""))
	_texte.text = Consignes.texte(c, _appareil)
	_touche.text = String(_libelles.get(cmd, ""))
	_touche.visible = _touche.text != ""
	_picto.visible = not (cmd in SANS_PICTO)
	_icone = String(Etats.etat(game, cmd).icone) if _picto.visible and game is Dictionary else cmd
	_picto.queue_redraw()

func _placer(haut: float) -> void:
	size = get_combined_minimum_size()
	var place := get_parent_area_size()
	position = Vector2((place.x - size.x) / 2.0, haut - (1.0 - _opacite) * GLISSEMENT)

## Le pictogramme de la commande : le même que sur son bouton (celui du kit équipé).
func _dessiner_picto() -> void:
	if not Icones.connue(_icone):
		return
	var lot := Triangles.new()
	Icones.ajouter(lot, _icone, _picto.size / 2.0, RAYON_PICTO, Couleurs.PAL.gold)
	lot.tracer(_picto)
