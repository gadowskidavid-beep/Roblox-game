# Pet Rock Simulator – QOF-32 bis QOF-36 Inventory-/Items-QOL-Roadmap

> **Fortsetzbarer Arbeitsauftrag für Kiro**
> Diese Datei ergänzt `QOF-22-31-ROADMAP-README.md`. Sie darf erst nach QOF-31 begonnen werden. Der Auto-Hatch-Neubau aus Nutzerschritt 1 ist bereits verbindlich in QOF-28 eingeplant, weil er die Transaktions- und Potion-Grundlagen aus QOF-25/26 benötigt.

## 1. Ziel und Reihenfolge

Die gewünschte QOL-Überarbeitung wird nicht als riskanter Monolith umgesetzt:

1. QOF-28: Auto-Hatch Contract V2 mit einzigem HUD-Toggle und ausschließlich x1/x3/x9.
2. QOF-32: serverautoritative generische Itemgrundlage und Schema-Migration.
3. QOF-33: zentrales Inventory-Shell mit Pets, Items, Mastery, Quests und Shop.
4. QOF-34: reibungslose Potion-/Itemnutzung und HUD-Timer.
5. QOF-35: Enchanting-Vertrag beweisen und UI auf genau einen manuellen Versuch reduzieren.
6. QOF-36: gemeinsame Studio-/Multiplayer-/Persistenzabnahme und Release.

Skill Tree, vollständige deutsche Lokalisierung und allgemeine ZoneService-Zerlegung bleiben außerhalb dieses Plans.

## 2. Verifizierter Ist-Zustand

- `UIController.lua` ist ein Monolith mit getrennten ScreenGuis für Pet Inventory, Shop, Quests, Mastery und Pet Index.
- Der Index bleibt ausdrücklich außerhalb des neuen Inventory-Shells als Weltmaschine/eigener Screen.
- Es existiert noch kein generisches Itemmodell. Persistiert werden nur `potionInventory`, aktive Buffquellen, Potion-Upgrades und Auto-Drink-Auswahl.
- Shopkauf und Potionnutzung sind bereits getrennte Serverdienste, aber heute in derselben Shopkarte sichtbar.
- Timed Potions desselben kanonischen Typs verlängern bereits ab `max(now, oldExpiry)`; dieses Verhalten bleibt verbindlich. Verschiedene Bufftypen können parallel aktiv sein. Luck und Mega Luck bleiben getrennte Quellen desselben Slots, wobei der stärkste aktive Multiplikator wirkt.
- Die tatsächliche Codebasis enthält **keinen Auto-Enchant-Loop und keine Ziel-Enchant-Auswahl**. QOF-19 besitzt bereits genau einen serverautoritativen, bezahlten ROLL pro Buttonklick. QOF-35 ist deshalb primär UI-/Vertragsbereinigung und Regressionsevidenz, keine erfundene Loop-Entfernung.
- QOF-25/26 müssen vor Items/Potions abgeschlossen sein, damit Autosave, Shop, Potion, Shiny-Charges und Hatch denselben sicheren Profil-/Lease-Lifecycle verwenden.

## 3. Offene Produktentscheidungen

Diese Fragen blockieren nicht QOF-22–27. Sie müssen spätestens vor dem genannten Paket entschieden werden:

