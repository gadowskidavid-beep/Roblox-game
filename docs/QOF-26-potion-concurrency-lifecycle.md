# QOF-26 – Potion-Concurrency und Lifecycle

Status: **Code-verifiziert – Studio-Test ausstehend**

Implementierungscommit: `5df4944`

QOF-26 ersetzt unabhängige Potion-Locks durch einen gemeinsamen, opaken per-player Lease. Hatch-Shiny-Reservationen, manuelles Trinken, der vollständige Auto-Drink-Pass, Selection, Potion-Upgrades, Reconciliation und Potion-Shopkäufe können dadurch keinen Zwischenzustand mehr gegenseitig überschreiben. Direkte Potion-Mutationen besitzen zusätzlich den zentralen QOF-25-Profil-Owner und sind damit gegen Autosave, Leave und Shutdown serialisiert.

## Kanonischer Vertrag

- Pro UserId existiert höchstens ein aktueller Potion-Lease. Freigabe verlangt exakt denselben Player, dieselbe Profilidentität und dasselbe opake Handle; falsche, veraltete und doppelte Freigaben scheitern.
- Direkte Potion-Pfade erwerben zuerst den lokalen Lease und anschließend einen save-aware `ProfileTransactionService`-Owner, bevor sie das Profil mutieren. Scheitert die zentrale Admission wegen Save oder Leave, wird der lokale Lease ohne Mutation freigegeben.
- Egg und Shop verwenden einen verschachtelten Potion-Lease ohne zweiten zentralen Owner: Paid Egg und Shop besitzen das Profil bereits über ihre Currency-Transaktion. Alle Akquisitionspfade warten nicht, sondern liefern deterministisch `BUSY`.
- Eine Shiny-Hatch-Reservation subtrahiert höchstens die Batchgröße und hält den Lease bis Egg-Commit oder Egg-Rollback. Nur `EggService` entscheidet den Ausgang dieses Handles.
- Shiny-Rollback schreibt keinen alten Tabellen-Snapshot zurück. Er validiert Profil, Buff-Tabelle und Lease und addiert ausschließlich `reserved` zum aktuellen Charge-Wert.
- Würde eine Restoration 30 Charges überschreiten oder stimmt eine Identität nicht, bleibt Handle plus Lease retrybar erhalten. Es wird weder geklemmt noch verworfen.
- Reservation-Begin und erfolgreicher Rollback erzeugen keine Potion-Revision und kein Event. Erfolgreicher Commit erzeugt genau eine Revision und ein geschütztes `PotionStateUpdated`.
- Eine Shiny Potion wird nur konsumiert, wenn alle drei Charges Platz haben. `27 → 30` ist gültig; bei `28`, `29` oder `30` bleiben Potion und Charges unverändert. Ein Clamp darf keine bezahlten Charges vernichten.
- `getState` ist eine reine Projektion: keine Default-Initialisierung, Expiry-Bereinigung, Revision, Bewegungserneuerung oder Eventemission.
- Expiry-Reconciliation und der gesamte deterministische Auto-Drink-Katalogpass laufen unter demselben Lease und zentralem Profil-Owner. Offline-Zeit bleibt absolut; es wird keine Offline-Auto-Drink-Schleife nachgeholt.
- Shop- und Potion-Transaktionen behalten starke aktive Records, Locks, Currency-Owner und gegebenenfalls Potion-Lease, bis Commit oder exakter retrybarer Rollback abgeschlossen ist.
- Shutdown schließt neue Shop-/Potion-Admission und stoppt den Potion-Scheduler. Bereits existierende Handles und Finalizer bleiben settlebar.
- Leave und Shutdown setteln Egg vor Potion. Wenn Egg noch ausführt oder einen post-PONR Shiny-Commit retryt, darf Potion weder den Handle zurückrollen noch den Lease freigeben.
- `DataService` speichert und releast erst, wenn Egg, Shop, Potion, der zentrale Profil-Owner sowie Pet- und Potion-Leases vollständig idle sind.

