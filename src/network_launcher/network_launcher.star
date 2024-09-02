netem = import_module("../netem/netem_launcher.star")

def launch_network(plan, genesis_files, parsed_args):
    networks = {}
    for chain in parsed_args["chains"]:
        chain_name = chain["name"]
        chain_type = chain["type"]
        binary = "cored" if chain_type == "coreum" else "gaiad"
        config_folder = "/root/.core/{}/config".format(chain["chain_id"]) if binary == "cored" else "/root/.gaia/config"
        cored_args = "--chain-id {}".format(chain["chain_id"]) if binary == "cored" else ""
        start_args = cored_args

        # Get the genesis file and related data
        genesis_data = genesis_files[chain_name]
        genesis_file = genesis_data["genesis_file"]
        mnemonics = genesis_data["mnemonics"]
        faucet_data = genesis_data.get("faucet", None)

        if binary == "gaiad":
            start_args = "--minimum-gas-prices {}{}".format(chain["modules"]["feemodel"]["min_gas_price"], chain["denom"]["name"])

        # Launch nodes for each participant
        node_counter = 0
        node_info = []
        network_conditions = []
        netem_enabled = False
        first_node_id = ""
        first_node_ip = ""
        for participant in chain["participants"]:
            for _ in range(participant["count"]):
                node_counter += 1
                node_name = "{}-node-{}".format(chain_name, node_counter)
                mnemonic = mnemonics[node_counter - 1]

                ssl_enabled = participant.get("ssl", False)

                latency = participant.get("latency", 0)
                jitter = participant.get("jitter", 0)
                if latency > 0:
                    netem_enabled = True

                # Start seed node
                if node_counter == 1:
                    first_node_id, first_node_ip =  start_node(plan, node_name, netem_enabled, participant, binary, cored_args, start_args, config_folder, genesis_file, mnemonic, faucet_data, True, first_node_id, first_node_ip, ssl_enabled)
                    node_info.append({"name": node_name, "node_id": first_node_id, "ip": first_node_ip})
                else:
                    # Start normal nodes
                    node_id, node_ip =  start_node(plan, node_name, netem_enabled, participant, binary, cored_args, start_args, config_folder, genesis_file, mnemonic, faucet_data, False, first_node_id, first_node_ip, ssl_enabled)
                    node_info.append({"name": node_name, "node_id": node_id, "ip": node_ip})
                    # Add network condition for this node
                    network_conditions.append({
                        "node_name": node_name,
                        "target_ip": node_ip,
                        "target_port": 26656,
                        "latency": latency,
                        "jitter": jitter
                    })

        # Launch toxiproxy and configure network conditions
        if netem_enabled:
            netem.launch_netem(plan, chain_name, network_conditions)

        networks[chain_name] = node_info

    plan.print(networks)
    return networks

def start_node(plan, node_name, netem_enabled, participant, binary, cored_args, start_args, config_folder, genesis_file, mnemonic, faucet_data, is_first_node, first_node_id, first_node_ip, ssl_enabled):

    # Path where the node ID will be stored
    node_id_file = "/var/tmp/{}.node_id".format(node_name)
    faucet_mnemonic = faucet_data["mnemonic"] if is_first_node and faucet_data else ""

    seed_options = ""
    if not is_first_node:
        proxy_port = (8475 + (int(node_name.split('-')[-1]) - 1)) if netem_enabled else 26656
        seed_address = "{}@{}:{}".format(first_node_id, first_node_ip, proxy_port)
        seed_options = "--p2p.seeds {}".format(seed_address)


    node_config_data = {
        "binary": binary,
        "config_folder": config_folder,
        "genesis_file_path": "/tmp/genesis/genesis.json",
        "mnemonic": mnemonic,
        "faucet_mnemonic": faucet_mnemonic,
        "keyring_flags": "--keyring-backend test",
        "rpc_options": "--rpc.laddr tcp://0.0.0.0:26657 --grpc.address 0.0.0.0:9090 --api.address tcp://0.0.0.0:1317 --api.enable --api.enabled-unsafe-cors",
        "seed_options": seed_options,
        "cored_args": cored_args,
        "start_args": start_args,
        "prometheus_listen_addr": "0.0.0.0:26660",
        "cors_allowed_origins": "*",
        "node_id_file": node_id_file,
        "ssl_enabled": ssl_enabled,
    }

    # Render the start-node.sh script template
    start_node_script = plan.render_templates(
        config={
            "start-node.sh": struct(
                template=read_file("templates/start-node.sh.tmpl"),
                data=node_config_data
            )
        },
        name="{}-start-script".format(node_name)
    )

    if ssl_enabled:
        cert_file = plan.upload_files(
            src ="templates/cert.crt",
            name = "cert.crt",
        )
        key_file = plan.upload_files(
            src ="templates/privkey.key",
            name = "privkey.key",
        )

        files = {
            "/tmp/genesis": genesis_file,
            "/usr/local/bin": start_node_script,
            config_folder: Directory(
                artifact_names=[cert_file, key_file]
            )
        }
    else:
        files = {
            "/tmp/genesis": genesis_file,
            "/usr/local/bin": start_node_script
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
            min_cpu=participant["min_cpu"],
            min_memory=participant["min_memory"],
            cmd=["/bin/sh", "/usr/local/bin/start-node.sh"]
        )
    )

    node_ip = node_service.ip_address
    node_id = extract_node_id(plan, node_name)

    return node_id, node_ip

def extract_node_id(plan, node_name):
    node_id_file = "/var/tmp/{}.node_id".format(node_name)
    init_result = plan.wait(
        service_name = node_name,
        recipe = ExecRecipe(
            command=["/bin/sh", "-c", "cat {}".format(node_id_file)],
            extract={
                "node_id": "fromjson | .node_id"
            }
        ),
        field = "code",
        assertion = "==",
        target_value = 0,
        interval = "1s",
        timeout = "5m",
        description = "Waiting for node {} to initialise".format(node_name)
    )
    return init_result["extract.node_id"]