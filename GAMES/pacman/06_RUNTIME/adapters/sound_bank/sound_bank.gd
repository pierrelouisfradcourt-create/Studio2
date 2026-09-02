# sound_bank.gd — SIX DESCRIPTEURS DE SYNTHESE, un par moment sonore
# (ligne sound_bank.six_descriptors).
#
# Six DESCRIPTEURS, jamais six references de fichier : aucun echantillon n'entre dans le
# depot, et c'est pourquoi ce module n'est PAS range en `asset.audio` (04_ASSETS),
# categorie reservee aux fichiers audio importes que l'invariant zero asset interdit.
#
# Donnee COMPARABLE deux a deux, ce qui interdit de brancher six evenements sur un meme
# son. Feuille du graphe : ne depend de rien, ne joue rien.
extends RefCounted

# Vocabulaire ferme des formes d'onde synthetisees.
const ONDE_CARREE := "carree"
const ONDE_TRIANGLE := "triangle"
const ONDE_DENT_DE_SCIE := "dent_de_scie"
const ONDE_SINUS := "sinus"
const ONDES: Array = [ONDE_CARREE, ONDE_TRIANGLE, ONDE_DENT_DE_SCIE, ONDE_SINUS]

# Champs obligatoires d'un descripteur de synthese.
const CHAMPS: Array = ["onde", "hauteur_hz", "duree_ms", "attaque_ms", "chute_ms", "volume"]

# Les six moments, DANS L'ORDRE DECLARE par game_events.
const DESCRIPTEURS: Dictionary = {
	"son_deplacement": {
		"onde": ONDE_CARREE, "hauteur_hz": 220.0, "duree_ms": 40.0,
		"attaque_ms": 2.0, "chute_ms": 20.0, "volume": 0.20,
	},
	"son_collecte": {
		"onde": ONDE_TRIANGLE, "hauteur_hz": 660.0, "duree_ms": 60.0,
		"attaque_ms": 1.0, "chute_ms": 30.0, "volume": 0.35,
	},
	"son_effraye": {
		"onde": ONDE_DENT_DE_SCIE, "hauteur_hz": 130.0, "duree_ms": 220.0,
		"attaque_ms": 8.0, "chute_ms": 120.0, "volume": 0.45,
	},
	"son_mort": {
		"onde": ONDE_DENT_DE_SCIE, "hauteur_hz": 90.0, "duree_ms": 500.0,
		"attaque_ms": 4.0, "chute_ms": 400.0, "volume": 0.55,
	},
	"son_victoire": {
		"onde": ONDE_SINUS, "hauteur_hz": 880.0, "duree_ms": 420.0,
		"attaque_ms": 6.0, "chute_ms": 200.0, "volume": 0.50,
	},
	"son_pause": {
		"onde": ONDE_SINUS, "hauteur_hz": 440.0, "duree_ms": 120.0,
		"attaque_ms": 3.0, "chute_ms": 60.0, "volume": 0.30,
	},
}

const MOMENTS: Array = [
	"son_deplacement", "son_collecte", "son_effraye",
	"son_mort", "son_victoire", "son_pause",
]

const FREQUENCE_ECHANTILLONNAGE: float = 22050.0

# --- PISTE MUSICALE (V3, cause racine P3) -----------------------------------------
# Ce qui manquait n'etait PAS « le son » — six bruitages existent et sont prouves — mais
# une PISTE : une suite de notes qui tourne en fond. Elle est declaree ICI, a cote des
# six descripteurs et dans la MEME forme, pour qu'un seul moteur de synthese la fabrique
# (audio.gd). Aucun fichier, aucun echantillon importe : l'invariant zero asset tient.
#
# La piste est TENUE HORS de DESCRIPTEURS : `MOMENTS` compte les SIX moments de jeu, et
# l'inventaire en fait un controle croise (« six descripteurs de synthese »). Y ajouter
# une septieme entree changerait la signification de ce comptage.
const MOMENT_MUSIQUE := "musique"

