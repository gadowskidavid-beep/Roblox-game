# QOF-24 – Kanonische Schadenspräzision

Status: **Abgeschlossen – Fortsetzung durch ausdrückliches Nutzer-`Weiter`; Studio-Ergebnis nicht separat gemeldet**

Implementierungscommit: `52a335690d56a236016194065e5fa8138457e6ef`

QOF-24 entfernt Zwischenrundungen aus dem serverautoritativen Kampfschaden. Basisvariante, Shiny, Strong-Enchant, Quest-/Upgradefaktor und Shopfaktor werden in einer einzigen ungerundeten Kette verrechnet. Der replizierte Wert `pet.damage` bleibt ausschließlich Kompatibilitäts-/Anzeige-Mirror und besitzt keine Kampfauthorität.

## Kanonischer Vertrag

- `PetVariantMath.getPetBaseDamage` bestimmt den Basiswert aus Pet-Art, `Normal`/`Golden`/`Rainbow` und dem unabhängigen Shiny-Modifier.
- `PetEnchantMath.getDamageMultiplier` liefert ausschließlich den kanonischen Strong-I–III-Faktor; Agile und gefälschte Pet-Felder bleiben neutral.
- Quest-/Upgrade- und Shopfaktor werden über geschützte Provideraufrufe aufgelöst.
- Jeder endliche Faktor größer als `0` ist gültig. Damit bleiben auch echte Reduktionsfaktoren wie `0.5` wirksam und `1` neutral.
- `0`, negative Werte, `NaN`, positive/negative Unendlichkeit, falsche Typen, fehlende Provider und Providerfehler werden auf den neutralen Faktor `1` normalisiert.
- Der vollständige Wert wird als `base × enchant × quest × shop` ohne `math.floor` berechnet. Erst danach wird das Gesamtergebnis validiert.
- Ein nicht endliches Gesamtergebnis, etwa durch numerischen Overflow, liefert fail-closed `0` und gelangt nicht in den Kampfzustand.
- Mehrere Pets werden in `ZoneService` ungerundet summiert. Zwei Pets mit je `4.5` ergeben exakt `9`.
- Overkill ist keine Rundung: Der einmalige Zielgrenzwert ist `min(Gesamtschaden, verbleibende HP)`. Bei `9` Schaden gegen `8` HP werden exakt `8` angewandt und als Beitrag erfasst.
- Campaign-Deploy, Pet-HP (`damage × 5`), reguläre Gegner, Bosse und gegnerische Basis behalten Bruchwerte unverändert.
- Bestehende Ganzzahlgrenzen der Economy-Verteilung bleiben unverändert; sie runden Rewards, nicht Kampfschaden.

## Abgedeckte Regressionen

- Alle sechs Zustände Normal, Normal Shiny, Golden, Golden Shiny, Rainbow und Rainbow Shiny.
- Ein kanonischer `Splash` Normal Shiny bleibt bei `4.5`, selbst wenn `pet.damage` gefälscht ist.
- Strong I, II und III liefern aus `4.5` exakt `4.5 × 1.10`, `4.5 × 1.25` und `4.5 × 1.50`.
- Enchant-, Quest- und Shopfaktor verwenden denselben ungerundeten Zwischenwert.
- Positive Faktoren in `(0,1)`, neutraler Faktor `1`, hostile Faktoren und Providerfehler.
- Overflow des vollständigen Produkts.
- Zwei `4.5`-Pets summieren sich in einem echten `ZoneService.attackDestructible`-Pfad zu `9`; ein 8-HP-Ziel erhält exakt `8`.
- Campaign speichert `damage = 4.5`, `hp = maxHp = 22.5` und zieht Gegnern, Bossen sowie der gegnerischen Basis jeweils exakt `4.5` ab.

## Lokale Verifikation

- Gepinnte Pflicht-Toolchain erfolgreich geprüft (`rbxmk 0.9.1`, Luau/Compiler `0.735`).
- Python-Compile für Tools und Tests erfolgreich.
- Luau-Compile: **78/78** Runtime-Sources.
- Vollständige Luau-Suite: **366/366** in kanonischer und umgekehrter Reihenfolge.
- `verify_generated_place.py`: 78 Sources bytegenau, davon 76 ModuleScripts, 1 Script und 1 LocalScript.
- Unabhängiger QOF-24-Releaseverifier, Fresh-Build-Vergleich, RBXL-Signatur, kanonisches ZIP und SHA-Manifest erfolgreich.
- `git diff --check` erfolgreich.

## Testartefakt

| Artefakt | Bytes | SHA-256 |
|---|---:|---|
| `BATTLE_PETS.rbxlx` | 1.117.390 | `293d80b391340210bfcfbcb123a995fdc37e8b817e4d7b04577bb2a7759e5760` |
| `BATTLE_PETS_QOF-24_TEST.rbxl` | 394.245 | `68ec212191c21d9d2f524bada14e20eef2505c3ff5848e22c35a5ba6dd5f33bb` |
| `BATTLE_PETS_QOF-24_RBXLX.zip` | 224.452 | `a2c950185b60a62f53788b74f198e93c0d02dcf30f9a3e0f78e0ff273166979e` |
| `BATTLE_PETS_QOF-24_SHA256SUMS.txt` | 1.080 | `bd12420d1989dd4a184e0ecc6ae90340666b52b56aa79955075120a8126e3b1c` |

