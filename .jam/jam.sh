#!/usr/bin/env bash

set -euo pipefail


# If this script is executed via a symlink SYM_SCRIPTNAME is the symlink's name.
readonly SYM_SCRIPTNAME="${0##*/}"

# echo "a: $0"
# echo "b: $BASH_SOURCE"

# Whereas this is the real terminal file-name of the current script.
readonly REAL_SCRIPTNAME="$(realpath "${BASH_SOURCE:-0}";)"

readonly JAM_OPTSTRING='qvL'

eval set -- $(getopt "$JAM_OPTSTRING" "$@");

declare JAM_QUIET="${JAM_QUIET:-}"


puts ()
{
    if [ -z "$JAM_QUIET" ]; then
        printf "=> $@"
    fi
}


make_container ()
{
    # TODO: Canonicalise image name (-t) to underscores including converting - to _ and whitespace etc. Probably save implementing that for the Zig version of this.
    podman build \
           --squash \
           --omit-history \
           --build-arg PROJECT_NAME="$JAM_NAME" \
           -t localhost/jam/"$JAM_NAME" \
           -f "$JAM_CONTEXT"/.jam/Containerfile \
           "$JAM_CONTEXT"
}


# TODO: Use underscores in image and container names instead of hyphens jam_foo_lorem instead of jam-foo-lorem.
# TODO: Rename (as appropriate) as this function should create (if not already exists), and start the container both.
run_container ()
{
    local container_user="$(podman image inspect localhost/jam/"$JAM_NAME" --format "{{.User}}")"
    # TODO: Error checking on above output exit status and value (not empty string). Also, what are valid linux usernames? Just realised I don't know concretely. Probably a-Z0-9 with underscore and hyphen only? i.e. regex validate as appropriate too.

    podman run -it -d --replace \
           --init \
	       --userns keep-id \
	       --security-opt label=disable,unmask=all \
	       --volume /run/host/"$JAM_CONTEXT":/home/"$container_user"/project \
	       --hostname "jam-$JAM_NAME" \
	       --name "jam-$JAM_NAME" \
           --network=host \
	       localhost/jam/"$JAM_NAME"
}


ssh_container ()
{
    local container_user="$(podman image inspect localhost/jam/"$JAM_NAME" --format "{{.User}}")"
    podman exec -it -u "$container_user" "jam-$JAM_NAME" /bin/bash
}


while getopts "$JAM_OPTSTRING" opt; do
    printf '%s\n' "$opt"
    case $opt in
        q) echo "TODO: quiet";;
        v) echo "TODO: verbose";;
        L) echo "TODO: no color";;
        --) shift; break;;
    esac
done

shift $(($OPTIND - 1))


# --------------------------------------------------------------------
# If this script is called as a symlink honour where that symlink (that is, _the_ symlink) is located and not where the real eventual path of that symlink leads to.
# e.g. imagine symlinking to a master jam.sh from a few projects, would want the context to be per project and not the target jam.sh location.
# TODO: edge case of this script being sourced by another, but probably disallow that but probably re-write jam into zig later on anyway so something something premature optimisation.
readonly THIS_SCRIPT="${BASH_SOURCE:-$0}"

# TODO: Put this output behind the verbose flag.
printf 'script: %s' "$THIS_SCRIPT"
if [ -L "$THIS_SCRIPT" ]; then
    printf ' -> %s' "$(realpath "$THIS_SCRIPT";)"
fi
printf '\n'

cd "$(dirname -- "$THIS_SCRIPT";)"
readonly JAM_CONTEXT="$(git rev-parse --show-toplevel)"
# TODO: Error checking on exit status of above git command.

printf 'context: %s\n' "$JAM_CONTEXT"
cd "$JAM_CONTEXT"
# --------------------------------------------------------------------

readonly JAM_NAME="$(basename -- "$JAM_CONTEXT";)"

readonly JAM_TARGET="$1"

case "$JAM_TARGET" in
    make)
        puts "building dev jam container $JAM_NAME...\n"
        make_container
        ;;
    run)
        puts "{create,start}-ing dev jam container $JAM_NAME...\n"
        run_container
        ;;
    ssh)
        # We could use attach here since podman --init will manage a default session.
        ssh_container
        ;;
    *)
        printf 'Uknown target: %s\n' "$JAM_TARGET"
        # TODO: Add usage.
        exit 1
        ;;
esac
