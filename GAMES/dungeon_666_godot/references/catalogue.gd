extends RefCounted
## Le CATALOGUE des parties de référence : ce que la garde rejoue (references/verifier.gd).
## Repris tel quel de la version web (tools/traces.mjs, figée le 2026-10-01) : mêmes parties,
## mêmes graines, mêmes bots — les 70 parties dont l'égalité exacte avec le web a été prouvée
## ce jour-là (parite/LISEZ_MOI.md). Depuis, c'est Godot qui les enregistre.
##
## Une spec : voir references/partie.gd. Ajouter une partie = ajouter une ligne ici, puis
## l'enregistrer (references/enregistrer.gd -- <nom>). Les graines sont choisies pour que ce que
## la partie doit exercer se produise vraiment : après un changement de règle voulu, vérifier
## qu'elles le font toujours.

const KITS := [["revenant", "lame"], ["revenant", "dagues"], ["bourreau", "hache"], ["bourreau", "marteau"], ["chasseresse", "arc"], ["chasseresse", "arbalete"]]
const GUARDIAN_FLOORS := [18, 36, 54, 72] # Charon, Cerbère, Minos, Colosse (rotation)

static func all() -> Array:
	var out: Array = []
	out.append_array(_base())
	out.append_array(_guardians_and_depth())
	out.append_array(_lab_and_phases())
	out.append_array(_long_and_random())
	out.append_array(_content())
	out.append_array(_altars_and_layouts())
	out.append_array(_bestiary())
	return out

static func names() -> Array:
	return all().map(func(s): return s.name)

## La spec d'une partie, ou null.
static func find(name: String):
	for s in all():
		if s.name == name:
			return s
	return null

static func _base() -> Array:
	var out: Array = []
	# Chaque kit, du premier étage : combat, menus de bénédiction, portes.
	for i in KITS.size():
		out.append({"name": "kit_%s" % KITS[i][1], "seed": 101 + i, "floor": 1, "kit": KITS[i], "policy": "skilled", "seconds": 45})
	# Le bestiaire entier (milieu et fin de section 1), joueurs maladroits compris (morts, reprises).
	out.append({"name": "etage_7_habile", "seed": 201, "floor": 7, "policy": "skilled", "seconds": 45})
	out.append({"name": "etage_12_sans_dash", "seed": 202, "floor": 12, "policy": "noDash", "seconds": 45})
	out.append({"name": "etage_14_martele", "seed": 203, "floor": 14, "policy": "masher", "seconds": 45})
	out.append({"name": "etage_5_martele_ville", "seed": 204, "floor": 5, "policy": "masher", "seconds": 45, "deaths": "town"})
	# Salles calmes : halte de mi-section, antichambre.
	out.append({"name": "halte_9", "seed": 301, "floor": 8, "policy": "skilled", "seconds": 45})
	out.append({"name": "antichambre_17", "seed": 302, "floor": 16, "policy": "skilled", "seconds": 45})
	return out

static func _guardians_and_depth() -> Array:
	var out: Array = []
	# Les quatre Gardiens, par les trois classes.
	for i in GUARDIAN_FLOORS.size():
		var f: int = GUARDIAN_FLOORS[i]
		var kit: Array = KITS[(i * 2) % KITS.size()]
		out.append({"name": "gardien_%d_%s" % [f, kit[1]], "seed": 401 + i, "floor": f, "kit": kit, "policy": "skilled", "seconds": 60})
		out.append({"name": "gardien_%d_sans_dash" % f, "seed": 451 + i, "floor": f, "policy": "noDash", "seconds": 40})
	# Profondeur : Cercles lointains, finale, victoire.
	out.append({"name": "profond_163", "seed": 501, "floor": 163, "policy": "skilled", "seconds": 45})
	out.append({"name": "profond_400_arc", "seed": 502, "floor": 400, "kit": ["chasseresse", "arc"], "policy": "skilled", "seconds": 45})
	out.append({"name": "finale_660", "seed": 503, "floor": 660, "policy": "skilled", "seconds": 45})
	out.append({"name": "gardien_final_666", "seed": 504, "floor": 666, "policy": "skilled", "seconds": 60, "godMode": true})
	return out

