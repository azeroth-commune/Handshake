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
  if not order then return "pas de commande à annoncer" end -- Handshake.Annoncer(p, i) d'un rang qui n'existe pas
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

---------------------------------------------------------------------------------------------------
-- Lire : les Demandes lues, côté artisan. Une ligne du Commerce ou un cri qui demande (« WTB », « Buy », « Search » en
-- tête, ou « WTB » n'importe où, comme Trade Board) le lien d'un objet ou d'une recette qu'un de mes persos sait
-- fabriquer. Le texte vient d'inconnus (SECURITE.md) : nettoyé et coupé avant tout affichage, et rien ne se fait sans clic.
-- ponytail: en mémoire seulement (la session) ; une demande du Commerce vaut quelques minutes
ns.DEMANDE_DUREE = 900 -- secondes avant qu'une demande lue disparaisse
local MAX_TEXTE, MAX_DEMANDES = 160, 30
local lues = {} -- [qui#objet] = { qui, id (objet) ou sort, lien, texte, ou, t, repondu }

local function lienRecette(id)
  local r = ns.recipes()[id]
  local nom = r and r.name or (GetSpellInfo and GetSpellInfo(id)) or ("recette " .. id)
  return ("|cffffd000|Henchant:%d|h[%s]|h|r"):format(id, nom)
end

-- Le texte d'un inconnu, affichable : sans caractères de contrôle ; les liens d'objet et de recette refaits ici depuis leur
-- ID (un faux nom ne passe pas), les autres réduits à leur texte ; sans codes de couleur, de texture, d'atlas ; coupé à max
-- octets (hors liens), jamais au milieu d'un caractère.
function ns.nettoyer(s, max)
  s = tostring(s or ""):gsub("[%z\1-\31\127]", "")
  local liens = {}
  s = s:gsub("|H([^|]*)|h(.-)|h", function(lien, vu)
    local quoi, id = lien:match("^(%a+):(%d+)")
    id = tonumber(id)
    local propre = id and (quoi == "item" and ns.lienObjet(id) or (quoi == "enchant" or quoi == "spell") and lienRecette(id))
    if not propre then return vu end
    liens[#liens + 1] = propre
    return "\1" .. #liens .. "\2"
  end)
  s = s:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|K.-|k", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|", "")
  if max and #s > max then
    s = s:sub(1, max):gsub("[\192-\255][\128-\191]*$", ""):gsub("\1%d*$", "") .. "…"
  end
  return (s:gsub("\1(%d+)\2", function(n) return liens[tonumber(n)] end))
end

local function estDemande(msg)
  local l = msg:lower()
  return l:find("^%s*wtb") or l:find("^%s*buy") or l:find("^%s*search") or l:find("%f[%w]wtb%f[%W]")
end

local function demandeLue(msg, sender, ou)
  if not estDemande(msg) then return end
  local lines, _, _, _, recettes, liens = ns.parseList(msg) -- le lecteur des listes reçues, pas un second
  if not liens then return end -- des noms tapés entre crochets ne suffisent pas
  local objets, sorts = ns.jeSaisFabriquer()
  local id, sort
  for _, l in ipairs(lines) do if objets[l.id] then id = l.id break end end
  if not id then for _, r in ipairs(recettes) do if sorts[r] then sort = r break end end end
  if not (id or sort) then return end
  local cle = sender .. "#" .. (id or ("sort" .. sort))
  local d, neuve = lues[cle], lues[cle] == nil
  d = d or { qui = sender, id = id, sort = sort, lien = id and ns.lienObjet(id) or lienRecette(sort) }
  d.texte, d.ou, d.t = ns.nettoyer(msg, MAX_TEXTE), ou, GetTime()
  lues[cle] = d
  if neuve then
    dire(("%s demande %s %s (/handshake demandes)."):format(ns.nettoyer(sender, 48), d.lien, ou))
  end
  if ns.refreshDemandes then ns.refreshDemandes() end
end

-- Les demandes lues, de la plus récente à la plus vieille ; les vieilles (ns.DEMANDE_DUREE) sont oubliées.
function ns.demandesLues()
  local out = {}
  for k, d in pairs(lues) do
    if GetTime() - d.t > ns.DEMANDE_DUREE then lues[k] = nil else out[#out + 1] = d end
  end
  table.sort(out, function(a, b) return a.t > b.t end)
  for i = #out, MAX_DEMANDES + 1, -1 do
    lues[out[i].qui .. "#" .. (out[i].id or ("sort" .. out[i].sort))], out[i] = nil, nil
  end
  return out
end

-- « Répondre » (un clic) : un chuchotement à l'auteur de la demande d, avec le lien refait ici.
function ns.repondreDemande(d)
  ns.whisper(("Bonjour ! Je peux te fabriquer %s. Intéressé(e) ?"):format(d.lien), d.qui)
  d.repondu = true
end

-- Ce qui arrive des canaux publics (CHAT_MSG_CHANNEL, CHAT_MSG_YELL) : l'écho de mon annonce, les demandes des autres.
function ns.lireCanal(event, msg, sender, _, _, _, _, _, canal, base, _, _, guid)
  if type(msg) ~= "string" or type(sender) ~= "string" or (issecretvalue and (issecretvalue(msg) or issecretvalue(sender))) then return end
  local commerce = event == "CHAT_MSG_CHANNEL" and estCommerce(base)
  if not (commerce or event == "CHAT_MSG_YELL") then return end
  if ns.deMoi(sender, guid) then -- les miennes ne sont jamais listées
    if commerce and attente and canal == attente.canal then attente = nil end
    return
  end
  demandeLue(msg, sender, commerce and "dans le Commerce" or "en criant")
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("CHAT_MSG_CHANNEL")
f:RegisterEvent("CHAT_MSG_YELL")
f:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then return ns.balayerTB() end
  ns.lireCanal(event, ...)
end)

---------------------------------------------------------------------------------------------------
-- Les fenêtres de Handshake hors Contrats, reliées par des onglets en bas (skill ui-addon, modèle : Négoce) : la commande à
-- la main et les Demandes lues. Un onglet ouvre sa fenêtre à la place de celle-ci, qui se ferme.
local ONGLETS = { { "Commande", "HandshakeMainFrame", function() ns.openCommandeMain() end },
  { "Demandes lues", "HandshakeDemandesFrame", function() ns.openDemandes() end } }
function ns.onglets(frame, n)
  frame.Tabs = {}
  for i, o in ipairs(ONGLETS) do
    local t = CreateFrame("Button", nil, frame, "PanelTabButtonTemplate")
    t:SetID(i)
    t:SetText(o[1])
    t:SetScript("OnClick", function()
      if i == n then return end
      local x, y = frame:GetLeft(), frame:GetTop()
      o[3]()
      local autre = _G[o[2]]
      autre:ClearAllPoints()
      autre:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
      frame:Hide()
    end)
    frame.Tabs[i] = t
  end
  frame.Tabs[1]:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 10, 2)
  PanelTemplates_SetNumTabs(frame, #ONGLETS)
  PanelTemplates_SetTab(frame, n)
end

-- « Demandes lues » (/handshake demandes) : une ligne par demande, qui, depuis quand, où, son texte nettoyé ; l'objet
-- (survol : sa bulle) ; « Répondre », un clic, un chuchotement ; une fois fait, le bouton le dit.
local W, ROW, ROWS = 560, 38, 10
local fenetre
local function construire()
  fenetre = ns.newWindow("HandshakeDemandesFrame", "Demandes lues", W, 64 + ROWS * ROW)
  fenetre.vide = fenetre:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  fenetre.vide:SetPoint("TOPLEFT", 16, -48)
  fenetre.vide:SetWidth(W - 32)
  fenetre.vide:SetJustifyH("LEFT")
  fenetre.vide:SetText("Aucune demande lue. Les demandes du Commerce et des cris (WTB, Buy, Search) pour ce que tes persos savent fabriquer s'affichent ici, quelques minutes.")
  fenetre.rows = {}
  for i = 1, ROWS do
    local r = CreateFrame("Frame", nil, fenetre)
    r:SetSize(W - 28, ROW)
    r:SetPoint("TOPLEFT", 14, -44 - (i - 1) * ROW)
    r.objet = CreateFrame("Button", nil, r)
    r.objet:SetSize(28, 28)
    r.objet:SetPoint("LEFT", 0, 0)
    r.objet.icon = r.objet:CreateTexture(nil, "ARTWORK")
    r.objet.icon:SetAllPoints()
    r.objet:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if r.d.id then GameTooltip:SetItemByID(r.d.id) else GameTooltip:SetSpellByID(r.d.sort) end
      GameTooltip:Show()
    end)
    r.objet:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.qui = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.qui:SetPoint("TOPLEFT", 36, -3)
    r.qui:SetWidth(W - 160)
    r.qui:SetJustifyH("LEFT")
    r.texte = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.texte:SetPoint("TOPLEFT", r.qui, "BOTTOMLEFT", 0, -3)
    r.texte:SetWidth(W - 160)
    r.texte:SetJustifyH("LEFT")
    r.texte:SetWordWrap(false)
    r.repondre = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.repondre:SetSize(96, 22)
    r.repondre:SetPoint("RIGHT", 0, 0)
    r.repondre:SetScript("OnClick", function() ns.repondreDemande(r.d); ns.refreshDemandes() end)
    fenetre.rows[i] = r
  end
  ns.onglets(fenetre, 2)
  fenetre:SetScript("OnShow", function() ns.refreshDemandes() end)
end

function ns.refreshDemandes()
  if not (fenetre and fenetre:IsShown()) then return end
  local liste = ns.demandesLues()
  fenetre.vide:SetShown(#liste == 0)
  for i, r in ipairs(fenetre.rows) do
    local d = liste[i]
    r:SetShown(d ~= nil)
    if d then
      r.d = d
      r.objet.icon:SetTexture(d.id and C_Item.GetItemIconByID(d.id) or (GetSpellTexture and GetSpellTexture(d.sort)) or 134400)
      r.qui:SetText(("%s · depuis %s · %s"):format(ns.nettoyer(d.qui, 48), date("%H:%M", time() - math.floor(GetTime() - d.t)), d.ou))
      r.texte:SetText(d.texte)
      r.repondre:SetText(d.repondu and "Répondu" or "Répondre")
      r.repondre:SetEnabled(not d.repondu)
    end
  end
end

function ns.openDemandes()
  if not fenetre then construire() end
  fenetre:Show()
  ns.refreshDemandes()
end
