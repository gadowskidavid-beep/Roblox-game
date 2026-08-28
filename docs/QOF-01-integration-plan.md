# QOF-01 – Battle Pets Upgrade-System: Integrationsplan

**Status:** Planung abgeschlossen – keine Gameplay-Implementierung in QOF-01
**Ausgangsbranch:** `feat/battle-pets-upgrade-tree` (`8e6f8ee`)
**Spiel-/UI-Sprache:** Englisch
**Persistenz:** Roblox `DataStoreService` über den vorhandenen `DataService`

## 1. Ziel und Grenzen

QOF-01 legt den verbindlichen Daten-, Server-, Client-, UI-, Welt- und Build-Vertrag für die folgenden QOF-Pakete fest. In dieser Phase werden keine Preise balanciert, keine Käufe verändert und keine neuen Gameplay-Effekte aktiviert.

Folgende Systeme gehören zum Zielumfang:

- Egg Quality, Multi-Open und Auto-Hatch
- direkte Gold-, Rainbow- und Shiny-Hatches
- besondere Multi-/Rare-Hatch-Animationen
- Speed, Storage, Magnet, Double Luck und Pet Equip Slots
- persistente Potions, aktive Buffs, Potion Slots, Duration+ und Auto-Drink
- physische Gold- und Rainbow-Maschinen in verschiedenen Zonen
- Pet Enchanting und Pet Dex

Ausgeschlossen bleiben:

- Mythic
- Pet-Leveling
- Cosmetics/Trails/Emotes als eigenes Progressionssystem
- Prestige
- Fusion Potions

`upgradeTree.lua` und das Vide-Framework bleiben unverändert. Erweiterungen erfolgen über Daten, Adapter, Services, Controller und neue UI-/Welt-Komponenten.

## 2. Verbindliche Produktregeln

### 2.1 Pet-Varianten und Shiny

Intern bleiben die vorhandenen Basisvarianten kompatibel:

| Interner Wert | UI-Name | Basisschaden |
|---|---|---:|
| `Normal` | Normal | x1 |
| `Golden` | Gold | x2 |
| `Rainbow` | Rainbow | x5 |

Shiny ist künftig **keine exklusive Basisvariante**, sondern ein unabhängiges Boolean-Merkmal `shiny=true`, das auf jede Basisvariante angewendet werden kann.

| Kombination | Gesamtschaden vor weiteren Buffs |
|---|---:|
| Normal | x1 |
| Normal Shiny | x1,5 |
| Gold | x2 |
| Gold Shiny | x3 |
| Rainbow | x5 |
| Rainbow Shiny | x7,5 |

Formel:

```text
finalPetBaseDamage = speciesBaseDamage × baseVariantMultiplier × shinyMultiplier
shinyMultiplier = 1.5 when shiny=true, otherwise 1
```

Quest-, Mastery-, Shop- und andere Schadensbuffs werden anschließend serverseitig angewendet. `pet.damage` darf langfristig nicht mehr die Varianten-Autorität sein; die Autorität sind `petId`, `variant` und `shiny`.

### 2.2 Direkte Hatch-Chancen

Basiswahrscheinlichkeiten pro geöffnetem Ei:

| Ergebnis | Basiswahrscheinlichkeit |
|---|---:|
| Gold | 1 % |
| Rainbow | 0,1 % |
| Shiny | 0,01 % (1 zu 10.000) |

Gold und Rainbow werden mit einem gemeinsamen kategorischen Basisvarianten-Roll bestimmt, damit die Wahrscheinlichkeiten exakt und gegenseitig exklusiv bleiben. Shiny wird danach mit einem separaten, unabhängigen Roll bestimmt. Dadurch sind Gold Shiny und Rainbow Shiny möglich.

```text
base variant roll: Rainbow 0.1% → Gold 1% → otherwise Normal
independent modifier roll: Shiny 0.01%
```

Der Client erhält nur das Ergebnis. RNG, Chancen, Luck-Quellen und Pet-Auswahl bleiben vollständig serverautoritativ.

Shiny bleibt der seltenste Jackpot. Es gibt keine garantierte Shiny-Potion. Die geplante besondere Potion gewährt stattdessen **10x Shiny-Chance für die nächsten drei geöffneten Eier**. Weitere Upgrade-Kurven und Caps werden in QOF-02 balanciert.

### 2.3 Egg Quality und Multi-Open

