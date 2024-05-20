def launch_network(plan, genesis_files, parsed_args):
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
        for participant in chain["participants"]:
            for _ in range(participant["count"]):
                node_counter += 1
                node_name = "{}-node{}".format(chain_name, node_counter)
                node_id, node_ip =  setup_node(plan, node_name, participant, binary,cored_args, config_folder, genesis_file, mnemonics, faucet_data, node_counter == 1)
                node_info.append({"name": node_name, "node_id": node_id, "ip": node_ip})

        start_nodes(plan, node_info, binary, cored_args)

def setup_node(plan, node_name, participant, binary, cored_args, config_folder, genesis_file, mnemonics, faucet_data, is_first_node):
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
                "grpcWeb": PortSpec(number=9091, transport_protocol="TCP", wait=None),
                "api": PortSpec(number=1317, transport_protocol="TCP", wait=None),
                "pProf": PortSpec(number=6060, transport_protocol="TCP", wait=None),
                "prometheus": PortSpec(number=26660, transport_protocol="TCP", wait=None)
            }
        )
    )

    # Recover the validator key
    mnemonic = mnemonics.pop(0)
    recover_key(plan, node_name, mnemonic, binary, cored_args)

    # Initialize the node
    node_id = init_node(plan, node_name, mnemonic, binary, cored_args)

    # Move the genesis file
    move_genesis(plan, node_name, config_folder)

    # If the first node, set up faucet
    if is_first_node and faucet_data:
        setup_faucet(plan, node_name, faucet_data, binary, cored_args)

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

def start_nodes(plan, node_info, binary, cored_args):
    first_node = node_info[0]
    first_node_id = first_node["node_id"]
    first_node_ip = first_node["ip"]
    seed_address = "{}@{}:26656".format(first_node_id, first_node_ip)

    for node in node_info:
        node_name = node["name"]
        if node_name == first_node["name"]:
            seed_options = "--p2p.seeds ''"
        else:
            seed_options = "--p2p.seeds {}".format(seed_address)

        rpc_options = "--rpc.laddr tcp://0.0.0.0:26657 --grpc.address 0.0.0.0:9090"
        start_command = "nohup {} start {} {} {} > /dev/null 2>&1 &".format(binary, rpc_options, seed_options, cored_args)

        plan.exec(
            service_name=node_name,
            recipe=ExecRecipe(
                command=["/bin/sh", "-c", start_command]
            )
        )
        plan.print("{} started successfully".format(node_name))

        # cored start --rpc.laddr tcp://0.0.0.0:26657 --grpc.address 0.0.0.0:9090 --p2p.seeds '' --chain-id coreum-devnet-1