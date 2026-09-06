# فرستنده صندوق خروجی، برای اجرا از یک SQL Agent Job هر یک دقیقه.
#
# ردیف‌های نفرستاده را برمی‌دارد، یکجا با SendBulk می‌فرستد، و نتیجه را در
# همان جدول می‌نویسد. UserTraceId هر ردیف همان کلید جدول است، پس پاسخ سرویس
# مستقیماً به ردیف درست می‌نشیند.
#
# جز خود پاورشل به چیزی وابسته نیست. نه ماژول SqlServer لازم است و نه چیز
# دیگر؛ System.Data.SqlClient در خود دات‌نت هست.
#
# این فایل با BOM ذخیره شده. بدون BOM، ویندوز پاورشل ۵.۱ آن را ANSI می‌خواند
# و متن فارسی خراب می‌شود.
#
# در SQL Server Agent، نوع مرحله را PowerShell بگذارید یا:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\scripts\03-send-outbox.ps1

param(
    [string]$ConnectionString = 'Server=.;Database=YourDatabase;Integrated Security=True;TrustServerCertificate=True',
    [int]$BatchSize = 99
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$connection = New-Object System.Data.SqlClient.SqlConnection $ConnectionString
$connection.Open()

try {
    # سرویس در هر SendBulk حداکثر ۹۹ گیرنده می‌پذیرد.
    $command = $connection.CreateCommand()
    $command.CommandText = @'
SELECT TOP (@BatchSize) UserTraceId, Destination, [Text]
FROM dbo.SmsOutbox
WHERE SentAt IS NULL AND Attempts < 5
ORDER BY QueuedAt;
'@
    $null = $command.Parameters.AddWithValue('@BatchSize', $BatchSize)

    $pending = @()
    $reader = $command.ExecuteReader()
    while ($reader.Read()) {
        $pending += [pscustomobject]@{
            UserTraceId = $reader.GetInt64(0)
            Destination = $reader.GetInt64(1)
            Text        = $reader.GetString(2)
        }
    }
    $reader.Close()

    if ($pending.Count -eq 0) { return }

    $settings = $connection.CreateCommand()
    $settings.CommandText = 'SELECT TOP (1) ApiKey, Sender FROM dbo.PayamResanSettings;'
    $reader = $settings.ExecuteReader()
    $null = $reader.Read()
    $apiKey = $reader.GetString(0)
    $sender = $reader.GetInt64(1)
    $reader.Close()

    # همه ردیف‌ها یک متن ندارند، پس SendMultiple نه SendBulk: متن در سطح هر
    # گیرنده تعریف می‌شود.
    $payload = [ordered]@{
        ApiKey     = $apiKey
        Recipients = @($pending | ForEach-Object {
            [ordered]@{
                Sender      = $sender
                Destination = $_.Destination
                Text        = $_.Text
                UserTraceId = $_.UserTraceId
            }
        })
    } | ConvertTo-Json -Depth 5

    $bump = $connection.CreateCommand()
    $bump.CommandText = 'UPDATE dbo.SmsOutbox SET Attempts = Attempts + 1 WHERE SentAt IS NULL AND Attempts < 5;'
    $null = $bump.ExecuteNonQuery()

    $response = Invoke-RestMethod `
        -Method Post `
        -Uri 'https://api.sms-webservice.com/api/V3/SendMultiple' `
        -ContentType 'application/json; charset=utf-8' `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($payload)) `
        -TimeoutSec 30

    if (-not $response.Success) {
        # کل دسته رد شد. Attempts بالا رفته، پس اجرای بعدی دوباره تلاش می‌کند
        # و بعد از پنج بار دست می‌کشد.
        $fail = $connection.CreateCommand()
        $fail.CommandText = 'UPDATE dbo.SmsOutbox SET ErrorCode = @Code, [Error] = @Text WHERE SentAt IS NULL AND Attempts < 5;'
        $null = $fail.Parameters.AddWithValue('@Code', $response.ErrorCode)
        $null = $fail.Parameters.AddWithValue('@Text', [string]$response.Error)
        $null = $fail.ExecuteNonQuery()
        throw "ناموفق. کد $($response.ErrorCode): $($response.Error)"
    }

    foreach ($message in $response.Result) {
        $done = $connection.CreateCommand()
        $done.CommandText = 'UPDATE dbo.SmsOutbox SET SentAt = SYSUTCDATETIME(), ServiceId = @Id WHERE UserTraceId = @TraceId;'
        $null = $done.Parameters.AddWithValue('@Id', $message.Id)
        $null = $done.Parameters.AddWithValue('@TraceId', $message.UserTraceId)
        $null = $done.ExecuteNonQuery()
    }

    Write-Output "$($response.Result.Count) پیامک فرستاده شد."
}
finally {
    $connection.Close()
}
