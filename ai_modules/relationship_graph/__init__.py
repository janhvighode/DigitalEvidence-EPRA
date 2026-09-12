import os
import sys

_REL_DIR = os.path.dirname(os.path.abspath(__file__))
if _REL_DIR not in sys.path:
    sys.path.insert(0, _REL_DIR)
