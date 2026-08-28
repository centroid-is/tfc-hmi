# Access control — deployment

For whoever commissions a station. It covers the one thing in this design that
is a deployment step rather than app code: locking down the audit table on
Postgres. It also states, plainly, what that lockdown does and does not buy.

The design itself is `docs/access-control-spec.md`. This document does not
amend it.

---

## 1. What this protects against, and what it does not

The access control in this HMI is not an access control. It is an
**operational guardrail**.

Three credentials are held by the station, not by a person:

| Credential | Where it lives | What it authenticates |
|---|---|---|
| The OPC UA session username/certificate | `OpcUAConfig`, `state_man.dart` | the station |
| The Postgres password | `DatabaseConfig.postgres`, `database.dart` (`CENTROID_PGUSER` / `CENTROID_PGPASSWORD`, or the `database_config` entry in secure storage) | the station |
| The D-Bus credential behind system settings | the platform integration | the station |

Every one of them authenticates the *station*, never a person. Everything the
login screen, the role model and the audit trail do happens inside the Dart
process, and anyone with UaExpert or `psql` walks around all of it. A username
and password in this HMI tell you who was standing at the panel; they do not
stop anybody who is not standing at the panel.

That is acceptable, because the realistic failure in a plant is accident and
shift confusion, not a malicious insider. It stops being true — in the good
direction — when relay Phase 10 moves preferences onto the pipe and takes
credentials off the client.

**Say this out loud when you hand a station over.** The danger is not the
guardrail. The danger is somebody hearing "the HMI has logins" and
deprioritising network segmentation on the strength of it. The segmentation is
the control. This is the guardrail inside it.

---

## 2. The INSERT-only audit role (Postgres)

The audit trail is append-only and never pruned. The application enforces that
on its own side — the writer has one method and no way to remove a row, and the
collector's retention machinery refuses `audit_entry` by name
(`kRetentionExemptTables`, `packages/tfc_dart/lib/core/database.dart`). None of
that binds a `psql` session using the station's own credential.

What the database can enforce is a split: the station may **add** to the trail
and may not **remove from** it.

### When to run this

After the station has opened the database at least once, so schema v6 has
created `audit_entry` and its three indexes. The migration needs table
ownership to create indexes; step 4 below takes ownership away. Running these
statements before the first open leaves the migration unable to finish.

Run as a superuser or as the database owner.

### The SQL

```sql
-- 0. Names used below. Replace `hmi_station` with the role in the station's
--    CENTROID_PGUSER / database_config; the other two are created here.
--      hmi_station      -- what the HMI connects as
--      hmi_audit_writer -- may append to the trail, nothing else
--      hmi_audit_owner  -- owns the trail so hmi_station cannot re-grant itself

-- 1. A login-less owner for the audit table. Nobody connects as this role;
--    it exists so that the table's owner is not the station.
CREATE ROLE hmi_audit_owner NOLOGIN;

-- 2. A login-less role carrying exactly one privilege.
CREATE ROLE hmi_audit_writer NOLOGIN;

-- 3. Take ownership away from the station.
--    This step is the one that makes the rest real. In Postgres a table's
--    owner keeps full rights no matter what you REVOKE, and can simply
--    GRANT them back to itself. If audit_entry is still owned by
--    hmi_station, steps 5 and 6 are decoration.
ALTER TABLE audit_entry OWNER TO hmi_audit_owner;
--    The `id SERIAL` sequence is owned by the column, so the line above
--    already moved it. Stated explicitly anyway, because it costs nothing and
--    a sequence left behind is an INSERT that fails on a live station.
ALTER SEQUENCE audit_entry_id_seq OWNER TO hmi_audit_owner;

-- 4. Strip whatever the station had.
REVOKE ALL ON TABLE audit_entry FROM hmi_station;
REVOKE ALL ON SEQUENCE audit_entry_id_seq FROM hmi_station;

-- 5. Grant the writer role its one privilege — and the sequence rights that
--    an `id SERIAL` column needs. This is the step that gets forgotten:
--    without the sequence grant every INSERT fails with
--    "permission denied for sequence audit_entry_id_seq", and because the
--    sink swallows its failures the only sign is an AUDIT ROW LOST line in
--    the log.
GRANT INSERT ON TABLE audit_entry TO hmi_audit_writer;
GRANT USAGE, SELECT ON SEQUENCE audit_entry_id_seq TO hmi_audit_writer;

-- 6. Let the station act with the writer role's privileges and no others.
--    This relies on hmi_station having INHERIT, which is the default. If it
--    was created NOINHERIT the station gets nothing here and every audit
--    INSERT fails: `ALTER ROLE hmi_station INHERIT;`
GRANT hmi_audit_writer TO hmi_station;
```

### Verifying it

