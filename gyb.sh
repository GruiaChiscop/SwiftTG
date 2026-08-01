API_ID="$1" API_HASH="$2" gyb --line-directive '' \
    -o BetterTG/Secret/Secret.swift \
    templates/Secret.swift.gyb
