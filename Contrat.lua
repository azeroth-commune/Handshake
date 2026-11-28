-- Handshake, les contrats : format, signature, registre, verdict. Rien d'affiché ici (ContratUI.lua,
-- Echange.lua), tout est testé hors jeu (check.lua). Les règles viennent du modèle de menace : SECURITE.md.
--
-- Un contrat = deux ventes protégées.
--   m : composants que le client fournit, { id, qty, unit } — unit = caution par unité, payée par l'artisan.
--   o : objets fabriqués, { id, qty, unit } — unit = ce que le client paie par objet livré (caution rendue + prix).
-- Chaque échange est équilibré par ces valeurs unitaires (P1) : pas de prorata, pas d'arrondi, jamais de crédit.
-- Échéance dépassée : chacun garde ce qu'il a, plus aucun échange conforme.
--
-- Sur le fil (messages d'addon, chuchotement uniquement), champs à position fixe, rien de libre (P4). Protocole 3
-- (Handshake#29) : les signataires sont des GUID, et chaque message porte en 3e champ le GUID de son expéditeur.
--   P|3|expéditeur|origine|id|version|empreinte parente|client|artisan|m|o|échéance
--        expéditeur, origine, client, artisan = GUID (« Player-6942-014B6DDC ») ; m, o = "id:qté:unité,…" triés par id
--   A|3|expéditeur|origine|id|version|empreinte      (accepte cette version précise)
--   R|3|expéditeur|origine|id|version (refuse)         X|3|expéditeur|origine|id|version (retire sa proposition)
--   Q|3|expéditeur  (as-tu Handshake ?)                H|3|expéditeur  (oui : la réponse, envoyée seule, sans rien afficher)
-- Identité (SECURITE.md, n° 26) : le GUID déclaré dans un message n'est pas une preuve. Il doit concorder avec ce que
-- le serveur a donné (ns.knownGUID : chuchotement, cible, survol, groupe) : un autre GUID appris pour ce nom, ou ce GUID
-- appris sous un autre nom, fait rejeter le message. Jamais appris, il est accepté pour négocier et vérifié au premier
-- échange, avant que rien ne bouge : le GUID du partenaire, donné par le serveur, doit être celui du contrat, sinon NON
-- CONFORME. Le nom affiché est celui de l'expéditeur authentifié (c.peer.name), jamais déduit du GUID déclaré.
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
-- Noms : « Prénom Nom », la forme que le serveur donne comme expéditeur et qu'il accepte pour un chuchotement
-- (lib.Destinataire, LibCommune#35). Ils servent à afficher et à chuchoter ; un personnage s'identifie par son GUID.
local lib = AzerothCommune
ns.fullName, ns.whisperTarget = lib.Destinataire, lib.Destinataire
function ns.me() return UnitGUID("player") end -- moi : mon GUID (le mode debug le remplace par celui du Testeur)
function ns.myName() return lib.Personnage().nom end
-- « Prénom Nom » d'un perso vu (UnitName : prénom, puis nom de famille sur Forever).
function ns.unitName(prenom, nom)
  if type(prenom) ~= "string" or prenom == "" then return nil end
  return (type(nom) == "string" and nom ~= "") and (prenom .. " " .. nom) or prenom
end

-- Grammaire stricte d'un GUID de personnage, comme le reste du contrat.
local GUID = "^Player%-%d+%-%x%x%x%x%x%x%x%x$"
function ns.isGUID(g) return type(g) == "string" and #g <= 30 and g:match(GUID) ~= nil end

-- GUID appris de sources serveur, par nom et par GUID : celui que le jeu joint à un chuchotement reçu, ceux des persos
-- qu'on voit (cible, survol, groupe, échange). Jamais pris dans un message de l'autre addon.
ns.knownGUID, ns.knownName = {}, {}
function ns.learnGUID(name, guid)
  if type(name) == "string" and name ~= "" and ns.isGUID(guid) then ns.knownGUID[name], ns.knownName[guid] = guid, name end
end
function ns.learnUnit(unit)
  if not (UnitExists(unit) and UnitIsPlayer(unit)) then return end
  ns.learnGUID(ns.unitName(UnitName(unit)), UnitGUID(unit))
end
-- « Prénom Nom — GUID » pour l'affichage (plus de royaume : le jeu ne le donne plus, build 71037).
function ns.identity(name, guid)
  return (("%s — %s"):format(name or "?", guid or "GUID inconnu"):gsub("|", "||"))
end
function ns.myIdentity() return ns.identity(ns.myName(), ns.me()) end

-- Un GUID déclaré par name : "ok" (le serveur l'a donné pour ce nom), "faux" (le serveur a donné un autre GUID pour ce
-- nom, ou ce GUID pour un autre nom), "inconnu" (jamais appris : vérifié au premier échange).
-- ponytail: pas de GetPlayerInfoByGUID (forme de ses retours pas relevée sur Forever) ; à ajouter quand une sonde l'aura vu.
function ns.ctCheckClaim(name, guid)
  local known, other = ns.knownGUID[name], ns.knownName[guid]
  if known then return known == guid and "ok" or "faux" end
  if other and other ~= name then return "faux" end
  return "inconnu"
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
local function terms(c) return c.origin, c.id, c.v, c.parent, c.client, c.artisan, listText(c.m), listText(c.o), c.d end
function ns.ctCanonical(c) return table.concat({ "P", "3", terms(c) }, "|") end
-- Un message de moi : son type, le protocole, mon GUID, puis ses champs.
local function wire(kind, ...) return table.concat({ kind, "3", ns.me(), ... }, "|") end
function ns.ctMessage(c) return wire("P", terms(c)) end
function ns.ctTotal(list)
  local s = 0
  for _, l in ipairs(list) do s = s + l.qty * l.unit end
  return s
end

-- P8 (SECURITE.md, n° 13) : TON estimation des termes du contrat c, d'après ton dernier scan de l'HV, vue depuis ta place
-- (me). La fiche du contrat (ns.ctDescribe) et la page du projet lisent ces nombres, rien n'est estimé ailleurs.
--   scanned : date du scan (nil = jamais) ; composants : ce que coûteraient les apports, hors ceux sans prix connu ;
--   manquants : combien n'ont pas de prix (estimation incomplète) ; ecart : caution − composants, en % des composants ;
--   alerte : au-delà de 10 % dans le sens où je perds (client : caution trop basse ; artisan : trop haute) ; perte : ce
--   que je perds au plus si l'autre disparaît après l'étape 1 ; valeur : ce que valent les objets livrés (hors sans prix).
local function estimate(list, items, vendors)
  local total, missing = 0, 0
  for _, l in ipairs(list) do
    local cost = lib:PrixAchat(l.id, l.qty, items, vendors)
    if cost then total = total + cost else missing = missing + 1 end
  end
  return total, missing
end
function ns.ctEstimation(c, me)
  local m = ns.market()
  local items, artisan, caution, vendors = m and m.items, me == c.artisan, ns.ctTotal(c.m), lib:PrixMarchands()
  local e = { scanned = m and (m.scanned or m.source), valeur = (estimate(c.o, items, vendors)) }
  e.composants, e.manquants = estimate(c.m, items, vendors)
  e.ecart = e.composants > 0 and (caution - e.composants) / e.composants * 100 or 0
  e.alerte = artisan and e.ecart > 10 or not artisan and e.ecart < -10
  e.perte = math.max(0, artisan and caution - e.composants or e.composants - caution)
  return e
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

-- Une proposition reçue, adressée à me (mon GUID). Renvoie le contrat (forme locale) et le GUID déclaré de son
-- expéditeur, ou nil, raison.
function ns.ctParse(body, me, t)
  local f = fields(body)
  if f[1] ~= "P" or #f ~= 12 or f[2] ~= "3" then return nil, "format" end
  local from = f[3]
  local c = { origin = f[4], id = f[5], v = int(f[6], 2, 1, 99), parent = f[7], client = f[8], artisan = f[9],
    m = parseList(f[10]), o = parseList(f[11]), d = int(f[12], 12, 0, 9e11) }
  if not (c.v and c.m and c.o and c.d) or #c.o == 0 then return nil, "champs" end
  if not (c.id:match("^%d+$") and #c.id <= 12) then return nil, "id" end
  if not (c.parent == "0" or c.parent:match("^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$")) then return nil, "parent" end
  for _, g in ipairs({ from, c.origin, c.client, c.artisan }) do
    if not ns.isGUID(g) then return nil, "GUID" end -- un GUID tel quel : ni nom, ni adresse, ni GUID malformé
  end
  if c.client == c.artisan or not ((c.client == me and c.artisan == from) or (c.artisan == me and c.client == from)) then
    return nil, "parties"
  end
  if c.origin ~= c.client and c.origin ~= c.artisan then return nil, "origine" end
  if c.d < t - 60 or c.d > t + MAX_DAYS * 86400 then return nil, "échéance" end
  if ns.ctTotal(c.m) > MAX_TOTAL or ns.ctTotal(c.o) > MAX_TOTAL then return nil, "montant" end
  c.v = tostring(c.v)
  return c, from
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
  if prefix ~= PREFIX or channel ~= "WHISPER" or type(text) ~= "string" or type(sender) ~= "string" or sender == "" then return end
  sender = ns.fullName(sender) -- « Prénom Nom », donné par le serveur
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
-- Une nouvelle version pas encore envoyée (brouillon, #19) se range à côté de la version en cours : « origine#id+ ».
local function key(c) return c.origin .. "#" .. c.id .. (c.status == "brouillon" and c.parent ~= "0" and "+" or "") end
ns.ctKey = key

-- Ce brouillon de nouvelle version ne vaut plus : la version en cours a changé depuis (il a contre-proposé, signé, refusé…).
function ns.ctBrouillonPerime(c)
  if c.status ~= "brouillon" or c.parent == "0" then return false end
  local cur = store()[c.origin .. "#" .. c.id]
  return not (cur and cur.hash == c.parent and (cur.status == "envoye" or cur.status == "a_signer"))
end

local function notify(text) if ns.ctNotify then ns.ctNotify(text) end end
-- Envoyer (#71) : les joueurs (nom donné par le serveur) dont on sait qu'ils ont Handshake, pour la session ; les envois
-- qui attendent la réponse à la question de présence, par joueur.
local presents, attente = {}, {}
local repondu

local function pendingFrom(sender) -- par nom authentifié : un GUID déclaré ne coûte rien à changer
  local n = 0
  for _, c in pairs(store()) do if c.status == "a_signer" and c.peer and c.peer.name == sender then n = n + 1 end end
  return n
end

local function snapshot(c)
  return { v = c.v, m = c.m, o = c.o, d = c.d, hash = c.hash }
end

function ns.ctReceive(sender, body)
  local me, t = ns.me(), now()
  local f = fields(body)
  local from = f[3]
  if f[2] ~= "3" or not ns.isGUID(from) then -- chaque message porte le GUID de son expéditeur
    if f[1] == "P" then notify(("proposition de %s rejetée (format)."):format(sender)) end
    return
  end
  local claim = ns.ctCheckClaim(sender, from)
  if claim == "faux" then return notify(("message de %s rejeté : le GUID annoncé n'est pas le sien."):format(sender)) end
  presents[sender] = true -- un message de contrat valide : il a Handshake (pour la session, #71)
  if f[1] == "Q" and #f == 3 then return send(sender, wire("H")) end -- répondu en silence : rien d'affiché, rien à cliquer
  if f[1] == "H" and #f == 3 then return repondu(sender, false) end
  if f[1] == "P" then
    local c, why = ns.ctParse(body, me, t)
    if not c then return notify(("proposition de %s rejetée (%s)."):format(sender, why)) end
    local cur = store()[key(c)]
    if cur and (cur.peer or {}).name ~= sender then return end -- seul l'autre signataire, sous le nom donné par le serveur (n° 19)
    if not cur then
      if c.v ~= "1" or c.origin ~= from or c.parent ~= "0" then return end
      if pendingFrom(sender) >= MAX_PENDING then return notify(sender .. " a déjà 3 propositions en attente : ignorée.") end
    else
      if cur.status ~= "envoye" and cur.status ~= "a_signer" then return end -- signé, refusé, retiré : figé (P5)
      if tonumber(c.v) ~= tonumber(cur.v) + 1 or c.parent ~= cur.hash or c.client ~= cur.client or c.artisan ~= cur.artisan then return end
      c.prev = snapshot(cur)
    end
    c.hash, c.author, c.status, c.received = ns.ctHash(ns.ctCanonical(c)), from, "a_signer", t
    c.peer = { guid = from, name = sender, verified = claim == "ok" or (cur and cur.peer and cur.peer.verified) or nil }
    store()[key(c)] = c
    return notify(("%s te propose un contrat (v%s) : /contrat pour le lire."):format(sender, c.v))
  end
  local origin, id, v = f[4], f[5], f[6]
  local c = type(origin) == "string" and type(id) == "string" and store()[origin .. "#" .. id]
  -- seul l'autre signataire peut agir (n° 19) : son GUID, sous le nom que le serveur donne
  if not c or from ~= ns.other(c, me) or not c.peer or sender ~= c.peer.name then return end
  if f[1] == "A" and #f == 7 then
    if c.status ~= "envoye" or c.author ~= me then return end
    if v ~= c.v then return notify(("%s a accepté la v%s, mais ta v%s l'a remplacée : rien n'est signé."):format(sender, v, c.v)) end
    if f[7] ~= c.hash then return notify(sender .. " a accepté un texte différent du tien : rien n'est signé.") end
    c.status, c.signed = "signe", t
    c.peer.verified = claim == "ok" or c.peer.verified
    notify(("contrat avec %s signé (v%s)."):format(sender, c.v))
  elseif f[1] == "R" and #f == 6 and v == c.v and (c.status == "envoye" or c.status == "a_signer") then
    c.status = "refuse"
    notify(sender .. " a refusé le contrat.")
  elseif f[1] == "X" and #f == 6 and v == c.v and c.status == "a_signer" and c.author == from then
    c.status = "retire"
    notify(sender .. " a retiré sa proposition.")
  end
end

-- Mes actions
-- Tout ce qui part (v1, contre-proposition, nouvelle version) passe d'abord nos propres bornes (n° 11, 14, 15) : les listes
-- relues par la lecture stricte, montants, version et échéance comme les vérifie celui qui reçoit.
local function horsBornes(c)
  if not (ns.isGUID(c.client) and ns.isGUID(c.artisan) and c.peer and c.peer.name) then return "GUID de l'autre joueur inconnu" end
  local m, o = parseList(listText(c.m)), parseList(listText(c.o))
  if not (m and o) or #o == 0 then return "termes hors bornes (30 lignes, 1000 par ligne au plus)" end
  if ns.ctTotal(m) > MAX_TOTAL or ns.ctTotal(o) > MAX_TOTAL then return "montant trop élevé" end
  if tonumber(c.v) > 99 then return "trop de versions" end
  if c.d < now() or c.d > now() + MAX_DAYS * 86400 then return "échéance dépassée ou à plus de 30 jours" end
end

-- Ce qui doit tenir avant tout envoi : une nouvelle version périmée (#19) ne part pas, son brouillon est effacé (une
-- contre-proposition, jamais rangée, #74, n'efface rien) ; puis nos bornes. Renvoie nil, ou la raison.
local function pasPret(c)
  if ns.ctBrouillonPerime(c) then
    if store()[key(c)] ~= c then return "la version reçue a changé : relis-la, rien n'est parti" end
    store()[key(c)] = nil
    return "le contrat a changé depuis ce brouillon : « Nouvelle version » le refait"
  end
  return horsBornes(c)
end

-- Le texte du contrat en clair, chuchoté à quelqu'un sans Handshake (il ne vaut pas signature).
local function texteEnClair(c)
  local other = c.peer.name
  if #c.m > 0 then
    for _, msg in ipairs(ns.listMessages("Contrat", c.m, ("· composants fournis par le client, caution %s"):format(ns.poText(ns.ctTotal(c.m))))) do
      ns.whisper(msg, other)
    end
  end
  for _, msg in ipairs(ns.listMessages("Contrat", c.o, ("· à la livraison %s · avant le %s"):format(ns.poText(ns.ctTotal(c.o)), date("%d/%m %H:%M", c.d)))) do
    ns.whisper(msg, other)
  end
end

-- Le contrat part : par Handshake, ou en clair (marqueur c.enClair, le seul qui permet « Il a dit oui »). Envoyé, un
-- brouillon de nouvelle version prend la place de la version en cours.
local function partir(c, clair)
  store()[c.origin .. "#" .. c.id .. "+"] = nil -- une nouvelle version part : un brouillon de la suivante ne vaut plus
  c.hash, c.author, c.status, c.enClair = ns.ctHash(ns.ctCanonical(c)), ns.me(), "envoye", clair or nil
  store()[key(c)] = c
  if clair then texteEnClair(c) else send(c.peer.name, ns.ctMessage(c)) end
  ns.balayerTB() -- une commande partie en contrat quitte le tableau de Trade Board (Annonce.lua)
  return c
end

-- Par Handshake, sans question : renvoie le contrat envoyé, ou nil, raison (rien n'est enregistré ni envoyé).
function ns.ctPropose(c)
  local err = pasPret(c)
  if err then return nil, err end
  return partir(c)
end

-- Envoyer (#71, CONTEXT.md) : un seul geste. Si l'on sait qu'il a Handshake, le contrat part par Handshake ; sinon une
-- question de présence (Q) part, et sa réponse (H) dans les 3 s le fait partir par Handshake, son silence en clair. Le
-- contrat attend tel quel : modifié ou effacé entre-temps, rien ne part. Renvoie le contrat, ou nil, raison.
-- Le chemin se décide à la v1, les versions suivantes le suivent (lu sur la version en cours, que pasPret a vue à jour) :
-- partie en clair, la nouvelle version part en clair sans question (son Handshake, installé depuis, n'a pas de v1 et
-- l'ignorerait) ; partie ou reçue par Handshake, elle part par Handshake, jamais en clair (sinon sa v1 resterait signable
-- chez lui) : sans réponse, rien ne part. Seule une v1 choisit le clair par son silence.
local function cheminDe(c) -- "clair", "handshake", ou nil (une v1 : libre)
  if c.parent == "0" then return nil end
  local cur = store()[c.origin .. "#" .. c.id]
  return cur and cur.enClair and "clair" or "handshake"
end
local function dire(c, clair)
  notify(clair and ("contrat v%s parti en clair à %s (%s) : s'il dit oui, « Il a dit oui »."):format(c.v, c.peer.name,
      c.v == "1" and "pas de réponse de Handshake" or "comme la version d'avant")
    or ("contrat v%s parti signé à %s (il a Handshake)."):format(c.v, c.peer.name))
end
repondu = function(name, clair)
  local liste = attente[name]
  attente[name] = nil
  for _, e in ipairs(liste or {}) do
    local c = e.c
    local change = (not e.direct and store()[key(c)] ~= c) or c.status ~= "brouillon" or ns.ctCanonical(c) ~= e.texte
    local err = change and "le contrat a changé pendant l'attente de sa réponse" or pasPret(c)
      or clair and cheminDe(c) == "handshake" and "pas de réponse de son Handshake : réessaie quand il est en ligne"
    if err then notify(("rien n'est parti à %s : %s."):format(name, err))
    else dire(partir(c, clair), clair) end
  end
end
-- c attend la réponse, ou (c en cours) sa contre-proposition l'attend : renvoie la version en route (c, ou sa
-- contre-proposition), sinon false.
function ns.ctEnAttente(c)
  for _, e in ipairs(c.peer and attente[c.peer.name] or {}) do
    if e.c == c or c.hash and e.c.parent == c.hash and e.c.origin == c.origin and e.c.id == c.id then return e.c end
  end
  return false
end
function ns.ctEnvoyer(c)
  if c.status ~= "brouillon" then return nil, "déjà parti" end
  if ns.ctEnAttente(c) then return nil, "déjà en route : sa réponse est attendue" end
  local err = pasPret(c)
  if err then return nil, err end
  local name = c.peer.name
  local chemin = cheminDe(c)
  if chemin == "clair" or presents[name] then
    dire(partir(c, chemin == "clair"), chemin == "clair")
    return c
  end
  local liste = attente[name]
  if not liste then
    liste = {}
    attente[name] = liste
    C_Timer.After(3, function() if attente[name] == liste then repondu(name, true) end end)
  end
  -- direct : une contre-proposition (#74), jamais rangée ; seule sa version parente doit tenir (pasPret, périmée)
  liste[#liste + 1] = { c = c, texte = ns.ctCanonical(c), direct = store()[key(c)] ~= c }
  if #liste == 1 then send(name, wire("Q")) end -- après l'inscription : la réponse peut arriver tout de suite (debug)
  return c
end

function ns.ctAccept(c, shownHash)
  -- Le bouton porte l'empreinte affichée : si une autre version est arrivée entre-temps, rien n'est signé (n° 5).
  if c.status ~= "a_signer" or c.author == ns.me() or shownHash ~= c.hash then return false end
  c.status, c.signed = "signe", now()
  send(c.peer.name, wire("A", c.origin, c.id, c.v, c.hash))
  return true
end

function ns.ctRefuse(c)
  if c.status ~= "a_signer" then return end
  c.status = "refuse"
  send(c.peer.name, wire("R", c.origin, c.id, c.v))
end

-- Parti en clair : il n'a rien reçu par Handshake, une ligne en clair le lui dit (ns.whisper : rien en mode debug).
function ns.ctWithdraw(c)
  if c.status ~= "envoye" then return end
  c.status = "retire"
  if c.enClair then
    ns.whisper(("Contrat retiré : celui à la livraison %s, avant le %s, ne tient plus."):format(ns.poText(ns.ctTotal(c.o)), date("%d/%m %H:%M", c.d)), c.peer.name)
  else
    send(c.peer.name, wire("X", c.origin, c.id, c.v))
  end
end

-- « Il a dit oui » (#71) : l'accord d'un joueur sans Handshake, noté à la main. Seulement pour un contrat parti en clair :
-- parti par Handshake, c'est sa signature qui compte. Mon panneau vérifiera les échanges contre MA copie.
function ns.ctIlADitOui(c)
  if c.status ~= "envoye" or not c.enClair then return false end
  c.status, c.signed, c.manual = "signe", now(), true
  return true
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
-- Une nouvelle version de c (m, o, échéance), pas encore envoyée.
local function nextVersion(c, m, o, d)
  return { origin = c.origin, id = c.id, v = tostring(tonumber(c.v) + 1), parent = c.hash, client = c.client, artisan = c.artisan,
    peer = c.peer, m = m, o = o, d = d, prev = snapshot(c) }
end
-- La réponse de l'artisan et la nouvelle version d'une demande, faites hors de Contrats (Composants, la liste), sont
-- préparées en brouillon (#19), à côté de la version en cours : rien ne part avant que son auteur ait relu SA fiche dans
-- Contrats (caution, perte maximale, objets sans prix, échéance, nom et GUID : P8, n° 11, 13, 26, 57) et cliqué
-- « Envoyer » (ns.ctEnvoyer). Préparée de nouveau, le brouillon est refait. Bornes vérifiées dès maintenant.
local function newVersion(c, m, o, d)
  local n = nextVersion(c, m, o, d)
  local err = horsBornes(n)
  if err then return nil, err end
  n.status = "brouillon"
  store()[key(n)] = n
  return n
end
-- Contre-proposition (#74) : la version suivante de c, la version en cours affichée sur sa fiche, avec les montants de
-- ses champs (nil = inchangé), envoyée du même clic par la règle d'Envoyer (présence, chemin décidé à la v1). Pas de
-- brouillon relu : la fiche affichée l'était. Renvoie la version partie (ou en route), ou nil, raison (rien ne part).
function ns.ctCounter(c, caution, delivery, days)
  if store()[c.origin .. "#" .. c.id] ~= c or (c.status ~= "a_signer" and c.status ~= "envoye") then
    return nil, "la version reçue a changé : relis-la, rien n'est parti"
  end
  if ns.ctEnAttente(c) then return nil, "déjà en route : sa réponse est attendue" end
  local n = nextVersion(c, ns.ctMontants(c, caution, delivery, days))
  n.status = "brouillon" -- le temps de partir : jamais rangé
  return ns.ctEnvoyer(n)
end

-- Les termes (m, o, échéance) de c avec ces montants (nil = inchangé), unités mises à l'échelle : ce que Contre-proposer
-- et Envoyer feront partir, et ce que la fiche montre pendant la saisie (#82). Un cuivre par objet au plus peut séparer
-- le total ainsi réparti du total tapé (une valeur entière par unité, P1) : la fiche montre le total qui part.
function ns.ctMontants(c, caution, delivery, days)
  return caution and scale(c.m, caution) or c.m, delivery and scale(c.o, delivery) or c.o,
    days and (now() + math.floor(days * 86400)) or c.d
end

-- Brouillon (pas encore envoyé) : on le modifie sur place, sans nouvelle version.
function ns.ctEditDraft(c, caution, delivery, days)
  if c.status ~= "brouillon" then return end
  c.m, c.o, c.d = ns.ctMontants(c, caution, delivery, days)
end

-- Les termes d'une demande (CONCEPTION.md). Le contrat ne voit que des objets × quantités, quelle que soit l'origine :
-- order = une commande de projet (ns.projetCommande, calculée avec les choix de case de son projet seulement) ou une
-- commande à la main (ns.commandeMain : order.apporte, sans arbre).
--   m = les apports (case entière, ou la quantité de la liste), unité = keep[id] (caution déjà au contrat) sinon leur
--       prix d'achat (mon scan) ;
--   o = ce qui est voulu, payé par objet : sa part de caution + sa part de l'offre (order.tip). Projet : au prorata de
--       l'estimation de la part de l'artisan pour chaque ligne, et la caution de ce que consomme chaque ligne. À la main :
--       les deux au prorata du prix d'achat de chaque ligne ; à parts égales dès qu'une ligne n'a pas de prix connu
--       (sinon elle vaudrait 0 pc par objet au contrat).
-- Le prix d'achat d'une ligne (qty objets), nil s'il n'est pas connu (ni marchand ni HV) ; la liste l'affiche.
function ns.prixAchatLigne(id, qty)
  local market = ns.market()
  return lib:PrixAchat(id, qty, market and market.items, lib:PrixMarchands())
end

local function demandeTerms(order, keep)
  local res = not order.apporte and ns.arbreDemande(order, order.apports) or nil
  local market = ns.market()
  local items, vendors = market and market.items, lib:PrixMarchands()
  local m, unit = {}, {}
  for _, a in ipairs(ns.commandeApports(order, res)) do
    local cost = lib:PrixAchat(a.id, a.qty, items, vendors)
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
  if res then
    for i, r in ipairs(res.roots) do shares[i] = { a = apportValue(r), c = r.cost or 0 }; totalCost = totalCost + shares[i].c end
  else
    local caution, w = ns.ctTotal(m), {}
    local inconnu = false
    for i, l in ipairs(order.lines) do
      w[i] = lib:PrixAchat(l.id, l.qty, items, vendors)
      if not w[i] then w[i], inconnu = 0, true end
      totalCost = totalCost + w[i]
    end
    if inconnu then totalCost = 0 end -- une ligne sans prix : tout à parts égales
    for i in ipairs(order.lines) do shares[i] = { a = totalCost > 0 and caution * w[i] / totalCost or caution / #order.lines, c = w[i] } end
  end
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
-- Son GUID doit avoir été donné par le serveur (chuchotement, cible, survol, groupe) : un contrat porte deux GUID.
function ns.ctFromDemande(order, days)
  local me, name = ns.me(), ns.fullName(order.player or "")
  if not name or name == "" or name == ns.myName() then return nil, "indique l'artisan (le joueur) dans la commande" end
  if not ns.nomComplet(name) then return nil, ("indique le nom complet « Prénom Nom » de l'artisan (%s seul ne suffit pas)"):format(name) end
  local artisan = ns.knownGUID[name]
  if not artisan then return nil, ("GUID de %s inconnu : cible-le, survole-le ou chuchote-lui d'abord"):format(name) end
  if artisan == me then return nil, "indique l'artisan (le joueur) dans la commande" end
  if #order.lines == 0 then return nil, "la commande est vide" end
  local m, o = demandeTerms(order)
  if not m then return nil, o end
  local id = now() -- plusieurs commandes d'un projet peuvent partir dans la même seconde : une clé chacune
  while store()[me .. "#" .. id] do id = id + 1 end
  return { origin = me, id = tostring(id), v = "1", parent = "0", client = me, artisan = artisan, m = m, o = o,
    peer = { guid = artisan, name = name, verified = true }, d = now() + math.floor((days or 3) * 86400) }
end

-- « Je réponds » (l'artisan, depuis l'arbre de sa réponse ; order = sa 1re commande) : ses apports et son prix, en
-- brouillon de nouvelle version, qui part de sa fiche dans Contrats.
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
-- prix de marché. Elle est préparée en brouillon (newVersion), relue dans Contrats avec le différentiel.
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

-- Terminé (CONTEXT.md) : plus rien n'en dépend. Un signé pas livré ne l'est pas (tant qu'il n'est pas échu).
local TERMINE = { clos = true, refuse = true, retire = true, echu = true }
function ns.ctTermine(c, t) return TERMINE[ns.ctStatus(c, t)] or false end
-- Quand il est devenu terminé : l'échéance pour un échu, le dernier échange pour un clos ; sinon (refusé, retiré) sa
-- réception ou son numéro (une date de création).
-- ponytail: refus et retrait ne sont pas datés ; noter le moment aux transitions si le « dernier terminé » se trompe.
local function fin(c, t)
  if ns.ctStatus(c, t) == "echu" then return c.d end
  return c.ledger and c.ledger[#c.ledger].t or c.received or tonumber(c.id) or 0
end
-- Archivé (CONTEXT.md, #72) : un champ du contrat (c.archive), réglé à chaque tri (l'échu vient du temps, pas d'une
-- transition). Tout terminé est archivé d'office, sauf le dernier terminé, gardé en vue ; un archivé le reste. Désarchiver
-- efface le champ et pose c.desarchive : l'archivage d'office ne reprend plus jamais ce contrat-là (le joueur l'a voulu en
-- vue ; il ne s'archive plus que d'une autre façon, s'il en vient une).
function ns.ctArchiver(t)
  local dernier, quand
  for _, c in pairs(store()) do
    if ns.ctTermine(c, t) and (not dernier or fin(c, t) > quand) then dernier, quand = c, fin(c, t) end
  end
  for _, c in pairs(store()) do
    if not ns.ctTermine(c, t) then c.archive = nil -- un signé pas livré n'est jamais archivé
    elseif c ~= dernier and not c.desarchive then c.archive = true end
  end
end
function ns.ctDesarchiver(c) c.archive, c.desarchive = nil, true end

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
  -- Le GUID du contrat fait foi ; le serveur donne celui du partenaire (n° 26, 31, 63). Un GUID déclaré jamais appris
  -- est vérifié ici, au premier échange, avant que rien ne bouge.
  local peer = c.peer or {}
  if snap.guid ~= peer.guid then bad("pas le bon personnage : son GUID n'est pas celui du contrat")
  elseif snap.partner ~= peer.name then
    if peer.verified then warn("même personnage, mais son nom a changé (" .. tostring(snap.partner) .. ")")
    else bad("ce n'est pas " .. tostring(peer.name)) end
  end
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
  -- Identité confirmée par le serveur au premier échange où nom et GUID correspondent ; confirmée, un nouveau nom sous
  -- le même GUID est un renommage : le nom du serveur est gardé.
  c.peer = c.peer or {}
  if snap.guid == c.peer.guid then
    if snap.partner == c.peer.name then c.peer.verified = true elseif c.peer.verified then c.peer.name = snap.partner end
  end
  c.ledger = c.ledger or {}
  table.insert(c.ledger, { t = t, give = snap.give, get = snap.get, conforme = r.ok, net = c.net })
  local artisan = me == c.artisan
  local inList, outList = artisan and c.m or c.o, artisan and c.o or c.m
  local done = c.net >= 0
  for _, l in ipairs(inList) do if (c.got[l.id] or 0) < l.qty then done = false end end
  for _, l in ipairs(outList) do if (c.gave[l.id] or 0) < l.qty then done = false end end
  if done then c.status = "clos" end
  return r
end

-- Les contrats signés du perso connecté (n° 53) avec un joueur, par son GUID ou son nom (pour le panneau d'échange :
-- même nom mais autre GUID, le panneau dit NON CONFORME).
function ns.ctActiveWith(partner, guid)
  local list, me = {}, ns.me()
  for _, c in pairs(store()) do
    local peer = c.peer or {}
    if c.status == "signe" and (c.client == me or c.artisan == me) and (peer.guid == guid or (partner and peer.name == partner)) then
      list[#list + 1] = c
    end
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
      HandshakeDB.surnames = nil -- noms de famille d'avant : le nom complet vient maintenant du serveur
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
