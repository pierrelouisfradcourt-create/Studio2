extends CanvasLayer
## Le HUD : tout ce que le joueur lit pendant le combat (vie, étage, or, Âmes, Gardien,
## bannières, bénédictions) et le DESSIN des commandes du combat V3, dans le même langage sur les
## trois appareils : le bouton d'attaque qui est la jauge d'ultime, les trois emplacements
## groupés, le dash à part (au doigt : en arc autour de l'attaque ; au bureau : en rangée).
## Visible seulement quand `app.ecran == "jeu"` et qu'une partie existe.
##
## Ce nœud ne fait que LIRE `partie.game` et répartir : chaque élément a son script sous
## jeu/interface/. Sa seule action : le bouton pause → `app.mettre_en_pause(true)`.
## Référence : GAMES/dungeon_666/src/render/hud.mjs.

const Couleurs = preload("res://jeu/theme/couleurs.gd")
const ThemeJeu = preload("res://jeu/theme/theme.gd")
const Disposition = preload("res://jeu/interface/disposition.gd")
const Etats = preload("res://jeu/interface/etat_commandes.gd")
const Degrades = preload("res://jeu/interface/degrades.gd")
const Accords = preload("res://jeu/theme/accords.gd")

const BORD := 14 # marge entre le HUD et le bord (en plus de la zone sûre)
const BANDE := 96.0 # hauteur de la bande sombre du haut
const BANDE_BAS := 110.0 # hauteur de la bande sombre du bas (rangée de commandes du bureau)
const BANDE_UTILE := 6.0 # marge sous le bloc central du haut (flèches hors champ)
const VIE_LARGEUR := Vector2(90.0, 200.0) # mini, maxi
const VIE_PART := 0.26 # part de la largeur d'écran
const VIE_BASSE := 0.3
const BANDE_BASSE := 0.42 # opacité de la bande sombre derrière la rangée de commandes du bureau
const LARGEUR_UTILE := 700.0 # le haut du HUD (vie, fil des étages, bourse) tient dans cette largeur
const SEUIL_MANETTE := 0.5 # un axe de manette compte comme « utilisé » au-delà
const ECART_ACCUEIL := 6.0 # entre le bloc de l'étage et la consigne de l'accueil
const ENFONCE := 0.14 # s : un bouton du bureau reste « enfoncé » au moins ce temps (un appui bref se voit)
const EMPLACEMENTS := ["skill1", "skill2", "skill3"]
const ECART_NIVEAU := 3.0 # entre la barre d'expérience et le bandeau de niveau
const EN_MARCHE := 0.5 # norme du déplacement voulu au-delà de laquelle le héros marche franchement
## Libellé de chaque commande selon le dernier périphérique utilisé (mêmes touches que jeu/entrees/).
## « move » (le déplacement) n'a pas de bouton : seules les consignes de l'accueil le nomment.
const TOUCHES := {
	"clavier": {"attack": "Clic G", "dash": "Espace", "skill1": "Clic D", "skill2": "E", "skill3": "F", "move": "ZQSD"},
	"manette": {"attack": "X", "dash": "A", "skill1": "B", "skill2": "Y", "skill3": "RB", "move": "Stick gauche"},
}
## Les quatre touches PHYSIQUES du déplacement (jeu/entrees/clavier_souris.gd) : leur lettre dépend
## du clavier (ZQSD sur un AZERTY, WASD sur un QWERTY).
const TOUCHES_DEPLACEMENT := [KEY_W, KEY_A, KEY_S, KEY_D]

var app
var partie
## Banc d'essai : présentation tactile sans vue Entrees (disposition de repli).
var forcer_tactile := false

var _marges := Vector4.ZERO # zone sûre : gauche, haut, droite, bas (px du viewport)
var _encoche_forcee := false
var _echelle := 1.0 # agrandissement des textes et barres sur une petite fenêtre (téléphone)
## Dernier périphérique utilisé hors écran tactile : « clavier » ou « manette » (libellés des commandes).
var _peripherique := "clavier"
var _deplacement := "" # les lettres du déplacement sur ce clavier (lues une fois)
var _xp_lue: Array = [] # ce qui a été lu de l'expérience à la dernière image (on ne relit l'arbre que si elle bouge)
var _enfonce := {} # commande -> s pendant lesquelles son bouton du bureau reste dessiné enfoncé

