prometheus = import_module("./src/prometheus/prometheus_launcher.star")
grafana = import_module("./src/grafana/grafana_launcher.star")
bdjuno = import_module("./src/bdjuno/bdjuno_launcher.star")

def run(plan, args):

    # Retrieve params from config file
    chain_id = args["chain_id"]
    genesis_time = args["genesis_time"]
    faucet_amount = args["faucet_amount"]
    min_self_delegation = args["min_self_delegation"]
    min_deposit = args["min_deposit"]
    voting_period = args["voting_period"]
    participants = args["participants"]

    KEY_PASSWORD = "LZeroPassword!"

    # Configure genesis data for template
    genesis_data = {
        "ChainID": chain_id,
        "GenesisTime": genesis_time,
        "FaucetAmount": faucet_amount,
        "MinSelfDelegation": min_self_delegation,
        "MinDeposit": min_deposit,
        "VotingPeriod": voting_period
    }

    # Render genesis file with cuastom params
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

    # Start a genesis service to set up genesis file
    plan.add_service(
        name = "genesis-service",
        config = ServiceConfig(
            image="tiljordan/coreum-cored:latest",
            files=files
        )
    )

    total_count = 0
    for participant in participants:
        total_count += participant["count"]

    plan.print("Creating a total of {0} validators".format(total_count))

    addresses = []
    mnemonics = []
    pub_keys = []
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
        pub_key = pub_keys[i]

        # Create gentx directory
        plan.exec(
            service_name = "genesis-service",
            recipe = ExecRecipe(
                command = ["/bin/sh", "-c", "mkdir -p /root/.core/{0}/config/gentx/".format(chain_id)]
            )
        )
        # Create genesis transactions for validators
        gentx_command = "echo -e 'LZeroPassword!\nLZeroPassword!' | cored genesis gentx validator{0} {1} --min-self-delegation {2} --moniker 'validator{0}' --output-document /root/.core/{3}/config/gentx/{4} --chain-id {3} --pubkey '{5}'".format(i, amount, min_self_delegation, chain_id, filename, pub_key)
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

    # Export genesis file
    store_genesis = plan.store_service_files(
        service_name = "genesis-service",
        src = "/root/.core/{0}/config/genesis.json".format(chain_id),
        name = "genesis-file"
    )

    # Remove genesis service after genesis file is exported
    plan.remove_service(name = "genesis-service")

    node_files = {
        "/tmp/genesis": store_genesis,
    }

    node_names = []
    seed_info = ""
    node_id = ""
    first_node_service = ""
    counter = 0
    for i, participant in enumerate(participants):
        node_count = participant["count"]

        for j in range(node_count):

            node_name = "node{0}".format(counter + 1)
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
                        "rpc": PortSpec(number = 26657, transport_protocol = "TCP", wait = None),
                        "grpc": PortSpec(number = 9090, transport_protocol = "TCP", wait = None),
                        "grpcWeb": PortSpec(number = 9091, transport_protocol = "TCP", wait = None),
                        "api": PortSpec(number = 1317, transport_protocol = "TCP", wait = None),
                        "pProf": PortSpec(number = 6060, transport_protocol = "TCP", wait = None),
                        "prometheus": PortSpec(number = 26660, transport_protocol = "TCP", wait = None)
                    }
                )
            )

            # Recreate keys on the node
            mnemonic = mnemonics[counter]
            recover_key_command = "echo -e '{0}\n{1}\n{1}' | cored keys add validator{2} --recover --chain-id {3}".format(mnemonic, KEY_PASSWORD, counter, chain_id)
            plan.exec(
                service_name = node_name,
                recipe = ExecRecipe(
                    command=["/bin/sh", "-c", recover_key_command]
                )
            )

            # Init the Coreum node
            plan.print("Initialising " + node_name)
            init_cmd = "echo -e '{0}' | cored init validator{1} --chain-id {2} --recover".format(mnemonic, counter, chain_id)
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

            # Build persistent peers string
            if i == 0 and j == 0:
                # Store the first node service to later retrieve ip address
                first_node_service = node_service
                # Get node id for peering
                node_id = plan.exec(
                    service_name = node_name,
                    recipe = ExecRecipe(
                        command = ["/bin/sh", "-c", "cored tendermint show-node-id --chain-id " + chain_id]
                    )
                )

            counter += 1

    plan.print("Peering nodes with the following seed: " + seed_info)
    for (i, node_name) in enumerate(node_names):

        if i == 0:
            update_seed_command = "sed -i 's/seeds = \"[^\"]*\"/seeds = \"\"/' /root/.core/{0}/config/config.toml".format(chain_id)
            plan.print("Executing first seed command: {0}".format(update_seed_command))
        else:
            # Use workaround for dealing with future references; Temp store variables and use to replace seed info
            store_id_command = "echo '" + node_id["output"] + "' > /tmp/node_id"
            store_ip_command = "echo '" + first_node_service.ip_address + "' > /tmp/node_ip"

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
                    "sed -i 's/^seeds = .*/seeds = \"'$node_id@$node_ip:26656'\"/' /root/.core/" + chain_id + "/config/config.toml"
            )

        plan.exec(
            service_name = node_name,
            recipe = ExecRecipe(
                command = ["/bin/sh", "-c", update_seed_command]
            )
        )

        update_prometheus_command = (
            "sed -i 's|^prometheus = false|prometheus = true|' /root/.core/" + chain_id + "/config/config.toml && " +
            "sed -i 's|^prometheus_listen_addr = \":26660\"|prometheus_listen_addr = \"0.0.0.0:26660\"|' /root/.core/" + chain_id + "/config/config.toml"
        )

        plan.exec(
            service_name=node_name,
            recipe=ExecRecipe(
                command=["/bin/sh", "-c", update_prometheus_command]
            )
        )


    # Start nodes
    for node_name in node_names:
        plan.exec(
            service_name = node_name,
            recipe = ExecRecipe(
                command = ["/bin/sh", "-c", "nohup cored start --rpc.laddr tcp://0.0.0.0:26657 --grpc.address 0.0.0.0:9090 --chain-id " + chain_id + " > /dev/null 2>&1 &"]
            )
        )
        plan.print("{0} started successfully with chain ID {1}".format(node_name, chain_id))

    # Start prometheus service
    prometheus_url = prometheus.launch_prometheus(plan, node_names)

    # Start grafana
    grafana.launch_grafana(plan, prometheus_url)

    # Start BDJuno explorer
    bdjuno.launch_bdjuno(plan)