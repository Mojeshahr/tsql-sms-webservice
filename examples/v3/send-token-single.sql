-- SendTokenSingle - ارسال قالب به یک شماره، با بدنه JSON.
--
-- مسیر معمول رمز یک‌بارمصرف. خط فرستنده ورودی ندارد؛ سامانه آن را از روی خود
-- قالب برمی‌دارد. همین واریانت POST را به کار ببرید، نه GET: در GET هم کلید
-- حساب و هم خود رمز داخل نشانی و لاگ وب‌سرور می‌نشینند، و در T-SQL دردسر
-- percent-encode را هم اضافه می‌کند.
--
-- پیش‌نیازها و جدول dbo.PayamResanSettings در README آمده.

-- docs:start
DECLARE @ApiKey nvarchar(100) = (SELECT TOP (1) ApiKey FROM dbo.PayamResanSettings);

DECLARE @Payload nvarchar(max) = (
    SELECT @ApiKey AS ApiKey,
           N'verifycode' AS TemplateKey,
           CAST(9121112222 AS bigint) AS Destination,
           N'123456' AS p1
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
);

DECLARE @Object int, @Status int, @Response nvarchar(max);

EXEC @Status = sp_OACreate N'MSXML2.ServerXMLHTTP.6.0', @Object OUTPUT;
IF @Status <> 0 THROW 50000, N'ساخت شیء HTTP ناموفق بود. Ole Automation Procedures روشن است؟', 1;

EXEC sp_OAMethod @Object, N'open', NULL, N'POST',
     N'https://api.sms-webservice.com/api/V3/SendTokenSingle', N'false';
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

-- این متد UserTraceId در ورودی ندارد، پس در پاسخ NULL برمی‌گردد. اگر شناسه
-- پی‌گیری لازم دارید، SendTokenMulti را حتی برای یک گیرنده هم می‌شود به کار برد.
SELECT Id, Sender, FinalText
FROM OPENJSON(@Response, N'$.Result')
     WITH (Id bigint N'$.Id',
           Sender bigint N'$.Sender',
           FinalText nvarchar(max) N'$.FinalText');
-- docs:end