# Hauteurs de la boucle, en hertz. Gamme pentatonique mineure : elle tourne sans jamais
# produire d'intervalle dissonant, quelle que soit la note ou la boucle est reprise.
const SILENCE_HZ: float = 0.0
const NOTES: Array = [
	220.0, 261.63, 293.66, 349.23, 293.66, 261.63,
	220.0, SILENCE_HZ, 196.0, 261.63, 293.66, SILENCE_HZ,
	220.0, 293.66, 349.23, 392.0,
]

const PISTE_ONDE := ONDE_TRIANGLE
const PISTE_VOLUME: float = 0.22
const PISTE_DUREE_NOTE_MS: float = 180.0
const PISTE_ATTAQUE_MS: float = 8.0
const PISTE_CHUTE_MS: float = 90.0


static func nb_notes() -> int:
	return NOTES.size()


static func duree_piste_ms() -> float:
	return float(NOTES.size()) * PISTE_DUREE_NOTE_MS


# Rang de note atteint apres `ms` millisecondes de lecture. La piste BOUCLE : le rang
# revient a son point de depart au bout d'une duree de piste, et un temps negatif est
# ramene dans la boucle plutot que refuse — une piste de fond n'a pas de bord.
static func rang_note(ms: float) -> int:
	if NOTES.is_empty():
		return 0
	var total: float = duree_piste_ms()
	var t: float = fmod(ms, total)
	if t < 0.0:
		t += total
	var r: int = int(t / PISTE_DUREE_NOTE_MS)
	if r >= NOTES.size():
		return NOTES.size() - 1
	return r


static func hauteur_note(rang: int) -> float:
	if NOTES.is_empty():
		return SILENCE_HZ
	var i: int = rang % NOTES.size()
	if i < 0:
		i += NOTES.size()
	return float(NOTES[i])


# Descripteur de synthese d'UNE note, dans la MEME forme que les six bruitages : c'est
# ce qui permet a audio.gd de la fabriquer avec le moteur deja prouve, sans le doubler.
static func descripteur_note(rang: int) -> Dictionary:
	return {
		"onde": PISTE_ONDE,
		"hauteur_hz": hauteur_note(rang),
		"duree_ms": PISTE_DUREE_NOTE_MS,
		"attaque_ms": PISTE_ATTAQUE_MS,
		"chute_ms": PISTE_CHUTE_MS,
		"volume": PISTE_VOLUME,
	}


# Nombre de HAUTEURS DISTINCTES de la piste, silence exclu. Une piste dont toutes les
# notes seraient identiques serait un bourdon, pas une musique : la valeur est mesuree,
# pas affirmee (regle de variance ratifiee Pierre 2026-07-21).
static func hauteurs_distinctes() -> int:
	var vues: Array = []
	for n in NOTES:
		if float(n) == SILENCE_HZ:
			continue
		if not vues.has(float(n)):
			vues.append(float(n))
	return vues.size()


static func connu(moment: String) -> bool:
	return DESCRIPTEURS.has(moment)


static func descripteur(moment: String) -> Dictionary:
	if not connu(moment):
		return {}
	return DESCRIPTEURS[moment]


static func champs_manquants(desc: Dictionary) -> Array:
	var sortie: Array = []
	for c in CHAMPS:
		if not desc.has(c):
			sortie.append(c)
	return sortie


# Deux descripteurs different-ils par AU MOINS un parametre ?
static func differents(a: Dictionary, b: Dictionary) -> bool:
	for c in CHAMPS:
		if a.get(c) != b.get(c):
			return true
	return false


# Nombre de PAIRES IDENTIQUES parmi les six descripteurs : la valeur attendue vaut
# exactement 0 — brancher deux evenements sur un meme son serait visible ici.
static func paires_identiques() -> int:
	var n: int = 0
	for i in range(MOMENTS.size()):
		for j in range(i + 1, MOMENTS.size()):
			if not differents(descripteur(MOMENTS[i]), descripteur(MOMENTS[j])):
				n += 1
	return n
