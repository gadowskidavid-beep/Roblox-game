# QOF-19 Pet Enchanting

## Produktvertrag

QOF-19 ergänzt QOF-18 um ein serverautoritatives, inventarbasiertes Pet-Enchanting. Es gibt **keine Enchant-Weltstation**, keinen ProximityPrompt, keinen Enchant-Aktivierungstoken und keinen zweiten Machine-Remote. Der Einstieg ist der `Details`-Button einer normalen Pet-Karte. `UseMachine` bleibt der einzige Machine-Mutationsweg; Enchanting verwendet ausschließlich `GetEnchantingState` und `RollPetEnchant`.

| Vertrag | Wert |
|---|---:|
| Runtime-Gate | `BalanceConfig.Enchanting.RuntimeEnabled = true` |
| Preis pro Roll oder Reroll | exakt 500 Diamonds |
| Slots pro Pet | exakt 1 |
| Netzwerkvertrag | V1 |
| Persistenz | optionales `pet.enchantId` |
| Kein Enchant | boolescher DTO-Sentinel `false`; in der Persistenz `nil`/fehlendes Feld |

Jeder erfolgreiche Roll ersetzt den einen Slot. Ein vorhandenes Ergebnis kann weder behalten noch parallel gespeichert werden. Auch ein Reroll auf dieselbe ID ist ein normaler bezahlter Erfolg: 500 Diamonds werden verbraucht und die Pet-Revision steigt.

## Kanonischer Pool

`BalanceConfig.Enchanting.Pool` ist die einzige Whitelist und Reihenfolge. Die ganzzahlige Ziehung ist 1..100 einschließlich beider Grenzen.

| Bereich | ID | Gewicht | Wirkung |
|---:|---|---:|---:|
| 1-35 | `StrongI` | 35 % | Damage ×1,10 |
| 36-50 | `StrongII` | 15 % | Damage ×1,25 |
| 51-55 | `StrongIII` | 5 % | Damage ×1,50 |
| 56-85 | `AgileI` | 30 % | Campaign-Speed ×1,10 |
| 86-97 | `AgileII` | 12 % | Campaign-Speed ×1,20 |
| 98-100 | `AgileIII` | 3 % | Campaign-Speed ×1,35 |

`BalanceConfig.Validate()` erzwingt den aktiven Gate, genau vier Enchanting-Vertragsfelder, den exakten Preis, einen Slot, genau sechs vollständig geformte Outcomes in dieser Reihenfolge und eine Gewichtssumme von 100.

## Persistenz und Schema V10

`DataSchema.VERSION = 10`. Pro Pet ist ausschließlich eine der sechs kanonischen IDs in `enchantId` persistent. `PetEnchantMath.normalizeEnchantId` entfernt leere, unbekannte, falsch geschriebene oder falsch typisierte IDs. Bei jedem Normalize werden untrusted/abgeleitete Felder gelöscht:

- `enchant`
- `enchantData`
- `enchants`
- `enchantStat`
- `enchantMultiplier`

V9-Pets ohne Enchant erhalten keinen erfundenen Wert. Gültige IDs überleben Migration, Persistence-Clone und Rejoin idempotent. `pet.damage` bleibt der kanonische Variant-Kompatibilitätsmirror und speichert keinen Strong-Multiplikator.

`PetEnchantMath` baut beim Laden eine private ID-Tabelle aus dem Balance-Pool. Definitionen und Public Pool werden nur als defensive Kopien ausgegeben. Stat und Multiplikator werden nie aus Pet-Payloads gelesen; ausschließlich `rawget(pet, "enchantId")` wird gegen die private Whitelist aufgelöst.

## Strong- und Agile-Semantik

**Strong:** `PetService.getPetDamage` ermittelt zuerst den kanonischen Variant-/Shiny-Basisschaden, multipliziert ihn mit dem whitelisted Strong-Wert und komponiert danach bestehende StrongPets-/Shop-Buffs. Agile wirkt nicht auf Damage.

**Agile:** `PetService.getCampaignLaneSpeed` verwendet ausschließlich `PetData.Pets[petId].baseSpeed × Agile`. Strong wirkt nicht auf Speed. `CampaignService.deployPet` löst Damage und Speed geschützt und vollständig **vor** dem Energie-Commit auf. Fehlerhafte, fehlende oder nicht-endliche Provider verbrauchen keine Energie. Speed wird beim Deploy gesnapshottet; ein späterer Reroll verändert ein bereits eingesetztes Pet nicht. Damage bleibt beim Angriff über `PetService.getPetDamage` zentral auflösbar.

