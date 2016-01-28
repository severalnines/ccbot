#!/bin/bash

# Uncomment to connect to Slack
#export HUBOT_SLACK_TOKEN=<yourslacktoken>

# Uncomment to connect to Hipchat
#export HUBOT_HIPCHAT_JID=<yourhipchatJID>
#export HUBOT_HIPCHAT_PASSWORD=<yourhipchatpassword>

# Uncomment to connect to Flowdock
#export HUBOT_FLOWDOCK_API_TOKEN=<yourflowdocktoken>

# Uncomment to connect to Campfire
#export HUBOT_CAMPFIRE_ACCOUNT=<yourcampfireaccount>
#export HUBOT_CAMPFIRE_TOKEN=<yourcampfiretoken>
#export HUBOT_CAMPFIRE_ROOMS=<campfirerooms>

# Hubot listens on this http port for external events
export PORT=8081

# CMONRPC integration
export HUBOT_CMONRPC_TOKEN=<cmonprc token>
export HUBOT_CMONRPC_HOST=<cmon host>
export HUBOT_CMONRPC_PORT=9500

./bin/hubot --adapter <youradapter>
