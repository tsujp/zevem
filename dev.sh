#!/usr/bin/env bash

# XXX: Works but not as sophisticated, saving for now by commenting.
# podman run -it --userns keep-id \
# 	   --security-opt label=disable \
# 	   --volume /run/host/Users/tsujp/prog/zevem:/home/jammy/project \
# 	   --hostname "jam-zevem" \
# 	   localhost/jammy/zevem \
# 	   /bin/bash -l

THIS_SCRIPT="$(realpath "${BASH_SOURCE:-0}";)"

PROJECT_PATH="$(dirname -- "$THIS_SCRIPT";)"
PROJECT_DIR="$(basename -- "$PROJECT_PATH";)"

PODMAN_CMD='/opt/local/bin/podman'

# TODO: Handle paths that might need escaping (just use printf %q).
# TODO: Since this intended to just spawn the container for later use, perhaps `tail -f /dev/null` in the Containerfile for the default command, or some infinite loop, and then perhaps no `-it` as the arguments here since if we want an interactive shell and what not we'd use `podman exec` to get one.
podman run -it -d --replace \
	   --userns keep-id \
	   --security-opt label=disable,unmask=all \
	   --volume /run/host/"$PROJECT_PATH":/home/jammy/project \
	   --hostname "jam-$PROJECT_DIR" \
	   --name "jam-$PROJECT_DIR" \
	   localhost/jammy/"$PROJECT_DIR"
