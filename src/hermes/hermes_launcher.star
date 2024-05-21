def launch_hermes(plan, connection, genesis_files, parsed_args):
    chain_a = connection["chain_a"]
    chain_b = connection["chain_b"]
    relayer_config = connection.get("relayer_config", {})
    hermes_image = relayer_config.get("hermes_image", "tiljordan/hermes:latest")

    chain_a_data = genesis_files[chain_a]
    chain_b_data = genesis_files[chain_b]

    chain_a_config = get_chain_config(parsed_args, chain_a)
    chain_b_config = get_chain_config(parsed_args, chain_b)

    chain_a_id = chain_a_config["chain_id"]
    chain_b_id = chain_b_config["chain_id"]

    chain_a_mnemonic = chain_a_data["faucet"]["mnemonic"]
    chain_b_mnemonic = chain_b_data["faucet"]["mnemonic"]

    chain_a_node = plan.get_service(name="{}-node-1".format(chain_a))
    chain_b_node = plan.get_service(name="{}-node-1".format(chain_b))

    chain_a_rpc_url = "http://{}:{}".format(chain_a_node.ip_address, chain_a_node.ports['rpc'].number)
    chain_a_grpc_url = "http://{}:{}".format(chain_a_node.ip_address, chain_a_node.ports['grpc'].number)
    chain_b_rpc_url = "http://{}:{}".format(chain_b_node.ip_address, chain_b_node.ports['rpc'].number)
    chain_b_grpc_url = "http://{}:{}".format(chain_b_node.ip_address, chain_b_node.ports['grpc'].number)

    config_data = {
        "TelemetryPort": 7698,
        "SourceChainID": chain_a_id,
        "SourceRPCURL": chain_a_rpc_url,
        "SourceGRPCURL": chain_a_grpc_url,
        "SourceAccountPrefix": "cosmos" if chain_a_config["type"] == "gaia" else "devcore",
        "SourceMaxGas": chain_a_config["consensus_params"]["block_max_gas"],
        "SourceGasPrice": {
            "Amount": chain_a_config["modules"]["feemodel"]["min_gas_price"],
            "Denom": chain_a_config["denom"]["name"]
        },
        "PeerChainID": chain_b_id,
        "PeerRPCURL": chain_b_rpc_url,
        "PeerGRPCURL": chain_b_grpc_url,
        "PeerAccountPrefix": "cosmos" if chain_b_config["type"] == "gaia" else "devcore",
        "PeerMaxGas": chain_b_config["consensus_params"]["block_max_gas"],
        "PeerGasPrice": {
            "Amount": chain_b_config["modules"]["feemodel"]["min_gas_price"],
            "Denom": chain_b_config["denom"]["name"]
        }
    }

    config_file = plan.render_templates(
        config={
            "config.toml": struct(
                template=read_file("templates/hermes_config.tmpl"),
                data=config_data,
            )
        },
        name="hermes-config-{}-{}".format(chain_a, chain_b),
    )

    plan.add_service(
        name="hermes-{}-{}".format(chain_a, chain_b),
        config=ServiceConfig(
            image=hermes_image,
            files={
                "/root/.hermes": config_file
            },
            ports={
                "telemetry": PortSpec(number=7698, transport_protocol="TCP", wait=None),
            },
            cmd=["sleep", "infinity"]
        ),
    )

    # Import chain A mnemonic
    plan.exec(
        service_name="hermes-{}-{}".format(chain_a, chain_b),
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", "echo '{}' > /root/.hermes/{}-mnemonic".format(chain_a_mnemonic, chain_a)]
        )
    )

    # Recreate chain A account
    chain_a_hd_path = "--hd-path \"m/44'/990'/0'/0/0\"" if chain_a_config["type"] == "coreum" else ""
    plan.exec(
        service_name="hermes-{}-{}".format(chain_a, chain_b),
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", "hermes keys add --chain {} --key-name source-key {} --mnemonic-file /root/.hermes/{}-mnemonic".format(chain_a_id, chain_a_hd_path, chain_a)]
        )
    )

    # Import chain B mnemonic
    plan.exec(
        service_name="hermes-{}-{}".format(chain_a, chain_b),
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", "echo '{}' > /root/.hermes/{}-mnemonic".format(chain_b_mnemonic, chain_b)]
        )
    )

    # Recreate chain B account
    chain_b_hd_path = "--hd-path \"m/44'/990'/0'/0/0\"" if chain_b_config["type"] == "coreum" else ""
    plan.exec(
        service_name="hermes-{}-{}".format(chain_a, chain_b),
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", "hermes keys add --chain {} --key-name peer-key {} --mnemonic-file /root/.hermes/{}-mnemonic".format(chain_b_id, chain_b_hd_path, chain_b)]
        )
    )

    # Create the IBC channel and start Hermes relayer
    plan.exec(
        service_name="hermes-{}-{}".format(chain_a, chain_b),
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", "nohup sh -c 'hermes create channel --a-chain {} --b-chain {} --a-port transfer --b-port transfer --new-client-connection --yes && hermes start' > /dev/null 2>&1 &".format(chain_a_id, chain_b_id)]
        )
    )

    plan.print("Hermes service started successfully for {} <-> {}".format(chain_a, chain_b))

def get_chain_config(parsed_args, chain_name):
    for chain in parsed_args["chains"]:
        if chain["name"] == chain_name:
            return chain