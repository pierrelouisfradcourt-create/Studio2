"""Forge Observer — couche d'observation lecture seule du studio.

Observer ne modifie ni la Forge, ni les contrats, ni les agents, ni les jeux.
Il reconstruit ce qui s'est reellement passe a partir des seules traces deja
produites, et refuse d'inventer ce qu'il ne peut pas lire.
"""

__all__ = ["events", "sources"]
