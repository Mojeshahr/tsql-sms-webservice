-- TokenList - قالب‌های حساب، با کلید و متن و وضعیت تأییدشان.
--
-- برای پیدا کردن TemplateKey که متدهای ارسال قالب لازم دارند. این متد هم مثل
-- AccountInfo از بررسی اعتبار معاف است.
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
     N'https://api.sms-webservice.com/api/V3/TokenList', N'false';
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

SELECT [Key],
       TextTemplate,
       CASE WHEN [Status] = 2 THEN N'قابل ارسال' ELSE N'قابل ارسال نیست' END AS Sendable
FROM OPENJSON(@Response, N'$.Result')
     WITH ([Key] nvarchar(100) N'$.Key',
           TextTemplate nvarchar(max) N'$.TextTemplate',
           [Status] int N'$.Status');
-- docs:end
