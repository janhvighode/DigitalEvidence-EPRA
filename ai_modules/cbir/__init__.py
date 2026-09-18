import os
import sys

_CBIR_DIR = os.path.dirname(os.path.abspath(__file__))
if _CBIR_DIR not in sys.path:
    sys.path.insert(0, _CBIR_DIR)
