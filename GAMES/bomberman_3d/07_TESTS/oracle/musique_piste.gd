# musique_piste.gd — oracle produit de la PISTE MUSICALE.
#
# CE QU'IL PROUVE, ET POURQUOI IL NE REGARDE PAS LE JOURNAL : le parc porte un defaut
# mesure (games/pacman/.../audio.gd, playtest « la musique j'ai rien ») ou la fonction
# journalisait un tampon puis rendait la main sans jamais pousser les trames. Un oracle qui
# compte les entrees de journal aurait declare cette musique jouee. Ici la seule grandeur
# retenue est le nombre d'ECHANTILLONS REELLEMENT POUSSES, et une piste qui n'en pousse
# aucun est rouge quel que soit son journal.
#
# Sortie : "FORGE_ORACLE musique_piste {json}".
extends SceneTree

const Audio = preload("res://06_RUNTIME/adapters/audio/audio.gd")

var _audio
var _f := 0
var _fait := false

func _initialize() -> void:
	Audio.reinitialiser_journal()
	_audio = Audio.new()
	get_root().add_child(_audio)

func _process(_d: float) -> bool:
	_f += 1
	if _f < 6:
		return false
	if _fait:
		return true
	_fait = true

	var total := 0
	var notes := 0
	var hauteurs := {}
	for i in range(Audio.MOTIF.size() * 2):
		total += _audio.jouer_musique(i, i * 16)
		notes += 1
		hauteurs[Audio.hauteur_note(i)] = true

	var fails: Array = []
	if total <= 0:
		fails.append("0 echantillon pousse — piste MUETTE (defaut du parc reproduit)")
	if notes != Audio.journal_musique.size():
		fails.append("le journal ne compte pas les notes demandees")
	if hauteurs.size() < 3:
		fails.append("moins de 3 hauteurs distinctes — ce n'est pas une piste")
	# Une piste doit BOUCLER : la deuxieme passe rejoue les memes hauteurs.
	if Audio.hauteur_note(Audio.MOTIF.size()) != Audio.hauteur_note(0):
		fails.append("le motif ne boucle pas")

	print("FORGE_ORACLE musique_piste " + JSON.stringify({
		"ok": fails.is_empty(), "fails": fails,
		"notes_demandees": notes, "echantillons_pousses": total,
		"hauteurs_distinctes": hauteurs.size(),
	}))
	quit(0 if fails.is_empty() else 1)
	return true