1. **Vor QOF-28:** Darf das Auto-Hatch-Icon nur die aktuell nahe Egg-Station anbieten, oder soll eine Auswahl aller freigeschalteten Eier den Spieler sicher zur Station führen? Fernhatchen ohne Welt-/Stationsbindung ist kein zulässiger Default.
2. **Vor QOF-28:** Wie werden vorhandene x2/x5/x10-Upgrades auf x3/x9 migriert? Sicherer Vorschlag: alter x2-Zugang → x3, alter x5-Zugang → x3, alter x10-Zugang → x9; gekaufte Upgrade-IDs bleiben erhalten und werden nicht gelöscht. Eine andere Zuordnung braucht eine ausdrückliche Entscheidung.
3. **Vor QOF-32:** Konkrete IDs, Namen, Effekte, Stacklimits, Quellen und Balance für mindestens ein Usable Item, eine Frucht und eine Mystery Box. Potions sind bereits definiert; Kategorien allein reichen nicht für serverautoritatives Gameplay.
4. **Vor QOF-33:** Sollen Mastery-/Quest-/Shop-HUD-Buttons komplett verschwinden oder als Shortcuts bestehen bleiben? Sicherer Default: permanentes HUD enthält Inventory, Index, Auto-Hatch und Settings; die drei alten Buttons entfallen.
5. **Vor QOF-34:** Keine weitere Stackingfrage nötig, solange das bestehende Verlängerungsverhalten gewünscht ist. Eine neue Potion desselben Typs verlängert die Restzeit; sie ersetzt sie nicht.

## 4. Gemeinsame Architekturregeln

- Server ist alleinige Autorität für Besitz, Kategorien, Stackmengen, Preise, Effekte, RNG, Cooldowns und Ablaufzeiten.
- Shared UI-Daten sind Präsentation, nie Katalogautorität.
- Jedes Command-DTO ist versioniert, exakt geformt, metatable-frei, größenbegrenzt und rate-limited.
- Profile werden nur über den zentralen QOF-25-Mutationsowner geändert; Potion/Shiny-Pfade verwenden den QOF-26-Lease.
- Ein zentrales Client-Shell darf nur Navigation und DTO-Projektion besitzen. PetService, ItemService, PotionService, ShopService, MasteryService und QuestService behalten ihre Domänen.
- Neue UI-Features werden als Controller-Module erstellt; `UIController.lua` erhält nur Komposition/Adapter, keine weiteren tausend Zeilen Featurelogik.
- Tabwechsel blendet bestehende Content-Frames ein/aus. Kein Re-Parenting und kein vollständiger Neuaufbau pro Klick.
- Jede asynchrone Antwort ist an Screen-/Tabgeneration und monotone Domainrevision gebunden.
- Jedes Code-QOF liefert Tests, vollständigen temporären Release-Satz, echte binäre Test-RBXL, SHA, Studio-Matrix und ehrlichen Status gemäß `.kiro/steering/qof-test-debug-workflow.md`.

## 5. Fortschritt

| QOF | Paket | Status | Abhängigkeit | Nächste Aktion | Studio-Gate | Evidenz |
|---|---|---|---|---|---|---|
| QOF-32 | Item Registry und DataSchema | OFFEN | QOF-31 | Produktkatalog bestätigen | separat | – |
| QOF-33 | Zentrales Inventory-Shell | OFFEN | QOF-32 | nach QOF-32 | separat | – |
| QOF-34 | Potion-/Usable-Item-UX | OFFEN | QOF-26, QOF-32–33 | nach QOF-33 | separat | – |
| QOF-35 | Single-Enchant-UX und Vertragsevidenz | OFFEN | QOF-31, QOF-33 | nach QOF-33 | separat | – |
| QOF-36 | QOL-Gesamtabnahme und Release | OFFEN | QOF-28, QOF-32–35 | finale Matrix | final | – |

---

# QOF-32 – Serverautoritative Item Registry und DataSchema

## Scope

1. `ItemData` als kanonischen Serverkatalog mit `itemId`, Kategorie, Stacklimit, erlaubten Actions, Shopquelle und Domainowner einführen.
2. Kategorien mindestens: `usable`, `potion`, `fruit`, `mysteryBox`. Der Client darf filtern, aber keine Kategorie behaupten, die der Server vertraut.
3. DataSchema auf eine neue Version migrieren. Bestehendes `potionInventory` wird verlustfrei in die kanonische Itemprojektion übernommen; aktive Buffs bleiben getrennt vom Besitz.
4. Rolling-Kompatibilität, Whitelist, endliche Ganzzahlen, per-ID-Caps, unbekannte IDs, sparse/hostile Maps und idempotentes `cloneForPersistence` definieren.
5. `ItemService` besitzt Read-State und Use/Open-Admission. Effekte werden an autoritative Domainhandler delegiert; keine allgemeine Funktion darf beliebige Client-Effektdaten ausführen.
6. Mystery-Box-RNG verwendet ein eigenes Prepare/Commit-Ergebnis und keine clientseitige Auswahl. Usable-/Fruit-Effekte brauchen vor Code konkrete Balanceentscheidungen.
7. Shopkauf bleibt ShopService und schreibt atomar über den zentralen Profilowner in Itemstacks.

