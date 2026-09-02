# sound_cues.gd — QUEL EVENEMENT DE JEU produit QUEL son. Logique PURE : aucune API audio,
# aucun noeud, aucun fichier. Ce module dit ce qu'il FAUT jouer ; il ne joue rien.
#
# reused_from = CONCEPT (games/pacman/06_RUNTIME/adapters/sound_bank + audio.gd) : le son
# est DECRIT par un descripteur de synthese (onde, hauteur, duree, enveloppe) et FABRIQUE a
# l'execution. Aucun echantillon n'est lu depuis un fichier — c'est la seule voie qui
# satisfait core.audio sans introduire d'asset audio dans le depot.
#
# La separation compte : la banque vit dans les REGLES parce que « poser une bombe fait un
# bruit sec et grave » est une decision de design, pas une affaire de plateforme. La
# synthese, elle, vit dans l'adaptateur.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")

# Vocabulaire FERME des moments sonores.
const CUE_POSE := "pose"
const CUE_EXPLOSION := "explosion"
const CUE_DESTRUCTION := "destruction"
const CUE_RAMASSAGE := "ramassage"
const CUE_MORT := "mort"
const CUE_FIN := "fin"
const CUE_MORT_SUBITE := "mort_subite"

const CUES: Array = [
	CUE_POSE, CUE_EXPLOSION, CUE_DESTRUCTION, CUE_RAMASSAGE,
	CUE_MORT, CUE_FIN, CUE_MORT_SUBITE,
]

# Formes d'onde disponibles.
const ONDE_CARREE := 0
const ONDE_TRIANGLE := 1
const ONDE_BRUIT := 2

# BANQUE : un descripteur par moment. `hz` en hertz, `ms` en millisecondes, `gain` dans
# [0,1], `chute` = decroissance de l'enveloppe (1.0 = coupe nette, 0.0 = tenue).
#
# Les hauteurs sont CHOISIES pour etre distinguables a l'oreille : un joueur doit savoir,
# sans regarder, s'il vient de poser une bombe ou de ramasser un bonus. C'est la meme
# exigence que la discernabilite visuelle, portee sur un autre sens.
const BANQUE: Dictionary = {
	CUE_POSE:        {"onde": ONDE_CARREE,   "hz": 180.0, "ms": 90,  "gain": 0.35, "chute": 0.85},
	CUE_EXPLOSION:   {"onde": ONDE_BRUIT,    "hz": 90.0,  "ms": 260, "gain": 0.55, "chute": 0.70},
	CUE_DESTRUCTION: {"onde": ONDE_BRUIT,    "hz": 320.0, "ms": 120, "gain": 0.30, "chute": 0.90},
	CUE_RAMASSAGE:   {"onde": ONDE_TRIANGLE, "hz": 880.0, "ms": 150, "gain": 0.40, "chute": 0.60},
	CUE_MORT:        {"onde": ONDE_CARREE,   "hz": 110.0, "ms": 420, "gain": 0.50, "chute": 0.45},
	CUE_FIN:         {"onde": ONDE_TRIANGLE, "hz": 523.0, "ms": 600, "gain": 0.45, "chute": 0.35},
	CUE_MORT_SUBITE: {"onde": ONDE_BRUIT,    "hz": 140.0, "ms": 200, "gain": 0.42, "chute": 0.75},
}

# Correspondance EVENEMENT DE BOUCLE -> moment sonore. Un `kind` sans son declare rend ""
# — le silence est une valeur, jamais un plantage.
const PAR_EVENEMENT: Dictionary = {
	"bombe_posee": CUE_POSE,
	"explosion": CUE_EXPLOSION,
	"bloc_detruit": CUE_DESTRUCTION,
	"powerup_ramasse": CUE_RAMASSAGE,
	"mort": CUE_MORT,
	"fin": CUE_FIN,
	"mort_subite": CUE_MORT_SUBITE,
}


static func cue_pour_evenement(kind: String) -> String:
	if PAR_EVENEMENT.has(kind):
		return String(PAR_EVENEMENT[kind])
	return ""


static func descripteur(cue: String) -> Dictionary:
	if BANQUE.has(cue):
		return BANQUE[cue]
	return {}


# Nombre d'echantillons qu'un moment doit produire a une frequence donnee. Fonction PURE :
# c'est elle qui rend le volume de synthese VERIFIABLE sans jouer un seul son.
static func echantillons(cue: String, frequence: int) -> int:
	var d: Dictionary = descripteur(cue)
	if d.is_empty() or frequence <= 0:
		return 0
	return int(float(d["ms"]) * float(frequence) / 1000.0)


# Nombre de PAIRES de moments partageant EXACTEMENT la meme hauteur ET la meme onde.
# L'oracle exige 0 — meme regle que la discernabilite visuelle, appliquee a l'oreille.
static func cues_indiscernables() -> int:
	var n: int = 0
	for i in range(CUES.size()):
		for j in range(i + 1, CUES.size()):
			var a: Dictionary = descripteur(String(CUES[i]))
			var b: Dictionary = descripteur(String(CUES[j]))
			if a["hz"] == b["hz"] and int(a["onde"]) == int(b["onde"]):
				n += 1
	return n
