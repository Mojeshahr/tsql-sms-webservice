-- StatusByUserTraceId - وضعیت پیامک با شناسه‌هایی که خودتان داده‌اید.
--
-- برای SQL Server این طبیعی‌ترین متد گزارش است: اگر UserTraceId را کلید همان
-- رکوردی بگذارید که پیامک را ساخته، دیگر لازم نیست Id سامانه را در جدولی
-- جدا نگه دارید. راه امن تشخیص ارسال تکراری هم هست: بعد از قطع ارتباط، اول
-- اینجا بپرسید ثبت شده یا نه.
--
-- این فایل STRING_AGG دارد، پس کف نسخه‌اش SQL Server 2017 است نه 2016.
--
-- پیش‌نیازها و جدول dbo.PayamResanSettings در README آمده.

-- docs:start
DECLARE @ApiKey nvarchar(100) = (SELECT TOP (1) ApiKey FROM dbo.PayamResanSettings);

DECLARE @TraceIds TABLE (UserTraceId bigint);
INSERT INTO @TraceIds (UserTraceId) VALUES (1001), (1002);

DECLARE @Payload nvarchar(max) = (
    SELECT @ApiKey AS ApiKey,
           JSON_QUERY(CONCAT(N'[', (SELECT STRING_AGG(CAST(UserTraceId AS nvarchar(20)), N',') FROM @TraceIds), N']')) AS UserTraceIds
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
);

DECLARE @Object int, @Status int, @Response nvarchar(max);

EXEC @Status = sp_OACreate N'MSXML2.ServerXMLHTTP.6.0', @Object OUTPUT;
IF @Status <> 0 THROW 50000, N'ساخت شیء HTTP ناموفق بود. Ole Automation Procedures روشن است؟', 1;

EXEC sp_OAMethod @Object, N'open', NULL, N'POST',
     N'https://api.sms-webservice.com/api/V3/StatusByUserTraceId', N'false';
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

-- کد ۸ یعنی این شناسه در حساب شما نیست. بعد از یک timeout، همین یعنی ارسال
-- ثبت نشده و می‌توانید با خیال راحت دوباره بفرستید.
SELECT UserTraceId,
       CASE WHEN StatusCode = 8 THEN N'ثبت نشده' ELSE [Status] END AS [Status]
FROM OPENJSON(@Response, N'$.Result')
     WITH (UserTraceId bigint N'$.UserTraceId',
           StatusCode int N'$.StatusCode',
           [Status] nvarchar(100) N'$.Status');
-- docs:end
