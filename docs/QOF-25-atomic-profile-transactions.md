# QOF-25 – Zentrale atomare Profil-/Currency-Transaktionen

Status: **Code-verifiziert – Studio-Test ausstehend**

Implementierungscommit: `b25979fb0ce38250a9c6079a535a35e1dfe6d093`

QOF-25 führt einen serverweiten, exklusiven Transaktions-Owner pro geladenem Profil ein. Composite Purchases reservieren Currency ohne Live-Debit, halten den Owner bis Commit oder exaktem Rollback und blockieren jeden Persistenz-Snapshot, solange ein Zustand nicht abschließend aufgelöst ist.

## Kanonischer Vertrag

- `ProfileTransactionService` besitzt pro UserId höchstens einen opaken Owner und stellt `begin`, `closeAdmission`, `hasPending`, `settlePlayer`, `commit` sowie retrybares `rollback` bereit.
- Der Owner wird vor der ersten Liveprofilmutation registriert. Roblox-`Player`-Instances und numerische UserIds werden defensiv unterstützt.
- `DataService.savePlayerData` setzt zuerst die Save-Admission und prüft danach den zentralen Owner. Bei einem pending Owner endet der Pfad mit `Profile transaction pending`, bevor `DataSchema.cloneForPersistence` aufgerufen wird.
- Autosave überspringt pending Profile. Leave und Shutdown schließen neue Admission, versuchen Service- und zentralen Settlement und speichern/releasen nur einen vollständig aufgelösten Zustand.
- `CurrencyService.beginSpendTransaction` prüft die serverseitige Currency und reserviert den Betrag, verändert den Live-Balancewert jedoch nicht und sendet kein `CurrencyUpdated`.
- Jede Reservation erhält sofort einen zentralen Default-Settler. Ein Composite Service ersetzt ihn vor seiner Domainmutation durch eine Domain-first-Kompensation.
- `commitSpendTransaction` ist der einzige Currency-PONR: genau ein Debit, danach Owner-Freigabe und eine geschützte Currency-Replikation.
- `rollbackSpendTransaction` storniert die Reservation ohne Refund-Credit, Bonuspfad oder Clientevent.
- Additive, bereits aufgelöste Rewards dürfen während einer Reservation den aktuellen Balancewert erhöhen; der Save bleibt blockiert und der spätere Commit zieht den reservierten festen Betrag vom dann aktuellen autoritativen Wert ab. Sie können deshalb kein Lost Update oder Refund-Flicker erzeugen.
- Fehlerhafte Rollbacks bleiben über starke Service- und zentrale Handles erhalten. Lifecycle-Retry wiederholt dieselbe idempotente Kompensation; ein unresolved Owner verhindert weiterhin sichere Snapshots.
- Fehler nach dem PONR, etwa `CurrencyUpdated`, Inventar-, Potion-, Upgrade- oder Quest-Benachrichtigungen, machen eine abgeschlossene Wirtschaftsmutation nicht erneut retrybar.

## Migrierte Composite-Pfade

- Upgrade Tree: stiller Spend, exakte Purchase-Tabellenkompensation, vollständige State-Projektion vor Commit.
- Egg/Hatch: paid Owner vor Shiny-Charge-Mutation; Pet-, Campaign-Claim-, Charge- und Currency-Rollback in Domain-first-Reihenfolge. Auch explizit kostenlose Hatches besitzen einen direkten zentralen Profil-Owner; Campaign-SpecialEgg schreibt Pet, Dex und einmaligen Claim-Marker unter demselben Owner.
- Shop-Potions: exakte Inventar-Key-Kompensation und postcommit geschützte Replikation.
- Potion-Upgrades: exakte Feld-/Revision-Restoration, getrennt gelatchter Domain-Rollback und retrybare Currency-Stornierung.
- Auto-Hatch-Zugang: Expiry/Revision/DTO vor Commit, exakte technische Kompensation und terminale postcommit Notification.
- Gold-/Rainbow-Maschinen: zentraler Owner und stiller Spend um den bestehenden QOF-17-Transaktionskern.
- Enchanting: zentraler Owner, vollständiger projizierter Contract-V1-DTO vor Currency-PONR, Pet-Restoration vor Currency-Stornierung und post-PONR geschützte Inventarreplikation.

## Abgedeckte Regressionen

