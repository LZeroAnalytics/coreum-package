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
                command = [
                    "/bin/sh",
                    "-c",
                    "nohup cored start --rpc.laddr tcp://0.0.0.0:26657 --grpc.address 0.0.0.0:9090 --chain-id " + chain_id + " > /dev/null 2>&1 &"
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