static func _lab_and_phases() -> Array:
	var out: Array = []
	# Labo du feel : chaque variante hors référence.
	out.append({"name": "labo_gel_local", "seed": 601, "floor": 6, "policy": "skilled", "seconds": 40, "tuning": {"lab": {"hitstop": "local"}}})
	out.append({"name": "labo_tout_dash", "seed": 602, "floor": 6, "policy": "skilled", "seconds": 40, "tuning": {"lab": {"dashStrike": "toutDash"}}})
	out.append({"name": "labo_apres_dash", "seed": 603, "floor": 6, "policy": "skilled", "seconds": 40, "tuning": {"lab": {"dashStrike": "apresDash"}}})
	out.append({"name": "labo_ancre", "seed": 604, "floor": 6, "policy": "skilled", "seconds": 40, "tuning": {"lab": {"comboMobility": "ancre"}}})
	out.append({"name": "labo_fluide", "seed": 605, "floor": 6, "policy": "skilled", "seconds": 40, "tuning": {"lab": {"comboMobility": "fluide"}}})
	# Les trois phases de chaque Gardien : PV réduits (les seuils de phase tombent vite), héros invulnérable.
	for pair in [[18, "gardien"], [36, "cerbere"], [54, "minos"], [72, "colosse"]]:
		out.append({"name": "phases_%s" % pair[1], "seed": 801 + pair[0], "floor": pair[0], "policy": "skilled", "seconds": 120, "godMode": true, "tuning": {"boss": {pair[1]: {"hp": 260}}}})
	return out

static func _long_and_random() -> Array:
	var out: Array = []
	# Sections entières (cinq à sept minutes) : rien ne doit dériver sur la durée.
	out.append({"name": "section_lame", "seed": 901, "floor": 1, "kit": ["revenant", "lame"], "policy": "skilled", "seconds": 420})
	out.append({"name": "section_arbalete", "seed": 902, "floor": 1, "kit": ["chasseresse", "arbalete"], "policy": "skilled", "seconds": 420})
	out.append({"name": "section_marteau_martele", "seed": 903, "floor": 1, "kit": ["bourreau", "marteau"], "policy": "masher", "seconds": 300})
	# Entrées au hasard, pour chaque kit : les bords que les bots ne touchent jamais.
	for i in KITS.size():
		out.append({"name": "hasard_%s" % KITS[i][1], "seed": 1001 + i, "floor": 2 + i * 3, "kit": KITS[i], "policy": "hasard", "seconds": 90, "godMode": i % 2 == 0})
	# Modes : arène d'essai, entraînement contre un Gardien.
	out.append({"name": "arene", "seed": 701, "floor": 1, "policy": "skilled", "seconds": 45, "sandbox": true})
	out.append({"name": "entrainement_cerbere", "seed": 702, "floor": 36, "policy": "masher", "seconds": 40, "practice": true})
	return out

## Départs garnis (build) qui exercent les procs des bénédictions et des pouvoirs : esquives
## parfaites, murs, Super lancé, salles sans blessure, derniers coups de combo, éclairs, explosions.
static func _content() -> Array:
	return [
		{"name": "contenu_esquives_hasard", "seed": 5115, "floor": 14, "policy": "hasard", "seconds": 60, "build": {"boons": ["represailles", "baillement", "ivresse", "eclair_de_depit", "mauvais_oeil", "foudre_du_dedain", "trop_plein", "festin"], "power": "eperons_alastor"}},
		{"name": "contenu_murs_marteau", "seed": 5012, "floor": 9, "kit": ["bourreau", "marteau"], "policy": "masher", "seconds": 60, "build": {"boons": ["mur_du_sommeil", "faire_les_poches", "mepris", "coup_de_sang", "tresor_de_guerre", "prime_de_risque"], "power": "fracas_moloch"}},
		{"name": "contenu_super_lame", "seed": 5022, "floor": 5, "policy": "skilled", "seconds": 75, "build": {"boons": ["ripaille", "passion_brulante", "bouchee_double", "baiser_vole", "invaincu", "prime_de_risque", "extase"], "power": "main_de_gloire"}},
		{"name": "contenu_eclairs_arc", "seed": 5031, "floor": 10, "kit": ["chasseresse", "arc"], "policy": "skilled", "seconds": 60, "build": {"boons": ["coup_de_sang", "baiser_vole", "mauvais_oeil", "foudre_du_dedain", "invaincu"], "rarity": "rare", "power": "dard_lilith"}},
		{"name": "contenu_dagues_belial", "seed": 5041, "floor": 11, "kit": ["revenant", "dagues"], "policy": "skilled", "seconds": 60, "build": {"boons": ["bouchee_double", "mepris", "eclair_de_depit", "tresor_de_guerre"], "rarity": "epique", "power": "marteau_belial"}},
		{"name": "contenu_hache_abaddon", "seed": 5052, "floor": 13, "kit": ["bourreau", "hache"], "policy": "skilled", "seconds": 60, "build": {"boons": ["mauvais_oeil", "coup_de_sang", "mur_du_sommeil", "faire_les_poches", "represailles"], "power": "linceul_abaddon"}},
	]

