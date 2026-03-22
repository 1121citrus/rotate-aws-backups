# Design Notes

Developer-facing notes on non-obvious design decisions and alternatives
that were considered but not adopted.

---

## Multi-file backup sets (grouped rotation)

### The problem

A single backup event often produces more than one S3 object.  For example,
`mokerlink-backup` uploads:

```text
20260313T000000-switch-1-mokerlink-1.0.0.27-config-backup.tar.bz2.gpg
20260313T000000-switch-1-mokerlink-1.0.0.27-config-backup.tar.sha1
```

Both objects carry the same timestamp and together form one logical backup.
They must be kept or discarded **as a unit**: preserving the encrypted archive
while deleting its checksum (or vice versa) produces a useless half-backup.

The original implementation created one WORKDIR file per S3 key and let
`rotate-backups` evaluate each file independently.  Because `rotate-backups`
has no concept of related files, it could — and in practice did — preserve one
half of a backup set while deleting the other.

### Solution adopted: timestamp-based grouping (local to rotate-aws-backups)

Objects are grouped by `(S3 directory prefix, timestamp)`.  The timestamp is
extracted from the object key with the bash ERE `[0-9]{8}[Tt][0-9]{6}`,
which matches the default `TIMESTAMP_PATTERN` used by `rotate-backups`.

During the listing phase, only the **first key seen** in each group gets a
representative file in `WORKDIR`.  All member keys are appended to a group
members file in a separate `METADIR` temp directory (never seen by
`rotate-backups`).

During the rotation phase, when `rotate-backups` emits a decision (delete /
preserve / ignore) for a representative file, the script looks up the group
members file and applies the same decision to **every member of the set**.

The behaviour is enabled by default (`GROUP_BY_TIMESTAMP=true`) and can be
disabled with `--no-group` (or `GROUP_BY_TIMESTAMP=false`) to restore the
pre-grouping per-file behaviour if needed.

Key properties of this approach:

- Entirely local to `rotate-aws-backups`; no changes to backup producers.
- Correct across S3 pagination: the members file accumulates on disk across
  page iterations, so two files from the same event on different pages of a
  large bucket listing are still grouped correctly.
- Degrades gracefully: objects with no recognisable timestamp form singleton
  groups and behave exactly as before.
- The grouping key is `dirname(key)::timestamp`, encoded as a filename by
  replacing `/` with `__`.  A theoretical collision exists if an S3 directory
  name contains `__` immediately before a `::` separator, but this is
  negligible in practice.

### Alternatives considered

#### Strip file extensions to derive a common basename

**Idea:** strip all extensions from each key (`${key%%.*}`) and use the
resulting stem as the group identifier.

**Why not adopted:** filenames that embed version numbers (e.g.
`...mokerlink-1.0.0.27-config-backup.tar.bz2.gpg`) contain dots that are
part of the stem, not the extension.  `${key%%.*}` strips too aggressively
(`...mokerlink-1` instead of `...mokerlink-1.0.0.27-config-backup`).  Any
purely syntactic extension-stripping heuristic is fragile because S3 key
naming conventions vary across backup producers.

Timestamp-based grouping avoids this entirely: the timestamp is the canonical
identifier of a backup event regardless of how many dots follow it.

#### Require backup producers to bundle all assets into one file

**Idea:** each backup tool produces a single archive containing both the
payload and its metadata (checksum, manifest, etc.).  `rotate-aws-backups`
needs no change.

**Why not adopted:** retrofitting every backup producer is a large coordinated
change and imposes constraints on tools that are otherwise independent.  The
local fix in `rotate-aws-backups` achieves the same outcome with no changes
outside this repository.

This remains a worthwhile long-term convention for new backup tools.

#### Store all assets for one event under a common S3 prefix (virtual folder)

**Idea:** each backup event uploads its files under a shared prefix, e.g.:

```text
20260313T000000-switch-1-mokerlink-1.0.0.27-config-backup/
    config-backup.tar.bz2.gpg
    config-backup.tar.sha1
```

`rotate-backups` natively treats a directory whose name matches a timestamp
pattern as a single backup.  With S3's flat key model, this requires
`list-objects-v2` to group by common prefix rather than by individual key.

**Why not adopted:** requires all backup producers to adopt the prefix
convention, and requires non-trivial changes to the S3 listing logic in
`rotate-aws-backups` (prefix grouping rather than flat key enumeration).  The
timestamp-based in-process grouping achieves the same atomicity guarantee with
a smaller, self-contained change.

This convention may be worth standardising for future backup tools.

#### Manifest file per backup event

**Idea:** each backup upload includes a sidecar manifest file listing the
companion objects.  `rotate-aws-backups` reads manifests to expand groups.

**Why not adopted:** requires backup producers to generate manifests; adds a
coupling between `rotate-aws-backups` and a manifest format; and introduces a
failure mode if the manifest is uploaded but a companion file is not (or vice
versa).  The timestamp-based approach derives grouping purely from S3 key
names with no producer coordination.

---

## WORKDIR / METADIR separation

The group members files are stored in a separate `METADIR` temp directory
rather than a subdirectory of `WORKDIR`.  This prevents `rotate-backups` from
ever seeing them: if they were under `WORKDIR`, `rotate-backups` would scan
them, find no timestamp in their names, and emit "Ignoring" lines that would
pollute the output and potentially interact badly with `DELETE_IGNORED=true`.

Both `WORKDIR` and `METADIR` are cleaned up by the `cleanup()` trap.
