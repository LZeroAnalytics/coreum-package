def launch_bdjuno(plan, chain_name, denom, be_args):
    postgres_service = launch_postgres_service(plan, chain_name)

    # Get first node
    first_node = plan.get_service(
        name = "{}-node-1".format(chain_name)
    )

    # Launch the bdjuno service
    launch_bdjuno_service(plan, postgres_service, first_node, chain_name, denom)

    # Launch hasura service
    harusa_service = launch_hasura_service(plan, postgres_service, chain_name)

    # Launch big dipper UI block explorer
    big_dipper_service = launch_big_dipper(plan, chain_name, be_args["harusa_url"], be_args["harusa_ws"], be_args["node_rpc_url"], be_args["image"]. be_args["base_path"])

    # Launch nginx reverse proxy to access explorer
    launch_nginx(plan, big_dipper_service, harusa_service, first_node, chain_name)

    plan.print("BdJuno and Hasura started successfully")


def launch_postgres_service(plan, chain_name):

    # Upload SQL schema files to Kurtosis
    schema_files_artifact = plan.upload_files(
        src="github.com/CoreumFoundation/bdjuno/database/schema",
        name="{}-schema-files".format(chain_name)
    )
    postgres_service = plan.add_service(
        name="{}-bdjuno-postgres".format(chain_name),
        config = ServiceConfig(
            image = "postgres:14.5",
            ports = {
                "db": PortSpec(number=5432, transport_protocol="TCP", application_protocol="postgres")
            },
            env_vars = {
                "POSTGRES_USER": "root",
                "POSTGRES_PASSWORD": "password",
                "POSTGRES_DB": "root"
            },
            files = {
                "/tmp/database/schema": schema_files_artifact
            }
        )
    )

    # Command to execute SQL files
    init_db_command = (
            "for file in /tmp/database/schema/*.sql; do " +
            "psql -U root -d root -f $file; " +
            "done"
    )

    plan.exec(
        service_name="{}-bdjuno-postgres".format(chain_name),
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", init_db_command]
        )
    )

    return postgres_service


def launch_bdjuno_service(plan, postgres_service, node_service, chain_name, denom):
    # Render the configuration file
    bdjuno_config_data = {
        "ChainPrefix": denom["display"],
        "NodeIP": node_service.ip_address,
        "PostgresIP": postgres_service.ip_address,
        "PostgresPort": postgres_service.ports["db"].number,
        "RpcPort": node_service.ports["rpc"].number,
        "GrpcPort": node_service.ports["grpc"].number
    }
    bdjuno_config_artifact = plan.render_templates(
        config = {
            "config.yaml": struct(
                template = read_file("templates/config.yaml.tmpl"),
                data = bdjuno_config_data
            )
        },
        name="{}-bdjuno-config".format(chain_name)
    )

    # Retrieve the genesis file
    genesis_file_artifact = plan.get_files_artifact(
        name = "{}-genesis-file".format(chain_name)
    )

    bdjuno_service = plan.add_service(
        name = "{}-bdjuno-service".format(chain_name),
        config = ServiceConfig(
            image = "coreumfoundation/bdjuno:latest",
            ports = {
                "bdjuno": PortSpec(number=26657, transport_protocol="TCP", wait = None)
            },
            files = {
                "/bdjuno/.bdjuno": bdjuno_config_artifact,
                "/tmp/genesis": genesis_file_artifact
            },
            cmd = ["tail", "-f", "/dev/null"], # Override the start command
        )
    )

    # Parse the genesis file
    plan.exec(
        service_name = "{}-bdjuno-service".format(chain_name),
        recipe = ExecRecipe(
            command = ["/bin/sh", "-c", "bdjuno parse genesis-file --genesis-file-path /tmp/genesis/genesis.json --home /bdjuno/.bdjuno"]
        )
    )

    # Start bdjuno
    plan.exec(
        service_name = "{}-bdjuno-service".format(chain_name),
        recipe = ExecRecipe(
            command = ["/bin/sh", "-c", "nohup bdjuno start --home /bdjuno/.bdjuno > /dev/null 2>&1 &"]
        )
    )

    return bdjuno_service


def launch_hasura_service(plan, postgres_service, chain_name):
    hasura_service = plan.add_service(
        name = "{}-hasura".format(chain_name),
        config = ServiceConfig(
            image = "coreumfoundation/hasura:latest",
            ports = {
                "graphql": PortSpec(number=8080, transport_protocol="TCP")
            },
            env_vars = {
                "HASURA_GRAPHQL_UNAUTHORIZED_ROLE": "anonymous",
                "HASURA_GRAPHQL_DATABASE_URL": "postgresql://root:password@" + postgres_service.ip_address + ":" + str(postgres_service.ports["db"].number) + "/root",
                "HASURA_GRAPHQL_ENABLE_CONSOLE": "true",
                "HASURA_GRAPHQL_DEV_MODE": "false",
                "HASURA_GRAPHQL_ENABLED_LOG_TYPES": "startup, http-log, webhook-log",
                "HASURA_GRAPHQL_ADMIN_SECRET": "myadminsecretkey",
                "HASURA_GRAPHQL_METADATA_DIR": "/hasura/metadata",
                "ACTION_BASE_URL": "http://0.0.0.0:3000",
                "HASURA_GRAPHQL_SERVER_PORT": "8080"
            }
        )
    )
    return hasura_service


def launch_big_dipper(plan,chain_name, harusa_url, harusa_ws, node_rpc_url, image, base_path):
    big_dipper_service = plan.add_service(
        name="{}-big-dipper-service".format(chain_name),
        config=ServiceConfig(
            image=image,
            env_vars={
                "NEXT_PUBLIC_CHAIN_TYPE": "devnet",
                "PORT": "3000",
                "NEXT_PUBLIC_GRAPHQL_URL": harusa_url,
                "NEXT_PUBLIC_GRAPHQL_WS": harusa_ws,
                "NEXT_PUBLIC_RPC_WEBSOCKET": node_rpc_url,
                "BASE_PATH": base_path
            },
            ports={
                "ui": PortSpec(number=3000, transport_protocol="TCP", wait=None)
            }
        )
    )

    return big_dipper_service



def launch_nginx(plan, big_dipper_service, harusa_service, node_service, chain_name):
    big_dipper_ip = big_dipper_service.ip_address
    big_dipper_port = big_dipper_service.ports["ui"].number
    node_ip = node_service.ip_address
    node_rpc_port = node_service.ports["rpc"].number
    harusa_ip = harusa_service.ip_address
    harusa_port = harusa_service.ports["graphql"].number

    nginx_config_data = {
        "NodeIP": node_ip,
        "NodePort": node_rpc_port,
        "BdIP": big_dipper_ip,
        "BdPort": big_dipper_port,
        "HarusaIP": harusa_ip,
        "HarusaPort": harusa_port
    }
    nginx_config_artifact = plan.render_templates(
        config = {
            "nginx.conf": struct(
                template = read_file("templates/nginx.conf.tmpl"),
                data = nginx_config_data
            )
        },
        name="{}-nginx-config".format(chain_name)
    )

    plan.add_service(
        name="{}-block-explorer".format(chain_name),
        config=ServiceConfig(
            image="nginx:latest",
            files={
                "/etc/nginx": nginx_config_artifact
            },
            ports={
                "http": PortSpec(number=80, transport_protocol="TCP", application_protocol="http", wait=None)
            },
        )
    )