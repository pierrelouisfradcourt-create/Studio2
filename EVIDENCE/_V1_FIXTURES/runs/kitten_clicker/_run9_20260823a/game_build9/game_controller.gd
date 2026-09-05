# game_controller.gd — CONTROLEUR RACINE (category godot.project_root : script racine
# attendu par les oracles, script de `main.tscn`). ASSEMBLE le jeu jouable :
#   - construit l'ecran (fond, galerie de raretes, pelote, boutons, HUD) ;
#   - charge les registres de monde AU BOOT (03_WORLD via world_content) ;
#   - instancie les adaptateurs ENTREE / PRESENTATION / AUDIO ;
#   - fait tourner la PRODUCTION dans `_process` (compteur de trames, aucune horloge).
#
# SEPARATION (garde-fou (c)) : toute la logique vit dans 05_SYSTEMS (pur). Ce controleur
# CAPTE (via input_adapter) et AFFICHE (labels/sprites), il ne recalcule aucune economie.
# DETERMINISME (garde-fou (b)) : la production avance d'un montant par trame rendue ; aucun
# randi/randf, aucun autoload, aucune static var economique — reinstancier `main.tscn` rend
# le meme HUD au boot.
extends Control

const Economy = preload("res://05_SYSTEMS/economy/economy.gd")
const Collection = preload("res://05_SYSTEMS/collection/collection.gd")
const Upgrades = preload("res://05_SYSTEMS/upgrades/upgrades.gd")
const Pricing = preload("res://05_SYSTEMS/pricing/pricing.gd")
const Decision = preload("res://05_SYSTEMS/decision/decision.gd")
const Progression = preload("res://05_SYSTEMS/progression/progression.gd")
const Goals = preload("res://05_SYSTEMS/goals/goals.gd")
const Prestige = preload("res://05_SYSTEMS/prestige/prestige.gd")
const WorldContent = preload("res://05_SYSTEMS/world_content/world_content.gd")
const Presentation = preload("res://06_RUNTIME/adapters/presentation/presentation.gd")
const InputAdapter = preload("res://06_RUNTIME/adapters/input_adapter/input_adapter.gd")
const Audio = preload("res://06_RUNTIME/adapters/audio/audio.gd")

const SPRITE_DIR: String = "res://04_ASSETS/sprites/"

var _state: Dictionary = {}
var _kittens: Array = []
var _places: Array = []
var _objects: Array = []
var _quests: Array = []

var _play_started: bool = false
var _tick: int = 0

var _hud: Dictionary = {}
var _hud_layer: Control = null
var _pelote: Control = null
var _input: InputAdapter = null
var _presentation: Presentation = null
var _audio: Audio = null
var _kitten_box: HBoxContainer = null
var _lieu2_box: HBoxContainer = null
var _branch_box: VBoxContainer = null
var _has_placer_jardin: bool = false
var _has_caresse: bool = false
var _lieu2_shown: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_state = Economy.initial_state()
	_load_registries()
	_build_background()
	_build_gallery()
	_build_containers()
	_build_pelote()
	_build_action_buttons()
	# Calque HUD dedie : evite toute collision de NOM entre un Label (ex. "prestige") et une
	# affordance de meme nom (le moteur renommerait l'un en "@Label@NN", non deterministe, et
	# casserait boot_reproducible). Les groupes "hud"/"affordance" restent globaux.
	_hud_layer = Control.new()
	_hud_layer.name = "HudLayer"
	_hud_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud_layer)
	_build_hud()
	# Presentation (feedback de clic) et audio (un son par evenement).
	_presentation = Presentation.new()
	add_child(_presentation)
	_audio = Audio.new()
	add_child(_audio)
	# input_adapter : CANAL D'ENTREE PUBLIC UNIQUE. Ajoute EN DERNIER pour que son `_input`
	# voie les evenements ; branche ses signaux vers audio/presentation/spawns.
	_input = InputAdapter.new()
	_input.setup(_state, _kittens)
	add_child(_input)
	_input.pelote_clicked.connect(_on_pelote)
	_input.kitten_adopted.connect(_on_kitten_adopted)
	_input.upgrade_bought.connect(_on_upgrade_bought)
	_input.prestiged.connect(_on_prestiged)
	_refresh()


# --- consommation amont (AU BOOT) ---------------------------------------------
func _load_registries() -> void:
	_kittens = WorldContent.kittens()
	_places = WorldContent.places()
	_objects = WorldContent.objects()
	_quests = WorldContent.quests()