- Egg Quality I/II werden mit Coins gekauft und verbessern die Species-/Rarity-Gewichte von Standard-Eiern.
- Egg Quality verändert nicht automatisch die Gold-/Rainbow-/Shiny-Basiswahrscheinlichkeiten.
- Multi-Open I/II/III werden mit Diamonds gekauft und erlauben 2/5/10 Eier pro Batch.
- Der Server leitet die erlaubte Batchgröße aus den gekauften Entitlements ab; ein vom Client gesendeter Count wird nie vertraut.
- Ein Batch ist atomar: volle Kosten und volle Inventarkapazität werden vorab geprüft; es gibt keinen Teil-Hatch.
- Auto-Hatch verwendet denselben serverseitigen Batch-Pfad.

Die bestehenden internen IDs `Eggs I` bis `Eggs V` bleiben zur Save-Kompatibilität stabil und werden später über Anzeigenamen/Wirkungen neu zugeordnet:

| Persistente ID | Neue UI-Bedeutung |
|---|---|
| `Eggs I` | Egg Quality I |
| `Eggs II` | Egg Quality II |
| `Eggs III` | Multi-Open I (2) |
| `Eggs IV` | Multi-Open II (5) |
| `Eggs V` | Multi-Open III (10) |

Die IDs werden nicht umbenannt. Die spätere Datenänderung muss Requirements und Währungen aktualisieren; `UpgradeTreeService` muss dann neben Coins auch Diamonds kanonisch validieren.

### 2.4 Seltene Hatch-Animation

Die Animation ist rein clientseitig und verändert kein Ergebnis:

- 1–10 Eier in responsiver Reihe, Kreis- oder Grid-Anordnung
- Pop-Kettenreaktion mit 0,1–0,2 Sekunden Versatz
- Ergebnis-Grid mit allen Pets nach Abschluss
- Gold: goldener Glow/Partikel
- Rainbow: animierter Farbverlauf/Farbring
- Shiny: glitzerndes Ei, weiße/cyanfarbene Sterne und wandernder Lichtstreifen
- bei einem seltenen Ergebnis pausieren/dimmen die übrigen Eier kurz
- kurzer Kamera-Zoom und leichte Zeitlupe für das seltene Reveal
- Shiny-Rainbow kombiniert Rainbow-Farben mit Shiny-Sternen
- permanenter sichtbarer Shiny-Effekt am Pet

Mehrere Auto-Hatches werden clientseitig gequeued; eine laufende Animation darf kommende Ergebnisse nicht verwerfen.

## 3. Maschinenvertrag

### 3.1 Weltplatzierung

Maschinen werden ausschließlich zur Laufzeit aus einer gemeinsamen Shared-Konfiguration erzeugt, damit Rojo, Generator und Place-Datei nicht auseinanderlaufen.

| Maschine | Zone | Zonenname | Umwandlung |
|---|---:|---|---|
| Gold Machine | 3 | Beach/Strand | Normal → Golden |
| Rainbow Machine | 6 | Volcano/Vulkan | Golden → Rainbow |

Jede Maschine besitzt ein sichtbares Modell, Attribute (`MachineId`, `MachineType`, `ZoneId`) und einen `ProximityPrompt`. Der Server prüft zusätzlich zur Remote-Anfrage die freigeschaltete Zone und die Entfernung des Spielers zur Maschine.

### 3.2 Gemeinsame Auswahlregeln

- 1–7 Pets pro Versuch
- alle Pets müssen dieselbe `petId`/Species besitzen
- Gold Machine akzeptiert nur Basisvariante `Normal`
- Rainbow Machine akzeptiert nur Basisvariante `Golden`
- favorisierte Pets sind gesperrt
- ausgerüstete Pets sind gesperrt und müssen zuerst abgelegt werden
- jede Pet-Instanz-ID darf nur einmal vorkommen
- Inputs werden bei Erfolg und Fehlschlag verbraucht
- bei Erfolg entsteht genau ein neues Pet derselben Species in der Zielvariante
- enthält die Auswahl mindestens ein Shiny-Pet, bleibt das Ergebnis bei Erfolg Shiny
- mehrere eingesetzte Shinys erzeugen keinen zusätzlichen Stack; die UI warnt vor unnötigem Verbrauch
- bei Fehlschlag wird kein Pet erzeugt
- Fusion Potions existieren nicht

### 3.3 Chancen und Preise

Für beide Maschinen gilt dieselbe Chance:

