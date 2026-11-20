-- Handshake, la base : les données dont le calcul a besoin (fenêtres, montants, noms d'objets : la lib commune).
-- Aucune donnée relevée n'est sauvegardée ici (ADR 0001 de l'atelier) : recettes connues, inventaires, métiers, marchands,
-- objets et cours de l'HV sont lus par la lib commune (LibCommune, lib:Lire), avec ou sans GameData. Sans lui, c'est son
-- relevé de repli (le perso connecté, en mémoire, le temps de la session : recettes connues, sacs, banque vue cette
-- session) ; l'HV passe par un fournisseur (Auctionator…) ou attend GameData, les autres persos aussi.
-- HandshakeDB ne garde que les données propres de Handshake : commandes, contrats, projets, réglages.
local _, ns = ...

local lib = LibStub("LibCommune-1.0") -- embarquée (OptionalDeps en développement)
-- Ce que Handshake lit : GameData ne relève que les types auxquels un add-on a souscrit (GameData#4).
if lib.Souscrire then for _, t in ipairs({ "recettes connues", "inventaires", "métiers et compétences", "marchands", "objets", "cours de l'HV" }) do lib:Souscrire(t) end end
-- Recettes connues de tous les persos relevés (sans GameData : le perso connecté) et recettes vues, ou rien.
local function recettesConnues()
  return lib:Lire("recettes connues", "tous") or { recettes = {}, persos = {} }
end
-- { [GUID] = { [métier] = { rank, max, known = { [clé] = difficulté } } } }
function ns.knownRecipes() return recettesConnues().persos end
-- Un type par perso, tous les persos relevés : { [GUID] = … }.
local function parPerso(t) local d = lib:Lire(t, "tous") return d and d.persos or {} end

---------------------------------------------------------------------------------------------------
-- Accès aux données (par la lib)
-- Recettes : celles relevées dans les fenêtres de métier (par la lib commune), complétées par la réserve Classic
-- (RecettesClassic.lua) pour les objets qu'aucune recette scannée ne fabrique (les métiers que tu n'as pas).
local classic -- la réserve, mise en forme une fois
local nomsDemandes = {} -- recettes dont on a déjà demandé les noms d'objets
function ns.recipes()
  local own = recettesConnues().recettes
  if not lib:Lire("objets") then -- sans catalogue des objets (GameData), personne d'autre ne demande ces noms au serveur
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
-- { [GUID] = { bags, bank, … } } ; { [GUID] = { professions, skills } } ; { [PNJ] = { items = { { id, price, stack, limited } } } }
function ns.inventaires() return parPerso("inventaires") end
function ns.metiers() return parPerso("métiers et compétences") end
function ns.vendors() return lib:Lire("marchands") or {} end
-- Mes sacs, lus à l'instant (la fenêtre se recalcule à chaque changement de sac).
function ns.mesSacs() return lib.Conteneurs(lib.EstSac) end

-- Noms d'objets : le catalogue des objets (GameData), sinon ceux arrivés du serveur cette session, en mémoire seulement.
local nomsDeSession = {}
function ns.items() return lib:Lire("objets") or nomsDeSession end

-- Cours de l'HV (scan de GameData, sinon un fournisseur : Auctionator, TSM, AuctionDB), même forme qu'avant :
-- { items = { [id] = { min, qty, tiers, … } }, scanned (date du scan de GameData), source (le fournisseur) }, ou nil et
-- la raison de la lib.
function ns.market()
  local d, lot = lib:Lire("cours de l'HV")
  if not d then return nil, lot end
  local h = d.hv and d.hv[GetRealmName() .. "-" .. (UnitFactionGroup("player") or "")]
  -- ponytail: une ligne lue au plus une fois par calcul (un calcul = un ns.market())
  local items = setmetatable({}, { __index = function(t, id)
    local l = d.objet(id) or false
    rawset(t, id, l)
    return l
  end })
  return { items = items, scanned = h and h.scanned, source = lot and lot.fournisseur }
end
-- L'état des prix de l'HV, pour la barre d'état : d'où ils viennent, ou ce qui les apporterait.
function ns.texteHV(m)
  local raison
  if not m then m, raison = ns.market() end
  if m and m.scanned then return "HV du " .. m.scanned end
  if m then return "prix de l'HV : " .. (m.source or "?") end
  if raison == "pas de GameData ni de fournisseur" then
    return "pas de prix de l'HV : GameData (scan à l'ouverture de l'HV) ou Auctionator les apporterait"
  end
  return "HV jamais scanné : ouvre l'hôtel des ventes"
end
-- Ce que GameData apporterait, quand il n'est pas là (la lib dit « pas de GameData » pour un type qu'elle ne relève pas
-- sans lui) : une ligne pour la fenêtre, nil s'il est là.
function ns.apportGameData()
  if select(2, lib:Lire("objets")) ~= "pas de GameData" then return nil end
  return "Sans GameData : ce perso seul, sa banque vue cette session. GameData ajouterait tes rerolls, ta banque à tout moment"
    .. (ns.market() and "." or " et les prix de l'HV.")
end

-- Un perso du joueur est rangé sous son GUID (LibCommune#19) ; son prénom pour l'affichage (« ? » si la lib ne le connaît
-- pas : un perso de GameData pas encore reconnecté depuis le passage au GUID).
function ns.prenom(guid)
  local p = lib.Personnage(guid)
  return p and p.adresse and p.adresse:match("^[^%-]+") or "?"
end

---------------------------------------------------------------------------------------------------
-- Montants, noms d'objets, fenêtres : ceux de la lib commune. Un nom d'objet arrivé du serveur est retenu en mémoire
-- (nomsDeSession), jamais sauvegardé.
ns.money, ns.moneyShort, ns.moneySigned, ns.newWindow = lib.Argent, lib.ArgentCourt, lib.ArgentSigne, lib.Fenetre
function ns.rememberItem(id) return lib.RetenirObjet(id, nomsDeSession) end
function ns.itemLabel(id) return lib.NomObjet(id, ns.items(), nomsDeSession) end
function ns.findItem(text) return lib.TrouverObjet(text, ns.items(), ns.recipes()) end

---------------------------------------------------------------------------------------------------
-- Les données relevées ne se sauvegardent plus ici (ADR 0001 de l'atelier) : on purge celles d'un Handshake d'avant
-- (recettes, sacs et banque des persos, noms d'objets, HV). Les données propres restent.
local RELEVES = { "recipes", "chars", "items", "market" }
function ns.purgerAnciensReleves()
  for _, k in ipairs(RELEVES) do HandshakeDB[k] = nil end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, a1)
  if a1 ~= "Handshake" then return end
  HandshakeDB = HandshakeDB or {}
  ns.purgerAnciensReleves()
end)
