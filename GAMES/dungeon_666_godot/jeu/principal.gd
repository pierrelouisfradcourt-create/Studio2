extends Node
## Racine de l'application : écran titre → Ville → descente, profil permanent, réglages.
## Portage du câblage de GAMES/dungeon_666/src/main.mjs (startRun, openTown, townOp, persistMeta).
##
## Ce nœud ne dessine rien et ne contient aucune règle de jeu. Il monte les vues (une scène par
## rôle, voir jeu/ARCHITECTURE.md), les branche sur la partie, et offre aux écrans les ACTIONS
## du joueur. Les vues lisent `app.profil`, `app.reglages`, `partie.game` ; elles n'écrivent que
## par les fonctions ci-dessous.

signal ecran_change(ecran: String) ## titre | ville | jeu
signal profil_change ## le profil permanent a changé (achat, équipement, retour de descente)
signal reglages_change

const Partie = preload("res://jeu/partie.gd")
const Profil = preload("res://jeu/profil.gd")
## Les vues, dans l'ordre de montage (dessous → dessus). Une vue absente est simplement ignorée.
const VUES := [
	"res://jeu/monde/monde.tscn",
	"res://jeu/effets/effets.tscn",
	"res://jeu/son/son.tscn",
	"res://jeu/interface/hud.tscn",
	"res://jeu/entrees/entrees.tscn",
	"res://jeu/ville/ville.tscn",
	"res://jeu/ecrans/ecrans.tscn",
]
const OPERATIONS_VILLE := ["select_class", "unlock", "select_skill", "select_gadget", "equip_from_stash", "salvage_from_stash", "buy_upgrade"]

var ecran := "titre"
var profil: Dictionary = {}
var reglages: Dictionary = {}
## Registre du contenu (classes, armes, prix…) pour les opérations de la Ville : un tuning neuf.
var contenu: Dictionary = {}
var partie: Node
var vues: Dictionary = {} # nom de la scène (« monde », « hud »…) -> nœud

func _ready() -> void:
	contenu = D6Data.create_tuning()
	profil = Profil.charger(contenu)
	reglages = Profil.charger_reglages()
	partie = Partie.new()
	partie.name = "Partie"
	add_child(partie)
	partie.profil_a_enregistrer.connect(enregistrer_profil)
	partie.mode_change.connect(_sur_mode)
	for chemin in VUES:
		_monter(chemin)
	if vues.has("entrees") and vues.entrees.has_method("lire"):
		partie.entrees = vues.entrees.lire
	ecran_change.emit(ecran)

func _monter(chemin: String) -> void:
	if not ResourceLoader.exists(chemin):
		return
	var vue: Node = (load(chemin) as PackedScene).instantiate()
	add_child(vue)
	vues[chemin.get_file().get_basename()] = vue
	if vue.has_method("brancher"):
		vue.brancher(self, partie)

# ---------------------------------------------------------------- écrans

func ouvrir_titre() -> void:
	partie.arreter()
	_changer_ecran("titre")

func ouvrir_ville() -> void:
	partie.arreter()
	_changer_ecran("ville")

## Descente depuis `etage` (un checkpoint). `arene` : arène d'essai ; `entrainement` : Gardien sans enjeu.
func demarrer_descente(etage: float, arene: bool = false, entrainement: bool = false, graine: float = -1.0) -> void:
	var options := {
		"seed": graine if graine >= 0.0 else float(randi()),
		"startFloor": 1.0 if arene else etage,
		"meta": profil,
		"sandbox": arene,
		"practice": entrainement,
		"tuning": {"lab": reglages.lab.duplicate()},
	}
	partie.demarrer(options)
	_changer_ecran("jeu")

## Entraînement : le Gardien choisi, à l'étage de sa première section, sans récompense ni risque.
func demarrer_entrainement(gardien: String) -> void:
	var sections: float = contenu.floors.total / contenu.floors.sectionLength
	var section := 1.0
	while section <= sections and D6Floors.guardian_for(contenu, section) != gardien:
		section += 1.0
	demarrer_descente(D6Floors.section_bounds(contenu, section).guardian, false, true)

func _changer_ecran(nouveau: String) -> void:
	ecran = nouveau
	ecran_change.emit(ecran)

# ---------------------------------------------------------------- en partie

func commande(cmd: Dictionary) -> bool:
	var ok: bool = partie.commande(cmd)
	_apres_commande()
	return ok

func abandonner() -> void:
	partie.en_pause = false
	commande({"type": "abandon"})

func mettre_en_pause(pause: bool) -> void:
	if partie.game != null and partie.game.mode == "play":
		partie.en_pause = pause

func _apres_commande() -> void:
	enregistrer_profil()
	_sur_mode(partie.game.mode if partie.game != null else "")

## Fin du run (portail du checkpoint, écran de mort ou de victoire, abandon) : retour en Ville.
func _sur_mode(mode: String) -> void:
	if mode == "town":
		enregistrer_profil()
		ouvrir_ville()

# ---------------------------------------------------------------- profil et Ville

## Recopie le profil de la partie (permanent) et l'enregistre. Jamais en arène ni à l'entraînement.
func enregistrer_profil() -> void:
	var g = partie.game
	if g != null and not D6Js.truthy(g.get("sandbox")) and not D6Js.truthy(g.get("practice")):
		profil = D6Js.clone(g.meta)
	Profil.enregistrer(profil)
	profil_change.emit()

## Opération de la Ville sur le profil (règles : D6Profile), puis enregistrement.
## `nom` : select_class | unlock | select_skill | select_gadget | equip_from_stash |
## salvage_from_stash | buy_upgrade ; `args` : les arguments après (profil, contenu).
## Rend le résultat de l'opération ({ok, reason?…}).
func operation_ville(nom: String, args: Array = []) -> Dictionary:
	if not (nom in OPERATIONS_VILLE):
		return {"ok": false, "reason": "opération inconnue"}
	var res = Callable(D6Profile, nom).callv([profil, contenu] + args)
	if res is Dictionary and D6Js.truthy(res.get("ok")):
		Profil.enregistrer(profil)
	profil_change.emit()
	return res if res is Dictionary else {"ok": false}

# ---------------------------------------------------------------- réglages

func regler(cle: String, valeur) -> void:
	reglages[cle] = valeur
	Profil.enregistrer_reglages(reglages)
	reglages_change.emit()

## Variante du labo du feel (D5 / D8 / D9) : retenue, et appliquée à la partie en cours.
func regler_labo(axe: String, choix: String) -> void:
	var axes: Dictionary = D6Data.tables().lab.LAB_AXES
	if not axes.has(axe) or not axes[axe].options.has(choix):
		return
	reglages.lab[axe] = choix
	Profil.enregistrer_reglages(reglages)
	if partie.game != null:
		D6Lab.set_lab(partie.game.tuning, axe, choix)
	reglages_change.emit()