# --- construction de l'ecran ---------------------------------------------------
func _build_background() -> void:
	var bg := TextureRect.new()
	var res = load(SPRITE_DIR + "refuge.svg")
	if res != null:
		bg.texture = res
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


# Galerie de TOUTES les raretes du registre : rend >=2 raretes visuellement distinctes des
# le boot (identite visuelle par rarete). Non-monochrome garanti (couleurs de halo variees).
func _build_gallery() -> void:
	var box := HBoxContainer.new()
	box.position = Vector2(40, 360)
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_to_group("gallery")
	add_child(box)
	for k in _kittens:
		if k is Dictionary:
			box.add_child(Presentation.make_kitten_sprite(k))


func _build_containers() -> void:
	_kitten_box = HBoxContainer.new()
	_kitten_box.position = Vector2(40, 300)
	_kitten_box.add_theme_constant_override("separation", 4)
	_kitten_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_kitten_box)
	_lieu2_box = HBoxContainer.new()
	_lieu2_box.position = Vector2(360, 300)
	_lieu2_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lieu2_box)
	_branch_box = VBoxContainer.new()
	_branch_box.position = Vector2(470, 210)
	_branch_box.add_theme_constant_override("separation", 6)
	_branch_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_branch_box)


func _build_pelote() -> void:
	_pelote = _make_affordance("pelote", Vector2(250, 150), Vector2(150, 150),
		SPRITE_DIR + "pelote.svg", "")
	_pelote.add_theme_constant_override("h_separation", 0)


# Une affordance = un Control (groupe "affordance") nomme, cliquable, avec un fond de sprite
# et un libelle. Ce sont ces noeuds que la sonde/le bot trouvent par leur nom.
func _make_affordance(nom: String, pos: Vector2, taille: Vector2, sprite_path: String,
		libelle: String) -> Control:
	var ctrl := Panel.new()
	ctrl.name = nom
	ctrl.position = pos
	ctrl.size = taille
	ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
	ctrl.add_to_group("affordance")
	var res = load(sprite_path)
	if res != null:
		var tex := TextureRect.new()
		tex.texture = res
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ctrl.add_child(tex)
	if libelle != "":
		var l := Label.new()
		l.text = libelle
		l.position = Vector2(6, 8)
		l.add_theme_color_override("font_color", Color(0.35, 0.24, 0.17))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ctrl.add_child(l)
	add_child(ctrl)
	return ctrl


func _build_action_buttons() -> void:
	_make_affordance("acheter_chaton", Vector2(460, 60), Vector2(168, 40),
		SPRITE_DIR + "ui_action_buttons.svg", "Adopter un chaton")
	_make_affordance("acheter_amelioration", Vector2(460, 108), Vector2(168, 40),
		SPRITE_DIR + "ui_action_buttons.svg", "Ameliorer la pelote")
	_make_affordance("prestige", Vector2(460, 156), Vector2(168, 40),
		SPRITE_DIR + "ui_action_buttons.svg", "Prestige")


func _make_label(nom: String, pos: Vector2, w: float, group: String) -> Label:
	var l := Label.new()
	l.name = nom
	l.position = pos
	l.size = Vector2(w, 20)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", Color(0.35, 0.24, 0.17))
	if group != "":
		l.add_to_group(group)
	_hud_layer.add_child(l)
	return l


func _build_hud() -> void:
	# Labels du groupe "hud", nommes EXACTEMENT comme les cles lues par loop.json.
	var objectif := _make_label("objectif", Vector2(12, 8), 616, "hud")
	objectif.add_theme_font_size_override("font_size", 15)
	_hud["objectif"] = objectif
	var rows := [["ronrons", 34.0], ["taux", 56.0], ["collection", 78.0], ["prestige", 100.0]]
	for r in rows:
		_hud[String(r[0])] = _make_label(String(r[0]), Vector2(12, float(r[1])), 340, "hud")
	# Labels cout_/effet_ a cote de chaque bouton d'achat (maillon DECISION INFORMATION).
	_hud["cout_acheter_chaton"] = _make_label("cout_acheter_chaton", Vector2(460, 44), 168, "hud")
	_hud["effet_acheter_chaton"] = _make_label("effet_acheter_chaton", Vector2(460, 100), 220, "hud")
	_hud["cout_acheter_amelioration"] = _make_label("cout_acheter_amelioration", Vector2(460, 148), 168, "hud")
	_hud["effet_acheter_amelioration"] = _make_label("effet_acheter_amelioration", Vector2(460, 196), 220, "hud")


