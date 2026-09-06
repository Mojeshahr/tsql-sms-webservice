-- SendTokenSingle با GET - همان ارسال قالب، با ورودی در نشانی.
--
-- برای آزمایش دستی مناسب است، برای محیط عملیاتی نه: در GET هم کلید حساب و هم
-- مقدار رمز یک‌بارمصرف داخل نشانی می‌نشینند و در لاگ وب‌سرور ثبت می‌شوند.
-- واریانت POST را بردارید؛ در T-SQL هم کوتاه‌تر است و هم دردسر encode ندارد.
--
-- اینجا همه مقادیر ASCII هستند، پس برخلاف send.sql به حلقه encode نیازی نیست
-- و کف نسخه همان SQL Server 2016 می‌ماند. اگر مقدار پارامتر فارسی شد، الگوی
-- encode را از send.sql بردارید.
--
-- پیش‌نیازها و جدول dbo.PayamResanSettings در README آمده.

-- docs:start
DECLARE @ApiKey nvarchar(100) = (SELECT TOP (1) ApiKey FROM dbo.PayamResanSettings);

DECLARE @Url nvarchar(4000) = CONCAT(
    N'https://api.sms-webservice.com/api/V3/SendTokenSingle',
    N'?ApiKey=', @ApiKey,
    N'&TemplateKey=verifycode',
    N'&Destination=9121112222',
    N'&p1=123456');

DECLARE @Object int, @Status int, @Response nvarchar(max);

EXEC @Status = sp_OACreate N'MSXML2.ServerXMLHTTP.6.0', @Object OUTPUT;
IF @Status <> 0 THROW 50000, N'ساخت شیء HTTP ناموفق بود. Ole Automation Procedures روشن است؟', 1;

EXEC sp_OAMethod @Object, N'open', NULL, N'GET', @Url, N'false';
EXEC sp_OAMethod @Object, N'send';

EXEC sp_OAMethod @Object, N'responseText', @Response OUTPUT;
EXEC sp_OADestroy @Object;

IF JSON_VALUE(@Response, N'$.Success') <> N'true'
BEGIN
    DECLARE @Error nvarchar(400) = CONCAT(
        N'ناموفق. کد ', JSON_VALUE(@Response, N'$.ErrorCode'),
        N': ', JSON_VALUE(@Response, N'$.Error'));
    THROW 50000, @Error, 1;
END;

SELECT Id, FinalText
FROM OPENJSON(@Response, N'$.Result')
     WITH (Id bigint N'$.Id',
           FinalText nvarchar(max) N'$.FinalText');
-- docs:end
