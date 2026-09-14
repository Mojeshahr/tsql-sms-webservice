# Working with this repository

You are looking at T-SQL examples for the **Payam Resan** SMS web service
(`api.sms-webservice.com`, API V3), an Iranian SMS provider. Someone is probably
asking you to send SMS from inside SQL Server — usually from an ERP, accounting
or clinic system where the business logic already lives in the database.

Before you write anything, read the next two sections. This repository has a
recommended route and a discouraged one, and the discouraged one is the one that
looks easier.

## Read this first: these examples are parsed, not run

Every other language repository in this organisation is verified by executing
the examples. This one is not, and the reason is structural: `sp_OACreate`
builds a COM object, COM is Windows-only, and there is no SQL Server on the
machine where these are checked.

What is verified is a parse with Microsoft's own `ScriptDom`. That proves the
syntax is valid for SQL Server. It proves nothing about whether the OLE calls
succeed. Do not describe this repository as tested, and treat the first run on
the user's instance as the real test.

## Rule 1: prefer the outbox, not the inline call

`outbox/` is the recommended production route, and the inline examples are for
when you genuinely must send from inside a trigger or a procedure.

The business logic calls `dbo.QueueSms`, which only inserts a row and returns
its key; a SQL Agent job runs `03-send-outbox.ps1` every minute, batches the
pending rows and posts `SendMultiple`.

The load-bearing design decision is worth stating plainly: **the outbox table's
key is the `UserTraceId` sent to the service.** After a timeout you can ask
`StatusByUserTraceId` whether the message was registered, without storing the
service's own id anywhere.

What you gain: the business transaction never waits on the network, retries and
attempt counts fall out naturally, and nothing has to be enabled on the database
engine, because the sender lives outside SQL Server.

What it costs: sending is up to a minute late rather than instant, SQL Server
Express has no SQL Agent at all, and the sending half is PowerShell rather than
T-SQL.

**Never send directly from a trigger.** A trigger should call `dbo.QueueSms`.

## Rule 2: what the inline route costs

`Ole Automation Procedures` has to be enabled, and there are three consequences
the user must accept before you write this code:

1. It is enabled on the **whole SQL Server instance**. That is a sysadmin action
   and it does not stop at this database.
2. The COM object is created **inside the SQL Server process**. Skip
   `sp_OADestroy` and you leak memory until the service restarts.
3. **The call blocks.** If the service is slow to answer, the transaction that
   called this code stays open just as long.

```sql
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'Ole Automation Procedures', 1;
RECONFIGURE;
```

Start with `account-info.sql`: if it answers, the key is valid, OLE Automation
is on, and the server can reach the internet.

## Rule 3: the version floor is per file, not per repository

The baseline is SQL Server 2016, where `JSON_VALUE` and `OPENJSON` arrived. Two
exceptions, and both are real:

| File | Needs | Why |
|---|---|---|
| `status-by-id.sql`, `status-by-user-trace-id.sql` | 2017 | `STRING_AGG` — `Ids` is an array of numbers and `FOR JSON` only produces arrays of objects |
| `send.sql` | 2019 | percent-encoding needs the UTF-8 bytes of the text, and UTF-8 collations arrived in 2019 |

`send.sql` is also longer and more fragile than the alternative — use `SendBulk`
unless there is a specific reason not to.

`send-token-single-get.sql` stays at 2016 because all its values are ASCII. If a
parameter turns Persian, take the encoding pattern from `send.sql`.

## Rule 4: the key lives in a table, not the code

T-SQL has no environment variables, so the "read the key from the environment"
rule every other repository follows has no meaning here. The database equivalent
is a settings table with restricted access:

```sql
DECLARE @ApiKey nvarchar(100) = (SELECT TOP (1) ApiKey FROM dbo.PayamResanSettings);
```

Three things follow: never write the key into the body of a procedure, take the
`DENY SELECT` on that table seriously, and never commit a script that carries
the real key.

## Rule 5: read the response with `sp_OAMethod`, not `sp_OAGetProperty`

Both work while the answer is short, but `sp_OAGetProperty` truncates long
strings — and the answer from `TokenList` or `GetInbox` gets long easily. The
truncation is silent, so the symptom is a JSON parse that returns null for no
apparent reason.

```sql
EXEC sp_OAMethod @Object, N'responseText', @Response OUTPUT;
EXEC sp_OADestroy @Object;

IF JSON_VALUE(@Response, N'$.Success') <> N'true'
BEGIN
    DECLARE @Error nvarchar(400) = CONCAT(
        N'ناموفق. کد ', JSON_VALUE(@Response, N'$.ErrorCode'),
        N': ', JSON_VALUE(@Response, N'$.Error'));
    THROW 50000, @Error, 1;
END;
```

