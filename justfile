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
build *EXTRA_FLAGS:
    zig build --summary all {{EXTRA_FLAGS}}

# TODO: What extra flags to zig build test do we want to pass (if any).
[doc]
[group: 'test']
test *EXTRA_FLAGS:
    zig build test --summary all {{EXTRA_FLAGS}}

# XXX: Temporary until Zig's fuse-overlayfs d_type woes are sorted.
[private]
dt-build *EXTRA_FLAGS:
    zig build --summary all -Dwith-cli=true --global-cache-dir zig-global {{EXTRA_FLAGS}}

[private]
dt-test *EXTRA_FLAGS:
    zig build test --summary all --global-cache-dir zig-global {{EXTRA_FLAGS}}
