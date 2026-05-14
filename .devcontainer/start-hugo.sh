#!/bin/sh


# Script to start Hugo after the container is ready so port 1313 is available for preview.

# Fail fast if a command is missing or returns an error so startup problems are visible early.
set -eu

# Use pkill first so a restarted container does not leave a duplicate Hugo process listening on the same port.
pkill -f 'hugo server -D --bind 0.0.0.0 --port 1313 --noTimes' || true

# Use nohup to detach Hugo from the startup command so dev container initialization can finish while the server keeps running.
# Use --noTimes because this workspace can be mounted on a filesystem that does not allow Hugo to update directory timestamps.
nohup hugo server -D --bind 0.0.0.0 --port 1313 --noTimes >/tmp/hugo-server.log 2>&1 &