-- Send - ساده‌ترین ارسال، یک متن به چند شماره با یک درخواست GET.
--
-- در بیشتر زبان‌ها این ساده‌ترین نمونه است. در T-SQL برعکس: چون متن باید
-- percent-encode شود و SQL Server تابع درون‌سازی برایش ندارد، این فایل از
-- SendBulk بلندتر و شکننده‌تر است. **از SendBulk استفاده کنید**، مگر اینکه
-- دلیل خاصی داشته باشید.
--
-- حلقه پایین بایت‌های UTF-8 را می‌گیرد، پس این فایل به یک collation از نوع
-- UTF-8 نیاز دارد و کف نسخه‌اش SQL Server 2019 است، نه 2016 مثل بقیه.
--
-- پیش‌نیازها و جدول dbo.PayamResanSettings در README آمده.

-- docs:start
DECLARE @ApiKey nvarchar(100), @Sender bigint;
SELECT TOP (1) @ApiKey = ApiKey, @Sender = Sender FROM dbo.PayamResanSettings;

DECLARE @Text nvarchar(400) = N'کد تأیید شما ۱۲۳۴۵۶ است';

DECLARE @Bytes varbinary(max) =
    CONVERT(varbinary(max), CONVERT(varchar(max), @Text COLLATE Latin1_General_100_CI_AI_SC_UTF8));

DECLARE @Encoded nvarchar(max) = N'', @Position int = 1;
WHILE @Position <= DATALENGTH(@Bytes)
BEGIN
    SET @Encoded = @Encoded + N'%' + CONVERT(char(2), SUBSTRING(@Bytes, @Position, 1), 2);
    SET @Position = @Position + 1;
END;

DECLARE @Url nvarchar(4000) = CONCAT(
    N'https://api.sms-webservice.com/api/V3/Send',
    N'?ApiKey=', @ApiKey,
    N'&Sender=', @Sender,
    N'&Text=', @Encoded,
    N'&Recipients=9121112222%2C9121113333');

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

SELECT Id
FROM OPENJSON(@Response, N'$.Result')
     WITH (Id bigint N'$.Id');
-- docs:end
