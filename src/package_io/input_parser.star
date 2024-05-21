def read_json_file(file_path):
    local_contents = read_file(src=file_path)
    return json.decode(local_contents)

# Paths to the default JSON files
DEFAULT_COREUM_FILE = "./coreum_defaults.json"
DEFAULT_GAIA_FILE = "./gaia_defaults.json"

DEFAULT_RELAYER_CONFIG = {
    "hermes_image": "tiljordan/hermes:latest"
}

def apply_chain_defaults(chain, defaults):
    # Simple key-value defaults
    chain["name"] = chain.get("name", defaults["name"])
    chain["type"] = chain.get("type", defaults["type"])
    chain["chain_id"] = chain.get("chain_id", defaults["chain_id"])
    chain["genesis_delay"] = chain.get("genesis_delay", defaults["genesis_delay"])
    chain["initial_height"] = chain.get("initial_height", defaults["initial_height"])

    # Nested defaults
    chain["denom"] = chain.get("denom", {})
    for key, value in defaults["denom"].items():
        chain["denom"][key] = chain["denom"].get(key, value)

    chain["faucet"] = chain.get("faucet", {})
    for key, value in defaults["faucet"].items():
        chain["faucet"][key] = chain["faucet"].get(key, value)

    chain["consensus_params"] = chain.get("consensus_params", {})
    for key, value in defaults["consensus_params"].items():
        chain["consensus_params"][key] = chain["consensus_params"].get(key, value)

    chain["modules"] = chain.get("modules", {})
    for module, module_defaults in defaults["modules"].items():
        chain["modules"][module] = chain["modules"].get(module, {})
        for key, value in module_defaults.items():
            chain["modules"][module][key] = chain["modules"][module].get(key, value)

    # Apply defaults to participants
    if "participants" not in chain:
        chain["participants"] = defaults["participants"]
    else:
        default_participant = defaults["participants"][0]
        participants = []
        for participant in chain["participants"]:
            for key, value in default_participant.items():
                participant[key] = participant.get(key, value)
            participants.append(participant)
        chain["participants"] = participants

    # Apply defaults to additional services
    if "additional_services" not in chain:
        chain["additional_services"] = defaults["additional_services"]
    else:
        if "faucet" in chain["additional_services"] and chain["type"] == "gaia":
            fail("Gaia does not support the faucet service currently.")

    return chain

def validate_input_args(input_args):
    if not input_args or "chains" not in input_args:
        fail("Input arguments must include the 'chains' field.")

    chain_names = []
    for chain in input_args["chains"]:
        if "name" not in chain or "type" not in chain:
            fail("Each chain must specify a 'name' and a 'type'.")
        if chain["name"] in chain_names:
            fail("Duplicate chain name found: " + chain["name"])
        if chain["type"] != "coreum" and chain["type"] != "gaia":
            fail("Unsupported chain type: "+ chain["type"])
        chain_names.append(chain["name"])

    for connection in input_args.get("connections", []):
        if connection["chain_a"] not in chain_names:
            fail("Connection specified with unknown chain name: " + connection["chain_a"])
        if connection["chain_b"] not in chain_names:
            fail("Connection specified with unknown chain name: " + connection["chain_b"])
        if connection["chain_a"] == connection["chain_b"]:
            fail("Connection cannot be made from a chain to itself: " + connection["chain_a"])

def input_parser(input_args=None):
    coreum_defaults = read_json_file(DEFAULT_COREUM_FILE)
    gaia_defaults = read_json_file(DEFAULT_GAIA_FILE)

    result = {"chains": [], "connections": []}

    if not input_args:
        input_args = {"chains": [coreum_defaults]}

    validate_input_args(input_args)

    if "chains" not in input_args:
        result["chains"].append(coreum_defaults)
    else:
        for chain in input_args["chains"]:
            chain_type = chain.get("type", "coreum")
            if chain_type == "coreum":
                defaults = coreum_defaults
            elif chain_type == "gaia":
                defaults = gaia_defaults
            else:
                fail("Unsupported chain type: " + chain_type)

            # Apply defaults to chain
            chain_config = apply_chain_defaults(chain, defaults)
            result["chains"].append(chain_config)

    # Process connections with default relayer_config
    for connection in input_args.get("connections", []):
        if "relayer_config" not in connection:
            connection["relayer_config"] = DEFAULT_RELAYER_CONFIG
        result["connections"].append(connection)

    return result