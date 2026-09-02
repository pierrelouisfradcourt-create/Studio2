# v2_input_device_translation.gd — ligne input.device_translation, capacite F76.
# L'adaptateur traduit les evenements du peripherique en INTENTION du vocabulaire ferme
# par LECTURE de la table de liaisons — et rien d'autre. Plus aucune table de codes de
# touches n'est ecrite ici.
# CONTROLE POSITIF OBLIGATOIRE : les memes references aux API d'entree SONT trouvees
# dans 06_RUNTIME, faute de quoi le comptage ne prouve rien.
extends RefCounted

const Intents = preload("res://05_SYSTEMS/input_intents/input_intents.gd")
const Bindings = preload("res://06_RUNTIME/adapters/input_bindings/input_bindings.gd")
const InputAdapter = preload("res://06_RUNTIME/adapters/input_adapter/input_adapter.gd")
const Purity = preload("res://06_RUNTIME/adapters/proof_harness/harness_purity_counts.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))


func run(h) -> void:
	# CONTROLE POSITIF : les references d'entree existent bien dans le runtime.
	var dans_runtime: Array = Purity.entree_dans_runtime()
	h.gt(dans_runtime.size(), 0, "input.translation: les API d'entree sont trouvees dans le runtime")
	h.eq(Purity.entree_dans_logique().size(), 0, "input.translation: et absentes de la logique")

	# PLUS AUCUNE TABLE de codes dans l'adaptateur : il LIT la table.
	var f := FileAccess.open("res://06_RUNTIME/adapters/input_adapter/input_adapter.gd", FileAccess.READ)
	var texte: String = Purity.code_seul(f.get_as_text() if f != null else "")
	h.eq(texte.contains("KEY_UP"), false, "input.translation: aucun code de touche ecrit ici")
	h.eq(texte.contains("KEY_LEFT"), false, "input.translation: aucun autre non plus")
	h.eq(texte.contains("Bindings."), true, "input.translation: la table est lue")

	# TRADUCTION : les trois peripheriques donnent la MEME sortie pour la MEME intention.
	var touche: int = Bindings.liaisons(Intents.Intention.GAUCHE, Bindings.CLAVIER)[0]
	var bouton: int = Bindings.liaisons(Intents.Intention.GAUCHE, Bindings.MANETTE)[0]
	var zone: String = Bindings.liaisons(Intents.Intention.GAUCHE, Bindings.TACTILE)[0]
	h.eq(InputAdapter.traduire(touche)["genre"], "direction", "input.translation: genre clavier")
	h.eq(InputAdapter.traduire_bouton(bouton)["genre"], "direction", "input.translation: genre manette")
	h.eq(InputAdapter.traduire_zone(zone)["genre"], "direction", "input.translation: genre tactile")
	h.eq(InputAdapter.traduire(touche)["direction"], MazeClass.GAUCHE, "input.translation: direction clavier")
	h.eq(InputAdapter.traduire_bouton(bouton)["direction"], MazeClass.GAUCHE, "input.translation: direction manette")
	h.eq(InputAdapter.traduire_zone(zone)["direction"], MazeClass.GAUCHE, "input.translation: direction tactile")

	# HORS VOCABULAIRE : jamais une exception, jamais un effet de bord.
	h.eq(InputAdapter.traduire(KEY_F13)["genre"], "aucune", "input.translation: touche non liee")
	h.eq(InputAdapter.traduire_bouton(99)["genre"], "aucune", "input.translation: bouton non lie")
	h.eq(InputAdapter.traduire_zone("zone_absente")["genre"], "aucune", "input.translation: zone non liee")
	h.eq(InputAdapter.direction_de_touche(KEY_F13), MazeClass.AUCUNE, "input.translation: aucune direction")
	h.eq(InputAdapter.normaliser_direction(Vector2i(5, 5)), MazeClass.AUCUNE, "input.translation: valeur hors vocabulaire normalisee")

	# LE RANG fait le lien avec l'ordre fixe des directions : une source unique.
	h.eq(InputAdapter.direction_de_intention(Intents.Intention.HAUT), MazeClass.HAUT, "input.translation: rang 0")
	h.eq(InputAdapter.direction_de_intention(Intents.Intention.DROITE), MazeClass.DROITE, "input.translation: rang 3")
	h.eq(InputAdapter.direction_de_intention(Intents.Intention.PAUSE), MazeClass.AUCUNE, "input.translation: une commande n'est pas une direction")
