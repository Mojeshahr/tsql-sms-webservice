-- استورد پروسیجری که منطق کسب‌وکار شما صدا می‌زند.
--
-- کاری که می‌کند عمداً کم است: یک ردیف می‌نویسد و برمی‌گردد. هیچ تماس شبکه‌ای
-- اینجا نیست، پس تریگر یا تراکنشی که صدایش می‌زند بابت کندی سرویس معطل
-- نمی‌ماند و اگر ارسال بعداً شکست بخورد، تراکنش کسب‌وکار شما rollback نمی‌شود.
--
--   sqlcmd -S . -d YourDatabase -i outbox/02-queue-sms.sql

-- docs:start
CREATE OR ALTER PROCEDURE dbo.QueueSms
    @Destination bigint,
    @Text        nvarchar(400),
    @UserTraceId bigint OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- شماره گیرنده صفر ابتدایی ندارد: 9121112222 یا با کد کشور 989121112222.
    IF @Destination < 900000000
        THROW 50001, N'شماره گیرنده باید بدون صفر ابتدایی باشد.', 1;

    INSERT INTO dbo.SmsOutbox (Destination, [Text])
    VALUES (@Destination, @Text);

    SET @UserTraceId = SCOPE_IDENTITY();
END;
-- docs:end
