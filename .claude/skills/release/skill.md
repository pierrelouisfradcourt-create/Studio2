---
name: release
description: Release complète. Gate Pierre obligatoire.
---
1. cargo test + pytest 100% vert.
2. ELO match si release Rocky.
3. Build Godot si release jeu.
4. Changelog depuis dernier tag.
5. Gate Pierre → sur ratification : tag + push.