Note the order: **destroy the object before the `THROW`, never after it.** A
`THROW` skips everything below it, so a destroy placed after the check leaks on
exactly the path that fails most often.

`JSON_VALUE` returns text, so `Success` is compared against the string
`N'true'`.

## Rule 6: arrays need `JSON_QUERY`

Without it the inner JSON string is embedded as escaped text, the service does
not see an array, and there is no clear error to tell you so.

## Rule 7: `Success`, never the HTTP status

The service answers `200` to everything, including a wrong key and an empty
account. Check the creation of the COM object separately — a non-zero status
there usually means `Ole Automation Procedures` is off, not that the call
failed.

## Rule 8: pick the right method

| The user wants | Use | File |
|---|---|---|
| one text to many people | `SendBulk` | `send-bulk.sql` |
| a different text per person | `SendMultiple` | `send-multiple.sql` |
| a one-time password or code | `SendTokenSingle` | `send-token-single.sql` |
| a template to many people | `SendTokenMulti` | `send-token-multi.sql` |
| delivery status | `StatusByUserTraceId` | `status-by-user-trace-id.sql` |
| balance and sender lines | `AccountInfo` | `account-info.sql` |

**A one-time password goes through a template**, not free text — that is the
usual route for OTP, and the template fixes the sender line, which is why
`SendTokenSingle` takes no `Sender`. `token-list.sql` lists the account's
templates; `Status` `2` means approved and sendable, `1` awaiting review, `3`
rejected.

## Rule 9: phone numbers, the 99 cap, and `UserTraceId`

The service wants `9121112222` or `989121112222`. A number with a leading zero
gets error `13`, and `dbo.QueueSms` rejects it before it ever reaches the
service. Ninety-nine recipients per request is the ceiling for `SendBulk`,
`SendMultiple` and `SendTokenMulti` — the outbox sender batches at exactly that.

Always send a `UserTraceId`. After a timeout or error `100`, resending blind may
send twice; `StatusByUserTraceId` is the only safe way to learn whether the
message was registered. `StatusCode` of `8` means the id is not in the account,
so it is safe to send again.

`SendTokenSingle` is the exception: it has no such input, so its `UserTraceId`
comes back null. If a trace id is needed for an OTP, use `SendTokenMulti` with a
single recipient.

## Rule 10: know which errors are worth retrying

These never succeed on retry — fix the cause; retrying only burns the rate limit
until the account hits error `20`:

`1`, `2`, `3`, `6`, `8`, `9`, `10`, `11`, `12`, `13`, `14`, `19`

`19` is an empty balance; `10` means the SQL Server's outbound IP is not on the
account's allowlist. Treat any unknown code the way you treat `100`: unclear
outcome, check with `StatusByUserTraceId` before resending. The outbox caps
attempts at five for the same reason.

## Rule 11: delivery status is a poll, not a callback

Status codes `0`, `1`, `2`, `3` and `10` mean still in flight — query again
later, and not more often than every few minutes or you will hit error `20`. A
SQL Agent job every minute is the usual way people trip this. Everything else is
final. Branch on `StatusCode`, never on the `Status` text.

## Rule 12: `GetInbox` consumes what it returns

The service hands over each incoming message **once**. A job that fetches the
inbox and then rolls back has destroyed those messages — write them inside the
same transaction that reads them.

The sender field is called `Form`, not `From`. That is the service's spelling.

## Testing without spending credit

Replace `V3` with `V3SandBox` in the URL. No message is sent and no credit is
spent. `TokenList` is not implemented there.

The sandbox is a simulator, not a mirror of the account: credit is always
`1234567`, sender lines are invented, and **it accepts any key**. Success there
proves nothing about the user's real key.

## A note on the PowerShell sender

`outbox/03-send-outbox.ps1` must be saved with a UTF-8 BOM. Without it, Windows
PowerShell 5.1 reads it as ANSI and the Persian text breaks. It uses
`System.Data.SqlClient` from .NET and needs no PowerShell module.

## Where the authoritative answers are

- Method reference and error tables: <https://docs.payam-resan.com>
- Machine-readable OpenAPI: <https://github.com/Mojeshahr/sms-webservice-spec>

If the spec and these examples ever disagree, the spec wins — report it as a bug
rather than guessing.
