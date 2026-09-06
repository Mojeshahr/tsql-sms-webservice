-- جدول‌های الگوی صندوق خروجی.
--
-- این الگو راه پیشنهادی برای محیط عملیاتی است. منطق کسب‌وکار شما فقط یک ردیف
-- در SmsOutbox می‌نویسد و تمام می‌شود؛ فرستادن کار یک SQL Agent Job است که
-- بیرون از تراکنش شما اجرا می‌شود. سه چیز را حل می‌کند که نمونه‌های درجای
-- examples/v3 حل نمی‌کنند: تراکنش شما بابت شبکه معطل نمی‌ماند، تلاش دوباره
-- طبیعی است، و چیزی روی موتور دیتابیس باز نمی‌شود.
--
--   sqlcmd -S . -d YourDatabase -i outbox/01-schema.sql

-- docs:start
CREATE TABLE dbo.PayamResanSettings (
    ApiKey nvarchar(100) NOT NULL,
    Sender bigint        NULL
);

-- کلید یک راز است. فقط حسابی که Agent Job با آن اجرا می‌شود باید بخواندش.
DENY SELECT ON dbo.PayamResanSettings TO public;

CREATE TABLE dbo.SmsOutbox (
    -- کلید همین جدول، همان UserTraceId است که به سرویس فرستاده می‌شود. تمام
    -- ارزش این الگو در همین یک تصمیم است: بعد از یک timeout می‌شود با
    -- StatusByUserTraceId پرسید ثبت شده یا نه، بدون نگه‌داشتن Id سامانه.
    UserTraceId bigint        IDENTITY(1, 1) NOT NULL,
    Destination bigint        NOT NULL,
    [Text]      nvarchar(400) NOT NULL,
    QueuedAt    datetime2(0)  NOT NULL CONSTRAINT DF_SmsOutbox_QueuedAt DEFAULT SYSUTCDATETIME(),
    SentAt      datetime2(0)  NULL,
    ServiceId   bigint        NULL,
    Attempts    int           NOT NULL CONSTRAINT DF_SmsOutbox_Attempts DEFAULT 0,
    ErrorCode   int           NULL,
    [Error]     nvarchar(400) NULL,
    CONSTRAINT PK_SmsOutbox PRIMARY KEY CLUSTERED (UserTraceId)
);

-- ایندکس فیلترشده، چون تنها پرسشی که هر دقیقه اجرا می‌شود همین است.
CREATE NONCLUSTERED INDEX IX_SmsOutbox_Pending
    ON dbo.SmsOutbox (QueuedAt)
    WHERE SentAt IS NULL;
-- docs:end
