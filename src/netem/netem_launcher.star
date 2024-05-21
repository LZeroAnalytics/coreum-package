# src/netem/netem_launcher.star

def launch_netem(plan, chain_name, netem_config):
    toxiproxy_image = netem_config.get("image", "ghcr.io/shopify/toxiproxy")
    network_conditions = netem_config.get("network_conditions", [])

    plan.print("Launching netem for chain {}".format(chain_name))

    toxiproxy_service_name = "{}-netem".format(chain_name)

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
        plan.print("Applying network condition: {} on port {}".format(condition['name'], listen_port))
        plan.exec(
            service_name=toxiproxy_service_name,
            recipe=ExecRecipe(
                command=[
                    "/toxiproxy-cli",
                    "create",
                    "--listen",
                    "0.0.0.0:{}".format(listen_port),
                    "--upstream",
                    "{}:{}".format(condition['target_service'], condition['target_port']),
                    condition["name"]
                ]
            )
        )
        for toxic in condition.get("toxics", []):
            plan.exec(
                service_name=toxiproxy_service_name,
                recipe=ExecRecipe(
                    command=[
                        "/toxiproxy-cli",
                        "toxic",
                        "add",
                        "--type",
                        toxic["type"],
                        "--toxicity",
                        str(toxic["toxicity"]),
                        "--attributes",
                        ",".join(["{}={}".format(k, v) for k, v in toxic["attributes"].items()]),
                        condition["name"],
                    ]
                )
            )

    return toxiproxy_service_name
