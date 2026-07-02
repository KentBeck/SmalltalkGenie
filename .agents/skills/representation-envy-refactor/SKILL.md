---
name: representation-envy-refactor
description: Use when reviewing or refactoring code that pulls apart another object's private representation, such as raw limb/byte/slot access, slice constructors, or helper methods that expose internal storage. Guides agents to find representation envy and suggest moving behavior onto the object that owns the representation, using live-image Genie tools when working in Pharo.
---

# Representation Envy Refactor

Use this skill when a change or review involves code that knows too much about another object's internal storage. The goal is to move the operation to the object that owns the representation, leaving callers to ask for intent rather than assemble internals.

## Smell

Look for code outside the representation owner that:

- Reads raw storage with selectors such as `basicAt:`, `byteAt:`, `limbAt:`, `slotAt:`, or `instVarAt:`.
- Builds slices or copies from another object's internal indexes.
- Passes raw representation into constructors, for example `sign:limbs:`, `limbs:count:`, `bytes:`, or similar.
- Repeats loops like `Array new: obj size. 1 to: ... do: [ :i | array at: i put: (obj rawAt: i) ]`.
- Computes offsets, byte indexes, limb indexes, masks, carries, or sign-extension details for a value it does not own.

This is not automatically wrong inside low-level algorithm kernels. It is suspicious when the caller can be rewritten as a clear request to the representation owner.

## Workflow

1. Establish a green baseline before refactoring.
2. Search for representation-shaped selectors and constructors:
   - In Genie/Pharo, use `search_references`, `search_implementors`, `search_methods_like`, `get_method_source`.
   - Search for names like `basicAt:`, `limbAt:`, `byteAt:`, `copyFrom:to:`, `limbs`, `digits`, `bytes`, `slot`, `raw`, `from:to:`.
3. Classify each hit:
   - **Owner-internal**: code inside the class that owns the representation. Usually acceptable, but may still deserve a named helper.
   - **Representation envy**: code in another class, class-side constructor, service, or domain object that extracts or assembles internals from an object.
   - **Algorithm boundary**: code that must operate on raw arrays for a specific algorithm. Prefer one explicit boundary method that prepares the representation.
4. Suggest or perform the smallest refactor:
   - Move the representation-copying or slicing operation onto the owning object.
   - Name it by intent, not storage mechanics, when possible.
   - Prefer `receiver operationFrom:to:` over `OwnerClass operationFrom: receiver startingAt: count:`.
   - Keep constructors simple; do not make them decode another instance's internals.
5. Update callers one at a time and rerun focused tests after each step.
6. Remove obsolete exposing methods only after all references are gone.

## Example

Before:

```smalltalk
lo := BigInt sign: 1 limbsFrom: r startingAt: 1 count: 16.
hi := BigInt sign: 1 limbsFrom: r startingAt: 17 count: limbCount - 16.
```

After:

```smalltalk
lo := r copyPositiveFrom: 1 to: 16.
hi := r copyPositiveFrom: 17 to: limbCount.
```

The byte layout and zero trimming stay inside `BigInt`, which owns the packed limb representation.

## Reporting

When asked to find cases, report:

- Exact methods that look like representation envy.
- Why each case leaks representation knowledge.
- Whether it is safe to refactor now or should remain an algorithm boundary.
- The next smallest test-backed refactor.
