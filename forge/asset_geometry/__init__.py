"""Asset Geometry Oracle V1 — mesure et jugement geometrique des assets glTF/GLB.

Separation stricte, cf. docs/forge/ASSET_GEOMETRY_ORACLE_V1_DESIGN.md :
  - `measure` ne juge JAMAIS  (produit un measurement, aucun verdict)
  - `oracle`  ne mesure JAMAIS (consomme un measurement, produit un verdict)

C'est ce qui rend l'oracle testable sur des measurements figes, sans aucun .glb.
"""
