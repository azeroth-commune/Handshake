-- Handshake, la fenêtre des contrats (/contrat). Un contrat à la fois, sa fiche lue comme la fenêtre d'échange du jeu
-- (#73) : l'en-tête (la bulle du nom : GUID, empreinte, identité), les alertes quand il y en a (identité pas vérifiée,
-- nom proche, ce qui a changé depuis la version d'avant, vérifications), qui donne quoi à chaque étape en deux colonnes
-- avec l'avancement une fois signé, TON estimation de la caution et ta perte maximale (P8).
-- Accepter : jamais par Entrée ni fenêtre surgissante, bouton réarmé 2 s après l'affichage d'une version (P7).
-- « Vérifier et envoyer… » dans le panneau d'un contrat préparé (Emplacement.lua, un bloc commandé dans Composants)
-- en ouvre le brouillon, relu ici ; « Préparer la demande » dans la commande à la main (ns.mainPreparer) en fait un
-- brouillon, relu ici ; « Nouvelle version » et la Réponse de l'artisan, un brouillon de la version suivante : rien ne
-- part avant « Envoyer » (ns.ctEnvoyer, #71 : par Handshake s'il l'a, sinon en clair, et alors seulement « Il a dit
-- oui »). Montants (#74) : caution, livraison et délai sont des champs de la fiche d'un préparé ou d'un à signer ;
-- « Envoyer » part avec ce qu'ils montrent ; à signer, un champ changé remplace « Signer » par « Contre-proposer »
-- (la version suivante, envoyée du même clic) et « Annuler ». Une demande reçue se répond dans l'arbre de Composants,
-- ou dans la liste sans lui. La fenêtre retient la clé du contrat affiché, et chaque clic de sa fiche part avec ce
-- contrat-là, tel qu'affiché (empreinte), ou rien (#69).
local _, ns = ...

-- La colonne des contrats à gauche (COL_W), le contrat affiché à droite de X0. W × H : taille de départ et minimum, ce
-- que prend le cas courant (la fiche d'un contrat à deux étapes et sa rangée de boutons) ; le texte défile, on agrandit.
local COL_W, X0 = 150, 166
local W, H = 680, 400
local ENTREE_H, NOUVELLE_H, ARCHIVES_H = 34, 22, 22
local frame, list, pos, shownHash = nil, {}, 1, nil
local deplie = false -- « Archivés (n) » replié par défaut, pour la session (#72)
-- Le contrat affiché, retenu par sa clé à travers les rafraîchissements (#69), et l'empreinte de ce qui en est affiché.
local shownKey, shownEmpreinte
local firstShown = {} -- empreinte -> moment où cette version a été affichée pour la première fois (réarmement)
local STATUS = { brouillon = "|cff999999BROUILLON (pas envoyé)|r", envoye = "|cffe6994dEN ATTENTE DE SA RÉPONSE|r",
  a_signer = "|cffffd100À SIGNER PAR TOI|r", signe = "|cff59cc73SIGNÉ|r", clos = "|cff59cc73CLOS|r", echu = "|cffe64d4dÉCHU|r",
  refuse = "|cffe64d4dREFUSÉ|r", retire = "|cff999999RETIRÉ|r" }
-- Dans la colonne des contrats : l'état en un mot (avec la couleur de STATUS).
local COURT = { brouillon = "brouillon", envoye = "en attente", a_signer = "à signer", signe = "signé", clos = "clos",
  echu = "échu", refuse = "refusé", retire = "retiré" }
-- L'ordre de la colonne : à signer, préparé, en attente, signé, puis le dernier terminé (et les désarchivés) ; les
-- archivés à la fin, sous leur en-tête (#72).
local ORDER = { a_signer = 1, brouillon = 2, envoye = 3, signe = 4, echu = 5, clos = 6, refuse = 7, retire = 8 }

local money = function(c) return ns.moneyShort(c) end
local function rel(sec)
  if sec < 0 then return "dépassée" end
  local d, h, m = math.floor(sec / 86400), math.floor(sec % 86400 / 3600), math.floor(sec % 3600 / 60)
  return d > 0 and ("dans %d j %d h"):format(d, h) or ("dans %d h %d min"):format(h, m)
end
-- Montant exact en po pour les champs (4 décimales = au cuivre près) : renvoyer un champ inchangé ne doit rien changer.
local function po(c) return (("%.4f"):format(c / 10000):gsub("%.?0+$", "")) end

-- Besoins vérifiés contre les recettes connues (n° 12) : quantité maximale de chaque objet dans l'arbre complet,
-- et ses ancêtres (demander une barre ET son minerai = doublon).
local function expansion(o)
  local by = {}
  for _, r in pairs(ns.recipes()) do
    if r.output and r.reagents and not by[r.output] then by[r.output] = r end
  end
  local qty, anc, unknown = {}, {}, {}
  local function walk(id, n, path, depth)
    local r = by[id]
    if not r then if depth == 0 then unknown[#unknown + 1] = id end return end
    if depth > 10 or path[id] then return end
    path[id] = true
    local crafts = math.ceil(n / math.max(1, r.made_min or 1))
    for _, rg in ipairs(r.reagents) do
      if rg.id then
        local q = rg.qty * crafts
        qty[rg.id] = (qty[rg.id] or 0) + q
        anc[rg.id] = anc[rg.id] or {}
        for a in pairs(path) do anc[rg.id][a] = true end
        walk(rg.id, q, path, depth + 1)
      end
    end
    path[id] = nil
  end
  for _, l in ipairs(o) do walk(l.id, l.qty, {}, 0) end
  return qty, anc, unknown
end

local function plain(name) return name:lower():gsub("[\128-\255]", "") end

-- La fiche d'un contrat vue depuis ma place (me) : ce que la fenêtre dessine (#73), et rien d'autre. Rien n'y manque de
-- ce qui sert la sécurité, c'est seulement rangé : GUID, empreinte et identité dans la bulle du nom ; ce qui doit arrêter
-- l'œil (identité pas vérifiée, nom proche n° 26, différentiel n° 4, vérifications n° 11-12, échange à vérifier n° 37)
-- en alertes, en haut, seulement quand elles s'appliquent ; TON estimation et ta perte maximale en bas (P8).
--   titre, echeance, role ; bulle = { lignes } ; alertes = { textes } ;
--   etapes = { { titre, gauche = { titre, lignes }, droite = { titre, lignes } } }, la gauche toujours « Tu … » ; une
--   ligne : { id, qty, detail, fait, mot } (un objet ; detail = son prix au contrat ; fait = l'avancement, une fois
--   signé) ou { texte, champ, unite } (un montant ; champ = "caution" ou "livraison" : un champ à saisir, suivi de
--   unite, sur un préparé ou un à signer, #74) ;
--   apres = { notes sous les étapes } ; estimation = { textes }.
function ns.ctFiche(c, me)
  local status = ns.ctStatus(c)
  local peer, artisan = c.peer or {}, me == c.artisan
  local other = peer.name or "?" -- le nom donné par le serveur, jamais déduit du GUID
  local otherShort = other:match("^%S+") or other
  local caution, delivery = ns.ctTotal(c.m), ns.ctTotal(c.o)
  local f = { alertes = {}, etapes = {}, apres = {}, estimation = {} }
  local function alerte(s, rouge) f.alertes[#f.alertes + 1] = (rouge and "|cffe64d4d! " or "|cffe6994d! ") .. s .. "|r" end
  f.titre = ("%s · v%s · %s"):format(other:gsub("|", "||"), c.v, STATUS[status] or status)
  f.echeance = "échéance " .. rel(c.d - GetServerTime())
  f.role = artisan and "Tu es l'artisan." or "Tu es le client."
  f.bulle = { ns.identity(other, peer.guid),
    peer.verified and "|cff59cc73Identité confirmée par le serveur|r" or "|cffe6994dGUID annoncé, vérifié au premier échange|r",
    "Toi : " .. ns.myIdentity(), ("v%s · empreinte %s"):format(c.v, (c.hash or "—"):sub(1, 8)) }

  if c.enClair then alerte(("Parti en clair : %s n'a pas répondu par Handshake ; s'il dit oui, « Il a dit oui »."):format(other)) end
  if not peer.verified then alerte(("Identité de %s pas encore vérifiée : GUID annoncé, vérifié au premier échange"):format(otherShort)) end
  for _, x in pairs(ns.ctStore()) do -- n° 26 : nom presque identique à un autre partenaire
    local o2 = x.peer and x.peer.name or other
    if o2 ~= other and plain(o2) == plain(other) then alerte(("Nom très proche de %s : vérifie que c'est bien la bonne personne."):format(o2), true) break end
  end
  if c.prev then -- n° 4 : ce qui a changé
    local ch = {}
    local pc, pd = ns.ctTotal(c.prev.m), ns.ctTotal(c.prev.o)
    if pc ~= caution then ch[#ch + 1] = ("caution %s -> %s"):format(ns.money(pc), ns.money(caution)) end
    if pd ~= delivery then ch[#ch + 1] = ("livraison %s -> %s"):format(ns.money(pd), ns.money(delivery)) end
    if c.prev.d ~= c.d then ch[#ch + 1] = "échéance changée" end
    for _, pair in ipairs({ { c.prev.m, c.m }, { c.prev.o, c.o } }) do
      local old = {}
      for _, l in ipairs(pair[1]) do old[l.id] = l.qty end
      for _, l in ipairs(pair[2]) do
        if old[l.id] ~= l.qty then ch[#ch + 1] = ("%s %s -> %d"):format(ns.itemLabel(l.id), old[l.id] or "absent", l.qty) end
        old[l.id] = nil
      end
      for id in pairs(old) do ch[#ch + 1] = ns.itemLabel(id) .. " retiré" end
    end
    alerte(("Changé depuis la v%s : %s"):format(c.prev.v, #ch > 0 and table.concat(ch, " ; ") or "rien"))
  end
  if delivery - caution <= 0 then
    alerte(artisan and "Aucun prix pour ton travail : change la livraison ci-dessous, ou « Répondre » pour chiffrer ta part."
      or "Prix laissé à l'artisan : il le chiffrera en contre-proposant.")
  end
  -- Vérifications (n° 11, 12)
  for _, l in ipairs(c.o) do
    if select(14, C_Item.GetItemInfo(l.id)) == 1 then alerte(ns.itemLabel(l.id) .. " est lié quand ramassé : impossible à livrer", true) end
  end
  for _, l in ipairs(c.m) do
    if select(14, C_Item.GetItemInfo(l.id)) == 1 then alerte(ns.itemLabel(l.id) .. " est lié quand ramassé : impossible à fournir", true) end
  end
  if #c.m > 0 then
    local need, anc, unknown = expansion(c.o)
    if #unknown > 0 then alerte("recette inconnue pour " .. ns.itemLabel(unknown[1]) .. " : quantités de composants non vérifiables", true) end
    if #unknown == 0 then
      for _, l in ipairs(c.m) do
        if not need[l.id] then alerte(ns.itemLabel(l.id) .. " n'entre pas dans les recettes", true)
        elseif l.qty > need[l.id] then alerte(("%s : %d demandés, la recette en consomme %d"):format(ns.itemLabel(l.id), l.qty, need[l.id]), true) end
        for _, l2 in ipairs(c.m) do
          if anc[l2.id] and anc[l2.id][l.id] then alerte(ns.itemLabel(l.id) .. " ET son composant " .. ns.itemLabel(l2.id) .. " sont demandés", true) end
        end
      end
    end
  end
  if c.unconfirmed then alerte(("%d échange(s) à vérifier : terminés, mais ton or ou tes sacs n'ont pas bougé comme prévu"):format(#c.unconfirmed)) end

  -- Les étapes en deux colonnes, la mienne à gauche ; l'avancement (ce que ton addon a vu passer) une fois signé.
  local suivi = c.signed or c.ledger
  local function objets(list, recu, detail)
    local t = {}
    for _, l in ipairs(list) do
      t[#t + 1] = { id = l.id, qty = l.qty, detail = detail:format(ns.money(l.unit)), mot = recu and "reçu" or "donné",
        fait = suivi and ((recu and (c.got or {}) or (c.gave or {}))[l.id] or 0) or nil }
    end
    return t
  end
  local function etape(titre, jeTitre, ilTitre, mes, siens)
    f.etapes[#f.etapes + 1] = { titre = titre, gauche = { titre = "Tu " .. jeTitre, lignes = mes },
      droite = { titre = otherShort .. " " .. ilTitre, lignes = siens } }
  end
  local unique = #c.m == 0
  if not unique then
    local apports, cautionL = objets(c.m, artisan, "caution %s l'unité"),
      { { texte = ns.money(caution) .. " de caution", champ = "caution", unite = "po de caution" } }
    if artisan then etape("1. Composants", "donnes", "donne", cautionL, apports)
    else etape("1. Composants", "donnes", "donne", apports, cautionL) end
  end
  local livre, paie = objets(c.o, not artisan, "%s l'objet"), { { texte = ns.money(delivery), champ = "livraison", unite = "po" } }
  if not unique then paie[2] = { texte = ("|cff999999(caution rendue %s + prix %s)|r"):format(ns.money(caution), ns.moneySigned(delivery - caution)) } end
  local titre = unique and "Livraison" or "2. Livraison"
  if artisan then etape(titre, "livres", "paie", livre, paie) else etape(titre, "paies", "livre", paie, livre) end
  if unique then f.apres[#f.apres + 1] = "|cff999999Vente simple : rien n'est apporté, donc pas de caution ; le panneau vérifiera l'objet et le prix.|r" end
  if c.ledger then f.apres[#f.apres + 1] = ("Solde des échanges (reçu − donné, en valeurs du contrat) : %s"):format(ns.moneySigned(c.net or 0)) end

  -- P8 : ton estimation, ta perte maximale (ns.ctEstimation, la même que sur la page du projet), en une ligne.
  local e, parts = ns.ctEstimation(c, me), {}
  if not unique then
    parts[#parts + 1] = "composants ~" .. money(e.composants)
    parts[#parts + 1] = ("caution %s%+.0f %%|r"):format(e.alerte and "|cffe64d4d" or "|cff59cc73", e.ecart)
    parts[#parts + 1] = "perte max " .. money(e.perte) .. (artisan and " + ton travail" or "")
  end
  if e.valeur > 0 then parts[#parts + 1] = "objets livrés ~" .. money(e.valeur) end
  f.estimation[1] = ("|cffffd100Ton estimation|r (scan : %s) : %s"):format(e.scanned or "jamais", #parts > 0 and table.concat(parts, " · ") or "aucun prix connu")
  if e.manquants > 0 then f.estimation[2] = ("|cffe6994d! %d composant(s) sans prix connu : estimation incomplète|r"):format(e.manquants) end
  return f
end

-- Une ligne d'étape en texte : « 20 Cuivre  donné 3/20 », ou le montant.
local function ligneTexte(l)
  if not l.id then return l.texte end
  local s = ("%d %s"):format(l.qty, ns.itemLabel(l.id))
  if l.fait then s = s .. ("  %s%s %d/%d|r"):format(l.fait >= l.qty and "|cff59cc73" or "|cff999999", l.mot, l.fait, l.qty) end
  return s
end

-- La fiche en texte (vérification hors jeu, débogage) : tout ce que la fenêtre montre, bulle du nom comprise.
function ns.ctDescribe(c, me)
  local f, t = ns.ctFiche(c, me), {}
  local function add(s) t[#t + 1] = s end
  add(f.titre .. "   ·   " .. f.echeance)
  add(f.role)
  for _, s in ipairs(f.bulle) do add("   " .. s) end
  for _, s in ipairs(f.alertes) do add(s) end
  for _, e in ipairs(f.etapes) do
    add(e.titre)
    for _, col in ipairs({ e.gauche, e.droite }) do
      add("   " .. col.titre)
      for _, l in ipairs(col.lignes) do add("      " .. ligneTexte(l) .. (l.detail and ("   (" .. l.detail .. ")") or "")) end
    end
  end
  for _, s in ipairs(f.apres) do add(s) end
  for _, s in ipairs(f.estimation) do add(s) end
  return table.concat(t, "\n")
end

---------------------------------------------------------------------------------------------------
local function sorted()
  local l = {}
  for k, c in pairs(ns.ctStore()) do
    if ns.ctBrouillonPerime(c) then ns.ctStore()[k] = nil else l[#l + 1] = c end -- la version en cours a changé depuis
  end
  ns.ctArchiver() -- l'échu vient du temps : l'archivage se règle à chaque tri (#72)
  table.sort(l, function(a, b)
    if not a.archive ~= not b.archive then return not a.archive end
    local oa, ob = ORDER[ns.ctStatus(a)] or 9, ORDER[ns.ctStatus(b)] or 9
    if oa ~= ob then return oa < ob end
    return (a.received or tonumber(a.id) or 0) > (b.received or tonumber(b.id) or 0)
  end)
  return l
end

-- Ce qui est affiché d'un contrat (un brouillon n'a pas encore d'empreinte : on la calcule) : ses termes et son état.
local function empreinte(c) return ns.ctHash(ns.ctCanonical(c)) .. c.status end

-- Un objet de la fiche se comporte comme un objet du jeu (skill ui-addon, modèle : la frise de Maîtrise) : la vraie bulle
-- puis son prix au contrat ; Maj+clic = lien dans le chat, Ctrl+clic = cabine d'essayage (HandleModifiedItemClick).
local function lien(id)
  local l = ns.lienObjet(id)
  return l:find("|H", 1, true) and l or ("|cffffffff|Hitem:%d::::::::::::::::|h%s|h|r"):format(id, l) -- pas encore chargé : fait main
end
local function bulleObjet(self)
  local l = self.l
  if not (l and l.id) then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetItemByID(l.id)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(("%d au contrat, %s"):format(l.qty, l.detail), 1, 0.82, 0)
  GameTooltip:AddLine("Maj+clic : le lien dans le chat", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end
local function clicObjet(self)
  if self.l and self.l.id then HandleModifiedItemClick(lien(self.l.id)) end
end

-- La fiche du contrat affiché (frame.ficheDe), dessinée de haut en bas dans le contenu qui défile, à sa largeur :
-- en-tête, alertes, étapes en deux colonnes (la mienne à gauche), estimation (#73). Redessinée quand la largeur change.
local ETAPE_W, ICONE, CHAMP_W = 92, 16, 64
-- Les montants se saisissent sur la fiche d'un préparé ou d'un à signer (#74) ; ailleurs, ils se lisent.
local function saisissable(c) local s = ns.ctStatus(c) return s == "a_signer" or s == "brouillon" end
local function dessiner()
  local C, c = frame.content, frame.ficheDe
  local w = C:GetWidth()
  for _, r in ipairs(frame.fiche) do r:Hide() end
  for _, b in ipairs(frame.cellules) do b:Hide() end
  if not c then
    frame.vide:Show()
    frame.vide:SetWidth(w - 6)
    C:SetHeight(frame.vide:GetStringHeight() + 10)
    return
  end
  frame.vide:Hide()
  local f, y, n = ns.ctFiche(c, ns.me()), 0, 0
  local champs = saisissable(c) and frame.champs
  local function place(r, x, dy, largeur)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", C, "TOPLEFT", x, -(y + (dy or 0)))
    if largeur then r:SetWidth(largeur) end
    r:Show()
  end
  local function texte(r, s, x, largeur, apres)
    r:SetText(s)
    place(r, x, 0, largeur)
    y = y + r:GetStringHeight() + (apres or 6)
  end
  local function trait(r) place(r, 0, 2, w - 6); y = y + 10 end
  -- En-tête : le titre est le bouton de la bulle du nom ; l'échéance à droite.
  frame.titre:SetText(f.titre)
  frame.titre.bulle = f.bulle
  place(frame.titre, 0, 0, w - 6)
  frame.echeance:SetText(f.echeance)
  frame.echeance:Show()
  local avant = frame.echeance -- le délai à saisir, juste avant l'échéance
  if champs then
    champs.delai:Show(); champs.delaiTexte:Show()
    avant = champs.delaiTexte
  end
  frame.titre:GetFontString():SetPoint("RIGHT", avant, "LEFT", -8, 0)
  y = y + 22
  texte(frame.role, f.role, 0, w - 6)
  if #f.alertes > 0 then texte(frame.alertes, table.concat(f.alertes, "\n"), 0, w - 6) end
  trait(frame.traits[1])
  -- Les étapes : titre de l'étape et des deux colonnes sur une rangée, puis une rangée par ligne.
  local col = (w - 6 - ETAPE_W) / 2
  local function cellule(l, x)
    n = n + 1
    local b = frame.cellules[n] or frame.nouvelleCellule()
    local e = champs and l.champ and champs[l.champ] -- un montant à saisir : le champ, puis son unité
    b.l = l
    b.icone:SetShown(l.id ~= nil)
    if l.id then b.icone:SetTexture(C_Item.GetItemIconByID(l.id)) end
    b.texte:ClearAllPoints()
    b.texte:SetPoint("TOPLEFT", l.id and ICONE + 4 or e and CHAMP_W + 12 or 0, e and -6 or -3)
    b.texte:SetWidth(col - (l.id and ICONE + 8 or e and CHAMP_W + 16 or 4))
    b.texte:SetText(l.id and ligneTexte(l) or e and l.unite or l.texte)
    local h = math.max(e and 20 or ICONE, b.texte:GetStringHeight() + 3)
    b:SetSize(col - 4, h)
    place(b, x)
    if e then
      e:ClearAllPoints()
      e:SetPoint("TOPLEFT", b, "TOPLEFT", 6, 0)
      e:SetFrameLevel(b:GetFrameLevel() + 2) -- au-dessus de la cellule, qui prendrait le clic
      e:Show()
    end
    return h
  end
  for i, e in ipairs(f.etapes) do
    local t = frame.etapes[i]
    t[1]:SetText(e.titre); place(t[1], 0)
    t[2]:SetText(e.gauche.titre); place(t[2], ETAPE_W, 0, col - 4)
    t[3]:SetText(e.droite.titre); place(t[3], ETAPE_W + col, 0, col - 4)
    y = y + 16
    for k = 1, math.max(#e.gauche.lignes, #e.droite.lignes) do
      local h = 0
      if e.gauche.lignes[k] then h = math.max(h, cellule(e.gauche.lignes[k], ETAPE_W)) end
      if e.droite.lignes[k] then h = math.max(h, cellule(e.droite.lignes[k], ETAPE_W + col)) end
      y = y + h + 3
    end
    y = y + 6
  end
  if #f.apres > 0 then texte(frame.apres, table.concat(f.apres, "\n"), 0, w - 6) end
  trait(frame.traits[2])
  texte(frame.estimation, table.concat(f.estimation, "\n"), 0, w - 6, 4)
  C:SetHeight(y + 6)
  local barre = frame.scroll.ScrollBar
  if barre then barre:SetShown(C:GetHeight() > frame.scroll:GetHeight()) end -- la barre seulement si ça déborde, comme la colonne
end

-- Les champs des montants (#74), remplis avec les valeurs reçues une fois par version affichée (frame.champs.pour) : une
-- saisie n'est jamais écrasée par un rafraîchissement, et ne change ni le contrat ni son empreinte (#69) ; le clic lit
-- ce qu'ils montrent.
local function jours(c) return (("%.1f"):format(math.max(0, (c.d - GetServerTime()) / 86400)):gsub("%.0$", "")) end
local function remplir(c)
  local ch = frame.champs
  ch.remplit = true
  ch.recu = { caution = #c.m > 0 and ns.ctTotal(c.m) or nil, livraison = ns.ctTotal(c.o), delai = tonumber(jours(c)) }
  ch.caution:SetText(po(ns.ctTotal(c.m)))
  ch.livraison:SetText(po(ns.ctTotal(c.o)))
  ch.delai:SetText(jours(c))
  ch.remplit = nil
end
-- Ce que montrent les champs : pour chacun, rien s'il montre la valeur reçue, sinon sa valeur (cuivre, jours), ou false
-- s'il est illisible, négatif, ou (délai) hors de 0-30 jours ; modifie = au moins un champ diffère du reçu.
local function saisie()
  local ch, s = frame.champs, {}
  for nom, recu in pairs(ch.recu or {}) do
    local v = tonumber((ch[nom]:GetText():gsub(",", "."):gsub("^%s+", ""):gsub("%s+$", "")))
    if v and nom ~= "delai" then v = math.floor(v * 10000 + 0.5) end
    if v ~= recu then
      s[nom] = v and v >= 0 and (nom ~= "delai" or v > 0 and v <= 30) and v or false
      s.modifie = true
    end
  end
  return s
end
-- La saisie, ou nil, la raison du refus (une ligne : rien ne part).
local function lire()
  local s = saisie()
  if s.delai == false then return nil, "délai entre 0 et 30 jours : rien n'est parti" end
  if s.caution == false or s.livraison == false then return nil, "montant illisible ou négatif : rien n'est parti" end
  return s
end

-- Les boutons du bas, au plus trois (skill ui-addon) : préparé, « Envoyer » ; à signer, « Signer · Refuser · Répondre »,
-- ou « Contre-proposer · Annuler » dès qu'un champ diffère du reçu (on ne signe jamais autre chose que ce qui est
-- affiché) ; en attente, « Retirer » (et « Il a dit oui » parti en clair) ; signé ou terminé, aucun.
local function boutons()
  for _, b in ipairs(frame.actions) do b:Hide() end
  local c = frame.ficheDe
  if not c then return end
  local status = ns.ctStatus(c)
  if status == "a_signer" then
    if saisie().modifie then
      frame.counter:Show(); frame.cancel:Show()
      frame.counter:SetEnabled(not ns.ctEnAttente(c)) -- en route, sa réponse attendue : pas de second envoi (#71)
    else
      frame.accept:Show(); frame.refuse:Show()
      if c.artisan == ns.me() then frame.reply:Show() end
    end
  elseif status == "brouillon" then
    frame.send:Show()
    frame.send:SetEnabled(not ns.ctEnAttente(c)) -- la question de présence est partie : pas de second envoi (#71)
  elseif status == "envoye" then
    frame.withdraw:Show()
    if c.enClair then frame.manual:Show() end -- seulement parti en clair : parti par Handshake, sa signature compte
  end
  -- Réarmement (n° 5) : « Signer » et « Il a dit oui » (une signature locale) s'activent 2 s après le premier affichage
  -- de CE contrat dans CET état, ou après « Annuler » ; « Refuser » avec « Signer » (il prend la place d'« Annuler »). Le
  -- clic porte l'empreinte affichée, un autre contrat ne peut pas être signé par lui.
  local signe = (frame.accept:IsShown() and frame.accept) or (frame.manual:IsShown() and frame.manual)
  if signe then
    firstShown[shownEmpreinte] = firstShown[shownEmpreinte] or GetTime()
    local wait = 2 - (GetTime() - firstShown[shownEmpreinte])
    signe:SetEnabled(wait <= 0)
    frame.refuse:SetEnabled(wait <= 0)
    if wait > 0 then C_Timer.After(wait + 0.05, boutons) end
  end
end

local function refresh()
  if Composants then Composants.Rafraichir() end -- l'état des contrats d'un projet (son emplacement du bloc) se lit ici
  if ns.refreshCommandeMain then ns.refreshCommandeMain() end
  if not (frame and frame:IsShown()) then return end
  list = sorted()
  -- Le contrat affiché se retrouve par sa clé, pas par sa place : une proposition arrivée en tête ou un brouillon périmé
  -- effacé ne font rien glisser sous les yeux (#69). Son brouillon parti ou effacé : sa version en cours ; sans version en
  -- cours (brouillon v1 abandonné, contrat effacé) : la tête de liste, pas ce qui a glissé à sa place.
  local function trouve(k) for i, x in ipairs(list) do if ns.ctKey(x) == k then return i end end end
  pos = shownKey and (trouve(shownKey) or trouve((shownKey:gsub("%+$", "")))) or 1
  pos = math.min(math.max(1, pos), math.max(1, #list))
  local c = list[pos]
  shownKey, shownEmpreinte = c and ns.ctKey(c), c and empreinte(c)
  frame.syncColonne() -- la liste et le contrat affiché ont pu changer
  frame.ficheDe = c
  shownHash = c and c.hash
  -- Une autre version du contrat affiché (la sienne, arrivée pendant la saisie) : la fiche passe à elle, les saisies sont
  -- jetées, et une ligne le dit ; « Signer » revient désarmé (nouvelle empreinte, n° 5).
  local ch = frame.champs
  local pour = c and saisissable(c) and ns.ctKey(c) .. "|" .. (c.hash or ns.ctCanonical(c)) or nil
  if pour ~= ch.pour then
    if c and ch.cle == ns.ctKey(c) and ns.ctStatus(c) == "a_signer" and saisie().modifie then
      print(("|cffa98fffContrats :|r %s a envoyé une v%s : tes modifications sont annulées."):format(c.peer.name, c.v))
    end
    ch.pour, ch.cle, ch.recu = pour, c and ns.ctKey(c), nil
    if pour then remplir(c) end
  end
  dessiner()
  boutons()
end
ns.refreshContracts = refresh

ns.ctNotify = function(text)
  print("|cffa98fffContrats :|r " .. text)
  refresh()
end

local function build()
  frame = ns.newWindow("HandshakeContratsFrame", "Contrats", W, H)
  local function button(text, w, onClick)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    -- Un clic agit sur le contrat AFFICHÉ (#69, P3) : relu dans la base par sa clé, et seulement s'il n'a pas changé depuis
    -- l'affichage (même empreinte) ; sinon rien ne part, et le contrat redessiné est à relire.
    b:SetScript("OnClick", function()
      local c = shownKey and ns.ctStore()[shownKey]
      if c and empreinte(c) == shownEmpreinte then
        onClick(c)
        shownKey = ns.ctKey(c) -- un brouillon parti change de clé (« origine#id+ » -> « origine#id »)
      else
        print("|cffe64d4dContrats :|r le contrat affiché a changé : relis-le, rien n'est parti.")
      end
      refresh()
    end)
    return b
  end
  -- Le contrat affiché : une colonne de tous les contrats, comme celle des projets de Composants (skill ui-addon : pas de
  -- menu déroulant) ; une entrée par contrat : l'icône du premier objet livré, le nom de l'autre, l'état en couleur en
  -- dessous (la version est sur la fiche) ; la bulle donne tous les objets. Celle affichée surlignée (le surlignage du
  -- jeu, tenu, et un trait doré) ; clic = l'afficher. Elle défile au-delà de sa hauteur. En bas, « Archivés (n) », replié
  -- par défaut ; clic droit sur un archivé : « Désarchiver » (#72). En tête, fixe hors de la liste qui défile,
  -- « + Nouvelle commande » : la Commande à la main, sans arbre ni projet (#38, #70).
  local col = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
  col:SetPoint("TOPLEFT", 10, -30) -- sous la barre de titre du gabarit
  col:SetPoint("BOTTOMLEFT", 10, 10)
  col:SetWidth(COL_W)
  local sc = CreateFrame("ScrollFrame", nil, col, "UIPanelScrollFrameTemplate")
  sc:SetPoint("TOPLEFT", 4, -4 - NOUVELLE_H)
  sc:SetPoint("BOTTOMRIGHT", -24, 4)
  local liste = CreateFrame("Frame", nil, sc)
  liste:SetSize(COL_W - 28, 1)
  sc:SetScrollChild(liste)
  local nouvelle = CreateFrame("Button", nil, col)
  nouvelle:SetSize(COL_W - 28, NOUVELLE_H - 2)
  nouvelle:SetPoint("TOPLEFT", 4, -4)
  nouvelle:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  nouvelle:SetFontString(nouvelle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")) -- doré, aligné sur les noms
  nouvelle:GetFontString():SetPoint("LEFT", 8, 0)
  nouvelle:SetText("+ Nouvelle commande")
  nouvelle:SetScript("OnClick", function() ns.openCommandeMain() end)
  -- L'en-tête des archivés, comme ceux du journal de quêtes (le + / – du jeu).
  local archives = CreateFrame("Button", nil, liste)
  archives:SetSize(COL_W - 28, ARCHIVES_H - 2)
  archives:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  archives.signe = archives:CreateTexture(nil, "ARTWORK")
  archives.signe:SetSize(14, 14)
  archives.signe:SetPoint("LEFT", 6, 0)
  archives:SetFontString(archives:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"))
  archives:GetFontString():SetPoint("LEFT", archives.signe, "RIGHT", 4, 0)
  archives:SetScript("OnClick", function() deplie = not deplie; frame.syncColonne() end)
  frame.archives = archives
  frame.entrees = {}
  local function entree(i)
    local b = CreateFrame("Button", nil, liste)
    b:SetSize(COL_W - 28, ENTREE_H - 2)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.fond = b:CreateTexture(nil, "BACKGROUND")
    b.fond:SetAllPoints()
    b.fond:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    b.fond:SetBlendMode("ADD")
    b.fond:SetVertexColor(1, 0.82, 0, 0.5)
    b.trait = b:CreateTexture(nil, "ARTWORK")
    b.trait:SetPoint("TOPLEFT"); b.trait:SetPoint("BOTTOMLEFT"); b.trait:SetWidth(2)
    b.trait:SetColorTexture(1, 0.82, 0, 0.9)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.icone = b:CreateTexture(nil, "ARTWORK")
    b.icone:SetSize(22, 22)
    b.icone:SetPoint("LEFT", 6, 0)
    b.nom = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.nom:SetPoint("TOPLEFT", 32, -4); b.nom:SetPoint("RIGHT", -4, 0)
    b.nom:SetJustifyH("LEFT"); b.nom:SetWordWrap(false)
    b.etat = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.etat:SetPoint("TOPLEFT", 32, -18); b.etat:SetPoint("RIGHT", -4, 0)
    b.etat:SetJustifyH("LEFT")
    b:SetScript("OnClick", function(self, souris)
      local c = self.c
      if souris ~= "RightButton" then shownKey = ns.ctKey(c); return refresh() end
      if c.archive then
        MenuUtil.CreateContextMenu(self, function(_, root)
          root:CreateButton("Désarchiver", function() ns.ctDesarchiver(c); refresh() end)
        end)
      end
    end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(self.nom:GetText())
      for _, l in ipairs(self.c.o) do GameTooltip:AddLine(("%d × %s"):format(l.qty, ns.itemLabel(l.id)), 1, 1, 1) end
      if self.c.archive then GameTooltip:AddLine("Clic droit : Désarchiver", 0.6, 0.6, 0.6) end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.entrees[i] = b
    return b
  end
  frame.syncColonne = function()
    local n, y = 0, 0
    for _, c in ipairs(list) do if c.archive then n = n + 1 end end
    archives:SetShown(n > 0)
    archives:SetText(("Archivés (%d)"):format(n))
    archives.signe:SetTexture(deplie and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
    for i, c in ipairs(list) do
      local b = frame.entrees[i] or entree(i)
      if i == #list - n + 1 then archives:SetPoint("TOPLEFT", 0, -y); y = y + ARCHIVES_H end -- le premier archivé
      local s = ns.ctStatus(c)
      b.c = c
      b.nom:SetText(c.peer and c.peer.name or "?")
      b.icone:SetTexture(c.o[1] and C_Item.GetItemIconByID(c.o[1].id) or "Interface\\Icons\\INV_Misc_Note_01")
      local couleur = (STATUS[s] or ""):match("^|c" .. ("%x"):rep(8)) -- la couleur de l'état en entier (8 chiffres : « |cff999999BROUILLON »)
      b.etat:SetText(couleur and (couleur .. (COURT[s] or s) .. "|r") or (COURT[s] or s))
      b.fond:SetShown(i == pos)
      b.trait:SetShown(i == pos)
      b:SetAlpha(c.archive and 0.5 or 1)
      b:SetPoint("TOPLEFT", 0, -y)
      b:SetShown(not c.archive or deplie)
      if b:IsShown() then y = y + ENTREE_H end
    end
    for i = #list + 1, #frame.entrees do frame.entrees[i]:Hide() end
    liste:SetHeight(y + 8)
    if sc.ScrollBar then sc.ScrollBar:SetShown(liste:GetHeight() > sc:GetHeight()) end -- la barre seulement si ça déborde
  end

  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", X0, -34) -- sous la barre de titre
  scroll:SetPoint("BOTTOMRIGHT", -32, 44)
  local C = CreateFrame("Frame", nil, scroll)
  frame.content, frame.scroll = C, scroll
  C:SetSize(W - X0 - 36, 1)
  scroll:SetScrollChild(C)
  scroll:SetScript("OnSizeChanged", function(_, w) -- la fiche suit la largeur de la fenêtre agrandie
    C:SetWidth(w)
    if frame.cellules then dessiner() end
  end)
  -- Les morceaux de la fiche (dessiner les place) : frame.fiche les liste pour tout cacher d'un coup.
  frame.fiche, frame.cellules, frame.traits, frame.etapes = {}, {}, {}, {}
  local function fs(police)
    local t = C:CreateFontString(nil, "OVERLAY", police or "GameFontHighlightSmall")
    t:SetJustifyH("LEFT")
    t:SetSpacing(2)
    frame.fiche[#frame.fiche + 1] = t
    return t
  end
  frame.vide = C:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.vide:SetPoint("TOPLEFT")
  frame.vide:SetJustifyH("LEFT")
  frame.vide:SetText("|cff999999Aucun contrat. « Commander » un bloc dans Composants, ou « + Nouvelle commande » puis « Préparer la demande ».|r")
  frame.titre = CreateFrame("Button", nil, C)
  frame.titre:SetHeight(16)
  frame.titre:SetFontString(frame.titre:CreateFontString(nil, "OVERLAY", "GameFontNormal"))
  frame.titre:GetFontString():SetPoint("LEFT")
  frame.titre:GetFontString():SetJustifyH("LEFT")
  frame.titre:GetFontString():SetWordWrap(false)
  frame.titre:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    for i, l in ipairs(self.bulle) do
      if i == 1 then GameTooltip:AddLine(l) else GameTooltip:AddLine(l, 1, 1, 1) end
    end
    GameTooltip:Show()
  end)
  frame.titre:SetScript("OnLeave", function() GameTooltip:Hide() end)
  frame.fiche[#frame.fiche + 1] = frame.titre
  frame.echeance = fs()
  frame.echeance:SetPoint("TOPRIGHT", C, "TOPRIGHT", -6, -2)
  frame.echeance:SetJustifyH("RIGHT")
  frame.titre:GetFontString():SetPoint("RIGHT", frame.echeance, "LEFT", -8, 0)
  frame.role, frame.alertes, frame.apres, frame.estimation = fs(), fs(), fs(), fs()
  for i = 1, 2 do
    local t = C:CreateTexture(nil, "ARTWORK")
    t:SetHeight(1)
    t:SetColorTexture(1, 0.82, 0, 0.25)
    frame.traits[i] = t
    frame.fiche[#frame.fiche + 1] = t
  end
  for i = 1, 2 do frame.etapes[i] = { fs("GameFontNormalSmall"), fs("GameFontNormalSmall"), fs("GameFontNormalSmall") } end
  -- Les champs des montants (#74), placés par dessiner : caution et livraison dans leur étape, le délai dans l'en-tête.
  -- Entrée ne valide rien (P7, n° 25) ; chaque frappe ne fait que choisir les boutons (Signer ou Contre-proposer).
  local ch = {}
  local function champ(w)
    local e = CreateFrame("EditBox", nil, C, "InputBoxTemplate")
    e:SetSize(w, 20)
    e:SetAutoFocus(false)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    e:SetScript("OnTextChanged", function() if not ch.remplit then boutons() end end)
    frame.fiche[#frame.fiche + 1] = e
    return e
  end
  ch.caution, ch.livraison, ch.delai = champ(CHAMP_W), champ(CHAMP_W), champ(32)
  ch.delai:SetPoint("RIGHT", frame.echeance, "LEFT", -10, 0)
  ch.delaiTexte = fs()
  ch.delaiTexte:SetText("délai (jours)")
  ch.delaiTexte:SetPoint("RIGHT", ch.delai, "LEFT", -10, 0)
  frame.champs = ch
  frame.nouvelleCellule = function()
    local b = CreateFrame("Button", nil, C)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.icone = b:CreateTexture(nil, "ARTWORK")
    b.icone:SetSize(ICONE, ICONE)
    b.icone:SetPoint("TOPLEFT")
    b.texte = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.texte:SetJustifyH("LEFT")
    b:SetScript("OnEnter", bulleObjet)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", clicObjet)
    frame.cellules[#frame.cellules + 1] = b
    return b
  end

  -- Actions (bas de la fenêtre)
  local function non(err) print("|cffe64d4dContrats :|r " .. err .. ".") end
  frame.accept = button("Signer", 90, function(c) if not ns.ctAccept(c, shownHash) then print("Contrats : la version affichée a changé, relis-la.") end end)
  frame.refuse = button("Refuser", 80, function(c) ns.ctRefuse(c) end)
  -- « Répondre » (l'artisan) : la Réponse, un projet tenu de Composants ouvert en Préparer ; sans Composants, la liste (#38).
  frame.reply = button("Répondre", 90, function(c)
    if Composants then Composants.Ouvrir(ns.projetReponse(c).id) else ns.openCommandeMain(c) end
  end)
  -- Contre-proposer (#74) : la version suivante avec les montants affichés, envoyée du même clic par la règle d'Envoyer.
  -- Refusée (bornes, pas de réponse de son Handshake…) : une ligne le dit, les champs gardent la saisie.
  frame.counter = button("Contre-proposer", 130, function(c)
    local s, err = lire()
    if not s then return non(err) end
    if not s.modifie then return end
    local ok, pourquoi = ns.ctCounter(c, s.caution, s.livraison, s.delai)
    if not ok then non(pourquoi) end
  end)
  -- Annuler : les montants reçus reviennent, et « Signer », réarmé (n° 5).
  frame.cancel = button("Annuler", 80, function(c)
    remplir(c)
    firstShown[shownEmpreinte] = GetTime()
  end)
  -- Envoyer (#71) : avec les montants affichés (le brouillon les prend), par Handshake s'il l'a, sinon en clair ; une
  -- ligne dans le chat dit comment il est parti.
  frame.send = button("Envoyer", 90, function(c)
    local s, err = lire()
    if not s then return non(err) end
    ns.ctEditDraft(c, s.caution, s.livraison, s.delai)
    local ok, pourquoi = ns.ctEnvoyer(c)
    if not ok then non(pourquoi) end
  end)
  frame.withdraw = button("Retirer", 90, function(c) ns.ctWithdraw(c) end)
  -- Parti en clair, il n'a pas Handshake : tu notes son accord. Ton panneau vérifiera tes échanges contre TA copie.
  frame.manual = button("Il a dit oui", 110, function(c) ns.ctIlADitOui(c) end)
  frame.actions = { frame.accept, frame.refuse, frame.reply, frame.counter, frame.cancel, frame.send, frame.withdraw, frame.manual }
  frame.accept:SetPoint("BOTTOMLEFT", X0, 12)
  frame.refuse:SetPoint("LEFT", frame.accept, "RIGHT", 6, 0)
  frame.reply:SetPoint("LEFT", frame.refuse, "RIGHT", 6, 0)
  frame.counter:SetPoint("BOTTOMLEFT", X0, 12)
  frame.cancel:SetPoint("LEFT", frame.counter, "RIGHT", 6, 0)
  frame.send:SetPoint("BOTTOMLEFT", X0, 12)
  frame.withdraw:SetPoint("BOTTOMLEFT", X0, 12)
  frame.manual:SetPoint("LEFT", frame.withdraw, "RIGHT", 6, 0)

  frame:SetScript("OnShow", refresh)
end

function ns.openContracts(key)
  if not frame then build() end
  frame:Show()
  if key then shownKey = key end
  refresh()
end

SLASH_HANDSHAKECONTRAT1 = "/contrat"
SlashCmdList.HANDSHAKECONTRAT = function() ns.openContracts() end
