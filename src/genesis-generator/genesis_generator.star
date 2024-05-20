def generate_genesis_files(plan, parsed_args):
    genesis_files = {}
    for chain in parsed_args["chains"]:
        if chain["type"] == "coreum":
            genesis_file, mnemonics, addresses = generate_genesis_file(plan, chain, "cored")
        elif chain["type"] == "gaia":
            genesis_file, mnemonics, addresses = generate_genesis_file(plan, chain, "gaiad")
        else:
            fail("Unsupported chain type: " + chain["type"])

        genesis_files[chain["name"]] = {
            "genesis_file": genesis_file,
            "mnemonics": mnemonics,
            "addresses": addresses
        }
    return genesis_files

def generate_genesis_file(plan, chain, binary):
    chain_id = chain["chain_id"]
    genesis_delay = chain["genesis_delay"]
    denom = chain["denom"]
    consensus_params = chain["consensus_params"]
    modules = chain["modules"]
    faucet = chain["faucet"]
    initial_height = chain["initial_height"]
    genesis_time = get_genesis_time(plan, genesis_delay)

    # Start the service to generate genesis file
    start_genesis_service(
        plan,
        chain_id,
        genesis_time,
        denom,
        consensus_params,
        modules,
        faucet,
        initial_height,
        binary
    )

    total_count = 0
    account_balances = []
    staking_addresses = []
    staking_amounts = []

    for participant in chain["participants"]:
        total_count += participant["count"]
        for _ in range(participant["count"]):
            account_balances.append("{}{}".format(participant["account_balance"], denom["name"]))
            if participant.get("staking", True):
                staking_amounts.append("{}{}".format(participant["staking_amount"], denom["name"]))

    mnemonics, addresses, pub_keys = generate_keys(plan, total_count, chain_id, binary)

    all_addresses = addresses[:]
    all_pub_keys = pub_keys[:]

    init_genesis(plan, chain_id, binary)

    plan.print(genesis_time)
    add_accounts(plan, chain_id, addresses, account_balances, binary)

    for participant in chain["participants"]:
        for _ in range(participant["count"]):
            if participant.get("staking", True):
                staking_addresses.append(all_addresses.pop(0))

    add_validators(plan, chain_id, staking_addresses, all_pub_keys[:len(staking_addresses)], modules["staking"]["min_self_delegation"], staking_amounts, binary)

    # Config folder is either .core or .gaia
    config_folder = binary[:len(binary) - 1]
    genesis_file = plan.store_service_files(
        service_name="genesis-service",
        src="/root/.{}/{}/config/genesis.json".format(config_folder, chain_id),
        name="{}-genesis-file".format(chain["name"])
    )
    plan.remove_service(name="genesis-service")

    return genesis_file, mnemonics, addresses

