input_parser = import_module("./src/package_io/input_parser.star")
genesis_generator = import_module("./src/genesis-generator/genesis_generator.star")
prometheus = import_module("./src/prometheus/prometheus_launcher.star")
grafana = import_module("./src/grafana/grafana_launcher.star")
bdjuno = import_module("./src/bdjuno/bdjuno_launcher.star")
faucet = import_module("./src/faucet/faucet_launcher.star")
hermes = import_module("./src/hermes/hermes_launcher.star")
network_launcher = import_module("./src/network_launcher/network_launcher.star")
locust = import_module("./src/locust/locust_launcher.star")

def run(plan, args):

    parsed_args = input_parser.input_parser(args)

    genesis_files = genesis_generator.generate_genesis_files(plan, parsed_args)

    networks = network_launcher.launch_network(plan, genesis_files, parsed_args)

    service_launchers = {
        "prometheus": prometheus.launch_prometheus,
        "grafana": grafana.launch_grafana,
        "faucet": faucet.launch_faucet,
        "bdjuno": bdjuno.launch_bdjuno,
        "spammer": locust.launch_locust
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
        # plan.wait(
        #     service_name = node_names[0],
        #     recipe = GetHttpRequestRecipe(
        #         port_id = "rpc",
        #         endpoint = "/status",
        #         extract = {
        #             "block": ".result.sync_info.latest_block_height"
        #         }
        #     ),
        #     field = "extract.block",
        #     assertion = ">=",
        #     target_value = "1",
        #     interval = "1s",
        #     timeout = "1m",
        #     description = "Waiting for first block for chain " + chain_name
        # )
        plan.run_python(
            description="Waiting for first block",
            run="""
import time
time.sleep(20)
""",
        )

        prometheus_url = None

        for service in service_launchers:
            if service in additional_services:
                plan.print("Launching {} for chain {}".format(service, chain_name))
                if service == "prometheus":
                    prometheus_url = service_launchers[service](plan, node_names, chain_name, chain["prometheus"]["server_url"], chain["prometheus"]["base_path"])
                    if chain["prometheus"]["server_url"] != "" and chain["grafana"]["server_url"] != "":
                        prometheus_url = chain["prometheus"]["server_url"]
                elif service == "grafana":
                    service_launchers[service](plan, prometheus_url, chain_name, chain["grafana"]["server_url"])
                elif service == "faucet":
                    faucet_mnemonic = genesis_files[chain_name]["faucet"]["mnemonic"]
                    transfer_amount = chain["faucet"]["transfer_amount"]
                    service_launchers[service](plan, chain_name, chain_id, faucet_mnemonic, transfer_amount)
                elif service == "spammer":
                    locust.launch_locust(plan, node_names, genesis_files[chain_name]["addresses"], genesis_files[chain_name]["mnemonics"], chain["spammer"]["tps"], chain)
                elif service == "bdjuno":
                    service_launchers[service](plan, chain_name, chain["denom"], chain["block_explorer"])


    for connection in parsed_args["connections"]:
        hermes.launch_hermes(plan, connection, genesis_files, parsed_args)

    plan.print(genesis_files)