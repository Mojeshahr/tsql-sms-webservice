-- SendTokenMulti - یک قالب، چند گیرنده، مقادیر متفاوت.
--
-- پارامترها اینجا آرایه‌اند، نه p1 تا p10. درایه اول به {1} می‌نشیند، دومی به
-- {2} و همین‌طور تا آخر: ترتیب از شماره جای‌گاه می‌آید، نه از جایی که در متن
-- قالب دیده می‌شود.
--
-- در T-SQL آرایه پارامترها با JSON_QUERY ساخته می‌شود، وگرنه رشته JSON داخلی
-- به‌صورت متن escape شده در بدنه می‌نشیند و سرویس آن را آرایه نمی‌بیند.
--
-- پیش‌نیازها و جدول dbo.PayamResanSettings در README آمده.

-- docs:start
DECLARE @ApiKey nvarchar(100) = (SELECT TOP (1) ApiKey FROM dbo.PayamResanSettings);

-- قالب نمونه: «مرسوله شما از {2} تحویل پست شد. بارکد مرسوله پستی: {1}»
DECLARE @Recipients TABLE (Destination bigint, UserTraceId bigint, Barcode nvarchar(50), City nvarchar(50));
INSERT INTO @Recipients (Destination, UserTraceId, Barcode, City)
VALUES (9121112222, 1001, N'BARCODE-AAA', N'شیراز'),
       (9121113333, 1002, N'BARCODE-BBB', N'تبریز');

DECLARE @Payload nvarchar(max) = (
    SELECT @ApiKey AS ApiKey,
           N'postcode' AS TemplateKey,
           (SELECT Destination,
                   UserTraceId,
                   JSON_QUERY((SELECT Barcode AS [0], City AS [1] FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS Parameters
            FROM @Recipients
            FOR JSON PATH) AS Recipients
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
);

DECLARE @Object int, @Status int, @Response nvarchar(max);

EXEC @Status = sp_OACreate N'MSXML2.ServerXMLHTTP.6.0', @Object OUTPUT;
IF @Status <> 0 THROW 50000, N'ساخت شیء HTTP ناموفق بود. Ole Automation Procedures روشن است؟', 1;

EXEC sp_OAMethod @Object, N'open', NULL, N'POST',
     N'https://api.sms-webservice.com/api/V3/SendTokenMulti', N'false';
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

SELECT UserTraceId, FinalText
FROM OPENJSON(@Response, N'$.Result')
     WITH (UserTraceId bigint N'$.UserTraceId',
           FinalText nvarchar(max) N'$.FinalText');
-- docs:end
