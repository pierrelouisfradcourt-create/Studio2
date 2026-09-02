# Forge Observer - lancement Windows

Trois scripts PowerShell 5.1 pour demarrer/arreter le serveur d'observation
`scripts/observer/live.py` (lecture seule, ecoute sur `127.0.0.1` uniquement)
sans passer par un terminal a chaque fois.

Ces scripts ne modifient rien dans le depot : les logs vont dans
`%LOCALAPPDATA%\ForgeObserver\observer.log`.

## Quoi

- `start_observer.ps1` - demarre l'Observer en arriere-plan si besoin, attend
  qu'il reponde (`/api/health`), puis ouvre `http://127.0.0.1:8771/` dans le
  navigateur par defaut. Si un Observer repond deja sur le port, il se contente
  d'ouvrir le navigateur (jamais de deuxieme instance).
  Parametres : `-Port` (8771), `-Project` (breakout_v2), `-TimeoutSeconds` (30).

- `stop_observer.ps1` - arrete uniquement le(s) processus Python dont la ligne
  de commande contient `observer\live.py` (jamais un autre processus Python de
  la machine). Avec `-Port <n>`, n'arrete que l'instance de ce port.

- `install_shortcut.ps1` - cree un raccourci "Forge Observer" sur le Bureau qui
  lance `start_observer.ps1` en un clic (fenetre cachee). `-Uninstall` le
  supprime.

## Comment

Un clic (apres installation du raccourci) :

```
Double-clic sur "Forge Observer" (Bureau)
```

Ou en ligne de commande depuis ce dossier :

```powershell
.\install_shortcut.ps1
.\start_observer.ps1
.\start_observer.ps1 -Port 8772 -Project autre_projet
.\stop_observer.ps1
.\stop_observer.ps1 -Port 8771
```

## Ou regarder en cas de probleme

- Log du serveur : `%LOCALAPPDATA%\ForgeObserver\observer.log`
- Si `start_observer.ps1` expire (timeout), il affiche automatiquement les
  30 dernieres lignes de ce log avant de sortir en erreur.

## Comment desinstaller

```powershell
.\stop_observer.ps1
.\install_shortcut.ps1 -Uninstall
```

Cela arrete le serveur et supprime le raccourci Bureau. Les trois scripts et
ce README peuvent ensuite etre supprimes manuellement du depot si l'Observer
n'est plus utilise ; aucun autre fichier du poste n'en depend.
