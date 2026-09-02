# settings.gd — MODE DE JEU et reglages (lignes settings.mode_vocabulary,
# settings.mode_default_normal).
#
# Modele PUR : en drapeau de runtime, ni l'exclusivite du vocabulaire ni la valeur par
# defaut ne seraient mesurables. La valeur initiale est CONSTRUITE, jamais lue sur le
# disque ni dans un fichier de configuration.
#
# V6 : ce module cesse d'etre une feuille du graphe. Il depend desormais du BLOC DE
# PARAMETRES, et de lui seul, parce qu'il porte la CORRESPONDANCE mode -> nombre de vies.
# Le sens de l'arete est declare : settings LIT params, jamais l'inverse — params ne
# connait aucun vocabulaire de mode, il ne porte que des grandeurs nommees.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")

# Vocabulaire de DEUX valeurs mutuellement exclusives et exhaustives.
enum Mode { NORMAL, TEST }

const MODES_VALIDES: Array = [Mode.NORMAL, Mode.TEST]
const NOMS: Array = ["NORMAL", "TEST"]

# --- CE QUE LE JOUEUR LIT (V5, cause racine P1) ------------------------------------
# `NOMS` reste l'IDENTIFIANT INTERNE — cle du code, du releve observable et de la sonde
# de debogage. `LIBELLES` est le NOM DESTINE AU JOUEUR. Montrer « NORMAL » / « TEST » a
# l'ecran, c'est montrer l'identifiant de l'enum : exactement la classe de defaut du
# keycode 4194325 corrigee en V4. Les deux vocabulaires vivent cote a cote, ils ne se
# remplacent pas.
const LIBELLES: Array = ["Arcade", "Decouverte"]

# --- CE QUE LE MODE GOUVERNE (V6) --------------------------------------------------
# NOM DE LA GRANDEUR gouvernee par le mode. Ce n'est pas un texte d'affichage : c'est
# EXACTEMENT la cle que porte le releve observable (`observable.CLES`), pour que la
# declaration puisse etre confrontee TELLE QUELLE a la divergence mesuree. Un nom de
# declaration different de la cle mesuree obligerait a traduire — et une traduction est un
# endroit ou la declaration peut cesser de parler de ce qui est mesure.
const GRANDEUR_VIES := "vies"

# EFFETS DE REGLE declares mode par mode, sous la MEME forme que dash.EFFETS_DECLARES :
# une DONNEE confrontee a la mesure, jamais une note de commentaire.
#
# V5 declarait `[[], []]` — aucun effet — et la mesure differentielle le confirmait : 0
# divergence sur 200 ticks entre les deux modes. C'etait un reglage sans consequence.
# V6 (decision Pierre) : chaque mode declare EXACTEMENT UN effet de regle, le nombre de
# vies de depart. La table dit ce que la mesure doit trouver, et rien de plus : si une
# autre grandeur divergeait, la declaration serait fausse et le harnais le dirait.
#
# LE DASH N'EST PAS DANS CETTE TABLE, et c'est une decision, pas un oubli : il reste un
# reglage SEPARE du mode, actif dans les DEUX modes. Le mode ne l'autorise ni ne
# l'interdit.
const EFFETS_DE_REGLE: Array = [[GRANDEUR_VIES], [GRANDEUR_VIES]]

# CORRESPONDANCE mode -> nombre de vies de depart, indexee par le vocabulaire ferme.
# Les VALEURS viennent du bloc de parametres : elles ne sont pas recopiees ici, sans quoi
# deux nombres pourraient diverger. C'est la SEULE table qui lie un mode a un nombre.
const VIES_PAR_MODE: Array = [P.VIES_MODE_DEFI, P.VIES_MODE_MARGE]

# Gabarit d'EXPLICATION par mode. Le nombre de vies n'est PAS ecrit ici : il est REMIS EN
# ARGUMENT par l'appelant, qui le lit par `vies_initiales(mode)`. Le texte affiche ne peut
# donc pas diverger de la regle.
#
# V6 : le texte dit la VRAIE difference — les vies, mesurees — la ou V5 disait « memes
# regles ». Meme discipline que le guide des fantomes : on lit le code, on le decrit.
const GABARITS_EXPLICATION: Array = [
	"Le defi : %d vies. Terminez les cartes et faites le meilleur score.",
	"La marge d'erreur : %d vies pour decouvrir toutes les cartes. Tout le reste est identique.",
]

# MENTION affichee a cote des explications de mode. Le joueur doit pouvoir distinguer DEUX
# reglages qui l'aident tous les deux mais n'ont rien a voir : le MODE choisit un nombre de
# vies, le DASH est une capacite de deplacement. Sans cette phrase, « Decouverte » et
# « Dash » se lisent comme deux facons de dire « mode facile », ce qui est faux.
const MENTION_MODE_ET_DASH := "Le Dash est un reglage a part : il reste disponible dans les deux modes."

