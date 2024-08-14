netem = import_module("../netem/netem_launcher.star")

def launch_network(plan, genesis_files, parsed_args):
    networks = {}
    for chain in parsed_args["chains"]:
        chain_name = chain["name"]
        chain_type = chain["type"]
        binary = "cored" if chain_type == "coreum" else "gaiad"
        config_folder = "/root/.core/{}/config".format(chain["chain_id"]) if binary == "cored" else "/root/.gaia/config"
        cored_args = "--chain-id {}".format(chain["chain_id"]) if binary == "cored" else ""

        # Get the genesis file and related data
        genesis_data = genesis_files[chain_name]
        genesis_file = genesis_data["genesis_file"]
        mnemonics = genesis_data["mnemonics"]
        faucet_data = genesis_data.get("faucet", None)

        # Launch nodes for each participant
        node_counter = 0
        node_info = []
        network_conditions = []
        netem_enabled = False
        for participant in chain["participants"]:
            for _ in range(participant["count"]):
                node_counter += 1
                node_name = "{}-node-{}".format(chain_name, node_counter)
                mnemonic = mnemonics[node_counter - 1]

                node_id, node_ip =  setup_node(plan, node_name, chain["chain_id"], participant, binary,cored_args, config_folder, genesis_file, mnemonic, faucet_data, node_counter == 1)
                node_info.append({"name": node_name, "node_id": node_id, "ip": node_ip})

                latency = participant.get("latency", 0)
                jitter = participant.get("jitter", 0)

                # Add network condition for this node
                network_conditions.append({
                    "node_name": node_name,
                    "target_ip": node_ip,
                    "target_port": 26656,
                    "latency": latency,
                    "jitter": jitter
                })

                if latency > 0:
                    netem_enabled = True

        if binary == "gaiad":
            cored_args = "--minimum-gas-prices {}{}".format(chain["modules"]["feemodel"]["min_gas_price"], chain["denom"]["name"])

        start_seed_node(plan, node_info, binary, chain["chain_id"], cored_args, chain["spammer"]["tps"])

        # Launch toxiproxy and configure network conditions
        if netem_enabled:
            netem.launch_netem(plan, chain_name, network_conditions)

        start_nodes(plan, chain_name, node_info, binary, chain["chain_id"], cored_args, chain["spammer"]["tps"], netem_enabled)

        networks[chain_name] = node_info
    return networks

def setup_node(plan, node_name, chain_id, participant, binary, cored_args, config_folder, genesis_file, mnemonic, faucet_data, is_first_node):
    # Add genesis file to the node
    files = {
        "/tmp/genesis": genesis_file,
    }

    # Launch the node service
    node_service = plan.add_service(
        name=node_name,
        config=ServiceConfig(
            image=participant["image"],
            files=files,
            ports={
                "p2p": PortSpec(number=26656, transport_protocol="TCP", wait=None),
                "rpc": PortSpec(number=26657, transport_protocol="TCP", wait=None),
                "grpc": PortSpec(number=9090, transport_protocol="TCP", wait=None),
                "grpc-web": PortSpec(number=9091, transport_protocol="TCP", wait=None),
                "api": PortSpec(number=1317, transport_protocol="TCP", wait=None),
                "p-prof": PortSpec(number=6060, transport_protocol="TCP", wait=None),
                "prometheus": PortSpec(number=26660, transport_protocol="TCP", wait=None)
            },
            min_cpu = participant["min_cpu"],
            min_memory = participant["min_memory"]
        )
    )

    # Recover the validator key
    recover_key(plan, node_name, mnemonic, binary, cored_args)

    # Initialize the node
    node_id = init_node(plan, node_name, mnemonic, binary, cored_args)

    # Move the genesis file
    move_genesis(plan, node_name, config_folder)

    # If the first node, set up faucet
    if is_first_node and faucet_data:
        setup_faucet(plan, node_name, faucet_data, binary, cored_args)

    setup_prometheus(plan, node_name, binary, chain_id)
    setup_cors(plan, node_name, binary, chain_id)
    node_ip = node_service.ip_address
    return node_id, node_ip

def recover_key(plan, node_name, mnemonic, binary, cored_args):
    keyring_flags = "--keyring-backend test"
    recover_key_command = "echo -e '{}\n\n' | {} keys add validator --recover {} {}".format(mnemonic, binary, keyring_flags, cored_args)
    plan.exec(
        service_name=node_name,
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", recover_key_command]
        )
    )

def init_node(plan, node_name, mnemonic, binary, cored_args):
    init_cmd = "echo -e '{}\n\n' | {} init validator --recover {}".format(mnemonic, binary, cored_args)
    init_result = plan.exec(
        service_name=node_name,
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", init_cmd],
            extract={
                "node_id": "fromjson | .node_id"
            }
        )
    )

    return init_result["extract.node_id"]

def move_genesis(plan, node_name, config_folder):
    genesis_path = "{}/genesis.json".format(config_folder)
    move_command = "mv -f /tmp/genesis/genesis.json {}".format(genesis_path)
    plan.exec(
        service_name=node_name,
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", move_command]
        )
    )

