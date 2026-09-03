"""Adaptateur de runtime LM local — extrait VERBATIM de `scripts/council.py` (V1, HEAD 58095ba9).

POURQUOI CE MODULE EXISTE (lot B, GO Pierre 2026-09-02, après RUN M).
`forge/runtime.py` importait `QwenAdapter` depuis `scripts/council.py`. En V2, ce fichier n'existe
pas : le run s'est arrêté à s6 sur un `ModuleNotFoundError` **avalé** par `qwen_available()`, puis
re-étiqueté « lmstudio :1234 down » — un motif faux sur un port ouvert.

CE QUI A ÉTÉ REPRIS, ET CE QUI NE L'A PAS ÉTÉ — mesuré par fermeture transitive :
    51 lignes sur 572 (8 %)   ·   34 définitions de premier niveau NON reprises

    reprises      QwenAdapter · _OpenAICompatAdapter · ModelId · CouncilError
                  CouncilCallError · LMSTUDIO_URL · _CONNECT_TIMEOUT_S · _READ_TIMEOUT_S
    NON reprises  la lane /council (CouncilTask, CouncilRole, CouncilResult, Disagreement,
                  ModelOpinion, _role_prompt…) — DÉCLARÉE GELÉE, CLAUDE.md:130
                  GeminiAdapter — adaptateur d'API EXTERNE (clé GEMINI_API_KEY)
                  ClaudeProxyAdapter · COUNCIL_WRITE_ACTION · ARTIFACT_DIR · REPO · governor

Copier les 572 lignes aurait réintroduit une lane gelée et un chemin réseau sortant pour obtenir
trois lignes de sous-classe. C'est la faute évitée sur les hooks et les skills, en plus lourd.

VERBATIM ASSUMÉ : le code ci-dessous n'est PAS réécrit. `ModelId` conserve ses trois valeurs alors
que V2 n'en consomme aucune (0 usage dans `forge/`) — la simplifier serait la seule dérive possible
de cette extraction, et elle est donc refusée explicitement. On récupère, on ne reconstruit pas.

Dépendance tierce : `requests` (importé paresseusement dans les méthodes, comme en V1).
"""
from __future__ import annotations

import os
from enum import Enum

# --- Endpoint (env-overridable) — verbatim council.py:47 ---
LMSTUDIO_URL = os.getenv("LMSTUDIO_BASE_URL", "http://127.0.0.1:1234/v1")

# --- Bornes de temps — verbatim council.py:51-52 ---
_CONNECT_TIMEOUT_S = 5
_READ_TIMEOUT_S = 110            # RT-198-2 : strictement < ROLE_TIMEOUT_S

# --- Erreurs — verbatim council.py:67-72 ---
class CouncilError(Exception):
    """Erreur council générique."""


class CouncilCallError(CouncilError):
    """Échec d'appel d'un adapter (réseau/quota/refus). Message = chaîne FIXE (jamais de secret)."""

# --- Enum de modèle — verbatim council.py:81-84 (NON simplifié, cf. entête) ---
class ModelId(str, Enum):
    CLAUDE = "claude"
    QWEN14B = "qwen2.5-14b"
    GEMINI_FLASH = "gemini-flash"

# --- Base OpenAI-compatible — verbatim council.py:261-297 ---
class _OpenAICompatAdapter:
    """Base openai-completions. Auth header-only. Aucune fuite de secret dans les exceptions."""

    def __init__(self, model: ModelId, base_url: str, model_name: str, api_key_env: str | None = None):
        self.model = model
        self._base = base_url.rstrip("/")
        self._model_name = model_name
        self._api_key_env = api_key_env

    def _api_key(self) -> str | None:
        return os.getenv(self._api_key_env) if self._api_key_env else None

    def is_available(self) -> bool:
        try:
            import requests
            r = requests.get(self._base.rsplit("/v1", 1)[0] + "/health",
                             timeout=(_CONNECT_TIMEOUT_S, 3))
            return r.status_code < 500
        except Exception:
            return False

    def complete(self, prompt: str, *, read_timeout: float = _READ_TIMEOUT_S) -> str:
        import requests
        headers = {"Content-Type": "application/json"}
        key = self._api_key()
        if key:
            headers["Authorization"] = f"Bearer {key}"   # header-only, jamais ?key=
        payload = {"model": self._model_name,
                   "messages": [{"role": "user", "content": prompt}],
                   "temperature": 0.2}
        try:
            r = requests.post(self._base + "/chat/completions", json=payload, headers=headers,
                              timeout=(_CONNECT_TIMEOUT_S, read_timeout))
            r.raise_for_status()
            return r.json()["choices"][0]["message"]["content"]
        except Exception as exc:  # noqa: BLE001 — mappe en chaîne FIXE (jamais de secret/URL/clé)
            raise CouncilCallError("call_failed") from None

# --- L'adaptateur réellement consommé par la Forge — verbatim council.py:308-310 ---
class QwenAdapter(_OpenAICompatAdapter):
    def __init__(self, base_url: str = LMSTUDIO_URL):
        super().__init__(ModelId.QWEN14B, base_url, "qwen2.5-14b-instruct")