def start_genesis_service(plan, chain_id, genesis_time, denom, consensus_params, modules, faucet, initial_height, binary):
    genesis_data = {
        "ChainID": chain_id,
        "GenesisTime": genesis_time,
        "DenomName": denom["name"],
        "DenomDisplay": denom["display"],
        "DenomSymbol": denom["symbol"],
        "DenomDescription": denom["description"],
        "DenomUnits": json.encode(denom["units"]),
        "MinSelfDelegation": modules["staking"]["min_self_delegation"],
        "MaxValidators": modules["staking"]["max_validators"],
        "BlockMaxBytes": consensus_params["block_max_bytes"],
        "BlockMaxGas": consensus_params["block_max_gas"],
        "EvidenceMaxAgeDuration": consensus_params["evidence_max_age_duration"],
        "EvidenceMaxAgeNumBlocks": consensus_params["evidence_max_age_num_blocks"],
        "EvidenceMaxBytes": consensus_params["evidence_max_bytes"],
        "ValidatorPubKeyTypes": json.encode(consensus_params["validator_pub_key_types"]),
        "InitialHeight": initial_height,
        "AuthMaxMemoCharacters": modules["auth"]["max_memo_characters"],
        "AuthSigVerifyCostEd25519": modules["auth"]["sig_verify_cost_ed25519"],
        "AuthSigVerifyCostSecp256k1": modules["auth"]["sig_verify_cost_secp256k1"],
        "AuthTxSigLimit": modules["auth"]["tx_sig_limit"],
        "AuthTxSizeCostPerByte": modules["auth"]["tx_size_cost_per_byte"],
        "CrisisConstantFeeAmount": modules["crisis"]["constant_fee_amount"],
        "DistributionBaseProposerReward": modules["distribution"]["base_proposer_reward"],
        "DistributionBonusProposerReward": modules["distribution"]["bonus_proposer_reward"],
        "DistributionCommunityTax": modules["distribution"]["community_tax"],
        "DistributionWithdrawAddrEnabled": modules["distribution"]["withdraw_addr_enabled"],
        "FeemodelMinGasPrice": modules["feemodel"]["min_gas_price"],
        "FeemodelEscalationStartFraction": modules["feemodel"]["escalation_start_fraction"],
        "FeemodelInitialGasPrice": modules["feemodel"]["initial_gas_price"],
        "FeemodelLongEmaBlockLength": modules["feemodel"]["long_ema_block_length"],
        "FeemodelMaxBlockGas": modules["feemodel"]["max_block_gas"],
        "FeemodelMaxDiscount": modules["feemodel"]["max_discount"],
        "FeemodelMaxGasPriceMultiplier": modules["feemodel"]["max_gas_price_multiplier"],
        "FeemodelShortEmaBlockLength": modules["feemodel"]["short_ema_block_length"],
        "SlashingDowntimeJailDuration": modules["slashing"]["downtime_jail_duration"],
        "SlashingMinSignedPerWindow": modules["slashing"]["min_signed_per_window"],
        "SlashingSignedBlocksWindow": modules["slashing"]["signed_blocks_window"],
        "SlashingSlashFractionDoubleSign": modules["slashing"]["slash_fraction_double_sign"],
        "SlashingSlashFractionDowntime": modules["slashing"]["slash_fraction_downtime"],
        "MintInflation": modules["mint"]["inflation"],
        "MintAnnualProvisions": modules["mint"]["annual_provisions"],
        "MintBlocksPerYear": modules["mint"]["blocks_per_year"],
        "MintGoalBonded": modules["mint"]["goal_bonded"],
        "MintInflationMax": modules["mint"]["inflation_max"],
        "MintInflationMin": modules["mint"]["inflation_min"],
        "MintInflationRateChange": modules["mint"]["inflation_rate_change"],
        "IbcAllowedClients": json.encode(modules["ibc"]["allowed_clients"]),
        "IbcMaxExpectedTimePerBlock": modules["ibc"]["max_expected_time_per_block"]
    }

    genesis_template = "templates/genesis_coreum.json.tmpl" if binary == "cored" else "templates/genesis_gaia.json.tmpl"
    genesis_file = plan.render_templates(
        config={
            "genesis.json": struct(
                template=read_file(genesis_template),
                data=genesis_data
            )
        },
        name="genesis-file-template"
    )

    files = {
        "/tmp/genesis": genesis_file,
    }

    plan.add_service(
        name="genesis-service",
        config=ServiceConfig(
            image="tiljordan/coreum-cored:latest" if binary == "cored" else "tiljordan/gaia:v15.2.0",
            files=files
        )
    )