Die RBXL beginnt mit der exakten binären Roblox-Signatur `<roblox!\x89\xff\r\n\x1a\n`.

## Verbindlicher Studio-Testplan

1. `BATTLE_PETS_QOF-24_TEST.rbxl` in Roblox Studio öffnen und **Play** starten. Erwartet: Welt und UI laden ohne rote Fehler im Output; vorhandene Pets, Währungen und Zonen erscheinen unverändert.
2. Für die exakten Zahlen möglichst ein frisches Testprofil ohne StrongPets-Questbonus und ohne aktiven Damage-Shopbuff verwenden. In der **Server**-Command-Bar ausführen:
   ```lua
   local player = game:GetService("Players"):GetPlayers()[1]
   local PetService = require(game.ServerScriptService.Services.PetService)
   local cases = {
       {"Normal", false}, {"Normal", true},
       {"Golden", false}, {"Golden", true},
       {"Rainbow", false}, {"Rainbow", true},
   }
   for _, case in ipairs(cases) do
       print("QOF24_BASE", case[1], case[2], PetService.getPetDamage({
           petId = "Splash", variant = case[1], shiny = case[2], damage = 999999,
       }, player))
   end
   ```
   Erwartet in Reihenfolge: `3`, `4.5`, `6`, `9`, `15`, `22.5`. Der gefälschte Mirror `999999` darf nie erscheinen.
3. Strong I–III in derselben Server-Command-Bar prüfen:
   ```lua
   local player = game:GetService("Players"):GetPlayers()[1]
   local PetService = require(game.ServerScriptService.Services.PetService)
   for _, enchantId in ipairs({"StrongI", "StrongII", "StrongIII"}) do
       print("QOF24_STRONG", enchantId, PetService.getPetDamage({
           petId = "Splash", variant = "Normal", shiny = true,
           enchantId = enchantId, damage = 999999,
       }, player))
   end
   ```
   Erwartet: `4.95`, `5.625`, `6.75` beziehungsweise die mathematisch äquivalenten Luau-Fließkommadarstellungen; kein Zwischen-Floor.
4. Zwei-Pet-Summe prüfen:
   ```lua
   local player = game:GetService("Players"):GetPlayers()[1]
   local PetService = require(game.ServerScriptService.Services.PetService)
   local pet = {petId = "Splash", variant = "Normal", shiny = true}
   print("QOF24_TWO_PETS", PetService.getPetDamage(pet, player) + PetService.getPetDamage(pet, player))
   ```
   Erwartet: exakt `9` bei neutralem Quest-/Shopzustand.
5. Gameplay-Overkill prüfen: Zwei entsprechend ausgerüstete `Splash` Normal Shiny auf ein Destructible mit höchstens 9 verbleibenden HP schicken. Erwartet: Das Ziel fällt in einem Tick; weder negativer HP-Wert noch überhöhter Reward-Beitrag, doppelter Drop oder roter Serverfehler entsteht.
6. Campaign öffnen und ein Pet mit Bruchschaden einsetzen, idealerweise `Splash` Normal Shiny. Erwartet: Deploy gelingt, reguläre Gegner und Bosse verlieren pro Treffer denselben Bruchschaden; die gegnerische Basis ebenfalls. Es gibt keinen Sprung auf `4` oder eine andere Zwischenrundung.
7. Einen Golden-/Rainbow-, Shiny-, Strong- und Agile-Smoke durchführen. Erwartet: Varianten- und Strong-Schaden bleiben korrekt; Agile verändert nur die Campaign-Laufgeschwindigkeit und nicht den Schaden.
8. Spiel verlassen, erneut beitreten und Inventar, Destructible-Kampf sowie Campaign erneut öffnen. Erwartet: gespeicherte Pets bleiben unverändert; `pet.damage` beeinflusst die serverseitige Berechnung weiterhin nicht.
9. Optional Mobile-/Tablet-Smoke: Inventar, Weltkampf und Campaign bedienen. Erwartet: keine neue QOF-24-spezifische UI- oder Laufzeitstörung.

## Bekannte Grenzen

Der echte Roblox-Studio-Playtest, Physik-/Netzwerkpfad und DataStore-Rejoin können im Linux-Sandbox-Build nicht ausgeführt werden. Die Serverautorität behält IEEE-754/Luau-Fließkommazahlen; QOF-24 führt keine Decimal-/Fixed-Point-Economy ein. UI darf Zahlen weiterhin formatieren, ohne die Kampfauthorität zu ändern. Der Nutzer hat anschließend ausdrücklich `Weiter` geschrieben und damit die Fortsetzung zu QOF-25 freigegeben; ein separates positives Studio-Ergebnis wurde nicht gemeldet und wird deshalb nicht behauptet.
