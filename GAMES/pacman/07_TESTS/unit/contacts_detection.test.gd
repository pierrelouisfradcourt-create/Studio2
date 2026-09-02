# contacts_detection.test.gd — ligne contacts.detection, capacite F34.
# Invariant de collision soumis au gate de mutation : un mutant qui ne detecte pas
# l'ECHANGE de cases sur une meme arete doit etre tue par la fixture de croisement en
# sens inverse.
extends RefCounted

const Contacts = preload("res://05_SYSTEMS/contacts/contacts.gd")


func run(h) -> void:
	var dehors: Array = [true, true, true, true]

	# (a) MEME CASE en fin de tick.
	var meme: Array = Contacts.detecter(
		Vector2i(5, 5), Vector2i(6, 5),
		[Vector2i(8, 5), Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)],
		[Vector2i(6, 5), Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)], dehors)
	h.eq(meme, [0], "contacts.detect: meme case en fin de tick")

	# (b) ECHANGE de cases sur la MEME ARETE (croisement en sens inverse). Sans cette
	# detection, les deux entites se traversent et le contact est manque.
	var echange: Array = Contacts.detecter(
		Vector2i(5, 5), Vector2i(6, 5),
		[Vector2i(6, 5), Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)],
		[Vector2i(5, 5), Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)], dehors)
	h.eq(echange, [0], "contacts.detect: echange de cases sur la meme arete")

	# Aucun contact : trajectoires disjointes.
	var aucun: Array = Contacts.detecter(
		Vector2i(5, 5), Vector2i(6, 5),
		[Vector2i(9, 9), Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)],
		[Vector2i(9, 8), Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)], dehors)
	h.eq(aucun, [], "contacts.detect: aucun contact sur trajectoires disjointes")

	# Croisement PARALLELE (meme direction) : ce n'est PAS un echange d'arete.
	var parallele: Array = Contacts.detecter(
		Vector2i(5, 5), Vector2i(6, 5),
		[Vector2i(7, 5), Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)],
		[Vector2i(8, 5), Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)], dehors)
	h.eq(parallele, [], "contacts.detect: suivre dans le meme sens n'est pas un contact")

	# Un fantome DANS la maison n'est jamais en contact, meme sur la meme case.
	var dedans: Array = [false, false, false, false]
	var maison: Array = Contacts.detecter(
		Vector2i(5, 5), Vector2i(6, 5),
		[Vector2i(6, 5), Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)],
		[Vector2i(6, 5), Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)], dedans)
	h.eq(maison, [], "contacts.detect: un fantome en maison n'est pas en contact")

	# Plusieurs fantomes au meme tick : tous rapportes, dans l'ordre fixe des index.
	var multiples: Array = Contacts.detecter(
		Vector2i(5, 5), Vector2i(6, 5),
		[Vector2i(6, 5), Vector2i(9, 9), Vector2i(6, 5), Vector2i(1, 1)],
		[Vector2i(5, 5), Vector2i(9, 9), Vector2i(6, 5), Vector2i(1, 1)], dehors)
	h.eq(multiples, [0, 2], "contacts.detect: plusieurs contacts, ordre fixe des index")

	# Pac-Man immobile et fantome qui arrive sur sa case : contact.
	var immobile: Array = Contacts.detecter(
		Vector2i(5, 5), Vector2i(5, 5),
		[Vector2i(6, 5), Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)],
		[Vector2i(5, 5), Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)], dehors)
	h.eq(immobile, [0], "contacts.detect: le fantome vient sur un Pac-Man immobile")
