def launch_netem(plan, chain_name, network_conditions):
    toxiproxy_image = "ghcr.io/shopify/toxiproxy"

    plan.print("Launching netem for chain {}".format(chain_name))

    toxiproxy_service_name = "{}-netem".format(chain_name)

    seed_node = plan.get_service(name = "{}-node-1".format(chain_name))

    # Collect all the required ports for the proxies
    ports = {}
    base_port = 8475
    for index, condition in enumerate(network_conditions):
        listen_port = base_port + index
        ports["proxy_{}".format(index)] = PortSpec(number=listen_port, transport_protocol="TCP", wait=None)

    plan.add_service(
        name=toxiproxy_service_name,
        config=ServiceConfig(
            image=toxiproxy_image,
            ports=ports
        )
    )

    # Apply network conditions
    for index, condition in enumerate(network_conditions):
        listen_port = base_port + index
        plan.print("Applying network condition for node {}: latency {} ms, jitter {} ms on port {}".format(
            condition['node_name'], condition['latency'], condition['jitter'], listen_port))
        plan.exec(
            service_name=toxiproxy_service_name,
            recipe=ExecRecipe(
                command=[
                    "/toxiproxy-cli",
                    "create",
                    "--listen",
                    "0.0.0.0:{}".format(listen_port),
                    "--upstream",
                    "{}:{}".format(seed_node.ip_address, 26656),
                    condition["node_name"]
                ]
            )
        )
        plan.exec(
            service_name=toxiproxy_service_name,
            recipe=ExecRecipe(
                command=[
                    "/toxiproxy-cli",
                    "toxic",
                    "add",
                    "--type", "latency",
                    "--attribute", "latency={}".format(condition['latency']),
                    "--attribute",  "jitter={}".format(condition['jitter']),
                    condition['node_name'],
                ]
            )
        )

    return toxiproxy_service_name