## Abgedeckte Races und Regressionen

- Reale `EggService`-/`PotionService`-/`ShopService`-Integration bei 5, 29 und 30 Shiny-Charges.
- Am deterministischen Egg-Hook `afterPrepare`: exakt 3 Charges reserviert; Egg läuft noch; Consume, Auto-Drink, Upgrade, Selection, Shopkauf und Reconciliation liefern `BUSY` ohne Currency-, Inventar-, Charge-, Revision- oder Eventmutation.
- Technischer Pre-PONR-Hatchfehler restauriert exakt 5/29/30 Charges und dieselbe Shiny-Potion-Anzahl.
- Erfolgreicher Hatch-Commit verbraucht exakt die Reservation und publiziert eine Revision/ein Event.
- Post-PONR Shiny-Finalisierungsfehler behält Egg-Transaktion, Pet-Lease, Potion-Handle und Potion-Lease; Potion-Cleanup darf nicht rollbacken; späterer Retry committet genau einmal.
- Fehlgeschlagene additive Restoration behält Handle/Lease und blockiert alle konkurrierenden Potion-Pfade bis zum erfolgreichen Retry.
- Save- und Leave-Admission blockieren Consume, Auto-Drink, Selection und Reconciliation vor jeder Mutation.
- Falsche, stale und doppelte Lease-Handles können einen aktuellen Owner nicht freigeben.
- `getState` bleibt auch während eines gehaltenen Leases rein.
- Shop-Potion und ExtraEquipSlot behalten fehlgeschlagene Rollbacks lifecycle-retrybar; Shutdown blockiert neue Käufe.
- Luck, Mega Luck, Speed, Coin Boost, Duration, Slots und Auto-Drink bleiben durch bestehende Regressionen abgedeckt.

## Lokale Verifikation

- Gepinnte Pflicht-Toolchain erfolgreich geprüft (`rbxmk 0.9.1`, Luau/Compiler `0.735`).
- Python-Compile für Tools und Tests erfolgreich.
- Vollständige Luau-Suite: **409/409** in kanonischer und umgekehrter Reihenfolge.
- Luau-Compile: **79/79** Runtime-Sources.
- `verify_generated_place.py`: 79 Sources bytegenau, davon 77 ModuleScripts, 1 Script und 1 LocalScript.
- Finaler semantischer Review: **APPROVED**, keine offenen QOF-26-Findings.
- Unabhängiger Fresh-Build, RBXL-Signatur, kanonisches ZIP und SHA-Manifest erfolgreich.
- `git diff --check` erfolgreich.

## Testartefakt

| Artefakt | Bytes | SHA-256 |
|---|---:|---|
| `BATTLE_PETS.rbxlx` | 1.161.446 | `a2b31d4d6c23ad576a4b3653366cef3b2901e77811bdab838d3f64184704c546` |
| `BATTLE_PETS_QOF-26_TEST.rbxl` | 409.870 | `2df33d0b3bd136e4030c2583fabdd4b8f731b3224e47abf103e47dd8f7770db1` |
| `BATTLE_PETS_QOF-26_RBXLX.zip` | 233.161 | `5365ebed16fe08587203af698a4b014befc7beb4505d3b215dfbbc8a959e834a` |
| `BATTLE_PETS_QOF-26_SHA256SUMS.txt` | 1.080 | `78f94977ea444650141295a70dfbcdbb62c9104d2a6ca25957f42f475080747e` |

Die RBXL beginnt mit der exakten binären Roblox-Signatur `<roblox!\x89\xff\r\n\x1a\n`.

## Verbindlicher Studio-Testplan

