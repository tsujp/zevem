#
# Does just now have?
# (1) optional parameter flags or only required arguments still?
# (2) invoke another receipe from WITHIN justfile even if its non-dependency?

# TODO: Add --unsorted to below if order sucks.
[private]
default:
    @just --justfile {{justfile()}} --list --list-heading $'Project commands:\n'

# TODO: Flags for release types shorthand (to zig build system) if valuable. For now just a basic `zig build`.
[doc]
[group: 'build']
build:
    zig build --summary all

# TODO: What extra flags to zig build test do we want to pass (if any).
[doc]
[group: 'test']
test:
    zig build test --summary all