## Contract V1

Alle Requests müssen plain tables ohne Metatable, zusätzliche Keys oder fehlende Keys sein. Pet-IDs sind nichtleer und maximal 128 Zeichen.

### GET_STATE Request

Exakt drei Felder:

```lua
{
    contractVersion = 1,
    action = "GET_STATE",
    petInstanceId = "stable-pet-id",
}
```

### ROLL Request

Exakt fünf Felder:

```lua
{
    contractVersion = 1,
    action = "ROLL",
    petInstanceId = "stable-pet-id",
    expectedStateRevision = 0,
    expectedEnchantId = false,
}
```

`expectedStateRevision` ist eine nichtnegative endliche Ganzzahl. `expectedEnchantId` ist exakt `false` oder eine kanonische ID. `nil`, unbekannte IDs, Zusatzfelder und Metatables sind ungültig. Für einen Reroll muss der Client exakt die zuletzt akzeptierte alte ID senden.

### State DTO

Jede Antwort wird frisch aufgebaut:

```lua
{
    contractVersion = 1,
    stateRevision = 0,
    runtimeEnabled = true,
    pet = {
        instanceId = "stable-pet-id",
        enchantId = false,
    },
    economy = {
        currency = "diamonds",
        price = 500,
    },
    maxSlotsPerPet = 1,
    outcomes = {
        -- sechs frische { id, weight, stat, multiplier }-Tabellen
    },
    availability = {
        canRoll = true,
        reason = nil,
    },
    isReroll = false,
}
```

Stabile Reason Codes sind `INVALID_REQUEST`, `RUNTIME_DISABLED`, `SERVICE_UNAVAILABLE`, `PROFILE_UNAVAILABLE`, `PET_NOT_FOUND`, `INVALID_PET_STATE`, `STALE_STATE`, `INSUFFICIENT_BALANCE`, `BUSY`, `RATE_LIMITED`, `TECHNICAL_FAILURE` und `ROLLBACK_FAILED`.

Main erstellt beide RemoteFunctions zur Laufzeit. Für GET gelten 0,15 Sekunden Cooldown und 12 Calls/10 Sekunden; für ROLL 0,35 Sekunden und 8 Calls/10 Sekunden. Bei Rate Limit kommt ein frischer autoritativer State zurück. Main prüft Player und Abuse-Grenzen; exakte DTO-Form, Ownership, Revision, Economy, RNG und Rollback bleiben `EnchantingService`-Eigentum.

## Transaktion, Rollback und Settlement

Lock-Reihenfolge für einen Roll:

1. `PetService.beginInventoryMutation(player, "EnchantingService")` nimmt den gemeinsamen opaken Inventory-Lease.
2. Der Enchanting-Player-Lock serialisiert die Transaktion.
3. Profil, Pets-Tabellenidentität, Pet-Index/-Referenz, alte Enchant-Präsenz/-ID und Revision werden geprüft.
4. `CurrencyService.beginSpendTransaction` reserviert exakt 500 Diamonds ohne Commit-Event.
5. RNG zieht eine Ganzzahl von 1 bis 100.
6. Lease, Profil, Pet-Identität, alter Wert und Revision werden erneut geprüft.
7. Nur `pet.enchantId` wird geschrieben.
8. `commitSpendTransaction` ist der Point of no Return.

Vor dem Currency-Commit müssen Pet und exakter Debit gemeinsam restauriert werden. Fehler bei Spend, RNG, Revalidierung, Mutation oder Commit liefern nur dann einen retrybaren technischen Fehler, wenn die Restaurierung vollständig gelang. Schlägt Pet- oder Currency-Restore fehl, bleibt die Transaktion mit Lease und Handles in `_activeTransactions`; der Service meldet `ROLLBACK_FAILED` und blockiert konkurrierende Pet-Mutationen fail-closed.

Nach erfolgreichem Currency-Commit ist der bezahlte Roll endgültig. Revision-Bump, Inventory-Replikation, State-Aufbau und spätere Transport-/Eventfehler laufen best effort und dürfen den Erfolg weder zurückrollen noch in einen retrybaren Fehler umdeuten. Ein erfolgreicher Client-ROLL wird nur akzeptiert, wenn seine Revision strikt über `expectedStateRevision` liegt; semantische Fehler dürfen denselben autoritativen Stand zurückgeben.