@onready var racine: Control = $Racine
@onready var bande: TextureRect = $Racine/BandeHaute
@onready var bande_basse: TextureRect = $Racine/BandeBasse
@onready var danger: TextureRect = $Racine/Danger
@onready var fleches: Control = $Racine/Fleches
@onready var marges: MarginContainer = $Racine/Marges
@onready var centre: VBoxContainer = $Racine/Marges/Zone/Centre
@onready var vie: Control = %Vie
@onready var vie_nombre: Label = %VieNombre
@onready var gauche: VBoxContainer = $Racine/Marges/Zone/Gauche
@onready var experience: HBoxContainer = %Experience
@onready var niveau_classe: Label = %NiveauClasse
@onready var barre_xp: Control = %BarreXp
@onready var niveau: HBoxContainer = %Niveau
@onready var benedictions: Control = %Benedictions
@onready var etage: Label = %Etage
@onready var etage_total: Label = %EtageTotal
@onready var fil: Control = %Fil
@onready var cercle: Label = %Cercle
@onready var gardien: VBoxContainer = %Gardien
@onready var or_montant: Label = %OrMontant
@onready var or_piece: Control = %OrPiece
@onready var ames: HBoxContainer = %Ames
@onready var ames_gemme: Control = %AmesGemme
@onready var ames_montant: Label = %AmesMontant
@onready var pause: Button = %Pause
@onready var banniere: VBoxContainer = %Banniere
@onready var indice: Label = %Indice
@onready var bureau: HBoxContainer = %Bureau
@onready var commandes_bureau: Array = [%CmdAttaque, %CmdDash, %CmdEmplacement1, %CmdEmplacement2, %CmdEmplacement3]
@onready var tactile: Control = $Racine/Tactile
@onready var reperes: Control = $Racine/Reperes
@onready var accueil: PanelContainer = %Accueil

func _ready() -> void:
	racine.theme = ThemeJeu.theme()
	bande.texture = Degrades.bande()
	bande_basse.texture = Degrades.bande(BANDE_BASSE)
	_habiller()
	_ignorer_souris(racine)
	pause.pressed.connect(_sur_pause)
	get_viewport().size_changed.connect(_poser_marges)
	_poser_marges()
	visible = false

## Seul point d'entrée de la vue (voir jeu/ARCHITECTURE.md).
func brancher(app_: Node, partie_: Node) -> void:
	app = app_
	partie = partie_
	banniere.brancher(partie)
	danger.brancher(partie)
	accueil.brancher(app, partie)
	niveau.brancher(partie)
	niveau.montre.connect(func(_texte: String) -> void: barre_xp.eclater())
	partie.partie_demarree.connect(_sur_demarrage)

func _sur_demarrage() -> void:
	vie.reinitialiser()
	_xp_lue = []

func _sur_pause() -> void:
	if app != null:
		app.mettre_en_pause(true)

func _process(delta: float) -> void:
	var game = partie.game if partie != null else null
	visible = game != null and app != null and app.ecran == "jeu" and game.get("info") != null
	if not visible:
		return
	var au_doigt := _tactile()
	_actualiser_vie(game)
	_actualiser_experience(game)
	# Le bandeau de niveau prend, le temps qu'il passe, la place des losanges des bénédictions.
	niveau.actualiser(delta, gauche.position + Vector2(0.0, experience.position.y + experience.size.y + ECART_NIVEAU))
	benedictions.modulate.a = 1.0 - niveau.opacite()
	_actualiser_centre(game)
	_actualiser_bourse(game)
	accueil.actualiser(game, delta, appareil(), libelles(), banniere.visible, centre.position.y + centre.size.y + ECART_ACCUEIL)
	_suivre_appuis(delta)
	var visee := _actualiser_commandes(game, au_doigt)
	_actualiser_reperes(game, au_doigt)
	reperes.montrer(visee, _arrivee_raccourcie(game), _echelle)

# ---------------------------------------------------------------- habillage et marges

## Les textes prennent leur style du thème (variations Hud… de jeu/theme/theme.gd) ; ici, seulement
## les couleurs des pièces dessinées et des filets, prises dans la palette par rôle.
func _habiller() -> void:
	var pal: Dictionary = Couleurs.PAL
	or_piece.couleur = pal.gold
	ames_gemme.couleur = pal.lance
	_ecrire_touches()

## Le HUD ne prend aucun clic ni toucher (ils vont à la vue Entrees), sauf le bouton pause.
func _ignorer_souris(n: Node) -> void:
	if n is Control and not n is BaseButton:
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for enfant in n.get_children():
		_ignorer_souris(enfant)

## Banc d'essai : impose une encoche (gauche, haut, droite, bas), en pixels du viewport.
func poser_encoche(encoche: Vector4) -> void:
	_encoche_forcee = true
	_marges = encoche
	_appliquer_marges()

