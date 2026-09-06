-- SendBulk - یک متن به چند گیرنده، هر کدام با شناسه پی‌گیری خودتان.
--
-- روش پیشنهادی برای ارسال عملیاتی. کلید در بدنه درخواست می‌رود نه در نشانی،
-- و برای هر گیرنده UserTraceId می‌پذیرد تا گزارش تحویل را بدون نگه‌داشتن Id
-- سامانه بگیرید. برای T-SQL این مهم‌تر هم هست، چون بدنه JSON نیازی به
-- percent-encode ندارد و آن کار در T-SQL تابع درون‌ساخت ندارد.
--
-- پیش‌نیازها و جدول dbo.PayamResanSettings در README آمده.

-- docs:start
DECLARE @ApiKey nvarchar(100), @Sender bigint;
SELECT TOP (1) @ApiKey = ApiKey, @Sender = Sender FROM dbo.PayamResanSettings;

DECLARE @Recipients TABLE (Destination bigint, UserTraceId bigint);
INSERT INTO @Recipients (Destination, UserTraceId)
VALUES (9121112222, 1001), (9121113333, 1002);

DECLARE @Payload nvarchar(max) = (
    SELECT @ApiKey AS ApiKey,
           @Sender AS Sender,
           N'سفارش شما ثبت شد.' AS [Text],
           (SELECT Destination, UserTraceId FROM @Recipients FOR JSON PATH) AS Recipients
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
);

DECLARE @Object int, @Status int, @Response nvarchar(max);

EXEC @Status = sp_OACreate N'MSXML2.ServerXMLHTTP.6.0', @Object OUTPUT;
IF @Status <> 0 THROW 50000, N'ساخت شیء HTTP ناموفق بود. Ole Automation Procedures روشن است؟', 1;

EXEC sp_OAMethod @Object, N'open', NULL, N'POST',
     N'https://api.sms-webservice.com/api/V3/SendBulk', N'false';
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
