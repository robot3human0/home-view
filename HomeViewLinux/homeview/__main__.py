"""Запуск: python -m homeview [--debug]"""

import argparse
import logging
import signal
import sys

from .app import run


def main() -> int:
    parser = argparse.ArgumentParser(prog="homeview", description="HomeView для Linux (X11)")
    parser.add_argument("--debug", action="store_true", help="подробный журнал")
    args, qt_args = parser.parse_known_args()
    logging.basicConfig(level=logging.DEBUG if args.debug else logging.INFO,
                        format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    signal.signal(signal.SIGINT, signal.SIG_DFL)  # Ctrl+C в терминале закрывает приложение
    return run([sys.argv[0], *qt_args])


if __name__ == "__main__":
    sys.exit(main())
