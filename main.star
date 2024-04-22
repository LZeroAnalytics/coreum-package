def run(plan, args):

    chain_id = args["chain_id"]
    genesis_time = args["genesis_time"]
    faucet_amount = args["faucet_amount"]
    min_self_delegation = args["min_self_delegation"]
    min_deposit = args["min_deposit"]
    voting_period = args["voting_period"]
    participants = args["participants"]

    KEY_PASSWORD = "LZeroPassword!"

    genesis_data = {
        "ChainID": chain_id,
        "GenesisTime": genesis_time,
        "FaucetAmount": faucet_amount,
        "MinSelfDelegation": min_self_delegation,
        "MinDeposit": min_deposit,
        "VotingPeriod": voting_period
    }

    genesis_file = plan.render_templates(
        config = {
            "genesis.json": struct(
                template = read_file("templates/genesis.json.tmpl"),
                data = genesis_data
            )
        }
    )

    files = {
        "/tmp/genesis": genesis_file,
    }

    genesis_service = plan.add_service(
        name = "genesis-service",
        config = ServiceConfig(
            image="tiljordan/coreum-cored:latest",
            files=files
        )
    )

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

    total_count = 0
    for participant in participants:
        total_count += participant["count"]

    plan.print("Creating a total of {0} validators".format(total_count))

    addresses = []
    mnemonics = []
    for i in range(total_count):
        # Add validator key
        keys_command = "echo -e '{0}\n{0}' | cored keys add validator{1} --chain-id {2} --output json".format(KEY_PASSWORD, i, chain_id)
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


    balance = "100000000000udevcore"
    for address in addresses:
        add_account_command = "cored genesis add-genesis-account {0} {1} --chain-id {2}".format(address, balance, chain_id)
        plan.exec(
            service_name="genesis-service",
            recipe=ExecRecipe(
                command=["/bin/sh", "-c", add_account_command]
            )
        )

    for i, address in enumerate(addresses):
        # Amount to bond
        amount = "20000000000udevcore"
        filename = "gentx-validator{0}.json".format(i)

        # Create gentx directory
        plan.exec(
            service_name = "genesis-service",
            recipe = ExecRecipe(
                command = ["/bin/sh", "-c", "mkdir -p /root/.core/{0}/config/gentx/".format(chain_id)]
            )
        )

        # TODO: Fix error of using the same public key for each validator; When using -pubkey flag get this error: secp256k1, expected: [ed25519]
        # Create genesis transactions for validators
        gentx_command = "echo -e 'LZeroPassword!\nLZeroPassword!' | cored genesis gentx validator{0} {1} --min-self-delegation {2} --moniker '{5}' --output-document /root/.core/{3}/config/gentx/{4} --chain-id {3}".format(i, amount, min_self_delegation, chain_id, filename, "validator{0}".format(i))
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

    # Export
    store_genesis = plan.store_service_files(
        service_name = "genesis-service",
        src = "/root/.core/{0}/config/genesis.json".format(chain_id),
        name = "genesis-file"
    )

    node_files = {
        "/tmp/genesis": store_genesis,
    }

    node_names = []
    seed_info = ""
    node_id = ""
    node_service= ""
    for i, participant in enumerate(participants):
        node_count = participant["count"]

        for j in range(node_count):

            node_name = "node{0}".format(i + j + 1)
            node_names.append(node_name)

            # Start the node service
            plan.print("Starting node service " + node_name)
            node_service = plan.add_service(
                name = node_name,
                config = ServiceConfig(
                    image=participant['image'],
                    files=node_files,
                    ports = {
                        "p2p": PortSpec(number = 26656, transport_protocol = "TCP", wait = None),
                        "rcp": PortSpec(number = 26657, transport_protocol = "TCP", wait = None),
                        "grpc": PortSpec(number = 9090, transport_protocol = "TCP", wait = None),
                        "grpcWeb": PortSpec(number = 9091, transport_protocol = "TCP", wait = None),
                        "api": PortSpec(number = 1317, transport_protocol = "TCP", wait = None),
                        "pProf": PortSpec(number = 6060, transport_protocol = "TCP", wait = None),
                        "prometheus": PortSpec(number = 26660, transport_protocol = "TCP", wait = None)
                    }
                )
            )

            # Init the Coreum node
            plan.print("Initialising " + node_name)
            init_cmd = "cored init {0} --chain-id {1}".format(node_name, chain_id)
            plan.exec(
                service_name = node_name,
                recipe = ExecRecipe(
                    command=["/bin/sh", "-c", init_cmd]
                )
            )

            # Use the preconfigured genesis file
            plan.exec(
                service_name = node_name,
                recipe = ExecRecipe(
                    command=["/bin/sh", "-c", move_command]
                )
            )

            # Recreate keys on the node
            mnemonic = mnemonics[i + j]
            recover_key_command = "echo -e '{0}\n{1}\n{1}' | cored keys add validator{2} --recover --chain-id {3}".format(mnemonic, KEY_PASSWORD, i + j, chain_id)
            plan.exec(
                service_name = node_name,
                recipe = ExecRecipe(
                    command=["/bin/sh", "-c", recover_key_command]
                )
            )

            # Build persistent peers string
            if i == 0 and j == 0:
                # Get node id for peering
                node_id = plan.exec(
                    service_name = node_name,
                    recipe = ExecRecipe(
                        command = ["/bin/sh", "-c", "cored tendermint show-node-id --chain-id " + chain_id]
                    )
                )

    plan.print("Peering nodes with the following seed: " + seed_info)
    for (i, node_name) in enumerate(node_names):

        if i == 0:
            update_seed_command = "sed -i 's/seeds = \"[^\"]*\"/seeds = \"\"/' /root/.core/{0}/config/config.toml".format(chain_id)
            plan.print("Executing first seed command: {0}".format(update_seed_command))
        else:
            # Use workaround for dealing with future references; Temp store variables and use to replace seed info
            store_id_command = "echo '" + node_id["output"] + "' > /tmp/node_id"
            store_ip_command = "echo '" + node_service.ip_address + "' > /tmp/node_ip"

            # Execute storage commands
            plan.exec(
                service_name=node_name,
                recipe=ExecRecipe(
                    command=["/bin/sh", "-c", store_id_command]
                )
            )

            plan.exec(
                service_name=node_name,
                recipe=ExecRecipe(
                    command=["/bin/sh", "-c", store_ip_command]
                )
            )

            update_seed_command = (
                    "node_id=$(cat /tmp/node_id) && " +
                    "node_ip=$(cat /tmp/node_ip) && " +
                    "sed -i 's/^seeds = .*/seeds = '\"$node_id@$node_ip:26656\"'/' /root/.core/" + chain_id + "/config/config.toml"
            )

        plan.exec(
            service_name = node_name,
            recipe = ExecRecipe(
                command = ["/bin/sh", "-c", update_seed_command]
            )
        )

    # Start nodes
    for node_name in node_names:
        plan.exec(
            service_name = node_name,
            recipe = ExecRecipe(
                command = ["/bin/sh", "-c", "cored start --chain-id " + chain_id]
            )
        )
        plan.print("{0} started successfully with chain ID {1}".format(node_name, chain_id))

