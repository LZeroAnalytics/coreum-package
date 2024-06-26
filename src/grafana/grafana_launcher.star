IMAGE_NAME = "grafana/grafana:latest"

GRAFANA_DASHBOARDS_DIRPATH_ON_SERVICE = "/var/lib/grafana/dashboards"

MIN_CPU = 0  # Minimum CPU for Grafana
MAX_CPU = 500  # Maximum CPU for Grafana
MIN_MEMORY = 0  # Minimum memory for Grafana in MB
MAX_MEMORY = 1024  # Maximum memory for Grafana in MB

def launch_grafana(plan, prometheus_url, chain_name):
    # Create Grafana configuration and dashboard provisioning artifacts

    grafana_datasource = plan.render_templates(
        config = {
            "datasource.yml": struct(
                template = read_file("templates/datasource.yml.tmpl"),
                data = {"PrometheusURL": prometheus_url}
            )
        },
        name="{}-grafana-datasource".format(chain_name)
    )

    grafana_dashboard_config = plan.upload_files(
        "templates/dashboard.yml",
        name="{}-grafana-dashboard-config".format(chain_name)
    )

    # Upload the custom dashboard JSON file
    grafana_dashboard_artifact = plan.upload_files(
        "templates/cosmos.json",
        name="{}-cosmos-dashboard".format(chain_name)
    )

    # Define the Grafana service configuration
    grafana_service_config = ServiceConfig(
        image=IMAGE_NAME,
        ports={
            "http-port-id": PortSpec(number = 3000, transport_protocol = "TCP", application_protocol = "http", wait = None)
        },
        env_vars={
            "GF_AUTH_ANONYMOUS_ENABLED": "true",
            "GF_AUTH_ANONYMOUS_ORG_ROLE": "Admin"
        },
        files={
            "/etc/grafana/provisioning/datasources": grafana_datasource,
            "/etc/grafana/provisioning/dashboards": grafana_dashboard_config,
            GRAFANA_DASHBOARDS_DIRPATH_ON_SERVICE: grafana_dashboard_artifact
        },
        min_cpu=MIN_CPU,
        max_cpu=MAX_CPU,
        min_memory=MIN_MEMORY,
        max_memory=MAX_MEMORY
    )

    # Add Grafana service to the plan
    grafana_service = plan.add_service("{}-grafana".format(chain_name), grafana_service_config)
    return grafana_service
