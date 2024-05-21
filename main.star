input_parser = import_module("./src/package_io/input_parser.star")
genesis_generator = import_module("./src/genesis-generator/genesis_generator.star")
prometheus = import_module("./src/prometheus/prometheus_launcher.star")
grafana = import_module("./src/grafana/grafana_launcher.star")
bdjuno = import_module("./src/bdjuno/bdjuno_launcher.star")
faucet = import_module("./src/faucet/faucet_launcher.star")
gaia = import_module("./src/gaia/gaia_launcher.star")
hermes = import_module("./src/hermes/hermes_launcher.star")
network_launcher = import_module("./src/network_launcher/network_launcher.star")

def run(plan, args):

    parsed_args = input_parser.input_parser(args)

    genesis_files = genesis_generator.generate_genesis_files(plan, parsed_args)

    networks = network_launcher.launch_network(plan, genesis_files, parsed_args)

    service_launchers = {
        "prometheus": prometheus.launch_prometheus,
        "grafana": grafana.launch_grafana,
        "faucet": faucet.launch_faucet,
        "bdjuno": bdjuno.launch_bdjuno,
        #"hermes": hermes.launch_hermes
    }

    # Launch additional services for each chain
    for chain in parsed_args["chains"]:
        chain_name = chain["name"]
        chain_id = chain["chain_id"]
        additional_services = chain.get("additional_services", [])

        node_info = networks[chain_name]
        node_names = []
        for node in node_info:
            node_names.append(node["name"])

        # Wait until first block is produced before deploying additional services
        plan.wait(
            service_name = node_names[0],
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
            description = "Waiting for first block for chain " + chain_name
        )

        prometheus_url = None

        for service in service_launchers:
            if service in additional_services:
                plan.print("Launching {} for chain {}".format(service, chain_name))
                if service == "prometheus":
                    prometheus_url = service_launchers[service](plan, node_names, chain_name)
                elif service == "grafana":
                    service_launchers[service](plan, prometheus_url, chain_name)
                elif service == "faucet":
                    faucet_mnemonic = genesis_files[chain_name]["faucet"]["mnemonic"]
                    transfer_amount = chain["faucet"]["transfer_amount"]
                    service_launchers[service](plan, chain_name, chain_id, faucet_mnemonic, transfer_amount)
                elif service == "hermes":
                    other_chain_id = parsed_args["chains"][1]["chain_id"] if len(parsed_args["chains"]) > 1 else None
                    mnemonics = genesis_files[chain_name]["mnemonics"]
                    relayer_mnemonic = genesis_files.get(parsed_args["chains"][1]["name"], {}).get("mnemonics")[0] if other_chain_id else None
                    if relayer_mnemonic:
                        service_launchers[service](plan, chain_id, other_chain_id, mnemonics[0], relayer_mnemonic)
                else:
                    service_launchers[service](plan, chain_name)

    plan.print(genesis_files)
    # prometheus_url = None
    # validator_mnemonic = None
    # relayer_mnemonic = None
    # funding_mnemonic = None
    # # Map service names to their respective launch functions
    # service_launchers = {
    #     "prometheus": lambda: prometheus.launch_prometheus(plan, node_names),
    #     "grafana": lambda: grafana.launch_grafana(plan, prometheus_url) if prometheus_url else None,
    #     "bdjuno": lambda: bdjuno.launch_bdjuno(plan),
    #     "faucet": lambda: faucet.launch_faucet(plan, chain_id, faucet_mnemonic, transfer_amount),
    #     "gaia": lambda: gaia.launch_gaia(plan, gaia_args["chain_id"], gaia_args["minimum_gas_price"]),
    #     "hermes": lambda: hermes.launch_hermes(plan, chain_id, gaia_args["chain_id"], mnemonics[0], relayer_mnemonic) if relayer_mnemonic else None
    # }
    #
    #
    # for service in service_launchers:
    #     if service in additional_services:
    #         if service == "prometheus":
    #             prometheus_url = service_launchers[service]()
    #         elif service == "gaia":
    #             validator_mnemonic, relayer_mnemonic, funding_mnemonic = service_launchers[service]()
    #         else:
    #             service_launchers[service]()
    #
    # plan.print("Coreum network launched successfully with these accounts")
    # plan.print(addresses)
    #
    # if "gaia" in additional_services:
    #     plan.print("Gaia network launched successfully with these mnemonics")
    #     plan.print([validator_mnemonic, relayer_mnemonic, funding_mnemonic])