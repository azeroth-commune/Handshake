-- Handshake, la base : les données dont le calcul a besoin (fenêtres, montants, noms d'objets : la lib commune).
-- Recettes et recettes connues : lues par la lib commune (LibCommune), avec ou sans GameData ; sans lui, c'est son
-- relevé de repli (le perso connecté, fenêtre de métier ouverte, en mémoire le temps de la session), jamais sauvegardé ici.
-- Le reste : si GameData est installé, on prend ses données (plus riches) ; sinon Handshake lit lui-même :
--   prix de l'hôtel des ventes   : à l'ouverture de l'HV (scan complet du jeu, au plus un par 15 min) ;
--   sacs et banque               : à chaque changement de sac, et quand la banque est ouverte.
-- Ça va dans HandshakeDB (SavedVariables), écrit au /reload ou à la déconnexion.
local _, ns = ...

local lib = LibStub("LibCommune-1.0") -- embarquée (OptionalDeps en développement)
-- Ce que Handshake lit : GameData ne relève que les types auxquels un add-on a souscrit (GameData#4).
if lib.Souscrire then for _, t in ipairs({ "recettes connues", "inventaires", "métiers et compétences", "marchands", "objets", "cours de l'HV" }) do lib:Souscrire(t) end end
-- Recettes connues de tous les persos relevés (sans GameData : le perso connecté) et recettes vues, ou rien.
local function recettesConnues()
  return lib:Lire("recettes connues", "tous") or { recettes = {}, persos = {} }
end
-- { [perso] = { [métier] = { rank, max, known = { [clé] = difficulté } } } }
function ns.knownRecipes() return recettesConnues().persos end

local function gd() return GameDataAPI ~= nil and GameDataDB ~= nil end
local function db() return HandshakeDB end

---------------------------------------------------------------------------------------------------
-- Accès aux données (GameData d'abord)
local function house() return GetRealmName() .. "-" .. UnitFactionGroup("player") end
-- Recettes : celles relevées dans les fenêtres de métier (par la lib commune), complétées par la réserve Classic
-- (RecettesClassic.lua) pour les objets qu'aucune recette scannée ne fabrique (les métiers que tu n'as pas).
local classic -- la réserve, mise en forme une fois
local nomsDemandes = {} -- recettes dont on a déjà demandé les noms d'objets
function ns.recipes()
  local own = recettesConnues().recettes
  if not gd() then -- sans GameData, personne d'autre ne demande ces noms au serveur
    for k, r in pairs(own) do
      if not nomsDemandes[k] then
        nomsDemandes[k] = true
        if r.output then ns.rememberItem(r.output) end
        for _, rg in ipairs(r.reagents or {}) do ns.rememberItem(rg.id) end
      end
    end
  end
  if not HandshakeClassicRecipes then return own end
  if not classic then
    classic = {}
    for k, c in pairs(HandshakeClassicRecipes) do
      local reagents = {}
      for i = 1, #c[6], 2 do reagents[#reagents + 1] = { id = c[6][i], qty = c[6][i + 1] } end
      classic[k] = { output = c[1], made_min = c[2], made_max = c[3], profession = c[4], name = c[5], reagents = reagents, level = c[7],
        classic = true }
    end
  end
  local out, made = {}, {}
  for k, r in pairs(own) do out[k] = r; if r.output then made[r.output] = true end end
  for k, r in pairs(classic) do
    if out[k] == nil and not made[r.output] then out[k] = r end -- une recette scannée de cet objet fait foi
  end
  return out
end
-- Compétence requise pour apprendre une recette : la sienne si les données la donnent, sinon celle de la réserve Classic.
function ns.recipeLevel(key, r)
  if r and r.level then return r.level end
  local c = key and HandshakeClassicRecipes and HandshakeClassicRecipes[key]
  return c and c[7] or nil
end
function ns.chars() return (gd() and GameDataDB.chars) or db().chars or {} end
function ns.vendors() return (gd() and GameDataDB.vendors) or {} end
function ns.items() return (gd() and GameDataItems and GameDataItems.items) or db().items or {} end
function ns.market() return (gd() and GameDataMarket and GameDataMarket[house()]) or (db().market or {})[house()] end

-- Sur Forever, UnitName("player") renvoie prénom, nom de famille ; la clé d'un perso est « Prénom Nom-Royaume »
-- (même forme que GameData).
function ns.charKey()
  local first, last = UnitName("player")
  return (last and (first .. " " .. last) or first) .. "-" .. GetRealmName()
end

-- Conteneurs d'Enum.BagIndex dont le nom passe le filtre (sacs, banque, onglets : ce que ce client a).
function ns.containers(keep)
  local out, seen = {}, {}
  for name, bag in pairs(Enum.BagIndex or {}) do
    if keep(name) and not seen[bag] then
      seen[bag] = true
      local size = C_Container.GetContainerNumSlots(bag)
      if size and size > 0 then
        local items = {}
        for slot = 1, size do
          local it = C_Container.GetContainerItemInfo(bag, slot)
          if it then items[#items + 1] = { id = it.itemID, count = it.stackCount } end
        end
        out[name] = { size = size, items = items }
      end
    end
  end
  return out
end
function ns.isBag(n) return n == "Backpack" or n == "Keyring" or n == "ReagentBag" or n:find("^Bag_") ~= nil end
function ns.isBank(n) return n:find("[Bb]ank") ~= nil end

---------------------------------------------------------------------------------------------------
-- Montants, noms d'objets, fenêtres : ceux de la lib commune. Un nom d'objet arrivé du serveur est retenu dans
-- HandshakeDB.items quand GameData n'est pas là (sinon c'est GameData qui le retient).
ns.money, ns.moneyShort, ns.moneySigned, ns.newWindow = lib.Argent, lib.ArgentCourt, lib.ArgentSigne, lib.Fenetre
local function garde() if not gd() then return db().items end end
function ns.rememberItem(id) return lib.RetenirObjet(id, garde()) end
function ns.itemLabel(id) return lib.NomObjet(id, ns.items(), garde()) end
function ns.findItem(text) return lib.TrouverObjet(text, ns.items(), ns.recipes()) end

---------------------------------------------------------------------------------------------------
-- Lecture des données quand GameData n'est pas là.
local function myChar()
  local key = ns.charKey()
  db().chars[key] = db().chars[key] or {}
  return db().chars[key]
end

-- Hôtel des ventes : scan complet du jeu (C_AuctionHouse.ReplicateItems), lu par paquets de 2 000 pour ne pas
-- figer l'écran ; par objet, le prix unitaire le plus bas, la quantité, et les paliers de prix les moins chers.
local TIERS, BATCH, COOLDOWN = 20, 2000, 15 * 60
local ahOpen, reading, lastRequest, readAt = false, false, -COOLDOWN, nil

function ns.aggregate(rows)
  local by = {}
  for _, r in ipairs(rows) do
    local count = (r.count and r.count > 0) and r.count or 1
    if r.id and r.buyout and r.buyout > 0 then
      by[r.id] = by[r.id] or {}
      table.insert(by[r.id], { math.floor(r.buyout / count), count })
    end
  end
  local out = {}
  for id, list in pairs(by) do
    table.sort(list, function(a, b) return a[1] < b[1] end)
    local tiers, qty = {}, 0
    for _, e in ipairs(list) do
      local last = tiers[#tiers]
      if last and last.price == e[1] then last.qty = last.qty + e[2]
      elseif #tiers < TIERS then tiers[#tiers + 1] = { price = e[1], qty = e[2] } end
      qty = qty + e[2]
    end
    out[id] = { min = list[1][1], qty = qty, auctions = #list, tiers = tiers }
  end
  return out
end

local function readReplicate()
  local n = C_AuctionHouse.GetNumReplicateItems()
  local rows, i = {}, 0
  local function step()
    for idx = i, math.min(i + BATCH, n) - 1 do
      local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(idx)
      rows[#rows + 1] = { id = itemID, count = count, buyout = buyout }
    end
    i = i + BATCH
    if i < n then return C_Timer.After(0, step) end
    db().market[house()] = { scanned = date("%d/%m %H:%M"), items = ns.aggregate(rows) }
    reading, readAt = false, GetTime()
    print(("Handshake : hôtel des ventes lu (%d enchères)."):format(n))
  end
  step()
end

-- Les recettes relevées ne se sauvegardent plus ici (ADR 0001 de l'atelier) : on purge celles d'un Handshake d'avant.
function ns.purgerAnciensReleves()
  HandshakeDB.recipes = nil
  for _, c in pairs(HandshakeDB.chars or {}) do c.recipes = nil end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, event, a1)
  if event == "ADDON_LOADED" then
    if a1 ~= "Handshake" then return end
    HandshakeDB = HandshakeDB or {}
    for _, k in ipairs({ "chars", "items", "market" }) do HandshakeDB[k] = HandshakeDB[k] or {} end -- plus de « recipes » : la lib
    ns.purgerAnciensReleves()
    if gd() then return end -- GameData lit tout ça pour nous
    for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
      "REPLICATE_ITEM_LIST_UPDATE", "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED" }) do
      pcall(f.RegisterEvent, f, e)
    end
  elseif event == "AUCTION_HOUSE_SHOW" then
    ahOpen = true
    if GetTime() - lastRequest >= COOLDOWN then lastRequest = GetTime(); C_AuctionHouse.ReplicateItems() end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    ahOpen = false
  elseif event == "REPLICATE_ITEM_LIST_UPDATE" and ahOpen and not reading then
    if readAt and GetTime() - readAt < COOLDOWN then return end
    reading = true
    readReplicate()
  elseif event == "BAG_UPDATE_DELAYED" then
    myChar().bags = ns.containers(ns.isBag)
  elseif event == "BANKFRAME_OPENED" or event == "PLAYERBANKSLOTS_CHANGED" then
    myChar().bank = ns.containers(ns.isBank)
  end
end)
