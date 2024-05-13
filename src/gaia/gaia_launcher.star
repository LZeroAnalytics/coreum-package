def launch_gaia(plan, chain_id, minimum_gas_price, num_validators):

    gaiad_start_command = "gaiad testnet start --minimum-gas-prices {0} --chain-id {1} --rpc.address=tcp://0.0.0.0:26657 --grpc.address=0.0.0.0:9090 --api.address=tcp://0.0.0.0:1317 --v 3 --print-mnemonic --log_format json".format(minimum_gas_price, chain_id, num_validators)
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
            },
            cmd = ["/bin/sh", "-c", gaiad_start_command]
        )
    )