| Eingesetzte Pets | Erfolgschance |
|---:|---:|
| 1 | 13 % |
| 2 | 26 % |
| 3 | 39 % |
| 4 | 50 % |
| 5 | 63 % |
| 6 | 88 % |
| 7 | 100 % |

Feste Kosten pro Versuch, unabhängig von der Pet-Anzahl:

- Gold Machine: **750 Diamonds**
- Rainbow Machine: **2.500 Diamonds**

Vor der Bestätigung zeigt die UI Zielpet, ausgewählte Pets, Diamond-Preis, Chance und den Hinweis, dass Pets und Diamonds auch bei Fehlschlag verloren gehen.

### 3.4 Atomare Servertransaktion

Der spätere `MachineService` erhält ausschließlich `machineId` und Pet-Instanz-IDs. Unter einem Player-Lock werden vor jeder Mutation geprüft:

1. gültiger Spieler und geladenes Profil
2. Rate-Limit und keine laufende Maschinenanfrage
3. bekannte Maschine und Spieler in Reichweite
4. Zone freigeschaltet
5. 1–7 eindeutige IDs
6. Eigentum, gleiche Species und korrekte Ausgangsvariante
7. weder Favorite noch Equipped
8. ausreichende Diamonds
9. ausreichende Ergebnis-Inventarkapazität

Danach werden Preis und Inputs ohne Yield in einem Commit mutiert, der serverseitige Roll ausgeführt und bei Erfolg das Ergebnis angelegt. Inventar, Currency, Discovery und Maschinenresultat werden anschließend jeweils einmal repliziert. Unerwartete Fehler dürfen keinen Teilzustand hinterlassen.

## 4. Potions- und Buff-Vertrag

### 4.1 Verbrauchsgegenstände

| Potion | Effekt | Dauer/Verbrauch |
|---|---|---|
| Luck Potion | x2 Luck | 10 Minuten |
| Mega Luck Potion | x5 Luck | 5 Minuten |
| Speed Potion | x2 Walk Speed | 5 Minuten |
| Coin Potion | x2 Breakable Coin Rewards | 10 Minuten |
| Shiny Potion | x10 Shiny-Chance | nächste 3 Eier |

Die frühere Idee „garantiert Shiny für drei Eier“ ist verworfen, damit Shiny extrem selten bleibt.

### 4.2 Inventar, Slots und Timer

- Kaufen und Trinken werden getrennte Serveroperationen.
- Potion-Inventar wird als persistente Count-Map gespeichert.
- aktive zeitbasierte Buffs speichern absolute `os.time()`-Endzeiten.
- Offline-Zeit zählt zur Laufzeit; abgelaufene Buffs werden beim Laden entfernt.
- gleichartige Potions verlängern den vorhandenen Buff und belegen nur einen Slot.
- unterschiedliche aktive Bufftypen belegen jeweils einen Potion Slot.
- Potion Slots, Potion Duration+ und Auto-Drink sind persistente Upgrades.
- Duration+ wird beim Trinken serverseitig in die Endzeit eingerechnet.
- Auto-Drink konsumiert nur bei online befindlichen Spielern; es verbraucht offline keine Items.
- jeder Consume-/Auto-Drink-Schritt wird serverseitig atomar ausgeführt und repliziert.

Die bestehenden `shopPurchases.extraEquipSlots` bleiben strikt von neuen Potion-Slots getrennt.

## 5. Persistenzvertrag

Die nächste Implementierungsphase muss von Schema V5 ausgehen und mindestens auf V6 migrieren. `upgradeTreePurchases` darf nicht verloren gehen.

Vorgesehene neue bzw. normalisierte Felder:

```text
pets[*].variant = "Normal" | "Golden" | "Rainbow"
pets[*].shiny = boolean
potionInventory[potionId] = non-negative integer
activeBuffs[buffType] = absolute unix expiry or structured charge state
potionUpgrades.slots = bounded integer
potionUpgrades.durationLevel = bounded integer
potionUpgrades.autoDrink = boolean/config
upgradeTreePurchases[id] = true
```

Legacy-Pet-Migration:

| Alter Zustand | Neuer Zustand |
|---|---|
| `golden=true` oder `variant="Golden"` | `variant="Golden", shiny=false` |
| `variant="Rainbow"` | `variant="Rainbow", shiny=false` |
| `variant="Shiny"` | `variant="Normal", shiny=true` |
| Normal/fehlend | `variant="Normal", shiny=false` |

