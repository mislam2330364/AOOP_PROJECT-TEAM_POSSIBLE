$ErrorActionPreference = "Stop"

$baseUrl = "http://localhost:8080/api/v1"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$username = "demo_$timestamp"
$password = "demo123"

Write-Host "Registering user: $username"
$registerBody = @{ username = $username; password = $password } | ConvertTo-Json
$register = Invoke-RestMethod -Method Post -Uri "$baseUrl/auth/register" -Body $registerBody -ContentType "application/json"
$register | ConvertTo-Json -Depth 6

Write-Host "Logging in user: $username"
$loginBody = @{ username = $username; password = $password } | ConvertTo-Json
$login = Invoke-RestMethod -Method Post -Uri "$baseUrl/auth/login" -Body $loginBody -ContentType "application/json"
$login | ConvertTo-Json -Depth 6

$playerId = $login.playerId
$worldId = "WORLD_001"

Write-Host "Saving inventory for playerId=$playerId worldId=$worldId"
$inventoryBody = @{
    playerId = "$playerId"
    worldId = $worldId
    items = @(
        @{ itemId = "MEDKIT"; itemName = "Med Kit"; itemDescription = "Heals 25 HP"; spriteName = "medkit"; quantity = 2 },
        @{ itemId = "AMMO_PISTOL"; itemName = "Pistol Ammo"; itemDescription = "9mm rounds"; spriteName = "ammo_pistol"; quantity = 30 }
    )
} | ConvertTo-Json -Depth 6

$save = Invoke-RestMethod -Method Post -Uri "$baseUrl/inventory/$playerId" -Body $inventoryBody -ContentType "application/json"
$save | ConvertTo-Json -Depth 6

Write-Host "Loading inventory for playerId=$playerId worldId=$worldId"
$load = Invoke-RestMethod -Method Get -Uri "$baseUrl/inventory/$playerId?worldId=$worldId"
$load | ConvertTo-Json -Depth 6

Write-Host "Demo complete. Check the database tables: players, inventories, inventory_items."

