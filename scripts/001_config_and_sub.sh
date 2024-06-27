#!/bin/sh
set -x

# TOPIC="nesa-peer-list"
TOPIC="/dns4/2.tcp.ngrok.io/tcp/19093/p2p/12D3KooWRDMhmSSCFvbieLXGX8JA7Wxmt5r8kvm7FHLJkUFJtMRW"
ipfs config Addresses.API /ip4/0.0.0.0/tcp/5001
ipfs config Addresses.Gateway /ip4/0.0.0.0/tcp/8080
ipfs config Addresses.Swarm --json '["/ip4/0.0.0.0/tcp/4001", "/ip6/::/tcp/4001"]'
ipfs config Pubsub.Router gossipsub


update_peers() {
  PEER_LIST=$1

  echo "$PEER_LIST" | jq -r '.[]' | while read -r PEER; do
    ipfs swarm connect $PEER
  done
}

ipfs pubsub sub $TOPIC | while read -r PEER_LIST; do
  update_peers "$PEER_LIST"
done