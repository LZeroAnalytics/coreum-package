# Coreum Package

This is a [Kurtosis][kurtosis-repo] package developed by [LZero](https://www.lzeroanalytics.com) that will spin up a private Coreum testnet over Docker or Kubernetes. Kurtosis packages are entirely reproducible and composable, so this will work the same way over Docker or Kubernetes, in the cloud or locally on your machine.

You now have the ability to spin up a private [Coreum](https://www.coreum.com) testnet or public devnet/testnet with a single command. This package is designed to be used for testing, validation, and development, and is not intended for production use.

Specifically, this [package][package-reference] will:

1. Generate a genesis file with prefunded accounts and validators using [cored](https://github.com/CoreumFoundation/coreum)
2. Spin up a Coreum network of *n* size using the genesis data generated above
3. Spin up a Grafana and Prometheus instances to observe the network
4. Launch a [faucet](https://github.com/CoreumFoundation/faucet) service to create funded accounts or fund existing accounts
5. Spin up a [Big Dipper](https://github.com/CoreumFoundation/big-dipper-2.0-cosmos) block explorer instance
## Quickstart


1. [Install Docker & start the Docker Daemon if you haven't done so already][docker-installation]
2. [Install the Kurtosis CLI, or upgrade it to the latest version if it's already installed][kurtosis-cli-installation]
3. Run the package with default configurations from the command line:
   
   ```bash
   kurtosis run --enclave my-testnet github.com/LZeroAnalytics/coreum-package
   ```

#### Run with your own configuration

Kurtosis packages are parameterizable, meaning you can customize your network and its behavior to suit your needs by storing parameters in a file that you can pass in at runtime like so:

```bash
kurtosis run --enclave my-testnet github.com/LZeroAnalytics/coreum-package --args-file network_params.yaml
```

Where `network_params.yaml` contains the parameters for your network in your home directory. You can also use the [sample configuration file](samples/default_config_sample.yml).

#### Run on Kubernetes

Kurtosis packages work the same way over Docker or on Kubernetes. Please visit the [Kubernetes docs](https://docs.kurtosis.com/k8s) to learn how to spin up a private testnet on a Kubernetes cluster.

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

## Debugging

To grab any files generated by the package, simply run:

```bash
kurtosis files download my-testnet $FILE_NAME $OUTPUT_DIRECTORY
```

For example, to retrieve the genesis file, run:

```bash
kurtosis files download my-testnet genesis-file ~/Downloads
```

## Configuration

To configure the package behaviour, you can modify your `network_params.yaml` file. The full YAML schema that can be passed in is as follows with the defaults provided:

````yaml
general:
   # The chain id used in the genesis file
   # This should be coreum-devnet-1 in order to generate the correct genesis
   chain_id: coreum-devnet-1

   # How long you want the network to wait before starting up in seconds
   genesis_delay: 20
   
   # The password use for the key store on each node
   key_password: LZeroPassword!

  # The size of each block in bytes (default: 21MB)
  # Too low decreases the network throughput
  # Too high can cause network instability
  block_size: 22020096
  
  # Total amount of gas that can be consumed by all transactions within a single block
  max_gas: 50000000

# Default parameters for the faucet
faucet:
   # The mnemonic to use for the faucet service
   # If this mnemonic is specified, the corresponding address needs to be specified
   mnemonic: fury gym tooth supply imitate fossil multiply future laundry spy century screen gloom net awake eager illness border hover tennis inspire nation regular ready
   
   # The address of the faucet
   # This address needs to correspond to the specified mnemonic
   address: devcore1nv9l6qmv3teux3pgl49vxddrcja3c4fejnhz96
   
   # The balance of the faucet service
   faucet_amount: 100000000000000
   
   # The amount to transfer for each each /fund request made to the service
   transfer_amount: 100000000

# Default parameters for validators and staking
staking:
   # The minimum amount of stake needed to become a validator
   min_self_delegation: 20000000000
   
   # The maximum number of validators allowed in the network
   max_validators: 32
   
   # The duration after which a validator is jailed after being offline
   downtime_jail_duration: 60s

# Default parameters for governance
governance:
   # The minimum amount to deposit to create a governance proposal
   min_deposit: 4000000000
   
   # The amount of time participants can vote on a proposal
   voting_period: 4h

# Default parameters for Cosmos hub (gaia)
gaia:
   # The chain id of the cosmos hub network
   chain_id: cosmos-lzero-testnet
   
   # The minimum amount of fess required for transactions
   # 0.01 photino tokens required per unit of gas
   # 0.001 stak tokens required per unit of gas
   minimum_gas_price: 0.01photino,0.001stake
   num_validators: 4

# Additional services to launch
# Faucet: Gives access to an api to fund addresses
# Bdjuno: The Big Dipper block explorer based on bdjuno and postgres
# Prometheus: Provides prometheus service for accessing node metrics
# Grafana: Dashboard that pulls data from prometheus
# Gaia: The Cosmos Hub blockchain - spins up one node with three accounts
# Hermes: A IBC relay that connects gaia and the coreum testnet
additional_services:
   - faucet
   - bdjuno
   - prometheus
   - grafana
   - gaia
   - hermes

# Specification of the participants in the network
# Each participant is a template for nodes and allows to create customisable networks
participants:
     # The Docker image that should be used for the Coreum node
   - image: tiljordan/coreum-cored:latest
     
     # The balance of each account (in udevcore)
     account_balance: 100000000000
     
     # The amount that is staked to become a validator
     # Needs to be larger than the minimum self delegation
     staking_amount: 20000000000

     # Count of nodes to spin up for this participant
     count: 3
````

#### Example configurations

The default configurations and all example configurations can be found in the [samples](samples) folder.

<details>
   <summary>A 2-node bare bones Coreum network without additional services</summary>

```yaml
participants:
  - image: tiljordan/coreum-cored:latest
    account_balance: 100000000000
    staking_amount: 20000000000
    count: 2
```
</details>

<details>
   <summary>A 5-node Coreum network with different node images used</summary>

```yaml
additional_services:
  - faucet
  - bdjuno
  - prometheus
  - grafana

participants:
  - image: tiljordan/coreum-cored:latest
    account_balance: 100000000000
    staking_amount: 20000000000
    count: 2
  - image: coreumfoundation/cored:v3.0.3
    account_balance: 200000000000
    staking_amount: 20000000000
    count: 3
```
</details>

<details>
<summary>A 3-node Coreum network with block size of 50MB</summary>

```yaml
general:
  block_size: 52428800

additional_services:
  - faucet
  - bdjuno
  - prometheus
  - grafana

participants:
  - image: tiljordan/coreum-cored:latest
    account_balance: 100000000000
    staking_amount: 20000000000
    count: 3
```
</details>

<details>
<summary>A 2-node Coreum network with gaia and hermes</summary>

```yaml
additional_services:
  - gaia
  - hermes

gaia:
  chain_id: cosmos-lzero-testnet
  minimum_gas_price: 0.1stake

participants:
- image: tiljordan/coreum-cored:latest
  account_balance: 100000000000
  staking_amount: 20000000000
  count: 2
```
</details>

## Faucet service
The faucet service is based on this [repository](https://github.com/CoreumFoundation/faucet).
The faucet service exposes an api that is mapped to a local port on localhost.
The service offers three paths: `/api/faucet/v1/status`, `/api/faucet/v1/fund` and `/api/faucet/v1/gen-funded`. 

`fund`

Send funds to the specified address. Prefunded addresses can be found in the console when running the package.
```bash
curl --location 'http://127.0.0.1:60095/api/faucet/v1/fund' \
--header 'Content-Type: application/json' \
--data '{
    "address": "devcore19tmtuldmuamlzuv4xx704me7ns7yn07crdc4r3"
}'
```
```bash
{
    "txHash":"E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855"
}
```

`gen-funded`

Generate a new funded account. This request requires to pass in the mnemonic address.

```bash
curl --location 'http://localhost:8090/api/faucet/v1/gen-funded' \
--header 'Content-Type: application/json' \
--data '{
    "address": "devcore175m7gdsh9m0rm08a0w3eccz9r895t9jex0abcd"
}'
```
```bash
{
  "txHash": "D039E2E8F4318A3C03F2B51D74E8E8CA8CFAFBC02B67E0A9716340B874347778",
  "mnemonic": "day oyster today mechanic soup happy judge matter output asset tiny bundle galaxy theory witness act adapt company thought shock pole explain orchard surround",
  "address": "devcore1lj597uzf689t0tpfxurhra9q9vtkxldezmtvwh"
}
```

## Developing On This Package
1. Clone this repository to your local machine:
   ```bash
   git clone https://github.com/LZeroAnalytics/coreum-package.git
   cd coreum-package
   ```
   
2. Make your code changes

3. To spin up the network, use the following command:
   ```bash
   kurtosis run --enclave my-testnet . --args-file samples/default_config_sample.yml
   ```

   Replace `samples/default_config_sample.yml` with the path to your custom configuration YAML file if needed.

When you're happy with your changes:

1. Create a PR
2. Add one of the maintainers of the repo as a "Review Request":
   * `tiljrd` (LZero)
   * `mistrz-g` (LZero)
   
3. Once everything works, merge!

<!------------------------ Only links below here -------------------------------->

[docker-installation]: https://docs.docker.com/get-docker/
[kurtosis-cli-installation]: https://docs.kurtosis.com/install
[kurtosis-repo]: https://github.com/kurtosis-tech/kurtosis
[package-reference]: https://docs.kurtosis.com/advanced-concepts/packages