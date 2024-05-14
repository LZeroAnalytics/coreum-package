def launch_gaia(plan, chain_id, minimum_gas_price):

    home_dir = "/root/.gaia"

    plan.add_service(
        name = "gaia",
        config = ServiceConfig(
            image="tiljordan/gaia:v15.2.0",
            files={},
            ports = {
                "p2p": PortSpec(number = 26656, transport_protocol = "TCP", wait = None),
                "rpc": PortSpec(number = 26657, transport_protocol = "TCP", wait = None),
                "grpc": PortSpec(number = 9090, transport_protocol = "TCP", wait = None),
                "api": PortSpec(number = 1317, transport_protocol = "TCP", wait = None),
                "pProf": PortSpec(number = 6050, transport_protocol = "TCP", wait = None),
            }
        )
    )

    # Initialize the Gaia chain
    init_command = (
        "gaiad init node0 --chain-id " + chain_id
    )
    plan.exec(
        service_name="gaia",
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", init_command]
        )
    )

    # Add keys and import mnemonics
    keyring_flags = "--keyring-backend test --keyring-dir " + home_dir

    add_validator_key_command = (
        "gaiad keys add validator --output json " + keyring_flags
    )
    validator_result = plan.exec(
        service_name="gaia",
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", add_validator_key_command],
            extract={
                "address": "fromjson | .address",
                "mnemonic": "fromjson | .mnemonic"
            }
        )
    )

    import_relayer_mnemonic_command = (
        "gaiad keys add relayer --output json " + keyring_flags
    )
    relayer_result = plan.exec(
        service_name="gaia",
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", import_relayer_mnemonic_command],
            extract={
                "address": "fromjson | .address",
                "mnemonic": "fromjson | .mnemonic"
            }
        )
    )

    import_funding_mnemonic_command = (
        "gaiad keys add funding --output json " + keyring_flags
    )
    funding_result = plan.exec(
        service_name="gaia",
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", import_funding_mnemonic_command],
            extract={
                "address": "fromjson | .address",
                "mnemonic": "fromjson | .mnemonic"
            }
        )
    )

    validator_address = validator_result["extract.address"]
    relayer_address = relayer_result["extract.address"]
    funding_address = funding_result["extract.address"]
    validator_mnemonic = validator_result["extract.mnemonic"]
    relayer_mnemonic = relayer_result["extract.mnemonic"]
    funding_mnemonic = funding_result["extract.mnemonic"]

    # Fund the accounts
    fund_accounts_command = "gaiad genesis add-genesis-account {0} 300000000000stake && gaiad genesis add-genesis-account {1} 200000000000stake && gaiad genesis add-genesis-account {2} 100000000000stake".format(validator_address, relayer_address, funding_address)
    plan.exec(
        service_name="gaia",
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", fund_accounts_command]
        )
    )

    # Create validator gentx
    create_gentx_command = (
        "gaiad genesis gentx validator 100000000stake --chain-id " + chain_id + " " + keyring_flags
    )
    plan.exec(
        service_name="gaia",
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", create_gentx_command]
        )
    )

    # Collect gentx
    collect_gentxs_command = (
        "gaiad genesis collect-gentxs"
    )
    plan.exec(
        service_name="gaia",
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", collect_gentxs_command]
        )
    )

    # Start the Gaia node
    start_command = "nohup gaiad start --rpc.laddr tcp://0.0.0.0:26657 --grpc.address 0.0.0.0:9090 --grpc-web.address 0.0.0.0:1317 --minimum-gas-prices " + minimum_gas_price +  " > /dev/null 2>&1 &"
    plan.exec(
        service_name="gaia",
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", start_command]
        )
    )

    return validator_mnemonic, relayer_mnemonic, funding_mnemonic