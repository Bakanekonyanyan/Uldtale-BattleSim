#!/usr/bin/env python3
"""Uldtale content manager - edit the game's data/*.json files with forms.

Run from anywhere:   python DevTools/content_manager.py
Needs Python 3.9+ with Tkinter (included in the python.org Windows installer).
Field definitions live in DevTools/schemas/; the code in DevTools/cm/.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from cm.app import main  # noqa: E402

if __name__ == "__main__":
    main()
