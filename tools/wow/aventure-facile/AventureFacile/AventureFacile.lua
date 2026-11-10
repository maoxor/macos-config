-- Aventure facile : un guide qui choisit lui-même la prochaine étape, sans rien à cibler.
--   Guidage : parmi les quêtes du journal (objectif restant ou quête à rendre, positions de Questie) et la
--   suite des histoires de Storylines dans la zone (quête à prendre maintenant), il prend l'étape la plus
--   proche, au temps de trajet réel quand Shortest Path Forever sait l'estimer, et y trace le chemin
--   (marche, vols, bateaux). Il change de cible quand l'étape est faite ou qu'une autre est nettement plus
--   proche, se tait une fois sur place, et laisse toujours la priorité à un trajet choisi par le joueur.
--   Alerte : son et message quand un monstre utile à une quête en cours apparaît (hors combat). Ne cible rien.
--   Confort : à la première installation de Leatrix Plus, réparation et vente des objets gris automatiques.
-- Commandes : /af (aide), /af guidage, /af alerte, /af suivant.
local NOM = "AventureFacile"
local PREFIXE = "|cff66ccffAventure facile :|r "
local DELAI = 4                     -- secondes entre deux choix de cible
local SUR_PLACE, AUTOUR = 35, 120   -- mètres : arrivé à l'objectif / encore dans son secteur
local db
local ignorees = {}                 -- quête -> heure jusqu'à laquelle « /af suivant » l'écarte

local function dire(message)
  DEFAULT_CHAT_FRAME:AddMessage(PREFIXE .. message)
end

local function module(nom)
  if not (QuestieLoader and QuestieLoader.ImportModule) then return nil end
  local ok, m = pcall(QuestieLoader.ImportModule, QuestieLoader, nom)
  return ok and m or nil
end

local function api()
  local a = ShortestPathForever and ShortestPathForever.API
  return a and a.NavigateRoute and a or nil
end

-- Distance en mètres du joueur à un point de carte (x, y entre 0 et 1), par la bibliothèque de Questie.
local HBD
local function distance(uiMap, x, y)
  HBD = HBD or (LibStub and LibStub("HereBeDragonsQuestie-2.0", true))
  if not HBD then return nil end
  local px, py, pi = HBD:GetPlayerWorldPosition()
  local wx, wy, wi = HBD:GetWorldCoordinatesFromZone(x, y, uiMap)
  if not (px and wx) or pi ~= wi then return nil end
  return HBD:GetWorldDistance(pi, px, py, wx, wy)
end

local function ecartee(quete)
  return ignorees[quete] and ignorees[quete] > GetTime()
end

-- Quêtes du journal : l'objectif restant le plus proche, ou le PNJ qui la reprend si elle est finie.
local function etapesDuJournal(liste)
  local joueur, distances, zones = module("QuestiePlayer"), module("DistanceUtils"), module("ZoneDB")
  if not (joueur and joueur.currentQuestlog and distances and distances.GetNearestSpawnForQuest and zones) then return end
  for quete, q in pairs(joueur.currentQuestlog) do
    if type(q) == "table" and q.Objectives and not ecartee(quete) then
      local ok, etat = pcall(q.IsComplete, q)
      if ok and etat ~= -1 then
        local finie = etat == 1 or q.isComplete == true
        local trouve, point, zone, nom = pcall(distances.GetNearestSpawnForQuest, q)
        local uiMap = trouve and point and zone and zones:GetUiMapIdByAreaId(zone)
        if uiMap then
          local x, y = point[1] / 100, point[2] / 100
          local d = distance(uiMap, x, y)
          if d then
            local titre = q.name or ("Quête " .. quete)
            liste[#liste + 1] = {
              cle = ("%d:%s:%d:%d"):format(quete, finie and "r" or "o", math.floor(x * 1000), math.floor(y * 1000)),
              quete = quete, map = uiMap, x = x, y = y, dist = d,
              poids = finie and 0.8 or 1,   -- rendre une quête finie passe un peu avant
              type = finie and "turnin" or "objective",
              titre = finie and ("Rendre : " .. titre) or (nom and (nom .. " · " .. titre) or titre),
            }
          end
        end
      end
    end
  end
end

