"""Adaptateurs de sources.

Chaque adaptateur expose :
    NAME: str
    collect(ctx: ObserverContext) -> list[Event]

Il lit UNIQUEMENT via `ctx` (garde de cecite), n'ecrit rien, et ne leve pas
d'exception sur une source absente : une tentative de run n'a pas forcement
les memes fichiers qu'une autre.
"""

from __future__ import annotations

from typing import Any, Callable, Protocol


class Adapter(Protocol):
    NAME: str

    def collect(self, ctx: Any) -> list[Any]:  # pragma: no cover - contrat
        ...


def load_adapters() -> list[Any]:
    """Retourne les adaptateurs disponibles, dans un ordre stable."""
    from observer.adapters import forge_evidence, forge_run, transcripts

    return [forge_run, forge_evidence, transcripts]
