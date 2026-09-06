-- SendMultiple - متن و خط فرستنده جدا برای هر گیرنده.
--
-- برای پیام‌های شخصی‌سازی‌شده که با یک قالب ثابت پوشش داده نمی‌شوند. برخلاف
-- SendBulk، اینجا Text و Sender در سطح هر گیرنده تعریف می‌شوند. در T-SQL این
-- یعنی جدول گیرنده‌ها ستون متن هم دارد، که معمولاً همان چیزی است که از یک
-- JOIN با جدول مشتریان بیرون می‌آید.
--
-- پیش‌نیازها و جدول dbo.PayamResanSettings در README آمده.

-- docs:start
DECLARE @ApiKey nvarchar(100), @Sender bigint;
SELECT TOP (1) @ApiKey = ApiKey, @Sender = Sender FROM dbo.PayamResanSettings;

DECLARE @Recipients TABLE (Sender bigint, Destination bigint, [Text] nvarchar(400), UserTraceId bigint);
INSERT INTO @Recipients (Sender, Destination, [Text], UserTraceId)
VALUES (@Sender, 9121112222, N'آقای محمدی، سفارش شما ارسال شد.', 1001),
       (@Sender, 9121113333, N'خانم رضایی، سفارش شما ارسال شد.', 1002);

DECLARE @Payload nvarchar(max) = (
    SELECT @ApiKey AS ApiKey,
           (SELECT Sender, Destination, [Text], UserTraceId FROM @Recipients FOR JSON PATH) AS Recipients
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
);

DECLARE @Object int, @Status int, @Response nvarchar(max);

EXEC @Status = sp_OACreate N'MSXML2.ServerXMLHTTP.6.0', @Object OUTPUT;
IF @Status <> 0 THROW 50000, N'ساخت شیء HTTP ناموفق بود. Ole Automation Procedures روشن است؟', 1;

EXEC sp_OAMethod @Object, N'open', NULL, N'POST',
     N'https://api.sms-webservice.com/api/V3/SendMultiple', N'false';
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

SELECT UserTraceId, Id
FROM OPENJSON(@Response, N'$.Result')
     WITH (UserTraceId bigint N'$.UserTraceId', Id bigint N'$.Id');
-- docs:end
