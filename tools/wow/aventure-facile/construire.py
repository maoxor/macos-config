#!/usr/bin/env python3
"""Build the « Aventure facile » pack to send: Windows and Mac installers, their « Annuler » twins and a short guide.

Usage: python3 -I construire.py [output folder]   (default: ~/Documents/Aventure facile)
The addon in AventureFacile/ is embedded in each installer (base64 zip); the other addons are downloaded by the
installer from GitHub and the CurseForge file server (exact WoW Forever files, same pins as ../installer-addons-wow-forever.cmd).
"""
import base64
import io
import os
import sys
import zipfile

ICI = os.path.dirname(os.path.abspath(__file__))
SORTIE = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Documents/Aventure facile")


def cf(file_id, name):
    from urllib.parse import quote
    return f"https://mediafilez.forgecdn.net/files/{file_id // 1000}/{file_id % 1000}/{quote(name)}"


# No TomTom: without it, Shortest Path Forever answers TomTom calls itself, so Questie's and Storylines' waypoints
# become real journeys. No levelling guide, no action-bar replacement: the friends keep their own game.
ADDONS = [
    ("Questie", "https://github.com/Questie/Questie/releases/download/bundle/v12.6.2%2Bv1.0.11/Questie-v12.6.2%2Bv1.0.11.zip"),
    ("Shortest Path Forever", cf(9476765, "ShortestPathForever-v1.22.38-forever.zip")),
    ("Storylines", cf(9471649, "Storylines-1.0.0.zip")),
    ("Leatrix Plus", cf(9471872, "Leatrix_Plus-1.60.29-forever.zip")),
    ("OpenMap", cf(9299630, "OpenMap-v0.7.5-beta.zip")),
    ("Bagnon", cf(9456775, "Bagnon-12.1.8.zip")),
    ("Pawn", cf(9410140, "Pawn-2.14.1-Forever.zip")),
    ("BlizzMove", cf(9456490, "BlizzMove-v3.8.7.zip")),
    ("AtlasLoot", cf(9471932, "AtlasLootClassic-Continued_12922.zip")),
    ("DungeonJournal", cf(9473650, "ForeverDungeonJournal-1.7.0.zip")),
    ("Details!", cf(9447255, "Details-Details.20261104.15400.172.zip")),
    ("Auctionator", cf(9162359, "Auctionator-341.zip")),
    ("BugGrabber", cf(9277326, "!BugGrabber-v12.1.1.zip")),
    ("BugSack", cf(9336367, "BugSack-v12.1.9.zip")),
]

CMD_TETE = """<# : partie batch (Windows). Double-clique sur ce fichier.
@echo off
chcp 65001 >nul
set "AF_MODE={mode}"
set "AF_SELF=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ([IO.File]::ReadAllText($env:AF_SELF))"
echo.
pause
exit /b
#>
"""

GUIDE = """AVENTURE FACILE - WoW Forever

Ce que ça fait
- Le chemin vers ta prochaine étape s'affiche tout seul : un objectif de quête, une quête à rendre, ou la suite
  d'une histoire de Storylines. Pas besoin de choisir une quête : il prend la plus proche, change quand elle est
  faite, et se tait quand tu es sur place. Un trajet que tu choisis toi-même (Maj + clic sur la carte) passe avant.
- Un son et un message quand un monstre utile à une de tes quêtes apparaît.
- Questie : objectifs et donneurs de quêtes sur la carte et la minicarte.
- Réparation automatique et vente des objets gris chez les marchands.
- Sacs réunis (Bagnon), meilleur équipement signalé (Pawn), carte d'un seul tenant (OpenMap),
  fenêtres déplaçables (BlizzMove), butin des donjons (AtlasLoot), dégâts (Details).
- Storylines reste comme avant (s'il était déjà installé, on n'y touche pas).

Installer (WoW fermé)
- Windows : double-clic sur « Installer Aventure facile.cmd ». Si Windows avertit : « Informations complémentaires »
  puis « Exécuter quand même ».
- Mac : clic droit sur « Installer Aventure facile.command » > Ouvrir > Ouvrir.
Puis lance le jeu. Si un addon est marqué périmé : Menu > Add-ons > coche « Charger les add-ons périmés ».

En jeu
- /af : l'aide.
- /af suivant : passer l'étape proposée pendant 10 minutes.
- /af guidage : couper ou remettre le chemin automatique.
- /af alerte : couper ou remettre le son des monstres de quête.

Revenir comme avant (WoW fermé)
- Windows : double-clic sur « Annuler Aventure facile.cmd ».
- Mac : clic droit sur « Annuler Aventure facile.command » > Ouvrir.
Tes addons d'avant reviennent tels quels, et les réglages des addons ajoutés sont effacés.
"""


def zip_addon():
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        racine = os.path.join(ICI, "AventureFacile")
        for nom in sorted(os.listdir(racine)):
            chemin = os.path.join(racine, nom)
            info = zipfile.ZipInfo(f"AventureFacile/{nom}", date_time=(2026, 11, 11, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            with open(chemin, "rb") as f:
                z.writestr(info, f.read())
    return buf.getvalue()


def ecrire(nom, texte, crlf=False, executable=False):
    chemin = os.path.join(SORTIE, nom)
    if crlf:
        texte = texte.replace("\r\n", "\n").replace("\n", "\r\n")
    with open(chemin, "w", encoding="utf-8", newline="") as f:
        f.write(texte)
    if executable:
        os.chmod(chemin, 0o755)
    return chemin


def main():
    os.makedirs(SORTIE, exist_ok=True)
    b64 = base64.b64encode(zip_addon()).decode()
    ps = open(os.path.join(ICI, "modele-windows.ps1"), encoding="utf-8").read()
    liste_ps = "\n".join(f"  '{n}' = '{u}'" for n, u in ADDONS)
    ps = ps.replace("__LISTE__", liste_ps).replace("__ZIP__", b64)
    sh = open(os.path.join(ICI, "modele-mac.sh"), encoding="utf-8").read()
    liste_sh = "\n".join(f"installer '{n}' '{u}'" for n, u in ADDONS)
    lignes = "\n".join(b64[i:i + 76] for i in range(0, len(b64), 76))
    sh = sh.replace("__LISTE__", liste_sh).replace("__ZIP__", lignes)
    faits = []
    for mode, titre in (("installer", "Installer"), ("annuler", "Annuler")):
        faits.append(ecrire(f"{titre} Aventure facile.cmd", CMD_TETE.format(mode=mode) + ps, crlf=True))
        faits.append(ecrire(f"{titre} Aventure facile.command", sh.replace("__MODE__", mode), executable=True))
    faits.append(ecrire("Lisez-moi.txt", GUIDE, crlf=True))
    paquet = os.path.join(SORTIE, "Aventure facile.zip")
    with zipfile.ZipFile(paquet, "w", zipfile.ZIP_DEFLATED) as z:
        for chemin in faits:
            info = zipfile.ZipInfo(f"Aventure facile/{os.path.basename(chemin)}", date_time=(2026, 11, 11, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (0o755 if chemin.endswith(".command") else 0o644) << 16
            with open(chemin, "rb") as f:
                z.writestr(info, f.read())
    print("\n".join(faits + [paquet]))


if __name__ == "__main__":
    main()
