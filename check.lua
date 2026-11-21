-- Vérification hors jeu (non chargée par le TOC) : luajit Handshake/check.lua
-- Juste assez de l'API WoW pour le calcul et le texte. Les premiers tests jouent « GameData installé » (ses tables
-- globales servent de données, lues par la lib commune via les vrais accesseurs de GameData) ; un test à la fin joue
-- Handshake seul. Dans les deux cas, rien de relevé n'est écrit dans HandshakeDB (ADR 0001 de l'atelier).
local noop = function() end
local stubMT = { __index = function() return noop end }
CreateFrame = function() return setmetatable({}, stubMT) end
SlashCmdList, StaticPopupDialogs, UISpecialFrames = {}, {}, {}
C_Timer = { After = noop, NewTicker = noop }
C_Item = { GetItemInfo = noop, GetItemIconByID = noop }
date, time = os.date, os.time
GetTime = function() return 0 end
UnitFactionGroup = function() return "Alliance" end
-- Un perso est rangé sous son GUID ; son numéro de serveur est le royaume de la lib (LibCommune#35).
UnitGUID = function(u) if u == "player" then return "Player-6942-0000000E" end end
GameDataDB, GameDataItems, GameDataMarket = { recipes = {}, chars = {}, lots = {} }, { items = {} }, {}
-- GameData installé : la lib commune lit ses données par GameDataAPI, ses vrais accesseurs (GameData/Souscriptions.lua :
-- inventaires, métiers, marchands, objets, cours de l'HV) ; les recettes connues, même forme que GameData.
GameDataAPI = {}
assert(loadfile("GameData/Souscriptions.lua"))("GameData", GameDataAPI)
GameDataAPI.recettesConnues = function()
  local persos = {}
  for k, c in pairs(GameDataDB.chars) do persos[k] = c.recipes end
  return { recettes = GameDataDB.recipes, persos = persos }
end
HandshakeDB = {}
-- Rien de relevé dans les SavedVariables de Handshake : seulement ses données propres.
local RELEVES = { "recipes", "chars", "items", "market" }
local function aucunReleve(quand)
  for _, k in ipairs(RELEVES) do assert(HandshakeDB[k] == nil, quand .. " : relevé « " .. k .. " » écrit dans HandshakeDB") end
end
-- La lib commune (dépôt voisin, chargée avant Handshake comme dans le jeu) ; son cadre garde son script d'événements.
local libCadre
CreateFrame = function() local f = setmetatable({}, stubMT); f.SetScript = function(self, _, fn) self.onEvent = fn end; libCadre = f; return f end
assert(loadfile("LibCommune/LibStub.lua"))()
assert(loadfile("LibCommune/LibCommune.lua"))()
CreateFrame = function() return setmetatable({}, stubMT) end
assert(loadfile("LibCommune/Interface.lua"))() -- fenêtres, montants, noms d'objets
assert(loadfile("LibCommune/Capture.lua"))()
assert(loadfile("LibCommune/Fournisseurs.lua"))() -- cours de l'HV : GameData, sinon Auctionator…
local ns = {}
for _, f in ipairs({ "Donnees", "Calcul", "Projet", "Commande", "Fenetre", "Besoins", "Contrat", "ContratUI", "Echange", "Debug" }) do
  assert(loadfile("Handshake/" .. f .. ".lua"))("Handshake", ns)
end
assert(ns.findItem and ns.itemLabel and ns.newWindow, "base chargée")
local commune = LibStub("LibCommune-1.0")
assert(ns.newWindow == commune.Fenetre and ns.money == commune.Argent and ns.moneyShort == commune.ArgentCourt
  and ns.moneySigned == commune.ArgentSigne, "fenêtres et montants : ceux de la lib commune, plus de copie")
assert(not io.open("Handshake/Donnees.lua"):read("*a"):find("CreateFrame(\"Frame\", name", 1, true), "plus de copie de la fenêtre")

-- Acheter ou fabriquer : 20 barres de fer, barre à l'HV plus chère que son minerai fondu.

local market = {
  [3575] = { min = 300, qty = 50, tiers = { { price = 300, qty = 10 }, { price = 310, qty = 40 } } }, -- barre
  [2772] = { min = 270, qty = 15, tiers = { { price = 270, qty = 15 } } },                            -- minerai : 15 seulement
}
assert(ns.buyCost(3575, 20, market) == 10 * 300 + 10 * 310, "achat palier par palier")
local ore, how, partial = ns.buyCost(2772, 20, market)
assert(ore == 20 * 270 and how == "HV" and partial, "pas assez en vente : le reste au dernier prix, signalé")
GameDataDB.vendors = { [1] = { items = { { id = 2880, price = 90, stack = 1 } } } }
assert(select(2, ns.buyCost(2880, 2, market)) == "marchand")
local by = { [3575] = { { key = 3307, known = true, r = { name = "Fonte du fer", made_min = 1, reagents = { { id = 2772, qty = 1 } } } } } }
local p = ns.plan(3575, 20, { market = market, by = by }, 0, {})
assert(p.how == "fabriquer" and p.cost == 5400 and p.buy == 6100 and p.parts[1].qty == 20, "fondre est moins cher")
local list = ns.shopping(p, {})
assert(list[2772].qty == 20 and not list[3575], "liste de courses : le minerai, pas la barre")
market[2772].tiers[1].price = 400 -- minerai devenu cher : on achète la barre
assert(ns.plan(3575, 20, { market = market, by = by }, 0, {}).how == "HV")
-- Recette que personne n'a apprise : pas prise par le calcul, mais le « + » existe et la force.
local byU = { [3575] = { { key = 3307, known = false, r = by[3575][1].r } } }
local pu = ns.plan(3575, 20, { market = market, by = byU }, 0, {})
assert(pu.how == "HV" and pu.craftable, "recette pas apprise : achetée, mais « + » possible")
pu = ns.plan(3575, 20, { market = market, by = byU, force = { [3575] = "fabriquer" } }, 0, {})
assert(pu.how == "fabriquer" and pu.known == false, "« + » : décomposé avec la recette pas apprise")
-- Déjà en stock : « + » possible, et forcé il fabrique au lieu de prendre le stock.
local ps = ns.plan(3575, 1, { market = market, by = by, stock = { [3575] = { 1, 0, 0 } } }, 0, {})
assert(ps.how == "stock" and ps.craftable, "en stock : « + » possible")
ps = ns.plan(3575, 1, { market = market, by = by, stock = { [3575] = { 1, 0, 0 } }, force = { [3575] = "fabriquer" } }, 0, {})
assert(ps.how == "fabriquer" and ps.have[1] == 0 and ps.parts[1].id == 2772, "forcé : fabriqué, stock non pris")
print("Handshake : acheter ou fabriquer OK")

-- Stock partagé entre deux lignes (seam interne ns.plan).
market[2772].tiers[1].price = 270
local stock = { [2772] = { 15, 5, 0 }, [3575] = { 4, 0, 0 } } -- 20 minerais (15 sacs + 5 banque), 4 barres en sac
local ctx = { market = market, by = by, stock = stock }
local a = ns.plan(3575, 10, ctx, 0, {})  -- 1re ligne : 4 barres en stock, 6 à fondre avec 6 minerais du sac
assert(a.have[1] == 4 and a.need == 6 and a.how == "fabriquer" and a.cost == 0, "barres du sac puis minerai du sac : gratuit")
local b = ns.plan(3575, 20, ctx, 0, {})  -- 2e ligne : plus de barres ; 14 minerais restants (9 sac + 5 banque), 6 à acheter
assert(b.have[1] == 0 and b.parts[1].have[1] == 9 and b.parts[1].have[2] == 5 and b.parts[1].need == 6, "stock partagé")
assert(b.cost == 6 * 270)

-- Les cases d'un projet (Projet.lua) : une par objet, le même stock pour toutes ses lignes. Les données sont celles que
-- Handshake lit (GameData installé) : HV, recettes, persos ; mes sacs et ma banque.
UnitName = function() return "Moi" end
local MOI = UnitGUID("player")
local TOUT = { unlearned = true } -- options de calcul : toutes les recettes, aucun stock
local function donnees(d) -- d.sacs / d.banque = { [id] = nombre }, d.persos = fiches GameData des autres persos
  local function sac(t)
    local items = {}
    for id, n in pairs(t or {}) do items[#items + 1] = { id = id, count = n } end
    return { b = { items = items } }
  end
  GameDataMarket = { ["6942-Alliance"] = { scanned = "test", items = d.hv } }
  GameDataDB.recipes = d.recettes
  GameDataDB.chars = d.persos or {}
  GameDataDB.chars[MOI] = { bank = sac(d.banque) }
  commune.Conteneurs = function(garder) return garder("Backpack") and sac(d.sacs) or {} end -- mes sacs, lus à l'instant
end
local realContainers = commune.Conteneurs
donnees({ hv = market, recettes = { [3307] = { name = "Fonte du fer", output = 3575, reagents = { { id = 2772, qty = 1 } } } },
  sacs = { [2772] = 15, [3575] = 4 }, banque = { [2772] = 5 } })
local fer = ns.nouveauProjet({ lines = { { id = 3575, qty = 10 }, { id = 3575, qty = 20 } } })
local arbre = ns.projetArbre(fer, { bags = true, bank = true, unlearned = true })
local t1, ore = arbre.caseDe.T1, arbre.caseDe.I2772
assert(t1.have[1] == 4 and t1.made == 6 and arbre.caseDe.T2.made == 20, "barres : 4 du sac, le reste à fondre")
assert(ore.qty == 26 and ore.need == 6 and ore.have[1] == 15 and ore.have[2] == 5 and #ore.parents == 2, "minerai : une case pour les deux lignes")
ns.projetApport(fer, 2772, true)
arbre = ns.projetArbre(fer, { bags = true, bank = true, unlearned = true })
assert(arbre.caseDe.I2772.apport == 26 and arbre.caseDe.I2772.need == 0, "minerai apporté : la case entière")
print("Handshake : cases d'un projet, stock partagé OK")

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
  local p = ns.nouveauProjet({ lines = { { id = 5541, qty = 1 }, { id = 2870, qty = 1 } } })
  for id, c in pairs(choix or {}) do ns.projetChoix(p, id, c) end
  return ns.projetArbre(p, TOUT)
end
local tree = both()
local bronze, pearl, copper = tree.caseDe.I2841, tree.caseDe.I5500, tree.caseDe.I2770
assert(bronze.qty == 30 and bronze.made == 30 and bronze.crafts == 15 and #bronze.parents == 2, "une case bronze pour les deux")
assert(copper.qty == 15 and copper.need == 15 and #copper.parents == 1 and pearl.qty == 3, "cuivre sous le bronze seulement")
-- « – » sur le bronze : acheté tout fait. « + » quand l'achat est moins cher : décomposé quand même.
local bought = both({ [2841] = "acheter" })
assert(bought.caseDe.I2841.need == 30 and bought.caseDe.I2841.made == 0 and not bought.caseDe.I2770, "bronze acheté")
assert(bought.caseDe.I2841.craftable and bought.caseDe.I2841.choix == "acheter", "le « + » reste proposé, le choix se voit")
mk[2841].tiers[1].price = 1
assert(both().caseDe.I2841.made == 0, "bronze à 1 pc : acheté d'office")
assert(both({ [2841] = "fabriquer" }).caseDe.I2841.made == 30, "décomposé à la main")
-- Blocs : marteau et cuirasse = Forge (Bel en connaît 1 sur 2), bronze = Minage (Alt, 0 sur 1).
local res = both({ [2841] = "fabriquer" })
local hammer, plate = res.caseDe.T1, res.caseDe.T2
bronze = res.caseDe.I2841
assert(hammer.who == "Bel" and hammer.whoKnows and plate.who == "Bel" and not plate.whoKnows, "forge : Bel (marteau connu, cuirasse à apprendre)")
assert(bronze.who == "Alt" and not bronze.whoKnows, "bronze : Alt a le minage")
local forge, mine = res.blocDe.Forge, res.blocDe.Minage
assert(#res.blocs == 2 and res.blocs[1] == forge and #forge.cases == 2 and #forge.recipes == 2 and forge.level == 100, "un bloc par métier")
assert(forge.best == "Bel" and mine.best == "Alt", "qui peut faire chaque bloc")
-- Un bloc = une commande, par étapes : le minage (étape 1) livre 30 bronzes ; la forge (étape 2) livre le marteau et la
-- cuirasse, et reçoit le bronze en apport.
assert(mine.step == 1 and #mine.deliver == 1 and mine.qty[2841] == 30 and not next(mine.inputs), "étape 1 : le minage")
assert(forge.step == 2 and forge.qty[5541] == 1 and forge.qty[2870] == 1 and forge.inputs[2841], "étape 2 : la forge, bronze fourni")
-- Le bronze du minage pour le marteau et la cuirasse = UNE livraison Minage -> Forge, par Alt.
local o = res.livraisons[1]
assert(#res.livraisons == 1 and o.maker == "Minage" and o.client == "Forge" and o.player == "Alt", "une livraison Minage -> Forge")
assert(#o.lines == 1 and o.lines[1] == 2841 and o.qty[2841] == 30 and #o.edges == 2, "30 barres de bronze, deux liens regroupés")
-- Commandes (#6) : « Commander » un bloc ajoute une commande au projet affiché, pas un nouveau projet. Elle livre ce
-- que le bloc produit ; ses apports = ce qui entre dans le bloc (le bronze) + mes apports dans sa part (la perle).
do
  local p = ns.nouveauProjet({ player = "Moi", lines = { { id = 5541, qty = 1 }, { id = 2870, qty = 1 } } })
  ns.projetChoix(p, 2841, "fabriquer")
  ns.projetApport(p, 5500, true)
  local nb = select(2, ns.numeroProjet())
  local function arbre() return ns.projetArbre(p, TOUT) end
  local function vue(i) return ns.projetCommande(p, i) end
  local function qte(v, id) for _, l in ipairs(v.lines) do if l.id == id then return l.qty end end end
  local function nbApports(v) local k = 0 for _ in pairs(v.apports or {}) do k = k + 1 end return k end
  local tout = vue(1)
  assert(tout.part == "tout le projet" and tout.player == "Moi" and #tout.lines == 2 and tout.apports[5500], "le projet entier : sa 1re commande")
  local i = ns.projetCommander(p, arbre().blocDe.Forge)
  assert(i == 2 and ns.projetCourant() == p and select(2, ns.numeroProjet()) == nb, "la commande s'ajoute au projet affiché")
  local cf = vue(i)
  assert(cf.part == "Forge" and cf.player == "Bel" and not cf.vide, "le bloc de la forge, à Bel")
  assert(#cf.lines == 2 and qte(cf, 5541) == 1 and qte(cf, 2870) == 1, "il livre le marteau et la cuirasse")
  assert(nbApports(cf) == 2 and cf.apports[2841] and cf.apports[5500], "apports : le bronze qui entre, ma perle")
  local cm = vue(ns.projetCommander(p, arbre().blocDe.Minage))
  assert(cm.part == "Minage" and cm.player == "Alt" and #cm.lines == 1 and qte(cm, 2841) == 30 and nbApports(cm) == 0, "le minage livre 30 bronzes")
  assert(ns.projetCommander(p, arbre().blocDe.Forge) == 2, "le même bloc commandé deux fois : la même commande")
  ns.projetArtisan(p, "Cid", 2)
  ns.projetOffre(p, 700, 2)
  assert(vue(2).player == "Cid" and vue(2).tip == 700 and vue(1).player == "Moi" and not vue(1).tip, "artisan et offre par commande")
  -- Vue vivante : le bronze acheté dans le projet, sans rien recopier. Le bloc du minage disparaît, sa commande reste,
  -- vide ; la forge n'a plus le bronze en apport (son artisan l'achète).
  ns.projetChoix(p, 2841, "acheter")
  local vide = vue(3)
  assert(vide.part == "Minage" and vide.vide and #vide.lines == 0 and #ns.projetCommandes(p) == 3, "commande du minage : vide, toujours là")
  assert(nbApports(vue(2)) == 1 and vue(2).apports[5500], "la forge suit le choix de case du projet")
end
bronzeR.profession = "Couture"
res = both({ [2841] = "fabriquer" })
assert(res.caseDe.I2841.who == false and res.blocs[2].key == "Couture", "personne ne fait la couture : son bloc vient après")
bronzeR.profession = "Minage"
print("Handshake : blocs d'un projet OK")

-- Dessin (Fenetre.lua) : étages, relais, bandes, titres des blocs.
mk[2841].tiers[1].price = 100
local g = ns.dessinArbre(both())
bronze, pearl, copper = g.byKey.I2841, g.byKey.I5500, g.byKey.I2770
assert(g.cols == 3 and bronze.col == 1 and pearl.col == 1 and copper.col == 2, "étages : bronze et perle en 1, minerai en 2")
for _, n in ipairs(g.nodes) do -- pas de chevauchement dans un étage
  for _, m in ipairs(g.nodes) do
    assert(n == m or n.col ~= m.col or math.abs(n.y - m.y) >= 50, "cases superposées")
  end
end
assert(ns.dessinArbre(both({ [2841] = "acheter" })).cols == 2, "bronze acheté : plus d'étage 2")
-- Lien qui saute un étage (ta capture : barre de fer commandée + haubert qui en consomme) : il passe par un relais à
-- l'étage 1, et aucune case de cet étage ne lui marche dessus.
do
  local p = ns.nouveauProjet({ lines = { { id = 2841, qty = 2 }, { id = 5541, qty = 1 } } }) -- bronze commandé + marteau
  ns.projetChoix(p, 2841, "fabriquer")
  local gr = ns.dessinArbre(ns.projetArbre(p, TOUT))
  local e
  for _, x in ipairs(gr.edges) do if x.from.key == "T1" and x.to.key == "I2770" then e = x end end
  assert(e and #e.path == 3 and e.path[2].kind == "relay" and e.path[2].col == 1, "relais à l'étage 1")
  local r = e.path[2]
  for _, n in ipairs(gr.nodes) do
    assert(n.col ~= 1 or r.y + 14 <= n.y or n.y + 42 <= r.y, "une case de l'étage 1 recouvre le lien")
  end
end
do
  local gr = ns.dessinArbre(both({ [2841] = "fabriquer" }))
  local forge = gr.groupOf.Forge
  assert(forge.label == "Étape 2 · Forge · niv. 100 requis · Bel 164 (1/2)", forge.label)
  -- Rectangles : chaque métier dans sa bande, aucune case d'un autre dans son rectangle.
  for _, grp in ipairs(gr.groups) do
    local top, bottom, left, right = math.huge, -math.huge, math.huge, -math.huge
    for _, n in ipairs(grp.cards) do
      top, bottom = math.min(top, n.y), math.max(bottom, n.y + 42)
      left, right = math.min(left, n.col), math.max(right, n.col)
    end
    for _, n in ipairs(gr.nodes) do
      local inside = n.col >= left and n.col <= right and n.y + 42 > top and n.y < bottom
      assert(not inside or n.band == grp.key, "une case d'un autre dans le rectangle de " .. grp.key)
    end
  end
  assert(gr.byKey.I2770.band == "Minage", "minerai sous le bronze : dans la bande du minage")
  bronzeR.profession = "Couture"
  gr = ns.dessinArbre(both({ [2841] = "fabriquer" }))
  assert(gr.groupOf.Couture.label == "Étape 1 · Couture · personne de ta liste", gr.groupOf.Couture.label)
  for _, n in ipairs(gr.nodes) do -- rien ne se chevauche, bande sans artisan comprise
    for _, m in ipairs(gr.nodes) do
      assert(n == m or n.col ~= m.col or n.y + 42 <= m.y or m.y + 42 <= n.y, "cases superposées")
    end
  end
  bronzeR.profession = "Minage"
end
commune.Conteneurs, GameDataDB.chars = realContainers, {}
print("Handshake : dessin de l'arbre (étages, relais, bandes) OK")

-- Suggestions : fabricables d'abord, puis début de nom, puis noms courts.
GameDataItems.items = { [1] = { name = "Barre de bronze" }, [2] = { name = "Bronze" }, [3] = { name = "Lame en bronze" }, [4] = { name = "Fer" } }
GameDataDB.recipes = { [9] = { name = "Lame en bronze", output = 3 }, [8] = { name = "Cuirasse changeante", output = 210794 } }
local sug = ns.suggestItems(ns.itemIndex(), "bron")
assert(#sug == 3 and sug[1].id == 3 and sug[2].id == 2 and sug[3].id == 1, "ordre des suggestions")
assert(ns.suggestItems(ns.itemIndex(), "chang")[1].id == 210794, "recette dont l'objet n'a pas de nom")
assert(#ns.suggestItems(ns.itemIndex(), "b") == 0, "au moins 2 lettres")
print("Handshake : suggestions OK")


-- Texte échangé : liens réels (~80 caractères), découpés sous 255, relus à l'identique.
local function link(id, name) return ("|cff1eff00|Hitem:%d::::::::31:::::::::|h[%s]|h|r"):format(id, name) end
GameDataItems.items = { [7963] = { name = "Claymore en mithril", link = link(7963, "Claymore en mithril") },
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

-- Besoins : composants pas fabriqués avec ce qu'on a ; recette pas apprise -> l'objet « Plans : … ».
local res = { cases = {
  { id = 7963, kind = "target", qty = 1, made = 1, need = 0, have = { 0, 0, 0 }, unknown = true, recipe = { name = "Claymore en mithril" } },
  { id = 3858, kind = "item", qty = 36, made = 0, need = 30, cost = 3000, have = { 6, 0, 0 }, how = "HV" },
  { id = 7920, kind = "item", qty = 1, made = 0, need = 0, cost = 0, have = { 1, 0, 0 } },
}, total = 3000 }
local rows, recipes = ns.orderNeeds(res)
assert(#rows == 2 and rows[1].id == 3858 and rows[1].required == 36 and rows[2].need == 0, "manquants d'abord, le complet ensuite")
assert(#recipes == 1 and recipes[1].item == 7989, "recette trouvée par son nom")
print("Handshake : besoins OK")

aucunReleve("avec GameData, après les calculs")
-- Chargement (ADDON_LOADED) : les relevés d'un Handshake d'avant sont purgés, les données propres restent.
HandshakeDB = { chars = { [MOI] = { bags = {}, bank = {} } }, items = { [1] = { name = "x" } }, market = { ["6942-Alliance"] = {} },
  recipes = {}, contracts = { k = { status = "signe" } }, projets = { { name = "P", lines = {} } }, courant = 1,
  options = { bags = true }, surnames = { Bob = "Kerys" }, debug = { on = true } }
local loader
CreateFrame = function() return setmetatable({ SetScript = function(_, _, fn) loader = fn end }, stubMT) end
assert(loadfile("Handshake/Donnees.lua"))("Handshake", ns)
loader(nil, "ADDON_LOADED", "Handshake")
aucunReleve("au chargement")
assert(HandshakeDB.contracts.k and HandshakeDB.projets[1].name == "P" and HandshakeDB.options.bags and HandshakeDB.surnames.Bob
  and HandshakeDB.debug.on, "données propres gardées")
-- Première ouverture : réglages par défaut, aucun projet repris de GameData (ses vieux suivis ne sont plus lus).
HandshakeDB = nil
assert(loadfile("Handshake/Commande.lua"))("Handshake", ns)
loader(nil, "ADDON_LOADED", "Handshake")
assert(select(2, ns.numeroProjet()) == 1 and #ns.projetCourant().lines == 0 and HandshakeDB.options.bags and HandshakeDB.options.bank,
  "réglages par défaut, un projet vide")
-- Contrats d'avant la signature par GUID (signataires « Prénom-Royaume », Handshake#29) : plus lus, purgés au chargement
-- (perte de données acceptée) ; ceux signés par GUID restent, et aussi ceux du Testeur (mode debug).
HandshakeDB = { contracts = { ancien = { client = "Bob-CAMWOWEU4Realm8PvP", artisan = "Bel-CAMWOWEU4Realm8PvP", status = "signe" },
  neuf = { client = "Player-6942-00000B0B", artisan = "Player-6942-0000BEEF", status = "signe" } },
  debug = { contracts = { vieux = { client = "Testeur-R" }, bon = { client = "Player-0-00000DEB" } } } }
loader(nil, "ADDON_LOADED", "Handshake")
assert(HandshakeDB.contracts.neuf and not HandshakeDB.contracts.ancien, "ancien contrat purgé, contrat par GUID gardé")
assert(HandshakeDB.debug.contracts.bon and not HandshakeDB.debug.contracts.vieux, "pareil pour ceux du Testeur")
-- Migration (19/11/2026) : des commandes enregistrées à l'ancienne (la 2e liée à un contrat, affichée) et la table
-- globale des choix « fabriquer / acheter ».
HandshakeDB = { orders = {
  { name = "Ma commande", player = "Bel", tip = 500, lines = { { id = 5541, qty = 1 } }, apports = { [5500] = true } },
  { name = "Réponse à Bob", reply = "Bob-R#1", replyHash = "abc", player = "Bob-R", lines = { { id = 7963, qty = 1 } } },
}, current = 2, force = { [2841] = "acheter" } }
loader(nil, "ADDON_LOADED", "Handshake")
local pos, nb = ns.numeroProjet()
assert(nb == 2 and pos == 2, "chaque commande devient un projet, le même affiché")
local reponse = ns.projetCourant()
assert(not ns.projetAjouter(reponse, 2841, 1) and #reponse.lines == 1, "la commande liée est une réponse : ce qu'il veut est figé")
assert(ns.projetReponse({ origin = "Bob-R", id = "1", hash = "abc" }) == reponse, "la réponse retrouvée par son contrat, même version gardée")
local mien = ns.changerProjet(-1)
local tout = ns.projetCommande(mien)
assert(mien.name == "Ma commande" and tout.player == "Bel" and tout.tip == 500 and mien.apports[5500], "artisan, offre et apports repris")
assert(#ns.projetCommandes(mien) == 1 and tout.part == "tout le projet", "artisan et offre : sa commande « tout le projet »")
assert(ns.projetAjouter(mien, 2841, 1), "un projet à moi se modifie")
assert(HandshakeDB.force == nil and HandshakeDB.orders == nil and HandshakeDB.current == nil, "l'ancienne table des choix et les commandes disparaissent")
-- Un projet enregistré avant les commandes (#5 : artisan et offre sur le projet) : ils deviennent sa commande « tout le projet ».
HandshakeDB = { projets = { { name = "Projet #5", player = "Bel", tip = 900, lines = { { id = 5541, qty = 1 } } } }, courant = 1 }
loader(nil, "ADDON_LOADED", "Handshake")
local p5 = ns.projetCourant()
assert(ns.projetCommande(p5).player == "Bel" and ns.projetCommande(p5).tip == 900, "projet #5 : artisan et offre repris")
ns.projetArtisan(p5, "Cid")
assert(ns.projetCommande(p5).player == "Cid", "puis fixés sur sa commande")
ns.openCraftWindow = noop -- pas d'interface hors jeu
ns.importText(msgs[1] .. " " .. msgs[2]:gsub("^.-: ", ""), "Bob")
pos, nb = ns.numeroProjet()
assert(nb == 2 and pos == 2 and ns.projetCommande(ns.projetCourant()).player == "Bob", "commande importée affichée")
print("Handshake : reprise, migration et import OK")

-- /commande essai : la commande affichée revient comme un chuchotement de soi-même, sans réseau.
UnitName = function() return "Belegard" end
popups = {}
local realPrint = print
print = noop
ns.costCommand("essai")
print = realPrint
assert(#popups == 1 and popups[1].who == "Belegard" and popups[1].kind == "commande", "essai : import proposé")
print("Handshake : essai OK")

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
local bases = { [BEL] = { contracts = {} }, [BOB] = { contracts = {} } }
local current, notes, wire = BEL, {}, {}
local function as(who) current = who; HandshakeDB = bases[who] end
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

-- Bob contre-propose une caution de 6000 au lieu de 5400 : v2, parent = v1.
ns.ctCounter(atBob, 6000, nil, nil)
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
print("Handshake : échanges vérifiés et contrat clos OK")

-- Demande (CONCEPTION.md) : Bob veut une claymore (30 minerais + 4 cuirs lourds), il apporte le cuir (Ctrl+clic),
-- offre 3 po. Contrat v1 : caution = prix de marché du cuir seulement ; la claymore = sa part de caution + l'offre.
as(BOB)
UnitFactionGroup = function() return "Alliance" end
GameDataMarket = { ["6942-Alliance"] = { scanned = "hier", items = { [3858] = { tiers = { { price = 200, qty = 999 } } },
  [4234] = { tiers = { { price = 500, qty = 999 } } }, [7963] = { tiers = { { price = 99999, qty = 9 } } } } } }
GameDataDB.recipes = { [1] = { name = "Claymore", output = 7963, reagents = { { id = 3858, qty = 30 }, { id = 4234, qty = 4 } } } }
GameDataItems.items[4234] = { name = "Cuir lourd", link = link(4234, "Cuir lourd") }
HandshakeDB.projets = {}
local demande = ns.nouveauProjet({ player = BELN, tip = 30000, lines = { { id = 7963, qty = 1 } } })
ns.projetApport(demande, 4234, true)
local dres = ns.projetDemande(demande)
local brought = ns.demandeApports(dres)
assert(#brought == 1 and brought[1].id == 4234 and brought[1].qty == 4, "apport : le cuir, case entière")
assert(dres.roots[1].how == "fabriquer" and dres.roots[1].cost == 30 * 200, "part de l'artisan : le minerai seulement")
-- L'artisan doit avoir un GUID donné par le serveur (Bob a ciblé Belegard plus haut) : un contrat porte deux GUID.
local inconnu = ns.nouveauProjet({ player = CARLN, tip = 30000, lines = { { id = 7963, qty = 1 } } })
local pas, pourquoi = ns.ctFromDemande(ns.projetCommande(inconnu), 3)
assert(pas == nil and pourquoi:find("GUID de " .. CARLN .. " inconnu", 1, true), "artisan jamais vu : pas de contrat, " .. tostring(pourquoi))
local v1 = ns.ctFromDemande(ns.projetCommande(demande), 3)
assert(v1.client == BOB and v1.artisan == BEL and v1.peer.name == BELN and v1.peer.verified, "moi client, l'autre artisan (son GUID appris)")
assert(#v1.m == 1 and v1.m[1].id == 4234 and v1.m[1].unit == 500 and v1.o[1].unit == 4 * 500 + 30000, "caution sur l'apport + offre")
assert(ns.ctParse(ns.ctMessage(v1), BEL, clock), "ce qu'on envoie passe notre propre lecture stricte")
-- Sans apport : vente simple (pas de caution).
local simple = ns.ctFromDemande(ns.projetCommande(ns.nouveauProjet({ player = BELN, tip = 30000, lines = { { id = 7963, qty = 1 } } })), 3)
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
ns.openCraftWindow = noop
ns.importText(popups[1].data.text, "Bob")
assert(ns.projetCourant().apports and ns.projetCourant().apports[4234] and ns.projetCommande(ns.projetCourant()).tip == 30000, "demande importée avec ses apports")
print("Handshake : demande (apports, offre, vente simple, en clair) OK")

-- Mode debug (Debug.lua, non publié) : le Testeur a un nom complet et un GUID (numéro de serveur 0 : il n'existe pas) ;
-- ce qui lui est envoyé lui est livré sous mon nom, et il le lit comme un vrai joueur.
as(BOB)
ns.learnGUID("Testeur Bacasable", "Player-0-00000DEB") -- ce que fait l'ouverture du mode debug
local essai = ns.ctFromDemande(ns.projetCommande(ns.nouveauProjet({ player = "Testeur Bacasable", tip = 100, lines = { { id = 7963, qty = 1 } } })), 3)
assert(essai and ns.ctPropose(essai), "demande au Testeur")
local chezTesteur = HandshakeDB.debug.contracts[ns.ctKey(essai)]
assert(chezTesteur and chezTesteur.status == "a_signer" and chezTesteur.peer.name == BOBN and chezTesteur.peer.guid == GBOB,
  "livrée au Testeur, sous mon nom et mon GUID")
HandshakeDB.contracts[ns.ctKey(essai)], HandshakeDB.debug = nil, nil
print("Handshake : mode debug, le Testeur OK")

-- Je réponds (l'artisan) : Belegard ouvre la demande dans son arbre, demande aussi le minerai et chiffre 5 po.
ns.ctPropose(v1)
as(BEL)
local key1 = ns.ctKey(v1)
local recu = HandshakeDB.contracts[key1]
assert(recu and ns.ctStatus(recu) == "a_signer", "demande reçue par l'artisan")
local rep = ns.projetReponse(recu)
local function reponse1() return ns.projetCommande(rep) end -- la réponse elle-même : sa commande « tout le projet »
assert(rep.reponse == key1 and rep.apports[4234] and reponse1().tip == 30000 and rep.lines[1].id == 7963 and reponse1().player == BOBN, "sa demande dans mon arbre")
assert(select(2, ns.ctReplyFromOrder(reponse1())):find("rien n'a changé"), "rien changé : rien ne part")
ns.projetApport(rep, 3858, true)
ns.projetOffre(rep, 50000)
assert(ns.projetReponse(recu) == rep and rep.apports[3858], "même version rouverte : mes changements restent")
local v2 = ns.ctReplyFromOrder(reponse1())
assert(v2.v == "2" and #v2.m == 2 and v2.m[1].id == 3858 and v2.m[1].unit == 200 and v2.m[2].unit == 500,
  "minerai ajouté au prix de mon scan, cuir à la caution du contrat")
assert(v2.o[1].unit == 30 * 200 + 4 * 500 + 50000, "livraison = cautions + mon prix")
as(BOB)
local back = HandshakeDB.contracts[key1]
assert(back.v == "2" and back.status == "a_signer" and back.prev.v == "1", "Bob reçoit la contre-proposition")
assert(not ns.ctReplyFromOrder({ reponse = key1, lines = demande.lines }), "le client ne répond pas comme artisan")
print("Handshake : je réponds (ma part, mes apports, mon prix) OK")

-- Règles de la réponse (#10), une règle du module Projet : ce que veut le demandeur (lignes, quantités) est figé, avec
-- une raison affichable telle quelle ; apports, choix de case, prix et commande d'un bloc restent à l'artisan. La demande
-- est un contrat reçu (seuls son empreinte, son client, o et m comptent ici).
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
  figee("lignes", ns.projetPeut(r, "lignes"))
  figee("ajouter une ligne", ns.projetAjouter(r, 3858, 2))
  figee("changer une quantité", ns.projetQuantite(r, 1, 5))
  figee("retirer une ligne", ns.projetRetirer(r, 1))
  assert(#r.lines == 1 and r.lines[1].qty == 1, "ce qu'il veut n'a pas bougé")
  for _, quoi in ipairs({ "apports", "choix", "offre", "commander" }) do assert(ns.projetPeut(r, quoi), quoi .. " : permis") end
  assert(ns.projetApport(r, 3858, true) and r.apports[3858], "apports : contre-proposition")
  assert(ns.projetChoix(r, 3858, "acheter") and r.choix[3858] == "acheter", "choix de case : estimation de l'artisan")
  assert(ns.projetOffre(r, 40000) and ns.projetCommande(r).tip == 40000, "offre : mon prix")
  -- Commander un bloc d'une réponse : une commande de cette réponse (sous-traitance), ordinaire (j'en suis le client).
  ns.projetChoix(r, 3858, nil)
  local i = ns.projetCommander(r, ns.projetArbre(r, TOUT).blocs[1])
  local sous = ns.projetCommande(r, i)
  assert(i == 2 and #ns.projetCommandes(r) == 2 and sous.bloc and not sous.reponse and sous.etat == "pas envoyée",
    "le bloc commandé : une commande de la réponse")
  assert(ns.projetCommande(r).reponse and not ns.projetCommande(r).etat, "la 1re reste la réponse elle-même, sans état")
  ns.projetArtisan(r, "Cid", i)
  assert(ns.projetOffre(r, 700, i) and ns.projetCommande(r, i).player == "Cid" and ns.projetCommande(r, i).tip == 700,
    "sa commande de bloc se règle comme une autre")
  -- La même version rouverte : mes changements restent ; une nouvelle version de la demande : la réponse est reprise.
  assert(ns.projetReponse(recue("h1", 1)) == r and r.apports[3858] and ns.projetCommande(r).tip == 40000, "même version : rien ne bouge")
  assert(ns.projetReponse(recue("h2", 3)) == r and r.lines[1].qty == 3 and not r.apports[3858] and r.apports[4234]
    and ns.projetCommande(r).tip == 3 * 9000 - 4 * 500, "nouvelle version : sa demande reprise, mes changements effacés")
  -- Un projet à moi : tout se modifie.
  local mien = ns.nouveauProjet({ lines = { { id = 7963, qty = 1 } } })
  assert(ns.projetPeut(mien, "lignes") and ns.projetQuantite(mien, 1, 2) and ns.projetAjouter(mien, 3858, 1) and ns.projetRetirer(mien, 2),
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
GameDataMarket = { ["6942-Alliance"] = { scanned = "hier", items = tiers({ [2770] = 10, [2771] = 10, [5500] = 500, [2841] = 100, [5541] = 99999, [2870] = 99999 }) } }
GameDataDB.recipes = {
  [1] = { name = "Marteau", output = 5541, profession = "Forge", reagents = { { id = 2841, qty = 10 }, { id = 5500, qty = 1 } } },
  [2] = { name = "Cuirasse", output = 2870, profession = "Forge", reagents = { { id = 2841, qty = 20 } } },
  [3] = { name = "Fonte du bronze", output = 2841, made_min = 2, profession = "Minage", reagents = { { id = 2770, qty = 1 }, { id = 2771, qty = 1 } } },
}
do
  local function lignes() return { { id = 5541, qty = 1 }, { id = 2870, qty = 1 } } end
  local pa = ns.nouveauProjet({ player = BELN, tip = 8000, lines = lignes() })
  local pb = ns.nouveauProjet({ player = BELN, tip = 8000, lines = lignes() })
  ns.projetApport(pb, 5500, true)
  local function termes(p, i) -- les termes de la commande i (1 = tout le projet : ceux du projet seul, d'avant les commandes)
    local c = assert(ns.ctFromDemande(ns.projetCommande(p, i), 3))
    local function txt(l) local t = {} for _, x in ipairs(l) do t[#t + 1] = x.id .. ":" .. x.qty .. ":" .. x.unit end return table.concat(t, ",") end
    return txt(c.m) .. " / " .. txt(c.o)
  end
  local avantA, avantB = termes(pa), termes(pb)
  assert(avantB == "5500:1:500 / 2870:1:5333,5541:1:3167", avantB)
  ns.projetChoix(pa, 2841, "acheter")
  assert(termes(pa) ~= avantA, "témoin : le choix change les prix par objet du projet A")
  assert(ns.projetArbre(pa, TOUT).caseDe.I2841.made == 0, "projet A : le bronze acheté")
  assert(termes(pb) == avantB, "projet B : caution et prix par objet inchangés")
  assert(ns.projetArbre(pb, TOUT).caseDe.I2841.made == 30, "projet B : le bronze toujours fondu")
  -- Commande du bloc de la forge (#6) : le bronze du minage en caution à côté de ma perle ; la part de l'artisan ne
  -- coûte plus rien, l'offre se partage par moitié.
  local i = ns.projetCommander(pb, ns.projetArbre(pb, TOUT).blocDe.Forge)
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
local sacsAvant, optionsAvant = commune.Conteneurs, HandshakeDB.options
commune.Conteneurs = function() return { b = { items = { { id = 5541, count = 1 } } } } end
HandshakeDB.options = { bags = true, unlearned = true }
local ok, err = pcall(function()
  local p = ns.nouveauProjet({ lines = { { id = 5541, qty = 2 }, { id = 2870, qty = 1 } } })
  ns.projetChoix(p, 2841, "fabriquer")
  local blocs = ns.projetArbre(p).blocDe -- l'arbre de la fenêtre, stock déduit
  local forge, mine = ns.projetCommande(p, ns.projetCommander(p, blocs.Forge)), ns.projetCommande(p, ns.projetCommander(p, blocs.Minage))
  local livre, recu = mine.lines[1], ns.demandeApports(ns.projetDemande(forge))
  assert(livre.id == 2841 and recu[1].id == 2841 and livre.qty == recu[1].qty and livre.qty == 40,
    ("le minage livre %d bronzes, la forge en reçoit %d"):format(livre.qty, recu[1].qty))
end)
commune.Conteneurs, HandshakeDB.options = sacsAvant, optionsAvant
assert(ok, err)
print("Handshake : commandes sur l'arbre de la demande OK")

-- Envoyer une commande (#7) : « Préparer la demande » en fait un brouillon de contrat, qui la suit encore ; envoyée, elle
-- devient une demande (contrat v1) : ses termes sont ceux du contrat et ne bougent plus avec le projet, son état se lit
-- dans le contrat.
as(BOB)
do
  local p = ns.nouveauProjet({ lines = { { id = 5541, qty = 1 }, { id = 2870, qty = 1 } } })
  ns.projetChoix(p, 2841, "fabriquer")
  local i = ns.projetCommander(p, ns.projetArbre(p, TOUT).blocDe.Forge)
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
  assert(cmd().etat == "pas envoyée", "pas encore de contrat")
  local ct = assert(ns.projetEnvoyer(p, i))
  assert(ct.status == "brouillon" and cmd().etat == "pas envoyée", "brouillon : pas envoyée")
  ns.projetOffre(p, 9000, i)
  ct = assert(ns.projetEnvoyer(p, i))
  assert(ns.ctTotal(ct.o) - ns.ctTotal(ct.m) == 9000, "préparée de nouveau : le brouillon suit la commande")
  ns.ctPropose(ct)
  assert(cmd().etat == "demande envoyée", "envoyée : son état vient du contrat")
  assert(ns.ctKey(ct) ~= key1 and bases[BEL].contracts[ns.ctKey(ct)].hash == ct.hash, "même seconde qu'une autre demande : une autre clé, arrivée chez Belegard")
  local envoyee = termes(cmd())
  assert(envoyee == "2870x1,5541x1 / 2841 / 9000 / " .. BELN, envoyee)
  ns.projetChoix(p, 2841, "acheter")
  ns.projetApport(p, 5500, true)
  ns.projetAjouter(p, 5541, 3)
  ns.projetOffre(p, 1, i)
  ns.projetArtisan(p, "Cid", i)
  assert(termes(cmd()) == envoyee, "le projet change : la demande ne bouge pas")
  assert(ns.projetEnvoyer(p, i) == ct, "une demande envoyée n'est pas refaite")
  -- Belegard contre-propose (+ 10 pa), Bob signe : la commande suit son contrat, pas le projet.
  as(BEL)
  local chez = HandshakeDB.contracts[ns.ctKey(ct)]
  ns.ctCounter(chez, nil, ns.ctTotal(chez.o) + 1000)
  as(BOB)
  assert(cmd().etat == "contre-proposée", "contre-proposée")
  local v2 = HandshakeDB.contracts[ns.ctKey(ct)]
  assert(ns.ctAccept(v2, v2.hash))
  assert(cmd().etat == "signée" and cmd().tip == 10000, "signée, au prix de la version signée")
  -- En clair (#7) : le texte part de la commande, avec ses lignes, ses apports et son offre ; envoyée, ce sont ceux de son
  -- contrat, même si la recette a changé depuis (la cuirasse prend maintenant 25 bronzes).
  for id, nom in pairs({ [5541] = "Marteau", [2870] = "Cuirasse", [2841] = "Barre de bronze" }) do
    GameDataItems.items[id] = { name = nom, link = link(id, nom) }
  end
  GameDataDB.recipes[2].reagents[1].qty = 25
  popups = {}
  ns.whisper = function(msg) ns.onChat("CHAT_MSG_WHISPER", msg, BOBN) end
  ns.sendOrder(cmd())
  ns.whisper = realWhisper
  GameDataDB.recipes[2].reagents[1].qty = 20
  local voulu, _, offre, apporte = ns.parseList(popups[1].data.text)
  table.sort(voulu, function(a, b) return a.id < b.id end)
  assert(#voulu == 2 and voulu[1].id == 2870 and voulu[1].qty == 1 and voulu[2].id == 5541 and voulu[2].qty == 1, "ses lignes")
  assert(#apporte == 1 and apporte[1].id == 2841 and apporte[1].qty == 30 and offre == 10000, "ses apports (du contrat), son offre")
  -- Le bloc de la forge commandé de nouveau : sa commande est figée, une nouvelle commande vivante (son identité à elle) ;
  -- commandé encore une fois : la même, tant qu'elle n'est pas partie.
  local j = ns.projetCommander(p, ns.projetArbre(p, TOUT).blocDe.Forge)
  assert(j ~= i and not ns.projetCommande(p, j).fige and ns.projetCommande(p, j).etat == "pas envoyée", "une nouvelle commande de la forge")
  assert(ns.projetCommande(p, j).id ~= cmd().id, "chaque commande a son identité")
  assert(ns.projetCommander(p, ns.projetArbre(p, TOUT).blocDe.Forge) == j, "la commande vivante est reprise")
  assert(termes(cmd()) ~= termes(ns.projetCommande(p, j)), "la nouvelle suit le projet, l'envoyée non")
end
print("Handshake : envoyer une commande (demande figée, état lu dans le contrat) OK")

-- Écart et nouvelle version (#8) : une commande envoyée ne bouge jamais d'elle-même ; quand la part du projet qu'elle vise
-- change, l'écart est signalé (pas quand le changement est ailleurs) ; « Nouvelle version » la renvoie en contre-
-- proposition, dont le différentiel est l'écart. Refusée, retirée ou échue, elle se commande de nouveau.
-- L'écart est constaté, jamais expliqué (#18) : un libellé neutre, et l'écart de prix chiffré contre mon scan.
as(BOB)
C_CurrencyInfo = { GetCoinTextureString = function(c) return c .. "pc" end }
GameDataMarket = { ["6942-Alliance"] = { scanned = "hier", items = { [2841] = { tiers = { { price = 100, qty = 999 } } } } } }
do
  local p = ns.nouveauProjet({ lines = { { id = 5541, qty = 1 }, { id = 2870, qty = 1 } } })
  ns.projetChoix(p, 2841, "fabriquer")
  local blocs = ns.projetArbre(p, TOUT).blocDe
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
  local barres = GameDataMarket["6942-Alliance"].items[2841]
  assert(cmd(f).ecartPrix == 0 and not cmd(f).alertePrix and not cmd(f).incomplet, "caution = mon estimation : 0 %")
  barres.tiers[1].price = 150
  assert(math.floor(cmd(f).ecartPrix + 0.5) == -33 and cmd(f).alertePrix, "le marché monte : caution trop basse pour moi, en rouge")
  assert(not cmd(f).ecart, "le prix n'est pas un écart de contenu")
  assert(ns.ctDescribe(cf, BOB):find(("caution |cffe64d4d%+.0f %%|r"):format(cmd(f).ecartPrix), 1, true), "le même chiffre que la fiche")
  barres.tiers[1].price = 105
  assert(math.floor(cmd(f).ecartPrix + 0.5) == -5 and not cmd(f).alertePrix, "sous le seuil de 10 % : pas d'alerte")
  GameDataMarket["6942-Alliance"].items[2841] = nil
  assert(cmd(f).incomplet and cmd(f).ecartPrix == nil, "sans prix connu : estimation incomplète, pas de pourcentage")
  assert(ns.ctDescribe(cf, BOB):find("1 composant(s) sans prix connu", 1, true), "la fiche le dit aussi")
  GameDataMarket["6942-Alliance"].items[2841] = barres
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
  assert(chez[ns.ctKey(cf)].v == "1" and cmd(f).etat == "demande envoyée" and cmd(f).ecart, "rien n'est parti, l'écart reste")
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
  assert(not cmd(f).ecart and cmd(f).etat == "contre-proposée", "nouvelle version partie : plus d'écart")
  -- Sa contre-proposition qui ne change que le prix : rien à signaler (la part du projet n'a pas bougé).
  as(BEL)
  ns.ctCounter(recu, nil, ns.ctTotal(recu.o) + 1000)
  as(BOB)
  assert(cmd(f).etat == "contre-proposée" and not cmd(f).ecart, "il change son prix : pas d'écart")
  -- Une quantité qui change : le minage (plus de bronze) et la forge (plus de cuirasses).
  ns.projetQuantite(p, 2, 2)
  assert(cmd(m).ecart == "ne correspond plus au contrat" and cmd(f).ecart == cmd(m).ecart, "quantité : les deux, même libellé")
  -- Belegard refuse le minage : figé, pas de nouvelle version, mais il se commande de nouveau (une commande vivante,
  -- reprise tant qu'elle n'est pas partie).
  as(BEL)
  ns.ctRefuse(HandshakeDB.contracts[ns.ctKey(cm)])
  as(BOB)
  assert(cmd(m).etat == "refusée" and not cmd(m).ecart and cmd(m).recommander, "refusée : à commander de nouveau")
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
  assert(cmd(1).etat == "retirée" and cmd(1).recommander)
  local t2 = ns.projetRecommander(p, 1)
  assert(t2 and t2 ~= 1 and cmd(t2).part == "tout le projet" and not cmd(t2).fige and #cmd(t2).lines == 2, "tout le projet, de nouveau")
  -- Ce qui part reste dans les bornes que vérifie celui qui reçoit (n° 15) : 1001 cuirasses ne partent pas.
  ns.projetQuantite(p, 2, 1001)
  local _, trop = ns.projetNouvelleVersion(p, f)
  assert(trop and trop:find("bornes"), "hors bornes : rien n'est envoyé")
  assert(bases[BEL].contracts[ns.ctKey(cf)].v == "3", "Belegard a toujours la v3 (son prix)")
  -- Un brouillon de nouvelle version dépassé (il contre-propose entre-temps) : périmé, il ne part pas, il est effacé.
  ns.projetQuantite(p, 2, 2)
  local b = assert(ns.projetNouvelleVersion(p, f))
  assert(b.v == "4" and b.prev.v == "3", "brouillon de la v4")
  as(BEL)
  local v3 = HandshakeDB.contracts[ns.ctKey(cf)]
  assert(ns.ctCounter(v3, nil, ns.ctTotal(v3.o) + 500))
  as(BOB)
  local _, perime = ns.ctPropose(b)
  assert(perime and perime:find("a changé") and not HandshakeDB.contracts[ns.ctKey(b)], "périmé : effacé, pas envoyé")
  assert(HandshakeDB.contracts[ns.ctKey(cf)].author == BEL and bases[BEL].contracts[ns.ctKey(cf)].v == "4", "sa v4 reste")
end
print("Handshake : écart et nouvelle version d'une commande envoyée OK")

-- Fiche du contrat : besoins gonflés signalés (n° 12), perte maximale de chaque côté (P8).
C_CurrencyInfo = { GetCoinTextureString = function(c) return c .. "pc" end }
UnitFactionGroup = function() return "Alliance" end
GameDataMarket = { ["6942-Alliance"] = { scanned = "hier", items = { [3858] = { tiers = { { price = 200, qty = 999 } } } } } }
GameDataDB.recipes = { [1] = { name = "Claymore", output = 7963, reagents = { { id = 3858, qty = 30 } } } }
as(BOB)
local fiche = ns.ctDescribe(signed, BOB)
assert(fiche:find("36 demandés, la recette en consomme 30"), "minerai gonflé signalé")
assert(fiche:find("Si l'artisan disparaît après l'étape 1 : tu perds au plus 1188pc"), "perte max du client : 36×200 − 6012")
as(BEL)
assert(ns.ctDescribe(bases[BEL].contracts[k], BEL):find("tu es l'ARTISAN"), "rôle affiché depuis mon côté")
print("Handshake : fiche du contrat OK")

-- Noms à la Forever (LibCommune#35, Handshake#29) : « Prénom Nom », la forme du serveur, pour afficher et chuchoter ;
-- un personnage s'identifie par son GUID. Plus d'adresse « Prénom-Royaume » : lib.Adresse est retirée de la lib.
assert(ns.fullName == commune.Destinataire and ns.whisperTarget == commune.Destinataire, "noms : ceux de la lib commune, plus de copie")
assert(commune.Adresse == nil, "lib.Adresse retirée (plus d'appelant)")
assert(ns.fullName("Belegard Marteaudefer-CAMWOWEU4Realm8PvP") == BELN, "un « -Royaume » retiré")
UnitName = function() return "Belegard", "Marteaudefer" end
as(BEL)
assert(ns.me() == GBEL and ns.myName() == BELN, "moi : mon GUID ; mon nom : prénom et nom de famille")
print("Handshake : noms à la Forever OK")

-- Avec GameData : les recettes connues de tous ses persos, par la lib commune.
local ALT, SANS = "Player-6942-00000A17", "Player-6942-00005A25"
GameDataDB.chars = { [ALT] = { nom = "Alt Dupont", recipes = { Forge = { rank = 50, max = 75, known = { [9] = "easy" } } },
  professions = { { name = "Couture", rank = 120 } }, bags = { b = { items = { { id = 2840, count = 4 } } } } }, [SANS] = {} }
assert(ns.knownRecipes()[ALT].Forge.known[9] and not ns.knownRecipes()[SANS], "recettes connues de GameData, par GUID")
local alt
for _, e in ipairs(ns.crafters()) do if e.key == ALT then alt = e end end
assert(alt and alt.name == "Alt" and alt.ranks.Forge == 50 and alt.known[9], "artisan lu dans GameData, prénom tiré de sa fiche")
assert(alt.ranks.Couture == 120, "métiers des persos (fiche de GameData), par la lib")
-- Mes autres persos (option « mes autres persos ») : leurs sacs, par la lib.
GameDataDB.recipes = { [1] = { name = "Fonte du bronze", output = 2841, reagents = { { id = 2840, qty = 1 } } } }
GameDataMarket = { ["6942-Alliance"] = { scanned = "hier", items = { [2840] = { tiers = { { price = 50, qty = 99 } } } } } }
local bronze = ns.nouveauProjet({ lines = { { id = 2841, qty = 6 } } })
local arbreAlts = ns.projetArbre(bronze, { alts = true, unlearned = true })
assert(arbreAlts.caseDe.I2840.have[3] == 4 and arbreAlts.caseDe.I2840.need == 2, "sacs d'un autre perso déduits")
assert(ns.texteHV() == "HV du hier" and ns.apportGameData() == nil, "avec GameData : la date de son scan, rien à réclamer")
GameDataDB.chars = {}
aucunReleve("avec GameData")
print("Handshake : recettes connues avec GameData OK")

-- Handshake seul (sans GameData) : tout vient du relevé de repli de la lib (le perso connecté, en mémoire : recettes
-- connues dans la fenêtre de métier, sacs, banque vue cette session), d'un fournisseur pour l'HV, jamais de HandshakeDB.
GameDataAPI = nil
-- Relevés sauvegardés par un Handshake d'avant : purgés (ADR 0001), données propres gardées.
HandshakeDB.recipes = { [1] = { name = "vieux relevé" } }
HandshakeDB.chars = { ["Vieux-Perso"] = { recipes = { Forge = { known = { [1] = 1 } } }, bags = { [2770] = 3 } } }
HandshakeDB.items, HandshakeDB.market = { [2770] = { name = "Minerai" } }, { ["6942-Alliance"] = { items = {} } }
ns.purgerAnciensReleves()
aucunReleve("sans GameData, purge")
assert(HandshakeDB.contracts and HandshakeDB.projets, "données propres gardées")
assert(not ns.recipes()[5] and not next(ns.knownRecipes()), "rien de relevé cette session")
UnitName = function() return "Belegard", "Marteaudefer" end
Enum = Enum or {}
C_TradeSkillUI = {
  GetBaseProfessionInfo = function() return { professionName = "Minage", skillLevel = 75, maxSkillLevel = 150 } end,
  GetAllRecipeIDs = function() return { 5, 6 } end,
  GetRecipeInfo = function(id) return { name = id == 5 and "Fonte du cuivre" or "Fonte du bronze", learned = id == 5, relativeDifficulty = 1 } end,
  GetRecipeSchematic = function(id) return { outputItemID = id == 5 and 2840 or 2841, quantityMin = 1, quantityMax = 1,
    reagentSlotSchematics = { { reagents = { { itemID = id == 5 and 2770 or 2840 } }, quantityRequired = 1, required = true } } } end,
}
C_Timer.After = function(_, fn) fn() end
libCadre.onEvent(libCadre, "TRADE_SKILL_LIST_UPDATE")
C_Timer.After = noop
-- Les noms des produits et composants des recettes relevées sont demandés au serveur ; arrivés, gardés en mémoire.
local demandes = {}
C_Item.RequestLoadItemDataByID = function(id) demandes[id] = true end
ns.recipes()
assert(demandes[2840] and demandes[2770] and demandes[2841], "noms des produits et composants demandés au serveur")
C_Item.RequestLoadItemDataByID = nil
C_Item.GetItemInfo = function(id) if id == 2840 then return "Barre de cuivre", "|Hitem:2840|h[Barre de cuivre]|h" end end
ns.rememberItem(2840)
C_Item.GetItemInfo = noop
assert(ns.recipes()[5] and ns.findItem("barre de cuivre") == 2840 and ns.findItem("Fonte du cuivre") == 2840, "relevé de repli, noms en mémoire")
assert(ns.knownRecipes()[UnitGUID("player")].Minage.known[5] and not ns.knownRecipes()[UnitGUID("player")].Minage.known[6], "recettes connues du perso")
local moi = ns.crafters()[1]
assert(moi.key == UnitGUID("player") and moi.ranks.Minage == 75 and moi.known[5], "artisan : mon perso, même sans sacs relevés")
-- Sacs (lus à l'instant) et banque (vue cette session) du perso connecté : par la lib, déduits du calcul.
Enum.BagIndex = { Backpack = 0, Bank = -1 }
local slots = { [0] = { { itemID = 2770, stackCount = 2 } }, [-1] = { { itemID = 2770, stackCount = 3 } } }
C_Container = { GetContainerNumSlots = function(b) return #slots[b] end, GetContainerItemInfo = function(b, i) return slots[b][i] end }
GetBuildInfo = function() return "1.16.1", "64000" end
libCadre.onEvent(libCadre, "BANKFRAME_OPENED")
local cuivre = ns.nouveauProjet({ lines = { { id = 2840, qty = 10 } } })
local arbreSeul = ns.projetArbre(cuivre, { bags = true, bank = true, alts = true })
local minerai = arbreSeul.caseDe.I2770
assert(minerai.have[1] == 2 and minerai.have[2] == 3 and minerai.have[3] == 0 and minerai.need == 5, "sacs et banque du perso, pas d'autres persos")
-- HV : ni GameData ni fournisseur, rien à acheter ; la fenêtre dit ce que GameData apporterait.
assert(minerai.unpriced and ns.market() == nil, "pas de prix de l'HV")
assert(ns.texteHV():find("GameData", 1, true) and ns.texteHV():find("Auctionator", 1, true), "HV : ce qui l'apporterait")
local apport = ns.apportGameData()
assert(apport and apport:find("rerolls", 1, true) and apport:find("banque", 1, true) and apport:find("HV", 1, true), "ce que GameData apporterait")
-- Avec Auctionator (fournisseur) : ses prix du jour, sans paliers ; l'HV n'est plus dans ce qui manque.
time = os.time
Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(_, id) return id == 2770 and 30 or nil end,
  GetAuctionAgeByItemID = function() return 0 end } } }
arbreSeul = ns.projetArbre(cuivre, { bags = true, bank = true })
assert(arbreSeul.caseDe.I2770.cost == 5 * 30 and ns.texteHV() == "prix de l'HV : Auctionator", "prix d'Auctionator")
assert(not ns.apportGameData():find("HV", 1, true), "fournisseur présent : GameData pour les rerolls et la banque")
Auctionator = nil
aucunReleve("sans GameData")
-- Réserve Classic : ajoutée pour les objets sans recette scannée, jamais par-dessus une recette scannée du même objet.
HandshakeClassicRecipes = { [9001] = { 2840, 1, 1, "Minage", "Barre de cuivre (Classic)", { 2770, 2 } },
  [9002] = { 4255, 1, 1, "Travail du cuir", "Armure verte en cuir", { 4234, 9 } } }
local merged = ns.recipes()
assert(merged[5] and not merged[9001], "barre de cuivre déjà scannée : la recette Classic ne la double pas")
assert(merged[9002] and merged[9002].output == 4255 and merged[9002].reagents[1].qty == 9, "armure verte en cuir : recette Classic")
HandshakeClassicRecipes = nil
local demo = ns.demoOrder("hasard")
assert(demo.name == "Essai : au hasard" and #demo.lines == 1 and demo.lines[1].id == 2841, "essai : le bronze (son cuivre se fabrique)")
assert(#ns.demoOrder().lines == 3 and ns.demoOrder("ceinture").lines[1].id == 10721, "essais choisis : le set, les ceintures")
print("Handshake : sans GameData OK")

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

-- Royaume, faction et maison de l'HV par la lib, qui les sonde (Handshake#27) : plus d'appel direct dans le code chargé ;
-- le diagnostic /handshake noms est remplacé par les sondes d'identité de la lib.
local lib27 = LibStub("LibCommune-1.0")
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