`cleanup`/`onPlayerRemoving` und `prepareForShutdown` versuchen nicht-ausgeführte Restores erneut. Ein noch laufender oder nicht restaurierbarer Datensatz bleibt gehalten. Ownerlose Locks werden nie geraten oder blind gelöscht.

## Gemeinsamer Inventory-Lease und Lifecycle

`PetService` hält pro Player einen opaken Lease mit Tabellenidentität und Inventory-Inkarnation. Nur exakt derselbe aktuelle Lease kann freigegeben werden. Ein erfolgreicher Mutations-Commit erhöht die Inkarnation; stale Finally-/Cleanup-Pfade können keinen neueren Owner freigeben.

Der Lease schützt jetzt **jede** Pet-Inventar-/Pet-State-Mutation: paid Manual-/Auto-Hatch über die gesamte Prepare/Spend/Commit/Rollback-Transaktion, den freien Campaign-/Legacy-Hatch, Equip, Unequip, Favorite, Delete, Bulk Delete, Legacy-Convert sowie Machine und Enchanting. Direkte CRUD-Mutatoren erwerben genau einen Lease und geben nur ihre exakte Identität frei. Egg, Machine und Enchanting erwerben den Lease einmal im äußeren Owner und reichen ihn an Low-Level-Commit/Rollback weiter; diese Pfade versuchen keinen rekursiven Erwerb und können daher nicht selbst deadlocken. Ein fremder aktiver Owner führt fail-closed zu `BUSY`/`Pet inventory mutation already in progress`.

Egg, Machine und Enchanting halten retrybare `_activeTransactions`, Shutdown-Gates und ihre Restore-Handles. Egg löscht einen Hatch-Lock nie blind: ein fehlgeschlagener Pet-/Potion-/Currency-Restore behält Transaktion, Lease und Lock, bis `cleanup` vollständig restaurieren und exakt releasen kann.

`DataService` bindet jeden Cacheeintrag an die konkrete Player-Instanz und führt pro UserId einen expliziten Pending-Record mit `settled`, `settling`, `completed` und Retry-Zähler. Noch bevor `PlayerRemoving` einen Pending-Record anlegt beziehungsweise `BindToClose` irgendeinen Owner als settled beobachtet, schließt `DataService.closeMutationAdmission` die zentrale Mutationsaufnahme für diese Profilgeneration. Neue Delete-/Hatch-/Equip-/Favorite-/Machine-/Enchant-Leases scheitern danach fail-closed; ein bereits existierender Lease darf ausschließlich zu Ende settlen und muss idle sein, bevor der finale Snapshot gespeichert wird. `PlayerRemoving` invalidiert Auto-Hatch einmal und registriert anschließend eine idempotente Settlement-Funktion. Jeder Retry versucht Pickup, Egg, Machine und Enchanting; erst nach vollständigem Settlement laufen die übrigen transienten Cleanups und exakt ein erfolgreicher finaler Save/Session-Release. Ein Fehler lässt Cache, alte Player-Referenz und Owner-Handles gehalten.

Ein Rejoin derselben UserId erhält diesen Cache niemals. `loadPlayerData` gibt der Pending-Queue nur ein begrenztes Retry-Fenster; bleibt der alte Owner ungelöst, wird der neue Player mit einer sicheren Rejoin-Meldung abgewiesen. `getPlayerData` projiziert den gehaltenen Cache ebenfalls nicht auf eine andere Player-Instanz.

Bei `BindToClose` sperrt `beginShutdown` zuerst neue Auto-Hatch-/Egg-/Machine-/Enchant-Arbeit. Danach werden **alle Cacheeinträge**, einschließlich bereits verlassener Player-Referenzen, bis zur gemeinsamen 25-Sekunden-Deadline profilweise wiederholt settlet und gespeichert. Ein executing/transienter Owner wird in späteren Pässen erneut versucht. Geklärte Profile werden sofort final gespeichert und released; nur konkret ungelöste UserIds bleiben fail-closed im Cache. Ein ungelöster User unterdrückt niemals Saves anderer Profile.

## Machine-Verbrauch

