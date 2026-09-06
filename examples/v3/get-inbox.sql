-- GetInbox - پیامک‌هایی که کاربران به خطوط حساب شما فرستاده‌اند.
--
-- این یک استعلام است، نه webhook: سامانه چیزی به سرور شما نمی‌فرستد و باید
-- خودتان دوره‌ای صدایش بزنید. در SQL Server جای طبیعی این کار یک SQL Agent Job
-- است. فاصله را کمتر از چند دقیقه نگذارید، وگرنه به خطای ۲۰ می‌خورید.
--
-- پیش‌نیازها و جدول dbo.PayamResanSettings در README آمده.

-- docs:start
DECLARE @ApiKey nvarchar(100) = (SELECT TOP (1) ApiKey FROM dbo.PayamResanSettings);

DECLARE @Payload nvarchar(max) =
    (SELECT @ApiKey AS ApiKey FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

DECLARE @Object int, @Status int, @Response nvarchar(max);

EXEC @Status = sp_OACreate N'MSXML2.ServerXMLHTTP.6.0', @Object OUTPUT;
IF @Status <> 0 THROW 50000, N'ساخت شیء HTTP ناموفق بود. Ole Automation Procedures روشن است؟', 1;

EXEC sp_OAMethod @Object, N'open', NULL, N'POST',
     N'https://api.sms-webservice.com/api/V3/GetInbox', N'false';
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

-- نام ستون فرستنده در خود سرویس Form است، نه From. دنبال From نگردید.
SELECT ReceivedAt, Form, [To], [Text]
FROM OPENJSON(@Response, N'$.Result')
     WITH (ReceivedAt nvarchar(40) N'$.Time',
           Form bigint N'$.Form',
           [To] bigint N'$.To',
           [Text] nvarchar(max) N'$.Text');
-- docs:end
