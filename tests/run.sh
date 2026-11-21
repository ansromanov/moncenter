#!/usr/bin/env bash
# Runs the monitor-free test suite.
exec python3 -I -m unittest discover -v -s "$(dirname "$0")" -t "$(dirname "$0")"