-- Storylines : dans chaque histoire de la zone, la prochaine quête que l'on peut prendre maintenant.
local function etapesDesHistoires(liste)
  local S = Storylines
  if not (S and S.GetCurrentArea and S.GetZoneStories and S.ResolveStep and S.GetQuestAvailability
      and S.QuestDetails and S.GetGiver and S.Areas) then return end
  local zone = S:GetCurrentArea()
  if not zone then return end
  local deja = {}
  for _, histoire in ipairs(S:GetZoneStories(zone) or {}) do
    for _, pas in ipairs(histoire.steps or {}) do
      local quete, etat = S:ResolveStep(pas)
      if quete and etat ~= S.STATE_DONE then
        -- Une quête de l'histoire déjà dans le journal est couverte par etapesDuJournal.
        if etat == S.STATE_TODO and not deja[quete] and not ecartee(quete) and S:GetQuestAvailability(quete) == "available" then
          deja[quete] = true
          local d = S.QuestDetails[quete]
          local nom, _, aire, gx, gy
          if d then nom, _, aire, gx, gy = S:GetGiver(d[4], d[5]) end
          local carte = aire and S.Areas[aire] and S.Areas[aire][2]
          if carte and carte > 0 and gx and gy then
            local x, y = gx / 100, gy / 100
            local dist = distance(carte, x, y)
            if dist then
              liste[#liste + 1] = {
                cle = ("%d:p"):format(quete), quete = quete, map = carte, x = x, y = y, dist = dist,
                poids = 1.15, type = "pickup",
                titre = "Prendre : " .. (S:GetQuestName(quete) or "quête") .. (nom and (" (" .. nom .. ")") or ""),
              }
            end
          end
        end
        break
      end
    end
  end
end

-- La meilleure étape : la plus proche, puis, parmi les trois plus proches, la plus rapide à rejoindre.
local function choisir()
  local liste = {}
  pcall(etapesDuJournal, liste)
  pcall(etapesDesHistoires, liste)
  for _, e in ipairs(liste) do e.score = e.dist * e.poids end
  table.sort(liste, function(a, b) return a.score < b.score end)
  local a = api()
  local carte = C_Map.GetBestMapForUnit("player")
  local pos = carte and C_Map.GetPlayerMapPosition(carte, "player")
  if a and a.Estimate and pos and #liste > 1 then
    local px, py = pos:GetXY()
    local rapides = {}
    for i = 1, math.min(3, #liste) do
      local e = liste[i]
      local ok, secondes = pcall(a.Estimate, carte, px, py, e.map, e.x, e.y)
      if ok and type(secondes) == "number" then
        e.temps = secondes * e.poids
        rapides[#rapides + 1] = e
      end
    end
    if #rapides >= 2 then
      table.sort(rapides, function(x, y) return x.temps < y.temps end)
      return rapides[1], liste
    end
  end
  return liste[1], liste
end

local cible, surPlace, refusee

local function guider(force)
  local a = api()
  if not (db and db.guidage and a) or InCombatLockdown() or UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then return end
  -- Un trajet choisi par le joueur (clic sur la carte, Questie, Storylines) passe toujours avant.
  if a.Active() and not a.CurrentStop(NOM) then return end
  local meilleur, liste = choisir()
  if not meilleur then
    if a.CurrentStop(NOM) then a.Cancel(NOM) end
    cible = nil
    return
  end
  -- Garder la cible tant qu'elle existe, sauf si une autre est nettement plus proche (pas de va-et-vient).
  if cible and not force and meilleur.cle ~= cible.cle then
    for _, e in ipairs(liste) do
      if e.cle == cible.cle then
        if meilleur.score > e.score * 0.7 - 30 then meilleur = e end
        break
      end
    end
  end
  local meme = cible and cible.cle == meilleur.cle
  local fin = a.Ended(NOM)
  if meme and fin == "cleared" and not force then return end           -- le joueur a effacé ce trajet
  if meilleur.dist < SUR_PLACE or (meme and (surPlace or fin == "arrived") and meilleur.dist < AUTOUR) then
    if a.CurrentStop(NOM) then a.Cancel(NOM) end                         -- sur place : pas de flèche sur l'objectif
    cible, surPlace = meilleur, true
    return
  end
  if meme and a.CurrentStop(NOM) and not force then return end         -- déjà en route
  local etape = { map = meilleur.map, x = meilleur.x, y = meilleur.y, title = meilleur.titre, kind = meilleur.type }
  if meilleur.type ~= "pickup" then etape.questID = meilleur.quete end
  if a.NavigateRoute(NOM, { etape }) then
    cible, surPlace = meilleur, false
  end
end

-- Alerte : un monstre dont une quête en cours a encore besoin vient d'apparaître.
local vus, derniere = {}, 0
local function alerter(unite)
  if not (db and db.alerte) or InCombatLockdown() or UnitAffectingCombat("player") then return end
  if not UnitExists(unite) or UnitIsDead(unite) or UnitIsPlayer(unite) or (UnitIsTapDenied and UnitIsTapDenied(unite)) then return end
  local guid = UnitGUID(unite)
  if type(guid) ~= "string" then return end
  local genre, _, _, _, _, pnj = strsplit("-", guid)
  if genre ~= "Creature" or not pnj then return end
  local bulles, joueur = module("QuestieTooltips"), module("QuestiePlayer")
  local entrees = bulles and bulles.lookupByKey and bulles.lookupByKey["m_" .. pnj]
  if not (entrees and joueur and joueur.currentQuestlog) then return end
  local utile
  for _, t in pairs(entrees) do
    local o = t.objective
    if o and t.questId and joueur.currentQuestlog[t.questId] and (not o.Needed or o.Needed ~= o.Collected) then
      utile = true
      break
    end
  end
  if not utile then return end
  local maintenant = GetTime()
  if maintenant - derniere < 4 or (vus[pnj] and maintenant - vus[pnj] < 45) then return end
  vus[pnj], derniere = maintenant, maintenant
  PlaySound(SOUNDKIT.RAID_WARNING or 8959, "Master")
  RaidNotice_AddMessage(RaidWarningFrame, "Objectif de quête : " .. (UnitName(unite) or "?"), ChatTypeInfo["RAID_WARNING"])
end

-- Confort : seulement sur un Leatrix Plus neuf (jamais réglé), pour ne rien changer à des réglages choisis.
local LEATRIX = {
  AutoRepairGear = "On", AutoRepairShowSummary = "On", AutoSellJunk = "On", AutoSellShowSummary = "On",
  ShowFlightTimes = "On", FlightBarDestination = "On",
  AutomateQuests = "Off",   -- les dialogues de quête restent à lire
}
local function reglerLeatrix()
  if db.leatrix or type(LeaPlusDB) ~= "table" or LeaPlusDB.FirstRunMessageSeen then return end
  for cle, valeur in pairs(LEATRIX) do LeaPlusDB[cle] = valeur end
  db.leatrix = true
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, evenement, arg)
  if evenement == "ADDON_LOADED" then
    if arg == NOM then
      AventureFacileDB = AventureFacileDB or {}
      db = AventureFacileDB
      if db.guidage == nil then db.guidage = true end
      if db.alerte == nil then db.alerte = true end
    elseif arg == "Leatrix_Plus" and db then
      reglerLeatrix()   -- avant que Leatrix lise ses réglages (il se charge après nous)
    end
  elseif evenement == "PLAYER_LOGIN" then
    if not api() then dire("Shortest Path Forever n'est pas installé : pas de guidage.") end
    if not db.bienvenue then
      db.bienvenue = true
      dire("le chemin vers la prochaine étape s'affiche tout seul. /af pour l'aide.")
    end
    C_Timer.NewTicker(DELAI, function() pcall(guider) end)
    f:RegisterEvent("QUEST_ACCEPTED")
    f:RegisterEvent("QUEST_TURNED_IN")
    f:RegisterEvent("QUEST_REMOVED")
    f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
  elseif evenement == "NAME_PLATE_UNIT_ADDED" then
    pcall(alerter, arg)
  elseif evenement == "UPDATE_MOUSEOVER_UNIT" then
    pcall(alerter, "mouseover")
  else
    -- Le journal change : Questie met ses données à jour juste après, on attend un instant.
    C_Timer.After(1.5, function() pcall(guider) end)
  end
end)

