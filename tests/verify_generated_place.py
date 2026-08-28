#!/usr/bin/env python3
"""Verify that a generated Battle Pets place embeds every QOF-19 runtime source."""

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
    "PetEnchantMath": "src/ReplicatedStorage/Shared/PetEnchantMath.lua",
    "HatchCinematicPolicy": "src/ReplicatedStorage/Shared/HatchCinematicPolicy.lua",
    "AutoHatchClientSession": "src/ReplicatedStorage/Shared/AutoHatchClientSession.lua",
    "EnchantingClientSession": "src/ReplicatedStorage/Shared/EnchantingClientSession.lua",
    "EnchantingClientContract": "src/ReplicatedStorage/Shared/EnchantingClientContract.lua",
    "PetService": "src/ServerScriptService/Services/PetService.lua",
    "MachineService": "src/ServerScriptService/Services/MachineService.lua",
    "EnchantingService": "src/ServerScriptService/Services/EnchantingService.lua",
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
EXPECTED_SCRIPT_COUNTS = {"ModuleScript": 74, "Script": 1, "LocalScript": 1}
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
        b"PickupService.settlePlayer(player)",
        b"DataService.bindToClose({",
        b"AutoHatchService.prepareForShutdown()",
        b"EggService.beginShutdown()",
        b"MachineService.beginShutdown()",
        b"EnchantingService.beginShutdown()",
        b"EggService.cleanup(player)",
        b"MachineService.cleanup(player)",
        b"EnchantingService.cleanup(player)",
        b"PickupService.settlePlayer(player)",
        b"request.contractVersion == 2",
        b"ShopService.onPlayerRemoving(player)",
        b"PotionService.onPlayerAdded(player)",
        b'getRemoteFunction("ConsumePotion")',
        b'getRemoteFunction("PurchasePotionUpgrade")',
        b'getRemoteFunction("SetAutoDrinkSelection")',
        b"MachineService.init(DataService, CurrencyService, PetService)",
        b"MachineService.setQuestService(QuestService)",
        b"MachineService.onPlayerRemoving(player)",
        b"EnchantingService.init(DataService, CurrencyService, PetService)",
        b"EnchantingService.onPlayerRemoving(player)",
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
        b"function MachineService.prepareForShutdown",
        b"MachineService.onPlayerRemoving = MachineService.cleanup",
        b"MachineService._activeTransactions",
        b"MachineService._shuttingDown",
        b"restoreTransaction",
        b"beginInventoryMutation",
        b"endInventoryMutation",
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
        b"Input pets and their enchants are always consumed.",
        b"Diamonds are also spent on a normal failure.",
        b"A successful output starts with no enchant.",
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
    assert b'DataSchema.VERSION = 10' in data_schema_source
    assert b'autoHatchExpiresAt = 0' in data_schema_source
    assert b'normalizeAutoHatchExpiry' in data_schema_source
    assert b'or value % 1 ~= 0' in data_schema_source

    data_service_source = (
        ROOT / "src/ServerScriptService/Services/DataService.lua"
    ).read_bytes()
    for required in (
        b"DataService._profilePlayers",
        b"DataService._pendingProfiles",
        b"DataService._mutationAdmissionClosed",
        b"DataService._clock = os.clock",
        b"function DataService.closeMutationAdmission(player)",
        b"function DataService.isMutationAdmissionOpen(player)",
        b"function DataService.processPendingProfile",
        b"function DataService.onPlayerRemoving(player, settleCallback)",
        b"owner ~= nil and owner ~= player",
        b"for userId in pairs(DataService._cache) do",
        b"pendingWorkers = pendingWorkers + 1",
        b"while DataService._clock() < deadline",
        b"DataService._shutdownMaxPasses == nil",
        b"DataService.savePlayerData(record.player, true)",
    ):
        assert required in data_service_source, f"missing isolated retrying profile lifecycle: {required!r}"

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
    for required in (
        b"EggService._activeTransactions",
        b"EggService._shuttingDown",
        b'beginInventoryMutation(player, "EggService")',
        b"transaction.inventoryLease",
        b"local function settleTransaction(transaction)",
        b"function EggService.cleanup",
        b"function EggService.beginShutdown",
        b"function EggService.prepareForShutdown",
    ):
        assert required in egg_service_source, f"missing lease-held hatch lifecycle: {required!r}"

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

    # QOF-19 activates one inventory-native enchanting contract while preserving
    # every QOF-17/18 regression above.
    enchanting_balance = balance_source.split(b"\n\tEnchanting = {", 1)[1].split(
        b"\n\t-- Values below", 1
    )[0]
    for required in (
        b"RuntimeEnabled = true",
        b'RollCost = { currency = "diamonds", amount = 500 }',
        b"MaxSlotsPerPet = 1",
        b'{ id = "StrongI", weight = 35, stat = "damage", multiplier = 1.10 }',
        b'{ id = "StrongII", weight = 15, stat = "damage", multiplier = 1.25 }',
        b'{ id = "StrongIII", weight = 5, stat = "damage", multiplier = 1.50 }',
        b'{ id = "AgileI", weight = 30, stat = "speed", multiplier = 1.10 }',
        b'{ id = "AgileII", weight = 12, stat = "speed", multiplier = 1.20 }',
        b'{ id = "AgileIII", weight = 3, stat = "speed", multiplier = 1.35 }',
    ):
        assert required in enchanting_balance, f"missing active QOF-19 balance: {required!r}"
    for required in (
        b"Enchanting must contain exactly four contract fields",
        b"Enchanting roll cost must remain exactly 500 diamonds",
        b"Enchanting pool must contain exactly six outcomes",
        b"enchant weights must sum to 100",
    ):
        assert required in balance_source, f"missing QOF-19 balance validation: {required!r}"
    assert b"RuntimeEnabled = false" not in enchanting_balance

    for required in (
        b"DataSchema.VERSION = 10",
        b"PetEnchantMath.normalizeEnchantId(pet.enchantId)",
        b"pet.enchant = nil",
        b"pet.enchantData = nil",
        b"pet.enchants = nil",
        b"pet.enchantStat = nil",
        b"pet.enchantMultiplier = nil",
    ):
        assert required in data_schema_source, f"missing V10 whitelist-only persistence: {required!r}"
    assert b"pet.enchantId = pet.enchant" not in data_schema_source
    assert b"pet.enchantId = pet.enchantData" not in data_schema_source

    enchant_math_source = (
        ROOT / "src/ReplicatedStorage/Shared/PetEnchantMath.lua"
    ).read_bytes()
    for required in (
        b"local definitionsById = {}",
        b"for index, definition in ipairs(BalanceConfig.Enchanting.Pool) do",
        b"function PetEnchantMath.normalizeEnchantId",
        b"function PetEnchantMath.getDefinition",
        b"function PetEnchantMath.getPublicPool",
        b'PetEnchantMath.normalizeEnchantId(rawget(pet, "enchantId"))',
        b"function PetEnchantMath.getDamageMultiplier",
        b"function PetEnchantMath.getCampaignSpeedMultiplier",
    ):
        assert required in enchant_math_source, f"missing canonical enchant math: {required!r}"
    for forbidden in (
        b'rawget(pet, "enchant")',
        b'rawget(pet, "enchantData")',
        b'rawget(pet, "enchantMultiplier")',
    ):
        assert forbidden not in enchant_math_source, f"untrusted derived enchant field is authoritative: {forbidden!r}"

    enchanting_service_source = (
        ROOT / "src/ServerScriptService/Services/EnchantingService.lua"
    ).read_bytes()
    for required in (
        b"local CONTRACT_VERSION = 1",
        b"getmetatable(request) ~= nil",
        b'rawget(request, "contractVersion") == CONTRACT_VERSION',
        b'exactRequest(request, "GET_STATE"',
        b"}, 3) and validPetInstanceId",
        b'exactRequest(request, "ROLL"',
        b"}, 5) then",
        b"expectedEnchantId == false",
        b"stateRevision = userId and currentRevision",
        b"enchantId = enchantId or false",
        b"outcomes = PetEnchantMath.getPublicPool()",
        b"isReroll = enchantId ~= nil",
        b"EnchantingService._randomSource(1, 100)",
        b"beginSpendTransaction",
        b"commitSpendTransaction",
        b"rollbackSpendTransaction",
        b"petStillMatches(transaction)",
        b"transaction.writtenEnchantId = rolledEnchantId",
        b"transaction.committed = true",
        b"pcall(bumpRevision",
        b"pcall(EnchantingService._petService.replicateInventory, player)",
        b"local function restoreTransaction(transaction)",
        b"EnchantingService._activeTransactions",
        b"function EnchantingService.cleanup",
        b"function EnchantingService.prepareForShutdown",
        b"EnchantingService.onPlayerRemoving = EnchantingService.cleanup",
        b'beginInventoryMutation(\n\t\tplayer,\n\t\t"EnchantingService"',
        b"isInventoryMutationCurrent",
        b"endInventoryMutation",
        b"transaction.committed == true",
    ):
        assert required in enchanting_service_source, f"missing QOF-19 service contract: {required!r}"
    assert b"data.diamonds = data.diamonds -" not in enchanting_service_source
    assert b"math.random()" not in enchanting_service_source

    # Main owns only remote creation and abuse controls; the service owns exact
    # Contract V1 shape, optimistic concurrency, economy, RNG, and rollback.
    for required in (
        b'"GetEnchantingState"',
        b'"RollPetEnchant"',
        b"EnchantingService.init(DataService, CurrencyService, PetService)",
        b'getRemoteFunction("GetEnchantingState").OnServerInvoke',
        b'canCall(player, "GetEnchantingState", 0.15)',
        b'canCallBurst(player, "GetEnchantingState", 12, 10)',
        b'getRemoteFunction("RollPetEnchant").OnServerInvoke',
        b'canCall(player, "RollPetEnchant", 0.35)',
        b'canCallBurst(player, "RollPetEnchant", 8, 10)',
        b'false, "RATE_LIMITED", EnchantingService.getState(',
        b"DataService.onPlayerRemoving(player, function()",
        b"PetService.isInventoryMutationIdle(player)",
        b"Profile settlement queued for retry",
    ):
        assert required in main_source, f"missing QOF-19 Main wiring: {required!r}"
    data_queue_at = main_source.index(b"DataService.onPlayerRemoving(player, function()")
    egg_cleanup_at = main_source.index(b"EggService.onPlayerRemoving(player)", data_queue_at)
    machine_cleanup_at = main_source.index(b"MachineService.onPlayerRemoving(player)", egg_cleanup_at)
    enchanting_cleanup_at = main_source.index(
        b"EnchantingService.onPlayerRemoving(player)", machine_cleanup_at
    )
    assert data_queue_at < egg_cleanup_at < machine_cleanup_at < enchanting_cleanup_at, (
        "profile queue must own retries while Egg/Machine/Enchant settle in lease order"
    )
    shutdown_auto_at = main_source.index(b"AutoHatchService.prepareForShutdown()")
    shutdown_egg_at = main_source.index(b"EggService.beginShutdown()")
    shutdown_machine_at = main_source.index(b"MachineService.beginShutdown()")
    shutdown_enchant_at = main_source.index(b"EnchantingService.beginShutdown()")
    shutdown_pickup_at = main_source.index(b"PickupService.settlePlayer(player)")
    assert shutdown_auto_at < shutdown_egg_at < shutdown_machine_at < shutdown_enchant_at < shutdown_pickup_at

    pet_service_source = (
        ROOT / "src/ServerScriptService/Services/PetService.lua"
    ).read_bytes()
    for required in (
        b"function PetService.beginInventoryMutation",
        b"function PetService.isInventoryMutationIdle",
        b"function PetService.isInventoryMutationCurrent",
        b"PetService._dataService.isMutationAdmissionOpen(player) ~= true",
        b"function PetService.endInventoryMutation",
        b"PetService._inventoryMutationLeases[userId] == lease",
        b"PetService._inventoryMutationIncarnations[userId] = lease.incarnation + 1",
        b"enchantPresent = rawget(pet, \"enchantId\") ~= nil",
        b"enchantId = rawget(pet, \"enchantId\")",
        b"rawget(pet, \"enchantId\") ~= snapshot.enchantId",
        b"outputPet.enchantId = nil",
        b"PetEnchantMath.getDamageMultiplier",
        b"local enchantedDamage = baseDamage * enchantMultiplier",
        b"PetData.Pets[petId]",
        b"PetEnchantMath.getCampaignSpeedMultiplier",
        b"local speed = baseSpeed * multiplier",
        b"projected[index] = deepCopy(pet)",
        b"pcall(event.FireClient, event, player, projectPets(data.pets))",
        b'withInventoryMutation(player, "PetService.equipPet"',
        b'withInventoryMutation(player, "PetService.unequipPet"',
        b'withInventoryMutation(player, "PetService.setPetFavorite"',
        b'withInventoryMutation(player, "PetService.deletePet"',
        b'withInventoryMutation(player, "PetService.deletePets"',
    ):
        assert required in pet_service_source, f"missing shared lease/stat/machine semantics: {required!r}"

    campaign_service_source = (
        ROOT / "src/ServerScriptService/Services/CampaignService.lua"
    ).read_bytes()
    for required in (
        b"CampaignService._petService.getPetDamage",
        b"CampaignService._petService.getCampaignLaneSpeed",
        b'return false, "Pet stats unavailable"',
        b"battle.energy = battle.energy - deployCost",
        b"speed = speed",
        b"getCurrentPetDamage",
    ):
        assert required in campaign_service_source, f"missing Strong/Agile campaign semantics: {required!r}"
    assert campaign_service_source.index(b"CampaignService._petService.getCampaignLaneSpeed") < (
        campaign_service_source.index(b"battle.energy = battle.energy - deployCost")
    )

    enchanting_session_source = (
        ROOT / "src/ReplicatedStorage/Shared/EnchantingClientSession.lua"
    ).read_bytes()
    for required in (
        b"local CONTRACT_VERSION = 1",
        b"return value == false or ENCHANT_IDS[value] == true",
        b"operation.expectedStateRevision = session.stateRevision",
        b"operation.expectedEnchantId = session.enchantId",
        b"state.pet.instanceId ~= operation.petInstanceId",
        b"state.stateRevision < operation.expectedStateRevision",
        b"mutationSucceeded == true",
        b"state.stateRevision <= operation.expectedStateRevision",
        b"session.revisionsByPet[operation.petInstanceId] = state.stateRevision",
    ):
        assert required in enchanting_session_source, f"missing exact client concurrency contract: {required!r}"

    enchanting_contract_source = (
        ROOT / "src/ReplicatedStorage/Shared/EnchantingClientContract.lua"
    ).read_bytes()
    for required in (
        b"function EnchantingClientContract.validateState",
        b"getmetatable(value) ~= nil",
        b'rawget(economy, "price") ~= 500',
        b'rawget(outcome, "id") ~= expected.id',
        b'rawget(outcome, "weight") ~= expected.weight',
        b'rawget(outcome, "stat") ~= expected.stat',
        b'rawget(outcome, "multiplier") ~= expected.multiplier',
    ):
        assert required in enchanting_contract_source, f"missing strict client DTO contract: {required!r}"

    for required in (
        b'Shared:FindFirstChild("EnchantingClientSession")',
        b'Shared:FindFirstChild("EnchantingClientContract")',
        b'Remotes:FindFirstChild("GetEnchantingState")',
        b'Remotes:FindFirstChild("RollPetEnchant")',
        b'GetEnchantingState:InvokeServer({',
        b'action = "GET_STATE"',
        b'RollPetEnchant:InvokeServer({',
        b'action = "ROLL"',
        b"expectedStateRevision = operation.expectedStateRevision",
        b"expectedEnchantId = operation.expectedEnchantId",
        b"local validResultTuple = type(success) == \"boolean\"",
        b"success == false and ENCHANTING_REASON_CODES[reason] == true",
        b"EnchantingClientContract.validateState(state, petInstanceId)",
        b"success == true",
        b'showEnchantingUnavailable("UNAVAILABLE")',
    ):
        assert required in client_source, f"missing optional QOF-19 client contract: {required!r}"
    for forbidden in (
        b'WaitForChild("EnchantingClientSession")',
        b'WaitForChild("GetEnchantingState")',
        b'WaitForChild("RollPetEnchant")',
    ):
        assert forbidden not in client_source, f"rolling client can block on QOF-19: {forbidden!r}"

    for required in (
        b'detailsBtn.Name = "PetDetailsBtn"',
        b'self:showEnchantingUnavailable("UNAVAILABLE")',
        b'self._petDetailEnchantLabel.Text = "Current Enchant: UNAVAILABLE"',
        b'self._petDetailCostLabel.Text = "Cost: UNAVAILABLE"',
        b'local detailPet = self:_findInventoryPet(self._petDetailPetId)',
        b"if not detailPet then\n\t\t\tself:_requestEnchantingClose()",
        b"for _, outcome in ipairs(state.outcomes) do",
        b'tostring(state.economy.price) .. " Diamonds"',
        b"Reroll replaces this one enchant slot. The old enchant cannot be kept.",
        b"Input pets and their enchants are always consumed.",
        b"Diamonds are also spent on a normal failure.",
        b"A successful output starts with no enchant.",
    ):
        assert required in ui_source, f"missing QOF-19 inventory UX contract: {required!r}"

    zone_text = zone_service_source
    for forbidden in (
        b"EnchantStation",
        b"EnchantingStation",
        b"spawnEnchant",
        b"UseEnchantMachine",
        b"EnchantMachine",
    ):
        assert forbidden not in main_source
        assert forbidden not in client_source
        assert forbidden not in zone_text
    remote_function_manifest = main_source.split(
        b"local remoteFunctions = {", 1
    )[1].split(b"\n}", 1)[0]
    assert remote_function_manifest.count(b'"UseMachine",') == 1, (
        "QOF-19 must reuse the shared inventory lease, not add a second machine remote"
    )

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
    print("PASS: generated place embeds every QOF-19 runtime source exactly once")
    print(f"PASS: all {EXPECTED_SCRIPT_COUNTS['ModuleScript'] + 2} generated script sources have byte-exact source parity")
    print(f"PASS: generated script counts are {actual_counts}")


if __name__ == "__main__":
    main()
