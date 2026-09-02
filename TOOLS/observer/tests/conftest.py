import sys
from pathlib import Path

# scripts/observer/tests/conftest.py -> parents[2] == scripts/ (rend `observer` importable)
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
