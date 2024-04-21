def run(plan, args):

    chain_id = args["chain_id"]
    genesis_time = args["genesis_time"]
    faucet_amount = args["faucet_amount"]
    min_self_delegation = args["min_self_delegation"]
    min_deposit = args["min_deposit"]
    voting_period = args["voting_period"]
    participants = args["participants"]

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
            files=files,
            # ports = {
            #     "rcp": PortSpec(number = 26656, transport_protocol = "TCP"),
            #     "p2p": PortSpec(number = 26657, transport_protocol = "TCP"),
            #     "grpc": PortSpec(number = 9090, transport_protocol = "TCP"),
            #     "grpcWeb": PortSpec(number = 9091, transport_protocol = "TCP"),
            #     "api": PortSpec(number = 1317, transport_protocol = "TCP"),
            #     "pProf": PortSpec(number = 6060, transport_protocol = "TCP"),
            #     "prometheus": PortSpec(number = 26660, transport_protocol = "TCP")
            # }
        )
    )

    init_cmd = "cored init node1 --chain-id {0}".format(chain_id)
    plan.exec(
        service_name = "genesis-service",
        recipe = ExecRecipe(
            command=["/bin/sh", "-c", init_cmd]
        )
    )

    # #Replace the genesis.json file
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
        keys_command = "echo -e 'LZeroPassword!\nLZeroPassword!' | cored keys add validator{0} --chain-id {1} --output json".format(i, chain_id)
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
        plan.print("Extracted mnemonic: {0}".format(mnemonic))
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
        amount = "4000000000udevcore"
        gentx_command = "echo -e 'LZeroPassword!\nLZeroPassword!' | cored genesis gentx validator{0} {1} --chain-id {2}".format(i, amount, chain_id)
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

    for i, participant in enumerate(participants):
        node_count = participant["count"]

        for j in range(node_count):

            node_name = "node{0}".format(i + j + 1)

            # Start the node service
            plan.print("Starting node service " + node_name)
            plan.add_service(
                name = node_name,
                config = ServiceConfig(
                    image=participant['image'],
                    files={},
                    # ports = {
                    #     "rcp": PortSpec(number = 26656, transport_protocol = "TCP"),
                    #     "p2p": PortSpec(number = 26657, transport_protocol = "TCP"),
                    #     "grpc": PortSpec(number = 9090, transport_protocol = "TCP"),
                    #     "grpcWeb": PortSpec(number = 9091, transport_protocol = "TCP"),
                    #     "api": PortSpec(number = 1317, transport_protocol = "TCP"),
                    #     "pProf": PortSpec(number = 6060, transport_protocol = "TCP"),
                    #     "prometheus": PortSpec(number = 26660, transport_protocol = "TCP")
                    # }
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

            # TODO Peering

            # TODO: Start each node
            # start_cmd = "cored start --chain-id " + chain_id
            # plan.exec(
            #     service_name = node_name,
            #     recipe = ExecRecipe(
            #         command = ["/bin/sh", "-c", start_cmd]
            #     )
            # )

            plan.print("{0} started successfully with chain ID {1}".format(node_name, chain_id))