`prepareVariantConversion` snapshotet für jedes Input-Pet Enchant-Präsenz und exakte ID. `commitVariantConversion` bricht ab, wenn sich der Enchant zwischen Prepare und Commit verändert. Bei normalem Machine-Erfolg **oder** normalem Business-Misserfolg werden Input-Pets samt Enchants verbraucht; Diamonds werden entsprechend dem vorhandenen Machine-Vertrag belastet. Ein erfolgreicher Golden-/Rainbow-Output startet explizit ohne Enchant. Technische Fehler vor Commit restaurieren die ursprünglichen Pet-Objekte und damit ihre Enchants.

Die Machine-UI muss dauerhaft warnen:

- `Input pets and their enchants are always consumed.`
- `Diamonds are also spent on a normal failure.`
- `A successful output starts with no enchant.`

## Client, Inventory und Rolling Deployment

Der Client entdeckt `EnchantingClientSession`, `GetEnchantingState` und `RollPetEnchant` ausschließlich mit `FindFirstChild`. Ein neuer Client auf einem alten Server darf nicht durch `WaitForChild` blockieren; das Detail zeigt stattdessen sichtbar `UNAVAILABLE` und deaktiviert den Action-Button.

`EnchantingClientSession` bindet jede Operation an stabile Pet-ID, Generation, Revision und beim ROLL an die exakte alte Enchant-ID. Close, Pet-Wechsel A→B, malformed replacement und stale Responses verlieren Besitz. Vor jeder Session-/UI-Anwendung validiert das pure Shared-Modul `EnchantingClientContract` ausschließlich den exakten kanonischen V1-State: Top-Level, `pet`, `economy`, `availability`, Outcome-Liste und jedes Outcome müssen plain tables ohne Zusatzkeys sein; der Preis ist exakt 500 Diamonds, die Slotzahl exakt 1 und die sechs Definitionen müssen ID, Reihenfolge, Weight, Stat und Multiplier exakt wie `BalanceConfig.Enchanting.Pool` abbilden. Metatables, Preis 0/501, vertauschte Outcomes und jede Erweiterung liefern sichtbar `UNAVAILABLE`.

Jede normale Inventory-Karte hat `PetDetailsBtn`. Das Panel zeigt nur Serverpreis und Serverpool, markiert irreversible Rerolls und übernimmt keine optimistische Currency-/Pet-Mutation. `PetInventoryUpdated` ersetzt das lokale Inventar-Snapshot. Wird die stabile Detail-Pet-ID durch Delete oder Machine-Verbrauch entfernt, schließt das Panel samt Session; unbekannte/malformed/fehlende Runtime-Daten zeigen `UNAVAILABLE`.

Rolling Deployment:

- neuer Client + alter Server: optionale Discovery, keine Blockade, `UNAVAILABLE`;
- alter Client + neuer Server: bestehende QOF-17/18-Flows bleiben unverändert;
- gemischte Serverversionen: nur V10-Whitelist-IDs sind autoritativ, alte/abgeleitete Felder bleiben inert;
- kein Enchant-Station-Spawn und kein zusätzlicher Machine-Remote sind Teil des Rollouts.

## Automatisierte Verifikation

```bash
# Gesamte Luau-Suite
/projects/sandbox/.qof02-lua/lua tests/run_tests.lua

# Optional: alle Runtime-/Spec-Dateien kompilieren
/projects/sandbox/.qof10-luau/luau-compile <file.lua>

# Place in einer sauberen/temporären Ausgabe generieren
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 tools/generate_rbxlx.py

# Bytegenaue eins-zu-eins-Parität und QOF-17/18/19-Quellverträge
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 tests/verify_generated_place.py

# Python-Syntax
/usr/bin/python3 -m py_compile tools/generate_rbxlx.py tests/verify_generated_place.py

git diff --check
```

Der Generator bettet `PetEnchantMath`, `EnchantingClientSession` und den puren `EnchantingClientContract` als Shared ModuleScripts sowie `EnchantingService` als Service ModuleScript ein. Der Verifier verlangt exakt **74 ModuleScripts + 1 Script + 1 LocalScript = 76 Runtime-Sources** und bytegenaue eins-zu-eins-Parität mit dem aktuellen `src/`-Baum. Zusätzlich prüft er profilisolierte Lifecycle-Retries, die vollständige Lease-Abdeckung und die exakte kanonische Client-DTO-Grenze.

## Manuelle Studio-/Live-Matrix

