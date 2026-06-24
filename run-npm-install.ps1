$kuduUrl = "https://app-fcb03oztkaf.scm.azurewebsites.net"
$publishProfile = az webapp deployment list-publishing-profiles --resource-group rg-foundry-chat-baseline-fcb03 --name app-fcb03oztkaf --query "[0]" -o json | ConvertFrom-Json
$username = $publishProfile.userName
$password = $publishProfile.userPWD

Write-Host "Username: $username"
Write-Host "Password: $($password.Substring(0,5))..."

$auth = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$username`:$password"))
$headers = @{
    "Authorization" = "Basic $auth"
    "Content-Type" = "application/json"
}

$body = @{
    "command" = "cd D:\home\site\wwwroot && npm install"
} | ConvertTo-Json

$commandUrl = "$kuduUrl/api/command"
Write-Host "Executing npm install at $commandUrl"

try {
    $response = Invoke-RestMethod -Uri $commandUrl -Method POST -Headers $headers -Body $body -ErrorAction Stop
    Write-Host "Response: $($response | ConvertTo-Json -Depth 5)"
}
catch {
    Write-Host "Error: $_"
    Write-Host "Status Code: $($_.Exception.Response.StatusCode)"
}
