# QOF-04 – Kanonischer Varianten- und Shiny-Schaden

**Status:** Code-verifiziert – Studio-Test ausstehend
**Testbuild:** `BATTLE_PETS_QOF-04_TEST.rbxl`
**Schema:** V6 bleibt bestehen

## Ziel

QOF-04 aktiviert ausschließlich das kanonische Pet-Schadensmodell. Kampfwerte werden nicht mehr aus dem gespeicherten Feld `pet.damage` abgeleitet, sondern serverseitig aus der Pet-Identität berechnet:

```text
PetData.Pets[petId].baseDamage
× BalanceConfig.Variants.Base[variant].damageMultiplier
× (shiny and BalanceConfig.Variants.Shiny.damageMultiplier or 1)
```

`pet.damage` bleibt vorübergehend als serverseitig neu berechneter Anzeige-/DTO-Spiegel erhalten, damit bestehende Inventar-, Sortier- und Hatch-UIs kompatibel bleiben. Manipulierte oder alte Spiegelwerte beeinflussen den Kampf nicht.

## Aktive Multiplikatoren

| Basisvariante | Ohne Shiny | Mit Shiny |
|---|---:|---:|
| Normal | x1 | x1,5 |
| Golden | x2 | x3 |
| Rainbow | x5 | x7,5 |

Bruchteile bleiben erhalten. Beispiel: Splash hat Basisschaden 3; Normal Shiny verursacht 4,5 und Rainbow Shiny 22,5 Basisschaden.

Bestehende Strong-Pets- und Shop-Schadensmultiplikatoren werden anschließend wie bisher jeweils einmal angewendet. Es gibt keine doppelte Variantenmultiplikation.

## Laufzeitpfade

- `PetVariantMath` ist die gemeinsame Source of Truth für Normal, Golden, Rainbow und Shiny.
- `DataSchema` ersetzt beim Laden und Speichern jeden alten/manipulierten `pet.damage`-Wert durch den kanonischen Spiegel.
- Starterpet, Hatch-Ergebnisse und Golden-Konvertierung schreiben denselben kanonischen Spiegel.
- Overworld- und Campaign-Kampf verwenden `PetService.getPetDamage` und ignorieren den gespeicherten Spiegel als Autorität.
- Unbekannte `petId` werden nicht gelöscht, erhalten aber sicherheitshalber 0 Schaden.
- Nur `BalanceConfig.Variants.RuntimeEnabled` ist aktiviert.

## Bewusst noch unverändert

- Hatch bleibt ein einzelnes Ei mit den bisherigen exklusiven Legacy-Rolls und Luck-Quellen.
- Die Zielchancen Gold 1 %, Rainbow 0,1 % und Shiny 0,01 % sind weiterhin deaktiviert.
- Multi-Open, Maschinen, Potions, Enchanting, kombinierter Pet Dex und neue permanente Varianten-Effekte folgen in späteren QOFs.
- Golden-Konvertierung behält 1–7 Inputs, 13/26/39/50/63/88/100 %, keine Kosten und Consume-on-Failure.
- Alte Discovery-Keys und die aktuelle Vier-Kategorien-UI bleiben erhalten.
- Remotes, `upgradeTree.lua` und Vide bleiben unverändert.

## Verbindliche Produktions-Rollout-Regel

QOF-03-Server vertrauen noch dem gespeicherten Schadensspiegel und runden Bruchteile ab. Ein Normal-Shiny-Buddy könnte deshalb während eines gemischten QOF-03/QOF-04-Rollouts je nach Server unterschiedliche Werte verwenden.

**Vor einer QOF-04-Produktionseinführung müssen alle QOF-03- und älteren Server vollständig über Roblox „Shut Down All Servers“ geschlossen werden. Erst danach darf QOF-04 veröffentlicht werden. Ein gemischter Produktionsbetrieb ist nicht freigegeben.**

Der isolierte Studio-Testbuild beziehungsweise eine getrennte Test-Experience ist davon nicht betroffen. Falls ein alter Server einen Spiegel zwischenzeitlich abgerundet hat, stellt QOF-04 beim nächsten Laden den kanonischen Wert wieder her.

## Verifikation

- Luau-Compile für alle geänderten Dateien
- 52/52 Balance-, Schema-, Varianten- und PetService-Tests
- alle sechs Varianten-/Shiny-Kombinationen
- manipulierte Spiegelwerte beeinflussen Kampf nicht
- Strong-Pets-/Shop-Buffs wirken jeweils einmal
- Legacy-Shiny-Hatch erzeugt nun x1,5 statt x3
- Golden-Konvertierung erzeugt x2 und schützt Shiny
- QOF-03-Floor/Save wird beim QOF-04-Laden repariert
- generierte Source-Parität: 59 ModuleScripts, 1 Script, 1 LocalScript
- `upgradeTree.lua` und Vide unverändert

Roblox-Studio-Laufzeittests bleiben bis zum Nutzerfeedback ausstehend. Das nächste QOF beginnt erst nach `Weiter`.
