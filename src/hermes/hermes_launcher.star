def launch_hermes(plan, coreum_chain_id, gaia_chain_id, coreum_mnemonic, gaia_mnemonic):
    coreum_account_prefix = "devcore"
    coreum_relayer_coin_type = 990
    peer_account_prefix = "cosmos"
    telemetry_port = 7698

    # Get first node
    first_node = plan.get_service(name = "node1")

    # Get gaia node
    gaia_node = plan.get_service(name = "gaia")

    # Get node's rpc and grpc addresses
    coreum_rpc_url = 'http://' + first_node.ip_address + ":" + str(first_node.ports["rpc"].number)
    coreum_grpc_url = 'http://' + first_node.ip_address + ":" + str(first_node.ports["grpc"].number)
    peer_rpc_url = 'http://' + gaia_node.ip_address + ":" + str(gaia_node.ports["rpc"].number)
    peer_grpc_url = 'http://' + gaia_node.ip_address + ":" + str(gaia_node.ports["grpc"].number)

    config_data = {
        "TelemetryPort": telemetry_port,
        "CoreumChainID": coreum_chain_id,
        "CoreumRPCURL": coreum_rpc_url,
        "CoreumGRPCURL": coreum_grpc_url,
        "CoreumAccountPrefix": coreum_account_prefix,
        "CoreumGasPrice": {
            "Amount": "0.0625",
            "Denom": "udevcore"
        },
        "PeerChainID": gaia_chain_id,
        "PeerRPCURL": peer_rpc_url,
        "PeerGRPCURL": peer_grpc_url,
        "PeerAccountPrefix": peer_account_prefix,
        "PeerGasPrice": {
            "Amount": "0.1",
            "Denom": "stake"
        }
    }

    config_file = plan.render_templates(
        config={
            "config.toml": struct(
                template=read_file("templates/hermes_config.tmpl"),
                data=config_data,
            )
        },
        name="hermes-config",
    )

    plan.add_service(
        name="hermes",
        config=ServiceConfig(
            image="tiljordan/hermes:latest",
            files={
                "/root/.hermes": config_file
            },
            ports={
                "telemetry": PortSpec(number=telemetry_port, transport_protocol="TCP", wait=None),
            },
            cmd=["sleep", "infinity"]
        ),
    )

    # Import coreum mnemonic
    plan.exec(
        service_name="hermes",
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", "echo '" + coreum_mnemonic + "' > /root/.hermes/coreum-mnemonic"]
        )
    )

    # Recreate coreum account
    plan.exec(
        service_name="hermes",
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", "hermes keys add --chain " + coreum_chain_id + " --hd-path \"m/44'/" + str(coreum_relayer_coin_type) + "'/0'/0/0\" --mnemonic-file /root/.hermes/coreum-mnemonic"]
        )
    )

    # Wait until first block is produced in cosmos hub
    plan.wait(
        service_name = "gaia",
        recipe = GetHttpRequestRecipe(
            port_id = "rpc",
            endpoint = "/status",
            extract = {
                "block": ".result.sync_info.latest_block_height"
            }
        ),
        field = "extract.block",
        assertion = ">=",
        target_value = "1",
        interval = "1s",
        timeout = "1m",
        description = "Waiting for first cosmos hub block"
    )

    # Import gaia mnemonic
    plan.exec(
        service_name="hermes",
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", "echo '" + gaia_mnemonic + "' > /root/.hermes/peer-mnemonic"]
        )
    )

    # Recreate gaia account
    plan.exec(
        service_name="hermes",
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", "hermes keys add --chain " + gaia_chain_id + " --mnemonic-file /root/.hermes/peer-mnemonic"]
        )
    )

    # Create the IBC channel
    plan.exec(
        service_name="hermes",
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", "hermes create channel --a-chain " + coreum_chain_id + " --b-chain " + gaia_chain_id + " --a-port transfer --b-port transfer --new-client-connection --yes"]
        )
    )

    #Start the Hermes relayer
    plan.exec(
        service_name="hermes",
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", "nohup hermes start > /dev/null 2>&1 &"]
        )
    )

    plan.print("Hermes service started successfully")