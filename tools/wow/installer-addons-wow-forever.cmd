<# : batch part (Windows). Double-click this file, or run it from CMD.
@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ([IO.File]::ReadAllText('%~f0'))"
echo.
pause
exit /b
#>
# Installs the WoW Forever addons set up on the Mac (2026-11-06): 18 addons (17 downloads), versions for Forever 1.60.1 (interface 16001).
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }

Say "=== Installation des addons WoW Forever ===" Cyan

# 1. Find the game folder (_forever_)
$roots = @()
foreach ($k in 'HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft', 'HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft') {
  try { $p = (Get-ItemProperty $k -ErrorAction Stop).InstallPath; if ($p) { $roots += (Split-Path $p.TrimEnd('\')) } } catch {}
}
foreach ($d in (Get-PSDrive -PSProvider FileSystem).Root) {
  $roots += "$d`Program Files (x86)\World of Warcraft", "$d`Program Files\World of Warcraft", "$d`World of Warcraft", "$d`Games\World of Warcraft", "$d`Jeux\World of Warcraft"
}
$game = $roots | ForEach-Object { Join-Path $_ '_forever_' } | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $game) {
  $root = $roots | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
  if ($root) { $game = Join-Path $root '_forever_' }
}
if (-not $game -or -not (Test-Path $game)) {
  Say "WoW Forever introuvable automatiquement." Yellow
  $in = Read-Host "Colle le chemin du dossier World of Warcraft (celui qui contient _forever_)"
  $game = Join-Path $in.Trim('"') '_forever_'
  if (-not (Test-Path $game)) { Say "Dossier $game introuvable. Lance WoW Forever une fois depuis Battle.net puis relance ce script." Red; return }
}
$addons = Join-Path $game 'Interface\AddOns'
New-Item -ItemType Directory -Force -Path $addons | Out-Null
try { [IO.File]::WriteAllText((Join-Path $addons '.write-test'), 'x'); Remove-Item (Join-Path $addons '.write-test') }
catch { Say "Pas le droit d'ecrire dans $addons : clic droit sur ce fichier > Executer en tant qu'administrateur." Red; return }
Say "Dossier des addons : $addons" Green

if (Get-Process -Name 'Wow*' -ErrorAction SilentlyContinue) { Say "WoW est ouvert : ferme-le avant (les addons ne sont lus qu'au lancement)." Yellow; Read-Host "Entree quand WoW est ferme" | Out-Null }

# 2. Addons: GitHub releases (official) and CurseForge file server (exact Forever files)
function CF($id, $name) { "https://mediafilez.forgecdn.net/files/$([math]::Floor($id/1000))/$($id%1000)/$([uri]::EscapeDataString($name))" }
$list = [ordered]@{
  'Questie + QuestieDB'   = 'https://github.com/Questie/Questie/releases/download/bundle/v12.6.2%2Bv1.0.11/Questie-v12.6.2%2Bv1.0.11.zip'
  'QuestieTrace'          = 'https://github.com/Questie/QuestieTrace/releases/download/v1.9.0/QuestieTrace-v1.9.0.zip'
  'Bartender4'            = 'https://github.com/Nevcairiel/Bartender4/releases/download/4.18.4/Bartender4-4.18.4.zip'
  'Shortest Path Forever' = CF 9476765 'ShortestPathForever-v1.22.38-forever.zip'
  'Storylines Forever'    = CF 9471649 'Storylines-1.0.0.zip'
  'TomTom'                = CF 9426121 'TomTom-v4.4.0-release.zip'
  'OpenMap'               = CF 9299630 'OpenMap-v0.7.5-beta.zip'
  'DungeonJournal'        = CF 9473650 'ForeverDungeonJournal-1.7.0.zip'
  'BugGrabber'            = CF 9277326 '!BugGrabber-v12.1.1.zip'
  'BugSack'               = CF 9336367 'BugSack-v12.1.9.zip'
  'Details!'              = CF 9447255 'Details-Details.20261104.15400.172.zip'
  'Auctionator'           = CF 9162359 'Auctionator-341.zip'
  'Bagnon'                = CF 9456775 'Bagnon-12.1.8.zip'
  'Leatrix Plus'          = CF 9471872 'Leatrix_Plus-1.60.29-forever.zip'
  'AtlasLoot Continued'   = CF 9471932 'AtlasLootClassic-Continued_12922.zip'
  'Pawn'                  = CF 9410140 'Pawn-2.14.1-Forever.zip'
  'BlizzMove'             = CF 9456490 'BlizzMove-v3.8.7.zip'
}
$tmp = Join-Path $env:TEMP ("wowaddons-" + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $tmp | Out-Null
$ok = 0; $fail = @()
foreach ($n in $list.Keys) {
  try {
    $zip = Join-Path $tmp (($n -replace '[^\w]', '_') + '.zip'); $x = "$zip.d"
    Invoke-WebRequest -Uri $list[$n] -OutFile $zip -UseBasicParsing -UserAgent 'Mozilla/5.0'
    Expand-Archive -Path $zip -DestinationPath $x -Force
    Get-ChildItem $x -Directory | ForEach-Object {
      $dest = Join-Path $addons $_.Name
      if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
      Copy-Item $_.FullName $dest -Recurse -Force
    }
    Say "  OK  $n" Green; $ok++
  } catch { Say "  ECHEC  $n : $($_.Exception.Message)" Red; $fail += $n }
}
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

Say ""
Say "$ok / $($list.Count) addons installes." Cyan
if ($fail) { Say "A refaire plus tard : $($fail -join ', ')" Yellow }
Say "Lance WoW Forever > ecran des personnages > Menu > Add-ons : verifie que tout est coche." Cyan
Say "En jeu : /bugsack affiche les erreurs ; Shift+clic sur la carte = trajet (Shortest Path)."
