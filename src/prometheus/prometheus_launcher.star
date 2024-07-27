DEFAULT_SCRAPE_INTERVAL = "15s"
MIN_CPU = 0
MAX_CPU = 1000
MIN_MEMORY = 0
MAX_MEMORY = 2048
PROMETHEUS_DEFAULT_SCRAPE_INTERVAL = "5s"

def launch_prometheus(plan, node_names, chain_name, server_url, base_path):
    metrics_jobs = []
    for node_name in node_names:
        node_service = plan.get_service(name=node_name)
        metrics_jobs.append(new_metrics_job(
            job_name=node_name,
            endpoint="{}:26660".format(node_service.ip_address),
            metrics_path="/metrics",
            scrape_interval="5s"
        ))

    prometheus_url = run_prometheus(
        plan,
        metrics_jobs,
        name="{}-prometheus".format(chain_name),
        config_template_path="./templates/prometheus.yml.tmpl",
        server_url=server_url,
        base_path=base_path
    )

    return prometheus_url

def run_prometheus(plan, metrics_jobs, name, config_template_path, server_url, base_path):
    prometheus_config_template = read_file(src=config_template_path)

    prometheus_config_data = {
        "MetricsJobs": get_metrics_jobs(metrics_jobs)
    }

    prom_config_files_artifact = plan.render_templates(
        config={
            "prometheus-config.yml": struct(
                template=prometheus_config_template,
                data=prometheus_config_data,
            )
        },
        name="{}-config".format(name),
    )

    prometheus_service = plan.add_service(
        name=name,
        config=ServiceConfig(
            image="prom/prometheus:latest",
            ports={
                "http": PortSpec(
                    number=9090,
                    transport_protocol="TCP",
                    application_protocol="http",
                )
            },
            files={
                "/config": prom_config_files_artifact,
            },
            cmd=[
                "--config.file=/config/prometheus-config.yml",
                "--storage.tsdb.path=/prometheus",
                "--storage.tsdb.retention.time=1d",
                "--storage.tsdb.retention.size=512MB",
                "--storage.tsdb.wal-compression",
                "--web.console.libraries=/etc/prometheus/console_libraries",
                "--web.console.templates=/etc/prometheus/consoles",
                "--web.enable-lifecycle",
                "--web.external-url=" + server_url,
                "--web.route-prefix=" + base_path
            ],
            min_cpu=MIN_CPU,
            max_cpu=MAX_CPU,
            min_memory=MIN_MEMORY,
            max_memory=MAX_MEMORY,
        )
    )

    prometheus_service_ip_address = prometheus_service.ip_address
    prometheus_service_http_port = prometheus_service.ports["http"].number

    return "http://{}:{}".format(prometheus_service_ip_address, prometheus_service_http_port)

def new_metrics_job(job_name, endpoint, metrics_path, labels={}, scrape_interval=PROMETHEUS_DEFAULT_SCRAPE_INTERVAL):
    return {
        "Name": job_name,
        "Endpoint": endpoint,
        "MetricsPath": metrics_path,
        "Labels": labels,
        "ScrapeInterval": scrape_interval,
    }

def get_metrics_jobs(service_metrics_configs):
    metrics_jobs = []
    for metrics_config in service_metrics_configs:
        if "Name" not in metrics_config:
            fail("Name not provided in metrics config.")
        if "Endpoint" not in metrics_config:
            fail("Endpoint not provided in metrics config")

        labels = {}
        if "Labels" in metrics_config:
            labels = metrics_config["Labels"]

        metrics_path = "/metrics"
        if "MetricsPath" in metrics_config:
            metrics_path = metrics_config["MetricsPath"]

        scrape_interval = DEFAULT_SCRAPE_INTERVAL
        if "ScrapeInterval" in metrics_config:
            scrape_interval = metrics_config["ScrapeInterval"]

        metrics_jobs.append({
            "Name": metrics_config["Name"],
            "Endpoint": metrics_config["Endpoint"],
            "Labels": labels,
            "MetricsPath": metrics_path,
            "ScrapeInterval": scrape_interval,
        })

    return metrics_jobs