- Owner-Kollision zweier unterschiedlicher Services auf demselben Profil; unabhängige Profile bleiben parallel nutzbar.
- Save-Race: kein Snapshot nach Reservation, nach Domainmutation oder vor Commit; `cloneForPersistence` bleibt bis Settlement unaufgerufen.
- Keine Balanceänderung und kein Currency-Event bei Reservation oder Rollback; genau ein Debit/Event beim Commit.
- Technische Fehler nach Spend, Mutation und DTO-Bau restaurieren den exakten vorherigen Zustand.
- Rollback-`false` und Rollback-Exception behalten Owner, Lease und Handle für Cleanup-/Shutdown-Retry.
- Profil-, Tabellen- und Objektidentitätswechsel werden nicht durch einen alten Rollback überschrieben.
- Currency-Commit-Fehler restauriert Domainzustand und storniert dieselbe Reservation.
- Notification-Fehler nach Commit bleiben erfolgreicher, bezahlter Abschluss.
- Egg registriert den Owner vor einer Shiny-Charge-Reservation; Free Hatch blockiert Autosave ebenfalls.
- Campaign-SpecialEgg erstellt Pet/Dex und den exakten `campaignBossRewards`-Marker atomar; technische Fehler restaurieren auch hostile Altwerte, und ein fehlgeschlagener Pet-Rollback behält Owner plus Inventory-Lease.
- Enchanting baut und hält den vollständigen post-debit Contract-V1-DTO vor Commit; postcommit Profil-/Notificationfehler können deshalb keinen bezahlten Nil-State erzeugen.
- Reale Integration aus `DataService`, `ProfileTransactionService` und `CurrencyService`: Shop-Owner blockiert einen UpgradeTree-Versuch und den Save-Snapshot bis zur stillen Stornierung.
- Leave-/Shutdown-Settlement sowie normales und umgekehrtes Spec-Order werden getrennt geprüft.

## Lokale Verifikation

- Gepinnte Pflicht-Toolchain erfolgreich geprüft (`rbxmk 0.9.1`, Luau/Compiler `0.735`).
- Python-Compile für Tools und Tests erfolgreich.
- Luau-Compile: **79/79** Runtime-Sources.
- Vollständige Luau-Suite: **399/399** in kanonischer und umgekehrter Reihenfolge.
- `verify_generated_place.py`: 79 Sources bytegenau, davon 77 ModuleScripts, 1 Script und 1 LocalScript.
- Unabhängiger QOF-25-Releaseverifier, Fresh-Build-Vergleich, RBXL-Signatur, kanonisches ZIP und SHA-Manifest erfolgreich.
- `git diff --check` erfolgreich.

## Testartefakt

| Artefakt | Bytes | SHA-256 |
|---|---:|---|
| `BATTLE_PETS.rbxlx` | 1.147.921 | `340ecb65f5eeb32ddaeeb5d3e3e6fceabe7a99ead445639e9c525768c8231571` |
| `BATTLE_PETS_QOF-25_TEST.rbxl` | 405.293 | `2df665a6baa4b0b335abad48f3c1dbe7d58884e07eeb57c462e0083617143286` |
| `BATTLE_PETS_QOF-25_RBXLX.zip` | 230.517 | `594c4d78d233857349dfff43661010fcc31a34066584ffd1cc1354fb445d3192` |
| `BATTLE_PETS_QOF-25_SHA256SUMS.txt` | 1.080 | `c523966008de7a15fa60f88b3622b9bc0615a65acd0c5a38ce5a86a8444146dc` |

Die RBXL beginnt mit der exakten binären Roblox-Signatur `<roblox!\x89\xff\r\n\x1a\n`.

## Verbindlicher Studio-Testplan

1. `BATTLE_PETS_QOF-25_TEST.rbxl` in Roblox Studio öffnen und **Play** starten. Erwartet: Welt und UI laden ohne rote Fehler; Profil, Pets, Währungen und Zonen erscheinen unverändert.
2. In der **Server**-Command-Bar die stille Reservation prüfen:
   ```lua
   local p = game:GetService("Players"):GetPlayers()[1]
   local S = game.ServerScriptService.Services
   local Data = require(S.DataService)
   local Currency = require(S.CurrencyService)
   local Tx = require(S.ProfileTransactionService)
   local before = Data.getPlayerData(p).coins
   local h = Currency.beginSpendTransaction(p, "coins", 1, "QOF25Studio")
   print("QOF25_RESERVED", h ~= nil, before, Data.getPlayerData(p).coins, Tx.getOwnerName(p))
   print("QOF25_SECOND_OWNER_BLOCKED", Currency.beginSpendTransaction(p, "diamonds", 1, "OtherService") == nil)
   print("QOF25_SAVE_BLOCKED", Data.savePlayerData(p, false))
   print("QOF25_ROLLBACK", Currency.rollbackSpendTransaction(h), Data.getPlayerData(p).coins)
   ```
   Erwartet: Reservation erfolgreich; Coins vor/nach Begin identisch; Owner `QOF25Studio`; zweiter Owner blockiert; Save meldet `false, Profile transaction pending`; Rollback erfolgreich und Coins weiterhin identisch. Falls das Profil 0 Coins hat, zuerst regulär Coins erspielen.
