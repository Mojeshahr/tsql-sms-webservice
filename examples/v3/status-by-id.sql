-- StatusById - وضعیت پیامک با شناسه‌هایی که متد ارسال برگردانده است.
--
-- دسته‌ای بپرسید، نه یکی‌یکی. در SQL Server این طبیعی است: شناسه‌ها از یک
-- SELECT می‌آیند و یکجا فرستاده می‌شوند. فاصله استعلام‌ها را هم کمتر از چند
-- دقیقه نگذارید، وگرنه به خطای ۲۰ می‌خورید.
--
-- این فایل STRING_AGG دارد، پس کف نسخه‌اش SQL Server 2017 است نه 2016. دلیلش
-- این است که Ids آرایه‌ای از عدد است و FOR JSON فقط آرایه‌ای از شیء می‌سازد.
--
-- پیش‌نیازها و جدول dbo.PayamResanSettings در README آمده.

-- docs:start
DECLARE @ApiKey nvarchar(100) = (SELECT TOP (1) ApiKey FROM dbo.PayamResanSettings);

DECLARE @Ids TABLE (Id bigint);
INSERT INTO @Ids (Id) VALUES (9903211), (9903212);

DECLARE @Payload nvarchar(max) = (
    SELECT @ApiKey AS ApiKey,
           JSON_QUERY(CONCAT(N'[', (SELECT STRING_AGG(CAST(Id AS nvarchar(20)), N',') FROM @Ids), N']')) AS Ids
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
);

DECLARE @Object int, @Status int, @Response nvarchar(max);

EXEC @Status = sp_OACreate N'MSXML2.ServerXMLHTTP.6.0', @Object OUTPUT;
IF @Status <> 0 THROW 50000, N'ساخت شیء HTTP ناموفق بود. Ole Automation Procedures روشن است؟', 1;

EXEC sp_OAMethod @Object, N'open', NULL, N'POST',
     N'https://api.sms-webservice.com/api/V3/StatusById', N'false';
EXEC sp_OAMethod @Object, N'setRequestHeader', NULL,
     N'Content-Type', N'application/json; charset=utf-8';
EXEC sp_OAMethod @Object, N'send', NULL, @Payload;

EXEC sp_OAMethod @Object, N'responseText', @Response OUTPUT;
EXEC sp_OADestroy @Object;

IF JSON_VALUE(@Response, N'$.Success') <> N'true'
BEGIN
    DECLARE @Error nvarchar(400) = CONCAT(
        N'ناموفق. کد ', JSON_VALUE(@Response, N'$.ErrorCode'),
        N': ', JSON_VALUE(@Response, N'$.Error'));
    THROW 50000, @Error, 1;
END;

-- شرط را روی StatusCode بگذارید، نه روی متن Status. این پنج کد یعنی هنوز در
-- راه است و باید بعداً دوباره استعلام کنید، نه اینکه دوباره بفرستید.
SELECT Id,
       [Status],
       CASE WHEN StatusCode IN (0, 1, 2, 3, 10) THEN 1 ELSE 0 END AS AskAgainLater
FROM OPENJSON(@Response, N'$.Result')
     WITH (Id bigint N'$.Id',
           StatusCode int N'$.StatusCode',
           [Status] nvarchar(100) N'$.Status');
-- docs:end
