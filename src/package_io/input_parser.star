DEFAULT_GENERAL = {
    "chain_id": "coreum-devnet-1",
    "genesis_delay": "20",
    "key_password": "LZeroPassword!"

}

DEFAULT_FAUCET = {
    "mnemonic": "fury gym tooth supply imitate fossil multiply future laundry spy century screen gloom net awake eager illness border hover tennis inspire nation regular ready",
    "address": "devcore1nv9l6qmv3teux3pgl49vxddrcja3c4fejnhz96",
    "faucet_amount": "100000000000000",
    "transfer_amount": "100000000"
}

DEFAULT_STAKING = {
    "min_self_delegation": "20000000000",
    "max_validators": "32",
    "downtime_jail_duration": "60s"
}

DEFAULT_GOVERNANCE = {
    "min_deposit": "4000000000",
    "voting_period": "4h"
}

DEFAULT_ADDITIONAL_SERVICES = [
    "faucet",
    "bdjuno",
    "prometheus",
    "grafana"
]

DEFAULT_PARTICIPANTS = [
    {
        "image": "tiljordan/coreum-cored:latest",
        "account_balance": "100000000000",
        "staking_amount": "20000000000",
        "count": 3
    }
]


def input_parser(input_args):
    # Apply defaults and validate the 'general' settings
    result = {}

    # Apply defaults and validate the 'general' settings
    general = {
        "chain_id": input_args.get("general", {}).get("chain_id", DEFAULT_GENERAL["chain_id"]),
        "genesis_delay": input_args.get("general", {}).get("genesis_delay", DEFAULT_GENERAL["genesis_delay"]),
        "key_password": input_args.get("general", {}).get("key_password", DEFAULT_GENERAL["key_password"])
    }
    result["general"] = general

    # Validate 'general' settings
    if general["chain_id"] != "coreum-devnet-1":
        fail("Currently only coreum-devnet-1 is supported as chain id")


    genesis_delay_int = int(general["genesis_delay"])
    if genesis_delay_int < 0:
        fail("Genesis delay requires a non-negative integer")

    if len(general["key_password"]) < 8 or len(general["key_password"]) > 20:
        fail("Key password must be at between 8 and 20 characters")


    # Apply defaults and validate 'faucet' settings
    faucet = {
        "mnemonic": input_args.get("faucet", {}).get("mnemonic", DEFAULT_FAUCET["mnemonic"]),
        "address": input_args.get("faucet", {}).get("address", DEFAULT_FAUCET["address"]),
        "faucet_amount": input_args.get("faucet", {}).get("faucet_amount", DEFAULT_FAUCET["faucet_amount"]),
        "transfer_amount": input_args.get("faucet", {}).get("transfer_amount", DEFAULT_FAUCET["transfer_amount"])
    }
    result["faucet"] = faucet

    # Validate 'faucet' settings
    if len(faucet["mnemonic"].split()) != 24:
        fail("Mnemonic must consist of exactly 24 words")
    if not faucet["address"].startswith("devcore"):
        fail("Faucet address must start with 'devcore'")
    # faucet requires mnemonic if address is given
    if "address" in input_args.get("faucet", {}) and "mnemonic" not in input_args.get("faucet", {}):
        fail("Faucet address provided without a corresponding mnemonic.")
    if "mnemonic" in input_args.get("faucet", {}) and "address" not in input_args.get("faucet", {}):
        fail("Mnemonic provided without a corresponding faucet address")

    faucet_amount_int = int(faucet["faucet_amount"])
    if faucet_amount_int < 0:
        fail("Faucet amount expects a non-negative integer")

    transfer_amount = int(faucet["transfer_amount"])
    if transfer_amount < 0:
        fail("Transfer amount expects a non-negative integer")


    # Apply defaults and validate 'staking' settings
    staking = {
        "min_self_delegation": input_args.get("staking", {}).get("min_self_delegation", DEFAULT_STAKING["min_self_delegation"]),
        "max_validators": input_args.get("staking", {}).get("max_validators", DEFAULT_STAKING["max_validators"]),
        "downtime_jail_duration": input_args.get("staking", {}).get("downtime_jail_duration", DEFAULT_STAKING["downtime_jail_duration"])
    }
    result["staking"] = staking

    # Validate 'staking' settings
    min_self_delegation = int(staking["min_self_delegation"])
    if min_self_delegation < 0:
        fail("Min self delegation expects a non-negative integer")
    max_validators_int = int(staking["max_validators"])
    if max_validators_int < 2:
        fail("Max validators should be at least 2")
    if not staking["downtime_jail_duration"].endswith(('s', 'm', 'h')):
        fail("Downtime jail duration expects a time string (e.g., '60s', '2m', '1h')")

    # Apply defaults and validate 'governance' settings
    governance = {
        "min_deposit": input_args.get("governance", {}).get("min_deposit", DEFAULT_GOVERNANCE["min_deposit"]),
        "voting_period": input_args.get("governance", {}).get("voting_period", DEFAULT_GOVERNANCE["voting_period"])
    }
    result["governance"] = governance

    # Additional services
    additional_services = input_args.get("additional_services", DEFAULT_ADDITIONAL_SERVICES)
    result.update({"additional_services": additional_services})

    if input_args.get("additional_services") != None:
        if "grafana" in input_args.get("additional_services") and "prometheus" not in input_args.get("additional_services"):
            fail("Grafana service requires prometheus service")

    # Participants
    participants = input_args.get("participants", DEFAULT_PARTICIPANTS)
    result.update({"participants": participants})

    for participant in participants:
        staking_amount = int(participant["staking_amount"])
        account_balance = int(participant["account_balance"])
        if staking_amount < int(staking["min_self_delegation"]):
            fail("Staking amount needs to be at least the min self delegation (default: 20000000000")
        if staking_amount > account_balance:
            fail("Account balance needs to be at least the staking amount")

        count = int(participant["count"])
        if count < 1:
            fail("Participant count needs to be at least 1")

    return result