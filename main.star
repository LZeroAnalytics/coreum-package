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
                template = read_file("github.com/LZeroAnalytics/coreum/templates/genesis.json.tmpl"),
                data = genesis_data
            )
        }
    )

    files = {
        "/tmp/genesis.json": genesis_file,
    }

    for i, participant in enumerate(participants):
        node_count = participant["count"]

        node_name = "node{0}".format(i + 1)

        # Initialize the node
        plan.print(f"Initialising {node_name}")
        init_cmd = f"cored init {node_name} --chain-id {chain_id}"
        node_service = plan.add_service(
            name = node_name,
            image = participant['image'],
            cmd = ["/bin/sh", "-c", init_cmd],
            files = files,
            ports = {
                "rcp": PortSpec(number = 26656, transport_protocol = "TCP"),
                "p2p": PortSpec(number = 26657, transport_protocol = "TCP"),
                "grpc": PortSpec(number = 9090, transport_protocol = "TCP"),
                "grpcWeb": PortSpec(number = 9091, transport_protocol = "TCP"),
                "api": PortSpec(number = 1317, transport_protocol = "TCP"),
                "pProf": PortSpec(number = 6060, transport_protocol = "TCP"),
                "prometheus": PortSpec(number = 26660, transport_protocol = "TCP")
            }
        )

        # Replace the genesis.json file
        genesis_path = "/root/.core/{0}/config/genesis.json".format(chain_id)
        move_command = "mv -f /tmp/genesis.json " + genesis_path
        plan.exec(
            service_name = node_name,
            recipe = ExecRecipe(
                command=["/bin/sh", "-c", move_command]
            )
        )

        start_cmd = "cored start --chain-id " + chain_id
        plan.exec_command(node_service, ["/bin/sh", "-c", start_cmd])

        plan.print("{0} started successfully with chain ID {1}".format(node_name, chain_id))
