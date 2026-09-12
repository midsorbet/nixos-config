# Discoverability Rules

Start with the repository's existing terminology, naming patterns, and source
layout. A familiar generic name such as `config.ts` or `parse` can be the most
discoverable choice when its surrounding convention supplies the context.
Qualify a name when real searches are ambiguous, not to satisfy an arbitrary
naming quota or force uniqueness across unrelated modules.

Keep one authoritative definition for a concept. Reuse the project's spelling
rather than introducing synonyms. If a task genuinely changes a public
contract and its existing name becomes misleading, choose a clearer name,
update all callers, and remove the obsolete path. Do not rename a stable public
API or reorganize unrelated modules solely for this guidance, and do not add a
deprecated alias as a substitute for a clean cutover.

Use types where they prevent a plausible mistake. Distinct types may be useful
for easily swapped identifiers or units, capability types for privileged
operations, and discriminated unions for states with different valid data.
These are contextual tools, not requirements for every primitive or function.
Prefer type names and compiler errors that use the domain vocabulary.

Document meaningful constraints near the definition when the signature cannot
express them and omission could mislead a caller—for example units, timezone,
ownership, ordering, or whether a timestamp came from the source or insertion.
Use the ordinary phrase someone is likely to search for. Exports whose contract
is already clear do not need a ceremonial comment.

Make operational strings searchable and actionable. Preserve event names,
flags, and error codes as stable literals when operators or callers use them,
and include enough context in errors to explain the failed action and relevant
subject. A stable code or literal phrase can link a log entry to its source;
there is no need to invent a branded prefix for every message.

Place behavior where maintainers of this repository would expect to find it.
Keep a helper beside its sole caller when that aids understanding, and extract
or split a module when doing so improves a real navigation or ownership
boundary. Existing file and test-layout conventions take precedence over
forcing each concept into its own file.
