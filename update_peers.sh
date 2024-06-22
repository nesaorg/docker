#!/bin/bash

# Define the pubsub topic
TOPIC="nesa-peer-list"

while true; do
  PEER_LIST=$(ipfs swarm peers | jq -R -s -c 'split("\n")[:-1]')

  ipfs pubsub pub $TOPIC "$PEER_LIST"

  sleep 60
done