def launch_locust(plan, node_names, addresses, mnemonics, transactions_per_second, chain):

    chain_name = chain["name"]
    chain_id = chain["chain_id"]

    node_urls = []
    api_urls = []

    node_name = node_names[0]
    node_service = plan.get_service(name=node_name)
    node_url = "http://" + node_service.ip_address + ":" + str(node_service.ports["rpc"].number)
    api_url = "http://" + node_service.ip_address + ":" + str(node_service.ports["api"].number)
    node_urls.append(node_url)
    api_urls.append(api_url)

    workload = 0 if transactions_per_second == 0 else (1 / transactions_per_second)

    address_prefix = "devcore"
    if chain["type"] == "gaia":
        address_prefix = "cosmos"
    elif chain_id == "coreum-mainnet-1":
        address_prefix = "core"
    elif chain_id == "coreum-testnet-1":
        address_prefix = "testcore"

    locust_runner_data = {
        "Addresses": json.encode(addresses),
        "Mnemonics": json.encode(mnemonics),
        "NodeURLs": json.encode(node_urls),
        "APIURLs": json.encode(api_urls),
        "ChainID": chain_id,
        "Denom": chain["denom"]["name"],
        "Prefix": address_prefix,
        "MinGasFee": chain["modules"]["feemodel"]["min_gas_price"] * 200000,
        "Workload": workload,
        "Coin": 990 if chain["type"] == "coreum" else 118
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

    if transactions_per_second != 0:
        # Execute the Locust command in headless mode
        plan.exec(
            service_name="{}-locust-service".format(chain_name),
            recipe=ExecRecipe(
                command=["/bin/sh", "-c", "nohup locust -f /mnt/locust_runner.py --headless -u 1 -r 1 > locust.log 2>&1 &"]
            )
        )

    return locust_service