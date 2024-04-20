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

    addresses = []

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

    # TODO: Generate all validator keys and save seed + address
    # TODO: Run cored genesis add-genesis-account to add accounts to genesis
    # TODO: Run gentx for each validator and run collect-gentxs to get genesis file
    # validator_command = "cored genesis gentx validator0 4000000000udevcore --account-number 0 --chain-id coreum-devnet-1"
    # plan.exec(
    #     service_name = node_name,
    #     recipe = ExecRecipe(
    #         command=["/bin/sh", "-c", validator_command]
    #     )
    # )
    # TODO: Export genesis file

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

            # Add validator key
            plan.print("Adding validator keys for node {0}.".format(node_name))
            keys_command = "echo -e 'LZeroPassword!\nLZeroPassword!' | cored keys add validator{0} --chain-id coreum-devnet-1 --output json".format(i + j)
            key_result = plan.exec(
                service_name=node_name,
                recipe=ExecRecipe(
                    command=["/bin/sh", "-c", keys_command],
                    extract={
                        "validator_address": "fromjson | .address"
                    }
                )
            )

            address = key_result["extract.validator_address"]
            addresses.append(address)

            # Init the Coreum node
            plan.print("Initialising " + node_name)
            init_cmd = "cored init {0} --chain-id {1}".format(node_name, chain_id)
            plan.exec(
                service_name = node_name,
                recipe = ExecRecipe(
                    command=["/bin/sh", "-c", init_cmd]
                )
            )

            #TODO Peering

            # TODO: Start each node
            # start_cmd = "cored start --chain-id " + chain_id
            # plan.exec(
            #     service_name = node_name,
            #     recipe = ExecRecipe(
            #         command = ["/bin/sh", "-c", start_cmd]
            #     )
            # )

    plan.print("{0} started successfully with chain ID {1}".format(node_name, chain_id))