3. Genau-einmal-Commit prüfen:
   ```lua
   local p = game:GetService("Players"):GetPlayers()[1]
   local S = game.ServerScriptService.Services
   local Data = require(S.DataService)
   local Currency = require(S.CurrencyService)
   local before = Data.getPlayerData(p).coins
   local h = Currency.beginSpendTransaction(p, "coins", 1, "QOF25Commit")
   print("QOF25_BEFORE_COMMIT", before, Data.getPlayerData(p).coins)
   print("QOF25_COMMIT", Currency.commitSpendTransaction(h), Data.getPlayerData(p).coins)
   print("QOF25_DOUBLE_COMMIT", Currency.commitSpendTransaction(h))
   ```
   Erwartet: vor Commit unverändert; erster Commit `true` und exakt ein Coin weniger; zweiter Commit `false` und keine weitere Abbuchung.
4. Retrybaren zentralen Rollback prüfen:
   ```lua
   local p = game:GetService("Players"):GetPlayers()[1]
   local Tx = require(game.ServerScriptService.Services.ProfileTransactionService)
   local attempts = 0
   local h = Tx.begin(p, "QOF25Retry")
   Tx.setSettler(h, function()
       attempts += 1
       return attempts >= 2
   end)
   print("QOF25_RETRY_1", Tx.settlePlayer(p), Tx.hasPending(p), attempts)
   print("QOF25_RETRY_2", Tx.settlePlayer(p), Tx.hasPending(p), attempts)
   ```
   Erwartet: erster Aufruf `false, true, 1`; zweiter `true, false, 2`.
5. Je einen normalen Kauf in Shop, Upgrade Tree und Potion Upgrade durchführen. Erwartet: korrekte serverseitige Kosten, kein kurzes Debit-/Refund-Flackern, genau ein finaler State und kein roter Fehler.
6. Einen manuellen Paid Hatch mit vorhandenen Shiny-Charges und einen normalen Free-/Reward-Hatch, falls im Testfluss erreichbar, ausführen. Erwartet: vollständiges Batch oder keine Änderung; Charge nur bei erfolgreichem Paid Hatch verbraucht; kein teilweises Inventar.
7. Paid Auto-Hatch-Zugang kaufen und danach Enchanting einmal verwenden. Erwartet: jeweils genau eine Abbuchung, vollständiger finaler DTO/State und kein doppelter Kauf durch schnellen Doppelklick.
8. Gold- und Rainbow-Maschine je einmal mit gültigen Inputs testen. Erwartet: bestehende 13/26/39/50/63/88/100-Chancen und Business-Failure-Semantik unverändert; keine neue QOF-27-Reihenfolge behaupten.
9. Während schneller wiederholter Aktionen aus zwei Composite-UIs Doppelklicks/Parallelversuche erzeugen. Erwartet: ein Pfad wird sauber abgewiesen oder serialisiert; keine doppelte Abbuchung, kein negatives Guthaben und kein doppeltes Pet/Upgrade.
10. Nach den Käufen verlassen und erneut beitreten. Erwartet: nur abgeschlossene Zustände sind gespeichert; keine reservierte Currency, kein halbes Batch und kein verlorener erfolgreicher Kauf.
11. Optional einen Server mit zwei Spielern schließen. Erwartet: beide Profile werden unabhängig gesettelt; ein blockierter Spieler verhindert nicht die sichere Speicherung des anderen.
12. Desktop- und Mobile-Smoke für Shop, Hatch, Upgrade Tree, Machines, Enchanting und Auto-Hatch durchführen. Erwartet: keine neue UI-/Remote-Störung.

## Bekannte Grenzen

Der echte Roblox-Studio-Playtest, DataStore-Rejoin, Netzwerk-/Physikpfad und ein harter Prozessabbruch können im Linux-Sandbox-Build nicht ausgeführt werden. QOF-25 verändert bewusst nicht die Potion-/Shiny-/AutoDrink-Lease-Races (QOF-26), die verbindliche Maschinenreihenfolge `Inputs entfernen → RNG` (QOF-27) oder Auto-Hatch Contract V2 mit x1/x3/x9 und HUD-Flow (QOF-28). Direkte Reward-Credits bleiben additive autoritative Mutationen; QOF-25 serialisiert Composite Owner und verhindert Snapshots, führt aber kein allgemeines Event-Sourcing-Ledger ein.