1. `BATTLE_PETS_QOF-26_TEST.rbxl` in Roblox Studio öffnen und **Play** starten. Erwartet: Welt, Shop, Potion-UI und Egg-Stationen laden ohne rote Server-/Clientfehler; bestehende Pets, Währungen, Zonen und Potion-Zustände erscheinen unverändert.
2. In der **Server**-Command-Bar die Pflicht-Races ausführen:
   ```lua
   local p = game:GetService("Players"):GetPlayers()[1]
   local S = game.ServerScriptService.Services
   local Data = require(S.DataService)
   local Potion = require(S.PotionService)
   local Shop = require(S.ShopService)
   local d = Data.getPlayerData(p)
   d.potionUpgrades.autoDrink = true
   d.autoDrinkSelection.ShinyPotion = true

   local function race(initial)
       d.potionInventory.ShinyPotion = 2
       d.activeBuffs.shinyChance = { charges = initial }
       local beforeRevision = Potion.getState(p).stateRevision
       local h, reserved, beginError = Potion.beginShinyChargeTransaction(p, 3)
       print("QOF26_RESERVED", initial, reserved, beginError,
           d.activeBuffs.shinyChance and d.activeBuffs.shinyChance.charges or 0)
       print("QOF26_MANUAL_BUSY", Potion.consume(p, {
           contractVersion = 1, action = "consumePotion", potionId = "ShinyPotion"
       }))
       print("QOF26_AUTODRINK_BUSY", Potion.processAutoDrink(p))
       print("QOF26_UPGRADE_BUSY", Potion.purchaseUpgrade(p, {
           contractVersion = 1, action = "purchasePotionUpgrade", upgradeId = "Duration"
       }))
       print("QOF26_SELECTION_BUSY", Potion.setAutoDrinkSelection(p, {
           contractVersion = 1, action = "setAutoDrinkSelection",
           potionId = "ShinyPotion", selected = true
       }))
       print("QOF26_SHOP_BUSY", Shop.purchaseItem(p, {
           contractVersion = 2, action = "purchasePotion",
           itemId = "ShinyPotion", quantity = 1
       }))
       print("QOF26_UNCHANGED_WHILE_HELD",
           d.potionInventory.ShinyPotion,
           d.activeBuffs.shinyChance and d.activeBuffs.shinyChance.charges or 0,
           Potion.getState(p).stateRevision == beforeRevision)
       print("QOF26_ROLLBACK", Potion.rollbackShinyChargeTransaction(h),
           d.activeBuffs.shinyChance and d.activeBuffs.shinyChance.charges or 0,
           d.potionInventory.ShinyPotion)
   end

   race(5)
   race(29)
   race(30)
   ```
   Erwartet je Durchlauf: `reserved = 3`; verbleibend zunächst 2/26/27; Manual, AutoDrink, Upgrade, Selection und Shop liefern `false, BUSY`; Inventar bleibt 2 und Revision unverändert; Rollback liefert `true` und exakt 5/29/30 bei weiterhin 2 Potions.
3. Vollständige Shiny-Potion-Fit-Regel prüfen:
   ```lua
   local p = game:GetService("Players"):GetPlayers()[1]
   local S = game.ServerScriptService.Services
   local Data = require(S.DataService)
   local Potion = require(S.PotionService)
   local d = Data.getPlayerData(p)
   d.potionInventory.ShinyPotion = 2
   d.activeBuffs.shinyChance = { charges = 29 }
   print("QOF26_NO_CLAMP_29", Potion.consume(p, {
       contractVersion = 1, action = "consumePotion", potionId = "ShinyPotion"
   }), d.potionInventory.ShinyPotion, d.activeBuffs.shinyChance.charges)
   d.activeBuffs.shinyChance = { charges = 27 }
   print("QOF26_FULL_FIT_27", Potion.consume(p, {
       contractVersion = 1, action = "consumePotion", potionId = "ShinyPotion"
   }), d.potionInventory.ShinyPotion, d.activeBuffs.shinyChance.charges)
   ```
   Erwartet: bei 29 `false`, Inventar 2, Charges 29; bei 27 `true`, Inventar 1, Charges exakt 30.
