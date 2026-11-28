-- Vérification hors jeu (non chargée par la TOC) : luajit Handshake/check.lua, depuis le dossier des add-ons.
-- Juste assez de l'API WoW pour les commandes, les contrats et le texte. Le socle Azeroth Commune est chargé avant, comme
-- dans le jeu : ses SavedVariables (AzerothCommuneDB, AzerothCommuneItems, AzerothCommuneMarket) servent de données, lues
-- par ses vrais accesseurs. Composants (dossier voisin) est chargé aussi, comme en jeu quand les deux sont là : les
-- projets, leur arbre et leurs blocs viennent de son API publique ; « sans Composants » est vérifié plus bas en le
-- retirant. Rien de relevé n'est écrit dans HandshakeDB (ADR 0002 de l'atelier).
local noop = function() end
local stubMT = { __index = function() return noop end }
CreateFrame = function() return setmetatable({}, stubMT) end
SlashCmdList, StaticPopupDialogs, UISpecialFrames = {}, {}, {}
C_Timer = { After = noop, NewTicker = noop }
C_Item = { GetItemInfo = noop, GetItemIconByID = noop }
date, time = os.date, os.time
GetTime = function() return 0 end
geterrorhandler = function() return function(e) error(e, 0) end end
UnitFactionGroup = function() return "Alliance" end
-- Un perso est rangé sous son GUID ; son numéro de serveur est le royaume du socle (LibCommune#35).
UnitGUID = function(u) if u == "player" then return "Player-6942-0000000E" end end
AzerothCommuneDB, AzerothCommuneItems, AzerothCommuneMarket = { recipes = {}, chars = {}, lots = {} }, { items = {} }, {}
HandshakeDB = {}
-- Rien de relevé dans les SavedVariables de Handshake : seulement ses données propres.
local RELEVES = { "recipes", "chars", "items", "market" }
local function aucunReleve(quand)
  for _, k in ipairs(RELEVES) do assert(HandshakeDB[k] == nil, quand .. " : relevé « " .. k .. " » écrit dans HandshakeDB") end
end
-- Le socle (dépôt voisin, chargé avant Handshake comme dans le jeu), fichiers dans l'ordre de sa TOC avec son espace de
-- noms privé : fenêtres, montants, noms d'objets, capture, cours de l'HV (son scan, sinon Auctionator…), la base.
-- ponytail: VendorData.lua et RecettesReserve.lua (générés, ignorés par git) sont sautés : les marchands et la réserve des
-- recettes sont ceux du test (acns.recettesReserve).
local acns = {}
for f in io.open("AzerothCommune/AzerothCommune.toc"):read("*a"):gmatch("([%w_]+)%.lua") do
  if f ~= "VendorData" and f ~= "RecettesReserve" and f ~= "CatalogueObjets" then assert(loadfile("AzerothCommune/" .. f .. ".lua"))("AzerothCommune", acns) end
end
-- Handshake, puis Composants, puis l'entrée en jeu (PLAYER_LOGIN) : Handshake se branche sur Composants (l'ordre de
-- chargement n'y fait rien).
local ns, cns = {}, {}
local HSTOC = io.open("Handshake/Handshake.toc"):read("*a")
for f in HSTOC:gmatch("([%w_]+)%.lua") do assert(loadfile("Handshake/" .. f .. ".lua"))("Handshake", ns) end
for f in io.open("Composants/Composants.toc"):read("*a"):gmatch("([%w_]+)%.lua") do assert(loadfile("Composants/" .. f .. ".lua"))("Composants", cns) end
ns.brancherComposants()
local C = Composants
assert(ns.findItem and ns.itemLabel and ns.newWindow and C and Handshake, "base chargée, les deux globaux posés")
-- Un projet de Composants et sa commande « tout le projet » (son artisan, son offre) : le projet ne connaît pas ses commandes.
local function projetPour(player, tip, lines)
  local p = C.NouveauProjet({ lines = lines })
  ns.projetArtisan(p, player)
  ns.projetOffre(p, tip)
  return p
end
local commune = AzerothCommune
assert(ns.newWindow == commune.Fenetre and ns.money == commune.Argent and ns.moneyShort == commune.ArgentCourt
  and ns.moneySigned == commune.ArgentSigne, "fenêtres et montants : ceux du socle, plus de copie")
assert(not io.open("Handshake/Donnees.lua"):read("*a"):find("CreateFrame(\"Frame\", name", 1, true), "plus de copie de la fenêtre")
-- Les données des arbres : HV, recettes, persos ; mes sacs et ma banque (lus par Composants, par le socle).
UnitName = function() return "Moi", "Dupont" end
local MOI = UnitGUID("player")
local function donnees(d) -- d.sacs / d.banque = { [id] = nombre }, d.persos = fiches des autres persos dans la base du socle
  local function sac(t)
    local items = {}
    for id, n in pairs(t or {}) do items[#items + 1] = { id = id, count = n } end
    return { b = { items = items } }
  end
  AzerothCommuneMarket = { ["6942-Alliance"] = { scanned = "test", items = d.hv } }
  AzerothCommuneDB.recipes = d.recettes
  AzerothCommuneDB.chars = d.persos or {}
  AzerothCommuneDB.chars[MOI] = { bank = sac(d.banque) }
  commune.Conteneurs = function(garder) return garder("Backpack") and sac(d.sacs) or {} end -- mes sacs, lus à l'instant
end
local realContainers = commune.Conteneurs
-- Marteau (10 bronzes) et cuirasse (20 bronzes), bronze = cuivre + étain, ×2 par fonte. Forge : Bel 164 connaît le
-- marteau, pas la cuirasse ; minage : Alt 90.
local mk = { [2770] = { tiers = { { price = 10, qty = 999 } } }, [2771] = { tiers = { { price = 10, qty = 999 } } },
  [5500] = { tiers = { { price = 500, qty = 999 } } }, [2841] = { tiers = { { price = 100, qty = 999 } } },
  [5541] = { tiers = { { price = 99999, qty = 9 } } }, [2870] = { tiers = { { price = 99999, qty = 9 } } } }
local bronzeR = { name = "Fonte du bronze", output = 2841, made_min = 2, profession = "Minage", reagents = { { id = 2770, qty = 1 }, { id = 2771, qty = 1 } } }
donnees({ hv = mk, recettes = {
  [1] = { name = "Marteau", output = 5541, profession = "Forge", level = 100, reagents = { { id = 2841, qty = 10 }, { id = 5500, qty = 1 } } },
  [2] = { name = "Cuirasse", output = 2870, profession = "Forge", reagents = { { id = 2841, qty = 20 }, { id = 5500, qty = 2 } } },
  [3] = bronzeR },
  persos = { ["Player-6942-00000BE1"] = { nom = "Bel Dupont", recipes = { Forge = { rank = 164, known = { [1] = "easy" } } } },
    ["Player-6942-00000A17"] = { nom = "Alt Dupont", recipes = { Minage = { rank = 90, known = {} } } } } })
local function both(choix) -- un projet « marteau + cuirasse », avec ses choix de case
  local p = C.NouveauProjet({ lines = { { id = 5541, qty = 1 }, { id = 2870, qty = 1 } } })
  for id, c in pairs(choix or {}) do C.Choix(p, id, c) end
  return C.Arbre(p, true)
end
-- Commandes (#6) : « Commander » un bloc ajoute une commande au projet affiché, pas un nouveau projet. Elle livre ce
-- que le bloc produit ; ses apports = ce qui entre dans le bloc (le bronze) + mes apports dans sa part (la perle).
do
  local p = projetPour("Moi", nil, { { id = 5541, qty = 1 }, { id = 2870, qty = 1 } })
  C.Choix(p, 2841, "fabriquer")
  ns.projetApport(p, 5500, true)
  local nb = #C.Projets()
  local function arbre() return C.Arbre(p, true) end
  local function vue(i) return ns.projetCommande(p, i) end
  local function qte(v, id) for _, l in ipairs(v.lines) do if l.id == id then return l.qty end end end
  local function nbApports(v) local k = 0 for _ in pairs(v.apports or {}) do k = k + 1 end return k end
  local tout = vue(1)
  assert(tout.part == "tout le projet" and tout.player == "Moi" and #tout.lines == 2 and tout.apports[5500], "le projet entier : sa 1re commande")
  local i = ns.projetCommander(p, arbre().blocDe.Forge)
  assert(i == 2 and cns.projetCourant() == p and #C.Projets() == nb, "la commande s'ajoute au projet affiché, pas un nouveau projet")
  local cf = vue(i)
  assert(cf.part == "Forge" and cf.player == "Bel Dupont" and not cf.vide, "le bloc de la forge, à Bel")
  assert(#cf.lines == 2 and qte(cf, 5541) == 1 and qte(cf, 2870) == 1, "il livre le marteau et la cuirasse")
  assert(nbApports(cf) == 2 and cf.apports[2841] and cf.apports[5500], "apports : le bronze qui entre, ma perle")
  local cm = vue(ns.projetCommander(p, arbre().blocDe.Minage))
  assert(cm.part == "Minage" and cm.player == "Alt Dupont" and #cm.lines == 1 and qte(cm, 2841) == 30 and nbApports(cm) == 0, "le minage livre 30 bronzes")
  assert(ns.projetCommander(p, arbre().blocDe.Forge) == 2, "le même bloc commandé deux fois : la même commande")
  ns.projetArtisan(p, "Cid", 2)
  ns.projetOffre(p, 700, 2)
  assert(vue(2).player == "Cid" and vue(2).tip == 700 and vue(1).player == "Moi" and not vue(1).tip, "artisan et offre par commande")
  -- Vue vivante : le bronze acheté dans le projet, sans rien recopier. Le bloc du minage disparaît, sa commande reste,
  -- vide ; la forge n'a plus le bronze en apport (son artisan l'achète).
  C.Choix(p, 2841, "acheter")
  local vide = vue(3)
  assert(vide.part == "Minage" and vide.vide and #vide.lines == 0 and #ns.projetCommandes(p) == 3, "commande du minage : vide, toujours là")
  assert(nbApports(vue(2)) == 1 and vue(2).apports[5500], "la forge suit le choix de case du projet")
end
print("Handshake : commandes d'un bloc OK")

-- Commandes et apports hors du projet (Handshake#37) : rangés à part, rattachés à l'identité du projet ; le projet ne garde
-- que ses lignes et ses choix de case. Supprimer un autre projet ne change pas ce rattachement.
do
  local pa = C.NouveauProjet({ lines = { { id = 5541, qty = 1 } } })
  local pb = C.NouveauProjet({ lines = { { id = 5541, qty = 1 }, { id = 2870, qty = 1 } } })
  C.Choix(pb, 2841, "fabriquer")
  ns.projetApport(pb, 5500, true)
  local i = ns.projetCommander(pb, C.Arbre(pb, true).blocDe.Forge)
  ns.projetArtisan(pb, "Cid", i)
  local GARDE = { id = true, name = true, created = true, lines = true, choix = true }
  for k in pairs(pb) do assert(GARDE[k], "le projet ne garde pas « " .. k .. " »") end
  local idB = pb.id
  C.Supprimer(pa.id)
  local vues = ns.projetCommandes(pb)
  assert(pb.id == idB and #vues == 2 and vues[2].part == "Forge" and vues[2].player == "Cid" and vues[2].apports[5500]
    and vues[1].apports[5500], "un autre supprimé : ses commandes et ses apports, toujours à lui")
end
print("Handshake : commandes et apports hors du projet OK")
commune.Conteneurs, AzerothCommuneDB.chars = realContainers, {}

-- Suggestions de la commande à la main : la recherche d'objets du socle (AzerothCommune#49), pas d'index à Handshake.
assert(ns.chercherObjets == nil and ns.rechercheObjets == nil and ns.itemIndex == nil and ns.suggestItems == nil, "la recherche du socle")
assert(io.open("Handshake/CommandeMain.lua"):read("*a"):find("AzerothCommune.RechercheObjets(", 1, true), "sa barre de recherche")


-- Texte échangé : liens réels (~80 caractères), découpés sous 255, relus à l'identique.
local function link(id, name) return ("|cff1eff00|Hitem:%d::::::::31:::::::::|h[%s]|h|r"):format(id, name) end
AzerothCommuneItems.items = { [7963] = { name = "Claymore en mithril", link = link(7963, "Claymore en mithril") },
  [7920] = { name = "Camail en mithril", link = link(7920, "Camail en mithril") },
  [7927] = { name = "Gants ornés en mithril", link = link(7927, "Gants ornés en mithril") },
  [3858] = { name = "Minerai de mithril", link = link(3858, "Minerai de mithril") },
  [7989] = { name = "Plans : Claymore en mithril" } }
local order = { lines = { { id = 7963, qty = 1 }, { id = 7920, qty = 1 }, { id = 7927, qty = 2 } } }
local msgs = ns.listMessages("Commande", order.lines, "· pourboire 5 po · je fournis les composants")
assert(#msgs >= 2, "trop long pour un message")
for _, m in ipairs(msgs) do assert(#m <= 255, "message de " .. #m .. " caractères") end
assert(msgs[1]:find("^Commande %(1/%d%) : 1x|cff"), msgs[1])
-- À l'arrivée : morceaux recollés (le serveur livre les chuchotements d'un joueur dans l'ordre), puis relus.
popups = {}
StaticPopup_Show = function(_, who, kind, data) popups[#popups + 1] = { who = who, kind = kind, data = data } end
Ambiguate = function(s) return (s:gsub("%-.*", "")) end
for i = 1, #msgs do ns.onChat("CHAT_MSG_WHISPER", msgs[i], "Bob-Belegard") end
assert(#popups == 1 and popups[1].who == "Bob" and popups[1].kind == "commande", "une seule proposition d'import, une fois complet")
local lines, kind, tip, mats = ns.parseList(popups[1].data.text)
assert(kind == "commande" and #lines == 3 and lines[3].id == 7927 and lines[3].qty == 2, "lignes relues")
assert(tip == 50000 and mats, "pourboire et composants relus")
-- Écrit à la main : quantité après le lien, doublon additionné, noms entre crochets sans lien.
local l2 = ns.parseList("tu peux me faire " .. link(7963, "Claymore en mithril") .. " x2 et " .. link(7920, "Camail en mithril") .. " " .. link(7963, "Claymore en mithril"))
assert(#l2 == 2 and l2[1].qty == 3 and l2[2].qty == 1, "x2 après le lien, puis la claymore encore une fois")
local l3 = ns.parseList("Besoins : 36x[Minerai de mithril] [Camail en mithril]")
assert(#l3 == 2 and l3[1].id == 3858 and l3[1].qty == 36 and l3[2].qty == 1, "noms tapés à la main")
assert(ns.poText(55600) == "5.56 po" and ns.poText(50000) == "5 po")
print("Handshake : texte échangé OK")

-- Annonce (#51) : « WTB [lien] xN, [lien] xM » en un seul message de 255 octets au plus, par le formateur de la demande
-- en clair ; trop d'objets : coupée entre deux liens, « … » au bout, chaque lien entier.
do
  local claym, camail = AzerothCommuneItems.items[7963].link, AzerothCommuneItems.items[7920].link
  local a = ns.annonceTexte({ lines = { { id = 7963, qty = 1 }, { id = 7920, qty = 3 } } })
  assert(a == "WTB " .. claym .. " x1, " .. camail .. " x3", a)
  assert(a == ns.listMessages("WTB", { { id = 7963, qty = 1 }, { id = 7920, qty = 3 } }, nil, true)[1], "le même formateur que la demande en clair")
  local beaucoup = {}
  for _, id in ipairs({ 7963, 7920, 7927, 3858, 7963, 7920 }) do beaucoup[#beaucoup + 1] = { id = id, qty = 2 } end
  local b = ns.annonceTexte({ lines = beaucoup })
  assert(#b <= 255 and b:find(" …$") and b:find("^WTB |c"), #b .. " octets : " .. b)
  local relu = ns.parseList(b)
  local n = select(2, b:gsub("|Hitem:", ""))
  assert(n >= 2 and n < #beaucoup and select(2, b:gsub("|h|r x2", "")) == n, "liens entiers, chacun avec sa quantité")
  assert(relu[1].id == 7963 and relu[1].qty == 2, "relue par le lecteur de listes")
  -- L'offre (#55) au bout, par le formateur de la demande en clair ; sans offre, inchangée.
  local o = ns.annonceTexte({ lines = { { id = 7963, qty = 1 }, { id = 7920, qty = 3 } }, tip = 50000 })
  assert(o == a .. " · offre 5 po", o)
  assert(ns.annonceTexte({ lines = { { id = 7963, qty = 1 }, { id = 7920, qty = 3 } }, tip = 0 }) == a, "offre nulle : rien")
  local lr, _, tip = ns.parseList(o)
  assert(#lr == 2 and lr[1].id == 7963 and lr[1].qty == 1 and lr[2].id == 7920 and lr[2].qty == 3 and tip == 50000, "relue : objets et offre")
  -- Coupée : l'offre reste au bout, « … » avant elle, chaque lien entier.
  local c = ns.annonceTexte({ lines = beaucoup, tip = 55600 })
  assert(#c <= 255 and c:find(" … · offre 5%.56 po$") and c:find("^WTB |c"), #c .. " octets : " .. c)
  local nc = select(2, c:gsub("|Hitem:", ""))
  assert(nc >= 1 and select(2, c:gsub("|h|r x2", "")) == nc and select(2, c:gsub("|h", "")) == 2 * nc, "liens entiers")
  lr, _, tip = ns.parseList(c)
  assert(#lr >= 1 and lr[1].id == 7963 and tip == 55600, "coupée, relue : objets et offre")
  -- Un objet seul qui ne laisse pas la place à l'offre : l'offre saute, pas l'objet.
  local long = { { text = "[" .. ("x"):rep(236) .. "]", qty = 1 } }
  local sans = ns.listMessages("WTB", long, nil, true)[1]
  local d = ns.listMessages("WTB", long, ns.offreTexte(50000), true)[1]
  assert(#sans <= 255 and #sans + #" · offre 5 po" > 255 and d == sans, d)
end
print("Handshake : composition de l'annonce OK")

-- « Annoncer » (#51) : un clic = un message dans le canal Commerce trouvé par son nom ; hors d'une ville, refusé et dit ;
-- un second clic trop tôt refusé, avec l'heure où réessayer ; l'écho vérifié (le message revient de moi dans le canal),
-- sinon signalé et la limite levée ; vide ou partie, rien ; essai et debug : rien sur le réseau.
do
  local envoyes, minuteurs, dits, canaux, t = {}, {}, {}, {}, 1000
  local G0, T0, P0, D0 = GetTime, C_Timer, print, ns.debugSend
  GetTime = function() return t end
  C_Timer = { After = function(_, fn) minuteurs[#minuteurs + 1] = fn end, NewTicker = noop }
  SendChatMessage = function(msg, kind, _, cible) envoyes[#envoyes + 1] = { msg = msg, kind = kind, cible = cible } end
  GetChannelList = function() return unpack(canaux) end
  print = function(s) dits[#dits + 1] = s end
  local function minuter() local m = minuteurs; minuteurs = {}; for _, f in ipairs(m) do f() end end
  local function dit(motif) for _, s in ipairs(dits) do if s:find(motif) then return true end end end
  local o = { lines = { { id = 7963, qty = 1 } } }
  local ok, raison = ns.annoncer(o)
  assert(not ok and raison:find("Commerce") and #envoyes == 0, "hors d'une ville : refusé, et dit")
  canaux = { 1, "Général - Hurlevent", false, 2, "Commerce - Ville", false }
  assert(ns.annonceRefus(o) == nil and ns.annoncer(o), "en ville : part")
  assert(#envoyes == 1 and envoyes[1].kind == "CHANNEL" and envoyes[1].cible == 2 and envoyes[1].msg == ns.annonceTexte(o), "dans le canal Commerce")
  t = t + 60
  local r2, quand = ns.annonceRefus(o)
  assert(r2 and quand == 1000 + ns.ANNONCE_DELAI, "trop tôt : refusé, avec le moment où réessayer")
  ok, raison = ns.annoncer(o)
  assert(not ok and raison:find("à %d") and #envoyes == 1, "second clic trop tôt : rien ne part")
  ns.lireCanal("CHAT_MSG_CHANNEL", envoyes[1].msg, "Moi Dupont", "", "2. Commerce - Ville", "Moi Dupont", "", 0, 2, "Commerce - Ville", 0, 1, MOI)
  minuter()
  assert(not dit("pas revenue"), "écho reçu : rien à dire")
  t = t + ns.ANNONCE_DELAI
  assert(ns.annoncer(o) and #envoyes == 2, "après le délai : de nouveau")
  -- Une vieille ligne à moi, relue dans l'historique du chat (ouvrir « Annonces lues »), n'est pas l'écho.
  NUM_CHAT_WINDOWS, ChatFrame1 = 1, { ForEachMessage = function(_, op)
    op({ message = "x", extraData = { 1, 1, 1, "CHAT_MSG_CHANNEL", { envoyes[1].msg, "Moi Dupont", "", "2. Commerce - Ville",
      "Moi Dupont", "", 0, 2, "Commerce - Ville", 0, 1, MOI, n = 12 }, n = 5 }, timestamp = GetTime() })
  end }
  ns.relireChat()
  NUM_CHAT_WINDOWS, ChatFrame1 = nil, nil
  minuter()
  assert(dit("pas revenue") and ns.annonceRefus(o) == nil, "pas d'écho : signalé, et on peut réessayer")
  assert(not ns.annoncer({ lines = {} }) and not ns.annoncer({ lines = o.lines, fige = true }) and #envoyes == 2, "vide ou partie : rien")
  ns.debugSend = function(kind) return kind == "commerce" end
  assert(ns.annoncer({ lines = { { id = 7920, qty = 1 } } }) and #envoyes == 2, "mode debug : détourné")
  ns.debugSend = D0
  dits = {}
  assert(ns.annoncer({ lines = { { id = 7927, qty = 1 } } }, true) and #envoyes == 2 and dit("%[essai%].-WTB"), "essai : affiché, rien sur le réseau")
  GetTime, C_Timer, print, SendChatMessage, GetChannelList = G0, T0, P0, nil, nil
end
print("Handshake : annoncer dans le Commerce OK")

-- Trade Board (#53), son API hôte en version 1 : « Annoncer » ouvre son dialogue rempli pour le premier objet et ajoute les
-- autres à son tableau, rien n'est publié par Handshake ; commande partie, remplacée ou son projet supprimé : ses demandes
-- sont retirées du tableau (seulement celles que Handshake y a mises). Autre version, ou absent : l'annonce de Handshake.
do
  local appels, envoyes, possede = {}, {}, { [3858] = true } -- une demande à moi, d'avant Handshake : jamais retirée
  local function faux(version)
    local tb = { hostApiVersion = version }
    for _, f in ipairs({ "OpenRequestDialog", "AddRequest", "RemoveOwnRequest", "Integrate" }) do
      tb[f] = function(self, kind, id, q)
        assert(self == tb, "appelé comme méthode")
        appels[#appels + 1] = ("%s %s %s %s"):format(f, kind, id, q or "")
        if f == "AddRequest" or f == "OpenRequestDialog" then possede[id] = true elseif f == "RemoveOwnRequest" then possede[id] = nil end
      end
    end
    tb.HasOwnRequest = function(_, kind, id) return kind == "item" and possede[id] == true end
    return tb
  end
  local T0 = C_Timer
  C_Timer = { After = noop, NewTicker = noop }
  SendChatMessage = function(msg) envoyes[#envoyes + 1] = msg end
  GetChannelList = function() return 2, "Commerce - Ville", false end
  HandshakeDB.contracts = HandshakeDB.contracts or {}
  tradeBoard = faux(1)
  local m = ns.mainNouvelle()
  m.lines, m.tip = { { id = 7963, qty = 2 }, { id = 7920, qty = 1 }, { id = 3858, qty = 5 } }, 50000
  local dits, P0 = {}, print
  print = function(s) dits[#dits + 1] = s end
  assert(ns.annoncer(m, nil, m) and #envoyes == 0, "avec Trade Board : rien publié par Handshake")
  print = P0
  -- son API ne prend pas de prix (#55) : l'offre est dite, à saisir dans son dialogue
  assert(dits[#dits]:find("offre %(5 po pour la commande%).-dialogue"), dits[#dits])
  assert(appels[1] == "OpenRequestDialog item 7963 2" and appels[2] == "AddRequest item 7920 1" and appels[3] == "AddRequest item 3858 5",
    table.concat(appels, " / "))
  assert(ns.annonceEtiquette(m) == "Annoncer (Trade Board)", "le bouton dit par où l'annonce passe")
  appels = {}
  ns.balayerTB()
  assert(#appels == 0, "pas encore partie : rien de retiré")
  m.contrat, HandshakeDB.contracts.tbk = "tbk", { status = "envoye" }
  ns.balayerTB()
  table.sort(appels)
  assert(#appels == 2 and appels[1] == "RemoveOwnRequest item 7920 " and appels[2] == "RemoveOwnRequest item 7963 " and possede[3858],
    "partie en contrat : retirées, sauf celle d'avant : " .. table.concat(appels, " / "))
  -- Une nouvelle commande à la main remplace l'ancienne ; un projet supprimé emporte ses commandes.
  appels, m = {}, ns.mainNouvelle()
  m.lines = { { id = 7927, qty = 1 } }
  ns.annoncer(m, nil, m)
  ns.mainNouvelle()
  assert(appels[#appels] == "RemoveOwnRequest item 7927 ", "commande remplacée : retirée")
  local p = projetPour("Bel", nil, { { id = 7920, qty = 4 } })
  ns.projetAnnoncer(p, 1)
  assert(appels[#appels] == "OpenRequestDialog item 7920 4", "commande d'un projet : le dialogue")
  ns.oublierCommandes(p)
  assert(appels[#appels] == "RemoveOwnRequest item 7920 ", "projet supprimé : retirée")
  for _, a in ipairs(appels) do assert(not a:find("^Integrate"), "jamais Integrate") end
  -- Autre version de l'API, ou absent : l'annonce de Handshake, sans erreur.
  for _, tb in ipairs({ faux(2), false }) do
    tradeBoard, appels = tb or nil, {}
    local n = #envoyes
    assert(ns.annoncer({ lines = { { id = 7963, qty = tb and 3 or 4 } } }) and #envoyes == n + 1 and #appels == 0, "repli sur l'annonce de Handshake")
  end
  HandshakeDB.main, HandshakeDB.contracts.tbk = nil, nil
  C_Timer, SendChatMessage, GetChannelList = T0, nil, nil
end
print("Handshake : annoncer par Trade Board OK")

-- Annonces lues (#52) : une ligne de demande (WTB, Buy, Search en tête, ou WTB n'importe où) du Commerce ou d'un cri, avec
-- le lien d'un objet ou d'une recette qu'un de mes persos sait fabriquer, entre dans la liste ; WTS, sans lien, objet que
-- je ne sais pas faire, autre canal, mes propres annonces : non. Même joueur, même objet : une entrée. Le texte est nettoyé
-- et coupé avant tout affichage ; les demandes vieillissent ; « Répondre » chuchote à l'auteur.
do
  local t, dits, chuchotes = 5000, {}, {}
  local G0, P0, W0, chars0 = GetTime, print, ns.whisper, AzerothCommuneDB.chars
  GetTime = function() return t end
  local T0 = time
  time = function(x) if x then return T0(x) end return t end
  print = function(s) dits[#dits + 1] = s end
  ns.whisper = function(msg, cible) chuchotes[#chuchotes + 1] = { msg = msg, cible = cible } end
  -- Un perso sait faire le marteau (recette 1 : objet 5541) ; personne la cuirasse (recette 2 : 2870).
  AzerothCommuneDB.chars = { [MOI] = { recipes = { Forge = { rank = 150, known = { [1] = "easy" } } } } }
  local marteau = link(5541, "Marteau")
  AzerothCommuneItems.items[5541] = { name = "Marteau", link = marteau }
  local function canal(msg, qui, guid, base)
    ns.lireCanal("CHAT_MSG_CHANNEL", msg, qui, "", "2. " .. (base or "Commerce - Ville"), qui, "", 0, 2, base or "Commerce - Ville", 0, 1, guid or "Player-6942-00000B0B")
  end
  local function noms() local n = {} for _, d in ipairs(ns.demandesLues()) do n[#n + 1] = d.qui end table.sort(n) return table.concat(n, ",") end
  canal("WTB " .. marteau .. " pst", "Bob Dupont")
  assert(noms() == "Bob Dupont", "une demande de ce que je sais faire : listée")
  assert(#dits == 1 and dits[1]:find("Bob Dupont") and dits[1]:find("Hitem:5541"), "signal discret : une ligne dans le chat")
  canal("WTB " .. marteau .. " pst !!", "Bob Dupont")
  assert(#ns.demandesLues() == 1 and #dits == 1, "même joueur, même objet : une entrée, pas de second signal")
  canal("WTS " .. marteau, "Cid Lebrun", "Player-6942-00000C1D")
  canal("WTB [Marteau] pst", "Cid Lebrun", "Player-6942-00000C1D")
  canal("WTB " .. link(2870, "Cuirasse"), "Cid Lebrun", "Player-6942-00000C1D")
  canal("WTB " .. marteau, "Cid Lebrun", "Player-6942-00000C1D", "Général - Hurlevent")
  canal("WTB " .. marteau .. " x2", "Moi Dupont", MOI)
  assert(noms() == "Bob Dupont", "WTS, sans lien, objet inconnu, autre canal, mon annonce : rien")
  canal("LF forgeron, wtb " .. marteau, "Cid Lebrun", "Player-6942-00000C1D")
  ns.lireCanal("CHAT_MSG_YELL", "Buy " .. marteau .. " now", "Dan Cri", "", "", "Dan Cri", "", 0, 0, "", 0, 1, "Player-6942-00000DA0")
  canal("Search |cffffd000|Henchant:1|h[Faux nom]|h|r", "Eve Rune", "Player-6942-00000E7E")
  assert(noms() == "Bob Dupont,Cid Lebrun,Dan Cri,Eve Rune", "WTB n'importe où, un cri « Buy », une recette « Search » : " .. noms())
  -- Piégée : texture, lien inconnu, couleur, caractère de contrôle, faux nom sur un vrai lien ; puis trop longue.
  canal("WTB |cff1eff00|Hitem:5541::::|h[Épée gratuite]|h|r |TInterface\\Icons\\INV_Misc_Coin_01:0|t |Hurl:http://x|h[clique ici]|h |cffff0000rouge|r \7fin",
    "Mal Truand", "Player-6942-0000BAD0")
  local piege
  for _, d in ipairs(ns.demandesLues()) do if d.qui == "Mal Truand" then piege = d end end
  assert(piege, "listée, mais nettoyée")
  local sans = piege.texte:gsub("|cff1eff00|Hitem:5541::::::::31:::::::::|h%[Marteau%]|h|r", "")
  assert(not sans:find("|", 1, true) and not sans:find("[%z\1-\31]") and not piege.texte:find("Épée gratuite", 1, true)
    and sans:find("[clique ici]", 1, true) and sans:find("rouge", 1, true), "seul le lien reconnu reste, refait d'ici : " .. piege.texte)
  canal("WTB " .. marteau .. " " .. ("bla "):rep(100), "Lia Long", "Player-6942-00000111")
  for _, d in ipairs(ns.demandesLues()) do assert(#d.texte <= 260, "coupée : " .. #d.texte) end
  -- Rien sans clic : aucun chuchotement jusqu'ici. « Répondre » chuchote à l'auteur.
  assert(#chuchotes == 0, "aucune action sans clic")
  local bob
  for _, d in ipairs(ns.demandesLues()) do if d.qui == "Bob Dupont" then bob = d end end
  ns.repondreDemande(bob)
  assert(#chuchotes == 1 and chuchotes[1].cible == bob.qui and chuchotes[1].msg:find("Hitem:5541") and bob.repondu, "Répondre : un chuchotement à l'auteur")
  t = t + ns.DEMANDE_DUREE + 1
  assert(#ns.demandesLues() == 0, "les vieilles demandes disparaissent")
  GetTime, print, ns.whisper, AzerothCommuneDB.chars, time = G0, P0, W0, chars0, T0
end
print("Handshake : demandes lues OK")

-- Demandes par métier, sans lien : une ligne de demande (« LF » seul en tête, « cherche », « recherche », ou les règles
-- d'avant) qui nomme, en mot entier, un métier qu'un de mes persos a, entre dans la liste avec « métier : <Métier> » ;
-- LFW (une offre), LFG, LFM, LF1M (des groupes) : non. Un lien d'objet que je sais faire l'emporte. /handshake essai
-- demande : la même lecture, d'un faux auteur « Essai », et la raison d'un refus dans le chat.
do
  local t, dits, chuchotes = 20000, {}, {}
  local G0, P0, W0, chars0 = GetTime, print, ns.whisper, AzerothCommuneDB.chars
  GetTime = function() return t end
  local T0 = time
  time = function(x) if x then return T0(x) end return t end
  print = function(s) dits[#dits + 1] = s end
  ns.whisper = function(msg, cible) chuchotes[#chuchotes + 1] = { msg = msg, cible = cible } end
  AzerothCommuneDB.chars = { [MOI] = { recipes = { Forge = { rank = 150, known = { [1] = "easy" } } } } }
  local marteau = AzerothCommuneItems.items[5541].link
  local function canal(msg, qui)
    return ns.lireCanal("CHAT_MSG_CHANNEL", msg, qui, "", "2. Commerce - Ville", qui, "", 0, 2, "Commerce - Ville", 0, 1, "Player-6942-0000" .. #qui .. "F00")
  end
  local function de(qui) local r = {} for _, d in ipairs(ns.demandesLues()) do if d.qui == qui then r[#r + 1] = d end end return r end
  canal("LF BS pls", "Bob Dupont")
  local bob = de("Bob Dupont")
  assert(#bob == 1 and bob[1].metier == "Forge" and not bob[1].id and bob[1].texte == "LF BS pls", "« LF BS » : une demande de Forge")
  assert(#dits == 1 and dits[1]:find("Bob Dupont", 1, true) and dits[1]:find("forge", 1, true), "signal discret aussi : " .. tostring(dits[1]))
  canal("LF tailor", "Cid Lebrun")
  canal("LFW blacksmith", "Cid Lebrun")
  canal("LFM BRD need bs", "Cid Lebrun")
  canal("LF1M bs", "Cid Lebrun")
  canal("LFG forge", "Cid Lebrun")
  canal("WTS bs services", "Cid Lebrun")
  canal("LF quelqu'un a Forgefer", "Cid Lebrun")
  canal("cherche ma blacksmithe", "Cid Lebrun")
  -- Une offre de service qui achète aussi ses composants (« WTB » plus loin) n'est pas une demande de métier ; ni un
  -- achat de composants tapé sans lien (« cuir » seul ne nomme pas le métier), même quand un perso a le Travail du cuir.
  AzerothCommuneDB.chars["Player-6942-00000C01"] = { recipes = { ["Travail du cuir"] = { rank = 1, known = {} } } }
  canal("WTS BS services, WTB mats", "Cid Lebrun")
  canal("LFW bs, also WTB arcanite", "Cid Lebrun")
  canal("WTB cuir lourd x20", "Cid Lebrun")
  assert(#de("Cid Lebrun") == 0, "métier qu'aucun perso n'a, offre, groupe, mot dans un autre mot, composants : rien")
  canal("LF lw pour une armure", "Jo Cuir")
  canal("cherche un travailleur du cuir", "Lea Peau")
  assert(#de("Jo Cuir") == 1 and #de("Lea Peau") == 1 and de("Lea Peau")[1].metier == "Travail du cuir", "lw, travailleur du cuir")
  canal("WTB forgeron pour une ceinture", "Dan Cri")
  canal("cherche un forgeron", "Eve Rune")
  canal("Recherche Blacksmith !", "Fil Long")
  assert(#de("Dan Cri") == 1 and #de("Eve Rune") == 1 and de("Fil Long")[1].metier == "Forge", "WTB, cherche, recherche")
  -- Même joueur, même métier : une entrée ; un lien d'objet que je sais faire l'emporte sur le métier de la même ligne.
  canal("LF blacksmith", "Bob Dupont")
  canal("cherche forgeron", "Bob Dupont")
  assert(#de("Bob Dupont") == 1 and #dits == 6, "même joueur, même métier : une entrée, pas de second signal")
  canal("LF bs " .. marteau, "Gus Marteau")
  local gus = de("Gus Marteau")
  assert(#gus == 1 and gus[1].id == 5541 and not gus[1].metier, "le lien de l'objet l'emporte sur le métier")
  -- Un métier qu'un autre perso a (même sans recette notée) compte ; mots avec accents tels qu'écrits.
  AzerothCommuneDB.chars["Player-6942-00000A17"] = { recipes = { Couture = { rank = 1, known = {} } } }
  canal("cherche couturière", "Ida Fil")
  assert(#de("Ida Fil") == 1 and de("Ida Fil")[1].metier == "Couture", "couturière : Couture")
  -- Piégée : nettoyée comme les autres.
  canal("LF BS |TInterface\\Icons\\INV_Misc_Coin_01:0|t |Hurl:http://x|h[clique ici]|h |cffff0000rouge|r \7fin", "Mal Truand")
  local piege = de("Mal Truand")[1]
  assert(piege and not piege.texte:find("[|%z\1-\31]") and piege.texte:find("[clique ici]", 1, true), "nettoyée : " .. tostring(piege and piege.texte))
  -- « Répondre » : le chuchotement fixe, avec le métier.
  ns.repondreDemande(de("Bob Dupont")[1])
  assert(#chuchotes == 1 and chuchotes[1].cible == "Bob Dupont" and chuchotes[1].msg:find("forge", 1, true), "Répondre : " .. tostring(chuchotes[1] and chuchotes[1].msg))
  -- La raison d'un refus vient du lecteur.
  assert(canal("WTS bs", "Cid Lebrun"):find("offre", 1, true) and canal("LFM bs", "Cid Lebrun"):find("pas une demande", 1, true)
    and canal("LF alchemist", "Cid Lebrun"):find("métier", 1, true) and canal("LF bs", "Cid Lebrun") == nil, "raisons du lecteur")
  -- /handshake essai demande : la même lecture, d'« Essai » ; refusée, la raison en une ligne ; rien sur le réseau.
  -- Chaque essai garde les précédents (la clé habituelle : joueur#objet, joueur#métier) et se signale, même déjà listé.
  local n = #dits
  SlashCmdList.HANDSHAKE("essai lue WTB " .. marteau .. " pst")
  local essai = de("Essai")
  assert(#essai == 1 and essai[1].id == 5541 and #dits == n + 1 and dits[#dits]:find("Essai", 1, true), "essai : listée, signalée")
  SlashCmdList.HANDSHAKE("essai lue cherche un forgeron")
  assert(#de("Essai") == 2 and #dits == n + 2 and dits[#dits]:find("forge", 1, true), "un 2e essai : le 1er reste, le 2e signalé")
  SlashCmdList.HANDSHAKE("essai lue WTB " .. marteau .. " encore")
  assert(#de("Essai") == 2 and #dits == n + 3 and dits[#dits]:find("Hitem:5541", 1, true), "le même essai : une entrée, signalée de nouveau")
  n = #dits
  SlashCmdList.HANDSHAKE("essai lue WTS " .. marteau)
  assert(#dits == n + 1 and dits[#dits]:find("offre", 1, true), "essai : la raison du refus : " .. dits[#dits])
  SlashCmdList.HANDSHAKE("essai lue LF alchemist")
  assert(#dits == n + 2 and dits[#dits]:find("métier", 1, true), "essai : la raison du refus : " .. dits[#dits])
  assert(#chuchotes == 1, "essai : rien sur le réseau")
  -- « Répondre » sur une ligne d'essai : le vrai message, chuchoté à moi-même (le faux auteur « Essai » n'existe pas).
  local essaiLigne
  for _, d in ipairs(ns.demandesLues()) do if d.qui == "Essai" and d.id == 5541 then essaiLigne = d end end
  ns.repondreDemande(essaiLigne)
  local moi = ns.myName()
  assert(moi:find(" ", 1, true), "mon nom complet, pas le prénom seul : " .. tostring(moi))
  assert(#chuchotes == 2 and chuchotes[2].cible == moi and chuchotes[2].msg:find("Hitem:5541") and essaiLigne.repondu,
    "Répondre sur un essai : à moi-même, " .. tostring(chuchotes[2] and chuchotes[2].cible))
  t = t + ns.DEMANDE_DUREE + 1
  assert(#ns.demandesLues() == 0, "elles vieillissent comme les autres")
  GetTime, print, ns.whisper, AzerothCommuneDB.chars, time = G0, P0, W0, chars0, T0
end
-- Le format de couleur des clients récents, |cnIQ2: (couleur par qualité, vu en jeu le 23/11 : « LF blacksmith for cnIQ2:[Eperons en mithril] ») : retiré.
do
  local propre = ns.nettoyer("LF blacksmith for |cnIQ2:|Hitem:5541::::|h[Eperons en mithril]|h|r")
  assert(not propre:find("cnIQ2", 1, true) and propre:find("^LF blacksmith for |c") and propre:find("Hitem:5541", 1, true), "|cn…: retiré : " .. propre)
end
print("Handshake : demandes par métier OK")

-- L'historique du chat (les lignes déjà dans ChatFrame1..NUM_CHAT_WINDOWS, avant /reload ou avant la fin du login) : les
-- données que le client garde avec chaque ligne (l'évènement, ses arguments bruts) passent par le même lecteur. Une ligne
-- vue dans deux fenêtres : lue une fois ; les miennes, les offres, les autres canaux : non ; l'heure de l'horodatage quand
-- il y en a un, sinon maintenant. Les demandes lues survivent à un /reload (HandshakeDB.demandes, par perso, déjà
-- nettoyées), les vieilles sont oubliées.
do
  local dits, stubMT0 = {}, getmetatable(CreateFrame())
  local T0, P0, chars0, GT0 = time, print, AzerothCommuneDB.chars, GetTime
  local t = T0({ year = 2026, month = 11, day = 23, hour = 14, min = 10, sec = 0 })
  GetTime = function() return 50000 end
  time = function(x) if x then return T0(x) end return t end
  print = function(s) dits[#dits + 1] = s end
  AzerothCommuneDB.chars = { [MOI] = { recipes = { Forge = { rank = 150, known = { [1] = "easy" } } } } }
  local marteau = AzerothCommuneItems.items[5541].link
  -- Un /reload : Annonce.lua rechargé (sa mémoire repart à zéro), puis l'entrée en jeu (PLAYER_LOGIN).
  local function recharger()
    local C0, ev = CreateFrame, nil
    CreateFrame = function() return setmetatable({ SetScript = function(_, _, fn) ev = fn end }, stubMT0) end
    assert(loadfile("Handshake/Annonce.lua"))("Handshake", ns)
    CreateFrame = C0
    ev(nil, "PLAYER_LOGIN")
  end
  recharger()
  -- Une ligne telle que la fenêtre de chat la garde (ChatFrameOverrides.lua : AddMessage(texte, r, g, b, id, accessID,
  -- typeID, event, SafePack(...), formateur)).
  -- L'entrée telle que ScrollingMessageFrame la garde (PackageEntry) : extraData = { id, accessID, typeID, event, args, … },
  -- timestamp = GetTime() à son arrivée ; age : il y a combien de secondes elle est arrivée.
  local function ligne(event, msg, qui, base, lineID, guid, age)
    local args = { msg, qui, "", base and ("2. " .. base) or "", qui, "", 0, base and 2 or 0, base or "", 0, lineID, guid,
      0, false, false, false, false, { userID = 0 }, n = 18 }
    return { message = "|Hplayer:" .. qui .. ":" .. lineID .. "|h[" .. qui .. "]|h: " .. msg, r = 1, g = 1, b = 1,
      extraData = { 1, 1, 1, event, args, nil, n = 6 }, timestamp = GetTime() - (age or 0) }
  end
  local function cadre(lignes)
    return { ForEachMessage = function(_, op) for _, e in ipairs(lignes) do if op(e) then break end end end }
  end
  local CH, CR = "CHAT_MSG_CHANNEL", "CHAT_MSG_YELL"
  local bob = ligne(CH, "WTB " .. marteau .. " pst", "Bob Dupont", "Commerce - Ville", 101, "Player-6942-00000B0B", 300)
  NUM_CHAT_WINDOWS = 2
  ChatFrame1 = cadre({
    bob,
    ligne(CH, "WTS " .. marteau, "Cid Lebrun", "Commerce - Ville", 102, "Player-6942-00000C1D"),
    ligne(CR, "Buy " .. marteau .. " now", "Dan Cri", nil, 103, "Player-6942-00000DA0"),
    ligne(CH, "WTB " .. marteau, "Eve Rune", "Général - Hurlevent", 104, "Player-6942-00000E7E"),
    ligne(CH, "WTB " .. marteau .. " x2", "Moi Dupont", "Commerce - Ville", 106, MOI),
    ligne(CH, "WTB |cff1eff00|Hitem:5541::::|h[Épée gratuite]|h|r |TInterface\\Icons\\INV_Misc_Coin_01:0|t |Hurl:http://x|h[clique ici]|h \7fin",
      "Mal Truand", "Commerce - Ville", 107, "Player-6942-0000BAD0"),
    { message = "|cffa78ffcHandshake :|r une ligne écrite par un add-on, sans données", r = 1, g = 1, b = 1, timestamp = GetTime() },
    ligne(CH, "WTB " .. marteau, "Fil Long", "Commerce - Ville", 109, "Player-6942-00000F11", 4200), -- 70 min : trop vieille
  })
  ChatFrame2 = cadre({ bob })
  local J0, appels = ns.jeSaisFabriquer, 0
  ns.jeSaisFabriquer = function() appels = appels + 1 return J0() end
  ns.relireChat()
  ns.jeSaisFabriquer = J0
  assert(appels == 1, "mes recettes, calculées une fois par relecture : " .. appels)
  local function rangs() local r = {} for _, d in ipairs(ns.demandesLues()) do r[d.qui] = d end return r end
  local function noms() local n = {} for q in pairs(rangs()) do n[#n + 1] = q end table.sort(n) return table.concat(n, ",") end
  assert(noms() == "Bob Dupont,Dan Cri,Mal Truand", "l'historique : Commerce et cri, pas l'offre, le Général, les miennes, les vieilles : " .. noms())
  assert(#dits == 3, "une ligne de signal par demande, la ligne vue dans deux fenêtres une fois : " .. #dits)
  local r = rangs()
  assert(r["Bob Dupont"].t == t - 300 and r["Dan Cri"].t == t, "l'heure d'arrivée de la ligne, gardée par le client")
  assert(r["Dan Cri"].ou == "en criant" and r["Bob Dupont"].ou == "dans le Commerce", "où")
  local mal = r["Mal Truand"].texte
  assert(not mal:gsub("|cff1eff00|Hitem:5541::::::::31:::::::::|h%[Marteau%]|h|r", ""):find("|", 1, true)
    and not mal:find("Épée gratuite", 1, true) and not mal:find("[%z\1-\31]"), "nettoyée comme une ligne en direct : " .. mal)
  ns.relireChat()
  assert(#dits == 3 and #ns.demandesLues() == 3 and rangs()["Bob Dupont"].t == t - 300, "relire : rien de neuf, l'heure ne bouge pas")
  -- Gardées par perso dans HandshakeDB, déjà nettoyées : le texte propre et les IDs, jamais la ligne brute.
  local gardees = HandshakeDB.demandes[MOI]
  local n = 0
  for _, d in pairs(gardees) do
    n = n + 1
    for k, v in pairs(d) do assert(type(v) ~= "string" or k == "lien" or not v:find("|T", 1, true) and not v:find("Épée", 1, true), "gardée nettoyée : " .. k) end
  end
  assert(n == 3, "les trois gardées")
  -- /reload : le chat est vide, les fraîches reviennent, les vieilles sont oubliées.
  gardees["Vieux Pas#5541"] = { cle = "Vieux Pas#5541", qui = "Vieux Pas", id = 5541, texte = "WTB", ou = "dans le Commerce", t = t - ns.DEMANDE_DUREE - 1 }
  ChatFrame1, ChatFrame2 = cadre({}), cadre({})
  recharger()
  assert(noms() == "Bob Dupont,Dan Cri,Mal Truand" and not HandshakeDB.demandes[MOI]["Vieux Pas#5541"], "après /reload : " .. noms())
  t = t + ns.DEMANDE_DUREE + 1
  assert(#ns.demandesLues() == 0 and next(HandshakeDB.demandes[MOI]) == nil, "elles vieillissent, gardées comprises")
  ChatFrame1, ChatFrame2, NUM_CHAT_WINDOWS = nil, nil, nil
  time, print, AzerothCommuneDB.chars, GetTime = T0, P0, chars0, GT0
end
print("Handshake : historique du chat et /reload OK")


aucunReleve("après les calculs")
-- Chargement (ADDON_LOADED) : les relevés d'un Handshake d'avant sont purgés, les données propres restent.
HandshakeDB = { chars = { [MOI] = { bags = {}, bank = {} } }, items = { [1] = { name = "x" } }, market = { ["6942-Alliance"] = {} },
  recipes = {}, contracts = { k = { status = "signe" } }, surnames = { Bob = "Kerys" }, debug = { on = true } }
local loader
CreateFrame = function() return setmetatable({ SetScript = function(_, _, fn) loader = fn end }, stubMT) end
assert(loadfile("Handshake/Donnees.lua"))("Handshake", ns)
loader(nil, "ADDON_LOADED", "Handshake")
aucunReleve("au chargement")
assert(HandshakeDB.contracts.k and HandshakeDB.surnames.Bob and HandshakeDB.debug.on, "données propres gardées")
-- Première ouverture : des contrats, rien d'autre (plus de réglages de l'arbre : ils sont à Composants).
HandshakeDB = nil
assert(loadfile("Handshake/Commande.lua"))("Handshake", ns)
loader(nil, "ADDON_LOADED", "Handshake")
assert(type(HandshakeDB.contracts) == "table" and HandshakeDB.options == nil and HandshakeDB.projets == nil, "première ouverture")
-- Contrats d'avant la signature par GUID (signataires « Prénom-Royaume », Handshake#29) : plus lus, purgés au chargement
-- (perte de données acceptée) ; ceux signés par GUID restent, et aussi ceux du Testeur (mode debug).
HandshakeDB = { contracts = { ancien = { client = "Bob-CAMWOWEU4Realm8PvP", artisan = "Bel-CAMWOWEU4Realm8PvP", status = "signe" },
  neuf = { client = "Player-6942-00000B0B", artisan = "Player-6942-0000BEEF", status = "signe" } },
  debug = { contracts = { vieux = { client = "Testeur-R" }, bon = { client = "Player-0-00000DEB" } } } }
loader(nil, "ADDON_LOADED", "Handshake")
assert(HandshakeDB.contracts.neuf and not HandshakeDB.contracts.ancien, "ancien contrat purgé, contrat par GUID gardé")
assert(HandshakeDB.debug.contracts.bon and not HandshakeDB.debug.contracts.vieux, "pareil pour ceux du Testeur")
-- Les projets sont partis dans Composants (Handshake#39) : pas de migration, perte acceptée. Les projets d'avant, leurs
-- commandes (rattachées à des identités que Composants redonnera), les réglages de l'arbre et les vieilles tables
-- s'effacent ; les contrats restent intacts.
HandshakeDB = { orders = { { name = "Ma commande", lines = { { id = 5541, qty = 1 } } } }, current = 1, force = { [2841] = "acheter" },
  options = { bags = true }, projets = { { id = 1, name = "Projet #5", lines = { { id = 5541, qty = 1 } } } }, projetSeq = 1, courant = 1,
  commandes = { [1] = { liste = { { id = 1, player = "Bel", contrat = "neuf" } }, seq = 1 } },
  contracts = { neuf = { client = "Player-6942-00000B0B", artisan = "Player-6942-0000BEEF", status = "signe" } } }
loader(nil, "ADDON_LOADED", "Handshake")
for _, k in ipairs({ "projets", "projetSeq", "courant", "commandes", "options", "orders", "current", "force" }) do
  assert(HandshakeDB[k] == nil, "effacé au chargement : " .. k)
end
assert(HandshakeDB.contracts.neuf, "le contrat reste")
-- À l'entrée en jeu, Composants chargé : les commandes d'un projet qui n'existe plus sont oubliées, celles d'un projet
-- vivant restent ; sans Composants, rien n'est oublié (ses projets ne sont peut-être que désactivés).
do
  local vivant = C.NouveauProjet()
  HandshakeDB.commandes = { [vivant.id] = { liste = { { id = 1 } }, seq = 1 }, [99999] = { liste = { { id = 1 } }, seq = 1 } }
  local C0 = Composants
  Composants, ns.branche = nil, nil
  ns.brancherComposants()
  assert(HandshakeDB.commandes[99999] and not ns.branche, "sans Composants : rien d'oublié")
  Composants = C0
  ns.brancherComposants()
  assert(HandshakeDB.commandes[vivant.id] and not HandshakeDB.commandes[99999] and HandshakeDB.contracts.neuf, "projet disparu : ses commandes oubliées")
end
cns.openCraftWindow = noop -- pas d'interface hors jeu
ns.importText(msgs[1] .. " " .. msgs[2]:gsub("^.-: ", ""), "Bob")
local importe = C.Projets()[#C.Projets()]
assert(cns.projetCourant() == importe and #importe.lines == 3 and ns.projetCommande(importe).player == "Bob", "commande importée en projet, affichée")
assert(ns.contratDuBloc(importe, nil) == 1, "une liste reçue : un projet commandé en entier")
-- Les commandes d'avant Composants#26 (sans numéro) : celles d'un bloc ou avec un contrat en prennent un, rien n'est effacé ;
-- le projet entier jamais commandé reste sans.
do
  local db = { commandes = { [1] = { liste = { { id = 1 }, { id = 2, bloc = "Forge" }, { id = 3, contrat = "x#1" } }, seq = 3 },
    [2] = { liste = { { id = 1, contrat = "y#2" } }, seq = 1 } } }
  ns.numeroterAnciennes(db)
  local l = db.commandes[1].liste
  assert(not l[1].n and l[2].n and l[3].n and db.commandes[2].liste[1].n and #l == 3, "numérotées, rien d'effacé")
end
print("Handshake : reprise, purge et import OK")

-- /handshake essai : la commande à la main revient comme un chuchotement de soi-même, sans réseau.
UnitName = function() return "Belegard" end
popups = {}
local realPrint = print
print = noop
HandshakeDB.main = { lines = { { id = 7963, qty = 1 } }, apporte = {} }
SlashCmdList.HANDSHAKE("essai")
HandshakeDB.main = nil
print = realPrint
assert(#popups == 1 and popups[1].who == "Belegard" and popups[1].kind == "commande", "essai : import proposé")
print("Handshake : essai OK")

-- Protocole 3 (signature par GUID) incompatible avec le 2 : la version de l'add-on change (0.2.0-beta).
local toc = assert(io.open("Handshake/Handshake.toc")):read("*a")
assert(toc:find("\n## Version: 0.2.0-beta\n", 1, true), "version 0.2.0-beta dans le TOC")
print("Handshake : version OK")

-- Morceaux bornés : (1/9999) ignoré, un « 1/n » repart de zéro.
local t0 = 0
GetTime = function() return t0 end
popups = {}
ns.onChat("CHAT_MSG_WHISPER", "Commande (1/9999) : 1x[Minerai de mithril]", "Mal-Belegard")
ns.onChat("CHAT_MSG_WHISPER", "Commande (2/2) : vieux morceau", "Bob-Belegard")
ns.onChat("CHAT_MSG_WHISPER", msgs[1], "Bob-Belegard")
assert(#popups == 0, "rien de complet")
ns.onChat("CHAT_MSG_WHISPER", msgs[2], "Bob-Belegard")
assert(#popups == (#msgs == 2 and 1 or 0), "le vieux 2/2 a été jeté par le 1/2")
print("Handshake : morceaux bornés OK")

-- Contrats entre deux joueurs simulés : Belegard (artisan) et Bob (client), chacun sa base. Un perso s'identifie par
-- son GUID (les signataires d'un contrat, Handshake#29) ; le serveur donne son nom « Prénom Nom » comme expéditeur d'un
-- message d'addon et le prend pour un chuchotement (le prénom seul ne passe plus, LibCommune#35).
local GBEL, GBOB, GMAL, GCARL = "Player-6942-0000BEEF", "Player-6942-00000B0B", "Player-6942-0000BAD0", "Player-6942-0000CA71"
local BEL, BOB = GBEL, GBOB -- les signataires
local BELN, BOBN, MALN, CARLN = "Belegard Marteaudefer", "Bob Dupont", "Mallory Truand", "Carl Inconnu"
local NOM, GUIDDE = { [GBEL] = BELN, [GBOB] = BOBN }, { [BELN] = GBEL, [BOBN] = GBOB }
local clock = 1795000000
GetServerTime = function() return clock end
-- Chacun ses contrats (HandshakeDB) et ses projets (ComposantsDB).
local bases = { [BEL] = { contracts = {} }, [BOB] = { contracts = {} } }
local projets = { [BEL] = {}, [BOB] = {} }
local current, notes, wire = BEL, {}, {}
local function as(who) current = who; HandshakeDB, ComposantsDB = bases[who], projets[who] end
UnitName = function() return NOM[current]:match("^(%S+) (%S+)$") end
UnitGUID = function(u) if u == "player" then return current end end
-- Une proposition sur le fil : P|3|expéditeur|origine|id|version|parent|client|artisan|m|o|échéance
local function P(from, origin, id, v, parent, client, artisan, m, o, d)
  return table.concat({ "P", "3", from, origin, id, v, parent, client, artisan, m, o, d }, "|")
end
ns.ctNotify = function(t) notes[#notes + 1] = current .. " : " .. t end
-- Le réseau : ce qu'envoie l'un arrive chez l'autre, sous le nom que donne le serveur (on peut aussi intercepter pour
-- jouer l'attaquant).
C_ChatInfo = { SendAddonMessage = function(prefix, text, channel, target)
  wire[#wire + 1] = { text = text, target = target }
  local from = current
  as(GUIDDE[target]); ns.ctOnAddon(prefix, text, channel, NOM[from]); as(from)
end }
local function inject(fromName, to, body) -- un message forgé, en un morceau, d'un expéditeur nommé par le serveur
  local back = current
  as(to); ns.ctOnAddon("Handshake", "1/1|" .. body, "WHISPER", fromName); as(back)
end
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

assert(ns.isGUID(GBEL) and not ns.isGUID("Player-6942-0BEEF") and not ns.isGUID("Player-6942-|cff00000") and not ns.isGUID("Bob-6942"),
  "grammaire stricte d'un GUID")
assert(ns.ctHash("abc") ~= ns.ctHash("abd") and #ns.ctHash("abc") == 16, "empreinte 64 bits")

-- Belegard propose : Bob fournit 36 minerais (caution 150 pc l'unité), Belegard livre une claymore payée 5400 + 4000.
-- Bob n'a jamais appris le GUID de Belegard (ni chuchotement, ni cible) : le GUID déclaré est accepté pour négocier.
as(BEL)
local terms = { origin = BEL, id = "1795000000", v = "1", parent = "0", client = BOB, artisan = BEL, peer = { guid = BOB, name = BOBN },
  m = { { id = 3858, qty = 36, unit = 150 } }, o = { { id = 7963, qty = 1, unit = 9400 } }, d = clock + 3 * 86400 }
ns.ctPropose(terms)
assert(wire[#wire].target == BOBN and wire[#wire].text:find("1/1|P|3|" .. GBEL .. "|" .. GBEL .. "|1795000000|1|0|" .. GBOB .. "|" .. GBEL .. "|", 1, true) == 1,
  "chuchoté à « Prénom Nom », le GUID de l'expéditeur en 3e champ, deux GUID signataires : " .. wire[#wire].text)
as(BOB)
local k = BEL .. "#1795000000"
local atBob = HandshakeDB.contracts[k]
assert(ns.ctCheckClaim(BELN, GBEL) == "inconnu", "GUID jamais appris")
assert(atBob and atBob.status == "a_signer" and atBob.author == BEL, "Bob a la proposition (GUID déclaré, jamais appris)")
assert(atBob.peer.guid == GBEL and atBob.peer.name == BELN and not atBob.peer.verified, "le nom du serveur, le GUID déclaré, pas encore vérifié")
assert(atBob.hash == bases[BEL].contracts[k].hash, "même empreinte des deux côtés")

-- Bob contre-propose une caution de 6000 au lieu de 5400 : v2, parent = v1. Un brouillon d'abord, à côté de la v1 : rien
-- ne part avant qu'il ait relu la fiche de SA version et cliqué « Envoyer la proposition » (P8, n° 11, 13, 26, 57).
local envoyes = #wire
local brouillon2 = assert(ns.ctCounter(atBob, 6000, nil, nil))
assert(brouillon2.status == "brouillon" and #wire == envoyes and HandshakeDB.contracts[ns.ctKey(brouillon2)] == brouillon2
  and HandshakeDB.contracts[k] == atBob and atBob.v == "1" and atBob.status == "a_signer", "contre-proposition : un brouillon, rien n'est parti")
assert(ns.ctPropose(brouillon2) and #wire == envoyes + 1, "envoyée de sa fiche")
as(BEL)
local atBel = HandshakeDB.contracts[k]
assert(atBel.v == "2" and atBel.status == "a_signer" and atBel.prev.v == "1" and ns.ctTotal(atBel.m) == 36 * 167, "contre-proposition reçue, avec la version d'avant")

-- n° 5 : Belegard accepte avec l'empreinte affichée ; une empreinte périmée ne signe rien.
assert(not ns.ctAccept(atBel, "0000000000000000"), "empreinte périmée : rien n'est signé")
assert(ns.ctAccept(atBel, atBel.hash), "signé côté Belegard")
as(BOB)
assert(HandshakeDB.contracts[k].status == "signe", "signé côté Bob")
print("Handshake : contrat proposé, négocié, signé OK")

-- Un contrat porte deux GUID : un nom, une adresse ou un GUID malformé à la place de l'un d'eux est rejeté.
do
  local bon = P(GMAL, GMAL, "1795000020", "1", "0", GBOB, GMAL, "", "7963:1:1", clock + 3600)
  assert(ns.ctParse(bon, GBOB, clock), "témoin : deux GUID, le GUID de l'expéditeur")
  for _, mauvais in ipairs({ "Bob Dupont", "Bob", "Bob-6942", "0", "Player-6942-0B0B", "Player-6942-00000B0B-x", "Player-6942-|cff0000", "player-6942-00000B0B" }) do
    for _, champ in ipairs({ 3, 4, 8, 9 }) do -- expéditeur, origine, client, artisan
      local f = {}
      for x in (bon .. "|"):gmatch("([^|]*)|") do f[#f + 1] = x end
      f[champ] = mauvais
      local c, raison = ns.ctParse(table.concat(f, "|"), GBOB, clock)
      assert(c == nil and (raison == "GUID" or raison == "format"), ("champ %d « %s » : %s"):format(champ, mauvais, tostring(raison)))
    end
  end
end

-- Attaques sur la négociation (SECURITE.md).
local before = count(bases[BOB].contracts)
-- n° 2 : Mallory propose un contrat dont l'origine est Belegard, en déclarant son propre GUID.
inject(MALN, BOB, P(GMAL, GBEL, "1795000001", "1", "0", GBOB, GMAL, "", "7963:1:1", clock + 3600))
-- n° 3 : rôles qui ne sont pas {moi, l'expéditeur}.
inject(MALN, BOB, P(GMAL, GMAL, "1795000002", "1", "0", GCARL, GMAL, "", "7963:1:1", clock + 3600))
inject(MALN, BOB, P(GMAL, GMAL, "1795000002", "1", "0", GBOB, GBEL, "", "7963:1:1", clock + 3600))
-- n° 14 : nombres piégés, zéros de tête, liste pas triée, doublon, quantité énorme.
for _, bad in ipairs({ "0x10:1:1", "7963:01:1", "7963:1:1,3858:1:1", "7963:1:1,7963:1:1", "7963:5000:1", "7963:1:-1", "7963:1:1e9" }) do
  inject(MALN, BOB, P(GMAL, GMAL, "1795000003", "1", "0", GBOB, GMAL, "", bad, clock + 3600))
end
-- n° 11 : échéance absurde ; n° 22 : protocole inconnu (l'ancien « 2 », celui des adresses, aussi) ; champ en trop.
inject(MALN, BOB, P(GMAL, GMAL, "1795000004", "1", "0", GBOB, GMAL, "", "7963:1:1", clock + 99 * 86400))
inject(MALN, BOB, (P(GMAL, GMAL, "1795000005", "1", "0", GBOB, GMAL, "", "7963:1:1", clock + 3600):gsub("^P|3|", "P|2|")))
inject(MALN, BOB, P(GMAL, GMAL, "1795000006", "1", "0", GBOB, GMAL, "", "7963:1:1", clock + 3600) .. "|x")
-- Le format d'avant (protocole 2, adresses « Prénom-Royaume ») : plus lu.
inject(MALN, BOB, table.concat({ "P", "2", "Mallory-6942", "1795000007", "1", "0", "Bob-6942", GBOB, "Mallory-6942", GMAL, "", "7963:1:1", clock + 3600 }, "|"))
-- Identité : sans GUID de l'expéditeur, avec un GUID qui n'est pas le mien, avec un GUID piégé.
inject(MALN, BOB, P("0", GMAL, "1795000008", "1", "0", GBOB, GMAL, "", "7963:1:1", clock + 3600))
inject(MALN, BOB, P(GMAL, GMAL, "1795000009", "1", "0", GCARL, GMAL, "", "7963:1:1", clock + 3600))
inject(MALN, BOB, P("Player-6942-|cff0000", GMAL, "1795000010", "1", "0", GBOB, GMAL, "", "7963:1:1", clock + 3600))
-- Le GUID déclaré contredit celui que le serveur a donné pour ce nom (Mallory a chuchoté à Bob : le jeu a joint le
-- sien) : Mallory annonce celui de Belegard.
ns.learnGUID(MALN, GMAL)
notes = {}
inject(MALN, BOB, P(GBEL, GBEL, "1795000011", "1", "0", GBOB, GBEL, "", "7963:1:1", clock + 3600))
assert(notes[1] and notes[1]:find("pas le sien"), "GUID déclaré ≠ GUID appris pour ce nom : rejeté, dit")
-- Un GUID appris sous un autre nom : Bob a ciblé Belegard ; Carl (jamais vu) annonce le GUID de Belegard.
UnitExists, UnitIsPlayer = function() return true end, function() return true end
local vraiUnitName, vraiUnitGUID = UnitName, UnitGUID
UnitName = function(u) if u == "target" then return "Belegard", "Marteaudefer" end return vraiUnitName(u) end
UnitGUID = function(u) if u == "target" then return GBEL end return vraiUnitGUID(u) end
ns.learnUnit("target")
UnitName, UnitGUID = vraiUnitName, vraiUnitGUID
assert(ns.knownGUID[BELN] == GBEL and ns.knownName[GBEL] == BELN and ns.ctCheckClaim(BELN, GBEL) == "ok", "cible : nom complet et GUID appris")
notes = {}
inject(CARLN, BOB, P(GBEL, GBEL, "1795000012", "1", "0", GBOB, GBEL, "", "7963:1:1", clock + 3600))
assert(notes[1] and notes[1]:find("pas le sien"), "GUID connu sous un autre nom : rejeté, dit")
assert(count(bases[BOB].contracts) == before, "aucune proposition piégée enregistrée")
-- n° 19 : un tiers refuse le contrat signé de Bob et Belegard ; même en déclarant le GUID de Belegard, il n'est pas
-- Belegard pour le serveur.
inject(MALN, BOB, "R|3|" .. GMAL .. "|" .. BEL .. "|1795000000|2")
inject(CARLN, BOB, "R|3|" .. GBEL .. "|" .. BEL .. "|1795000000|2")
inject(BELN, BOB, "R|2|" .. BEL .. "|1795000000|2") -- l'ancien format, sans GUID de l'expéditeur
-- n° 5/P5 : une v3 envoyée après la signature ne change rien.
inject(BELN, BOB, P(GBEL, GBEL, "1795000000", "3", atBel.hash, GBOB, GBEL, "3858:36:1", "7963:1:9400", clock + 3600))
local signed = bases[BOB].contracts[k]
assert(signed.status == "signe" and signed.v == "2" and ns.ctTotal(signed.m) == 36 * 167, "contrat signé figé")
-- n° 12 (inondation) : au-delà de 3 propositions en attente du même joueur, ignoré (témoin : les 3 premières passent),
-- même s'il change de GUID déclaré (compté par nom, celui du serveur).
for n = 1, 5 do
  local g = ("Player-6942-0000BA%02d"):format(n)
  inject("Inondeur Fou", BOB, P(g, g, "17950001" .. n, "1", "0", GBOB, g, "", "7963:1:1", clock + 3600))
end
assert(count(bases[BOB].contracts) == before + 3, "3 propositions en attente au plus")
as(BOB); ns.ctOnAddon("Handshake", "1/99|P", "WHISPER", MALN)
print("Handshake : attaques sur la négociation repoussées OK")

-- Échanges. Étape 1 vue par Bob (client) : il donne 20 minerais, Belegard 20 × 167 (6000/36 arrondi à l'unité).
-- Le GUID déclaré par Belegard n'était pas appris quand Bob a signé : il est vérifié ici, au premier échange.
as(BOB)
local unit = signed.m[1].unit
local function snap(partner, give, get) return { partner = partner, guid = GBEL, give = give, get = get } end
local s1 = snap(BELN, { items = { [3858] = 20 }, money = 0 }, { items = {}, money = 20 * unit })
assert(ns.ctEvaluate(signed, BOB, s1, clock).ok, "lot 1 équilibré : conforme")
-- Un échange dont le partenaire a un autre GUID que celui du contrat : NON CONFORME, même sous le bon nom.
local autre = ns.ctEvaluate(signed, BOB, { partner = BELN, guid = GMAL, give = s1.give, get = s1.get }, clock)
assert(not autre.ok and autre.problems[1]:find("GUID", 1, true), "partenaire d'un autre GUID : non conforme")
assert(#ns.ctActiveWith(BELN, GMAL) == 1, "même nom, autre GUID : le panneau s'ouvre et dit NON CONFORME")
assert(#ns.ctActiveWith(MALN, GMAL) == 0, "ni le nom ni le GUID : pas de contrat")
-- n° 45 : caution trop faible pour ce qui est donné.
local short = ns.ctEvaluate(signed, BOB, snap(BELN, { items = { [3858] = 20 }, money = 0 }, { items = {}, money = 19 * unit }), clock)
assert(not short.ok and short.short == unit, "il manque une unité de caution")
-- n° 30/33 : objet hors contrat donné, trop donné.
assert(not ns.ctEvaluate(signed, BOB, snap(BELN, { items = { [3858] = 40 }, money = 0 }, { items = {}, money = 40 * unit }), clock).ok, "40 > 36 : non conforme")
assert(not ns.ctEvaluate(signed, BOB, snap(BELN, { items = { [7963] = 1 }, money = 0 }, { items = {}, money = 99999 }), clock).ok, "objet hors contrat donné")
-- n° 31/26 : bon GUID mais autre nom avant toute confirmation, contrat échu, objet illisible.
assert(not ns.ctEvaluate(signed, BOB, snap("Bélegard Marteaudefer", s1.give, s1.get), clock).ok, "homonyme, GUID pas encore confirmé")
assert(not ns.ctEvaluate(signed, BOB, { partner = BELN, guid = GBEL, unknown = true, give = s1.give, get = s1.get }, clock).ok, "illisible")
assert(not ns.ctEvaluate(signed, BOB, s1, clock + 4 * 86400).ok, "échu")
ns.ctRecord(signed, BOB, s1, clock)
assert(signed.peer.guid == GBEL and signed.peer.verified and signed.got[3858] == nil and signed.gave[3858] == 20 and signed.net == 0, "lot 1 inscrit, GUID confirmé")
assert(not ns.ctEvaluate(signed, BOB, { partner = BELN, guid = "Player-6942-0000A07E", give = s1.give, get = s1.get }, clock).ok, "même nom, autre GUID")
local renamed = ns.ctEvaluate(signed, BOB, { partner = "Belegarde Marteaudefer", guid = GBEL, give = { items = { [3858] = 16 }, money = 0 },
  get = { items = {}, money = 16 * unit } }, clock)
assert(renamed.ok and renamed.warnings[1]:find("nom a changé"), "même GUID, nouveau nom : conforme, signalé")
-- n° 46 : « c'est le lot 2/2, donne tout » — le reste dû vient du registre : 16 au plus.
assert(not ns.ctEvaluate(signed, BOB, snap(BELN, { items = { [3858] = 20 }, money = 0 }, { items = {}, money = 20 * unit }), clock).ok, "plus que les 16 restants")
ns.ctRecord(signed, BOB, snap(BELN, { items = { [3858] = 16 }, money = 0 }, { items = {}, money = 16 * unit }), clock)
-- Étape 2 : la claymore contre 9400 ; n° 35 : sans l'objet, payer est non conforme.
assert(not ns.ctEvaluate(signed, BOB, snap(BELN, { items = {}, money = 9400 }, { items = {}, money = 0 }), clock).ok, "payer sans recevoir")
local s2 = snap(BELN, { items = {}, money = 9400 }, { items = { [7963] = 1 }, money = 0 })
assert(ns.ctEvaluate(signed, BOB, s2, clock).ok, "livraison conforme")
ns.ctRecord(signed, BOB, s2, clock)
assert(signed.status == "clos" and signed.net == 0, "contrat clos, solde nul")
assert(signed.unsaved == nil, "plus d'état « non enregistré » (#70)")
print("Handshake : échanges vérifiés et contrat clos OK")

-- Demande (CONCEPTION.md) : Bob veut une claymore (30 minerais + 4 cuirs lourds), il apporte le cuir (Ctrl+clic),
-- offre 3 po. Contrat v1 : caution = prix de marché du cuir seulement ; la claymore = sa part de caution + l'offre.
as(BOB)
UnitFactionGroup = function() return "Alliance" end
AzerothCommuneMarket = { ["6942-Alliance"] = { scanned = "hier", items = { [3858] = { tiers = { { price = 200, qty = 999 } } },
  [4234] = { tiers = { { price = 500, qty = 999 } } }, [7963] = { tiers = { { price = 99999, qty = 9 } } } } } }
AzerothCommuneDB.recipes = { [1] = { name = "Claymore", output = 7963, reagents = { { id = 3858, qty = 30 }, { id = 4234, qty = 4 } } } }
AzerothCommuneItems.items[4234] = { name = "Cuir lourd", link = link(4234, "Cuir lourd") }
local demande = projetPour(BELN, 30000, { { id = 7963, qty = 1 } })
ns.projetApport(demande, 4234, true)
local dres = ns.arbreDemande(demande, ns.projetApports(demande))
local brought = ns.demandeApports(dres)
assert(#brought == 1 and brought[1].id == 4234 and brought[1].qty == 4, "apport : le cuir, case entière")
assert(dres.roots[1].how == "fabriquer" and dres.roots[1].cost == 30 * 200, "part de l'artisan : le minerai seulement")
-- L'artisan doit avoir un GUID donné par le serveur (Bob a ciblé Belegard plus haut) : un contrat porte deux GUID.
local inconnu = projetPour(CARLN, 30000, { { id = 7963, qty = 1 } })
local pas, pourquoi = ns.ctFromDemande(ns.projetCommande(inconnu), 3)
assert(pas == nil and pourquoi:find("GUID de " .. CARLN .. " inconnu", 1, true), "artisan jamais vu : pas de contrat, " .. tostring(pourquoi))
-- Un projet d'avant le nom complet (« Belegard » seul) : il faut « Prénom Nom », pas un message sur le GUID.
local prenomSeul = projetPour("Belegard", 30000, { { id = 7963, qty = 1 } })
pas, pourquoi = ns.ctFromDemande(ns.projetCommande(prenomSeul), 3)
assert(pas == nil and pourquoi:find("nom complet", 1, true) and pourquoi:find("Prénom Nom", 1, true) and not pourquoi:find("GUID", 1, true),
  "prénom seul : le nom complet est demandé, " .. tostring(pourquoi))
-- La commande en clair au prénom seul : refusée à l'écran, rien ne part dans le vide.
do
  local partis, dit = {}, {}
  local realWhisper, realPrint = ns.whisper, print
  ns.whisper = function(msg, cible) partis[#partis + 1] = cible end
  print = function(t) dit[#dit + 1] = t end
  ns.sendOrder(ns.projetCommande(prenomSeul))
  print = realPrint
  assert(#partis == 0 and #dit == 1 and dit[1]:find("nom complet", 1, true) and dit[1]:find("Belegard", 1, true),
    "prénom seul : rien chuchoté, " .. tostring(dit[1]))
  ns.sendOrder(ns.projetCommande(projetPour("Belegard Marteaudefer-CAMWOWEU4Realm8PvP", nil, { { id = 7963, qty = 1 } })))
  ns.whisper = realWhisper
  assert(#partis == 1 and partis[1] == BELN, "chuchoté au nom complet « Prénom Nom »")
end
local v1 = ns.ctFromDemande(ns.projetCommande(demande), 3)
assert(v1.client == BOB and v1.artisan == BEL and v1.peer.name == BELN and v1.peer.verified, "moi client, l'autre artisan (son GUID appris)")
assert(#v1.m == 1 and v1.m[1].id == 4234 and v1.m[1].unit == 500 and v1.o[1].unit == 4 * 500 + 30000, "caution sur l'apport + offre")
assert(ns.ctParse(ns.ctMessage(v1), BEL, clock), "ce qu'on envoie passe notre propre lecture stricte")
-- Sans apport : vente simple (pas de caution).
local simple = ns.ctFromDemande(ns.projetCommande(projetPour(BELN, 30000, { { id = 7963, qty = 1 } })), 3)
assert(#simple.m == 0 and simple.o[1].unit == 30000, "vente simple")
-- En clair : « Commande : 1x[Claymore] · j'apporte 4x[Cuir lourd] · offre 3 po », relu à l'identique.
popups = {}
local realWhisper = ns.whisper
ns.whisper = function(msg) ns.onChat("CHAT_MSG_WHISPER", msg, BOBN) end
ns.sendOrder(ns.projetCommande(demande))
ns.whisper = realWhisper
assert(#popups == 1, "commande reçue")
local wanted, kindR, offer, apportsR = ns.parseList(popups[1].data.text)
assert(#wanted == 1 and wanted[1].id == 7963 and #apportsR == 1 and apportsR[1].id == 4234 and apportsR[1].qty == 4 and offer == 30000,
  "ce qu'il veut, ce qu'il apporte, son offre")
ns.importText(popups[1].data.text, "Bob")
assert(ns.projetApports(cns.projetCourant()) and ns.projetApports(cns.projetCourant())[4234] and ns.projetCommande(cns.projetCourant()).tip == 30000, "demande importée avec ses apports")
print("Handshake : demande (apports, offre, vente simple, en clair) OK")

-- Mode debug (Debug.lua, non publié) : le Testeur a un nom complet et un GUID (numéro de serveur 0 : il n'existe pas) ;
-- ce qui lui est envoyé lui est livré sous mon nom, et il le lit comme un vrai joueur.
as(BOB)
ns.learnGUID("Testeur Bacasable", "Player-0-00000DEB") -- ce que fait l'ouverture du mode debug
local essai = ns.ctFromDemande(ns.projetCommande(projetPour("Testeur Bacasable", 100, { { id = 7963, qty = 1 } })), 3)
assert(essai and ns.ctPropose(essai), "demande au Testeur")
local chezTesteur = HandshakeDB.debug.contracts[ns.ctKey(essai)]
assert(chezTesteur and chezTesteur.status == "a_signer" and chezTesteur.peer.name == BOBN and chezTesteur.peer.guid == GBOB,
  "livrée au Testeur, sous mon nom et mon GUID")
HandshakeDB.contracts[ns.ctKey(essai)], HandshakeDB.debug = nil, nil
print("Handshake : mode debug, le Testeur OK")

-- #49 : un projet à lignes fabrication (Composants#7). « Tout le projet » : la fabrication devient l'objet produit × fois,
-- l'enchantement (rien de produit) aucune ligne ; demande, brouillon et son écart, envoi en clair ne plantent plus.
do
  AzerothCommuneDB.recipes[2] = { name = "Enchantement", reagents = { { id = 3858, qty = 1 } } }
  local fab = C.NouveauProjet({ lines = { { recette = 1, fois = 2 }, { recette = 2, fois = 3 } } })
  C.Tenir(fab, "test") -- comme Maîtrise
  ns.projetArtisan(fab, BELN)
  ns.projetOffre(fab, 30000)
  local v = ns.projetCommande(fab)
  assert(#v.lines == 1 and v.lines[1].id == 7963 and v.lines[1].qty == 2, "fabrication → objet × fois, enchantement ignoré")
  local ct = assert(ns.projetEnvoyer(fab))
  assert(#ct.o == 1 and ct.o[1].id == 7963 and ct.o[1].qty == 2, "demande : la claymore × 2")
  assert(not ns.projetCommande(fab).ecart, "brouillon : pas d'écart avec son projet")
  local partis, realWhisper = 0, ns.whisper
  ns.whisper = function() partis = partis + 1 end
  ns.sendOrder(ns.projetCommande(fab))
  ns.whisper = realWhisper
  assert(partis >= 1, "en clair : chuchoté")
  HandshakeDB.contracts[ns.ctKey(ct)], AzerothCommuneDB.recipes[2] = nil, nil
  C.Tenir(fab, nil)
  C.Supprimer(fab.id)
end
print("Handshake : projet à lignes fabrication OK")

-- Je réponds (l'artisan) : Belegard ouvre la demande dans son arbre, demande aussi le minerai et chiffre 5 po.
ns.ctPropose(v1)
as(BEL)
local key1 = ns.ctKey(v1)
local recu = HandshakeDB.contracts[key1]
assert(recu and ns.ctStatus(recu) == "a_signer", "demande reçue par l'artisan")
local rep = ns.projetReponse(recu)
local function reponse1() return ns.projetCommande(rep) end -- la réponse elle-même : sa commande « tout le projet »
assert(ns.estReponse(rep) and reponse1().reponse == key1 and ns.projetApports(rep)[4234] and reponse1().tip == 30000 and rep.lines[1].id == 7963 and reponse1().player == BOBN, "sa demande dans mon arbre")
assert(select(2, ns.ctReplyFromOrder(reponse1())):find("rien n'a changé"), "rien changé : rien ne part")
ns.projetApport(rep, 3858, true)
ns.projetOffre(rep, 50000)
assert(ns.projetReponse(recu) == rep and ns.projetApports(rep)[3858], "même version rouverte : mes changements restent")
local envoyesRep = #wire
local v2 = ns.ctReplyFromOrder(reponse1())
assert(v2.status == "brouillon" and #wire == envoyesRep and recu.v == "1" and HandshakeDB.contracts[ns.ctKey(v2)] == v2,
  "la contre-proposition de l'artisan : un brouillon, relu sur sa fiche ; rien n'est parti")
assert(ns.ctPropose(v2) and #wire == envoyesRep + 1, "envoyée de sa fiche")
assert(v2.v == "2" and #v2.m == 2 and v2.m[1].id == 3858 and v2.m[1].unit == 200 and v2.m[2].unit == 500,
  "minerai ajouté au prix de mon scan, cuir à la caution du contrat")
assert(v2.o[1].unit == 30 * 200 + 4 * 500 + 50000, "livraison = cautions + mon prix")
as(BOB)
local back = HandshakeDB.contracts[key1]
assert(back.v == "2" and back.status == "a_signer" and back.prev.v == "1", "Bob reçoit la contre-proposition")
assert(not ns.ctReplyFromOrder({ reponse = key1, lines = demande.lines }), "le client ne répond pas comme artisan")
-- Un brouillon de nouvelle version dépassé (l'autre a envoyé la sienne entre-temps) ne part pas : il est effacé, comme
-- celui d'une nouvelle version de demande (ctVersionDemande, plus bas). Contre-proposition d'abord (ctCounter)…
do
  local function relance(qui) -- qui envoie une nouvelle version de sa copie (+10 pa à la livraison)
    as(qui)
    local c = HandshakeDB.contracts[key1]
    assert(ns.ctPropose(assert(ns.ctCounter(c, nil, ns.ctTotal(c.o) + 1000))))
  end
  local function perime(b, quoi)
    local envoyes = #wire
    local rien, err = ns.ctPropose(b)
    assert(not rien and err:find("a changé") and not HandshakeDB.contracts[ns.ctKey(b)] and #wire == envoyes, quoi .. " périmé : effacé, rien n'est parti")
  end
  local contre = assert(ns.ctCounter(back, nil, ns.ctTotal(back.o) + 500)) -- Bob, sur la v2 reçue
  relance(BEL) -- Belegard envoie sa v3 avant
  as(BOB)
  perime(contre, "la contre-proposition (ctCounter)")
  assert(HandshakeDB.contracts[key1].v == "3" and HandshakeDB.contracts[key1].status == "a_signer", "la v3 de Belegard reste à signer")
  -- … puis la réponse de l'artisan (ctReplyFromOrder) : Belegard prépare la sienne sur la v4 de Bob, Bob envoie sa v5 avant.
  relance(BOB)
  as(BEL)
  local rep4 = assert(ns.ctReplyFromOrder(reponse1()))
  assert(rep4.status == "brouillon" and rep4.v == "5", "la réponse de Belegard : un brouillon de la v5")
  relance(BOB)
  as(BEL)
  perime(rep4, "la réponse de l'artisan (ctReplyFromOrder)")
  assert(HandshakeDB.contracts[key1].v == "5" and HandshakeDB.contracts[key1].author == BOB, "la v5 de Bob reste")
  ns.ctRefuse(HandshakeDB.contracts[key1]) -- clos : il ne compte plus dans les 3 propositions en attente de Bob (n° 12)
  as(BOB)
end
print("Handshake : je réponds (ma part, mes apports, mon prix ; un brouillon relu sur sa fiche) OK")

-- Commande à la main (#38) : sans arbre, une liste « ce que je veux » et une liste « ce que j'apporte » (objets ×
-- quantités), remplies par la recherche (un ID) ou par un objet déposé (un ID). Le contrat ne voit que des objets × quantités :
-- mêmes termes que la commande du projet aux mêmes objets (la claymore, 4 cuirs lourds apportés, offre 3 po).
as(BOB)
do
  local function txt(l) local t = {} for _, x in ipairs(l) do t[#t + 1] = x.id .. ":" .. x.qty .. ":" .. x.unit end return table.concat(t, ",") end
  HandshakeDB.main = nil
  local cm = ns.commandeMain()
  assert(#cm.lines == 0 and #cm.apporte == 0 and ns.commandeMain() == cm, "une commande à la main, vide, rangée dans HandshakeDB")
  assert(ns.mainAjouter(cm, "lines", 7963, 1), "recherche : l'objet choisi entre dans ce que je veux")
  assert(ns.mainAjouter(cm, "apporte", ns.findItem(link(4234, "Cuir lourd")), 3), "un lien donne l'objet, qui entre dans ce que j'apporte")
  assert(ns.mainAjouter(cm, "apporte", 4234, 1) and #cm.apporte == 1 and cm.apporte[1].qty == 4, "le même objet : quantités additionnées")
  assert(not ns.mainAjouter(cm, "apporte", ns.findItem("pas un objet"), 1) and #cm.apporte == 1, "pas d'objet : rien n'entre")
  assert(ns.mainQuantite(cm, "lines", 1, 2) and cm.lines[1].qty == 2 and ns.mainQuantite(cm, "lines", 1, 1), "quantité changée")
  cm.player, cm.tip = BELN, 30000
  local main = assert(ns.ctFromDemande(cm, 3))
  local proj = assert(ns.ctFromDemande(ns.projetCommande(demande), 3))
  assert(txt(main.m) == txt(proj.m) and txt(main.o) == txt(proj.o) and main.artisan == BEL, "mêmes termes : " .. txt(main.m) .. " / " .. txt(main.o))
  -- Deux lignes : mêmes objets, mêmes apports, même caution ; la livraison se répartit sans arbre (prix d'achat de chaque ligne).
  local p2 = projetPour(BELN, 30000, { { id = 7963, qty = 1 }, { id = 3858, qty = 5 } })
  ns.projetApport(p2, 4234, true)
  local cm2 = { lines = { { id = 7963, qty = 1 }, { id = 3858, qty = 5 } }, apporte = { { id = 4234, qty = 4 } }, player = BELN, tip = 30000 }
  local a, b = assert(ns.ctFromDemande(cm2, 3)), assert(ns.ctFromDemande(ns.projetCommande(p2), 3))
  local function objets(l) local t = {} for _, x in ipairs(l) do t[#t + 1] = x.id .. "x" .. x.qty end return table.concat(t, ",") end
  assert(txt(a.m) == txt(b.m) and objets(a.o) == objets(b.o), "deux lignes : mêmes objets et apports")
  assert(math.abs(ns.ctTotal(a.o) - ns.ctTotal(b.o)) <= 3, "deux lignes : caution + offre à l'arrondi près")
  -- Une ligne sans prix d'achat connu : caution et offre à parts égales entre les lignes (jamais 0 pc par objet).
  assert(ns.prixAchatLigne(12345, 1) == nil and ns.prixAchatLigne(7963, 1), "prix d'achat d'une ligne, nil si inconnu")
  local cm3 = { lines = { { id = 7963, qty = 1 }, { id = 12345, qty = 1 } }, apporte = { { id = 4234, qty = 4 } }, player = BELN, tip = 30000 }
  local c3 = assert(ns.ctFromDemande(cm3, 3))
  assert(#c3.o == 2 and c3.o[1].unit == 16000 and c3.o[2].unit == 16000, "prix inconnu : parts égales : " .. txt(c3.o))
  -- Le texte lisible : le même qu'aujourd'hui.
  local function enClair(order)
    local msgs, real = {}, ns.whisper
    ns.whisper = function(m) msgs[#msgs + 1] = m end
    ns.sendOrder(order)
    ns.whisper = real
    return table.concat(msgs, "\n")
  end
  local texte = enClair(cm)
  assert(texte ~= "" and texte == enClair(ns.projetCommande(demande)), "même texte lisible : " .. texte)
  assert(texte:find("^Commande : 1x") and texte:find("· j'apporte 4x", 1, true) and texte:find("· offre 3 po", 1, true), texte)
  -- « Préparer la demande » : un brouillon dans Contrats, refait tant qu'il n'est pas parti ; parti, la commande est figée.
  local ct = assert(ns.mainPreparer(cm))
  assert(ct.status == "brouillon" and cm.contrat == ns.ctKey(ct) and txt(ct.m) == txt(proj.m), "brouillon de la demande")
  local avant = cm.contrat
  ct = assert(ns.mainPreparer(cm))
  assert(cm.contrat == avant or not HandshakeDB.contracts[avant], "refait : l'ancien brouillon ne reste pas")
  assert(ns.ctPropose(ct) and ct.status == "envoye", "envoyée par le chemin d'aujourd'hui")
  assert(ns.mainPreparer(cm) == ct, "envoyée : son contrat, inchangé")
  local ok, raison = ns.mainAjouter(cm, "lines", 3858, 1)
  assert(not ok and raison:find("envoyée", 1, true) and #cm.lines == 1, "envoyée : la commande est figée")
  assert(ns.etatDemande(ct) == "envoyé", ns.etatDemande(ct))
  local nouvelle = ns.mainNouvelle()
  assert(nouvelle ~= cm and #nouvelle.lines == 0 and ns.commandeMain() == nouvelle and HandshakeDB.contracts[ns.ctKey(ct)], "nouvelle commande ; le contrat reste")

  -- Côté artisan : la demande reçue se répond dans la liste. Ce qu'il veut ne change pas ; apports et prix oui ; la
  -- contre-proposition est une nouvelle version (cuir à la caution du contrat, minerai ajouté au prix de mon scan).
  as(BEL)
  local recue = HandshakeDB.contracts[ns.ctKey(ct)]
  assert(recue and ns.ctStatus(recue) == "a_signer", "demande reçue")
  local r = ns.reponseMain(recue)
  assert(r.reponse == ns.ctKey(recue) and r.player == BOBN and objets(r.lines) == "7963x1" and objets(r.apporte) == "4234x4" and r.tip == 30000,
    "sa demande dans la liste")
  local figee, pourquoi = ns.mainAjouter(r, "lines", 3858, 1)
  assert(not figee and pourquoi:find("sa demande", 1, true), "ce qu'il veut : on n'ajoute rien")
  assert(not ns.mainQuantite(r, "lines", 1, 3) and r.lines[1].qty == 1, "ce qu'il veut : quantité figée")
  assert(select(2, ns.ctReplyFromOrder(r)):find("rien n'a changé"), "rien changé : rien ne part")
  assert(ns.mainAjouter(r, "apporte", 3858, 30) and ns.reponseMain(recue) == r, "apport ajouté ; même version : mes changements restent")
  r.tip = 50000
  local v2 = assert(ns.ctReplyFromOrder(r))
  assert(v2.status == "brouillon", "en liste aussi : un brouillon")
  assert(ns.ctPropose(v2))
  assert(v2.v == "2" and txt(v2.m) == "3858:30:200,4234:4:500" and v2.o[1].unit == 30 * 200 + 4 * 500 + 50000, "contre-proposition : " .. txt(v2.m) .. " / " .. txt(v2.o))
  as(BOB)
  local back = HandshakeDB.contracts[ns.ctKey(ct)]
  assert(back.v == "2" and back.status == "a_signer" and back.prev.v == "1", "le demandeur reçoit la nouvelle version")
  HandshakeDB.main = nil
end
-- Ctrl+clic droit appartient aux projets (bientôt Composants) : la commande à la main ne le prend jamais.
local srcMain = io.open("Handshake/CommandeMain.lua"):read("*a")
assert(not srcMain:find("HandleModifiedItemClick", 1, true), "Ctrl+clic droit pas pris")
assert(not srcMain:find("ChatEdit_InsertLink", 1, true), "Maj+clic pas pris : il garde son sens dans le jeu")
print("Handshake : commande à la main (liste, demande, texte, réponse) OK")

-- Règles de la réponse (#10) : un projet tenu (#37) ; ce que veut le demandeur (lignes, quantités) est figé, avec la
-- raison que donne la partie commandes, affichée telle quelle ; apports, choix de case, prix et commande d'un bloc
-- restent à l'artisan. La demande est un contrat reçu (seuls son empreinte, son client, o et m comptent ici).
as(BEL)
do
  local function recue(hash, qty)
    return { origin = BOB, id = "77", hash = hash, client = BOB, peer = { guid = BOB, name = BOBN }, o = { { id = 7963, qty = qty, unit = 9000 } },
      m = { { id = 4234, qty = 4, unit = 500 } } }
  end
  local r = ns.projetReponse(recue("h1", 1))
  local function figee(quoi, ok, raison)
    assert(ok == false and type(raison) == "string" and raison:find("sa demande", 1, true), quoi .. " : refusé, avec sa raison")
  end
  figee("lignes", C.Peut(r, "lignes"))
  figee("ajouter une ligne", C.Ajouter(r, 3858, 2))
  figee("changer une quantité", C.Quantite(r, 1, 5))
  figee("retirer une ligne", C.Retirer(r, 1))
  assert(#r.lines == 1 and r.lines[1].qty == 1, "ce qu'il veut n'a pas bougé")
  assert(C.Peut(r, "choix"), "choix de case : permis (un projet tenu ne tient que ses lignes)")
  assert(ns.projetApport(r, 3858, true) and ns.projetApports(r)[3858], "apports : contre-proposition")
  assert(C.Choix(r, 3858, "acheter") and r.choix[3858] == "acheter", "choix de case : estimation de l'artisan")
  assert(ns.projetOffre(r, 40000) and ns.projetCommande(r).tip == 40000, "offre : mon prix")
  -- Commander un bloc d'une réponse : une commande de cette réponse (sous-traitance), ordinaire (j'en suis le client).
  C.Choix(r, 3858, nil)
  local i = ns.projetCommander(r, C.Arbre(r, true).blocs[1])
  local sous = ns.projetCommande(r, i)
  assert(i == 2 and #ns.projetCommandes(r) == 2 and sous.bloc and not sous.reponse and sous.etat == "préparé",
    "le bloc commandé : une commande de la réponse")
  assert(ns.projetCommande(r).reponse and not ns.projetCommande(r).etat, "la 1re reste la réponse elle-même, sans état")
  ns.projetArtisan(r, "Cid", i)
  assert(ns.projetOffre(r, 700, i) and ns.projetCommande(r, i).player == "Cid" and ns.projetCommande(r, i).tip == 700,
    "sa commande de bloc se règle comme une autre")
  -- La même version rouverte : mes changements restent ; une nouvelle version de la demande : la réponse est reprise.
  assert(ns.projetReponse(recue("h1", 1)) == r and ns.projetApports(r)[3858] and ns.projetCommande(r).tip == 40000, "même version : rien ne bouge")
  C.Choix(r, 2841, "acheter")
  assert(ns.projetReponse(recue("h2", 3)) == r and r.lines[1].qty == 3 and not ns.projetApports(r)[3858] and ns.projetApports(r)[4234]
    and ns.projetCommande(r).tip == 3 * 9000 - 4 * 500, "nouvelle version : sa demande reprise, mes apports et mon prix effacés")
  assert(r.tenu == ns.FIGE and r.choix[2841] == "acheter" and C.Projet(r.id) == r, "un projet tenu de Composants, mes choix de case gardés")
  -- Un projet à moi : tout se modifie.
  local mien = C.NouveauProjet({ lines = { { id = 7963, qty = 1 } } })
  assert(C.Peut(mien, "lignes") and C.Quantite(mien, 1, 2) and C.Ajouter(mien, 3858, 1) and C.Retirer(mien, 2),
    "mon projet : lignes et quantités se changent")
end
as(BOB)
print("Handshake : règles de la réponse OK")

-- Projets : un choix de case appartient à son projet (CONTEXT.md) ; ni l'arbre ni le contrat d'un autre projet n'en
-- dépendent. Marteau = 10 bronzes + 1 perle, cuirasse = 20 bronzes ; le bronze se fond (cuivre + étain, ×2).
as(BOB)
local function tiers(prix)
  local t = {}
  for id, p in pairs(prix) do t[id] = { tiers = { { price = p, qty = 999 } } } end
  return t
end
AzerothCommuneMarket = { ["6942-Alliance"] = { scanned = "hier", items = tiers({ [2770] = 10, [2771] = 10, [5500] = 500, [2841] = 100, [5541] = 99999, [2870] = 99999 }) } }
AzerothCommuneDB.recipes = {
  [1] = { name = "Marteau", output = 5541, profession = "Forge", reagents = { { id = 2841, qty = 10 }, { id = 5500, qty = 1 } } },
  [2] = { name = "Cuirasse", output = 2870, profession = "Forge", reagents = { { id = 2841, qty = 20 } } },
  [3] = { name = "Fonte du bronze", output = 2841, made_min = 2, profession = "Minage", reagents = { { id = 2770, qty = 1 }, { id = 2771, qty = 1 } } },
}
do
  local function lignes() return { { id = 5541, qty = 1 }, { id = 2870, qty = 1 } } end
  local pa = projetPour(BELN, 8000, lignes())
  local pb = projetPour(BELN, 8000, lignes())
  ns.projetApport(pb, 5500, true)
  local function termes(p, i) -- les termes de la commande i (1 = tout le projet : ceux du projet seul, d'avant les commandes)
    local c = assert(ns.ctFromDemande(ns.projetCommande(p, i), 3))
    local function txt(l) local t = {} for _, x in ipairs(l) do t[#t + 1] = x.id .. ":" .. x.qty .. ":" .. x.unit end return table.concat(t, ",") end
    return txt(c.m) .. " / " .. txt(c.o)
  end
  local avantA, avantB = termes(pa), termes(pb)
  assert(avantB == "5500:1:500 / 2870:1:5333,5541:1:3167", avantB)
  C.Choix(pa, 2841, "acheter")
  assert(termes(pa) ~= avantA, "témoin : le choix change les prix par objet du projet A")
  assert(C.Arbre(pa, true).caseDe.I2841.made == 0, "projet A : le bronze acheté")
  assert(termes(pb) == avantB, "projet B : caution et prix par objet inchangés")
  assert(C.Arbre(pb, true).caseDe.I2841.made == 30, "projet B : le bronze toujours fondu")
  -- Commande du bloc de la forge (#6) : le bronze du minage en caution à côté de ma perle ; la part de l'artisan ne
  -- coûte plus rien, l'offre se partage par moitié.
  local i = ns.projetCommander(pb, C.Arbre(pb, true).blocDe.Forge)
  ns.projetArtisan(pb, BELN, i)
  ns.projetOffre(pb, 8000, i)
  assert(termes(pb, i) == "2841:30:100,5500:1:500 / 2870:1:6000,5541:1:5500", termes(pb, i))
  assert(termes(pb) == avantB, "la commande « tout le projet » n'a pas bougé")
end
print("Handshake : choix de case propres à chaque projet OK")

-- Les commandes d'un projet se lisent sur l'arbre de la demande (aucun stock déduit, toutes les recettes) : mes stocks
-- ne réduisent jamais la part de l'artisan (CONCEPTION.md). Avec un marteau dans mes sacs et le stock coché, ce que livre
-- le minage = le bronze que la forge reçoit en apport.
as(BOB)
local sacsAvant, optionsAvant = commune.Conteneurs, ComposantsDB.options
commune.Conteneurs = function() return { b = { items = { { id = 5541, count = 1 } } } } end
ComposantsDB.options = { bags = true, unlearned = true }
local ok, err = pcall(function()
  local p = C.NouveauProjet({ lines = { { id = 5541, qty = 2 }, { id = 2870, qty = 1 } } })
  C.Choix(p, 2841, "fabriquer")
  local blocs = C.Arbre(p, true).blocDe -- l'arbre de la fenêtre, stock déduit
  local forge, mine = ns.projetCommande(p, ns.projetCommander(p, blocs.Forge)), ns.projetCommande(p, ns.projetCommander(p, blocs.Minage))
  local livre, recu = mine.lines[1], ns.demandeApports(ns.arbreDemande(forge, forge.apports))
  assert(livre.id == 2841 and recu[1].id == 2841 and livre.qty == recu[1].qty and livre.qty == 40,
    ("le minage livre %d bronzes, la forge en reçoit %d"):format(livre.qty, recu[1].qty))
end)
commune.Conteneurs, ComposantsDB.options = sacsAvant, optionsAvant
assert(ok, err)
print("Handshake : commandes sur l'arbre de la demande OK")

-- Envoyer une commande (#7) : « Préparer la demande » en fait un brouillon de contrat, qui la suit encore ; envoyée, elle
-- devient une demande (contrat v1) : ses termes sont ceux du contrat et ne bougent plus avec le projet, son état se lit
-- dans le contrat.
as(BOB)
do
  local p = C.NouveauProjet({ lines = { { id = 5541, qty = 1 }, { id = 2870, qty = 1 } } })
  C.Choix(p, 2841, "fabriquer")
  local i = ns.projetCommander(p, C.Arbre(p, true).blocDe.Forge)
  ns.projetArtisan(p, BELN, i)
  ns.projetOffre(p, 8000, i)
  local function cmd() return ns.projetCommande(p, i) end
  local function termes(v) -- ce que la commande demande : lignes, apports, offre, artisan
    local t = {}
    for _, l in ipairs(v.lines) do t[#t + 1] = l.id .. "x" .. l.qty end
    table.sort(t)
    local a = {}
    for id in pairs(v.apports or {}) do a[#a + 1] = id end
    table.sort(a)
    return table.concat(t, ",") .. " / " .. table.concat(a, ",") .. " / " .. tostring(v.tip) .. " / " .. tostring(v.player)
  end
  assert(cmd().etat == "préparé", "pas encore de contrat")
  local ct = assert(ns.projetEnvoyer(p, i))
  assert(ct.status == "brouillon" and cmd().etat == "préparé", "brouillon : pas envoyée")
  ns.projetOffre(p, 9000, i)
  ct = assert(ns.projetEnvoyer(p, i))
  assert(ns.ctTotal(ct.o) - ns.ctTotal(ct.m) == 9000, "préparée de nouveau : le brouillon suit la commande")
  ns.ctPropose(ct)
  assert(cmd().etat == "envoyé", "envoyée : son état vient du contrat")
  assert(ns.ctKey(ct) ~= key1 and bases[BEL].contracts[ns.ctKey(ct)].hash == ct.hash, "même seconde qu'une autre demande : une autre clé, arrivée chez Belegard")
  local envoyee = termes(cmd())
  assert(envoyee == "2870x1,5541x1 / 2841 / 9000 / " .. BELN, envoyee)
  C.Choix(p, 2841, "acheter")
  ns.projetApport(p, 5500, true)
  C.Ajouter(p, 5541, 3)
  ns.projetOffre(p, 1, i)
  ns.projetArtisan(p, "Cid", i)
  assert(termes(cmd()) == envoyee, "le projet change : la demande ne bouge pas")
  assert(ns.projetEnvoyer(p, i) == ct, "une demande envoyée n'est pas refaite")
  -- Belegard contre-propose (+ 10 pa), Bob signe : la commande suit son contrat, pas le projet.
  as(BEL)
  local chez = HandshakeDB.contracts[ns.ctKey(ct)]
  ns.ctPropose(assert(ns.ctCounter(chez, nil, ns.ctTotal(chez.o) + 1000)))
  as(BOB)
  assert(cmd().etat == "contre-proposé", "contre-proposée")
  local v2 = HandshakeDB.contracts[ns.ctKey(ct)]
  assert(ns.ctAccept(v2, v2.hash))
  assert(cmd().etat == "signé" and cmd().tip == 10000, "signée, au prix de la version signée")
  -- En clair (#7) : le texte part de la commande, avec ses lignes, ses apports et son offre ; envoyée, ce sont ceux de son
  -- contrat, même si la recette a changé depuis (la cuirasse prend maintenant 25 bronzes).
  for id, nom in pairs({ [5541] = "Marteau", [2870] = "Cuirasse", [2841] = "Barre de bronze" }) do
    AzerothCommuneItems.items[id] = { name = nom, link = link(id, nom) }
  end
  AzerothCommuneDB.recipes[2].reagents[1].qty = 25
  popups = {}
  ns.whisper = function(msg) ns.onChat("CHAT_MSG_WHISPER", msg, BOBN) end
  ns.sendOrder(cmd())
  ns.whisper = realWhisper
  AzerothCommuneDB.recipes[2].reagents[1].qty = 20
  local voulu, _, offre, apporte = ns.parseList(popups[1].data.text)
  table.sort(voulu, function(a, b) return a.id < b.id end)
  assert(#voulu == 2 and voulu[1].id == 2870 and voulu[1].qty == 1 and voulu[2].id == 5541 and voulu[2].qty == 1, "ses lignes")
  assert(#apporte == 1 and apporte[1].id == 2841 and apporte[1].qty == 30 and offre == 10000, "ses apports (du contrat), son offre")
  -- Le bloc de la forge commandé de nouveau : sa commande est figée, une nouvelle commande vivante (son identité à elle) ;
  -- commandé encore une fois : la même, tant qu'elle n'est pas partie.
  local j = ns.projetCommander(p, C.Arbre(p, true).blocDe.Forge)
  assert(j ~= i and not ns.projetCommande(p, j).fige and ns.projetCommande(p, j).etat == "préparé", "une nouvelle commande de la forge")
  assert(ns.projetCommande(p, j).id ~= cmd().id, "chaque commande a son identité")
  assert(ns.projetCommander(p, C.Arbre(p, true).blocDe.Forge) == j, "la commande vivante est reprise")
  assert(termes(cmd()) ~= termes(ns.projetCommande(p, j)), "la nouvelle suit le projet, l'envoyée non")
  -- Supprimer le projet dans Composants (#37, #39) : sa commande signée reste dans Contrats, jamais effacée ; celle qui
  -- n'est pas partie disparaît avec lui (le signal « ce projet a changé »).
  local signee = ns.ctKey(ct)
  assert(C.Supprimer(p.id) == p and not C.Projet(p.id), "le projet est supprimé")
  assert(HandshakeDB.contracts[signee] and ns.ctStatus(HandshakeDB.contracts[signee]) == "signe", "la commande signée reste dans Contrats")
  assert(HandshakeDB.commandes[p.id] == nil, "ses commandes pas encore parties disparaissent")
end
print("Handshake : envoyer une commande (demande figée, état lu dans le contrat) OK")

-- Commander un bloc (Composants#26) crée tout de suite un contrat préparé, numéroté (le numéro ne voyage pas) ; le bloc est
-- confié (l'emplacement du bloc de Composants le réduit à une case) tant que son contrat vit ; « Vérifier et envoyer… »
-- n'en fait que le brouillon de la v1, ouvert sur sa fiche dans Contrats, d'où il part (ns.ctPropose : « Envoyer la
-- proposition ») ; refusé, retiré ou échu, le bloc revient, sans ses apports. Abandonner un contrat préparé efface son
-- brouillon et ses apports. Supprimer le projet efface ses contrats préparés (et leurs brouillons), jamais un contrat parti.
as(BOB)
do
  assert(cns.fournisseur == ns.emplacement, "Handshake branché sur l'emplacement du bloc de Composants")
  local p = C.NouveauProjet({ lines = { { id = 5541, qty = 1 }, { id = 2870, qty = 1 } } })
  C.Choix(p, 2841, "fabriquer")
  local E = ns.emplacement
  local blocs = C.Arbre(p, true).blocDe
  assert(not E.confie(p, blocs.Forge) and not E.confie(p, nil) and E.apports(p) == nil and E.aDonner(p) == nil, "rien de commandé")
  assert(HandshakeDB.commandes[p.id] == nil, "lire un projet n'y range rien")
  local avant = HandshakeDB.numero or 0
  local f = ns.projetCommander(p, C.Arbre(p, true).blocDe.Forge)
  local m = ns.projetCommander(p, C.Arbre(p, true).blocDe.Minage)
  local cf, cm = HandshakeDB.commandes[p.id].liste[f], HandshakeDB.commandes[p.id].liste[m]
  assert(cf.n == avant + 1 and cm.n == avant + 2, "chaque contrat préparé a son numéro, tout de suite")
  assert(ns.projetCommander(p, C.Arbre(p, true).blocDe.Forge) == f and cf.n == avant + 1, "le même bloc : le même contrat, le même numéro")
  assert(E.confie(p, blocs.Forge) and E.confie(p, blocs.Minage) and not E.confie(p, nil), "les deux blocs confiés, pas le projet entier")
  assert(ns.projetCommande(p, f).etat == "préparé" and not HandshakeDB.contracts[cf.contrat or ""], "préparé : rien dans Contrats")
  ns.projetApport(p, 5500, true)
  assert(E.apports(p) == nil and E.aDonner(p)[5500], "mes apports : à donner (des Besoins), pas hors de mon arbre")
  -- Vérifier et envoyer… : sans artisan connu, pas de brouillon (la raison est dite) ; avec, le brouillon de la v1, rien
  -- sur le fil ; il part de sa fiche (« Envoyer la proposition »).
  ns.projetArtisan(p, "Cid", f)
  local rien, pourquoi = ns.projetEnvoyer(p, f)
  assert(not rien and pourquoi, "artisan inconnu : pas de brouillon")
  ns.projetArtisan(p, BELN, f)
  local ct = assert(ns.projetEnvoyer(p, f))
  assert(ct.status == "brouillon" and not bases[BEL].contracts[ns.ctKey(ct)], "un brouillon, rien sur le fil")
  assert(ns.ctPropose(ct) and ct.status == "envoye" and ct.v == "1" and bases[BEL].contracts[ns.ctKey(ct)], "parti de sa fiche, arrivé chez Belegard")
  assert(ns.projetEnvoyer(p, f) == ct, "parti : pas refait")
  -- Aucun autre chemin ne fait partir un contrat en sautant sa fiche, ni la v1 ni une nouvelle version (contre-proposition,
  -- réponse de l'artisan : des brouillons, Contrat.lua newVersion) : l'envoi ne s'appelle que de la fenêtre Contrats
  -- (« Envoyer la proposition », lié au contrat affiché) et du module des contrats ; tout autre fichier du TOC, présent ou
  -- à venir, n'y touche pas.
  for fichier in HSTOC:gmatch("([%w_]+%.lua)") do
    if fichier ~= "Contrat.lua" and fichier ~= "ContratUI.lua" then
      local code = io.open("Handshake/" .. fichier):read("*a"):gsub("%-%-[^\n]*", "")
      assert(not code:find("ctPropose", 1, true) and not code:find("ctSendRaw", 1, true), fichier .. " envoie un contrat sans sa fiche")
    end
  end
  -- Le minage : préparé (j'apporte le cuivre), son brouillon dans Contrats, puis abandonné : le brouillon s'efface, le bloc
  -- revient sans son apport ; la perle de la forge, toujours commandée, reste apportée.
  ns.projetApport(p, 2770, true)
  assert(E.aDonner(p)[2770] and E.aDonner(p)[5500], "le cuivre du minage, la perle de la forge")
  ns.projetArtisan(p, BELN, m)
  local bm = assert(ns.projetEnvoyer(p, m))
  assert(HandshakeDB.contracts[ns.ctKey(bm)].status == "brouillon", "un brouillon dans Contrats")
  assert(ns.abandonner(p, m) and not HandshakeDB.contracts[ns.ctKey(bm)], "abandonné : son brouillon effacé")
  assert(not E.confie(p, blocs.Minage) and E.confie(p, blocs.Forge), "le minage revient, la forge reste confiée")
  assert(not ns.projetApports(p)[2770] and ns.projetApports(p)[5500], "le bloc rendu n'a plus d'apports ; la forge garde les siens")
  -- Belegard refuse la forge : le bloc revient ; commandé de nouveau, un autre contrat, un autre numéro.
  as(BEL)
  ns.ctRefuse(HandshakeDB.contracts[ns.ctKey(ct)])
  as(BOB)
  assert(not E.confie(p, blocs.Forge), "refusé : le bloc revient")
  assert(E.apports(p) == nil and ns.projetApports(p) == nil, "refusé : plus d'apports, ses cases reviennent dans l'arbre")
  local f2 = ns.projetCommander(p, C.Arbre(p, true).blocDe.Forge)
  assert(f2 ~= f and HandshakeDB.commandes[p.id].liste[f2].n > cm.n and E.confie(p, blocs.Forge), "de nouveau : un autre contrat")
  -- Supprimer le projet : le préparé (et son brouillon) s'efface, le contrat parti (refusé) reste.
  ns.projetArtisan(p, BELN, f2)
  local b2 = assert(ns.projetEnvoyer(p, f2))
  C.Supprimer(p.id)
  assert(HandshakeDB.commandes[p.id] == nil and not HandshakeDB.contracts[ns.ctKey(b2)], "ses contrats préparés effacés")
  assert(HandshakeDB.contracts[ns.ctKey(ct)], "le contrat parti reste dans Contrats")
  -- Le projet entier commandé : sa 1re place prend un numéro ; tout l'arbre est confié.
  local q = C.NouveauProjet({ lines = { { id = 5541, qty = 1 } } })
  assert(ns.projetCommander(q, {}) == 1 and HandshakeDB.commandes[q.id].liste[1].n and E.confie(q, nil), "tout le projet, confié")
  assert(ns.abandonner(q, 1) and not E.confie(q, nil) and #HandshakeDB.commandes[q.id].liste == 1, "abandonné : la place reste, pas commandée")
  C.Supprimer(q.id)
end
print("Handshake : commander un bloc crée un contrat préparé (numéro, envoyer, abandonner, supprimer) OK")

-- Les contrats dans les Besoins (Composants#27). clos = tous les contrats vivants du projet livrés : tout dans les sacs
-- mais un contrat ouvert, on reste en Réunir ; livré, Fabriquer. Un bloc confié sort des Besoins, mes apports y restent
-- (à donner). Lancer marche avec un contrat pas signé. Abandonner selon l'état, sans jamais forger d'état chez l'autre :
-- envoyé → retiré (message X, le geste « Retirer »), contre-proposé par lui → refusé (message R), signé → lâché par le
-- projet seulement (rien n'est envoyé, le contrat reste signé des deux côtés) ; le bloc revient.
as(BOB)
do
  local E = ns.emplacement
  local TOUT = { unlearned = true }
  local conteneurs = AzerothCommune.Conteneurs
  AzerothCommune.Conteneurs = function() return {} end -- des sacs vides (les Besoins comptent toujours les sacs)
  local function lignes(p)
    local t = {}
    for _, r in ipairs((cns.orderNeeds(cns.besoinsArbre(p, TOUT)))) do t[r.id] = r end
    return t
  end
  local p = C.NouveauProjet({ lines = { { id = 5541, qty = 1 }, { id = 2870, qty = 1 } } })
  C.Choix(p, 2841, "fabriquer")
  assert(E.clos(p) and lignes(p)[5500], "aucun contrat : clos ; la perle à réunir")
  local f = ns.projetCommander(p, C.Arbre(p, true).blocDe.Forge)
  assert(not E.clos(p), "un contrat préparé : pas clos")
  assert(not lignes(p)[5500] and lignes(p)[2770], "la forge confiée : sa perle sort des Besoins, le minage reste")
  ns.projetApport(p, 5500, true)
  assert(lignes(p)[5500] and lignes(p)[5500].required == 1, "la perle apportée : une ligne des Besoins")
  assert(cns.lancer(p) == p and C.Projet(p.id).phase == "reunir", "Lancer avec un contrat pas signé")
  -- Le projet entier commandé, rien à apporter : rien à réunir ; il ne passe en Fabriquer qu'à la livraison.
  local q = C.NouveauProjet({ lines = { { id = 5541, qty = 1 } } })
  ns.projetCommander(q, {})
  ns.projetArtisan(q, BELN, 1)
  local ct = assert(ns.ctPropose(assert(ns.projetEnvoyer(q, 1)))) -- (« Envoyer la proposition », sur sa fiche)
  assert(next(lignes(q)) == nil, "tout confié : rien à réunir")
  cns.lancer(q)
  assert(not cns.avancerPhase(q) and q.phase == "reunir", "tout est là mais le contrat est ouvert : Réunir")
  ct.status = "clos" -- (comme après le dernier échange vérifié)
  assert(E.clos(q) and cns.avancerPhase(q) and q.phase == "fabriquer", "livré : Fabriquer")
  assert(E.confie(q, nil), "livré : le bloc reste celui du contrat")
  assert(not ns.abandonner(q, 1), "livré : rien à abandonner")
  C.Supprimer(q.id)
  -- Abandonner, selon l'état. Préparé : effacé (Commander un bloc, plus haut).
  local function forge()
    local i = ns.projetCommander(p, C.Arbre(p, true).blocDe.Forge)
    ns.projetArtisan(p, BELN, i)
    local k = ns.ctKey(assert(ns.ctPropose(assert(ns.projetEnvoyer(p, i))))) -- (de sa fiche)
    return i, k
  end
  assert(ns.abandonner(p, f) == "efface" and not E.confie(p, C.Arbre(p, true).blocDe.Forge), "préparé : effacé")
  -- Envoyé : retiré ; Belegard le voit retiré (le message de retrait, le même que « Retirer » dans Contrats).
  local i, k = forge()
  assert(ns.abandonner(p, i) == "retire", "envoyé : retiré")
  assert(HandshakeDB.contracts[k].status == "retire" and bases[BEL].contracts[k].status == "retire", "retiré des deux côtés")
  assert(not E.confie(p, C.Arbre(p, true).blocDe.Forge) and lignes(p)[2870] == nil and lignes(p)[5500], "le bloc revient")
  -- Contre-proposé par Belegard (à signer, c'est à moi) : refusé, des deux côtés.
  i, k = forge()
  as(BEL); ns.ctPropose(assert(ns.ctCounter(bases[BEL].contracts[k], nil, ns.ctTotal(bases[BEL].contracts[k].o) + 1000))); as(BOB)
  assert(HandshakeDB.contracts[k].status == "a_signer", "sa contre-proposition")
  assert(ns.abandonner(p, i) == "refuse" and bases[BEL].contracts[k].status == "refuse", "à signer : refusé, des deux côtés")
  -- Signé : le projet le lâche ; rien ne part, le contrat reste signé des deux côtés (son registre, son échéance).
  i, k = forge()
  as(BEL); assert(ns.ctAccept(bases[BEL].contracts[k], bases[BEL].contracts[k].hash)); as(BOB)
  assert(HandshakeDB.contracts[k].status == "signe", "signé")
  local fil = #wire
  assert(ns.abandonner(p, i) == "lache", "signé : lâché")
  assert(#wire == fil, "rien n'est envoyé")
  assert(HandshakeDB.contracts[k].status == "signe" and bases[BEL].contracts[k].status == "signe", "toujours signé des deux côtés")
  assert(not E.confie(p, C.Arbre(p, true).blocDe.Forge) and E.clos(p), "le bloc revient ; plus de contrat vivant : clos")
  assert(not ns.abandonner(p, i), "lâché : plus rien à abandonner")
  C.Supprimer(p.id)
  assert(HandshakeDB.contracts[k].status == "signe", "le projet supprimé : le contrat signé reste")
  AzerothCommune.Conteneurs = conteneurs
end
print("Handshake : les contrats dans les Besoins (clos, apports à donner, Abandonner selon l'état) OK")

-- Écart et nouvelle version (#8) : une commande envoyée ne bouge jamais d'elle-même ; quand la part du projet qu'elle vise
-- change, l'écart est signalé (pas quand le changement est ailleurs) ; « Nouvelle version » la renvoie en contre-
-- proposition, dont le différentiel est l'écart. Refusée, retirée ou échue, elle se commande de nouveau.
-- L'écart est constaté, jamais expliqué (#18) : un libellé neutre, et l'écart de prix chiffré contre mon scan.
as(BOB)
C_CurrencyInfo = { GetCoinTextureString = function(c) return c .. "pc" end }
AzerothCommuneMarket = { ["6942-Alliance"] = { scanned = "hier", items = { [2841] = { tiers = { { price = 100, qty = 999 } } } } } }
do
  local p = C.NouveauProjet({ lines = { { id = 5541, qty = 1 }, { id = 2870, qty = 1 } } })
  C.Choix(p, 2841, "fabriquer")
  local blocs = C.Arbre(p, true).blocDe
  local f, m = ns.projetCommander(p, blocs.Forge), ns.projetCommander(p, blocs.Minage)
  local function cmd(i) return ns.projetCommande(p, i) end
  local function envoyer(i)
    ns.projetArtisan(p, BELN, i)
    return assert(ns.projetEnvoyer(p, i))
  end
  local cf = envoyer(f)
  assert(not cmd(f).ecart, "brouillon tout juste préparé : pas d'écart")
  ns.projetOffre(p, 5000, f)
  assert(cmd(f).ecart == "brouillon à refaire", "l'offre change après « Préparer la demande » : le brouillon est à refaire")
  cf = envoyer(f)
  assert(not cmd(f).ecart, "préparé de nouveau : il suit le projet")
  assert(ns.ctPropose(cf))
  local cm = envoyer(m)
  assert(ns.ctPropose(cm))
  assert(not cmd(f).ecart and not cmd(m).ecart, "envoyées, projet inchangé : pas d'écart")
  -- Écart de prix (#18) : la caution du contrat contre MON estimation actuelle, celle de la fiche (P8). Le marché bouge,
  -- le pourcentage suit, sans que le projet change ; un composant sans prix connu : pas de pourcentage.
  local barres = AzerothCommuneMarket["6942-Alliance"].items[2841]
  assert(cmd(f).ecartPrix == 0 and not cmd(f).alertePrix and not cmd(f).incomplet, "caution = mon estimation : 0 %")
  barres.tiers[1].price = 150
  assert(math.floor(cmd(f).ecartPrix + 0.5) == -33 and cmd(f).alertePrix, "le marché monte : caution trop basse pour moi, en rouge")
  assert(not cmd(f).ecart, "le prix n'est pas un écart de contenu")
  assert(ns.ctDescribe(cf, BOB):find(("caution |cffe64d4d%+.0f %%|r"):format(cmd(f).ecartPrix), 1, true), "le même chiffre que la fiche")
  barres.tiers[1].price = 105
  assert(math.floor(cmd(f).ecartPrix + 0.5) == -5 and not cmd(f).alertePrix, "sous le seuil de 10 % : pas d'alerte")
  AzerothCommuneMarket["6942-Alliance"].items[2841] = nil
  assert(cmd(f).incomplet and cmd(f).ecartPrix == nil, "sans prix connu : estimation incomplète, pas de pourcentage")
  assert(ns.ctDescribe(cf, BOB):find("1 composant(s) sans prix connu", 1, true), "la fiche le dit aussi")
  AzerothCommuneMarket["6942-Alliance"].items[2841] = barres
  barres.tiers[1].price = 100
  assert(cmd(m).ecartPrix == nil and not cmd(m).incomplet, "rien d'apporté : pas de caution à estimer")
  -- Ma perle (apport) sous les cases de la forge : la part de la forge change, pas celle du minage.
  ns.projetApport(p, 5500, true)
  assert(cmd(f).ecart == "ne correspond plus au contrat", "apport dans la forge : écart signalé, sans cause")
  assert(not cmd(m).ecart, "changement ailleurs : rien pour le minage")
  -- Aucune version ne part d'elle-même : le projet a beau changer et la page se redessiner, Belegard a toujours la v1.
  ns.projetCommandes(p)
  local chez = bases[BEL].contracts
  assert(chez[ns.ctKey(cf)].v == "1" and chez[ns.ctKey(cm)].v == "1" and cf.v == "1", "rien ne part sans clic")
  assert(not ns.projetNouvelleVersion(p, m), "pas d'écart, pas de nouvelle version")
  -- « Nouvelle version » (#19) : la v2 en brouillon, à côté de la v1, relue avec le différentiel avant l'envoi ; rien n'est
  -- parti. Préparée de nouveau, elle est refaite. Elle part de Contrats (« Envoyer la proposition ») et remplace la v1.
  local brouillon = assert(ns.projetNouvelleVersion(p, f))
  assert(brouillon.status == "brouillon" and brouillon.v == "2" and ns.ctKey(brouillon) ~= ns.ctKey(cf)
    and HandshakeDB.contracts[ns.ctKey(brouillon)] == brouillon and HandshakeDB.contracts[ns.ctKey(cf)] == cf, "brouillon à côté de la v1")
  assert(chez[ns.ctKey(cf)].v == "1" and cmd(f).etat == "envoyé" and cmd(f).ecart, "rien n'est parti, l'écart reste")
  local apercu = ns.ctDescribe(brouillon, BOB)
  assert(apercu:find("BROUILLON") and apercu:find("Changé depuis la v1") and apercu:find("absent %-> 1"), "le différentiel avant l'envoi")
  local v2 = assert(ns.projetNouvelleVersion(p, f))
  assert(v2 ~= brouillon and HandshakeDB.contracts[ns.ctKey(v2)] == v2, "préparée de nouveau : refaite")
  local cle = ns.ctKey(v2)
  assert(ns.ctPropose(v2))
  assert(HandshakeDB.contracts[ns.ctKey(cf)] == v2 and not HandshakeDB.contracts[cle], "envoyée : elle remplace la v1, plus de brouillon")
  as(BEL)
  local recu = HandshakeDB.contracts[ns.ctKey(cf)]
  assert(recu.v == "2" and recu.status == "a_signer" and recu.prev.v == "1" and recu.hash == v2.hash, "contre-proposition reçue")
  local function qtes(list) local t = {} for _, l in ipairs(list) do t[#t + 1] = l.id .. "x" .. l.qty end return table.concat(t, ",") end
  assert(qtes(recu.prev.o) == qtes(recu.o) and qtes(recu.o) == "2870x1,5541x1", "ce qu'il livre : inchangé")
  assert(qtes(recu.prev.m) == "2841x30" and qtes(recu.m) == "2841x30,5500x1", "ses apports : la perle (du marteau) en plus")
  assert(recu.m[1].unit == recu.prev.m[1].unit, "la caution déjà au contrat reste")
  local offre = function(c) return ns.ctTotal(c.o) - ns.ctTotal(c.m) end
  assert(math.abs(offre(recu) - offre(recu.prev)) <= 1, "l'offre reste celle du contrat (à l'arrondi près)")
  local diff = ns.ctDescribe(recu, BEL)
  assert(diff:find("Changé depuis la v1") and diff:find("absent %-> 1"), "le différentiel montre la perle ajoutée")
  as(BOB)
  assert(not cmd(f).ecart and cmd(f).etat == "contre-proposé", "nouvelle version partie : plus d'écart")
  -- Sa contre-proposition qui ne change que le prix : rien à signaler (la part du projet n'a pas bougé).
  as(BEL)
  ns.ctPropose(assert(ns.ctCounter(recu, nil, ns.ctTotal(recu.o) + 1000)))
  as(BOB)
  assert(cmd(f).etat == "contre-proposé" and not cmd(f).ecart, "il change son prix : pas d'écart")
  -- Une quantité qui change : le minage (plus de bronze) et la forge (plus de cuirasses).
  C.Quantite(p, 2, 2)
  assert(cmd(m).ecart == "ne correspond plus au contrat" and cmd(f).ecart == cmd(m).ecart, "quantité : les deux, même libellé")
  -- Belegard refuse le minage : figé, pas de nouvelle version, mais il se commande de nouveau (une commande vivante,
  -- reprise tant qu'elle n'est pas partie).
  as(BEL)
  ns.ctRefuse(HandshakeDB.contracts[ns.ctKey(cm)])
  as(BOB)
  assert(cmd(m).etat == "refusé" and not cmd(m).ecart and cmd(m).recommander, "refusée : à commander de nouveau")
  local _, err = ns.projetNouvelleVersion(p, m)
  assert(err, "refusée : pas de nouvelle version")
  local m2 = ns.projetRecommander(p, m)
  assert(m2 and m2 ~= m and not cmd(m2).fige and cmd(m2).part == "Minage" and cmd(m2).player == BELN, "une nouvelle commande du minage")
  assert(ns.projetRecommander(p, m) == m2, "la commande vivante est reprise")
  assert(not ns.projetRecommander(p, f), "en cours : pas à recommander")
  -- Tout le projet, retiré : il se commande de nouveau aussi.
  local t = envoyer(1)
  assert(ns.ctPropose(t))
  ns.ctWithdraw(t)
  assert(cmd(1).etat == "retiré" and cmd(1).recommander)
  local t2 = ns.projetRecommander(p, 1)
  assert(t2 and t2 ~= 1 and cmd(t2).part == "tout le projet" and not cmd(t2).fige and #cmd(t2).lines == 2, "tout le projet, de nouveau")
  -- Ce qui part reste dans les bornes que vérifie celui qui reçoit (n° 15) : 1001 cuirasses ne partent pas.
  C.Quantite(p, 2, 1001)
  local _, trop = ns.projetNouvelleVersion(p, f)
  assert(trop and trop:find("bornes"), "hors bornes : rien n'est envoyé")
  assert(bases[BEL].contracts[ns.ctKey(cf)].v == "3", "Belegard a toujours la v3 (son prix)")
  -- Un brouillon de nouvelle version dépassé (il contre-propose entre-temps) : périmé, il ne part pas, il est effacé.
  C.Quantite(p, 2, 2)
  local b = assert(ns.projetNouvelleVersion(p, f))
  assert(b.v == "4" and b.prev.v == "3", "brouillon de la v4")
  as(BEL)
  local v3 = HandshakeDB.contracts[ns.ctKey(cf)]
  assert(ns.ctPropose(assert(ns.ctCounter(v3, nil, ns.ctTotal(v3.o) + 500))))
  as(BOB)
  local _, perime = ns.ctPropose(b)
  assert(perime and perime:find("a changé") and not HandshakeDB.contracts[ns.ctKey(b)], "périmé : effacé, pas envoyé")
  assert(HandshakeDB.contracts[ns.ctKey(cf)].author == BEL and bases[BEL].contracts[ns.ctKey(cf)].v == "4", "sa v4 reste")
end
print("Handshake : écart et nouvelle version d'une commande envoyée OK")

-- Fiche du contrat : besoins gonflés signalés (n° 12), perte maximale de chaque côté (P8).
C_CurrencyInfo = { GetCoinTextureString = function(c) return c .. "pc" end }
UnitFactionGroup = function() return "Alliance" end
AzerothCommuneMarket = { ["6942-Alliance"] = { scanned = "hier", items = { [3858] = { tiers = { { price = 200, qty = 999 } } } } } }
AzerothCommuneDB.recipes = { [1] = { name = "Claymore", output = 7963, reagents = { { id = 3858, qty = 30 } } } }
as(BOB)
local fiche = ns.ctDescribe(signed, BOB)
assert(fiche:find("36 demandés, la recette en consomme 30"), "minerai gonflé signalé")
assert(fiche:find("Si l'artisan disparaît après l'étape 1 : tu perds au plus 1188pc"), "perte max du client : 36×200 − 6012")
as(BEL)
assert(ns.ctDescribe(bases[BEL].contracts[k], BEL):find("tu es l'ARTISAN"), "rôle affiché depuis mon côté")
print("Handshake : fiche du contrat OK")

-- Noms à la Forever (LibCommune#35, Handshake#29) : « Prénom Nom », la forme du serveur, pour afficher et chuchoter ;
-- un personnage s'identifie par son GUID. Plus d'adresse « Prénom-Royaume » : lib.Adresse est retirée du socle.
assert(ns.fullName == commune.Destinataire and ns.whisperTarget == commune.Destinataire, "noms : ceux du socle, plus de copie")
assert(commune.Adresse == nil, "lib.Adresse retirée (plus d'appelant)")
assert(ns.fullName("Belegard Marteaudefer-CAMWOWEU4Realm8PvP") == BELN, "un « -Royaume » retiré")
UnitName = function() return "Belegard", "Marteaudefer" end
as(BEL)
assert(ns.me() == GBEL and ns.myName() == BELN, "moi : mon GUID ; mon nom : prénom et nom de famille")
print("Handshake : noms à la Forever OK")

-- Relevés d'un Handshake d'avant purgés, catalogue des objets pas encore relevé (noms demandés au serveur) ; jamais rien de
-- relevé dans HandshakeDB. Relevés sauvegardés par un Handshake d'avant : purgés (ADR 0002), données propres gardées.
HandshakeDB.recipes = { [1] = { name = "vieux relevé" } }
HandshakeDB.chars = { ["Vieux-Perso"] = { recipes = { Forge = { known = { [1] = 1 } } }, bags = { [2770] = 3 } } }
HandshakeDB.items, HandshakeDB.market = { [2770] = { name = "Minerai" } }, { ["6942-Alliance"] = { items = {} } }
ns.purgerAnciensReleves()
aucunReleve("purge")
assert(HandshakeDB.contracts, "données propres gardées")
AzerothCommuneDB.recipes, AzerothCommuneItems.items, AzerothCommuneMarket = {}, {}, {}
assert(not ns.recipes()[5], "rien de relevé")
-- Minage relevé par le socle (fenêtre de métier) ; le catalogue des objets, lui, pas encore.
AzerothCommuneDB.recipes = {
  [5] = { name = "Fonte du cuivre", profession = "Minage", output = 2840, reagents = { { id = 2770, qty = 1 } } },
  [6] = { name = "Fonte du bronze", profession = "Minage", output = 2841, reagents = { { id = 2840, qty = 1 } } } }
-- Les noms des produits et composants des recettes relevées sont demandés au serveur ; arrivés, gardés en mémoire.
local demandes = {}
C_Item.RequestLoadItemDataByID = function(id) demandes[id] = true end
ns.recipes()
assert(demandes[2840] and demandes[2770] and demandes[2841], "noms des produits et composants demandés au serveur")
C_Item.RequestLoadItemDataByID = nil
C_Item.GetItemInfo = function(id) if id == 2840 then return "Barre de cuivre", "|Hitem:2840|h[Barre de cuivre]|h" end end
ns.rememberItem(2840)
C_Item.GetItemInfo = noop
assert(ns.recipes()[5] and ns.findItem("barre de cuivre") == 2840 and ns.findItem("Fonte du cuivre") == 2840, "noms en mémoire")
aucunReleve("noms demandés")
-- Base des recettes du socle (Handshake#36, AzerothCommune#48) : Handshake y souscrit et la lit par Lire. La réserve
-- Classic est celle du socle (privée : acns.recettesReserve), ajoutée pour les objets sans recette vue, jamais par-dessus
-- une recette vue du même objet.
assert(AzerothCommuneDB.souscriptions["base des recettes"], "Handshake souscrit à la base des recettes")
acns.recettesReserve = { [9001] = { 2840, 1, 1, "Minage", "Barre de cuivre (Classic)", { 2770, 2 }, 1 },
  [9002] = { 4255, 1, 1, "Travail du cuir", "Armure verte en cuir", { 4234, 9 }, 175 },
  [5] = { 2840, 1, 1, "Minage", "Fonte du cuivre", { 2770, 1 }, 25 } }
local merged = ns.recipes()
assert(merged[5] and not merged[9001], "barre de cuivre déjà vue : la recette Classic ne la double pas")
assert(merged[9002] and merged[9002].output == 4255 and merged[9002].reagents[1].qty == 9, "armure verte en cuir : recette Classic")
-- Handshake ne livre plus de réserve et ne remet plus rien au socle (Handshake#36).
local hstoc = io.open("Handshake/Handshake.toc"):read("*a")
assert(not hstoc:find("RecettesReserve", 1, true), "plus de réserve dans la TOC de Handshake")
for f in hstoc:gmatch("([%w_]+)%.lua") do
  local code = io.open("Handshake/" .. f .. ".lua"):read("*a"):gsub("%-%-[^\n]*", "")
  for _, m in ipairs({ "HandshakeClassicRecipes", "RemettreRecettes" }) do assert(not code:find(m, 1, true), f .. ".lua : " .. m) end
end
-- Handshake n'a plus d'arbre à lui (Handshake#39) : ni projets, ni calcul, ni Besoins ; il ne lit que l'API de Composants.
for _, f in ipairs({ "Calcul", "Projet", "Fenetre", "Besoins" }) do
  assert(not hstoc:find(f .. ".lua", 1, true) and not io.open("Handshake/" .. f .. ".lua"), "plus de " .. f .. ".lua")
end
for f in hstoc:gmatch("([%w_]+)%.lua") do
  local code = io.open("Handshake/" .. f .. ".lua"):read("*a"):gsub("%-%-[^\n]*", "")
  for _, m in ipairs({ "ComposantsDB", "ComposantsFrame", "craftPlan", "projetArbre", "dessinArbre", "HandleModifiedItemClick" }) do
    assert(not code:find(m, 1, true), f .. ".lua : " .. m)
  end
end
for _, k in ipairs({ "nouveauProjet", "projetArbre", "projetDemande", "craftPlan", "crafters", "orderNeeds", "openCraftWindow", "demoOrder", "sendNeeds" }) do
  assert(ns[k] == nil, "ns." .. k .. " : parti dans Composants")
end
-- (Les recettes connues sont de nouveau lues, pour les Demandes lues (#52) : ce que mes persos savent fabriquer.)
for _, t in ipairs({ "inventaires", "métiers et compétences" }) do
  assert(not io.open("Handshake/Donnees.lua"):read("*a"):find('"' .. t .. '"', 1, true), "Handshake ne souscrit plus à " .. t)
end
print("Handshake : purge, noms demandés, réserve des recettes OK")


-- Identité affichée : « Prénom Nom — GUID », plus de royaume (Handshake#29) ; le nom vient du serveur, codes échappés.
UnitExists, UnitIsPlayer = function() return true end, function() return true end
UnitGUID = function(u) return u == "target" and GBOB or GBEL end
UnitName = function(u) if u == "target" then return "Bob", "Kerys|cffBois" end return "Belegard", "Marteaudefer" end
ns.learnUnit("target")
assert(ns.knownGUID["Bob Kerys|cffBois"] == GBOB, "cible : nom complet et GUID appris")
assert(ns.identity("Bob Kerys|cffBois", GBOB) == "Bob Kerys||cffBois — " .. GBOB, "codes échappés")
assert(ns.myIdentity() == "Belegard Marteaudefer — " .. GBEL)
assert(ns.identity("Carl", nil) == "Carl — GUID inconnu")
print("Handshake : identité complète OK")

-- Royaume, faction et maison de l'HV par le socle, qui les sonde (Handshake#27) : plus d'appel direct dans le code chargé ;
-- le diagnostic /handshake noms est remplacé par les sondes d'identité du socle.
local lib27 = AzerothCommune
assert(not ns.myIdentity():find(" — " .. lib27.Royaume() .. " — ", 1, true), "plus de royaume dans l'identité")
for f in io.open("Handshake/Handshake.toc"):read("*a"):gmatch("([%w_]+%.lua)") do
  local code = io.open("Handshake/" .. f):read("*a")
  for _, appel in ipairs({ "GetRealmName", "GetNormalizedRealmName", "UnitFactionGroup", "UnitFullName", "namesDiagnostic",
    "lib.Adresse", "RoyaumeNormalise", "clientGUID", "surnames[" }) do
    assert(not code:find(appel, 1, true), f .. " : " .. appel)
  end
end
for _, f in ipairs({ "LISEZ-MOI.txt", "SECURITE.md" }) do
  assert(not io.open("Handshake/" .. f):read("*a"):find("handshake noms", 1, true), f .. " cite encore /handshake noms")
end
print("Handshake : royaume et faction par la lib OK")

-- Destinataire d'un chuchotement : « Prénom Nom », la forme que le serveur accepte (au prénom seul : « Aucun joueur
-- nommé 'Belegard' », 21/11/2026, LibCommune#35).
assert(ns.whisperTarget("Belegard Marteaudefer") == "Belegard Marteaudefer")
print("Handshake : destinataire des chuchotements OK")

-- Plus d'API publique (Composants#26) : le global Handshake reste, vide ; c'est Handshake qui se branche sur Composants
-- (l'emplacement du bloc), Composants ne connaît pas Handshake.
do
  assert(type(Handshake) == "table" and next(Handshake) == nil, "le global, vide")
  assert(HSTOC:find("\n## OptionalDeps: TradeBoard, Composants\n", 1, true) and HSTOC:find("\n## Dependencies: AzerothCommune\n", 1, true),
    "le socle requis ; Trade Board et Composants en option : Handshake se branche sur Composants, pas l'inverse")
end
print("Handshake : API publique OK")

-- Remplir ma part : jamais plus que dû ; une pile trop grosse est coupée (une case d'échange prend la pile entière).
do
  local function piles(counts, left)
    local st = {}
    for i, n in ipairs(counts) do st[i] = { count = n } end
    local whole, cut, rest = ns.pilesAPoser(st, left)
    local w = {}
    for _, p in ipairs(whole) do w[#w + 1] = p.count end
    return table.concat(w, ","), cut and cut.count, rest
  end
  local w, cut, rest = piles({ 3 }, 2)
  assert(w == "" and cut == 3 and rest == 2, "une pile de 3 pour 2 : coupée, pas posée entière")
  w, cut, rest = piles({ 1, 2, 5 }, 3)
  assert(w == "2,1" and not cut and rest == 0, "piles entières au compte exact : " .. w)
  w, cut, rest = piles({ 3, 2 }, 4)
  assert(w == "3" and cut == 2 and rest == 1, "3 posée, la plus petite pile assez grosse est coupée")
  w, cut, rest = piles({ 1 }, 3)
  assert(w == "1" and not cut and rest == 2, "pas assez dans les sacs : ce qui manque")
end
print("Handshake : remplir ma part OK")

-- Avec Composants : /handshake <objet> ou /handshake demo … lui sont transmis (l'arbre est chez lui).
do
  local avant, recu = SlashCmdList.COMPOSANTS, nil
  SlashCmdList.COMPOSANTS = function(a) recu = a end
  SlashCmdList.HANDSHAKE("demo ceinture")
  SlashCmdList.COMPOSANTS = avant
  assert(recu == "demo ceinture", "avec Composants, /handshake <texte> : transmis à /composants")
end

-- Sans Composants (Handshake seul) : la commande à la main sert, rien n'échoue. /handshake ouvre la commande à la main,
-- une liste reçue s'importe en commande à la main, les commandes d'un projet ne sont jamais demandées.
do
  local C0, ouverte = Composants, nil
  Composants = nil
  local avant = ns.openCommandeMain
  ns.openCommandeMain = function(c) ouverte = c or true end
  SlashCmdList.HANDSHAKE("")
  assert(ouverte == true, "/handshake : la commande à la main")
  ouverte = nil
  SlashCmdList.HANDSHAKE("demo ceinture")
  assert(ouverte == true, "sans Composants, /handshake <texte> : la commande à la main")
  ouverte = nil
  ns.importText("Commande : 2x" .. link(7963, "Claymore en mithril") .. " · j'apporte 4x" .. link(4234, "Cuir lourd") .. " · offre 3 po", "Bob")
  local m = ns.commandeMain()
  assert(ouverte and #m.lines == 1 and m.lines[1].id == 7963 and m.lines[1].qty == 2 and m.apporte[1].id == 4234
    and m.player == "Bob" and m.tip == 30000, "importée en commande à la main")
  -- Une commande à la main en cours (pas envoyée) n'est jamais écrasée par un import : refusé, elle reste.
  ns.importText("Commande : 1x" .. link(3858, "Minerai de mithril"), "Lya")
  assert(ns.commandeMain() == m and #m.lines == 1 and m.lines[1].id == 7963 and m.player == "Bob", "import refusé : la commande en cours reste")
  ns.openCommandeMain, Composants = avant, C0
  HandshakeDB.main = nil
end
print("Handshake : sans Composants OK")
