# scene.gd — pilote de la scene principale (res://06_RUNTIME/main.tscn). Node2D qui
# ASSEMBLE les adaptateurs deja prouves dans un arbre de scene vivant : il ne contient
# AUCUNE regle de jeu, il branche des briques pures.
#
# Adaptateur de presentation/runtime (systeme runtime_loop) : il connait la scene, l'horloge
# et l'entree du moteur — c'est precisement son role. La logique PURE (etat, tick, collision,
# pause, relance, meilleur score) reste dans 05_SYSTEMS et ne connait rien de ce fichier :
# dependance a sens unique (garde-fou c). Aucun litteral de GAMEPLAY ici — toutes les valeurs
# de jeu viennent de params.gd ; seules CELL_PX / BAND_H / SEED_INITIAL sont des constantes de
# PRESENTATION ou de determinisme, jamais des reglages d'equilibrage (garde-fou d).
extends Node2D

# --- Briques pures (05_SYSTEMS) : consommees, jamais reecrites ---
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const Pause = preload("res://05_SYSTEMS/game_state/pause.gd")
const Restart = preload("res://05_SYSTEMS/game_state/restart.gd")
const BestScore = preload("res://05_SYSTEMS/best_score/best_score.gd")
const DebugState = preload("res://05_SYSTEMS/debug_state/debug_state.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

# --- Adaptateurs (06_RUNTIME) : consommes, jamais reecrits ---
const Boot = preload("res://06_RUNTIME/adapters/runtime_loop/boot.gd")
const Exit = preload("res://06_RUNTIME/adapters/runtime_loop/exit.gd")
const RuntimeLoop = preload("res://06_RUNTIME/adapters/runtime_loop/runtime_loop.gd")
const InputAdapter = preload("res://06_RUNTIME/adapters/input_adapter/input_adapter.gd")
const GridView = preload("res://06_RUNTIME/adapters/presentation/grid_view.gd")
const Hud = preload("res://06_RUNTIME/adapters/presentation/hud.gd")
const EndScreen = preload("res://06_RUNTIME/adapters/presentation/end_screen.gd")
const PausePanel = preload("res://06_RUNTIME/adapters/presentation/pause_panel.gd")
const BestScoreStore = preload("res://06_RUNTIME/adapters/best_score_store/best_score_store.gd")
const DebugProbe = preload("res://06_RUNTIME/adapters/debug_probe/debug_probe.gd")

# --- Constantes de PRESENTATION (pas de gameplay) ---
const CELL_PX := 32          # cote d'une case a l'ecran ; 20 * 32 = 640 = largeur du viewport
const BAND_H := 40           # hauteur du bandeau HUD en haut (680 - 640)
# --- Graine de determinisme (pas un parametre d'equilibrage) ---
const SEED_INITIAL := 1

var _state                   # etat de partie PUR (State) — la seule source de verite du jeu
var _record: int = 0         # meilleur score, HORS de l'etat de partie (etancheite)
var _accum_ms: float = 0.0   # accumulateur du cadenceur (borne a 1 tick/trame, sans rattrapage)
var _pending: Vector2i = Loop.AUCUNE   # direction demandee, profondeur 1 (derniere gagne)
var _store                   # best_score_store : SEULE I/O du produit
var _hud_label: Label
var _pause_label: Label
var _end_label: Label


func _ready() -> void:
	_store = BestScoreStore.new()
	_record = _store.charger()                 # record persistant (0 si absent/corrompu)
	_state = Boot.etat_initial(SEED_INITIAL)    # etat initial ATTEINT sans aucun geste
	_construire_labels()
	_rafraichir_labels()
	_emettre_recu()                             # constate l'etat initial sur le canal public
	queue_redraw()


# Rendu de la grille par primitives du moteur (aucun asset). Lit l'etat, ne decide rien.
func _draw() -> void:
	var largeur: int = P.TAILLE_GRILLE * CELL_PX
	# Fond du bandeau HUD + fond du plateau (couleur VIDE de grid_view : reutilisee, pas
	# un nouveau litteral de couleur).
	var fond := GridView.couleur(GridView.Cat.VIDE)
	draw_rect(Rect2(0, 0, largeur, BAND_H + largeur), fond)
	# Cases occupees uniquement (tete, corps, nourriture) ; le fond VIDE reste visible en
	# quadrillage grace a l'inset d'1 px -> lisibilite de la grille.
	for x in range(P.TAILLE_GRILLE):
		for y in range(P.TAILLE_GRILLE):
			var cat := GridView.categorie_cellule(_state, Vector2i(x, y))
			if cat == GridView.Cat.VIDE:
				continue
			var px := x * CELL_PX
			var py := BAND_H + y * CELL_PX
			draw_rect(Rect2(px + 1, py + 1, CELL_PX - 2, CELL_PX - 2), GridView.couleur(cat))


# Cadenceur : le moteur fournit le delta reel ; runtime_loop le convertit en 0 ou 1 tick,
# SANS rattrapage. En pause ou apres la fin, aucun temps n'est accumule (frozen).
func _process(delta: float) -> void:
	var en_cours: bool = _state.statut == State.Statut.EN_COURS
	var res: Dictionary = RuntimeLoop.avancer(_accum_ms, delta * 1000.0, _state.periode, not en_cours)
	_accum_ms = res["accumulateur"]
	if res["ticks"] != 1:
		return
	# ticks == 1 implique en_cours (sinon avancer aurait renvoye 0 via le gel).
	var avant: int = _state.statut
	var sortie: Dictionary = Loop.step(_state, _pending)   # tick PUR ; applique la demande
	_state = sortie["etat"]
	_pending = Loop.AUCUNE                                  # profondeur 1 : demande consommee
	if avant == State.Statut.EN_COURS and _state.statut != State.Statut.EN_COURS:
		_sur_fin_de_partie()
	_emettre_recu()
	_rafraichir_labels()
	queue_redraw()


# Entree du moteur -> canal PUBLIC (le meme que le bot). L'adaptateur traduit, la logique
# pure decide. Directions : bufferisees (profondeur 1). Commandes : appliquees tout de suite.
func _input(event: InputEvent) -> void:
	var keycode := InputAdapter.keycode_de_event(event)
	if keycode == -1:
		return
	var action := InputAdapter.traduire_keycode(keycode)
	match action.get("kind"):
		"direction":
			_pending = action["dir"]
		"commande":
			_traiter_commande(action["commande"])


func _traiter_commande(commande: String) -> void:
	match commande:
		InputAdapter.CMD_PAUSE:
			Pause.basculer(_state)              # transition pure en-cours <-> en-pause
			_rafraichir_labels()
			queue_redraw()
		InputAdapter.CMD_RELANCE:
			_state = Restart.relancer(SEED_INITIAL)   # etat neuf ; le record survit seul
			_accum_ms = 0.0
			_pending = Loop.AUCUNE
			_emettre_recu()
			_rafraichir_labels()
			queue_redraw()
		InputAdapter.CMD_SORTIE:
			_quitter()


# Fin de partie : le record se met a jour au passage terminal (max pur), puis est ecrit.
func _sur_fin_de_partie() -> void:
	var nouveau := BestScore.mettre_a_jour(_record, _state.score)
	if nouveau != _record:
		_record = nouveau
		_store.enregistrer(_record)


# Sortie OBSERVABLE : record sauve, dernier recu emis, puis le processus se termine (code 0).
func _quitter() -> void:
	var nouveau := BestScore.mettre_a_jour(_record, _state.score)
	if nouveau != _record:
		_record = nouveau
		_store.enregistrer(_record)
	_emettre_recu()
	get_tree().quit(Exit.CODE_SORTIE)


func _construire_labels() -> void:
	_hud_label = Label.new()
	_hud_label.position = Vector2(8, 8)
	add_child(_hud_label)

	var largeur: int = P.TAILLE_GRILLE * CELL_PX
	_pause_label = Label.new()
	_pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_label.size = Vector2(largeur, 32)
	_pause_label.position = Vector2(0, BAND_H + largeur / 2 - 16)
	add_child(_pause_label)

	_end_label = Label.new()
	_end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_label.size = Vector2(largeur, 96)
	_end_label.position = Vector2(0, BAND_H + largeur / 2 - 48)
	add_child(_end_label)


# Le texte affiche et l'etat expose sont STRICTEMENT egaux (hud.gd garantit le re-parse).
func _rafraichir_labels() -> void:
	_hud_label.text = Hud.texte_score(_state.score) + "     " + Hud.texte_meilleur(_record)
	var statut: int = _state.statut
	_pause_label.text = PausePanel.MENTION_PAUSE if PausePanel.mentions_pause(statut) > 0 else ""
	if EndScreen.est_actif(statut):
		var recap: Dictionary = EndScreen.recap(_state)
		_end_label.text = "%s\n%s\n[R] Rejouer   [Echap] Quitter" % [
			EndScreen.message(statut), Hud.texte_score(recap["score"])
		]
	else:
		_end_label.text = ""


# Canal d'observation public : projette l'etat deja tenu et l'emet ligne-a-ligne sur stdout.
func _emettre_recu() -> void:
	DebugProbe.emettre(DebugState.projeter(_state, _record))
