# no_time_catchup.test.gd — ligne runtime.fixed_step_accumulator. L'accumulateur a pas FIXE
# RETRANCHE un pas entier par tick et CONSERVE le reste fractionnaire : une meme duree cumulee
# produit le meme nombre de ticks quel que soit le decoupage des trames (propriete DURABLE,
# independante du framerate). Le rattrapage est BORNE par un plafond nomme ; au-dela, le surplus
# est jete. Ce test INVERSE la propriete figee de l'ancien cadenceur (« au plus 1 tick, reste
# jete a chaque appel »), qui rendait le nombre de ticks/seconde dependant du framerate (F1).
extends RefCounted

const RL = preload("res://06_RUNTIME/adapters/runtime_loop/runtime_loop.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

func run(h) -> void:
	var pas: float = RL.pas_ms()
	var cap: int = P.MAX_TICKS_PAR_FRAME

	# (1) delta < pas -> 0 tick, temps sous le pas CONSERVE (jamais jete).
	var r1: Dictionary = RL.avancer(0.0, pas / 2.0, false)
	h.eq(r1["ticks"], 0, "delta < pas -> 0 tick")
	h.eq(r1["accumulateur"], pas / 2.0, "temps sous le pas conserve dans l'accumulateur")

	# (2) accumulateur == pas -> EXACTEMENT 1 tick ; le reste vaut 0 parce qu'un pas ENTIER a ete
	#     RETRANCHE (et non parce qu'on remet arbitrairement a 0).
	var r2: Dictionary = RL.avancer(pas / 2.0, pas / 2.0, false)
	h.eq(r2["ticks"], 1, "accumulateur == pas -> exactement 1 tick")
	h.eq(r2["accumulateur"], 0.0, "un pas entier retranche -> reste exactement 0")

	# (3) INVERSION de la perte figee : le RESTE fractionnaire est CONSERVE. 2.5 pas -> 2 ticks,
	#     reste 0.5 pas (l'ancien cadenceur jetait ce reste et ne rendait qu'1 tick).
	var r3: Dictionary = RL.avancer(0.0, pas * 2.5, false)
	h.eq(r3["ticks"], 2, "2.5 pas -> exactement 2 ticks (rattrapage, pas 1 seul)")
	h.eq(r3["accumulateur"], pas * 0.5, "reste fractionnaire (0.5 pas) conserve, jamais jete")

	# (4) INDEPENDANCE AU DECOUPAGE DES TRAMES : une meme duree cumulee T = 3 pas produit
	#     floor(T/pas) = 3 ticks, qu'elle soit servie en 1 grosse trame ou en 6 fragments de
	#     0.5 pas — c'est exactement ce que l'ancien cadenceur ne garantissait pas.
	var gros: Dictionary = RL.avancer(0.0, pas * 3.0, false)
	var acc: float = 0.0
	var total_petit: int = 0
	for _i in range(6):
		var rr: Dictionary = RL.avancer(acc, pas * 0.5, false)
		total_petit += int(rr["ticks"])
		acc = rr["accumulateur"]
	h.eq(gros["ticks"], 3, "3 pas en 1 trame -> 3 ticks")
	h.eq(total_petit, 3, "3 pas en 6 fragments de 0.5 pas -> 3 ticks (independant du decoupage)")
	h.eq(total_petit, int(gros["ticks"]), "meme duree cumulee -> meme nombre de ticks quel que soit le decoupage")
	h.eq(acc, 0.0, "reste final nul apres 3 pas exacts servis en fragments")

	# (5) RATTRAPAGE BORNE (anti-spirale) : un delta enorme applique AU PLUS le plafond de ticks,
	#     et le surplus AU-DELA du plafond est JETE (accumulateur ramene sous un pas).
	var enorme: Dictionary = RL.avancer(0.0, pas * 100.0, false)
	h.eq(enorme["ticks"], cap, "delta enorme -> plafonne a MAX_TICKS_PAR_FRAME ticks (rattrapage borne)")
	h.ok(float(enorme["accumulateur"]) < pas, "surplus au-dela du plafond jete (accumulateur < un pas)")

	# (6) gelee (fin de partie) -> aucun tick, accumulateur inchange.
	var g: Dictionary = RL.avancer(5.0, pas * 100.0, true)
	h.eq(g["ticks"], 0, "gelee -> aucun tick")
	h.eq(g["accumulateur"], 5.0, "gelee -> accumulateur inchange")
