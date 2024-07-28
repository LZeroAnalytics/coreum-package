def launch_faucet(plan, chain_name, chain_id, mnemonic, transfer_amount):

    # Get first node
    first_node = plan.get_service(
        name = "{}-node-1".format(chain_name)
    )

    mnemonic_data = {
        "Mnemonic": mnemonic
    }

    mnemonic_file = plan.render_templates(
        config = {
            "mnemonic.txt": struct(
                template = read_file("templates/mnemonic.txt.tmpl"),
                data = mnemonic_data
            )
        },
        name="{}-faucet-mnemonic-file".format(chain_name)
    )

    plan.add_service(
        name="{}-faucet".format(chain_name),
        config = ServiceConfig(
            image = "tiljordan/coreum-faucet:prod",
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
                "faucet --monitoring-address :8091 --address :8090 --chain-id " + chain_id + " --key-path-mnemonic /tmp/mnemonic/mnemonic.txt --node http://" + first_node.ip_address + ":" + str(first_node.ports["grpc"].number) + " --transfer-amount " + str(transfer_amount)
            ]
        )
    )