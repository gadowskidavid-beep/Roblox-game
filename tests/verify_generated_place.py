#!/usr/bin/env python3
"""Verify that a generated Battle Pets place embeds every QOF-18 runtime source."""

from collections import Counter
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PLACE = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / "BATTLE_PETS.rbxlx"
EXPECTED_SOURCES = {
    "BalanceConfig": "src/ReplicatedStorage/Shared/BalanceConfig.lua",
    "Config": "src/ReplicatedStorage/Shared/Config.lua",
    "ShopData": "src/ReplicatedStorage/Shared/ShopData.lua",
    "upgradeTreeData": "src/ReplicatedStorage/modules/upgradeTree/upgradeTreeData.lua",
    "upgradeTreeSettings": "src/ReplicatedStorage/modules/upgradeTree/upgradeTreeSettings.lua",
    "PetHatchMath": "src/ReplicatedStorage/Shared/PetHatchMath.lua",
    "PetVariantMath": "src/ReplicatedStorage/Shared/PetVariantMath.lua",
    "PetVariantPresentation": "src/ReplicatedStorage/Shared/PetVariantPresentation.lua",
    "HatchCinematicPolicy": "src/ReplicatedStorage/Shared/HatchCinematicPolicy.lua",
    "AutoHatchClientSession": "src/ReplicatedStorage/Shared/AutoHatchClientSession.lua",
    "PetService": "src/ServerScriptService/Services/PetService.lua",
    "MachineService": "src/ServerScriptService/Services/MachineService.lua",
    "CurrencyService": "src/ServerScriptService/Services/CurrencyService.lua",
    "EggService": "src/ServerScriptService/Services/EggService.lua",
    "AutoHatchService": "src/ServerScriptService/Services/AutoHatchService.lua",
    "ShopService": "src/ServerScriptService/Services/ShopService.lua",
    "PotionService": "src/ServerScriptService/Services/PotionService.lua",
    "UpgradeTreeService": "src/ServerScriptService/Services/UpgradeTreeService.lua",
    "MovementService": "src/ServerScriptService/Services/MovementService.lua",
    "PickupService": "src/ServerScriptService/Services/PickupService.lua",
    "DataSchema": "src/ServerScriptService/Services/DataSchema.lua",
    "DataService": "src/ServerScriptService/Services/DataService.lua",
    "UIController": "src/StarterPlayer/StarterPlayerScripts/UIController.lua",
    "EffectsController": "src/StarterPlayer/StarterPlayerScripts/EffectsController.lua",
    "PetController": "src/StarterPlayer/StarterPlayerScripts/PetController.lua",
    "UpgradeTreeController": "src/StarterPlayer/StarterPlayerScripts/UpgradeTreeController.lua",
}
EXPECTED_SCRIPT_COUNTS = {"ModuleScript": 70, "Script": 1, "LocalScript": 1}
EXPECTED_DUPLICATE_NAME_SOURCES = {
    "Main": [
        "src/ServerScriptService/Main.server.lua",
        "src/StarterPlayer/StarterPlayerScripts/Main.client.lua",
    ],
}


def all_expected_runtime_paths() -> list[Path]:
    """Mirror the generator's runtime source surfaces and exclude tests/tools."""
    paths = [
        *sorted((ROOT / "src/ReplicatedStorage/Shared").glob("*.lua")),
        *sorted((ROOT / "src/ReplicatedStorage/packages/vide").glob("*.lua")),
        ROOT / "src/ReplicatedStorage/modules/formatNumber.lua",
        *sorted((ROOT / "src/ReplicatedStorage/modules/upgradeTree").glob("*.lua")),
        ROOT / "src/ServerScriptService/Main.server.lua",
        *sorted((ROOT / "src/ServerScriptService/Services").glob("*.lua")),
        ROOT / "src/StarterPlayer/StarterPlayerScripts/Main.client.lua",
        *sorted((ROOT / "src/StarterPlayer/StarterPlayerScripts").glob("*Controller.lua")),
    ]
    assert len(paths) == EXPECTED_SCRIPT_COUNTS["ModuleScript"] + 2, (
        f"expected {EXPECTED_SCRIPT_COUNTS['ModuleScript'] + 2} runtime source paths, found {len(paths)}"
    )
    return paths


def serialized_source_bytes(source: str) -> bytes:
    """Recover exact Source bytes from XML or rbxmk's binary-string projection."""
    try:
        # rbxmk 0.9.1 projects RBXL ProtectedString bytes as Latin-1 code points
        # when writing an XML roundtrip. Re-encoding restores the original bytes.
        return source.encode("latin-1")
    except UnicodeEncodeError:
        return source.encode("utf-8")


