-- Handshake, les contrats : format, signature, registre, verdict. Rien d'affiché ici (ContratUI.lua,
-- Echange.lua), tout est testé hors jeu (check.lua). Les règles viennent du modèle de menace : SECURITE.md.
--
-- Un contrat = deux ventes protégées.
--   m : composants que le client fournit, { id, qty, unit } — unit = caution par unité, payée par l'artisan.
--   o : objets fabriqués, { id, qty, unit } — unit = ce que le client paie par objet livré (caution rendue + prix).
-- Chaque échange est équilibré par ces valeurs unitaires (P1) : pas de prorata, pas d'arrondi, jamais de crédit.
-- Échéance dépassée : chacun garde ce qu'il a, plus aucun échange conforme.
--
-- Sur le fil (messages d'addon, chuchotement uniquement), champs à position fixe, rien de libre (P4) :
--   P|2|origine|id|version|empreinte parente|client|GUID client|artisan|GUID artisan|m|o|échéance
--        m, o = "id:qté:unité,…" triés par id ; GUID = identifiant du perso (« Player-1234-0A1B2C3D »), « 0 » si inconnu
--   A|2|origine|id|version|empreinte|GUID de celui qui accepte        (accepte cette version précise)
--   R|2|origine|id|version                  (refuse)       X|2|origine|id|version   (retire sa proposition)
-- Identité : le contrat retient l'identifiant du perso d'en face (c.peer), pas seulement son nom. Un identifiant
-- annoncé par l'autre addon n'est cru que confirmé par le serveur : celui joint à ses chuchotements, la fiche
-- identifiant -> nom du client, ou à défaut le premier échange (identifiant ET nom doivent alors correspondre).
-- Chaque message part en morceaux « i/n| » (≤ 10, recollés par expéditeur, oubliés après 30 s).
local _, ns = ...

local PREFIX = "Handshake"
ns.PREFIX = PREFIX
local MAX_LINES, MAX_QTY, MAX_UNIT, MAX_TOTAL = 30, 1000, 1000000000, 2147483647
local MAX_DAYS, MAX_PENDING = 30, 3

-- La base des contrats (le mode debug peut en substituer une : celle du joueur fictif).
function ns.ctStore() return (ns.debugStore and ns.debugStore()) or HandshakeDB.contracts end
local store = ns.ctStore
local function now() return GetServerTime() end

---------------------------------------------------------------------------------------------------
-- Noms : toujours « Prénom-Royaume », royaume sans espace ni tiret (forme des messages d'addon).
-- Sur Forever les persos ont un nom de famille (« Aedi Triple-Forgé ») : UnitName renvoie prénom, nom de famille, et
-- un nom de famille peut contenir des tirets. On garde le prénom ; le royaume est ce qui suit le DERNIER tiret, et
-- seulement s'il n'y a pas d'espace (sinon ce tiret peut être celui du nom de famille) ou si c'est notre royaume.
-- Un homonyme (même prénom) ne gagne rien : chaque échange est équilibré (P1), et le GUID est figé au 1er échange.
local NAME = "^[^%-|,:%s%c]+%-[^%-|,:%s%c]+$"
function ns.fullName(name, realm)
  if type(name) ~= "string" or name == "" then return nil end
  local mine = (GetNormalizedRealmName and GetNormalizedRealmName() or ""):gsub("[%s%-]", "")
  if not realm then
    local before, after = name:match("^(.+)%-([^%-]+)$")
    if after and (not name:find("%s") or after:gsub("%s", "") == mine) then name, realm = before, after end
  end
  name = name:match("^[^%s%-]+")
  if not name then return nil end
  realm = (realm and realm ~= "") and realm:gsub("[%s%-]", "") or mine
  local full = name .. "-" .. realm
  return full:match(NAME) and full or nil
end
function ns.me() return ns.fullName((UnitName("player"))) end

-- À qui adresser un chuchotement : le prénom seul pour quelqu'un de mon royaume. Sur Forever, « Prénom-Royaume » est
-- lu « Prénom NomDeFamille » (le jeu a répondu « Aucun joueur nommé 'Testeur CAMWOWEU4Realm8PvP' », 18/11/2026).
-- ponytail: un autre royaume garde « Prénom-Royaume », à vérifier le jour où on joue entre royaumes
function ns.whisperTarget(name)
  local full = ns.fullName(name)
  if not full then return name end
  local first, realm = full:match("^([^%-]+)%-(.+)$")
  local mine = (GetNormalizedRealmName and GetNormalizedRealmName() or ""):gsub("[%s%-]", "")
  return realm == mine and first or full
end
function ns.myGUID() return UnitGUID("player") end

-- Identifiants appris de sources serveur : l'identifiant que le jeu joint à chaque chuchotement reçu.
local GUID = "^Player%-%d+%-%x+$"
ns.knownGUID = {}
function ns.learnGUID(name, guid)
  if name and type(guid) == "string" and guid:match(GUID) then ns.knownGUID[name] = guid end
end
-- Nom de famille : lu au serveur sur les persos qu'on voit (cible, groupe, survol, échange), rangé par identifiant ;
-- jamais pris dans un message de l'autre addon (P4 : aucun texte libre ne voyage).
ns.surnames = {}
function ns.learnUnit(unit)
  if not (UnitExists(unit) and UnitIsPlayer(unit)) then return end
  local guid, _, surname = UnitGUID(unit), UnitName(unit)
  if type(guid) == "string" and guid:match(GUID) and type(surname) == "string" and surname ~= "" and #surname <= 40 then
    ns.surnames[guid] = surname
  end
end
-- « Prénom Nom — Royaume — identifiant » pour l'affichage.
function ns.identity(nameRealm, guid, surname)
  local first, realm = (nameRealm or "?"):match("^([^%-]+)%-?(.*)$")
  surname = surname or (guid and ns.surnames[guid])
  local mine = (GetNormalizedRealmName and GetNormalizedRealmName() or ""):gsub("[%s%-]", "")
  local shown = (realm == mine or realm == "") and GetRealmName() or realm
  return (("%s%s — %s — %s"):format(first, surname and (" " .. surname) or "", shown, guid or "identifiant inconnu"):gsub("|", "||"))
end
function ns.myIdentity()
  local _, surname = UnitName("player")
  return ns.identity(ns.me(), ns.myGUID(), surname)
end

-- Un identifiant annoncé pour name : "ok" (confirmé par le serveur), "faux" (le serveur dit autre chose), "inconnu".
function ns.ctCheckClaim(name, guid)
  local known = ns.knownGUID[name]
  if known then return known == guid and "ok" or "faux" end
  if GetPlayerInfoByGUID then
    local _, _, _, _, _, gname, grealm = GetPlayerInfoByGUID(guid)
    if type(gname) == "string" and gname ~= "" then
      return ns.fullName(gname, grealm ~= "" and grealm or nil) == name and "ok" or "faux"
    end
  end
  return "inconnu"
end

-- /handshake noms : comment ce client et ce serveur écrivent les noms (pour vérifier ce qui précède en jeu).
ns.rawSenders = {}
function ns.namesDiagnostic()
  local a, b = UnitName("player")
  print(("Handshake — UnitName(player) = %s | %s ; UnitFullName = %s | %s ; royaume normalisé = %s ; moi = %s")
    :format(tostring(a), tostring(b), tostring((UnitFullName("player"))), tostring(select(2, UnitFullName("player"))),
      tostring(GetNormalizedRealmName()), tostring(ns.me())))
  if UnitExists("target") and UnitIsPlayer("target") then
    local t1, t2 = UnitName("target")
    print(("  cible : UnitName = %s | %s ; GetUnitName(true) = %s ; lu comme %s"):format(tostring(t1), tostring(t2),
      tostring(GetUnitName("target", true)), tostring(ns.fullName(t1))))
  end
  for kind, s in pairs(ns.rawSenders) do print(("  dernier expéditeur (%s) : « %s » lu comme %s"):format(kind, s, tostring(ns.fullName(s)))) end
end
function ns.other(c, me) return c.client == me and c.artisan or c.client end

---------------------------------------------------------------------------------------------------
-- Empreinte : deux FNV-1a 32 bits (le texte, puis le texte retourné) = 64 bits. Elle constate qu'on a signé la
-- même chose ; la sécurité n'en dépend pas (chacun vérifie sa propre copie).
local function fnv(s)
  local h = 2166136261
  for i = 1, #s do
    h = bit.bxor(h, s:byte(i)) % 4294967296
    h = ((h % 256) * 16777216 + h * 403) % 4294967296 -- h × 16777619 modulo 2³², sans dépasser 2⁵³
  end
  return h
end
function ns.ctHash(s) return ("%08x%08x"):format(fnv(s), fnv(s:reverse())) end

local function listText(list)
  local t = {}
  for i, l in ipairs(list) do t[i] = l.id .. ":" .. l.qty .. ":" .. l.unit end
  return table.concat(t, ",")
end
function ns.ctCanonical(c)
  return table.concat({ "P", "2", c.origin, c.id, c.v, c.parent, c.client, c.clientGUID, c.artisan, c.artisanGUID,
    listText(c.m), listText(c.o), c.d }, "|")
end
function ns.ctTotal(list)
  local s = 0
  for _, l in ipairs(list) do s = s + l.qty * l.unit end
  return s
end

---------------------------------------------------------------------------------------------------
-- Lecture stricte (P3) : champs à position fixe, entiers sans zéro de tête, bornes, listes triées sans doublon.
local function int(s, maxLen, lo, hi)
  if type(s) ~= "string" or not s:match("^%d+$") or #s > maxLen then return nil end
  local n = tonumber(s)
  if tostring(n) ~= s or n < lo or n > hi then return nil end
  return n
end
local function parseList(s)
  local out, last = {}, -1
  if s == "" then return out end
  for part in (s .. ","):gmatch("([^,]*),") do
    local a, b, u = part:match("^(%d+):(%d+):(%d+)$")
    local id, qty, unit = int(a, 7, 1, 9999999), int(b, 4, 1, MAX_QTY), int(u, 10, 0, MAX_UNIT)
    if not (id and qty and unit) or id <= last or #out >= MAX_LINES then return nil end
    last, out[#out + 1] = id, { id = id, qty = qty, unit = unit }
  end
  return out
end
local function fields(body)
  local f = {}
  for x in (body .. "|"):gmatch("([^|]*)|") do f[#f + 1] = x end
  return f
end

-- Une proposition reçue de sender, adressée à me. Renvoie le contrat (forme locale) ou nil, raison.
function ns.ctParse(body, sender, me, t)
  local f = fields(body)
  if f[1] ~= "P" or #f ~= 13 or f[2] ~= "2" then return nil, "format" end
  local c = { origin = f[3], id = f[4], v = int(f[5], 2, 1, 99), parent = f[6], client = f[7], clientGUID = f[8],
    artisan = f[9], artisanGUID = f[10], m = parseList(f[11]), o = parseList(f[12]), d = int(f[13], 12, 0, 9e11) }
  if not (c.v and c.m and c.o and c.d) or #c.o == 0 then return nil, "champs" end
  if not (c.id:match("^%d+$") and #c.id <= 12) then return nil, "id" end
  if not (c.parent == "0" or c.parent:match("^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$")) then return nil, "parent" end
  for _, k in ipairs({ "origin", "client", "artisan" }) do
    if not c[k]:match(NAME) then return nil, "nom" end
  end
  if c.client == c.artisan or not ((c.client == me and c.artisan == sender) or (c.artisan == me and c.client == sender)) then
    return nil, "parties"
  end
  if c.origin ~= c.client and c.origin ~= c.artisan then return nil, "origine" end
  for _, g in ipairs({ c.clientGUID, c.artisanGUID }) do
    if not (g == "0" or (#g <= 40 and g:match(GUID))) then return nil, "identifiant" end
  end
  local senderGUID, myField = c.client == sender and c.clientGUID or c.artisanGUID, c.client == me and c.clientGUID or c.artisanGUID
  if senderGUID == "0" then return nil, "identifiant de l'expéditeur manquant" end
  if myField ~= "0" and myField ~= ns.myGUID() then return nil, "ce n'est pas ton identifiant" end
  if c.d < t - 60 or c.d > t + MAX_DAYS * 86400 then return nil, "échéance" end
  if ns.ctTotal(c.m) > MAX_TOTAL or ns.ctTotal(c.o) > MAX_TOTAL then return nil, "montant" end
  c.v = tostring(c.v)
  c.d = c.d
  return c
end

---------------------------------------------------------------------------------------------------
-- Transport : messages d'addon en chuchotement, en morceaux bornés.
local function send(target, body)
  local n = math.ceil(#body / 240)
  if n > 10 then return print("|cffe64d4dContrats :|r contrat trop long pour être envoyé.") end
  local out = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
  for i = 1, n do
    local text = i .. "/" .. n .. "|" .. body:sub((i - 1) * 240 + 1, i * 240)
    if not (ns.debugSend and ns.debugSend("addon", target, text)) then out(PREFIX, text, "WHISPER", ns.whisperTarget(target)) end
  end
end
ns.ctSendRaw = send

local buffers, rate = {}, {}
function ns.ctOnAddon(prefix, text, channel, sender)
  if prefix ~= PREFIX or channel ~= "WHISPER" or type(text) ~= "string" then return end
  ns.rawSenders.addon = sender
  sender = ns.fullName(sender)
  if not sender then return end
  local r = rate[sender] or { t = GetTime(), n = 0 } -- 30 messages par minute et par expéditeur
  if GetTime() - r.t > 60 then r.t, r.n = GetTime(), 0 end
  r.n, rate[sender] = r.n + 1, r
  if r.n > 30 then return end
  local i, n, piece = text:match("^(%d%d?)/(%d%d?)|(.*)$")
  i, n = tonumber(i), tonumber(n)
  if not i or n < 1 or n > 10 or i < 1 or i > n then return end
  local b = buffers[sender]
  if i == 1 or not b or b.n ~= n or GetTime() - b.t > 30 then b = { n = n } buffers[sender] = b end
  b[i], b.t = piece, GetTime()
  for k = 1, n do if not b[k] then return end end
  buffers[sender] = nil
  local ok, err = pcall(ns.ctReceive, sender, table.concat(b, "", 1, n))
  if not ok then print("|cffe64d4dContrats :|r message de " .. sender .. " ignoré (" .. tostring(err) .. ").") end
end

---------------------------------------------------------------------------------------------------
-- États : a_signer (reçu, c'est à moi), envoye (à lui), signe, refuse, retire, clos. « échu » se calcule.
local function key(c) return c.origin .. "#" .. c.id end
ns.ctKey = key

local function notify(text) if ns.ctNotify then ns.ctNotify(text) end end

local function pendingFrom(sender)
  local n = 0
  for _, c in pairs(store()) do if c.status == "a_signer" and c.author == sender then n = n + 1 end end
  return n
end

local function snapshot(c)
  return { v = c.v, m = c.m, o = c.o, d = c.d, hash = c.hash }
end

function ns.ctReceive(sender, body)
  local me, t = ns.me(), now()
  local f = fields(body)
  if f[1] == "P" then
    local c, why = ns.ctParse(body, sender, me, t)
    if not c then return notify(("proposition de %s rejetée (%s)."):format(sender, why)) end
    local senderGUID = c.client == sender and c.clientGUID or c.artisanGUID
    local claim = ns.ctCheckClaim(sender, senderGUID)
    if claim == "faux" then return notify(("proposition de %s rejetée : l'identifiant annoncé n'est pas le sien."):format(sender)) end
    local cur = store()[key(c)]
    if cur and cur.peer and cur.peer.guid ~= senderGUID then return end -- l'identifiant ne change pas en cours de route
    if not cur then
      if c.v ~= "1" or c.origin ~= sender or c.parent ~= "0" then return end
      if pendingFrom(sender) >= MAX_PENDING then return notify(sender .. " a déjà 3 propositions en attente : ignorée.") end
    else
      if cur.status ~= "envoye" and cur.status ~= "a_signer" then return end -- signé, refusé, retiré : figé (P5)
      if tonumber(c.v) ~= tonumber(cur.v) + 1 or c.parent ~= cur.hash or c.client ~= cur.client or c.artisan ~= cur.artisan then return end
      c.prev = snapshot(cur)
    end
    c.hash, c.author, c.status, c.received = ns.ctHash(ns.ctCanonical(c)), sender, "a_signer", t
    c.peer = { guid = senderGUID, verified = claim == "ok" or (cur and cur.peer and cur.peer.verified) or nil }
    store()[key(c)] = c
    return notify(("%s te propose un contrat (v%s) : /contrat pour le lire."):format(sender, c.v))
  end
  local origin, id, v = f[3], f[4], f[5]
  if f[2] ~= "2" or type(origin) ~= "string" or type(id) ~= "string" then return end
  local c = store()[origin .. "#" .. id]
  if not c or sender ~= ns.other(c, me) then return end -- seul l'autre signataire peut agir (n° 19)
  if f[1] == "A" and #f == 7 then
    if c.status ~= "envoye" or c.author ~= me then return end
    local guid = f[7]
    local field = c.client == sender and c.clientGUID or c.artisanGUID
    if not guid:match(GUID) or (field ~= "0" and field ~= guid) or (c.peer and c.peer.guid and c.peer.guid ~= guid) then
      return notify(sender .. " a accepté avec un identifiant qui n'est pas celui du contrat : rien n'est signé.")
    end
    local claim = ns.ctCheckClaim(sender, guid)
    if claim == "faux" then return notify(sender .. " a accepté avec un identifiant qui n'est pas le sien : rien n'est signé.") end
    if v ~= c.v then return notify(("%s a accepté la v%s, mais ta v%s l'a remplacée : rien n'est signé."):format(sender, v, c.v)) end
    if f[6] ~= c.hash then return notify(sender .. " a accepté un texte différent du tien : rien n'est signé.") end
    c.status, c.signed = "signe", t
    c.peer = { guid = guid, verified = claim == "ok" or (c.peer and c.peer.verified) or nil }
    notify(("contrat avec %s signé (v%s)."):format(sender, c.v))
  elseif f[1] == "R" and #f == 5 and v == c.v and (c.status == "envoye" or c.status == "a_signer") then
    c.status = "refuse"
    notify(sender .. " a refusé le contrat.")
  elseif f[1] == "X" and #f == 5 and v == c.v and c.status == "a_signer" and c.author == sender then
    c.status = "retire"
    notify(sender .. " a retiré sa proposition.")
  end
end

-- Mes actions
-- Tout ce qui part (v1, contre-proposition, nouvelle version) passe d'abord nos propres bornes (n° 11, 14, 15) : les listes
-- relues par la lecture stricte, montants, version et échéance comme les vérifie celui qui reçoit.
local function horsBornes(c)
  local m, o = parseList(listText(c.m)), parseList(listText(c.o))
  if not (m and o) or #o == 0 then return "termes hors bornes (30 lignes, 1000 par ligne au plus)" end
  if ns.ctTotal(m) > MAX_TOTAL or ns.ctTotal(o) > MAX_TOTAL then return "montant trop élevé" end
  if tonumber(c.v) > 99 then return "trop de versions" end
  if c.d < now() or c.d > now() + MAX_DAYS * 86400 then return "échéance dépassée ou à plus de 30 jours" end
end

-- Renvoie le contrat envoyé, ou nil, raison (rien n'est enregistré ni envoyé).
function ns.ctPropose(c)
  local err = horsBornes(c)
  if err then return nil, err end
  c.hash, c.author, c.status = ns.ctHash(ns.ctCanonical(c)), ns.me(), "envoye"
  local otherGUID = c.client == ns.me() and c.artisanGUID or c.clientGUID
  if otherGUID ~= "0" and not c.peer then c.peer = { guid = otherGUID, verified = ns.knownGUID[ns.other(c, ns.me())] == otherGUID or nil } end
  store()[key(c)] = c
  send(ns.other(c, ns.me()), ns.ctCanonical(c))
  return c
end

function ns.ctAccept(c, shownHash)
  -- Le bouton porte l'empreinte affichée : si une autre version est arrivée entre-temps, rien n'est signé (n° 5).
  if c.status ~= "a_signer" or c.author == ns.me() or shownHash ~= c.hash then return false end
  c.status, c.signed = "signe", now()
  send(ns.other(c, ns.me()), table.concat({ "A", "2", c.origin, c.id, c.v, c.hash, ns.myGUID() }, "|"))
  return true
end

function ns.ctRefuse(c)
  if c.status ~= "a_signer" then return end
  c.status = "refuse"
  send(ns.other(c, ns.me()), table.concat({ "R", "2", c.origin, c.id, c.v }, "|"))
end

function ns.ctWithdraw(c)
  if c.status ~= "envoye" then return end
  c.status = "retire"
  send(ns.other(c, ns.me()), table.concat({ "X", "2", c.origin, c.id, c.v }, "|"))
end

-- Contre-proposition : nouveaux totaux (caution, livraison) et échéance ; les unités sont mises à l'échelle.
local function scale(list, total)
  local old = ns.ctTotal(list)
  local units = 0
  for _, l in ipairs(list) do units = units + l.qty end
  local out = {}
  for i, l in ipairs(list) do
    local u = old > 0 and l.unit * total / old or total / units
    out[i] = { id = l.id, qty = l.qty, unit = math.max(0, math.floor(u + 0.5)) }
  end
  return out
end
-- Une nouvelle version de c (m, o, échéance), envoyée à l'autre.
local function newVersion(c, m, o, d)
  local me, peerGUID = ns.me(), c.peer and c.peer.guid or "0"
  local n = { origin = c.origin, id = c.id, v = tostring(tonumber(c.v) + 1), parent = c.hash, client = c.client, artisan = c.artisan,
    clientGUID = c.client == me and ns.myGUID() or peerGUID, artisanGUID = c.artisan == me and ns.myGUID() or peerGUID, peer = c.peer,
    m = m, o = o, d = d, prev = snapshot(c) }
  return ns.ctPropose(n)
end
function ns.ctCounter(c, caution, delivery, days)
  return newVersion(c, caution and scale(c.m, caution) or c.m, delivery and scale(c.o, delivery) or c.o,
    days and (now() + math.floor(days * 86400)) or c.d)
end

-- Brouillon (pas encore envoyé) : on le modifie sur place, sans nouvelle version.
function ns.ctEditDraft(c, caution, delivery, days)
  if c.status ~= "brouillon" then return end
  if caution then c.m = scale(c.m, caution) end
  if delivery then c.o = scale(c.o, delivery) end
  if days then c.d = now() + math.floor(days * 86400) end
end

-- Les termes d'une demande (CONCEPTION.md) ; order = une commande (ns.projetCommande), calculée avec les choix de case
-- de son projet seulement :
--   m = les apports (case entière), unité = keep[id] (caution déjà au contrat) sinon leur prix de marché (mon scan) ;
--   o = ce qui est voulu, payé par objet : sa part de caution + sa part de l'offre (order.tip), au prorata de
--       l'estimation de la part de l'artisan pour chaque ligne.
local function demandeTerms(order, keep)
  local res = ns.projetDemande(order)
  local market = ns.market()
  local items = market and market.items
  local m, unit = {}, {}
  for _, a in ipairs(ns.demandeApports(res)) do
    local cost = ns.buyCost(a.id, a.qty, items)
    unit[a.id] = keep and keep[a.id] or cost and math.floor(cost / a.qty + 0.5) or 0
    m[#m + 1] = { id = a.id, qty = a.qty, unit = unit[a.id] }
  end
  local function apportValue(node)
    if node.how == "apport" then return node.qty * (unit[node.id] or 0) end
    local v = 0
    for _, p in ipairs(node.parts or {}) do v = v + apportValue(p) end
    return v
  end
  local shares, totalCost, byId = {}, 0, {}
  for i, r in ipairs(res.roots) do shares[i] = { a = apportValue(r), c = r.cost or 0 }; totalCost = totalCost + shares[i].c end
  local offer = order.tip or 0
  for i, l in ipairs(order.lines) do
    local share = totalCost > 0 and shares[i].c / totalCost or 1 / #order.lines
    local e = byId[l.id] or { id = l.id, qty = 0, amount = 0 }
    e.qty, e.amount, byId[l.id] = e.qty + l.qty, e.amount + shares[i].a + offer * share, e
  end
  local o = {}
  for _, e in pairs(byId) do o[#o + 1] = { id = e.id, qty = e.qty, unit = math.floor(e.amount / e.qty + 0.5) } end
  table.sort(o, function(x, y) return x.id < y.id end)
  if #m > MAX_LINES or #o > MAX_LINES then return nil, "trop de lignes" end
  return m, o
end

-- Le contrat tiré d'une demande : moi client, le joueur de la commande artisan. Sans offre, l'artisan chiffre.
function ns.ctFromDemande(order, days)
  local me, artisan = ns.me(), ns.fullName(order.player or "")
  if not artisan or artisan == me then return nil, "indique l'artisan (le joueur) dans la commande" end
  if #order.lines == 0 then return nil, "la commande est vide" end
  local m, o = demandeTerms(order)
  if not m then return nil, o end
  local id = now() -- plusieurs commandes d'un projet peuvent partir dans la même seconde : une clé chacune
  while store()[me .. "#" .. id] do id = id + 1 end
  return { origin = me, id = tostring(id), v = "1", parent = "0", client = me, artisan = artisan, m = m, o = o,
    clientGUID = ns.myGUID(), artisanGUID = ns.knownGUID[artisan] or "0", d = now() + math.floor((days or 3) * 86400) }
end

-- « Je réponds » (l'artisan, depuis l'arbre de sa réponse ; order = sa 1re commande) : ses apports et son prix, envoyés
-- en nouvelle version.
-- Les cautions déjà au contrat restent ; un apport qu'il ajoute est estimé à son prix de marché.
function ns.ctReplyFromOrder(order)
  local c = order.reponse and store()[order.reponse]
  if not c then return nil, "le contrat de cette réponse n'existe plus" end
  if ns.ctStatus(c) ~= "a_signer" or c.artisan ~= ns.me() then return nil, "ce contrat n'attend pas ta réponse" end
  local keep = {}
  for _, l in ipairs(c.m) do keep[l.id] = l.unit end
  local m, o = demandeTerms(order, keep)
  if not m then return nil, o end
  if listText(m) == listText(c.m) and listText(o) == listText(c.o) then return nil, "rien n'a changé : signe-le dans Contrats" end
  return newVersion(c, m, o, c.d)
end

-- « Nouvelle version » de ma demande c (#8, moi client) : ce que la commande order demande maintenant (ses lignes, ses
-- apports, son offre), en contre-proposition. Les cautions déjà au contrat restent ; un apport ajouté est estimé à mon
-- prix de marché.
function ns.ctVersionDemande(c, order)
  if c.client ~= ns.me() or (c.status ~= "envoye" and c.status ~= "a_signer") then return nil, "ce contrat ne prend plus de nouvelle version" end
  if #order.lines == 0 then return nil, "la commande est vide : retire (ou refuse) la demande dans Contrats" end
  local keep = {}
  for _, l in ipairs(c.m) do keep[l.id] = l.unit end
  local m, o = demandeTerms(order, keep)
  if not m then return nil, o end
  return newVersion(c, m, o, c.d)
end

---------------------------------------------------------------------------------------------------
-- Registre (P2) : ce que mon addon a vu passer. c.got / c.gave = quantités cumulées par objet, c.net = valeur reçue −
-- valeur donnée, en valeurs du contrat (ce que je reçois au-delà de ce qui reste dû ne compte pas).
function ns.ctStatus(c, t)
  if c.status == "signe" and (t or now()) > c.d then return "echu" end
  return c.status
end

local function find(list, id)
  for _, l in ipairs(list) do if l.id == id then return l end end
end

-- Verdict d'un échange (P1, P6). snap = { partner, guid, give = { items = {[id]=qté}, money }, get = {…},
-- unknown = objet illisible, slot7 = objet en 7ᵉ case, api = fonctions du jeu modifiées }.
function ns.ctEvaluate(c, me, snap, t)
  local r = { problems = {}, warnings = {}, valueIn = 0, valueOut = 0 }
  local function bad(s) r.problems[#r.problems + 1] = s end
  local function warn(s) r.warnings[#r.warnings + 1] = s end
  local status = ns.ctStatus(c, t)
  if status == "echu" then bad("contrat échu : chacun garde ce qu'il a")
  elseif status ~= "signe" then bad("contrat pas signé") end
  local other, peer = ns.other(c, me), c.peer or {}
  if peer.guid then -- identifiant du contrat : c'est lui qui fait foi
    if snap.guid ~= peer.guid then bad("pas le bon personnage : son identifiant n'est pas celui du contrat") end
    if snap.partner ~= other then
      if peer.verified then warn("même personnage, mais son nom a changé (" .. tostring(snap.partner) .. ")")
      else bad("ce n'est pas " .. other) end
    end
  elseif snap.partner ~= other then bad("ce n'est pas " .. other) end
  if snap.api then bad("fonctions de l'échange modifiées par un autre addon : non vérifiable") end
  if snap.unknown then bad("objet illisible (pas encore chargé) : attends ou retire-le") end
  if snap.slot7 then warn("un objet est dans la case « ne sera pas échangé » : il ne compte pas") end
  local artisan = me == c.artisan
  local inList, outList = artisan and c.m or c.o, artisan and c.o or c.m
  local got, gave = c.got or {}, c.gave or {}
  r.valueIn = snap.get.money or 0
  for id, q in pairs(snap.get.items) do
    local l = find(inList, id)
    if not l then warn("il donne un objet hors contrat (ne compte pas)")
    else
      local left = math.max(0, l.qty - (got[id] or 0))
      if q > left then warn(("il donne %d de trop"):format(q - left)) end
      r.valueIn = r.valueIn + math.min(q, left) * l.unit
    end
  end
  r.valueOut = snap.give.money or 0
  for id, q in pairs(snap.give.items) do
    local l = find(outList, id)
    if not l then bad("tu donnes un objet hors contrat")
    else
      local left = math.max(0, l.qty - (gave[id] or 0))
      if q > left then bad(("tu donnes %d de plus que prévu"):format(q - left)) end
      r.valueOut = r.valueOut + q * l.unit
    end
  end
  r.net = (c.net or 0) + r.valueIn - r.valueOut
  if r.net < 0 then r.short = -r.net bad("il manque de son côté") end
  r.empty = r.valueIn == 0 and r.valueOut == 0 and not next(snap.get.items) and not next(snap.give.items)
  r.ok = #r.problems == 0 and not r.empty
  return r
end

-- Un échange terminé et confirmé : on l'inscrit.
function ns.ctRecord(c, me, snap, t)
  local r = ns.ctEvaluate(c, me, snap, t)
  c.got, c.gave = c.got or {}, c.gave or {}
  for id, q in pairs(snap.get.items) do c.got[id] = (c.got[id] or 0) + q end
  for id, q in pairs(snap.give.items) do c.gave[id] = (c.gave[id] or 0) + q end
  c.net = (c.net or 0) + r.valueIn - r.valueOut
  -- Identité confirmée par le serveur au premier échange où nom et identifiant correspondent.
  c.peer = c.peer or {}
  if snap.partner == ns.other(c, me) and (not c.peer.guid or c.peer.guid == snap.guid) then
    c.peer.guid, c.peer.verified = snap.guid, true
  end
  if c.peer.guid == snap.guid and snap.surname then c.peer.surname = snap.surname end
  c.ledger = c.ledger or {}
  table.insert(c.ledger, { t = t, give = snap.give, get = snap.get, conforme = r.ok, net = c.net })
  local artisan = me == c.artisan
  local inList, outList = artisan and c.m or c.o, artisan and c.o or c.m
  local done = c.net >= 0
  for _, l in ipairs(inList) do if (c.got[l.id] or 0) < l.qty then done = false end end
  for _, l in ipairs(outList) do if (c.gave[l.id] or 0) < l.qty then done = false end end
  if done then c.status = "clos" end
  c.unsaved = true
  return r
end

-- Les contrats en cours avec un joueur (pour le panneau d'échange).
function ns.ctActiveWith(partner, guid)
  local list, me = {}, ns.me()
  for _, c in pairs(store()) do
    local peer = c.peer or {}
    local named = ns.other(c, me) == partner and (c.client == me or c.artisan == me)
    if c.status == "signe" and ((peer.guid and peer.guid == guid) or (named and not peer.verified)) then list[#list + 1] = c end
  end
  table.sort(list, function(a, b) return (a.signed or 0) < (b.signed or 0) end)
  return list
end

---------------------------------------------------------------------------------------------------
local f = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "CHAT_MSG_ADDON", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
  "GROUP_ROSTER_UPDATE", "TRADE_SHOW" }) do f:RegisterEvent(e) end
f:SetScript("OnEvent", function(_, event, ...)
  if event == "CHAT_MSG_ADDON" then return ns.ctOnAddon(...) end
  if event == "ADDON_LOADED" then
    if ... == "Handshake" then
      HandshakeDB = HandshakeDB or {}
      HandshakeDB.surnames = HandshakeDB.surnames or {}
      ns.surnames = HandshakeDB.surnames
    end
  elseif event == "PLAYER_LOGIN" then
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
  elseif event == "PLAYER_TARGET_CHANGED" then ns.learnUnit("target")
  elseif event == "UPDATE_MOUSEOVER_UNIT" then ns.learnUnit("mouseover")
  elseif event == "TRADE_SHOW" then ns.learnUnit("NPC")
  elseif event == "GROUP_ROSTER_UPDATE" then
    for i = 1, 4 do ns.learnUnit("party" .. i) end
    for i = 1, 40 do ns.learnUnit("raid" .. i) end
  end
end)
