-- AccountInfo - اعتبار باقی‌مانده و خطوط فعال حساب.
--
-- سبک‌ترین متد سرویس و بهترین راه آزمودن کلید: چیزی ارسال نمی‌کند، اعتباری
-- مصرف نمی‌کند، و حتی با اعتبار صفر هم جواب می‌دهد.
--
-- پیش‌نیازها، هر دو یک بار روی نمونه SQL Server:
--
--   EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
--   EXEC sp_configure 'Ole Automation Procedures', 1; RECONFIGURE;
--
-- و جدول تنظیمات که کلید در آن می‌نشیند، نه داخل کد:
--
--   CREATE TABLE dbo.PayamResanSettings (
--       ApiKey  nvarchar(100) NOT NULL,
--       Sender  bigint        NULL
--   );
--
-- شرح هر دو و دسترسی‌هایی که باید روی آن جدول بگذارید در README آمده.
-- کف نسخه SQL Server 2016 است، چون JSON_VALUE و OPENJSON از آنجا هستند.

-- docs:start
DECLARE @ApiKey nvarchar(100) = (SELECT TOP (1) ApiKey FROM dbo.PayamResanSettings);

DECLARE @Payload nvarchar(max) =
    (SELECT @ApiKey AS ApiKey FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

DECLARE @Object int, @Status int, @Response nvarchar(max);

EXEC @Status = sp_OACreate N'MSXML2.ServerXMLHTTP.6.0', @Object OUTPUT;
IF @Status <> 0 THROW 50000, N'ساخت شیء HTTP ناموفق بود. Ole Automation Procedures روشن است؟', 1;

EXEC sp_OAMethod @Object, N'open', NULL, N'POST',
     N'https://api.sms-webservice.com/api/V3/AccountInfo', N'false';
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

SELECT JSON_VALUE(@Response, N'$.Result.Credit') AS Credit;

SELECT Sender
FROM OPENJSON(@Response, N'$.Result.AvailableSenders')
     WITH (Sender bigint N'$');
-- docs:end
