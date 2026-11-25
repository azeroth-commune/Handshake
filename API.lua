-- Handshake n'offre plus d'API publique (Composants#26) : c'est lui qui se branche sur Composants, par l'emplacement du
-- bloc (Composants.Emplacements, Emplacement.lua) ; Composants ne connaît ni Handshake ni les contrats. Le global reste,
-- vide : il dit seulement que Handshake est chargé.
Handshake = {}