# --- handlers d'evenements (branches sur les signaux de l'input_adapter) -------
func _on_pelote(gain: int) -> void:
	_play_started = true
	if _presentation != null and _pelote != null:
		_presentation.pop(_pelote.get_global_rect().get_center(), gain)
	if _audio != null:
		_audio.play_cue(Audio.CUE_CLICK, _tick)
	_refresh()


func _on_kitten_adopted(index: int) -> void:
	if _audio != null:
		_audio.play_cue(Audio.CUE_PURCHASE, _tick)
	if index >= 0 and index < _kittens.size():
		_kitten_box.add_child(Presentation.make_kitten_sprite(_kittens[index]))
	# Branche ADOPTER : fait apparaitre l'affordance PROPRE `placer_au_jardin`.
	if not _has_placer_jardin:
		_has_placer_jardin = true
		_spawn_branch_affordance("placer_au_jardin", "Place ton chaton au jardin")
	# Deblocage du second lieu au palier requis : fait apparaitre un noeud du groupe "lieu_2".
	if not _lieu2_shown and Progression.lieu2_unlocked(_state, _places):
		_lieu2_shown = true
		if _audio != null:
			_audio.play_cue(Audio.CUE_UNLOCK, _tick)
		var node := TextureRect.new()
		var res = load(SPRITE_DIR + "lieu_2.svg")
		if res != null:
			node.texture = res
		node.custom_minimum_size = Vector2(64, 64)
		node.size = Vector2(64, 64)
		node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.add_to_group("lieu_2")
		_lieu2_box.add_child(node)
	_refresh()


func _on_upgrade_bought(_level: int) -> void:
	if _audio != null:
		_audio.play_cue(Audio.CUE_PURCHASE, _tick)
	# Branche AMELIORER : fait apparaitre l'affordance PROPRE `caresse_longue`.
	if not _has_caresse:
		_has_caresse = true
		_spawn_branch_affordance("caresse_longue", "Tente une caresse longue")
	_refresh()


func _spawn_branch_affordance(nom: String, libelle: String) -> void:
	var ctrl := Panel.new()
	ctrl.name = nom
	ctrl.custom_minimum_size = Vector2(168, 30)
	ctrl.size = Vector2(168, 30)
	ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
	ctrl.add_to_group("affordance")
	var l := Label.new()
	l.text = libelle
	l.position = Vector2(6, 4)
	l.add_theme_color_override("font_color", Color(0.35, 0.24, 0.17))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctrl.add_child(l)
	_branch_box.add_child(ctrl)


func _on_prestiged() -> void:
	if _audio != null:
		_audio.play_cue(Audio.CUE_PRESTIGE, _tick)
	_refresh()


# --- boucle et affichage -------------------------------------------------------
func _process(_delta: float) -> void:
	_tick += 1
	if _input != null:
		_input.set_tick(_tick)
	if _play_started:
		var rate: float = Collection.passive_rate(_state, _kittens)
		var mult: float = float(Prestige.production_multiplier(_state))
		Economy.production_tick(_state, rate, mult)
	_refresh()


func _taux_par_sec() -> float:
	return Collection.passive_rate(_state, _kittens) * float(Prestige.production_multiplier(_state)) * Economy.PASSIVE_UNIT


func _refresh() -> void:
	var ronrons: int = Economy.total(_state)
	_hud["objectif"].text = Goals.objective(_state, _places, ronrons)
	_hud["ronrons"].text = "Ronrons : %d" % ronrons
	_hud["taux"].text = "Ronron/s : %.1f" % _taux_par_sec()
	_hud["collection"].text = "Chatons : %d" % Collection.count(_state)
	_hud["prestige"].text = "Prestige : %d" % Prestige.bonus(_state)
	_hud["cout_acheter_chaton"].text = "Cout : %d" % Decision.cost(_state, "acheter_chaton")
	_hud["effet_acheter_chaton"].text = Decision.effect_text(_state, _kittens, "acheter_chaton")
	_hud["cout_acheter_amelioration"].text = "Cout : %d" % Decision.cost(_state, "acheter_amelioration")
	_hud["effet_acheter_amelioration"].text = Decision.effect_text(_state, _kittens, "acheter_amelioration")
