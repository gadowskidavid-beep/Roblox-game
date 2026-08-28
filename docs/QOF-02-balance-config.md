# QOF-02 – Zentrale Balance-Konfiguration

**Status:** Code-verifiziert – Studio-Test ausstehend
**Source of truth:** `src/ReplicatedStorage/Shared/BalanceConfig.lua`
**Testbuild:** `BATTLE_PETS_QOF-02_TEST.rbxl`

## Ziel

QOF-02 zentralisiert bestehende und bereits freigegebene zukünftige Balancewerte. Es aktiviert bewusst noch keine neuen Gameplay-, UI-, Daten- oder Weltfeatures. Das aktuelle Spielverhalten und die Optik des Upgrade Trees bleiben unverändert.

## Aktive Kompatibilitätswerte

Folgende aktuelle Systeme lesen nun aus `BalanceConfig`, ohne ihre öffentlichen Datenformen zu ändern:

- Inventar-, Equip-, Auto-Hatch- und Replikationslimits über `Config.lua`
- Rarity-Gewichte, acht Egg-/Zone-Preise und Campaign-Werte über `Config.lua`
- aktuelle exklusive Shiny-/Rainbow-Hatch-Chancen über `Legacy.Hatch`
- sechs aktuelle Shop-Angebote über `Legacy.Shop`
- bestehende Golden-Konvertierung (1–7 Inputs, 13/26/39/50/63/88/100 %) über `Legacy.GoldenConversion`
- alle 56 bestehenden Upgrade-Tree-Requirements über stabile Node-IDs

Die Golden-Konvertierung verwendet absichtlich den aktiven Legacy-Vertrag und nicht die deaktivierte zukünftige Maschinenkonfiguration.

## Freigegebene, aber noch deaktivierte Zielwerte

Diese Bereiche besitzen jeweils `RuntimeEnabled = false` und werden erst in ihrem späteren QOF serverautoritativ aktiviert:

- Basisvarianten Normal x1, Gold x2, Rainbow x5 sowie unabhängiges Shiny x1,5
- direkte Hatch-Chancen: Gold 1 %, Rainbow 0,1 %, Shiny 0,01 %
- Egg Quality und Multi-Open 2/5/10
- physische Gold-/Rainbow-Maschinen in Zone 3/6 für 750/2.500 Diamonds
- Speed, Storage, Magnet, Double Luck und Equip Slots
- Potion-Katalog inklusive x10 Shiny-Chance für drei Hatches
- Potion Slots, Duration+ und Auto-Drink
- Enchanting

Mythic, Fusion Potions, Pet-Leveling, Cosmetics und Prestige sind nicht enthalten.

## Validierung und Regression

`BalanceConfig.Validate()` läuft beim Require und prüft unter anderem:

- alle QOF-02 Runtime-Gates bleiben deaktiviert
- Limits, Rarity-Summe, acht Zonen und Campaign-Werte
- Chancen, Multiplikatoren, Kostenkurven und Maschinenkurven
- Potion-/Enchanting-Daten
- aktive Legacy-Hatch-, Shop- und Golden-Werte
- exakt 56 Upgrade-Tree-Nodes

Verifizierte Befehle:

```text
luau-compile <alle geänderten Luau-Dateien>
lua tests/run_tests.lua
python3 tools/generate_rbxlx.py
python3 tests/verify_generated_place.py
python3 -m py_compile tools/generate_rbxlx.py
git diff --check
```

Die Suite enthält 30 bestandene Tests. Zusätzlich wird geprüft, dass `BalanceConfig`, `Config`, `ShopData`, `upgradeTreeData` und `PetService` jeweils genau einmal und source-identisch in `BATTLE_PETS.rbxlx` eingebettet sind.

## Studio-Abnahmekriterien

1. Place öffnet ohne Parse-/Load-Fehler.
2. Play startet ohne rote Output-Fehler zu `BalanceConfig` oder `require`.
3. Upgrade Tree sieht aus und navigiert wie vor QOF-02; Preise sind unverändert.
4. Shop zeigt dieselben sechs Angebote, Preise, Laufzeiten und Effekte.
5. Normales Hatching funktioniert wie bisher; neue Zielchancen/Multi-Open sind noch nicht sichtbar.
6. Golden-Konvertierung akzeptiert 1–7 normale, gleiche, nicht favorisierte und nicht ausgerüstete Pets; Chancen und Verbrauchsverhalten sind unverändert.
7. Bestehende Saves laden ohne Migration oder Datenverlust.
8. PC und Mobile zeigen keine neue UI- oder Performance-Regression.

QOF-03 beginnt erst nach Studio-Feedback und der ausdrücklichen Nachricht `Weiter`.
