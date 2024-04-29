def launch_faucet(plan, chain_id):

    # Get first node
    first_node = plan.get_service(
        name = "node1"
    )

    mnemonic_file =  plan.upload_files(
        src = "templates/mnemonic.txt",
        name = "mnemonic-file",
    )

    # TODO: Fix issue with making requests to faucet service
    plan.add_service(
        name="faucet",
        config = ServiceConfig(
            image = "tiljordan/coreum-faucet:latest",
            ports = {
                "api": PortSpec(number=8090, transport_protocol="TCP", wait=None),
                "monitoring": PortSpec(number=8091, transport_protocol="TCP", wait=None)
            },
            files = {
                "/tmp/mnemonic": mnemonic_file
            },
            entrypoint = [
                "bin/sh",
                "-c",
                "faucet --monitoring-address :8091 --address :8090 --chain-id " + chain_id + " --key-path-mnemonic /tmp/mnemonic/mnemonic.txt --node http://" + first_node.ip_address + ":" + str(first_node.ports["grpc"].number) + " --transfer-amount 100000000"
            ]
        )
    )