```sql
-- Should list exactly: hmi_audit_writer=a/hmi_audit_owner (a = INSERT),
-- plus the owner's own entry. No `d` (DELETE) or `w` (UPDATE) for hmi_station.
SELECT relname, relacl FROM pg_class WHERE relname = 'audit_entry';

-- Should fail. If it succeeds, step 3 did not happen.
SET ROLE hmi_station;
DELETE FROM audit_entry WHERE id = (SELECT min(id) FROM audit_entry);
RESET ROLE;
```

### What the station can and cannot do afterwards

- **Can** insert a row, including a row that says something untrue. The trail
  can be *forged* by anything holding the station's credential.
- **Cannot** delete a row, update a row, or `TRUNCATE` the table. What is in
  the trail stays in the trail.

That is the whole of the guarantee, and it is worth stating in exactly those
terms: a doc that promises more than this is worse than no doc, because the
next person to weigh network segmentation will weigh it against the promise.

### One thing that changes in Phase 5

The trail viewer reads `audit_entry`, and the SQL above grants the station no
`SELECT`. When that viewer lands, add:

```sql
GRANT SELECT ON TABLE audit_entry TO hmi_audit_writer;
```

`SELECT` does not weaken the property this section is about — reading a row
cannot remove it — but it does mean the trail is readable by anything holding
the station's credential, which was already true of the whole database.

---

## 3. SQLite (dev and demo) has neither separation

On SQLite there is no second role and nothing to revoke. The process owns the
file; anything that can open the file can rewrite it, and `sqlite3` on the
station's disk is all it takes.

**So on SQLite the audit trail is append-only by convention only.** The
in-process guarantees still hold — the sink cannot remove a row and retention
cannot sweep the table — and that is the whole of it. Nothing in section 2
applies. Do not read the existence of this document as meaning the guarantee
travels with the app.

SQLite is the development and demo backend. A commissioned station runs
Postgres, and section 2 is a commissioning step, not an optional hardening
pass.

---

## 4. Break-glass recovery

**The scenario.** The only Engineering account's password is lost, or the
person holding it has left. Nobody can reach the screens behind the
`administer` group, including the screen that creates users.

**Break-glass is documented, not built.** There is no recovery code, no
bootstrap flag and no default password — each of those is a permanent hole
kept open for a rare day. Engineering already holds the station's Postgres
credential, so the recovery is deleting a row, not reflashing a station. That
is a direct consequence of this being a guardrail rather than a security
boundary: the people who would have to be stopped by a real recovery mechanism
are the same people who hold the credential that defeats it.

**Recovering one account:**

```sql
DELETE FROM app_user WHERE username = 'the.locked.out.account';
```

Then re-create it from another account that still has `administer`.

**Recovering when no account can get in.** Empty the table:

```sql
DELETE FROM app_user;
```

This reopens the **first-user window**: creating a user is permitted only while
`app_user` is empty, so the next person to open the app creates a fresh
Engineering account and the door closes behind them again. That is the
supported way back in, and it is the same path a freshly commissioned station
takes.

Between the `DELETE` and that first new account the station is claimable by
whoever reaches it first. Do it when somebody is standing at the panel.

**The audit consequence, stated rather than hidden.** Neither `DELETE` is
audited. They happen in `psql`, outside the application, and the application is
the only thing that writes the trail. So a break-glass leaves `app_user` empty
with no row saying who emptied it or why — the audit trail will show the new
account's first login and nothing before it.

This is not a defect to fix. It is the same fact as section 1: anyone with
`psql` is outside everything this design can see. Record the break-glass in
whatever the site uses for change control, because the HMI cannot.

---

## 5. What must not be changed

**The `Operator` role cannot be deleted or renamed.** This is enforced in code
(`isProtectedRoleName` / `ProtectedRoleError` in `packages/tfc_access`), and
the guard is case-insensitive and whitespace-trimmed, so `operator` and
`" Operator "` are refused too.

**Editing `Operator`'s groups is not a small edit.** Anonymous resolves to
`Operator`, so its group set is what every logged-out panel on the floor may
do. Widening it hands those permissions to anybody walking past a panel;
narrowing it can lock out routine operation everywhere at once, with no
logged-in user anywhere to notice the change was deliberate. Change it with the
same care as a PLC download, and note the change in change control.

**The audit table's schema.** `audit_entry`'s columns are the audit contract
(`AuditRecord` in `packages/tfc_access`) one for one. Adding a column is a
migration; dropping or repurposing one silently changes what historic rows
mean.

**`kRetentionExemptTables`.** Removing `audit_entry` from it puts the trail
back within reach of the collector's retention sweeping. It is refused there so
that naming a collected key `audit_entry` — a free string in the collector
config — cannot reach the trail by accident.