4. Im normalen UI nacheinander Luck, Mega Luck, Speed und Coin Potion konsumieren. Erwartet: jeweiliges Inventar sinkt exakt einmal; Luck/Mega Luck teilen einen Buff-Typ mit dem höchsten aktiven Multiplikator; Speed aktualisiert Bewegung; Coin Boost wirkt; keine rote Fehlermeldung.
5. Potion-Slots, Duration und Auto-Drink regulär kaufen beziehungsweise verwenden. Erwartet: korrekte serverseitige Diamond-Kosten, genau eine finale Revision, kein Debit-/Refund-Flackern und keine doppelte Mutation bei schnellem Doppelklick.
6. Auto-Drink für mindestens eine Timed Potion auswählen, Effekt ablaufen lassen und online bleiben. Erwartet: genau eine ausgewählte Potion wird beim nächsten regulären Tick konsumiert. Studio schließen/neu öffnen beziehungsweise rejoinen: keine simulierte Offline-Schleife verbraucht mehrere Potions.
7. Einen manuellen Paid Hatch mit mindestens 3 Shiny-Charges ausführen. Erwartet: erfolgreicher Hatch verbraucht höchstens die Batchgröße exakt; bei einer normalen serverseitigen Ablehnung bleiben Charges und Potion-Inventar unverändert; Ergebnisanimation und Pet-Inventar funktionieren weiterhin.
8. Während eines Hatches und während eines Potion-Upgrades schnell Consume, Auto-Drink-Selection und Shop-Potion auslösen. Erwartet: konkurrierende Aktionen werden sauber mit `BUSY` abgewiesen; keine doppelte Abbuchung, keine negative Potion-Anzahl und keine verlorenen Charges.
9. Einen normalen Potion-Shopkauf und einen ExtraEquipSlot-Kauf durchführen. Erwartet: exakt eine Abbuchung/ein Item beziehungsweise Slot; Shop- und Potion-State aktualisieren sich einmal; kein zweiter Kauf durch Doppelklick.
10. Spiel verlassen und erneut beitreten. Erwartet: nur vollständig abgeschlossene Potion-/Shop-/Hatch-Zustände sind gespeichert; keine reservierten Charges, kein halber Kauf und kein verlorener erfolgreicher Consume.
11. Optional einen Server mit zwei Spielern schließen. Erwartet: beide Profile setteln unabhängig; ein unresolved Owner verhindert nur den eigenen Save und wird retrybar gehalten.
12. Desktop- und Mobile-Smoke für Potion-UI, Shop, Hatch, Bewegung und Auto-Drink durchführen. Erwartet: keine neue UI-/Remote-Störung.

## Bekannte Grenzen

Der echte Roblox-Studio-Playtest, DataStore-Rejoin, Netzwerk-/Physikpfad und ein harter Prozessabbruch können im Linux-Sandbox-Build nicht ausgeführt werden. Das Studio-Gate ist deshalb ausdrücklich offen. QOF-26 ändert bewusst weder die Maschinenreihenfolge `Inputs entfernen → RNG` (QOF-27) noch Auto-Hatch Contract V2, HUD-Flow oder x1/x3/x9 (QOF-28). Es führt kein Event-Sourcing-Ledger ein; stattdessen werden die betroffenen Profilmutationen exklusiv und save-aware serialisiert.

## Offenes Feedback

Bitte nach dem Studio-Test melden:

1. Sind bei den 5/29/30-Races alle konkurrierenden Rückgaben `BUSY` und die Endwerte exakt?
2. Bleiben Potion-Inventar, Shiny-Charges und Diamond-Kosten bei schnellen Parallelaktionen exakt konserviert?
3. Funktionieren Luck, Mega Luck, Speed, Coin Boost, Duration, Slots und Auto-Drink unverändert?
4. Bleibt nach Leave/Rejoin ausschließlich der vollständig abgeschlossene Zustand erhalten?
5. Gibt es rote Server-/Clientfehler oder auffällige UI-/Bewegungsregressionen?

QOF-27 wird erst durch ein erneutes ausdrückliches `Weiter` nach diesem Handoff freigegeben.
