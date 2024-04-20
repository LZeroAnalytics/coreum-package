# Coreum Package

This is a [Kurtosis][kurtosis-repo] package that will spin up a private Coreum testnet over Docker or Kubernetes. Kurtosis packages are entirely reproducible and composable, so this will work the same way over Docker or Kubernetes, in the cloud or locally on your machine.

You now have the ability to spin up a private Coreum testnet or public devnet/testnet with a single command. This package is designed to be used for testing, validation, and development, and is not intended for production use.

Specifically, this [package][package-reference] will:

1. Generate genesis information using [cored](https://github.com/CoreumFoundation/coreum)
2. Spin up a Coreum network of *n* size using the genesis data generated above

## Quickstart

#### Install
1. [Install Docker & start the Docker Daemon if you haven't done so already][docker-installation]
2. [Install the Kurtosis CLI, or upgrade it to the latest version if it's already installed][kurtosis-cli-installation]

#### Run with your own configuration

Kurtosis packages are parameterizable, meaning you can customize your network and its behavior to suit your needs by storing parameters in a file that you can pass in at runtime like so:

```bash
kurtosis run --enclave my-testnet github.com/LZeroAnalytics/coreum-package --args-file network_params.yaml
```

Where `network_params.yaml` contains the parameters for your network in your home directory. You can also use the [sample configuration file](samples/coreum_testnet.yml).

#### Run on Kubernetes

Kurtosis packages work the same way over Docker or on Kubernetes. Please visit our [Kubernetes docs](https://docs.kurtosis.com/k8s) to learn how to spin up a private testnet on a Kubernetes cluster.

## Developing On This Package
1. Clone this repository to your local machine:
   ```bash
   git clone https://github.com/LZeroAnalytics/coreum-package.git
   cd coreum-package
   ```

2. To spin up the network, use the following command:
   ```bash
   kurtosis run --enclave my-testnet . --args-file samples/coreum_testnet.yml
   ```

   Replace `samples/coreum_testnet.yml` with the path to your custom configuration YAML file if needed.

## Configuration
An example configuration file can be found under `samples/coreum_testnet.yml`. This file demonstrates how to specify the configuration for spinning up a Coreum network.

````yaml
# The chain id used in the genesis file
# This should be coreum-devnet-1 in order to generate the correct genesis
chain_id: coreum-devnet-1

# The time the network starts
genesis_time: 2024-04-14T12:00:00Z

# The amount to deposit into the faucet account
faucet_amount: 100000000000000

# The minimum amount to stake to become a validator
min_self_delegation: 20000000000

# Minimum amount to be deposited for a governance proposal
min_deposit: 4000000000

# The duration of time validators have to cast their vote on a governance proposal
voting_period: 4h

# Specification of the participants in the network
participants:
  
    # The Docker image that should be used for the Coreum node
  - image: tiljordan/coreum-cored:latest
    
    # Count of nodes to spin up for this participant
    count: 1
````
## Management

The [Kurtosis CLI](https://docs.kurtosis.com/cli) can be used to inspect and interact with the network.

For example, if you need shell access, simply run:

```bash
kurtosis service shell my-testnet $SERVICE_NAME
```

And if you need the logs for a service, simply run:

```bash
kurtosis service logs my-testnet $SERVICE_NAME
```

Check out the full list of CLI commands [here](https://docs.kurtosis.com/cli)
<!------------------------ Only links below here -------------------------------->

[docker-installation]: https://docs.docker.com/get-docker/
[kurtosis-cli-installation]: https://docs.kurtosis.com/install
[kurtosis-repo]: https://github.com/kurtosis-tech/kurtosis
[enclave]: https://docs.kurtosis.com/advanced-concepts/enclaves/
[package-reference]: https://docs.kurtosis.com/advanced-concepts/packages