# Agent guide

Runnable T-SQL examples for the Payam Resan SMS web service. One script per API
method, plus an outbox pattern that is the recommended production route.

## Rule one: this repository cannot be run here

Every other language repository in this organisation is verified by executing
the examples. This one is not, and the reason is structural rather than
temporary: `sp_OACreate` builds a COM object, COM is a Windows technology, and
there is no SQL Server available on this machine at all.

What **is** verified, and what every change must keep passing, is a parse with
Microsoft's own T-SQL parser:

```bash
docker run --rm -v "$PWD:/w:ro" tsql-check /w/examples/v3/*.sql /w/outbox/*.sql
```

The image is built from `mcr.microsoft.com/dotnet/sdk:8.0` plus the NuGet
package `Microsoft.SqlServer.TransactSql.ScriptDom`, using `TSql160Parser`. That
proves the syntax is valid for SQL Server. It proves nothing about whether the
OLE calls succeed. Say so when reporting; do not describe this repository as
tested.

## Rule two: the key comes from a table, not the code

T-SQL has no environment variables, so the organisation-wide rule cannot be
followed literally. The equivalent is `dbo.PayamResanSettings`, read at the top
of every example:

```sql
DECLARE @ApiKey nvarchar(100) = (SELECT TOP (1) ApiKey FROM dbo.PayamResanSettings);
```

That table is the reader's own infrastructure, defined in the README, not a
helper from this repository. Never write a key into the body of an example, and
never commit a script carrying a real one.

## Rule three: the examples are the documentation

Each file carries `-- docs:start` and `-- docs:end`. The region between them is
lifted verbatim into the method's page on docs.payam-resan.com, so it is read by
people who have never seen this repository.

Two consequences:

- **Full-line comments are stripped** when the region is lifted. Anything the
  reader must see has to be code. The `Success` check is an `IF`, not a note.
- The file name matches the reference page slug exactly: `send-bulk.sql`,
  `status-by-user-trace-id.sql`. A path with two variants gets two files, the
  plain name for `POST` and a `-get` suffix for `GET`.

The full contract lives in the `handbook` repository, section `docs-site`, file
`code-samples.md`.

## Rule four: check Success, and always destroy the object

The service answers `200` to everything, so the only signal is the envelope:

```sql
IF JSON_VALUE(@Response, N'$.Success') <> N'true'
```

And `sp_OADestroy` runs in every example, before the check. A COM object left
behind stays inside the SQL Server process until the service restarts. Put the
destroy **before** the `THROW`, never after it.

Read the body with `sp_OAMethod`, not `sp_OAGetProperty`: the latter truncates
long strings, and `TokenList` and `GetInbox` return long ones.

## Rule five: JSON arrays need JSON_QUERY

`FOR JSON` nested in a subquery embeds correctly, but a string built by hand
does not: without `JSON_QUERY` it lands in the body as escaped text and the
service silently fails to see an array. An array of bare numbers, as `Ids` and
`UserTraceIds` need, has no `FOR JSON` form at all and is built with
`STRING_AGG` inside `JSON_QUERY`.

## Rule six: state the version floor per file

The baseline is SQL Server 2016 for `JSON_VALUE` and `OPENJSON`. Two files sit
higher and each says so in its own header: the two status files need 2017 for
`STRING_AGG`, and `send.sql` needs 2019 for a UTF-8 collation, because
percent-encoding requires the UTF-8 bytes and T-SQL has no built-in encoder.

If a change raises a floor, write it in the file header **and** in the README
table. A floor that is only in one of the two is how this gets wrong.

## Rule seven: a version is a folder

A new service version means a new `examples/v<n>/`. No file inside an existing
version folder is moved or renamed; older versions still have users.

## Secrets

No key, no real phone number and no customer name goes into a file here, not
even a dead one. Example numbers are `9121112222` upward and the example key is
`123456-XXXXXXXXXXXXXXX`.

## Layout

| Path | What it holds |
|---|---|
| `examples/v3/` | one self-contained script per service operation, using `sp_OACreate` |
| `outbox/` | schema, queueing procedure and PowerShell sender for the recommended pattern |

## Before every commit

```bash
docker run --rm -v "$PWD:/w:ro" tsql-check /w/examples/v3/*.sql /w/outbox/*.sql
```

The PowerShell sender in `outbox/` is checked the way the powershell repository
checks its own files: it must start with a UTF-8 BOM and parse without errors.

## Git

Semantic messages, `type(scope): subject`, with no explanatory body and no
attribution trailer. Commits here are authored as Payam Resan.
