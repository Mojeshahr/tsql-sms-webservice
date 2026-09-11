<div align="center">

<a href="https://payam-resan.com">
  <img src=".github/assets/logo.svg" width="64" height="64" alt="Payam Resan">
</a>

<h1>T-SQL examples for the Payam Resan SMS web service</h1>

Send SMS from inside SQL Server, through the <a href="https://payam-resan.com"><b>Payam Resan SMS panel</b></a><br>
One runnable script per API method, plus an outbox pattern

[![API](https://img.shields.io/badge/API-V3-0a7cbd)](https://payam-resan.com)
[![SQL Server](https://img.shields.io/badge/SQL%20Server-2016%2B-cc2927)](https://learn.microsoft.com/sql)
[![Dependencies](https://img.shields.io/badge/dependencies-none-2ea44f)](#quick-start)
[![License](https://img.shields.io/badge/license-MIT-6e7781)](LICENSE)

<a href="README.md">فارسی</a> · <b>English</b>

</div>

<sub>Looking for another language? The same examples exist for the others at
[github.com/Mojeshahr](https://github.com/Mojeshahr).</sub>

---

## Who this is for

Anyone running accounting, inventory, clinic or ERP software on SQL Server
whose business logic lives in stored procedures. When an invoice is issued or
stock hits the reorder point, the database is the first thing that knows, and
sending the message from there means no separate service to deploy.

## Two warnings first

**SQL Server cannot speak HTTP on its own.** The examples in `examples/v3/`
use `sp_OACreate`, which builds a Windows COM object. That means:

- `Ole Automation Procedures` has to be enabled on the whole SQL Server
  instance. That is a sysadmin action and it does not stop at this database.
- The COM object is created inside the SQL Server process. Skip `sp_OADestroy`
  and you leak memory until the service restarts.
- The call blocks. If the service is slow to answer, the transaction that
  called this code stays open just as long.

**This is not the recommended route.** The [outbox pattern](#the-outbox-pattern)
solves all three, and that is what to use in production. The inline examples are
for when you genuinely must send from inside a trigger or procedure.

## Quick start

Once per SQL Server instance:

```sql
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'Ole Automation Procedures', 1;
RECONFIGURE;
```

And once per database, so the key is not in the code:

```sql
CREATE TABLE dbo.PayamResanSettings (
    ApiKey nvarchar(100) NOT NULL,
    Sender bigint        NULL
);

INSERT INTO dbo.PayamResanSettings (ApiKey, Sender)
VALUES (N'123456-XXXXXXXXXXXXXXX', 30004040);

DENY SELECT ON dbo.PayamResanSettings TO public;
```

Then start with `account-info.sql`. It sends nothing, spends no credit, and if
it answers then the key is valid, OLE Automation is on, and the server can
reach the internet.

## Where the key lives

T-SQL has no environment variables, so the "read the key from the environment"
rule that every other repository in this organisation follows has no meaning
here. The database equivalent is a settings table with restricted access, the
`dbo.PayamResanSettings` above.

Three things matter: never write the key into the body of a procedure, take the
`DENY SELECT` seriously, and never commit a script that carries the real key.

## The outbox pattern

The recommended route for production. Your business logic writes one row and is
done; sending is a SQL Agent Job that runs outside your transaction.

| File | What it does |
|---|---|
| [01-schema.sql](outbox/01-schema.sql) | The settings table and the outbox table |
| [02-queue-sms.sql](outbox/02-queue-sms.sql) | The procedure your logic calls, which only writes a row |
| [03-send-outbox.ps1](outbox/03-send-outbox.ps1) | The sender, to run from an Agent Job every minute |

The whole value of the pattern is one decision: **the outbox table's key is the
`UserTraceId` sent to the service.** After a timeout you can ask
`StatusByUserTraceId` whether the message was registered, without storing the
service's own id anywhere.

What you gain: your business transaction never waits on the network, retries
and attempt counts fall out naturally, and nothing is enabled on the database
engine because the sender lives outside SQL Server.

What it costs: sending is no longer instant but up to a minute late, SQL Server
Express has no SQL Agent at all, and the sending half is PowerShell rather than
T-SQL.

## The methods

| Example | Method | What it does |
|---|---|---|
| [account-info.sql](examples/v3/account-info.sql) | `AccountInfo` | Credit and active lines |
| [send.sql](examples/v3/send.sql) | `Send` | Simple send over `GET` |
| [send-bulk.sql](examples/v3/send-bulk.sql) | `SendBulk` | One text to many recipients, with tracking ids |
| [send-multiple.sql](examples/v3/send-multiple.sql) | `SendMultiple` | A separate text per recipient |
| [token-list.sql](examples/v3/token-list.sql) | `TokenList` | The account's templates |
| [send-token-single.sql](examples/v3/send-token-single.sql) | `SendTokenSingle` | Send a template to one number |
| [send-token-single-get.sql](examples/v3/send-token-single-get.sql) | `SendTokenSingle` | The same, over `GET` |
| [send-token-multi.sql](examples/v3/send-token-multi.sql) | `SendTokenMulti` | One template, many recipients |
| [status-by-id.sql](examples/v3/status-by-id.sql) | `StatusById` | Status by the service's id |
| [status-by-user-trace-id.sql](examples/v3/status-by-user-trace-id.sql) | `StatusByUserTraceId` | Status by your own id |
| [get-inbox.sql](examples/v3/get-inbox.sql) | `GetInbox` | Messages people sent to your lines |

## The version floor is not uniform

The baseline is SQL Server 2016, where `JSON_VALUE` and `OPENJSON` arrived.
Two exceptions:

| File | Floor | Why |
|---|---|---|
| `status-by-id.sql`, `status-by-user-trace-id.sql` | 2017 | needs `STRING_AGG`, because `Ids` is an array of numbers and `FOR JSON` only produces arrays of objects |
| `send.sql` | 2019 | percent-encoding needs the UTF-8 bytes of the text, and UTF-8 collations arrived in 2019 |

## Things that will save you time

**Read the response with `sp_OAMethod`, not `sp_OAGetProperty`.** Both work
while the answer is short, but `sp_OAGetProperty` truncates long strings, and
the answer from `TokenList` or `GetInbox` gets long easily. Every example here
uses `sp_OAMethod @Object, N'responseText', @Response OUTPUT`.

**Do not drop `sp_OADestroy`.** The COM object stays inside the SQL Server
process, and every run without it is memory you do not get back until the
service restarts.

**Do not read the HTTP status code.** The service answers `200` to everything,
including a wrong key. Decide on the `Success` field. Every example here does.

**Build arrays with `JSON_QUERY`.** Without it the inner JSON string is
embedded as escaped text and the service does not see an array, with no clear
error to tell you so.

**Recipient numbers carry no leading zero.** Use `9121112222`, or
`989121112222` with the country code. A number that does not start with `9` or
`989` returns error code `13`.

**Never send directly from a trigger.** A trigger runs inside the transaction,
and a network call there means locks held open. A trigger should call
`dbo.QueueSms`.

## Before sending anything real

There is a sandbox server that answers exactly like production but sends no
message and spends no credit. Swap `V3` for `V3SandBox` in the URL. The one
exception is `TokenList`, which the sandbox does not implement.

## Layout

| Path | What it holds |
|---|---|
| `examples/v3/` | One self-contained example per service operation, using `sp_OACreate` |
| `outbox/` | The outbox pattern, the recommended production route |

The `v3` in the path is deliberate. A new service version means a new
`examples/v<n>/`, with the existing folder left alone.

## Documentation and support

The full guide to the web service is at
[docs.payam-resan.com](https://docs.payam-resan.com), and the machine-readable
OpenAPI description is in
[sms-webservice-spec](https://github.com/Mojeshahr/sms-webservice-spec).

Question or bug? [Open an issue](https://github.com/Mojeshahr/tsql-sms-webservice/issues)
or contact [support](https://payam-resan.com).

## License

Released under the MIT license. Full text in [`LICENSE`](LICENSE).

<br>
<div align="center">
  <sub>
    <img src=".github/assets/logo.svg" width="16" height="16" alt="" align="top">
    &nbsp;<b>Payam Resan SMS Panel - Moje Shahr</b>&nbsp;
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset=".github/assets/mojeshahr-dark.svg">
      <img src=".github/assets/mojeshahr-light.svg" width="16" height="16" alt="" align="top">
    </picture>
  </sub>
  <br>
  <sub>
    <a href="https://payam-resan.com">payam-resan.com</a>
    &nbsp;·&nbsp;
    <a href="https://mojeshahr.ir">mojeshahr.ir</a>
  </sub>
</div>
