# v2_contacts_dash_unchanged_by_design.test.gd — ligne contacts.dash_unchanged_by_design, F85/F86.
# Ce module NE CONNAIT PAS LE DASH : un deplacement de dash traverse le MEME test de
# contact que n'importe quel autre. C'est la raison STRUCTURELLE de la declaration
# « comportement face aux fantomes : inchange par conception ».
extends RefCounted

const Contacts = preload("res://05_SYSTEMS/contacts/contacts.gd")
const Dash = preload("res://05_SYSTEMS/dash/dash.gd")
const Mesure = preload("res://06_RUNTIME/adapters/proof_harness/harness_dash_measurement.gd")
const Purity = preload("res://06_RUNTIME/adapters/proof_harness/harness_purity_counts.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))


func run(h) -> void:
	# RAISON STRUCTURELLE : le module ne reference jamais le dash.
	var f := FileAccess.open("res://05_SYSTEMS/contacts/contacts.gd", FileAccess.READ)
	h.ok(f != null, "contacts.dash: le module est lisible")
	var texte: String = Purity.code_seul(f.get_as_text() if f != null else "")
	h.eq(texte.contains("Dash"), false, "contacts.dash: aucune reference au dash")
	h.eq(texte.contains("budget"), false, "contacts.dash: aucune notion de budget de pas")
	h.eq(texte.contains("dash_recharge"), false, "contacts.dash: aucun champ de dash")

	# MEME TEST DE CONTACT : la detection ne prend aucun budget en entree.
	var touches: Array = Contacts.detecter(
		Vector2i(1, 1), Vector2i(4, 1),
		[Vector2i(4, 1), Vector2i(9, 9), Vector2i(9, 9), Vector2i(9, 9)],
		[Vector2i(4, 1), Vector2i(9, 9), Vector2i(9, 9), Vector2i(9, 9)],
		[true, true, true, true])
	h.eq(touches.size(), 1, "contacts.dash: un contact de fin de tick est detecte")
	h.eq(touches[0], 0, "contacts.dash: le fantome touche est nomme")
	var aucun: Array = Contacts.detecter(
		Vector2i(1, 1), Vector2i(4, 1),
		[Vector2i(9, 9), Vector2i(9, 9), Vector2i(9, 9), Vector2i(9, 9)],
		[Vector2i(9, 9), Vector2i(9, 9), Vector2i(9, 9), Vector2i(9, 9)],
		[true, true, true, true])
	h.eq(aucun.size(), 0, "contacts.dash: aucun contact quand personne ne se croise")

	# LA MESURE CONFIRME la declaration, elle ne la fonde pas.
	h.eq(Dash.EFFETS_DECLARES["comportement_fantomes"], Dash.INCHANGE, "contacts.dash: declare inchange")
	var r: Dictionary = Mesure.releves(Maze)
	h.eq(r["comportement_fantomes"]["avec"], r["comportement_fantomes"]["sans"],
		"contacts.dash: mesure egale avec et sans dash")
	h.eq(Mesure.ecarts_a_la_declaration(Maze).has("comportement_fantomes"), false,
		"contacts.dash: aucun ecart a la declaration sur cette grandeur")