func _poser_marges() -> void:
	if not _encoche_forcee:
		_marges = _zone_sure()
	_appliquer_marges()

## Encoche et bords arrondis des téléphones, convertis en pixels du viewport.
func _zone_sure() -> Vector4:
	if not OS.has_feature("mobile"):
		return Vector4.ZERO
	var fenetre := Vector2(DisplayServer.window_get_size())
	var sure := Rect2(DisplayServer.get_display_safe_area())
	if fenetre.x <= 0.0 or fenetre.y <= 0.0 or sure.size.x <= 0.0:
		return Vector4.ZERO
	var k := racine.get_viewport_rect().size / fenetre
	var fin := fenetre - sure.end
	return Vector4(maxf(0.0, sure.position.x) * k.x, maxf(0.0, sure.position.y) * k.y, maxf(0.0, fin.x) * k.x, maxf(0.0, fin.y) * k.y)

## Textes, barres et bouton pause gardent leur taille de référence sur une petite fenêtre : le
## bloc `Marges` est agrandi (jamais au point que le haut du HUD ne tienne plus dans la largeur).
## Les commandes tactiles et les flèches, placées en pixels du viewport, ne sont pas concernées.
func _appliquer_marges() -> void:
	var vue := racine.get_viewport_rect().size
	var k: float = ThemeJeu.echelle(vue, get_window())
	ThemeJeu.nettete(get_viewport(), k)
	_echelle = maxf(1.0, minf(k, vue.x / LARGEUR_UTILE))
	marges.scale = Vector2(_echelle, _echelle)
	marges.position = Vector2.ZERO
	marges.size = vue / _echelle
	marges.add_theme_constant_override("margin_left", BORD + int(_marges.x / _echelle))
	marges.add_theme_constant_override("margin_top", BORD + int(_marges.y / _echelle))
	marges.add_theme_constant_override("margin_right", BORD + int(_marges.z / _echelle))
	marges.add_theme_constant_override("margin_bottom", BORD + int(_marges.w / _echelle))
	bande.offset_bottom = BANDE * _echelle + _marges.y
	bande_basse.offset_top = -BANDE_BAS * _echelle - _marges.w

# ---------------------------------------------------------------- clavier ou manette

## Le dernier périphérique utilisé décide des libellés sous les commandes. Le HUD écoute sans rien
## consommer : les entrées restent à la vue Entrees.
func _input(ev: InputEvent) -> void:
	if ev is InputEventJoypadButton and ev.pressed:
		montrer_peripherique("manette")
	elif ev is InputEventJoypadMotion and absf(ev.axis_value) > SEUIL_MANETTE:
		montrer_peripherique("manette")
	elif (ev is InputEventKey or ev is InputEventMouseButton) and ev.pressed:
		montrer_peripherique("clavier")

## « clavier » ou « manette » : les libellés de la rangée de commandes suivent.
func montrer_peripherique(nom: String) -> void:
	if nom == _peripherique or not TOUCHES.has(nom):
		return
	_peripherique = nom
	_ecrire_touches()

func peripherique() -> String:
	return _peripherique

## L'appareil en main : « tactile », sinon le dernier périphérique utilisé (clavier ou manette).
func appareil() -> String:
	return "tactile" if _tactile() else _peripherique

## Les libellés de l'appareil en main, {commande: touche ou bouton} ; au doigt, aucun : c'est le
## bouton lui-même qui se montre.
func libelles() -> Dictionary:
	if _tactile():
		return {}
	var l: Dictionary = TOUCHES[_peripherique].duplicate()
	if _peripherique == "clavier":
		if _deplacement == "":
			_deplacement = _lettres_du_deplacement(l.move)
		l.move = _deplacement
	return l

## Les lettres que porte CE clavier sur les touches du déplacement ; à défaut (pas de fenêtre,
## clavier inconnu), `repli`. Lu une seule fois.
func _lettres_du_deplacement(repli: String) -> String:
	if DisplayServer.get_name() == "headless":
		return repli
	var lettres := ""
	for touche in TOUCHES_DEPLACEMENT:
		var nom := OS.get_keycode_string(DisplayServer.keyboard_get_label_from_physical(touche))
		if nom.length() != 1:
			return repli
		lettres += nom
	return lettres

func _ecrire_touches() -> void:
	for c in commandes_bureau:
		c.get_parent().get_node("Touche").text = TOUCHES[_peripherique][c.id]

# ---------------------------------------------------------------- lecture de la partie