def main() -> None:
    main_source = (ROOT / "src/ServerScriptService/Main.server.lua").read_bytes()
    assert b"applyWalkSpeedBuffs" not in main_source, (
        "deleted legacy WalkSpeed helper is still referenced by the server entry point"
    )
    for required in (
        b"MovementService.bindPlayer(player)",
        b"PickupService.onPlayerRemoving(player)",
        b"DataService.bindToClose(function()",
        b"AutoHatchService.prepareForShutdown()",
        b"return PickupService.settleAllPlayers()",
        b"request.contractVersion == 2",
        b"ShopService.onPlayerRemoving(player)",
        b"PotionService.onPlayerAdded(player)",
        b'getRemoteFunction("ConsumePotion")',
        b'getRemoteFunction("PurchasePotionUpgrade")',
        b'getRemoteFunction("SetAutoDrinkSelection")',
        b"MachineService.init(DataService, CurrencyService, PetService)",
        b"MachineService.setQuestService(QuestService)",
        b"MachineService.cleanup(player)",
        b'getRemoteFunction("UseMachine")',
        b"MachineAuthorityBootstrap.install",
    ):
        assert required in main_source, f"missing server lifecycle or purchase wiring: {required!r}"
    assert b'"ConvertToGoldenPet",' in main_source, (
        "rolling clients would block without the fail-closed compatibility remote"
    )
    assert b'getRemoteFunction("ConvertToGoldenPet").OnServerInvoke' in main_source
    assert b"Legacy conversion unavailable" in main_source
    assert b"PetService.convertToGoldenPet(player, petInstanceIds)" not in main_source, (
        "legacy free conversion remains publicly routed"
    )

    balance_source = (
        ROOT / "src/ReplicatedStorage/Shared/BalanceConfig.lua"
    ).read_bytes()
    assert b"Machines = {\n\t\t-- QOF-17" in balance_source
    assert b"Gold = {\n\t\t\tRuntimeEnabled = true," in balance_source, (
        "QOF-17 Gold machine gate is not active"
    )
    assert b"Rainbow = {\n\t\t\tRuntimeEnabled = true," in balance_source, (
        "QOF-17 Rainbow machine gate is not active"
    )

    machine_service_source = (
        ROOT / "src/ServerScriptService/Services/MachineService.lua"
    ).read_bytes()
    for required in (
        b"function MachineService.init",
        b"function MachineService.setQuestService",
        b"function MachineService.setActivationValidator",
        b"function MachineService.attemptConversion",
        b"function MachineService.cleanup",
        b"beginSpendTransaction",
        b"commitSpendTransaction",
        b"rollbackSpendTransaction",
        b"prepareVariantConversion",
        b"commitVariantConversion",
        b"rollbackVariantConversion",
        b'"goldenPetsConverted"',
    ):
        assert required in machine_service_source, f"missing QOF-17 machine authority: {required!r}"

    zone_service_source = (
        ROOT / "src/ServerScriptService/Services/ZoneService.lua"
    ).read_bytes()
    for required in (
        b"local function spawnMachineStation",
        b"validateMachineActivation",
        b'prompt.Name = "UseMachinePrompt"',
        b'identityToken = HttpService:GenerateGUID(false)',
        b"MACHINE_MAX_DISTANCE",
        b"hasConflictingStationIdentity",
        b"anchor.Shape ~= record.anchorShape",
        b"anchor.Color ~= record.anchorColor",
        b"anchor.Material ~= record.anchorMaterial",
        b'spawnMachineStation(zonesFolder, "Gold")',
        b'spawnMachineStation(zonesFolder, "Rainbow")',
    ):
        assert required in zone_service_source, f"missing QOF-17 world authority: {required!r}"
    assert b"spawnRainbowMachineStation" not in zone_service_source

    client_source = (
        ROOT / "src/StarterPlayer/StarterPlayerScripts/Main.client.lua"
    ).read_bytes()
    for required in (
        b'WaitForChild("UseMachine")',
        b"getMachinePromptData",
        b"GoldMachine = true",
        b"RainbowMachine = true",
        b"UseMachine:InvokeServer(machineId, identityToken, selectedIds)",
        b"MachineClientSession.finishRequest(machineSession, operation)",
        b"prompt == machineSession.prompt",
        b"uiController:openMachineSelection(machineId)",
    ):
        assert required in client_source, f"missing QOF-17 client prompt routing: {required!r}"
    assert b'WaitForChild("ConvertToGoldenPet")' not in client_source

    purchase_handler = main_source.split(
        b'getRemoteFunction("PurchaseShopItem").OnServerInvoke', 1
    )[1].split(b"-- GetShopBuffs", 1)[0]
    assert b"isValidShopPurchaseRequest(request)" in purchase_handler
    assert b"MovementService.refresh" not in purchase_handler, (
        "inventory-only potion purchases must not refresh movement effects"
    )

    shop_service_source = (
        ROOT / "src/ServerScriptService/Services/ShopService.lua"
    ).read_bytes()
    for required in (
        b'local PURCHASE_MODE = "inventoryOnly"',
        b"_purchaseLocks",
        b"beginSpendTransaction",
        b"rollbackSpendTransaction",
        b"commitSpendTransaction",
        b"data.potionInventory[itemId] = count + POTION_QUANTITY",
    ):
        assert required in shop_service_source, f"missing QOF-13 shop authority: {required!r}"

    potion_service_source = (
        ROOT / "src/ServerScriptService/Services/PotionService.lua"
    ).read_bytes()
    for required in (
        b'local CONTRACT_VERSION = 1',
        b'os.time()',
        b'beginShinyChargeTransaction',
        b'processAutoDrink',
        b'purchaseUpgrade',
        b'setAutoDrinkSelection',
        b'stateRevision',
        b'notifyInventoryChanged',
    ):
        assert required in potion_service_source, f"missing QOF-14 potion authority: {required!r}"

    shop_data_source = (ROOT / "src/ReplicatedStorage/Shared/ShopData.lua").read_bytes()
    assert b'"LuckPotion"' in shop_data_source and b'"ShinyPotion"' in shop_data_source
    assert b"LuckyPotion =" not in shop_data_source and b"PowerPotion =" not in shop_data_source

    ui_source = (
        ROOT / "src/StarterPlayer/StarterPlayerScripts/UIController.lua"
    ).read_bytes()
    for required in (
        b"contractVersion = ShopData.ContractVersion",
        b"purchaseMode == ShopData.PurchaseMode",
        b'card.status.Text = "OWNED "',
        b'PotionContractVersion',
        b'revision < self._potionStateRevision',
        b'drinkBtn.Name = "DrinkBtn"',
        b'consumeAvailability = type(payload.consumeAvailability) == "table"',
        b'availability.reason == "Maximum timed duration reached (30 days)"',
        b'autoBtn.Name = "AutoDrinkBtn"',
        b'_purchasePotionUpgrade',
    ):
        assert required in ui_source, f"missing QOF-13 inventory UI contract: {required!r}"
    for required in (
        b'machineBtn.Name = "UseMachineBtn"',
        b"self._multiSelectMode and self._machineSessionActive",
        b"presentation.baseVariant == machineInputVariant",
        b"PetVariantPresentation.resolve(petData).baseVariant == machineInputVariant",
        b"presentation.baseVariant ~= definition.inputVariant",
        b"BalanceConfig.Machines.SuccessChanceByInput[count]",
        b"tostring(definition.cost.amount)",
        b'outputLabel = "Golden"',
        b'outputLabel = "Rainbow"',
        b"Diamonds are consumed even on failure",
        b"result.outputPet",
        b"self:_requestMachineCancel()",
        b"self._machineOverlay ~= completedOverlay",
    ):
        assert required in ui_source, f"missing QOF-17 machine UI contract: {required!r}"
    assert b'FindFirstChild("UseRainbowMachineBtn")' not in ui_source
    assert b'FindFirstChild("MakeGoldenBtn")' not in ui_source
    assert b'FindFirstChild("ConvertToGoldenPet")' not in ui_source

    # QOF-18 paid Auto-Hatch is a separate strict service; legacy ShopService
    # compatibility symbols remain discoverable but can never schedule work.
    auto_hatch_source = (
        ROOT / "src/ServerScriptService/Services/AutoHatchService.lua"
    ).read_bytes()
    for required in (
        b'local CONTRACT_VERSION = 1',
        b'DEFINITION.cost.currency',
        b'DEFINITION.cost.amount',
        b'DEFINITION.durationSeconds',
        b'DEFINITION.intervalSeconds',
        b'beginSpendTransaction',
        b'commitSpendTransaction',
        b'rollbackSpendTransaction',
        b'REJOIN_REQUIRES_STATION',
        b'BATCH_NOT_ENTITLED',
        b'consumeShinyCharges = false',
        b'function AutoHatchService._processTick',
        b'if session.inFlight or now < session.nextHatchAt then return end',
        b'function AutoHatchService.onPlayerRemoving',
        b'function AutoHatchService.prepareForShutdown',
        b'or value % 1 ~= 0',
        b'local function dependenciesReady()',
        b'local function runtimeAvailable()',
        b'RUNTIME_UNAVAILABLE',
        b'AutoHatchService._schedulerSpawn',
        b'AutoHatchService._actionFeedback[userId] = {',
        b'local function disableRuntimeAfterSchedulerFailure()',
        b'fireStateUpdated(player, state)',
    ):
        assert required in auto_hatch_source, f"missing QOF-18 service contract: {required!r}"

    data_schema_source = (
        ROOT / "src/ServerScriptService/Services/DataSchema.lua"
    ).read_bytes()
    assert b'DataSchema.VERSION = 9' in data_schema_source
    assert b'autoHatchExpiresAt = 0' in data_schema_source
    assert b'normalizeAutoHatchExpiry' in data_schema_source
    assert b'or value % 1 ~= 0' in data_schema_source

    for required in (
        b'local eggStationRegistry = {}',
        b'EggStationIdentityToken',
        b'validateEggRecordIntegrity',
        b'hasConflictingEggStationIdentity',
        b'validateSelection = function',
        b'requireProximity == true',
        b'return validateMachineActivation, buildEggAuthority()',
        b'pedestal.Color ~= record.pedestalColor',
        b'pedestal.Material ~= record.pedestalMaterial',
        b'interactZone.Shape ~= record.interactZoneShape',
        b'interactZone.Color ~= record.interactZoneColor',
        b'interactZone.Material ~= record.interactZoneMaterial',
    ):
        assert required in zone_service_source, f"missing QOF-18 egg authority: {required!r}"

    for required in (
        b'"AutoHatchStateUpdated"',
        b'"PurchaseAutoHatch"',
        b'"GetAutoHatchState"',
        b'"SetAutoHatchBatch"',
        b'"StartAutoHatch"',
        b'"StopAutoHatch"',
        b'AutoHatchService.onPlayerRemoving(player)',
        b'AutoHatchService.onPlayerAdded(player)',
        b'AutoHatchService.prepareForShutdown()',
        b'AutoHatchService.rejectStart(player, request, "RATE_LIMITED")',
        b'Legacy Auto-Hatch contract unavailable',
    ):
        assert required in main_source, f"missing QOF-18 server wiring: {required!r}"
    assert main_source.count(b"AutoHatchService.onPlayerAdded(player)") == 2, (
        "normal and already-connected player paths must both reconcile Auto-Hatch"
    )
    existing_player_bootstrap = main_source.split(
        b"-- Handle players who joined before script loaded", 1
    )[1].split(b"-- Helper: update leaderstats", 1)[0]
    bootstrap_load = existing_player_bootstrap.index(b"DataService.loadPlayerData(player)")
    bootstrap_potion = existing_player_bootstrap.index(b"PotionService.onPlayerAdded(player)")
    bootstrap_auto_hatch = existing_player_bootstrap.index(b"AutoHatchService.onPlayerAdded(player)")
    bootstrap_movement = existing_player_bootstrap.index(b"MovementService.bindPlayer(player)")
    assert bootstrap_load < bootstrap_potion < bootstrap_auto_hatch < bootstrap_movement, (
        "already-connected players must use profile -> potion -> Auto-Hatch -> movement order"
    )
    assert main_source.index(b"AutoHatchService.init(") < main_source.index(
        b"AutoHatchService.start()"
    ), "Auto-Hatch dependencies must be installed before scheduler startup"
    assert main_source.index(b'AutoHatchService.onPlayerRemoving(player)') < main_source.index(
        b'EggService.onPlayerRemoving(player)'
    ), "Auto-Hatch must invalidate before EggService cleanup"

    egg_service_source = (
        ROOT / "src/ServerScriptService/Services/EggService.lua"
    ).read_bytes()
    assert b'local function defaultStationValidator' not in egg_service_source
    assert b'return defaultStationValidator(player, eggType)' not in egg_service_source
    assert b'partial world bootstrap must never fall back' in egg_service_source

    assert b'function ShopService._processAutoHatch()\n\treturn false' in shop_service_source
    assert b'local highestZone' not in shop_service_source
    assert b'task.wait(Config.AutoHatchInterval' not in shop_service_source

    for required in (
        b'FindFirstChild("PurchaseAutoHatch")',
        b'FindFirstChild("AutoHatchStateUpdated")',
        b'GetAttribute("EggStationId")',
        b'GetAttribute("EggStationIdentityToken")',
        b'AutoHatchClientSession.finishRequest',
        b'Direct A-to-B prompt switches revoke both request and busy UI ownership.',
        b'Cancel/navigation owns the same invalidation boundary as PromptHidden:',
        b're-triggering must reinstall it before controls reopen.',
        b'if autoHatchSession.prompt ~= prompt then',
        b'autoHatchGlobalToken += 1',
        b'local applied = applyAutoHatchState(state)',
        b'Valid semantic failures carry revisioned authoritative actionFeedback',
        b'uiController:clearAutoHatchLocalStation()',
        b'not uiController:isAutoHatchRuntimeEnabled()',
    ):
        assert required in client_source, f"missing QOF-18 rolling client contract: {required!r}"
    assert b'WaitForChild("PurchaseAutoHatch")' not in client_source
    assert b'WaitForChild("AutoHatchStateUpdated")' not in client_source
    for required in (
        b'autoPanel.Name = "AutoHatchControls"',
        b'AUTO_HATCH_REASON_TEXT',
        b'revision <= self._autoHatchStateRevision',
        b'generation ~= self._autoHatchUiGeneration',
        b'autoRuntimeUnavailable',
        b'card.button.Text = "UNAVAILABLE"',
        b'function UIController:isAutoHatchRuntimeEnabled()',
        b'item.itemType == "autoHatch"',
        b'self._autoHatchUiGeneration += 1',
        b'actionFeedback = type(payload.actionFeedback) == "table"',
        b'actionFeedback.stationId == station.stationId',
        b'start.Active = runtimeEnabled and remaining > 0',
        b'RUNTIME_UNAVAILABLE = "Auto-Hatch is temporarily unavailable on this server."',
    ):
        assert required in ui_source, f"missing QOF-18 UI contract: {required!r}"

    root = ET.parse(PLACE).getroot()
    scripts: dict[str, list[str]] = {}
    counts: dict[str, int] = {}

    for item in root.findall(".//Item"):
        class_name = item.attrib.get("class", "")
        counts[class_name] = counts.get(class_name, 0) + 1
        properties = item.find("Properties")
        if properties is None:
            continue
        name = properties.find("./string[@name='Name']")
        source = properties.find("./ProtectedString[@name='Source']")
        if source is None:
            source = properties.find("./string[@name='Source']")
        if name is not None and source is not None:
            scripts.setdefault(name.text or "", []).append(source.text or "")

    for script_name, relative_path in EXPECTED_SOURCES.items():
        generated_sources = scripts.get(script_name, [])
        assert len(generated_sources) == 1, (
            f"expected exactly one {script_name}, found {len(generated_sources)}"
        )
        expected_source = (ROOT / relative_path).read_bytes()
        assert serialized_source_bytes(generated_sources[0]) == expected_source, (
            f"generated source bytes differ from {relative_path}"
        )

    for script_name, relative_paths in EXPECTED_DUPLICATE_NAME_SOURCES.items():
        generated_sources = scripts.get(script_name, [])
        assert len(generated_sources) == len(relative_paths), (
            f"expected {len(relative_paths)} {script_name} scripts, found {len(generated_sources)}"
        )
        for relative_path in relative_paths:
            expected_source = (ROOT / relative_path).read_bytes()
            assert sum(
                serialized_source_bytes(source) == expected_source
                for source in generated_sources
            ) == 1, (
                f"generated source differs from or duplicates {relative_path}"
            )

    expected_source_counts = Counter(
        path.read_bytes() for path in all_expected_runtime_paths()
    )
    generated_source_counts = Counter(
        serialized_source_bytes(source)
        for source_list in scripts.values()
        for source in source_list
    )
    assert generated_source_counts == expected_source_counts, (
        "generated place does not have byte-exact one-to-one runtime source parity"
    )

    actual_counts = {name: counts.get(name, 0) for name in EXPECTED_SCRIPT_COUNTS}
    assert actual_counts == EXPECTED_SCRIPT_COUNTS, (
        f"generated script counts changed: {actual_counts}"
    )
    print("PASS: generated place embeds every QOF-18 runtime source exactly once")
    print(f"PASS: all {EXPECTED_SCRIPT_COUNTS['ModuleScript'] + 2} generated script sources have byte-exact source parity")
    print(f"PASS: generated script counts are {actual_counts}")


if __name__ == "__main__":
    main()
