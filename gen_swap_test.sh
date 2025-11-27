#!/usr/bin/env bash

# TODO: Place this file somewhere else.

case_name=''
bytecode_stack_pad='5f'
swap1_start=0x90

for i in {1..16}; do
    printf '// SWAP%s\n' "$i"

    printf -v case_name 's%02d_a' "$i"

    printf -v pad '%0*s' "$((i - 1))"
    # printf 'PAD IS: >%s<\n' "$pad"

    printf -v middle_stack_pad '%s' "${pad//0/$bytecode_stack_pad}"

    # Test scenario.
    printf 'var %s = try basicBytecode("6006%s6009%x00");\n' "$case_name" "$middle_stack_pad" $((swap1_start + i - 1))

    # Assertions on test scenario behaviour.
    printf 'try expectEqual(%d, %s.stack.len);\n' $((i + 1)) "$case_name"
    printf 'try expectEqual(6, utils.stackOffTop(&%s, 0));\n' "$case_name"
    printf 'try expectEqual(9, utils.stackOffTop(&%s, %d));\n' "$case_name" $i

    printf '\n'
done
