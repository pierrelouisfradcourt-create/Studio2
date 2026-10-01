extends RefCounted
## L'ORDRE DES COUCHES d'affichage (CanvasLayer.layer), du dessous au dessus. Une scène écrite à
## la main porte le NOMBRE (`layer = 10`) ; ce fichier dit ce qu'il signifie, et
## jeu/theme/verifier.gd vérifie que chaque vue porte le sien. Voir « Ordre des couches » dans
## jeu/ARCHITECTURE.md.
##   const Couches = preload("res://jeu/theme/couches.gd")

## Le monde et les effets du monde (Node2D, caméra).
const MONDE := 0
## Le voile d'ambiance du Monde (vignette) : sur le monde et ses effets, SOUS les flashs.
const VOILE_MONDE := 2
## Flashs d'écran des effets (voile clair, vignette de blessure) : sur le monde, SOUS le HUD.
const FLASH := 5
## Le HUD : toujours lisible, même pendant un flash.
const HUD := 10
## La Ville de Dité (plein écran).
const VILLE := 20
## Les écrans : titre, choix, mort, victoire, pause.
const ECRANS := 30
## Le fondu entre deux écrans (StudioTransitions du kit, qui pose lui-même sa couche).
const FONDU := 100
