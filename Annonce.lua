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

-- Trade Board (Kurki), quand il est installé et que son API hôte a la version attendue : « Annoncer » passe par son tableau
-- (son dialogue de demande, son rythme d'envoi, sa synchro de guilde). On n'appelle que les fonctions de son API hôte
-- (OpenRequestDialog, AddRequest, HasOwnRequest, RemoveOwnRequest), jamais Integrate (un seul hôte possible : Profession
-- Master) ni son intérieur, comme le socle avec Auctionator et TSM.
local function tradeBoard()
  local tb = rawget(_G, "tradeBoard")
  return type(tb) == "table" and tb.hostApiVersion == 1 and tb or nil
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
  if r or tradeBoard() then return r end
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
  return tradeBoard() and "Annoncer (Trade Board)" or "Annoncer", raison == nil
end

local function dire(s) print("|cffa78ffcHandshake :|r " .. s) end

-- Par Trade Board : le dialogue de demande, rempli, pour le premier objet (le joueur y choisit guilde ou Commerce) ; les
-- autres ajoutés à son tableau (guilde par défaut), le plus simple pour plusieurs objets. rec (la commande telle que
-- HandshakeDB la garde) retient les demandes que Handshake y a mises (rec.tb), pour les retirer quand elle part.
local function annoncerTB(tb, order, rec)
  local ids = rec and rec.tb or {}
  for k, l in ipairs(order.lines) do
    if not tb:HasOwnRequest("item", l.id) then ids[l.id] = true end -- une demande à toi d'avant reste à toi
    if k == 1 then tb:OpenRequestDialog("item", l.id, l.qty) else tb:AddRequest("item", l.id, l.qty) end
  end
  if rec and next(ids) then rec.tb = ids end
  if #order.lines > 1 then
    dire(("Trade Board : le premier objet dans son dialogue, les %d autres ajoutés à son tableau (guilde ; à changer là-bas)."):format(#order.lines - 1))
  end
  return true
end

-- Retire du tableau de Trade Board les demandes que Handshake y a mises pour la commande rec (partie, remplacée, son
-- projet supprimé). Sans Trade Board, elles restent notées pour la prochaine fois.
function ns.retirerTB(rec)
  local tb = tradeBoard()
  if not (tb and rec and rec.tb) then return end
  for id in pairs(rec.tb) do
    if tb:HasOwnRequest("item", id) then tb:RemoveOwnRequest("item", id) end
  end
  rec.tb = nil
end

-- Les commandes parties en contrat (ou closes) : leurs demandes quittent le tableau. Après chaque envoi de contrat et à
-- l'entrée en jeu.
function ns.balayerTB()
  for _, r in pairs(HandshakeDB.commandes or {}) do
    for _, c in ipairs(r.liste or {}) do if c.tb and ns.commandeEnvoyee(c) then ns.retirerTB(c) end end
  end
  local m = HandshakeDB.main
  if m and m.tb and ns.commandeEnvoyee(m) then ns.retirerTB(m) end
end

-- « Annoncer » : rend true, ou nil et la raison. loop (/handshake essai annonce) : affichée, rien sur le réseau ; le mode
-- debug la détourne vers son journal (ns.debugSend), comme un chuchotement, Trade Board compris. Avec Trade Board, par son
-- tableau (rec : voir annoncerTB).
function ns.annoncer(order, loop, rec)
  local raison, quand
  if loop then raison = refusBase(order) else raison, quand = ns.annonceRefus(order) end
  if raison then return nil, quand and ("%s, de nouveau à %s"):format(raison, ns.annonceHeure(quand)) or raison end
  local msg = ns.annonceTexte(order)
  if loop then
    print("|cff999999[essai]|r " .. msg)
    return true
  end
  local tb, id, nom = tradeBoard(), ns.canalCommerce()
  if not tb then derniere[msg] = GetTime() end
  if ns.debugSend and ns.debugSend("commerce", tb and "Trade Board" or nom, msg) then return true end
  if tb then return annoncerTB(tb, order, rec) end
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
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("CHAT_MSG_CHANNEL")
f:RegisterEvent("CHAT_MSG_YELL")
f:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then return ns.balayerTB() end
  ns.lireCanal(event, ...)
end)