## Abnahme

- Alte Potionbestände und aktive Timer überleben Migration, Save, Reload und Rolling-Fallback ohne Duplikation.
- Kategorie-Spoofing, unbekannte IDs, Extra-Keys, negative/NaN/Infinity-Mengen und Stacküberlauf mutieren nichts.
- Ein Itemkauf ist entweder vollständiger Debit plus Stack oder vollständiger Vorzustand.
- Mystery Box ist entweder vollständig konsumiert plus vollständiges Ergebnis oder vollständig zurückgerollt.

---

# QOF-33 – Zentrales Inventory-Shell

## Scope

1. Neues `InventoryShellController`-Modul mit genau einem Fenster und Tabs `Pets | Items | Mastery | Quests | Shop`.
2. Je Tab ein dauerhaft erzeugter Content-Frame; Wechsel nur über `Visible`/aktive Styles, nicht Re-Parenting oder Neuaufbau.
3. Bestehende Screens schrittweise über Adapter in `PetsTabController`, `ItemsTabController`, `MasteryTabController`, `QuestsTabController`, `ShopTabController` verschieben.
4. Pets-Tab behält Suche, Sortierung, Variantenfilter, Multi-Select, Favorit/Lock, Delete und Maschinenmodus. Gridkarten bleiben kompakt; Details und Enchanting öffnen erst nach Petklick.
5. Items-Tab zeigt servergelieferte Stacks und Unterfilter für Usables, Potions, Früchte und Mystery Boxes. Keine optimistische Besitzmutation.
6. Mastery, Quests und Shop übernehmen bestehende Logik/Remotes unverändert; nur Präsentation und Navigation ändern sich.
7. Pet Index bleibt außerhalb des Shells und darf weder Tab noch eingebetteter Frame werden.
8. Desktop/Mobile-Layout, Fokus, Back/Close, Tabgeneration, stale Responses und wiederholtes Öffnen ohne Connection-Leaks absichern.

## Abnahme

- Ein Fenster, exakt fünf Tabs, höchstens ein sichtbarer Content-Frame.
- Tabwechsel erzeugt keine neuen Eventverbindungen und verliert keinen Scroll-/Suchzustand ohne dokumentierten Grund.
- Alle bisherigen Pets-Funktionen und Maschinenübergaben bleiben funktionsfähig.
- Index bleibt getrennt und aktualisiert bestätigte Discoveries weiterhin korrekt.

---

# QOF-34 – Reibungslose Potions und Usable Items

## Scope

1. Potion-/Itemklick im Items-Tab sendet unmittelbar genau einen Use-Intent; kein Bestätigungsdialog und kein künstlicher UX-Cooldown.
2. Serverseitiges Rate Limit und per-profile Lease verhindern Spam/Doppelverbrauch, ohne unterschiedliche gültige Potiontypen künstlich zu serialisieren, nachdem die vorherige Transaktion abgeschlossen ist.
3. Potionkauf ausschließlich im Shop-Tab; Nutzung ausschließlich im Items-Tab. Shopkarten besitzen keinen Drink-/Use-Button mehr.
4. Gleichartige timed Potions verlängern ab `max(now, expiresAt)`. Verschiedene Bufftypen bleiben parallel. Shiny bleibt chargebasiert und verwendet den gemeinsamen QOF-26-Lease.
5. `ActiveEffectHudController` rendert unten links pro aktiver Quelle/definiertem Effekt ein kompaktes Icon mit serverzeitkorrigiertem Countdown. Der Client darf Ablauf nur darstellen; Serverzustand entscheidet.
6. Abgelaufene Icons verschwinden auf autoritatives Stateupdate beziehungsweise lokal visuell bei null, können aber bei einem neueren Serverstate wieder erscheinen.
7. Mobile Safe Area, mehrere gleichzeitige Effekte, Respawn, Rejoin, Offline-Zeit und Clock-Skew testen.

