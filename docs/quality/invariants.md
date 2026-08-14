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
- Resource workers publish completed data but do not invoke host callbacks.
  Control-thread `poll` or `waitAndPoll` collects completion and invokes any
  `publicationReady` callback synchronously.
- Host restart requests run only from a host-approved control or UI callback,
  never from an audio, resource, device, or importer worker.
- Dynamic audio-bus topology snapshots and mutations through
  `HostRequestSink` or the raw `SimpleEffect` API run only on a non-realtime
  control thread. Debug and test realtime scopes reject the call before it can
  reach component locking.
- Native callback teardown publishes admission closure, stops or unregisters
  the platform source, drains every callback admitted before closure, and only
  then clears callback-visible state. Callback release synchronizes with the
  drain before the context can be freed.
- Native MIDI admission uses one atomic state containing a closed bit and an
  active count. Opening publishes callback-visible fields with release order;
  successful admission acquires them while incrementing the same state;
  closure and admission therefore have one atomic linearization point.
  Callback release uses release order, and the control-thread drain observes
  zero with acquire order before clearing the callback or parser.
- CoreAudio session and topology callbacks use one atomic state containing a
  closed bit and an active count. Admission and closure modify that same word,
  so a callback that observed an open gate before teardown cannot increment
  after teardown has observed zero. Callback release uses release order, and
  teardown drains with acquire order after stopping or unregistering the
  platform source and before freeing callback-visible state.
- ARA audio-reader slots use one atomic state containing a closed bit and a
  lease count. Opening release-publishes the complete reader state. Read
  admission acquires that publication while incrementing the same word. Close
  atomically sets the closed bit, waits with acquire order for every
  release-published lease to drain, destroys the host reader, and leaves the
  vacant slot closed. A host reader is never created unless create, read, and
  destroy callbacks are all present.
- A platform stop, disconnect, dispose, or unregister operation must prevent
  new foreign callback entry after it returns. The local admission gate covers
  callbacks already inside the adapter; it cannot make a platform that invokes
  a freed callback context conform to this required platform contract.

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
