# capture.gd — capture d'image a un tick DECLARE (ligne render.frame_capture).
#
# FAIT DE POSTE MESURE (2026-07-22, memoire studio) : `--headless` rend une texture
# NULLE sur ce poste et ne produit AUCUN PNG. Une preuve VISUELLE exige donc une fenetre
# GPU reelle. Ce module ECHOUE EXPLICITEMENT en headless au lieu d'ecrire un fichier
# vide : une image morte ne doit jamais passer pour un vert.
extends RefCounted

const PREFIXE := "tick_"
const EXTENSION := ".png"


# Faut-il capturer a ce tick ? La liste des ticks de capture est DECLAREE en entree.
static func doit_capturer(tick: int, ticks_declares: Array) -> bool:
	return ticks_declares.has(tick)


static func nom_fichier(tick: int) -> String:
	return PREFIXE + str(tick) + EXTENSION


# Le mode headless est-il un contexte de capture valide ? NON — reponse mesuree, pas
# supposee. Sert de garde explicite aux appelants.
static func contexte_capture_valide(entete_serveur_affichage: String) -> bool:
	return entete_serveur_affichage != "headless" and entete_serveur_affichage != "dummy"


# Capture la texture du viewport. Rend {"ok": bool, "raison": String}. Aucun fichier
# n'est ecrit quand l'image est nulle : l'echec est NOMME, jamais silencieux.
static func capturer(viewport: Viewport, chemin: String) -> Dictionary:
	if viewport == null:
		return {"ok": false, "raison": "aucun viewport"}
	var texture := viewport.get_texture()
	if texture == null:
		return {"ok": false, "raison": "texture nulle (fenetre GPU absente ?)"}
	var image := texture.get_image()
	if image == null or image.is_empty():
		return {"ok": false, "raison": "image nulle : --headless ne rend rien sur ce poste"}
	var erreur: int = image.save_png(chemin)
	if erreur != OK:
		return {"ok": false, "raison": "ecriture PNG impossible (code %d)" % erreur}
	return {"ok": true, "raison": chemin}
