#!/usr/bin/env bash

# --annotation [] \
# These don't seem to be being set or they are intended for build-time only (even though runtime has the same flags, idk just pass to `run`).
# --security-opt label=disable,unmask=all \

# TODO: Remove network alias that is garbage either here (if possible) or at the `run` command.

podman build \
	   --squash \
	   --omit-history \
	   -t localhost/jammy/zevem \
	   -f .jam/Containerfile \
	   .

# Run container with --hostname "jam-$PROJECT_NAME"
