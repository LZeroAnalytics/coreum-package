prometheus = import_module("github.com/kurtosis-tech/prometheus-package/main.star")

# The min/max CPU/memory that prometheus can use
MIN_CPU = 10
MAX_CPU = 1000
MIN_MEMORY = 128
MAX_MEMORY = 2048

PROMETHEUS_DEFAULT_SCRAPE_INTERVAL = "5s"


def launch_prometheus(plan, node_names):
    # Define the metrics jobs
    metrics_jobs = []
    for node_name in node_names:
        node_service = plan.get_service(name=node_name)
        metrics_jobs.append(
            new_metrics_job(
                job_name=node_name,
                endpoint="{0}:26660".format(node_service.ip_address),
                metrics_path="/metrics",
                scrape_interval="5s"
            )
        )

    # Launch Prometheus
    prometheus_url = prometheus.run(
        plan,
        metrics_jobs,
        min_cpu=MIN_CPU,
        max_cpu=MAX_CPU,
        min_memory=MIN_MEMORY,
        max_memory=MAX_MEMORY
    )

    return prometheus_url


def new_metrics_job(
        job_name,
        endpoint,
        metrics_path,
        labels = {},
        scrape_interval=PROMETHEUS_DEFAULT_SCRAPE_INTERVAL,
):
    return {
        "Name": job_name,
        "Endpoint": endpoint,
        "MetricsPath": metrics_path,
        "Labels": labels,
        "ScrapeInterval": scrape_interval,
    }