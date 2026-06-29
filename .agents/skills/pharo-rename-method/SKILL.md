---
name: pharo-rename-method
description: Rename Pharo methods safely through Genie's `rename_method` MCP refactoring tool. Use when a selector should be renamed while preserving behavior, updating senders and symbol references across the live image, including as one step in larger refactorings such as clarify API names, split responsibilities, or move behavior behind better messages.
---

# Pharo Rename Method

Use this skill only for behavior-preserving selector renames in a live Genie image. Work through the `genie` MCP tools; do not edit Tonel files.

## Workflow

1. Establish a green baseline with `run_test` for the narrow class or package you will touch.

2. Map the impact before renaming:
   - `search_implementors` for the old selector.
   - `search_references` for the old selector.
   - `get_method_source` for representative implementors and callers.

3. Use `rename_method`, not `define_method` plus `remove_method`, when the intent is a real rename:
   - `class_name`: owning class name, without ` class`.
   - `method_name`: old selector string.
   - `new_method_name`: new selector string.
   - `is_class_method`: true for class-side methods, omit or false for instance-side methods.
   - `permutation`: optional argument-position array, for example `[2, 1]`. Omit it for ordinary same-order renames.

4. Read back the changed methods. Confirm:
   - The old selector is gone from the intended class.
   - The new selector exists.
   - Senders now use the new selector.
   - Any symbol-literal references that should change have changed.

5. Rerun the same tests. If the rename is part of a larger refactoring, stop at the first green rename before making the next structural move.

6. Save the image only through `save_image` gated on the relevant test class or package.

## Sequencing

Use rename-method early when an unclear selector is hiding the next move. For example:

- Rename a misleading public message before extracting a helper that will call it.
- Rename a collaborator-facing selector before moving behavior to that collaborator.
- Rename a protocol family one selector at a time, testing between each rename.
- Rename test fixture selectors with care: refactoring updates symbol literals. In tests that assert the old selector disappeared, write `'oldSelector' asSymbol`, not `#oldSelector`, or the refactoring may rewrite the assertion itself.

Do not use `rename_method` to change arity and behavior together. First make behavior-preserving same-arity renames green. Then do signature or behavior changes under a test-first workflow.

## Example

```json
{
  "class_name": "Invoice",
  "method_name": "total",
  "new_method_name": "totalAmount"
}
```
