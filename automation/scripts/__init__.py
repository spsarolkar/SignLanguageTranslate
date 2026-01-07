"""
SignLanguageTranslate Automation Scripts Package
"""

import sys
from pathlib import Path

# Add scripts directory to path for imports
_scripts_dir = Path(__file__).parent
if str(_scripts_dir) not in sys.path:
    sys.path.insert(0, str(_scripts_dir))

from models import *
from logger import get_logger, setup_logger
from orchestrator import Orchestrator

__version__ = "1.0.0"
