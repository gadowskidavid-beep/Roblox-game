# QOF-20 – Six-State Pet Dex

Status: **Code-verifiziert – Studio-Test ausstehend**

QOF-20 ersetzt die alte vierteilige Collection-Projektion durch einen serverautoritativen Dex für alle sechs kanonischen Varianten eines Pets. Enchants bleiben bewusst eine unabhängige Inventareigenschaft und sind keine Collection-Dimension.

## Produktvertrag

Jede der 16 Species besitzt genau diese sechs Dex-Zustände:

1. Normal
2. Normal Shiny
3. Gold
4. Gold Shiny
5. Rainbow
6. Rainbow Shiny

Damit zeigt der Dex **96 Karten**. Der kanonische Schlüssel besteht aus Species, Basisvariante und optionalem Shiny-Marker:

- `Buddy|Normal`
- `Buddy|Normal|Shiny`
- `Buddy|Golden`
- `Buddy|Golden|Shiny`
- `Buddy|Rainbow`
- `Buddy|Rainbow|Shiny`

`PetDex` ist die gemeinsame pure Source of Truth für Reihenfolge, Schlüssel, Validierung, Migration und bestätigte Client-Projektion.

## Persistenz und Migration

`DataSchema.VERSION = 11`. `discoveredPets` bleibt eine persistierte Boolean-Map, enthält aber nur bekannte kanonische oder bekannte Legacy-Schlüssel.

Die vier Legacy-Formen bleiben während des Rolling-/Rollbackfensters additive Mirrors:

- `Buddy`
- `Golden_Buddy`
- `Rainbow_Buddy`
- `Shiny_Buddy`

Normal, Gold und Rainbow lassen sich eindeutig migrieren. Der historische `Shiny_Buddy` enthält keine Basisvariante. Ohne einen bereits vorhandenen exakten V11-Schlüssel wird er konservativ genau auf `Buddy|Normal|Shiny` abgebildet; Gold Shiny und Rainbow Shiny werden nicht geschenkt. Besitzt das Profil das Pet noch, backfillt V11 dessen exakten Zustand aus dem kanonischen Inventar.

Canonical Keys überleben einen zwischenzeitlichen QOF-19/V10-Save, weil V10 unbekannte wahre String-Keys bewahrt. V11 schreibt weiterhin Legacy-Mirrors, damit alte Server und Clients sichtbar bleiben. Eine gelöschte oder verbrauchte historische Gold-/Rainbow-Shiny-Entdeckung ist aus `Shiny_Buddy` allein prinzipiell nicht rekonstruierbar.

## Autoritative Mutation

Hatch und Machine verwenden denselben `PetDex.getWriteKeys`-Vertrag innerhalb ihrer vorhandenen Inventory-Leases und Prepare/Commit/Rollback-Grenzen:

- `isNewDiscovery` entscheidet ausschließlich der kanonische Sechs-State-Key.
- Canonical und Legacy-Mirror werden gemeinsam geschrieben.
- Batch-Hatches deduplizieren denselben kanonischen Zustand.
- Machine-Misserfolge schreiben keine Discovery.
- Technische Rollbacks entfernen nur unveränderte, von der Transaktion geschriebene Keys.
- Machine-Outputs bleiben wie in QOF-19 ausdrücklich ungeenchanted.

Der interne Legacy-Golden-Pfad schreibt denselben dualen Vertrag. Enchant-Rolls verändern den Dex nicht.

## Client und UI

Der Index iteriert `PetDex.getStates()` statt `PetData.Variants`, rendert 96 kombinierte Karten und verwendet `PetVariantPresentation` für korrekte Labels. Bestätigte Hatch- und Machine-Resultate aktualisieren den offenen Index sofort.

`GetDiscoveredPets` behält seine alte Map-Form, liefert aber eine defensive Kopie. Rate-Limit oder fehlendes Profil liefern `nil` statt einer scheinbar autoritativen leeren Map. Jede bestätigte Live-Discovery erhöht zusätzlich die Refresh-Generation, sodass eine bereits vorher gestartete Serverantwort den neueren Hatch-/Machine-Fortschritt nicht zurücksetzen kann. Der Client:

- ruft den Remote geschützt auf;
- projiziert nur bekannte Schlüssel;
- verwirft fehlgeschlagene, geschlossene und stale Generationen;
- leert lokalen Fortschritt niemals aufgrund eines Transportfehlers.

## Automatisierte Abnahme

- `PetDex.spec.lua`: sechs Zustände, 96 Karten, exakte Keys, defensive Kopien, konservative Legacy-Migration und hostile Grenzen.
- `DataSchema.spec.lua`: V10→V11, Starter-Backfill, exakte Inventory-Rekonstruktion, Rolling-V10-Idempotenz und Clone-Unabhängigkeit.
- `PetService.spec.lua`: sechs Hatch-Ergebnisse, duale Writes, Batch-Dedupe und Rollback.
- `MachineService.spec.lua`: getrennte Gold-Shiny-/Rainbow-Shiny-Entdeckung und Multi-Key-Rollback.
- `PetDexClient.spec.lua`: kombinierte UI, Live-Updates, stale Refresh und defensive Remote-Grenze.

## Manueller Studio-Test

1. Neues Profil laden und den Dex öffnen: `Buddy / Normal` ist entdeckt; Fortschritt startet bei 1/96.
2. Je einen normalen, Shiny-, Gold-, Gold-Shiny-, Rainbow- und Rainbow-Shiny-Zustand erzeugen: genau die jeweilige Karte wird sichtbar.
3. Dex während Hatch/Machine offen lassen: bestätigte Resultate erscheinen ohne Schließen/Neuöffnen.
4. Gold Shiny und Rainbow Shiny derselben Species erzeugen: beide Karten bleiben getrennt.
5. Rejoin durchführen: Fortschritt bleibt erhalten.
6. Mit einem alten Save mit `Shiny_<Pet>` laden: nur Normal Shiny wird konservativ übernommen, sofern kein exakter kombinierter Key vorhanden ist.
7. Desktop und Mobile prüfen: 96 Karten scrollen flüssig und Labels bleiben lesbar.

Roblox-Studio-Rendering, echte DataStore-Migration und Mehrclient-/Latenzverhalten bleiben bis zur manuellen Bestätigung offen.