## Abnahme

- Ein Tap = höchstens ein autoritativ zugelassener Verbrauch; kein Dialog und keine Warteanimation als Gate.
- Kauf und Nutzung sind UI-seitig und serverseitig getrennt.
- Timer zeigen keine negativen oder NaN-Werte und verleihen niemals selbst einen Buff.
- Paralleles Hatch/Shiny, Auto-Drink, Shopkauf, manuelles Trinken, Autosave, Leave und Shutdown können keine neuere Mutation überschreiben.

---

# QOF-35 – Single-Enchant-UX und Vertragsevidenz

## Verifizierte Ausgangslage

Es gibt im aktuellen Repository keinen Auto-Enchant-Code. `GetEnchantingState` lädt genau ein Pet; `RollPetEnchant` akzeptiert einen exakten V1-ROLL und führt unter Lock/Lease höchstens einen bezahlten Versuch aus. Kosten sind 500 Diamonds; der Pool besteht aus Strong I–III und Agile I–III. Diese Ökonomie bleibt unverändert.

## Scope

1. Enchanting-UI in ein eigenes Featuremodul auslagern und aus dem Pets-Detail öffnen.
2. UI enthält nur aktuellen Enchant, servergelieferte Kosten, sechs servergelieferte Outcomes/Prozente und einen `Enchant`/`Reroll`-Button.
3. Falls in einem generierten Place oder alten UI-Artefakt noch Auto-Enchant-Zielbuttons sichtbar sind, werden sie entfernt; es werden keine nicht vorhandenen Runtime-Schleifen erfunden.
4. Source-/Harness-Test beweist: ein Buttonklick erzeugt exakt einen ROLL-Invoke; stale Response löst höchstens GET_STATE, niemals automatischen zweiten ROLL aus.
5. Serverregression beweist unverändert einen RNG-Zug, 500 Diamonds, genau ein Pet, eine Slot-Ersetzung und kein Retry nach PONR.

## Abnahme

- Kein Auto-Enchant-Toggle, Zielselector, Scheduler oder Start-/Stop-Remote in Source oder Place.
- Jeder erfolgreiche Nutzerklick ist genau ein bezahlter Versuch; erneuter Versuch braucht erneuten Klick.
- Kosten und Wahrscheinlichkeiten sind byte-/wertgleich zur QOF-19-Baseline.

---

# QOF-36 – QOL-Gesamtabnahme und Release

- Alle QOF-28- und QOF-32–35-Artefakte/Commits/Evidenz vollständig.
- Studio-Matrix für Desktop, Mobile, Controller soweit unterstützt, echte Bewegung, Kamera, Latenz, zwei Spieler, Rejoin, DataStore, Leave und BindToClose.
- Migration mit alten Potion-, Hatch-Preference-, Pet-, Enchant- und Shopdaten.
- Performanceprofil für großes Pet-/Iteminventar und mehrere aktive Timer.
- Finaler reproduzierbarer Vier-Artefakt-Satz, CI, PR, Deployment-Handoff, Tag und Release erst nach Nutzerbestätigung.

## Backlog nach QOF-36

- Skill Tree als eigenes QOF; bis dahin bleiben bestehende Placeholder unangetastet.
- Vollständige LocalizationService-Anbindung und deutsche Texte.
- Weitere Zerlegung von `ZoneService.lua` außerhalb berührter Featuregrenzen.
