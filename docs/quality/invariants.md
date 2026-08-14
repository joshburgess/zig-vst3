# Quality Invariants

This file records contracts that span modules or cannot be established by a
single type. Later phases must link each invariant to code and verification.

## Ownership

- An allocation has one owner responsible for releasing it with the compatible
  allocator. Ownership transfer invalidates the sender's destruction duty.
- Partial initialization releases every acquired resource in reverse dependency
  order without publishing the incomplete object.
- A callback context remains at a stable address and alive until callback
  admission stops and all admitted callbacks drain.
- C, C++, host, and operating-system handles have one declared release path.

## State Mutation

- Parsing, restore, reconfiguration, and publication validate into inactive
  state before replacing active state.
- Failure leaves prior state usable unless the public contract explicitly names
  a terminal failure state.
- Versioned persistence retains stable field and parameter identifiers and
  bounds every decoded count before allocation or indexing.

## Threads and Realtime Work

- A cross-thread value is immutable while published or has a synchronization
  protocol that defines mutation and reclamation.
- Audio callbacks do not allocate, block, perform file or network I/O, wait for
  another thread, or execute work whose bound depends on unvalidated input.
- Teardown first prevents new callback admission, then drains admitted work,
  then releases callback-visible state.
- Atomic memory orders must follow from a written publication or ownership
  relationship. Performance alone does not justify a weaker order.

## Input and Arithmetic

- Parsers either consume input, return a complete result, or return an error.
  They cannot loop indefinitely on an unchanged cursor.
- Counts, offsets, sizes, timestamps, and sample positions are checked before
  narrowing, addition, multiplication, allocation, or slice construction.
- Invalid or non-finite input cannot cause partial output publication unless the
  public contract defines that behavior.

## ABI Boundaries

- External layouts, calling conventions, integer widths, and vtable order trace
  to a pinned declaration source and an automated comparison where possible.
- A foreign callback never lets a Zig error or panic cross the ABI boundary.
- Reference-counted identities return the same controlling identity required by
  their external interface contract and release exactly once at count zero.
