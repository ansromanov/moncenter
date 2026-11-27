default:
    @just --list

# the full local gate; CI runs the same checks
check: lint file-size test

# ruff (pyflakes, pycodestyle) and shellcheck
lint:
    ruff check app tests
    shellcheck install.sh tests/run.sh

# files stay at or below 800 lines
file-size:
    python3 scripts/check-file-size.py

# parsers, QML load (offscreen) and installer checks; no monitor needed
test:
    tests/run.sh

# install for the current user
install:
    ./install.sh