# Valeur au PREMIER LANCEMENT, sans reglage prealable ni etat persistant herite.
const MODE_PAR_DEFAUT: int = Mode.NORMAL
const DASH_ACTIF_PAR_DEFAUT: bool = true

# --- VOLUME GLOBAL (V3, cause racine P6) -----------------------------------------
# DISTINCT du champ `volume` que porte CHAQUE descripteur de son : celui-la dose UN
# bruitage a la fabrication, celui-ci dose L'ENSEMBLE au moment de jouer. Confondre les
# deux rendait le reglage global inexistant tout en donnant l'illusion qu'il existait.
#
# Le niveau est un RANG dans une echelle FERMEE, pas un flottant libre : c'est ce qui le
# rend enumerable, cyclable par une seule commande (Valider) et comparable deux a deux.
enum Canal { MUSIQUE, EFFETS }
const CANAUX: Array = [Canal.MUSIQUE, Canal.EFFETS]
const NOMS_CANAUX: Array = ["MUSIQUE", "EFFETS"]
const CLE_MUSIQUE := "volume_musique"
const CLE_EFFETS := "volume_effets"
const CLES_CANAUX: Array = [CLE_MUSIQUE, CLE_EFFETS]

const NIVEAU_MIN: int = 0
const NIVEAU_MAX: int = 4
# Gain applique par rang. Echelle croissante et STRICTEMENT monotone : deux rangs
# distincts ne peuvent pas produire le meme volume, sans quoi le reglage aurait des
# positions indiscernables.
const GAINS: Array = [0.0, 0.25, 0.5, 0.75, 1.0]

# Valeurs au PREMIER LANCEMENT. Les effets partent au maximum : le son du run V2 est
# exactement conserve tant que rien n'est regle.
const VOLUME_MUSIQUE_PAR_DEFAUT: int = 3
const VOLUME_EFFETS_PAR_DEFAUT: int = NIVEAU_MAX
const MUET_PAR_DEFAUT: bool = false

const CLES: Array = ["mode", "dash_actif", CLE_MUSIQUE, CLE_EFFETS, "muet"]


static func valide(mode: int) -> bool:
	return MODES_VALIDES.has(mode)


static func nom(mode: int) -> String:
	if not valide(mode):
		return ""
	return NOMS[mode]


# NOM DESTINE AU JOUEUR. Un mode hors vocabulaire n'a AUCUN libelle — chaine vide nommee,
# jamais le libelle d'un autre mode ni l'identifiant interne en repli.
static func libelle(mode: int) -> String:
	if not valide(mode):
		return ""
	return LIBELLES[mode]


# NOMBRE DE VIES DE DEPART du mode (V6). SOURCE UNIQUE de la regle : l'etat neuf, le
# domaine de validite, le HUD et le texte joueur en descendent tous. Un mode hors
# vocabulaire retombe sur le MODE PAR DEFAUT — meme repli que `normaliser`, jamais un
# nombre invente et jamais une exception.
static func vies_initiales(mode: int) -> int:
	if not valide(mode):
		return int(VIES_PAR_MODE[MODE_PAR_DEFAUT])
	return int(VIES_PAR_MODE[mode])


# PLUS GRAND nombre de vies qu'un mode puisse accorder. DERIVE de la table, jamais ecrit :
# designer « le plus genereux » a la main serait un second endroit a corriger.
#
# A QUOI IL SERT : le mode d'une partie EN COURS peut changer (ecran d'options ouvert
# depuis la pause), et le compteur de vies deja entame ne se rejuste PAS retroactivement —
# ce serait donner ou retirer des vies au milieu d'une partie. La borne STRUCTURELLE du
# domaine est donc la plus grande valeur declaree ; la regle du mode, elle, s'applique a
# la NAISSANCE d'une partie, ou elle est exacte.
static func vies_maximales() -> int:
	var m: int = 0
	for v in VIES_PAR_MODE:
		if int(v) > m:
			m = int(v)
	return m


# EXPLICATION destinee au joueur. `vies` est REMIS EN ARGUMENT : le nombre affiche est
# celui de la regle, jamais un nombre recopie.
static func explication(mode: int, vies: int) -> String:
	if not valide(mode):
		return ""
	return GABARITS_EXPLICATION[mode] % vies


# Effets de REGLE declares pour ce mode. Un mode inconnu n'en declare aucun.
static func effets_de_regle(mode: int) -> Array:
	if not valide(mode):
		return []
	return EFFETS_DE_REGLE[mode]


# Reglages du PREMIER LANCEMENT : construits, jamais lus.
static func initial() -> Dictionary:
	return {
		"mode": MODE_PAR_DEFAUT,
		"dash_actif": DASH_ACTIF_PAR_DEFAUT,
		CLE_MUSIQUE: VOLUME_MUSIQUE_PAR_DEFAUT,
		CLE_EFFETS: VOLUME_EFFETS_PAR_DEFAUT,
		"muet": MUET_PAR_DEFAUT,
	}