func _actualiser_vie(game: Dictionary) -> void:
	var p: Dictionary = game.player
	var part: float = p.hp / p.maxHp
	vie.custom_minimum_size.x = clampf(marges.size.x * VIE_PART, VIE_LARGEUR.x, VIE_LARGEUR.y)
	vie.poser(part, Couleurs.PAL.danger if part < VIE_BASSE else Couleurs.PAL.hpBar)
	vie_nombre.text = "%s / %s" % [D6Js.num_str(ceilf(p.hp)), D6Js.num_str(roundf(p.maxHp))]
	benedictions.poser(game.run.boons)

## L'expérience de la classe jouée, sous la vie : son niveau et la part acquise du niveau en cours.
## Lue dans D6Profile.tree_view (aucun calcul ici), et seulement quand l'expérience de la descente
## a bougé. Comme les Âmes : rien en arène ni à l'entraînement (rien n'y est gagné).
func _actualiser_experience(game: Dictionary) -> void:
	experience.visible = not D6Js.truthy(game.get("sandbox")) and not D6Js.truthy(game.get("practice")) and game.meta.get("tree") is Dictionary
	if not experience.visible:
		return
	experience.custom_minimum_size.x = vie.custom_minimum_size.x
	var classe = game.meta.loadout.classId
	var lue: Array = [classe, game.telemetry.get("xpEarned", 0.0)]
	if lue == _xp_lue:
		return
	_xp_lue = lue
	var v: Dictionary = D6Profile.tree_view(game.meta, game.tuning, classe)
	niveau_classe.text = "NIV. %s" % D6Js.num_str(v.level)
	barre_xp.poser(v.xp / v.xpNext if v.xpNext > 0.0 else 1.0)

func _actualiser_centre(game: Dictionary) -> void:
	var info: Dictionary = game.info
	if D6Js.truthy(game.get("sandbox")):
		etage.text = "ARÈNE D'ESSAI"
		etage_total.visible = false
		cercle.text = "%s · %s" % [Accords.compte(game.telemetry.kills, "démon", "démons"), Accords.compte(game.telemetry.dodges, "esquive parfaite", "esquives parfaites")]
		cercle.visible = true
		fil.visible = false
		gardien.visible = false
		etage.add_theme_color_override("font_color", Couleurs.PAL.text)
		return
	var sur_gardien := D6Js.truthy(info.isBoss)
	etage.text = "ÉTAGE %s" % D6Js.num_str(info.floor)
	etage_total.text = "/ %s" % D6Js.num_str(game.tuning.floors.total)
	etage_total.visible = true
	etage.add_theme_color_override("font_color", Couleurs.PAL.danger if sur_gardien else Couleurs.PAL.text)
	var combat: bool = gardien.actualiser(game, marges.size.x)
	fil.visible = not combat
	cercle.visible = not combat
	fil.poser(info.indexInSection, game.tuning.floors.sectionLength)
	cercle.text = String(info.circleName)

func _actualiser_bourse(game: Dictionary) -> void:
	or_montant.text = D6Js.num_str(game.run.gold)
	# Âmes (permanentes) : on les voit monter pendant la descente, pas en arène ni à l'entraînement.
	ames.visible = not D6Js.truthy(game.get("sandbox")) and not D6Js.truthy(game.get("practice"))
	ames_montant.text = D6Js.num_str(game.meta.souls)

## Rend la ligne de visée à tracer au BUREAU ({de, dir, couleur}, ou vide) : au doigt, la vue des
## commandes tactiles trace la sienne.
func _actualiser_commandes(game: Dictionary, au_doigt: bool) -> Dictionary:
	bureau.visible = not au_doigt
	bande_basse.visible = not au_doigt
	tactile.visible = au_doigt
	var designee: String = accueil.commande(game) # la consigne de l'accueil nomme une commande : elle bat
	if au_doigt:
		tactile.actualiser(game, _interface_tactile(), designee, _heros_a_l_ecran(game))
		return {}
	var visee := {}
	for c in commandes_bureau:
		var etat: Dictionary = Etats.etat(game, c.id)
		var enfonce: bool = _enfonce.has(c.id)
		c.montrer(etat, enfonce)
		c.designer(c.id == designee)
		if enfonce and c.id in EMPLACEMENTS and etat.get("visee", false) and not etat.get("vide", false):
			visee = _visee_bureau(game)
	return visee

# ---------------------------------------------------------------- clavier et manette : retours

## Le retour « enfoncé » des boutons du bureau : la vue Entrees dit quand une commande vient d'être
## enfoncée (signal) et lesquelles sont tenues ; le bouton le montre au moins ENFONCE secondes.
func _suivre_appuis(delta: float) -> void:
	for id in _enfonce.keys():
		_enfonce[id] -= delta
		if _enfonce[id] <= 0.0:
			_enfonce.erase(id)
	var entrees = _entrees()
	if entrees == null or not entrees.has_signal("commande_enfoncee"):
		return
	if not entrees.commande_enfoncee.is_connected(enfoncer):
		entrees.commande_enfoncee.connect(enfoncer)
	for id in entrees.tenues():
		enfoncer(id)