Bestehende IDs, Favorite, Equipped und `equippedPets` bleiben erhalten. Unbekannte oder ungültige Variant-/Potion-Werte werden auf Whitelist-Werte normalisiert.

Pet-Dex-Schlüssel müssen künftig Basisvariante und Shiny kombinieren können, beispielsweise:

```text
petId|Normal
petId|Normal|Shiny
petId|Golden
petId|Golden|Shiny
petId|Rainbow
petId|Rainbow|Shiny
```

Alte Discovery-Schlüssel werden bei der Migration übernommen. Maschinen und Hatches schreiben in denselben Dex; es gibt keine separate Maschinen-Collection.

## 6. Server-/Client-Aufteilung

### Shared/Config

Zentrale, serverlesbare Definitionen für:

- Varianten und Multiplikatoren
- Basis-Hatch-Chancen
- Multi-Open-Stufen
- Maschinenzonen, Preise und Chancen
- Potion-Katalog, Dauer, Multiplikatoren und Charges
- Upgrade-Kosten und Caps

QOF-02 legt die noch offenen Preise und Kurven fest.

### Server

Vorgesehene Verantwortlichkeiten:

- `PetService`: Pet-Resultat erzeugen, kanonischer Schaden, Inventory-/Favorite-/Equip-Invarianten
- `EggService`: atomare Single-/Batch-Hatch-Transaktion
- `MachineService`: Gold-/Rainbow-Auswahl, Zahlung, Verbrauch und Roll
- `PotionService` oder erweiterter `ShopService`: Inventar, Consume, Timer, Slots, Auto-Drink
- `UpgradeTreeService`: kanonische Currency-/Entitlement-Prüfung und Effektabfrage
- `DataSchema`/`DataService`: Migration, Normalisierung und DTOs
- `ZoneService`: ausschließlich Runtime-Modelle/Prompts aus Shared StationData erzeugen

### Client

- `Main.client.lua`: Remote-Wiring und zentraler Prompt-Router
- `UIController`: Screens, Potion-Inventar, Maschinen-Auswahl, Dex und Ergebnisanzeigen
- `EffectsController`: Batch-Hatch-Queue und Rare-Reveal
- `UpgradeTreeController`: unveränderter Renderer plus serverbasierter State-Adapter

Der Client darf Preise, Chancen, erlaubte Batchgröße, Zone, Pet-Eigentum oder Ergebnisse niemals autoritativ entscheiden.

## 7. Bestehende Lücken und geplante Auflösung

| Aktueller Befund | Ziel/QOF |
|---|---|
| Hatch verarbeitet nur ein Ei | atomarer Batch-Pfad in QOF-08 |
| `HatchPrompt` löst keinen Kauf aus | Prompt-Router in QOF-08/09 |
| Shiny ist exklusive Variante | Migration und Modifier in QOF-03/04 |
| Damage ist im Pet fest eingebrannt | zentrale Berechnung in QOF-04 |
| Tree-Käufe haben keine Gameplay-Wirkung | Entitlement-Resolver in QOF-07 |
| Tree-Service akzeptiert nur Coins | kanonischer Coin-/Diamond-Kauf in QOF-07 |
| Potion-Kauf aktiviert sofort | getrenntes Kaufen/Trinken in QOF-13/14 |
| Buff-Timer sind nur sitzungsintern | persistente `os.time()`-Timer in QOF-03/14 |
| Gold-Konvertierung ist UI-Funktion ohne Weltmaschine | MachineService/World Station in QOF-15/16 |
| Rainbow-Konvertierung fehlt | QOF-17 |
| Pet Dex kennt keine Kombinationen | QOF-20 |
| Generator hat harte Service-/Controllerlisten | bei jeder neuen Datei ergänzen; final in QOF-21 prüfen |
| Binäre RBXL ist kein reproduzierbares Generatorziel | reproduzierbarer Release-Schritt in QOF-21 |

## 8. Build- und Release-Regeln

- Source of truth bleibt `src/` plus Shared-Konfiguration.
- Maschinen werden nicht zusätzlich statisch in `build_workspace()` dupliziert.
- Neue Services/Controller werden sowohl in Rojo als auch in `tools/generate_rbxlx.py` eingebunden.
- `BATTLE_PETS.rbxlx` wird nach relevanten Source-Änderungen neu generiert und auf eingebettete Source-Parität geprüft.
- Die finale binäre `.rbxl` wird erst in QOF-21 aus dem geprüften `.rbxlx` erzeugt.
- Temporäre Konvertierungswerkzeuge werden nicht committed.

