-- Vérification hors jeu (non chargée par le TOC) : luajit Handshake/check.lua
-- Juste assez de l'API WoW pour le calcul et le texte. Les premiers tests jouent « GameData installé » (ses tables
-- globales servent de données) ; un test à la fin joue Handshake seul.
local noop = function() end
local stubMT = { __index = function() return noop end }
CreateFrame = function() return setmetatable({}, stubMT) end
SlashCmdList, StaticPopupDialogs, UISpecialFrames = {}, {}, {}
C_Timer = { After = noop, NewTicker = noop }
C_Item = { GetItemInfo = noop, GetItemIconByID = noop }
date, time = os.date, os.time
GetTime = function() return 0 end
GetRealmName, UnitFactionGroup = function() return "R" end, function() return "Alliance" end
GameDataDB, GameDataItems, GameDataMarket = { recipes = {}, chars = {} }, { items = {} }, {}
-- GameData installé : la lib commune lit ses recettes par GameDataAPI.recettesConnues (même forme que GameData).
GameDataAPI = { recettesConnues = function()
  local persos = {}
  for k, c in pairs(GameDataDB.chars) do persos[k] = c.recipes end
  return { recettes = GameDataDB.recipes, persos = persos }
end }
HandshakeDB = { chars = {}, items = {}, market = {} }
-- La lib commune (dépôt voisin, chargée avant Handshake comme dans le jeu) ; son cadre garde son script d'événements.
local libCadre
CreateFrame = function() local f = setmetatable({}, stubMT); f.SetScript = function(self, _, fn) self.onEvent = fn end; libCadre = f; return f end
assert(loadfile("LibCommune/LibStub.lua"))()
assert(loadfile("LibCommune/LibCommune.lua"))()
CreateFrame = function() return setmetatable({}, stubMT) end
assert(loadfile("LibCommune/Interface.lua"))() -- fenêtres, montants, noms d'objets
assert(loadfile("LibCommune/Capture.lua"))()
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
local MOI = ns.charKey()
local TOUT = { unlearned = true } -- options de calcul : toutes les recettes, aucun stock
local function donnees(d) -- d.sacs / d.banque = { [id] = nombre }, d.persos = fiches GameData des autres persos
  local function sac(t)
    local items = {}
    for id, n in pairs(t or {}) do items[#items + 1] = { id = id, count = n } end
    return { b = { items = items } }
  end
  GameDataMarket = { ["R-Alliance"] = { scanned = "test", items = d.hv } }
  GameDataDB.recipes = d.recettes
  GameDataDB.chars = d.persos or {}
  GameDataDB.chars[MOI] = { bank = sac(d.banque) }
  ns.containers = function() return sac(d.sacs) end
end
local realContainers = ns.containers
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
  persos = { ["Bel-R"] = { recipes = { Forge = { rank = 164, known = { [1] = "easy" } } } }, ["Alt-R"] = { recipes = { Minage = { rank = 90, known = {} } } } } })
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
ns.containers, GameDataDB.chars = realContainers, {}
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

-- Reprise des suivis de GameData à la première ouverture du module : ils deviennent un projet.
GameDataDB.craft_targets, GameDataDB.craft_options = { { id = 7963, qty = 1 } }, { bags = true }
HandshakeDB = nil
local loader
CreateFrame = function() return setmetatable({ SetScript = function(_, _, fn) loader = fn end }, stubMT) end
assert(loadfile("Handshake/Commande.lua"))("Handshake", ns)
loader(nil, "ADDON_LOADED", "Handshake")
assert(select(2, ns.numeroProjet()) == 1 and ns.projetCourant().lines[1].id == 7963 and HandshakeDB.options.bags, "suivis repris")
assert(GameDataDB.craft_targets == nil, "plus rien dans GameData")
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

