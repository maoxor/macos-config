#!/bin/bash
# Aventure facile pour WoW Forever (Mac) : installe ou annule le pack. construire.py en tire les deux fichiers
# .command, avec AF_MODE fixé (installer ou annuler). Avant d'installer, le dossier AddOns est copié dans
# _forever_/AventureFacile-sauvegarde ; « annuler » remet cette copie et efface les réglages des addons ajoutés.
set -u
AF_MODE="__MODE__"
dire() { printf '%s\n' "$*"; }
fin() { echo; read -r -p "Appuie sur Entrée pour fermer." _; exit "${1:-0}"; }

GAME="/Applications/World of Warcraft/_forever_"
if [ ! -d "$GAME" ]; then
  dire "WoW Forever introuvable dans Applications."
  read -r -p "Glisse ici le dossier World of Warcraft, puis Entrée : " p
  p="${p%"${p##*[![:space:]]}"}"; p="${p//\\/}"; p="${p%/}"; p="${p#\'}"; p="${p%\'}"
  GAME="$p/_forever_"
  [ -d "$GAME" ] || { dire "Dossier $GAME introuvable. Lance WoW Forever une fois, puis relance ce fichier."; fin 1; }
fi
ADDONS="$GAME/Interface/AddOns"; WTF="$GAME/WTF"
SAVE="$GAME/AventureFacile-sauvegarde"; AVANT="$SAVE/AddOns"

wow_ferme() {
  while pgrep -f "$GAME/World of Warcraft.app/" >/dev/null 2>&1; do
    dire "WoW est ouvert : ferme-le (les addons ne se chargent qu'au lancement du jeu)."
    read -r -p "Appuie sur Entrée quand WoW est fermé. " _ || fin 1
  done
}

if [ "$AF_MODE" = annuler ]; then
  dire "=== Aventure facile : retour à l'état d'avant ==="
  [ -d "$AVANT" ] || { dire "Rien à annuler : aucune sauvegarde d'Aventure facile sur ce Mac."; fin 0; }
  wow_ferme
  mkdir -p "$ADDONS"
  for d in "$ADDONS"/*/; do
    [ -d "$d" ] || continue
    n=$(basename "$d")
    if [ ! -d "$AVANT/$n" ]; then
      rm -rf "$d"
      # Réglages de l'addon retiré (compte et personnages) : SavedVariables/<Addon>.lua et .lua.bak
      [ -d "$WTF" ] && find "$WTF" -path "*/SavedVariables/$n.lua*" -type f -delete
    fi
  done
  for d in "$AVANT"/*/; do
    [ -d "$d" ] || continue
    n=$(basename "$d"); rm -rf "${ADDONS:?}/$n"; cp -R "$d" "$ADDONS/$n"
  done
  rm -rf "$SAVE"
  dire "C'est fait : tes addons sont revenus comme avant Aventure facile."
  fin 0
fi

dire "=== Installation d'Aventure facile ==="
mkdir -p "$ADDONS" 2>/dev/null && touch "$ADDONS/.test-ecriture" 2>/dev/null || { dire "Pas le droit d'écrire dans $ADDONS."; fin 1; }
rm -f "$ADDONS/.test-ecriture"
wow_ferme

# Sauvegarde de l'état d'avant (une seule fois : une réinstallation garde la première)
if [ ! -d "$AVANT" ]; then
  mkdir -p "$AVANT"
  for d in "$ADDONS"/*/; do [ -d "$d" ] && cp -R "$d" "$AVANT/$(basename "$d")"; done
  dire "Sauvegarde de tes addons actuels : $AVANT"
fi

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ok=0; total=0; echecs=""
poser() {   # copie les dossiers d'addon d'une archive dépliée, sans toucher à Storylines s'il est déjà là
  for d in "$1"/*/; do
    [ -d "$d" ] || continue
    n=$(basename "$d")
    [ "$n" = Storylines ] && [ -d "$ADDONS/$n" ] && continue
    rm -rf "${ADDONS:?}/$n"; cp -R "$d" "$ADDONS/$n"
  done
}
installer() {   # nom, adresse
  total=$((total + 1))
  local z="$TMP/$total.zip" x="$TMP/$total"
  if curl -fsSL -A 'Mozilla/5.0' -o "$z" "$2" && mkdir -p "$x" && unzip -q -o "$z" -d "$x"; then
    poser "$x"; ok=$((ok + 1)); dire "  OK  $1"
  else
    echecs="$echecs, $1"; dire "  ÉCHEC  $1"
  fi
}
__LISTE__
total=$((total + 1))
if base64 -D -o "$TMP/af.zip" <<'ZIP' && mkdir -p "$TMP/af" && unzip -q -o "$TMP/af.zip" -d "$TMP/af"; then
__ZIP__
ZIP
  poser "$TMP/af"; ok=$((ok + 1)); dire "  OK  Aventure facile"
else
  echecs="$echecs, Aventure facile"; dire "  ÉCHEC  Aventure facile"
fi

echo
dire "$ok / $total installés."
[ -n "$echecs" ] && dire "Relance ce fichier plus tard pour : ${echecs#, }"
dire "Lance WoW Forever. Si un addon est marqué périmé : Menu > Add-ons > coche « Charger les add-ons périmés »."
dire "En jeu : le chemin vers la prochaine étape s'affiche tout seul. /af pour l'aide."
dire "Ça ne te plaît pas ? Double-clic sur « Annuler Aventure facile.command » : tout revient comme avant."
fin 0