## La commande `id` vient d'être enfoncée (clavier, souris, manette) : son bouton s'enfonce.
func enfoncer(id: String) -> void:
	_enfonce[id] = ENFONCE

## Les commandes dessinées enfoncées au bureau (pour les essais).
func enfoncees() -> Array:
	return _enfonce.keys()

## La ligne de visée d'un emplacement tenu au clavier ou à la manette : du héros vers la souris ou
## le stick droit. Vide en visée assistée (la simulation choisit la cible : rien à montrer).
func _visee_bureau(game: Dictionary) -> Dictionary:
	var entrees = _entrees()
	var dir: Vector2 = entrees.visee_bureau() if entrees != null and entrees.has_method("visee_bureau") else Vector2.ZERO
	if dir == Vector2.ZERO:
		return {}
	return {"de": _heros_a_l_ecran(game), "dir": dir, "couleur": Couleurs.PAL.lance}

## Où le déplacement de classe poserait le héros S'IL ÉTAIT RACCOURCI par une rivière ou un
## obstacle bas (position d'écran), sinon INF. Lecture seule : D6Player.move_view dit si le geste
## est prêt, D6Player.move_landing où il finirait dans le sens de la marche. Rien si la salle n'a
## pas de terrain bas, si le héros ne marche pas franchement, ou sans vue Monde.
func _arrivee_raccourcie(game: Dictionary) -> Vector2:
	var monde = app.vues.get("monde") if app.vues is Dictionary else null
	if monde == null or not monde.has_method("monde_vers_ecran") or game.room.get("low", []).is_empty():
		return Vector2.INF
	var p: Dictionary = game.player
	var norme: float = sqrt(p.moveX * p.moveX + p.moveY * p.moveY)
	if game.mode != "play" or p.state == "dash" or norme < EN_MARCHE or not D6Player.move_view(game).ready:
		return Vector2.INF
	var arrivee: Dictionary = D6Player.move_landing(game, p.moveX / norme, p.moveY / norme)
	return Vector2.INF if arrivee.full else monde.monde_vers_ecran(Vector2(arrivee.x, arrivee.y))

func _actualiser_reperes(game: Dictionary, au_doigt: bool) -> void:
	var room: Dictionary = game.room
	var objet = room.get("interact")
	var objet_libre: bool = objet is Dictionary and not D6Js.truthy(objet.get("used"))
	# Une indication à la fois : l'indice des portes se tait tant qu'une consigne de l'accueil parle.
	indice.visible = D6Js.truthy(room.get("cleared")) and not objet_libre and _porte_ouverte(room) and accueil.montree() == ""
	var monde = app.vues.get("monde") if app.vues is Dictionary else null
	var haut := centre.get_global_rect().end.y + BANDE_UTILE
	fleches.actualiser(game, monde, haut, _marges, tactile.coin() if au_doigt else racine.size)

## Où le héros est dessiné à l'écran (départ de la ligne de visée) ; sans vue Monde, le centre.
func _heros_a_l_ecran(game: Dictionary) -> Vector2:
	var monde = app.vues.get("monde") if app.vues is Dictionary else null
	if monde == null or not monde.has_method("monde_vers_ecran"):
		return racine.size / 2.0
	return monde.monde_vers_ecran(partie.position_dessin(game.player, true))

func _porte_ouverte(room: Dictionary) -> bool:
	for porte in room.get("doors", []):
		if D6Js.truthy(porte.get("open")):
			return true
	return false

# ---------------------------------------------------------------- présentation tactile

func _entrees():
	return app.vues.get("entrees") if app != null and app.vues is Dictionary else null

func _tactile() -> bool:
	if forcer_tactile:
		return true
	var entrees = _entrees()
	if entrees != null and entrees.has_method("tactile"):
		return entrees.tactile()
	return entrees == null and OS.has_feature("mobile")

## Disposition donnée par la vue Entrees ; sans elle, celle de repli (la même, calculée à part).
func _interface_tactile() -> Dictionary:
	var entrees = _entrees()
	if entrees != null and entrees.has_method("interface_tactile"):
		var ui = entrees.interface_tactile()
		if ui is Dictionary and ui.get("buttons") is Array and not ui.buttons.is_empty():
			return ui
	return Disposition.calculer(racine.size, _marges)
