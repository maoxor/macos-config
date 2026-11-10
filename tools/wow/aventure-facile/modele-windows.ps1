# Aventure facile pour WoW Forever (Windows) : installe ou annule le pack. Lu par les deux fichiers .cmd générés par
# construire.py, qui fixent AF_MODE (installer ou annuler). Avant d'installer, le dossier AddOns est copié dans
# _forever_\AventureFacile-sauvegarde ; « annuler » remet cette copie et efface les réglages des addons ajoutés.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Windows PowerShell 5.1 : la barre de progression ralentit les téléchargements
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
$mode = $env:AF_MODE

# 1. Le dossier du jeu (_forever_)
$roots = @()
foreach ($k in 'HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft', 'HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft') {
  try { $p = (Get-ItemProperty $k -ErrorAction Stop).InstallPath; if ($p) { $roots += (Split-Path $p.TrimEnd('\')) } } catch {}
}
foreach ($d in (Get-PSDrive -PSProvider FileSystem).Root) {
  foreach ($sub in 'Program Files (x86)\World of Warcraft', 'Program Files\World of Warcraft', 'World of Warcraft', 'Games\World of Warcraft', 'Jeux\World of Warcraft', 'Battle.net\World of Warcraft') { $roots += (Join-Path $d $sub) }
}
$game = $roots | Where-Object { $_ -and (Test-Path $_) } | ForEach-Object { Join-Path $_ '_forever_' } | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $game) {
  Say "WoW Forever introuvable automatiquement." Yellow
  $in = Read-Host "Colle le chemin du dossier World of Warcraft (celui qui contient _forever_)"
  $game = Join-Path $in.Trim('"') '_forever_'
  if (-not (Test-Path $game)) { Say "Dossier $game introuvable. Lance WoW Forever une fois depuis Battle.net, puis relance ce fichier." Red; return }
}
$addons = Join-Path $game 'Interface\AddOns'
$wtf = Join-Path $game 'WTF'
$save = Join-Path $game 'AventureFacile-sauvegarde'
$avant = Join-Path $save 'AddOns'

function WowFerme {
  while (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$game\*" }) {
    Say "WoW est ouvert : ferme-le (les addons ne se chargent qu'au lancement du jeu)." Yellow
    Read-Host "Appuie sur Entrée quand WoW est fermé" | Out-Null
  }
}

if ($mode -eq 'annuler') {
  Say "=== Aventure facile : retour à l'état d'avant ===" Cyan
  if (-not (Test-Path $avant)) { Say "Rien à annuler : aucune sauvegarde d'Aventure facile sur cet ordinateur." Yellow; return }
  WowFerme
  $gardes = @(Get-ChildItem $avant -Directory | ForEach-Object { $_.Name })
  if (Test-Path $addons) {
    foreach ($dir in Get-ChildItem $addons -Directory) {
      if ($gardes -notcontains $dir.Name) {
        Remove-Item $dir.FullName -Recurse -Force
        # Réglages de l'addon retiré (compte et personnages) : SavedVariables\<Addon>.lua et .lua.bak
        if (Test-Path $wtf) {
          Get-ChildItem $wtf -Recurse -File -Filter ($dir.Name + '.lua*') -ErrorAction SilentlyContinue |
            Where-Object { $_.Directory.Name -eq 'SavedVariables' } | Remove-Item -Force
        }
      }
    }
  }
  New-Item -ItemType Directory -Force -Path $addons | Out-Null
  foreach ($dir in Get-ChildItem $avant -Directory) {
    $dest = Join-Path $addons $dir.Name
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Copy-Item $dir.FullName $dest -Recurse -Force
  }
  Remove-Item $save -Recurse -Force
  Say "C'est fait : tes addons sont revenus comme avant Aventure facile." Green
  return
}

Say "=== Installation d'Aventure facile ===" Cyan
New-Item -ItemType Directory -Force -Path $addons | Out-Null
try { [IO.File]::WriteAllText((Join-Path $addons '.test-ecriture'), 'x'); Remove-Item -Force (Join-Path $addons '.test-ecriture') }
catch { Say "Pas le droit d'écrire dans $addons : clic droit sur ce fichier > Exécuter en tant qu'administrateur." Red; return }
WowFerme

# 2. Sauvegarde de l'état d'avant (une seule fois : une réinstallation garde la première)
if (-not (Test-Path $avant)) {
  New-Item -ItemType Directory -Force -Path $avant | Out-Null
  foreach ($dir in Get-ChildItem $addons -Directory) { Copy-Item $dir.FullName (Join-Path $avant $dir.Name) -Recurse -Force }
  Say "Sauvegarde de tes addons actuels : $avant" Green
}

# 3. Les addons (fichiers exacts pour WoW Forever)
function CF($id, $name) { "https://mediafilez.forgecdn.net/files/$([math]::Floor($id/1000))/$($id%1000)/$([uri]::EscapeDataString($name))" }
$list = [ordered]@{
__LISTE__
}
$garder = @('Storylines')   # déjà là : on n'y touche pas
$tmp = Join-Path $env:TEMP ("aventure-facile-" + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $tmp | Out-Null
$ok = 0; $fail = @()
function Poser($dossier) {
  Get-ChildItem $dossier -Directory | ForEach-Object {
    $dest = Join-Path $addons $_.Name
    if (($garder -contains $_.Name) -and (Test-Path $dest)) { return }
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Copy-Item $_.FullName $dest -Recurse -Force
  }
}
foreach ($n in $list.Keys) {
  try {
    $zip = Join-Path $tmp (($n -replace '[^\w]', '_') + '.zip'); $x = "$zip.d"
    Invoke-WebRequest -Uri $list[$n] -OutFile $zip -UseBasicParsing -UserAgent 'Mozilla/5.0'
    Expand-Archive -Path $zip -DestinationPath $x -Force
    Poser $x
    Say "  OK  $n" Green; $ok++
  } catch { Say "  ÉCHEC  $n : $($_.Exception.Message)" Red; $fail += $n }
}
try {
  $zip = Join-Path $tmp 'AventureFacile.zip'
  [IO.File]::WriteAllBytes($zip, [Convert]::FromBase64String('__ZIP__'))
  Expand-Archive -Path $zip -DestinationPath "$zip.d" -Force
  Poser "$zip.d"
  Say "  OK  Aventure facile" Green; $ok++
} catch { Say "  ÉCHEC  Aventure facile : $($_.Exception.Message)" Red; $fail += 'Aventure facile' }
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

Say ""
Say "$ok / $($list.Count + 1) installés." Cyan
if ($fail) { Say "Relance ce fichier plus tard pour : $($fail -join ', ')" Yellow }
Say "Lance WoW Forever. Si un addon est marqué périmé : Menu > Add-ons > coche « Charger les add-ons périmés »." Cyan
Say "En jeu : le chemin vers la prochaine étape s'affiche tout seul. /af pour l'aide."
Say "Ça ne te plaît pas ? Double-clic sur « Annuler Aventure facile.cmd » : tout revient comme avant."