| Fall | Durchführung | Erwartung |
|---|---|---|
| 499/500 Diamonds | GET/ROLL einmal mit 499, dann mit exakt 500 | 499: `INSUFFICIENT_BALANCE`, kein RNG/Commit; 500: exakt ein bezahlter Roll, Balance 0 |
| Same-result paid reroll | Vorhandenes `StrongI`, RNG erneut im `StrongI`-Bereich | 500 Diamonds verbraucht, ID darf gleich bleiben, Revision steigt strikt |
| Concurrent Machine/Roll | Machine-Convert und Enchant-ROLL desselben Players gleichzeitig auslösen | Genau ein Shared-Lease-Owner; der andere erhält `BUSY`/Machine busy, keine Doppelmutation |
| Delete/consume detail | Detail öffnen, Pet serverseitig löschen bzw. in Machine verbrauchen | Neues Inventory-Snapshot entfernt ID; Detail und Session schließen, keine stale Aktion |
| Delayed A/B | Detail A laden, sofort B öffnen, A-Antwort verzögern | A verliert Generation; nur B darf rendern |
| Malformed/latency | Extra Keys, Metatable, falsche Revision/ID, fehlendes `false`, Timeout und out-of-order Responses | Fail-closed, kein Debit/RNG; malformed/stale Clientdaten rendern nie, UI zeigt ggf. `UNAVAILABLE` |
| Post-commit event failure | `PetInventoryUpdated`, Revision-Bookkeeping oder State-Aufbau nach Currency-Commit fehlschlagen lassen | Roll bleibt erfolgreicher, genau ein Debit, kein Rollback und kein sicher wiederholbarer Fehler |
| Pre-commit fault stages | Fehler nach Spend, Roll, Pet-Mutation und vor Commit injizieren | Exakte alte Enchant-Präsenz/-ID und 500 Diamonds restauriert; keine Events |
| Restore failure | Currency- oder Pet-Restore zunächst fehlschlagen, danach reparieren | `ROLLBACK_FAILED`, Lease/Profil gehalten; späteres Cleanup settlet exakt einmal |
| Machine enchant change | Zwischen Prepare und Commit Enchant-ID/Präsenz ändern | Machine-Commit verweigert und technisch restauriert |
| Machine Business-Failure | Enchanted Inputs, normaler Chance-Misserfolg | Inputs/Enchants und Machine-Kosten verbraucht; kein Output |
| Machine Success | Enchanted Inputs, erfolgreicher Gold/Rainbow-Convert | Inputs verbraucht; Output existiert ohne `enchantId` |
| Strong/Agile | Alle sechs IDs auf Normal/Golden/Rainbow/Shiny testen | Strong nur Damage; Agile nur Campaign-Speed; unbekannte/gefälschte Felder neutral |
| Campaign snapshot | Agile-Pet deployen, danach auf Strong rerollen | Lane-Speed bleibt Deploy-Snapshot; spätere Angriffe nutzen aktuellen zentralen Damage |
| Rolling alt/neu | Neuer Client gegen Server ohne QOF-19 und alter Client gegen QOF-19 | Kein Startup-Hang; sichtbar `UNAVAILABLE`; alte Flows unverändert |
| Keine Station/Remote | Workspace/Remotes in Studio inspizieren | Keine Enchant-Station; nur zwei Enchant-Remotes und weiterhin genau ein `UseMachine` |
| DataStore/Rejoin | Gültige/ungültige IDs speichern, verlassen, erneut joinen | Nur sechs IDs persistieren; unbekannte/abgeleitete Felder entfernt; gültige ID bleibt |
| PlayerRemoving | Leave während laufender bzw. ungelöster Transaktion; Restore zunächst fehlschlagen und danach reparieren | Pending-Record retried tatsächlich; Egg vor Machine vor Enchanting; danach genau ein finaler Save/Release |
| Rejoin bei Pending Owner | Nach permanent fehlendem Restore mit neuer Player-Instanz derselben UserId joinen | Alter Cache bleibt nur an alter Instanz; begrenzte Retries, danach Kick/fail closed statt Cache-Übernahme |
| Shutdown | Zwei Profile, davon eines executing/transient/permanent unresolved; eines bereits departed | Neue Arbeit gesperrt; spätere Settlement-Pässe; jedes geklärte Profil sofort gespeichert/released; nur konkrete unresolved userIds übersprungen |
| Multiplayer/Live | Mehrere Spieler unter normaler und künstlicher Latenz | Locks/Revisionen pro Player/Pet isoliert, keine Cross-Player-Auswirkung oder doppelter Debit |
