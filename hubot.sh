#!/bin/bash

# Token to connect to slack
export HUBOT_SLACK_TOKEN=<yourslacktoken>

# Hubot listens on this http port for external events
export PORT=8081

# CMONRPC integration
export HUBOT_CMONRPC_TOKEN=<cmonprc token>
export HUBOT_CMONRPC_HOST=<cmon host>
export HUBOT_CMONRPC_PORT=9500

./bin/hubot --adapter slack
