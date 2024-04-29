genesis_generator = import_module("./src/genesis-generator/genesis_generator.star")
prometheus = import_module("./src/prometheus/prometheus_launcher.star")
grafana = import_module("./src/grafana/grafana_launcher.star")
bdjuno = import_module("./src/bdjuno/bdjuno_launcher.star")
faucet = import_module("./src/faucet/faucet_launcher.star")

def run(plan, args):

    # Retrieve params from config file
    chain_id = args["chain_id"]
    genesis_time = args["genesis_time"]
    faucet_amount = args["faucet_amount"]
    min_self_delegation = args["min_self_delegation"]
    min_deposit = args["min_deposit"]
    voting_period = args["voting_period"]
    participants = args["participants"]

    genesis_file, mnemonics = genesis_generator.generate_genesis_file(plan, participants, chain_id, genesis_time, faucet_amount, min_self_delegation, min_deposit, voting_period)

    node_files = {
        "/tmp/genesis": genesis_file,
    }

    node_names = []
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
            recover_key_command = "echo -e '{0}\n{1}\n{1}' | cored keys add validator{2} --recover --chain-id {3}".format(mnemonic, "LZeroPassword!", counter, chain_id)
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

            genesis_path = "/root/.core/{0}/config/genesis.json".format(chain_id)
            move_command = "mv -f /tmp/genesis/genesis.json " + genesis_path
            # Use the preconfigured genesis file
            plan.exec(
                service_name = node_name,
                recipe = ExecRecipe(
                    command=["/bin/sh", "-c", move_command]
                )
            )

            counter += 1

    for (i, node_name) in enumerate(node_names):

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

    node_id = plan.exec(
        service_name = "node1",
        recipe = ExecRecipe(
            command = ["/bin/sh", "-c", "cored tendermint show-node-id --chain-id " + chain_id + " | tr -d '\n'"],
            extract = {
                "node_id" : "",
            }
        )
    )

    first_node_service = plan.get_service(name="node1")

    # Start nodes
    for i, node_name in enumerate(node_names):

        rpc_options = "--rpc.laddr tcp://0.0.0.0:26657 --grpc.address 0.0.0.0:9090 "
        if i == 0:
            seed_options = "--p2p.seeds ''"
        else:
            seed_options = "--p2p.seeds " + node_id["extract.node_id"] + "@" + first_node_service.ip_address + ":" + str(first_node_service.ports["p2p"].number)

        start_command = "nohup cored start " + rpc_options + seed_options + " --chain-id " + chain_id + " > /dev/null 2>&1 &"

        plan.exec(
            service_name = node_name,
            recipe = ExecRecipe(
                command = [
                    "/bin/sh",
                    "-c",
                    start_command
                ]
            )
        )
        plan.print("{0} started successfully with chain ID {1}".format(node_name, chain_id))

    # Start prometheus service
    prometheus_url = prometheus.launch_prometheus(plan, node_names)

    # Start grafana
    grafana.launch_grafana(plan, prometheus_url)

    # Start BDJuno explorer
    bdjuno.launch_bdjuno(plan)

    # Start faucet service
    faucet.launch_faucet(plan, chain_id)