SLASH_AVENTUREFACILE1 = "/af"
SLASH_AVENTUREFACILE2 = "/aventure"
SlashCmdList.AVENTUREFACILE = function(texte)
  local commande = strtrim((texte or ""):lower())
  if commande == "guidage" then
    db.guidage = not db.guidage
    if not db.guidage then
      local a = api()
      if a and a.CurrentStop(NOM) then a.Cancel(NOM) end
      cible = nil
    end
    dire("guidage automatique " .. (db.guidage and "activé." or "coupé."))
    if db.guidage then pcall(guider, true) end
  elseif commande == "alerte" then
    db.alerte = not db.alerte
    dire("alerte des monstres de quête " .. (db.alerte and "activée." or "coupée."))
  elseif commande == "suivant" then
    if cible then
      ignorees[cible.quete] = GetTime() + 600
      dire("« " .. cible.titre .. " » mis de côté pour 10 minutes.")
    end
    cible = nil
    pcall(guider, true)
  else
    dire("le chemin vers la prochaine étape s'affiche tout seul (objectif, quête à rendre ou suite de l'histoire).")
    dire("/af suivant : passer cette étape pour 10 min · /af guidage : couper ou remettre le guidage · /af alerte : couper ou remettre le son des monstres de quête.")
    dire(("guidage %s, alerte %s."):format(db.guidage and "activé" or "coupé", db.alerte and "activée" or "coupée"))
  end
end