def generate_keys(plan, total_count, chain_id, binary):
    addresses = []
    mnemonics = []
    pub_keys = []
    for i in range(total_count):
        keyring_flags = "--keyring-backend test"
        config_folder = binary[:len(binary) - 1]

        keys_command = "{} keys add validator{} {} --output json --chain-id {}".format(binary, i, keyring_flags, chain_id)
        key_result = plan.exec(
            service_name="genesis-service",
            recipe=ExecRecipe(
                command=["/bin/sh", "-c", keys_command],
                extract={
                    "validator_address": "fromjson | .address",
                    "mnemonic": "fromjson | .mnemonic"
                }
            )
        )

        key_address = key_result["extract.validator_address"]
        mnemonic = key_result["extract.mnemonic"]
        addresses.append(key_address)
        mnemonics.append(mnemonic)

        init_command = "echo -e '{}' | {} init validator{} --chain-id {} --recover".format(mnemonic, binary, i, chain_id)
        plan.exec(
            service_name = "genesis-service",
            recipe = ExecRecipe(
                command = ["/bin/sh", "-c", init_command]
            )
        )

        pubkey_command = "cat /root/.{}/{}/config/priv_validator_key.json".format(config_folder, chain_id)
        pubkey_result = plan.exec(
            service_name="genesis-service",
            recipe=ExecRecipe(
                command=["/bin/sh", "-c", pubkey_command],
                extract={
                    "pub_key": "fromjson | .pub_key.value"
                }
            )
        )
        pubkey_json = '{{"@type":"/cosmos.crypto.ed25519.PubKey", "key": "{}"}}'.format(pubkey_result["extract.pub_key"])
        pub_keys.append(pubkey_json)

        genesis_remove_command = "rm /root/.{}/{}/config/genesis.json".format(config_folder, chain_id)
        plan.exec(
            service_name="genesis-service",
            recipe=ExecRecipe(
                command=["/bin/sh", "-c", genesis_remove_command]
            )
        )

    return mnemonics, addresses, pub_keys

def init_genesis(plan, chain_id, binary):
    config_folder = binary[:len(binary) - 1]
    init_command = "{} init node1 --chain-id {}".format(binary, chain_id)
    plan.exec(
        service_name="genesis-service",
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", init_command]
        )
    )

    genesis_path = "/root/.{}/{}/config/genesis.json".format(config_folder, chain_id)
    move_command = "mv -f /tmp/genesis/genesis.json {}".format(genesis_path)
    plan.exec(
        service_name="genesis-service",
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", move_command]
        )
    )

def add_accounts(plan, chain_id, addresses, account_balances, binary):
    for i, address in enumerate(addresses):
        add_account_command = "{} genesis add-genesis-account {} {} --chain-id {}".format(binary, address, account_balances[i], chain_id)
        plan.exec(
            service_name="genesis-service",
            recipe=ExecRecipe(
                command=["/bin/sh", "-c", add_account_command]
            )
        )

def add_validators(plan, chain_id, addresses, pub_keys, min_self_delegation, staking_amounts, binary):
    config_folder = binary[:len(binary) - 1]

    # Create gentx directory
    plan.exec(
        service_name = "genesis-service",
        recipe = ExecRecipe(
            command = ["/bin/sh", "-c", "mkdir -p /root/.core/{0}/config/gentx/".format(chain_id)]
        )
    )

    for i, address in enumerate(addresses):
        keyring_flags = "--keyring-backend test"
        filename = "gentx-validator{}.json".format(i)
        pub_key = pub_keys[i]

        gentx_command = "{} genesis gentx validator{} {} --chain-id {} {} --min-self-delegation {} --output-document /root/.{}/{}/config/gentx/{} --pubkey '{}'".format(binary, i, staking_amounts[i], chain_id, keyring_flags, min_self_delegation, config_folder, chain_id, filename, pub_key)
        plan.exec(
            service_name="genesis-service",
            recipe=ExecRecipe(
                command=["/bin/sh", "-c", gentx_command]
            )
        )

    collect_gentxs_command = "{} genesis collect-gentxs --chain-id {}".format(binary, chain_id)
    plan.exec(
        service_name="genesis-service",
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", collect_gentxs_command]
        )
    )

def get_genesis_time(plan, genesis_delay):
    result = plan.run_python(
        description="Calculating genesis time",
        run="""
import time
from datetime import datetime, timedelta
import sys

padding = int(sys.argv[1])
future_time = datetime.utcnow() + timedelta(seconds=padding)
formatted_time = future_time.strftime('%Y-%m-%dT%H:%M:%SZ')
print(formatted_time, end="")
""",
        args=[str(genesis_delay)]
    )
    return result.output