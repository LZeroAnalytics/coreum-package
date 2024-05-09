def generate_genesis_file(plan, general_args, faucet_args, governance_args, staking_args, participants):

    chain_id = general_args["chain_id"]
    genesis_delay = general_args["genesis_delay"]
    key_password = general_args["key_password"]
    block_size = general_args["block_size"]
    max_gas = general_args["max_gas"]

    faucet_address = faucet_args["address"]
    faucet_amount = faucet_args["faucet_amount"]

    min_self_delegation = staking_args["min_self_delegation"]
    max_validators = staking_args["max_validators"]
    downtime_jail_duration = staking_args["downtime_jail_duration"]

    min_deposit = governance_args["min_deposit"]
    voting_period = governance_args["voting_period"]

    # Calculate genesis time
    genesis_time = get_genesis_time(plan, genesis_delay)


    # Start the service to generate genesis file
    start_genesis_service(
        plan,
        chain_id,
        genesis_time,
        faucet_address,
        faucet_amount,
        min_self_delegation,
        max_validators,
        downtime_jail_duration,
        min_deposit,
        voting_period,
        block_size,
        max_gas
    )

    # Total number of nodes
    total_count = 0
    account_balances = []
    staking_amounts = []
    for participant in participants:
        total_count += participant["count"]
        for _ in range(participant["count"]):
            account_balances.append(str(participant["account_balance"]) + "udevcore")
            staking_amounts.append(str(participant["staking_amount"]) + "udevcore")

    plan.print("Creating a total of {0} validators".format(total_count))

    # Generate an address for each node
    mnemonics, addresses, pub_keys = generate_keys(plan, total_count, chain_id, key_password)

    # Init the genesis file and use template file
    init_genesis(plan, chain_id)

    # Add accounts to genesis file
    add_accounts(plan, chain_id, addresses, account_balances)

    # Add validators to genesis using gentx commands
    add_validators(plan, chain_id, addresses, pub_keys, min_self_delegation, key_password, staking_amounts)

    # Export genesis file
    genesis_file = plan.store_service_files(
        service_name = "genesis-service",
        src = "/root/.core/{0}/config/genesis.json".format(chain_id),
        name = "genesis-file"
    )

    # Remove genesis service after genesis file is exported
    plan.remove_service(name = "genesis-service")

    return genesis_file, mnemonics, addresses


def start_genesis_service(
        plan,
        chain_id,
        genesis_time,
        faucet_address,
        faucet_amount,
        min_self_delegation,
        max_validators,
        downtime_jail_duration,
        min_deposit,
        voting_period,
        block_size,
        max_gas
):
    # Configure genesis data for template
    genesis_data = {
        "ChainID": chain_id,
        "GenesisTime": genesis_time,
        "FaucetAddress": faucet_address,
        "FaucetAmount": faucet_amount,
        "MinSelfDelegation": min_self_delegation,
        "MaxValidators": max_validators,
        "DowntimeJailDuration": downtime_jail_duration,
        "MinDeposit": min_deposit,
        "VotingPeriod": voting_period,
        "BlockSize": block_size,
        "MaxGas": max_gas
    }

    # Render genesis file with cuastom params
    genesis_file = plan.render_templates(
        config = {
            "genesis.json": struct(
                template = read_file("templates/genesis.json.tmpl"),
                data = genesis_data
            )
        },
        name="genesis-file-template"
    )

    files = {
        "/tmp/genesis": genesis_file,
    }

    # Start a genesis service to set up genesis file
    plan.add_service(
        name = "genesis-service",
        config = ServiceConfig(
            image="tiljordan/coreum-cored:latest",
            files=files
        )
    )


