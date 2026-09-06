<div align="center">

<a href="https://payam-resan.com">
  <img src=".github/assets/logo.svg" width="64" height="64" alt="پیام رسان">
</a>

<h1>نمونه‌کدهای T-SQL وب‌سرویس پیام رسان</h1>

ارسال پیامک از داخل SQL Server، برای <a href="https://payam-resan.com"><b>پنل پیامکی پیام رسان</b></a><br>
یک اسکریپت قابل اجرا به‌ازای هر متد سرویس، به‌علاوه الگوی صندوق خروجی

[![API](https://img.shields.io/badge/API-V3-0a7cbd)](https://payam-resan.com)
[![SQL Server](https://img.shields.io/badge/SQL%20Server-2016%2B-cc2927)](https://learn.microsoft.com/sql)
[![Dependencies](https://img.shields.io/badge/dependencies-none-2ea44f)](#شروع-سریع)
[![License](https://img.shields.io/badge/license-MIT-6e7781)](LICENSE)

<b>فارسی</b> · <a href="README.en.md">English</a>

</div>

<sub>دنبال زبان دیگری هستید؟ همین نمونه‌ها برای زبان‌های دیگر هم در
[github.com/Mojeshahr](https://github.com/Mojeshahr) هست.</sub>

---

## این مخزن برای کیست

برای کسی که نرم‌افزار حسابداری، انبار، مطب یا ERP روی SQL Server دارد و منطق
کسب‌وکارش در استورد پروسیجر زندگی می‌کند. وقتی فاکتور صادر می‌شود یا موجودی به
حد سفارش می‌رسد، خود دیتابیس اولین جایی است که این را می‌فهمد، و فرستادن پیامک
از همان‌جا یعنی نیازی به سرویس جداگانه نیست.

## پیش از هر چیز، دو هشدار

**خود SQL Server بلد نیست HTTP حرف بزند.** نمونه‌های `examples/v3/` از
`sp_OACreate` استفاده می‌کنند، که یک شیء COM ویندوزی می‌سازد. این یعنی:

- باید `Ole Automation Procedures` روی کل نمونه SQL Server روشن شود، که کار
  sysadmin است و فقط این دیتابیس را تحت تأثیر نمی‌گذارد.
- شیء COM داخل پراسس خود SQL Server ساخته می‌شود. اگر `sp_OADestroy` فراموش
  شود، حافظه نشت می‌کند.
- تماس مسدودکننده است. اگر سرویس کند جواب بدهد، تراکنشی که این کد را صدا زده
  همان‌قدر باز می‌ماند.

**راه پیشنهادی این نیست.** الگوی [صندوق خروجی](#الگوی-صندوق-خروجی) هر سه مورد
بالا را حل می‌کند و برای محیط عملیاتی همان را بردارید. نمونه‌های درجا برای
وقتی‌اند که واقعاً باید از داخل یک تریگر یا پروسیجر بفرستید.

## شروع سریع

یک بار روی نمونه SQL Server:

```sql
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'Ole Automation Procedures', 1;
RECONFIGURE;
```

و یک بار روی دیتابیس، برای اینکه کلید داخل کد نباشد:

```sql
CREATE TABLE dbo.PayamResanSettings (
    ApiKey nvarchar(100) NOT NULL,
    Sender bigint        NULL
);

INSERT INTO dbo.PayamResanSettings (ApiKey, Sender)
VALUES (N'123456-XXXXXXXXXXXXXXX', 30004040);

DENY SELECT ON dbo.PayamResanSettings TO public;
```

بعد با `account-info.sql` شروع کنید: چیزی ارسال نمی‌کند، اعتباری مصرف نمی‌کند،
و اگر جواب داد یعنی هم کلید سالم است، هم Ole Automation روشن است، هم سرور به
اینترنت دسترسی دارد.

## کلید حساب کجا می‌نشیند

در T-SQL متغیر محیطی وجود ندارد، پس قاعده «کلید را از محیط بخوان» که در بقیه
مخزن‌های این سازمان هست اینجا معنا ندارد. معادل درستش یک جدول تنظیمات با
دسترسی محدود است، همان `dbo.PayamResanSettings` بالا.

سه چیز را رعایت کنید: کلید را داخل متن پروسیجر ننویسید، `DENY SELECT` را جدی
بگیرید، و اسکریپتی که کلید واقعی در آن است را در سورس‌کنترل نگذارید.

## الگوی صندوق خروجی

راه پیشنهادی برای محیط عملیاتی. منطق کسب‌وکار شما فقط یک ردیف می‌نویسد و تمام
می‌شود؛ فرستادن کار یک SQL Agent Job است که بیرون از تراکنش شما اجرا می‌شود.

<div dir="rtl">

| فایل | کار |
|---|---|
| [01-schema.sql](outbox/01-schema.sql) | جدول تنظیمات و جدول صندوق خروجی |
| [02-queue-sms.sql](outbox/02-queue-sms.sql) | پروسیجری که منطق شما صدا می‌زند و فقط یک ردیف می‌نویسد |
| [03-send-outbox.ps1](outbox/03-send-outbox.ps1) | فرستنده، برای اجرا از Agent Job هر یک دقیقه |

</div>

تمام ارزش این الگو در یک تصمیم است: **کلید جدول صندوق خروجی همان `UserTraceId`
است که به سرویس فرستاده می‌شود.** بعد از یک timeout می‌شود با
`StatusByUserTraceId` پرسید ثبت شده یا نه، بدون اینکه Id سامانه جایی نگه داشته
شود.

سه چیزی که به دست می‌آورید: تراکنش کسب‌وکار شما بابت شبکه معطل نمی‌ماند، تلاش
دوباره و شمارش تلاش‌ها طبیعی درمی‌آید، و چیزی روی موتور دیتابیس باز نمی‌شود
چون فرستنده بیرون از SQL Server است.

سه هزینه‌اش را هم بدانید: ارسال دیگر آنی نیست بلکه تا یک دقیقه تأخیر دارد،
SQL Server Express اصلاً SQL Agent ندارد، و بخش فرستنده پاورشل است نه T-SQL.

## متدها

<div dir="rtl">

| نمونه | متد | کار |
|---|---|---|
| [account-info.sql](examples/v3/account-info.sql) | `AccountInfo` | اعتبار و خطوط فعال |
| [send.sql](examples/v3/send.sql) | `Send` | ارسال ساده با `GET` |
| [send-bulk.sql](examples/v3/send-bulk.sql) | `SendBulk` | یک متن به چند گیرنده، با شناسه پی‌گیری |
| [send-multiple.sql](examples/v3/send-multiple.sql) | `SendMultiple` | متن جدا برای هر گیرنده |
| [token-list.sql](examples/v3/token-list.sql) | `TokenList` | فهرست قالب‌ها |
| [send-token-single.sql](examples/v3/send-token-single.sql) | `SendTokenSingle` | ارسال قالب به یک شماره |
| [send-token-single-get.sql](examples/v3/send-token-single-get.sql) | `SendTokenSingle` | همان، با `GET` |
| [send-token-multi.sql](examples/v3/send-token-multi.sql) | `SendTokenMulti` | یک قالب، چند گیرنده |
| [status-by-id.sql](examples/v3/status-by-id.sql) | `StatusById` | وضعیت با شناسه سامانه |
| [status-by-user-trace-id.sql](examples/v3/status-by-user-trace-id.sql) | `StatusByUserTraceId` | وضعیت با شناسه خودتان |
| [get-inbox.sql](examples/v3/get-inbox.sql) | `GetInbox` | پیامک‌های رسیده |

</div>

## کف نسخه، که یکسان نیست

پایه مخزن SQL Server 2016 است، چون `JSON_VALUE` و `OPENJSON` از آنجا آمده‌اند.
دو استثنا دارد:

<div dir="rtl">

| فایل | کف نسخه | چرا |
|---|---|---|
| `status-by-id.sql` و `status-by-user-trace-id.sql` | 2017 | `STRING_AGG` لازم است، چون `Ids` آرایه‌ای از عدد است و `FOR JSON` فقط آرایه‌ای از شیء می‌سازد |
| `send.sql` | 2019 | برای percent-encode باید بایت‌های UTF-8 گرفته شود و collation از نوع UTF-8 از ۲۰۱۹ آمده |

</div>

## چند نکته که وقت‌تان را می‌خرد

**پاسخ را با `sp_OAMethod` بخوانید، نه `sp_OAGetProperty`.** هر دو کار
می‌کنند تا وقتی پاسخ کوتاه است، ولی `sp_OAGetProperty` روی رشته‌های بلند
بریده برمی‌گرداند و پاسخ `TokenList` یا `GetInbox` به‌راحتی بلند می‌شود. همه
نمونه‌های اینجا `sp_OAMethod @Object, N'responseText', @Response OUTPUT`
دارند.

**فراخوانی `sp_OADestroy` را حذف نکنید.** شیء COM داخل پراسس SQL Server
می‌ماند و هر اجرای بی‌آزادسازی حافظه‌ای است که تا ری‌استارت سرویس برنمی‌گردد.

**کد وضعیت HTTP را نخوانید.** سرویس همیشه `200` برمی‌گرداند، حتی وقتی کلید
اشتباه است. تصمیم را از فیلد `Success` بگیرید. هر نمونه اینجا همین کار را
می‌کند.

**آرایه را با `JSON_QUERY` بسازید.** بدون آن، رشته JSON داخلی به‌صورت متن
escape شده در بدنه می‌نشیند و سرویس آن را آرایه نمی‌بیند، بدون اینکه خطای
روشنی بدهد.

**شماره گیرنده صفر ابتدایی ندارد.** یعنی `9121112222` یا با کد کشور
`989121112222`. شماره‌ای که با `9` یا `989` شروع نشود کد خطای `13` می‌گیرد.

**از تریگر مستقیم نفرستید.** تریگر داخل تراکنش اجرا می‌شود و یک تماس شبکه
آنجا یعنی قفل باز نگه‌داشته‌شده. تریگر باید `dbo.QueueSms` را صدا بزند.

## پیش از ارسال واقعی

یک سرور آزمایشی هست که مثل سرور عملیاتی جواب می‌دهد ولی پیامکی نمی‌فرستد و
اعتباری مصرف نمی‌کند. کافی است `V3` در نشانی را با `V3SandBox` عوض کنید. تنها
استثنا `TokenList` است که روی آن سرور پیاده نشده.

## ساختار

<div dir="rtl">

| مسیر | چه چیزی دارد |
|---|---|
| `examples/v3/` | یک نمونه مستقل به‌ازای هر عملیات سرویس، با `sp_OACreate` |
| `outbox/` | الگوی صندوق خروجی، راه پیشنهادی محیط عملیاتی |

</div>

عدد `v3` در مسیر عمدی است. نسخه تازه سرویس یعنی پوشه `examples/v<n>/` تازه، و
پوشه موجود دست‌نخورده می‌ماند.

## مستندات و پشتیبانی

راهنمای کامل وب‌سرویس در [docs.payam-resan.com](https://docs.payam-resan.com)
است. توصیف ماشین‌خوان OpenAPI هم در
[sms-webservice-spec](https://github.com/Mojeshahr/sms-webservice-spec).

## مجوز

منتشرشده با مجوز MIT. متن کامل در [`LICENSE`](LICENSE).