-- Contrats entre deux joueurs simulés : Belegard (artisan) et Bob (client), chacun sa base.
local REALM = "CAMWOWEU4Realm8PvP"
local BEL, BOB = "Belegard-" .. REALM, "Bob-" .. REALM
GetNormalizedRealmName = function() return REALM end
local clock = 1795000000
GetServerTime = function() return clock end
local bases = { [BEL] = { contracts = {} }, [BOB] = { contracts = {} } }
local current, notes, wire = BEL, {}, {}
local function as(who) current = who; HandshakeDB = bases[who] end
UnitName = function() return (current:match("^[^%-]+")) end
local GBEL, GBOB, GMAL = "Player-1-0000BEEF", "Player-1-00000B0B", "Player-1-0000BAD0"
UnitGUID = function(u) if u == "player" then return current == BEL and GBEL or GBOB end end
local function P(origin, id, v, parent, client, cg, artisan, ag, m, o, d)
  return table.concat({ "P", "2", origin, id, v, parent, client, cg, artisan, ag, m, o, d }, "|")
end
local MAL = "Mallory-" .. REALM
ns.ctNotify = function(t) notes[#notes + 1] = current .. " : " .. t end
-- Le réseau : ce qu'envoie l'un arrive chez l'autre (on peut aussi intercepter pour jouer l'attaquant).
C_ChatInfo = { SendAddonMessage = function(prefix, text, channel, target)
  wire[#wire + 1] = text
  local from = current
  as(ns.fullName(target)); ns.ctOnAddon(prefix, text, channel, from); as(from)
end }
local function inject(from, to, body) -- un message forgé, en un morceau
  local back = current
  as(to); ns.ctOnAddon("Handshake", "1/1|" .. body, "WHISPER", from); as(back)
end
local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

assert(ns.fullName("Bob") == BOB and ns.fullName("Bob", "CAMWOW EU4 Realm 8 PvP") == BOB, "noms normalisés")
assert(ns.fullName("Bob|cff") == nil and ns.fullName("") == nil, "nom piégé refusé")
assert(ns.ctHash("abc") ~= ns.ctHash("abd") and #ns.ctHash("abc") == 16, "empreinte 64 bits")

-- Belegard propose : Bob fournit 36 minerais (caution 150 pc l'unité), Belegard livre une claymore payée 5400 + 4000.
as(BEL)
local terms = { origin = BEL, id = "1795000000", v = "1", parent = "0", client = BOB, artisan = BEL, clientGUID = "0", artisanGUID = GBEL,
  m = { { id = 3858, qty = 36, unit = 150 } }, o = { { id = 7963, qty = 1, unit = 9400 } }, d = clock + 3 * 86400 }
ns.ctPropose(terms)
as(BOB)
local k = BEL .. "#1795000000"
local atBob = HandshakeDB.contracts[k]
assert(atBob and atBob.status == "a_signer" and atBob.author == BEL, "Bob a la proposition")
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

-- Attaques sur la négociation (SECURITE.md).
local before = count(bases[BOB].contracts)
-- n° 2 : Mallory propose au nom de Belegard (origine ≠ expéditeur).
inject(MAL, BOB, P(BEL, "1795000001", "1", "0", BOB, "0", BEL, GBEL, "", "7963:1:1", clock + 3600))
-- n° 3 : rôles qui ne sont pas {moi, l'expéditeur}.
inject(MAL, BOB, P(MAL, "1795000002", "1", "0", "Carl-" .. REALM, "0", MAL, GMAL, "", "7963:1:1", clock + 3600))
-- n° 14 : nombres piégés, zéros de tête, liste pas triée, doublon, quantité énorme.
for _, bad in ipairs({ "0x10:1:1", "7963:01:1", "7963:1:1,3858:1:1", "7963:1:1,7963:1:1", "7963:5000:1", "7963:1:-1", "7963:1:1e9" }) do
  inject(MAL, BOB, P(MAL, "1795000003", "1", "0", BOB, "0", MAL, GMAL, "", bad, clock + 3600))
end
-- n° 11 : échéance absurde ; n° 22 : protocole inconnu (l'ancien « 1 » aussi) ; champ en trop.
inject(MAL, BOB, P(MAL, "1795000004", "1", "0", BOB, "0", MAL, GMAL, "", "7963:1:1", clock + 99 * 86400))
inject(MAL, BOB, (P(MAL, "1795000005", "1", "0", BOB, "0", MAL, GMAL, "", "7963:1:1", clock + 3600):gsub("^P|2|", "P|1|")))
inject(MAL, BOB, P(MAL, "1795000006", "1", "0", BOB, "0", MAL, GMAL, "", "7963:1:1", clock + 3600) .. "|x")
-- Identité : sans son propre identifiant, avec un identifiant qui n'est pas le mien, avec un identifiant piégé.
inject(MAL, BOB, P(MAL, "1795000007", "1", "0", BOB, "0", MAL, "0", "", "7963:1:1", clock + 3600))
inject(MAL, BOB, P(MAL, "1795000008", "1", "0", BOB, GMAL, MAL, GMAL, "", "7963:1:1", clock + 3600))
inject(MAL, BOB, P(MAL, "1795000009", "1", "0", BOB, "0", MAL, "Player-1-|cff00", "", "7963:1:1", clock + 3600))
-- Mallory annonce l'identifiant de Belegard : le serveur (son chuchotement) a donné le vrai à Bob.
ns.knownGUID[MAL] = GMAL
inject(MAL, BOB, P(MAL, "1795000010", "1", "0", BOB, "0", MAL, GBEL, "", "7963:1:1", clock + 3600))
assert(count(bases[BOB].contracts) == before, "aucune proposition piégée enregistrée")
-- n° 19 : un tiers refuse le contrat signé de Bob et Belegard.
inject(MAL, BOB, "R|2|" .. BEL .. "|1795000000|2")
-- n° 5/P5 : une v3 envoyée après la signature ne change rien.
inject(BEL, BOB, P(BEL, "1795000000", "3", atBel.hash, BOB, GBOB, BEL, GBEL, "3858:36:1", "7963:1:9400", clock + 3600))
local signed = bases[BOB].contracts[k]
assert(signed.status == "signe" and signed.v == "2" and ns.ctTotal(signed.m) == 36 * 167, "contrat signé figé")
-- n° 12 (inondation) : au-delà de 3 propositions en attente du même joueur, ignoré (témoin : les 3 premières passent).
for n = 1, 5 do
  inject(MAL, BOB, P(MAL, "17950001" .. n, "1", "0", BOB, "0", MAL, GMAL, "", "7963:1:1", clock + 3600))
end
assert(count(bases[BOB].contracts) == before + 3, "3 propositions en attente au plus")
as(BOB); ns.ctOnAddon("Handshake", "1/99|P", "WHISPER", "Mallory-" .. REALM)
print("Handshake : attaques sur la négociation repoussées OK")

-- Échanges. Étape 1 vue par Bob (client) : il donne 20 minerais, Belegard 20 × 167 (6000/36 arrondi à l'unité).
as(BOB)
local unit = signed.m[1].unit
local function snap(partner, give, get) return { partner = partner, guid = GBEL, give = give, get = get } end
local s1 = snap(BEL, { items = { [3858] = 20 }, money = 0 }, { items = {}, money = 20 * unit })
assert(ns.ctEvaluate(signed, BOB, s1, clock).ok, "lot 1 équilibré : conforme")
-- n° 45 : caution trop faible pour ce qui est donné.
local short = ns.ctEvaluate(signed, BOB, snap(BEL, { items = { [3858] = 20 }, money = 0 }, { items = {}, money = 19 * unit }), clock)
assert(not short.ok and short.short == unit, "il manque une unité de caution")
-- n° 30/33 : objet hors contrat donné, trop donné.
assert(not ns.ctEvaluate(signed, BOB, snap(BEL, { items = { [3858] = 40 }, money = 0 }, { items = {}, money = 40 * unit }), clock).ok, "40 > 36 : non conforme")
assert(not ns.ctEvaluate(signed, BOB, snap(BEL, { items = { [7963] = 1 }, money = 0 }, { items = {}, money = 99999 }), clock).ok, "objet hors contrat donné")
-- n° 31/26 : autre partenaire, autre personnage (GUID), contrat échu, objet illisible.
assert(not ns.ctEvaluate(signed, BOB, snap("Bélegard-" .. REALM, s1.give, s1.get), clock).ok, "homonyme")
assert(not ns.ctEvaluate(signed, BOB, { partner = BEL, guid = "x", unknown = true, give = s1.give, get = s1.get }, clock).ok, "illisible")
assert(not ns.ctEvaluate(signed, BOB, s1, clock + 4 * 86400).ok, "échu")
ns.ctRecord(signed, BOB, s1, clock)
assert(signed.peer.guid == GBEL and signed.peer.verified and signed.got[3858] == nil and signed.gave[3858] == 20 and signed.net == 0, "lot 1 inscrit")
assert(not ns.ctEvaluate(signed, BOB, { partner = BEL, guid = "Player-1-AUTRE", give = s1.give, get = s1.get }, clock).ok, "même nom, autre identifiant")
local renamed = ns.ctEvaluate(signed, BOB, { partner = "Belegarde-" .. REALM, guid = GBEL, give = { items = { [3858] = 16 }, money = 0 },
  get = { items = {}, money = 16 * unit } }, clock)
assert(renamed.ok and renamed.warnings[1]:find("nom a changé"), "même identifiant, nouveau nom : conforme, signalé")
-- n° 46 : « c'est le lot 2/2, donne tout » — le reste dû vient du registre : 16 au plus.
assert(not ns.ctEvaluate(signed, BOB, snap(BEL, { items = { [3858] = 20 }, money = 0 }, { items = {}, money = 20 * unit }), clock).ok, "plus que les 16 restants")
ns.ctRecord(signed, BOB, snap(BEL, { items = { [3858] = 16 }, money = 0 }, { items = {}, money = 16 * unit }), clock)
-- Étape 2 : la claymore contre 9400 ; n° 35 : sans l'objet, payer est non conforme.
assert(not ns.ctEvaluate(signed, BOB, snap(BEL, { items = {}, money = 9400 }, { items = {}, money = 0 }), clock).ok, "payer sans recevoir")
local s2 = snap(BEL, { items = {}, money = 9400 }, { items = { [7963] = 1 }, money = 0 })
assert(ns.ctEvaluate(signed, BOB, s2, clock).ok, "livraison conforme")
ns.ctRecord(signed, BOB, s2, clock)
assert(signed.status == "clos" and signed.net == 0, "contrat clos, solde nul")
print("Handshake : échanges vérifiés et contrat clos OK")

-- Demande (CONCEPTION.md) : Bob veut une claymore (30 minerais + 4 cuirs lourds), il apporte le cuir (Ctrl+clic),
-- offre 3 po. Contrat v1 : caution = prix de marché du cuir seulement ; la claymore = sa part de caution + l'offre.
as(BOB)
GetRealmName, UnitFactionGroup = function() return "R" end, function() return "Alliance" end
GameDataMarket = { ["R-Alliance"] = { scanned = "hier", items = { [3858] = { tiers = { { price = 200, qty = 999 } } },
  [4234] = { tiers = { { price = 500, qty = 999 } } }, [7963] = { tiers = { { price = 99999, qty = 9 } } } } } }
GameDataDB.recipes = { [1] = { name = "Claymore", output = 7963, reagents = { { id = 3858, qty = 30 }, { id = 4234, qty = 4 } } } }
GameDataItems.items[4234] = { name = "Cuir lourd", link = link(4234, "Cuir lourd") }
HandshakeDB.projets = {}
local demande = ns.nouveauProjet({ player = "Belegard", tip = 30000, lines = { { id = 7963, qty = 1 } } })
ns.projetApport(demande, 4234, true)
local dres = ns.projetDemande(demande)
local brought = ns.demandeApports(dres)
assert(#brought == 1 and brought[1].id == 4234 and brought[1].qty == 4, "apport : le cuir, case entière")
assert(dres.roots[1].how == "fabriquer" and dres.roots[1].cost == 30 * 200, "part de l'artisan : le minerai seulement")
local v1 = ns.ctFromDemande(ns.projetCommande(demande), 3)
assert(v1.client == BOB and v1.artisan == BEL and v1.clientGUID == GBOB, "moi client, l'autre artisan")
assert(#v1.m == 1 and v1.m[1].id == 4234 and v1.m[1].unit == 500 and v1.o[1].unit == 4 * 500 + 30000, "caution sur l'apport + offre")
assert(ns.ctParse(ns.ctCanonical(v1), BOB, BEL, clock), "ce qu'on envoie passe notre propre lecture stricte")
-- Sans apport : vente simple (pas de caution).
local simple = ns.ctFromDemande(ns.projetCommande(ns.nouveauProjet({ player = "Belegard", tip = 30000, lines = { { id = 7963, qty = 1 } } })), 3)
assert(#simple.m == 0 and simple.o[1].unit == 30000, "vente simple")
-- En clair : « Commande : 1x[Claymore] · j'apporte 4x[Cuir lourd] · offre 3 po », relu à l'identique.
popups = {}
local realWhisper = ns.whisper
ns.whisper = function(msg) ns.onChat("CHAT_MSG_WHISPER", msg, BOB) end
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

-- Je réponds (l'artisan) : Belegard ouvre la demande dans son arbre, demande aussi le minerai et chiffre 5 po.
ns.ctPropose(v1)
as(BEL)
local key1 = ns.ctKey(v1)
local recu = HandshakeDB.contracts[key1]
assert(recu and ns.ctStatus(recu) == "a_signer", "demande reçue par l'artisan")
local rep = ns.projetReponse(recu)
local function reponse1() return ns.projetCommande(rep) end -- la réponse elle-même : sa commande « tout le projet »
assert(rep.reponse == key1 and rep.apports[4234] and reponse1().tip == 30000 and rep.lines[1].id == 7963 and reponse1().player == BOB, "sa demande dans mon arbre")
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

-- Projets : un choix de case appartient à son projet (CONTEXT.md) ; ni l'arbre ni le contrat d'un autre projet n'en
-- dépendent. Marteau = 10 bronzes + 1 perle, cuirasse = 20 bronzes ; le bronze se fond (cuivre + étain, ×2).
as(BOB)
local function tiers(prix)
  local t = {}
  for id, p in pairs(prix) do t[id] = { tiers = { { price = p, qty = 999 } } } end
  return t
end
GameDataMarket = { ["R-Alliance"] = { scanned = "hier", items = tiers({ [2770] = 10, [2771] = 10, [5500] = 500, [2841] = 100, [5541] = 99999, [2870] = 99999 }) } }
GameDataDB.recipes = {
  [1] = { name = "Marteau", output = 5541, profession = "Forge", reagents = { { id = 2841, qty = 10 }, { id = 5500, qty = 1 } } },
  [2] = { name = "Cuirasse", output = 2870, profession = "Forge", reagents = { { id = 2841, qty = 20 } } },
  [3] = { name = "Fonte du bronze", output = 2841, made_min = 2, profession = "Minage", reagents = { { id = 2770, qty = 1 }, { id = 2771, qty = 1 } } },
}
do
  local function lignes() return { { id = 5541, qty = 1 }, { id = 2870, qty = 1 } } end
  local pa = ns.nouveauProjet({ player = "Belegard", tip = 8000, lines = lignes() })
  local pb = ns.nouveauProjet({ player = "Belegard", tip = 8000, lines = lignes() })
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
  ns.projetArtisan(pb, "Belegard", i)
  ns.projetOffre(pb, 8000, i)
  assert(termes(pb, i) == "2841:30:100,5500:1:500 / 2870:1:6000,5541:1:5500", termes(pb, i))
  assert(termes(pb) == avantB, "la commande « tout le projet » n'a pas bougé")
end
print("Handshake : choix de case propres à chaque projet OK")

-- Les commandes d'un projet se lisent sur l'arbre de la demande (aucun stock déduit, toutes les recettes) : mes stocks
-- ne réduisent jamais la part de l'artisan (CONCEPTION.md). Avec un marteau dans mes sacs et le stock coché, ce que livre
-- le minage = le bronze que la forge reçoit en apport.
as(BOB)
local sacsAvant, optionsAvant = ns.containers, HandshakeDB.options
ns.containers = function() return { b = { items = { { id = 5541, count = 1 } } } } end
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
ns.containers, HandshakeDB.options = sacsAvant, optionsAvant
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
  ns.projetArtisan(p, "Belegard", i)
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
  assert(envoyee == "2870x1,5541x1 / 2841 / 9000 / Belegard", envoyee)
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
  ns.whisper = function(msg) ns.onChat("CHAT_MSG_WHISPER", msg, BOB) end
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

-- Fiche du contrat : besoins gonflés signalés (n° 12), perte maximale de chaque côté (P8).
C_CurrencyInfo = { GetCoinTextureString = function(c) return c .. "pc" end }
GetRealmName, UnitFactionGroup = function() return "R" end, function() return "Alliance" end
GameDataMarket = { ["R-Alliance"] = { scanned = "hier", items = { [3858] = { tiers = { { price = 200, qty = 999 } } } } } }
GameDataDB.recipes = { [1] = { name = "Claymore", output = 7963, reagents = { { id = 3858, qty = 30 } } } }
as(BOB)
local fiche = ns.ctDescribe(signed, BOB)
assert(fiche:find("36 demandés, la recette en consomme 30"), "minerai gonflé signalé")
assert(fiche:find("Si l'artisan disparaît après l'étape 1 : tu perds au plus 1188pc"), "perte max du client : 36×200 − 6012")
as(BEL)
assert(ns.ctDescribe(bases[BEL].contracts[k], BEL):find("tu es l'ARTISAN"), "rôle affiché depuis mon côté")
print("Handshake : fiche du contrat OK")

-- Noms à la Forever : prénom + nom de famille (avec tirets), royaume après le dernier tiret.
assert(ns.fullName("Aedi Triple-Forgé-" .. REALM) == "Aedi-" .. REALM, "nom de famille à tiret, royaume au bout")
assert(ns.fullName("Aedi Triple-Forgé") == "Aedi-" .. REALM, "sans royaume : le tiret est celui du nom de famille")
assert(ns.fullName("Riwanon", "Kerys") == "Riwanon-Kerys" and ns.fullName("Riwanon") == "Riwanon-" .. REALM)
assert(ns.fullName("Bob-AutreRoyaume") == "Bob-AutreRoyaume", "autre royaume")
UnitName = function() return "Belegard", "Marteaudefer" end
assert(ns.me() == BEL, "moi = prénom + royaume, pas le nom de famille")
print("Handshake : noms à la Forever OK")

-- Avec GameData : les recettes connues de tous ses persos, par la lib commune.
GameDataDB.chars = { ["Alt Dupont-R"] = { recipes = { Forge = { rank = 50, max = 75, known = { [9] = "easy" } } } }, ["Sans-R"] = {} }
assert(ns.knownRecipes()["Alt Dupont-R"].Forge.known[9] and not ns.knownRecipes()["Sans-R"], "recettes connues de GameData")
local alt
for _, e in ipairs(ns.crafters()) do if e.key == "Alt Dupont-R" then alt = e end end
assert(alt and alt.name == "Alt" and alt.ranks.Forge == 50 and alt.known[9], "artisan lu dans GameData")
GameDataDB.chars = {}
print("Handshake : recettes connues avec GameData OK")

-- Handshake seul (sans GameData) : les recettes viennent du relevé de repli de la lib (fenêtre de métier ouverte),
-- jamais écrites dans HandshakeDB ; les autres données (objets, HV) restent dans ses propres tables.
GameDataAPI = nil
-- Relevés sauvegardés par un Handshake d'avant (recettes, recettes connues des persos) : purgés au chargement (ADR 0001).
HandshakeDB.recipes = { [1] = { name = "vieux relevé" } }
HandshakeDB.chars = { ["Vieux-Perso"] = { recipes = { Forge = { known = { [1] = 1 } } }, bags = { [2770] = 3 } } }
ns.purgerAnciensReleves()
assert(HandshakeDB.recipes == nil and HandshakeDB.chars["Vieux-Perso"].recipes == nil, "anciens relevés de recettes purgés")
assert(HandshakeDB.chars["Vieux-Perso"].bags[2770] == 3, "le reste des persos (sacs) n'est pas touché")
HandshakeDB.chars = {}
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
-- Les noms des produits et composants des recettes relevées sont demandés au serveur (comme l'ancien relevé de Handshake).
local demandes = {}
C_Item.RequestLoadItemDataByID = function(id) demandes[id] = true end
ns.recipes()
assert(demandes[2840] and demandes[2770] and demandes[2841], "noms des produits et composants demandés au serveur")
C_Item.RequestLoadItemDataByID = nil
HandshakeDB.items = { [2840] = { name = "Barre de cuivre" } }
assert(ns.recipes()[5] and ns.findItem("barre de cuivre") == 2840 and ns.findItem("Fonte du cuivre") == 2840, "relevé de repli")
assert(ns.knownRecipes()[ns.charKey()].Minage.known[5] and not ns.knownRecipes()[ns.charKey()].Minage.known[6], "recettes connues du perso")
assert(HandshakeDB.recipes == nil, "rien écrit dans HandshakeDB.recipes")
assert(next(HandshakeDB.chars) == nil, "rien écrit dans HandshakeDB.chars (recettes connues comprises)")
local moi = ns.crafters()[1]
assert(moi.key == ns.charKey() and moi.ranks.Minage == 75 and moi.known[5], "artisan : mon perso, même sans sacs relevés")
local agg = ns.aggregate({ { id = 2770, count = 20, buyout = 2000 }, { id = 2770, count = 5, buyout = 400 } })
assert(agg[2770].min == 80 and agg[2770].qty == 25 and agg[2770].tiers[1].price == 80, "HV agrégé")
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

-- Identité complète : prénom, nom de famille (lu au serveur, jamais dans un message), royaume, identifiant.
GetRealmName = function() return "CAMWOW EU4 Realm 8 PvP" end
UnitExists, UnitIsPlayer = function() return true end, function() return true end
UnitGUID = function(u) return u == "target" and GBOB or GBEL end
UnitName = function(u) if u == "target" then return "Bob", "Kerys-de|cffBois" end return "Belegard", "Marteaudefer" end
ns.learnUnit("target")
assert(ns.identity(BOB, GBOB) == "Bob Kerys-de||cffBois — CAMWOW EU4 Realm 8 PvP — " .. GBOB, "nom de famille lu, codes échappés")
assert(ns.myIdentity() == "Belegard Marteaudefer — CAMWOW EU4 Realm 8 PvP — " .. GBEL)
assert(ns.identity("Carl-AutreRoyaume", nil) == "Carl — AutreRoyaume — identifiant inconnu")
print("Handshake : identité complète OK")

-- Destinataire d'un chuchotement : prénom seul dans mon royaume (Forever lit « Prénom-Royaume » comme un nom de famille).
assert(ns.whisperTarget(BOB) == "Bob" and ns.whisperTarget("Bob") == "Bob" and ns.whisperTarget("Bob-AutreRoyaume") == "Bob-AutreRoyaume")
print("Handshake : destinataire des chuchotements OK")