def generate_keys(plan, total_count, chain_id, keyPassword):
    addresses = []
    mnemonics = []
    pub_keys = []
    for i in range(total_count):
        # Add validator key
        keys_command = "echo -e '{0}\n{0}' | cored keys add validator{1} --chain-id {2} --output json".format(keyPassword, i, chain_id)
        key_result = plan.exec(
            service_name = "genesis-service",
            recipe = ExecRecipe(
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

        # Initialize genesis with mnemonic from previous key generation
        init_command = "echo -e '{0}' | cored init validator{1} --chain-id {2} --recover".format(mnemonic, i, chain_id)
        plan.exec(
            service_name = "genesis-service",
            recipe = ExecRecipe(
                command = ["/bin/sh", "-c", init_command]
            )
        )

        # Extract public key from the priv_validator_key.json file
        extract_pubkey_command = "cat /root/.core/{0}/config/priv_validator_key.json".format(chain_id)
        pubkey_result = plan.exec(
            service_name = "genesis-service",
            recipe = ExecRecipe(
                command = ["/bin/sh", "-c", extract_pubkey_command],
                extract = {
                    "pub_key": "fromjson | .pub_key.value"
                }
            )
        )
        pubkey_json = '{"@type":"/cosmos.crypto.ed25519.PubKey", "key": "' + pubkey_result["extract.pub_key"] + '"}'
        pub_keys.append(pubkey_json)

        genesis_remove_command = "rm /root/.core/{0}/config/genesis.json".format(chain_id)
        plan.exec(
            service_name = "genesis-service",
            recipe = ExecRecipe(
                command = ["/bin/sh", "-c", genesis_remove_command]
            )
        )

    return mnemonics, addresses, pub_keys


def init_genesis(plan, chain_id):
    init_cmd = "cored init node1 --chain-id {0}".format(chain_id)
    plan.exec(
        service_name = "genesis-service",
        recipe = ExecRecipe(
            command=["/bin/sh", "-c", init_cmd]
        )
    )

    # Replace the genesis.json file
    genesis_path = "/root/.core/{0}/config/genesis.json".format(chain_id)
    move_command = "mv -f /tmp/genesis/genesis.json " + genesis_path
    plan.exec(
        service_name = "genesis-service",
        recipe = ExecRecipe(
            command=["/bin/sh", "-c", move_command]
        )
    )


def add_accounts(plan, chain_id, addresses, account_balances):
    for i, address in enumerate(addresses):
        add_account_command = "cored genesis add-genesis-account {0} {1} --chain-id {2}".format(address, account_balances[i], chain_id)
        plan.exec(
            service_name="genesis-service",
            recipe=ExecRecipe(
                command=["/bin/sh", "-c", add_account_command]
            )
        )


def add_validators(plan, chain_id, addresses, pub_keys, min_self_delegation, key_password, staking_amounts):
    for i, address in enumerate(addresses):
        # Amount to bond
        filename = "gentx-validator{0}.json".format(i)
        pub_key = pub_keys[i]

        # Create gentx directory
        plan.exec(
            service_name = "genesis-service",
            recipe = ExecRecipe(
                command = ["/bin/sh", "-c", "mkdir -p /root/.core/{0}/config/gentx/".format(chain_id)]
            )
        )
        # Create genesis transactions for validators
        gentx_command = "echo -e '{6}\n{6}' | cored genesis gentx validator{0} {1} --min-self-delegation {2} --moniker 'validator{0}' --output-document /root/.core/{3}/config/gentx/{4} --chain-id {3} --pubkey '{5}'".format(i, staking_amounts[i], min_self_delegation, chain_id, filename, pub_key, key_password)
        plan.exec(
            service_name="genesis-service",
            recipe=ExecRecipe(
                command=["/bin/sh", "-c", gentx_command]
            )
        )

    # Collect all gentxs
    collect_gentxs_command = "cored genesis collect-gentxs --chain-id {0}".format(chain_id)
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

# Get the padding from the command-line arguments
padding = int(sys.argv[1])

# Calculate future time by adding the padding (in seconds)
future_time = datetime.utcnow() + timedelta(seconds=padding)

# Format the future time in ISO 8601 format, appending 'Z' to denote UTC
formatted_time = future_time.strftime('%Y-%m-%dT%H:%M:%SZ')

print(formatted_time, end="")
""",
        args=[str(genesis_delay)]
    )
    return result.output