## 9. Sicherheitsinvarianten

1. Alle Currency-Abzüge erfolgen serverseitig über eine transaktionsgeeignete Currency-API.
2. Refunds dürfen keine Coin-Gain-Boni anwenden.
3. Batch-Hatch und Maschinenversuche sind all-or-nothing.
4. Remote-Parameter werden typ-, längen-, mengen- und bereichsgeprüft.
5. Pet-IDs werden dedupliziert und gegen das geladene Profil geprüft.
6. Favorites und Equipped Pets sind bei Maschinen geschützt.
7. Der Server bestimmt Upgrade-Entitlements, Chancen, Preise und Resultate.
8. Jeder teure Remote-Pfad hat Cooldown/Burst-Limit und einen Player-Lock.
9. Clientanimationen können Serverresultate weder verändern noch wiederholen.
10. Persistenz erhält Session-Lock- und Save-Ownership-Schutz des bestehenden `DataService`.

## 10. Bewusst an QOF-02 delegiert

Folgende Werte wurden noch nicht vom Nutzer festgelegt und werden zentral in QOF-02 balanciert:

- Preise von Egg Quality I/II
- Preise von Multi-Open I/II/III
- Preise/Kurven für Gold-, Rainbow- und Shiny-Chance-Upgrades
- Preise/Kurven für Speed, Storage, Magnet und Pet Equip Slots
- Potion-Kaufpreise, Potion-Slot-Kosten, Duration+-Kurve und Auto-Drink-Preis
- Enchanting-Preise und mögliche Enchant-Pools
- Luck-Stacking-Caps und maximale effektive Shiny-Chance
- Inventar-/Storage-Stufen

Bis QOF-02 gilt: keine garantierten Shinys und keine Änderung an den festgelegten Basiswahrscheinlichkeiten.

## 11. QOF-01-Abnahmekriterien

- [x] Bestehende Hatch-, Pet-, Shop-, Upgrade-, Daten-, UI-, Zonen- und Buildpfade untersucht
- [x] Mythic, Pet-Leveling, Cosmetics, Prestige und Fusion Potions ausgeschlossen
- [x] Basisvarianten und unabhängiges Shiny-Modell festgelegt
- [x] direkte Hatch-Chancen und Multiplikatoren festgelegt
- [x] Maschinenzonen, Preise, Chancen und Schutzregeln festgelegt
- [x] Potion-Inventar-/Timer-/Auto-Drink-Semantik festgelegt
- [x] atomare Servergrenzen und Anti-Exploit-Invarianten festgelegt
- [x] Migrationsrichtung von Schema V5 festgelegt
- [x] stabile Upgrade-Tree-ID-Strategie festgelegt
- [x] Build-/RBXL-Strategie festgelegt
- [x] alle noch offenen Balancewerte eindeutig QOF-02 zugeordnet

**QOF-01 ist abgeschlossen, sobald dieses Dokument geprüft wurde. Danach beginnt QOF-02 ausschließlich nach Nutzerfreigabe mit „Weiter“.**


## 12. Kollaborativer Test- und Debugging-Ablauf

Ab QOF-02 wird jedes implementierte Arbeitspaket als eigene echte binäre Test-RBXL bereitgestellt. Der Nutzer testet diese Datei in Roblox Studio anhand eines gelieferten Testplans und meldet Bugs sowie Bedien-/Performance-Beobachtungen zurück. Das nächste QOF beginnt erst nach ausdrücklichem `Weiter`.

Für jede Runde gelten drei getrennte Zustände:

1. **Code-verifiziert:** statische Prüfungen, Generator, Hierarchie und semantischer Review bestanden.
2. **Studio-Test ausstehend:** versionierte `BATTLE_PETS_QOF-XX_TEST.rbxl` wurde mit direktem Download-Link bereitgestellt.
3. **Studio-bestätigt:** der Nutzer hat die vereinbarten Testfälle ausgeführt und keine Blocker gemeldet.

Bugs bleiben im aktuellen QOF, werden ursächlich behoben und als `v2`, `v3` usw. erneut bereitgestellt. Der vollständige verbindliche Ablauf steht in `.kiro/steering/qof-test-debug-workflow.md`.
