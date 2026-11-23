-- Handshake : l'Annonce (CONTEXT.md), une ligne publiée ou lue dans le chat public. Elle n'engage à rien, seul le contrat
-- engage (SECURITE.md).
-- Publier : « Annoncer » une commande pas encore partie, un clic = un message dans le canal Commerce, au format que lisent
-- Trade Board, Crafting Order et les autres lecteurs du chat : « WTB [lien] xN, [lien] xM ».
local _, ns = ...

ns.ANNONCE_DELAI = 300 -- secondes avant de pouvoir répéter la même annonce
local ECHO = 5          -- secondes pour que l'annonce revienne du canal

-- Le canal Commerce, trouvé par son nom parmi les canaux rejoints (comme Trade Board) : id, nom ; nil hors d'une ville.
-- « орговля » : Lua ne met pas le cyrillique en minuscules (« Торговля »).
local COMMERCE = { "trade", "handel", "commerce", "commercio", "comercio", "comércio", "орговля", "거래", "交易" }
local function estCommerce(nom)
  if type(nom) ~= "string" then return false end
  nom = nom:lower()
  for _, s in ipairs(COMMERCE) do if nom:find(s, 1, true) then return true end end
  return false
end
ns.estCommerce = estCommerce
function ns.canalCommerce()
  local t = { GetChannelList() } -- id, nom, désactivé, … (deux valeurs par canal sur les vieux clients : on lit par paires)
  for i = 1, #t - 1 do
    if type(t[i]) == "number" and estCommerce(t[i + 1]) then return t[i], t[i + 1] end
  end
end

-- Moi, d'après le serveur : le GUID joint au message, sinon mon nom complet.
function ns.deMoi(sender, guid)
  if guid and guid ~= "" then return guid == UnitGUID("player") end
  return sender ~= nil and ns.fullName(sender) == ns.myName()
end

-- Le texte de l'annonce d'une commande : « WTB [lien] xN, [lien] xM » en un message, par le formateur de la demande en clair.
function ns.annonceTexte(order) return ns.listMessages("WTB", order.lines, nil, true)[1] end

-- ponytail: en mémoire seulement ; après un /reload la limite repart à zéro
local derniere, attente = {}, nil -- derniere[texte] = GetTime() de sa publication ; attente = l'annonce dont on attend l'écho

local function refusBase(order)
  if order.reponse then return "c'est sa demande, pas la tienne" end
  if #(order.lines or {}) == 0 then return "rien à annoncer" end
  if order.fige or ns.commandeEnvoyee(order) then return "demande déjà partie" end
end

-- Pourquoi « Annoncer » ne part pas maintenant (nil : il part) et, refusé par la limite, le moment (GetTime()) où réessayer.
function ns.annonceRefus(order)
  local r = refusBase(order)
  if r then return r end
  local t = derniere[ns.annonceTexte(order)]
  if t and GetTime() - t < ns.ANNONCE_DELAI then return "déjà annoncée", t + ns.ANNONCE_DELAI end
  if not ns.canalCommerce() then return "pas de canal Commerce ici (hors d'une ville)" end
end

-- L'heure (« 14:32 ») d'un moment GetTime() à venir.
function ns.annonceHeure(quand) return date("%H:%M", time() + math.ceil(quand - GetTime())) end

-- Le bouton « Annoncer » (règle « Info cliquable ») : son texte, s'il est cliquable, et le moment où il le redevient.
function ns.annonceEtiquette(order)
  local raison, quand = ns.annonceRefus(order)
  if quand then return "Annoncer à " .. ns.annonceHeure(quand), false, quand end
  if raison and not refusBase(order) then return "Pas de Commerce ici", false end
  return "Annoncer", raison == nil
end

local function dire(s) print("|cffa78ffcHandshake :|r " .. s) end

-- « Annoncer » : rend true, ou nil et la raison. loop (/handshake essai annonce) : affichée, rien sur le réseau ; le mode
-- debug la détourne vers son journal (ns.debugSend), comme un chuchotement.
function ns.annoncer(order, loop)
  local raison, quand
  if loop then raison = refusBase(order) else raison, quand = ns.annonceRefus(order) end
  if raison then return nil, quand and ("%s, de nouveau à %s"):format(raison, ns.annonceHeure(quand)) or raison end
  local msg = ns.annonceTexte(order)
  if loop then
    print("|cff999999[essai]|r " .. msg)
    return true
  end
  derniere[msg] = GetTime()
  local id, nom = ns.canalCommerce()
  if ns.debugSend and ns.debugSend("commerce", nom, msg) then return true end
  local say = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  say(msg, "CHANNEL", nil, id)
  attente = { msg = msg, canal = id }
  C_Timer.After(ECHO, function()
    if attente and attente.msg == msg then
      attente, derniere[msg] = nil, nil
      dire("ton annonce n'est pas revenue du canal Commerce : le serveur ne l'a pas affichée. Tu peux réessayer.")
      if ns.refreshCommandeMain then ns.refreshCommandeMain() end
    end
  end)
  return true
end

-- Ce qui arrive des canaux publics (CHAT_MSG_CHANNEL, CHAT_MSG_YELL) : l'écho de mon annonce.
function ns.lireCanal(event, msg, sender, _, _, _, _, _, canal, base, _, _, guid)
  if type(msg) ~= "string" or (issecretvalue and (issecretvalue(msg) or issecretvalue(sender))) then return end
  if event ~= "CHAT_MSG_CHANNEL" or not estCommerce(base) then return end
  if ns.deMoi(sender, guid) then
    if attente and canal == attente.canal then attente = nil end
    return
  end
end

local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_CHANNEL")
f:RegisterEvent("CHAT_MSG_YELL")
f:SetScript("OnEvent", function(_, ...) ns.lireCanal(...) end)