static func _altars_and_layouts() -> Array:
	var out: Array = []
	# Les autels : graines où le bot rencontre l'autel et y prend une option qui coûte.
	var altar_build := {"boons": ["furie", "torpeur", "voracite"], "souls": 90}
	for pair in [["autel_forge", 3000, 8], ["autel_miroir", 3004, 16], ["autel_registre_achat", 3066, 16], ["autel_registre_sang", 3063, 16], ["autel_clepsydre", 3040, 8]]:
		out.append({"name": pair[0], "seed": pair[1], "floor": pair[2], "policy": "skilled", "seconds": 60, "build": altar_build})
	# Quatre dispositions de salle, dans un Cercle qui les tire (héros invulnérable : équipement de départ).
	out.append({"name": "salle_colonnade", "seed": 4000, "floor": 74, "policy": "skilled", "seconds": 45, "godMode": true, "build": {"boons": ["mur_du_sommeil", "faire_les_poches", "coup_de_sang"]}})
	out.append({"name": "salle_goulet", "seed": 4000, "floor": 146, "policy": "skilled", "seconds": 45, "godMode": true, "build": {"boons": ["eclair_de_depit", "mauvais_oeil", "foudre_du_dedain"]}})
	out.append({"name": "salle_ilots", "seed": 4000, "floor": 220, "policy": "skilled", "seconds": 45, "godMode": true, "build": {"boons": ["passion_brulante", "ripaille", "trop_plein", "sang_devore"]}})
	out.append({"name": "salle_chicane", "seed": 4000, "floor": 290, "policy": "skilled", "seconds": 45, "godMode": true, "build": {"boons": ["represailles", "ivresse", "baillement", "invaincu"], "power": "linceul_abaddon"}})
	return out

## Porte-pavois (étage 10), Traqueur (12), Porte-étendard (14). Graines choisies pour que
## l'archétype COMBATTE vraiment : coups arrêtés par le pavois et coups de pavois, embuscades
## (dont certaines touchent), ennemis frappés sous l'étendard.
static func _bestiary() -> Array:
	return [
		{"name": "bestiaire_pavois_habile", "seed": 6009, "floor": 10, "policy": "skilled", "seconds": 60},
		{"name": "bestiaire_pavois_marteau_martele", "seed": 6103, "floor": 10, "kit": ["bourreau", "marteau"], "policy": "masher", "seconds": 60},
		{"name": "bestiaire_traqueur_sans_dash", "seed": 6202, "floor": 12, "policy": "noDash", "seconds": 60},
		{"name": "bestiaire_traqueur_arc", "seed": 6308, "floor": 12, "kit": ["chasseresse", "arc"], "policy": "skilled", "seconds": 60},
		{"name": "bestiaire_etendard_habile", "seed": 6407, "floor": 14, "policy": "skilled", "seconds": 75},
		# Champions : un Traqueur ardent (6405), un Porte-pavois vampirique (6406).
		{"name": "bestiaire_elite_traqueur", "seed": 6405, "floor": 14, "policy": "skilled", "seconds": 75},
		{"name": "bestiaire_elite_pavois", "seed": 6406, "floor": 14, "policy": "skilled", "seconds": 75},
		# Entrées au hasard : coups sur un pavois sous tous les angles, dashs à travers, frappes dans le vide d'un traqueur disparu.
		{"name": "bestiaire_hasard_hache", "seed": 6503, "floor": 15, "kit": ["bourreau", "hache"], "policy": "hasard", "seconds": 90, "godMode": true},
		{"name": "bestiaire_hasard_dagues", "seed": 6605, "floor": 16, "kit": ["revenant", "dagues"], "policy": "hasard", "seconds": 90},
		# En profondeur (toutes les sections suivantes ont le bestiaire entier), héros invulnérable.
		{"name": "bestiaire_profond_230", "seed": 6706, "floor": 230, "policy": "skilled", "seconds": 60, "godMode": true},
		{"name": "bestiaire_profond_100_arbalete", "seed": 6803, "floor": 100, "kit": ["chasseresse", "arbalete"], "policy": "noDash", "seconds": 60, "godMode": true},
	]