def setup_faucet(plan, node_name, faucet_data, binary, cored_args):
    faucet_mnemonic = faucet_data["mnemonic"]

    keyring_flags = "--keyring-backend test"
    recover_faucet_command = "echo -e '{}\n\n' | {} keys add faucet --recover {} {}".format(faucet_mnemonic, binary, keyring_flags, cored_args)
    plan.exec(
        service_name=node_name,
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", recover_faucet_command]
        )
    )

def setup_prometheus(plan, node_name, binary, chain_id):
    if binary == "cored":
        config_path = "/root/.core/" + chain_id + "/config/config.toml"
    else:
        config_path = "/root/.gaia/config/config.toml"

    update_prometheus_command = (
            "sed -i 's|^prometheus = false|prometheus = true|' " + config_path + " && " +
            "sed -i 's|^prometheus_listen_addr = \":26660\"|prometheus_listen_addr = \"0.0.0.0:26660\"|' " + config_path
    )

    plan.exec(
        service_name=node_name,
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", update_prometheus_command]
        )
    )

def setup_cors(plan, node_name, binary, chain_id):
    if binary == "cored":
        config_path = "/root/.core/" + chain_id + "/config/config.toml"
    else:
        config_path = "/root/.gaia/config/config.toml"

    # Command to update cors_allowed_origins in config.toml
    update_cors_command = (
            "sed -i 's|^cors_allowed_origins = \\[\\]|cors_allowed_origins = [\"*\"]|' " + config_path
    )

    # Execute the command on the specified node
    plan.exec(
        service_name=node_name,
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", update_cors_command]
        )
    )

def start_seed_node(plan, node_info, binary, chain_id, cored_args, workload):
    node = node_info[0]
    node_name = node["name"]

    config_path = "/root/.core/{}/config/config.toml".format(chain_id) if binary == "cored" else "/root/.gaia/config/config.toml"
    max_subscriptions = workload + len(node_info)

    # Command to replace the values in config.toml
    update_connections_command = "sed -i 's/max_open_connections = .*/max_open_connections = 0/' {0} && sed -i 's/max_subscriptions_per_client = .*/max_subscriptions_per_client = {1}/' {0} && sed -i 's/timeout_broadcast_tx_commit = .*/timeout_broadcast_tx_commit = \"60s\"/' {0}".format(config_path, max_subscriptions)

    plan.exec(
        service_name=node_name,
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", update_connections_command]
        )
    )

    seed_options = "--p2p.seeds ''"
    rpc_options = "--rpc.laddr tcp://0.0.0.0:26657 --grpc.address 0.0.0.0:9090 --api.address tcp://0.0.0.0:1317 --api.enable --api.enabled-unsafe-cors"
    start_command = "nohup {} start {} {} {} > node.log 2>&1 &".format(binary, rpc_options, seed_options, cored_args)
    plan.exec(
        service_name=node_name,
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", start_command]
        )
    )
    plan.print("{} started successfully".format(node_name))

def start_nodes(plan, chain_name, node_info, binary, chain_id, cored_args, workload, netem_enabled):
    first_node = node_info[0]
    first_node_id = first_node["node_id"]

    if netem_enabled:
        peer_ip = plan.get_service(name="{}-netem".format(chain_name)).ip_address
    else:
        peer_ip = first_node["ip"]

    config_path = "/root/.core/{}/config/config.toml".format(chain_id) if binary == "cored" else "/root/.gaia/config/config.toml"
    max_subscriptions = workload + len(node_info)

    for node in node_info:
        node_name = node["name"]
        if node_name != first_node["name"]:
            proxy_port = (8475 + (int(node_name.split('-')[-1]) - 1)) if netem_enabled else 26656
            seed_address = "{}@{}:{}".format(first_node_id, peer_ip, proxy_port)
            seed_options = "--p2p.seeds {}".format(seed_address)

            # Command to replace the values in config.toml
            update_connections_command = "sed -i 's/max_open_connections = .*/max_open_connections = 0/' {0} && sed -i 's/max_subscriptions_per_client = .*/max_subscriptions_per_client = {1}/' {0} && sed -i 's/timeout_broadcast_tx_commit = .*/timeout_broadcast_tx_commit = \"60s\"/' {0}".format(config_path, max_subscriptions)

            plan.exec(
                service_name=node_name,
                recipe=ExecRecipe(
                    command=["/bin/sh", "-c", update_connections_command]
                )
            )

            rpc_options = "--rpc.laddr tcp://0.0.0.0:26657 --grpc.address 0.0.0.0:9090 --api.address tcp://0.0.0.0:1317 --api.enable --api.enabled-unsafe-cors"
            start_command = "nohup {} start {} {} {} > node.log 2>&1 &".format(binary, rpc_options, seed_options, cored_args)
            plan.exec(
                service_name=node_name,
                recipe=ExecRecipe(
                    command=["/bin/sh", "-c", start_command]
                )
            )
            plan.print("{} started successfully".format(node_name))