# Normalise des reglages recus : une valeur hors vocabulaire retombe sur le defaut
# declare. Le refus est une VALEUR de retour, jamais une exception.
static func normaliser(brut: Dictionary) -> Dictionary:
	var mode: int = MODE_PAR_DEFAUT
	if brut.has("mode") and valide(int(brut["mode"])):
		mode = int(brut["mode"])
	var dash: bool = DASH_ACTIF_PAR_DEFAUT
	if brut.has("dash_actif"):
		dash = bool(brut["dash_actif"])
	var musique: int = VOLUME_MUSIQUE_PAR_DEFAUT
	if brut.has(CLE_MUSIQUE) and niveau_valide(int(brut[CLE_MUSIQUE])):
		musique = int(brut[CLE_MUSIQUE])
	var effets: int = VOLUME_EFFETS_PAR_DEFAUT
	if brut.has(CLE_EFFETS) and niveau_valide(int(brut[CLE_EFFETS])):
		effets = int(brut[CLE_EFFETS])
	var muet: bool = MUET_PAR_DEFAUT
	if brut.has("muet"):
		muet = bool(brut["muet"])
	return {
		"mode": mode,
		"dash_actif": dash,
		CLE_MUSIQUE: musique,
		CLE_EFFETS: effets,
		"muet": muet,
	}


# --- VOLUME : vocabulaire ferme ---------------------------------------------------
static func niveau_valide(n: int) -> bool:
	return n >= NIVEAU_MIN and n <= NIVEAU_MAX


static func canal_valide(canal: int) -> bool:
	return CANAUX.has(canal)


static func nom_canal(canal: int) -> String:
	if not canal_valide(canal):
		return ""
	return NOMS_CANAUX[canal]


# Cle de reglage d'un canal ; un canal inconnu n'a AUCUNE cle (chaine vide nommee),
# jamais celle d'un autre canal.
static func cle_canal(canal: int) -> String:
	if not canal_valide(canal):
		return ""
	return CLES_CANAUX[canal]


# GAIN d'un rang. Un rang hors echelle retombe sur le rang PLEIN : refuser un reglage
# ne doit jamais couper le son sans que personne ne l'ait demande.
static func gain(n: int) -> float:
	if not niveau_valide(n):
		return GAINS[NIVEAU_MAX]
	return GAINS[n]


# Rang SUIVANT dans l'echelle fermee : le parcours BOUCLE, donc chaque activation change
# la valeur et aucune position n'est un cul-de-sac.
static func volume_suivant(n: int) -> int:
	if not niveau_valide(n):
		return NIVEAU_MIN
	if n >= NIVEAU_MAX:
		return NIVEAU_MIN
	return n + 1


static func volume(reglages: Dictionary, canal: int) -> int:
	if not canal_valide(canal):
		return NIVEAU_MIN
	return int(normaliser(reglages)[cle_canal(canal)])


static func avec_volume(reglages: Dictionary, canal: int, niveau: int) -> Dictionary:
	var suite: Dictionary = normaliser(reglages)
	if canal_valide(canal) and niveau_valide(niveau):
		suite[cle_canal(canal)] = niveau
	return suite


static func muet(reglages: Dictionary) -> bool:
	return bool(normaliser(reglages)["muet"])


static func avec_muet(reglages: Dictionary, silence: bool) -> Dictionary:
	var suite: Dictionary = normaliser(reglages)
	suite["muet"] = silence
	return suite


# GAIN EFFECTIF d'un canal : le coupe-son l'emporte sur les deux rangs. C'est LA valeur
# que consomme la couche audio — elle ne recombine jamais le rang et le coupe-son
# elle-meme, sans quoi deux regles de priorite pourraient diverger.
static func gain_effectif(reglages: Dictionary, canal: int) -> float:
	var r: Dictionary = normaliser(reglages)
	if bool(r["muet"]):
		return 0.0
	if not canal_valide(canal):
		return 0.0
	return gain(int(r[cle_canal(canal)]))


static func avec_mode(reglages: Dictionary, mode: int) -> Dictionary:
	var suite: Dictionary = normaliser(reglages)
	if valide(mode):
		suite["mode"] = mode
	return suite


static func avec_dash(reglages: Dictionary, actif: bool) -> Dictionary:
	var suite: Dictionary = normaliser(reglages)
	suite["dash_actif"] = actif
	return suite


# Bascule du mode : d'une valeur du vocabulaire ferme a l'AUTRE, jamais a une troisieme.
static func mode_suivant(mode: int) -> int:
	if mode == Mode.NORMAL:
		return Mode.TEST
	return Mode.NORMAL
