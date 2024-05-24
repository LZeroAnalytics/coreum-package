def launch_locust(plan, addresses, mnemonics, transactions_per_second, chain):

    chain_name = chain["name"]
    chain_id = chain["chain_id"]


    first_node = plan.get_service(
        name = "{}-node-1".format(chain_name)
    )

    workload = 0 if transactions_per_second == 0 else (1 / transactions_per_second)

    locust_runner_data = {
        "Addresses": json.encode(addresses),
        "Mnemonics": json.encode(mnemonics),
        "NodeURL": "http://" + first_node.ip_address + ":" + str(first_node.ports["rpc"].number),
        "APIURL": "http://" + first_node.ip_address + ":" + str(first_node.ports["api"].number),
        "ChainID": chain_id,
        "Denom": chain["denom"]["name"],
        "Prefix": "cosmos" if chain["type"] == "gaia" else "devcore",
        "MinGasFee": chain["modules"]["feemodel"]["min_gas_price"] * 100000,
        "Workload": workload
    }

    locust_runner_file = plan.render_templates(
        config = {
            "locust_runner.py": struct(
                template = read_file("templates/locust_runner.py.tmpl"),
                data = locust_runner_data
            )
        },
        name="{}-locust-runner".format(chain_name)
    )


    # Define the service configuration for Locust
    locust_service_config = ServiceConfig(
        image="tiljordan/locust",
        ports={
        },
        files={
            "/mnt": locust_runner_file
        },
        entrypoint=["locust", "-f", "/mnt/locust_runner.py"]
    )

    # Start the Locust service
    locust_service = plan.add_service(
        name="{}-locust-service".format(chain_name),
        config=locust_service_config
    )

    # Execute the Locust command in headless mode
    plan.exec(
        service_name="{}-locust-service".format(chain_name),
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", "nohup locust -f /mnt/locust_runner.py --headless -u 1 -r 1 > locust.log 2>&1 &"]
        )
    )

    return locust_service