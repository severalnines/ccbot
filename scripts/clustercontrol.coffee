# Description:
#   Hubot integration with Severalnines ClusterControl.
#
# Configuration:
#  HUBOT_RPC_TOKEN
#  HUBOT_RPC_HOST
#  HUBOT_RPC_PORT
#
# Commands:
#   hubot status - Lists the clusters in ClusterControl and shows their status
#   hubot backup cluster <clusterid> - Schedules a back for an entire cluster using xtrabackup
#   hubot backup cluster <clusterid> schema <schema> - Schedules a backup for a single schema using mysqldump
#
# Scheduling backups with create an event that follows the job until this has finished or failed
#
# On start up the bot will keep track of the state of all clusters and alert if something changes
# 
# Authors:
#   Art van Scheppingen (art@severalnines.com)
#

config = require '../config/config'

module.exports = (robot) ->

  # Fetches the status of the clusters
  robot.respond /status/i, (res) ->
    clusterUrl = "http://" + config.cmonrpcHost + ":" + config.cmonrpcPort + "/0/clusters"

    POSTDATA = JSON.stringify ({
      token: config.cmonrpcToken 
    })
    @robot.http(clusterUrl)
      .header('Content-Type', 'application/json')
      .post(POSTDATA) (err, list, body) ->
        if body
          data = JSON.parse body
          for clusterid, cluster of data.data
            res.send "#{cluster.name}: #{cluster.statusText}"
            if cluster.status > 2
              POSTDATA = '{ "token": "ABCDEFGHIJKLMNOP", "operation": "getHosts" }' 
              robot.http("http://localhost:9500/" + cluster.id + "/stat")
                .header('Content-Type', 'application/json')
                .post(POSTDATA) (err, list, body) ->
                  if list.statusCode is 200
                    try
                      clusterdata = JSON.parse body
                      for hostid, host of clusterdata.data
                        if host.connected == false
                          res.send "#{host.hostname}: #{host.description} (#{host.nodetype})"
                    catch error
                      console.log(error)

  # Schedules a backup of a host or a schema
  # Either backups a full host or only a single schema (1 or 3 arguments)
  robot.respond /backup cluster (.*)/i, (res) ->
    if args = robot.getArguments(res.envelope.user, res.match[1], 3)
      # First arg is the clusterid
      clusterid = args[0]
      if args.length == 3
        backuptype = 'mysqldump'
        backupschema = args[2]
      else
        if args.length == 1
          backuptype = 'xtrabackupfull'
          backupschema = ''
      #Find the host in the cluster without an error
      url = "http://" + config.cmonrpcHost + ":" + config.cmonrpcPort + "/" + clusterid + "/stat"
      POSTDATA = JSON.stringify ({
        token: config.cmonrpcToken 
        operation: "getHosts"
      })
      robot.http(url)
        .header('Content-Type', 'application/json')
        .post(POSTDATA) (err, list, body) ->
          if list.statusCode is 200
            try
              clusterdata = JSON.parse body
              job = defineBackup(clusterdata, backuptype, backupschema)
              POSTDATA = JSON.stringify ({
                token: config.cmonrpcToken
                operation: "createJob"
                job: job
              })
              url = "http://" + config.cmonrpcHost + ":" + config.cmonrpcPort + "/" + clusterid + "/job"
              robot.http(url)
                .header('Content-Type', 'application/json')
                .post(POSTDATA) (err, list, body) ->
                  if list.statusCode is 200

                    try
                      jobdata = JSON.parse body
                      if jobdata.requestStatus is "ok"
                        res.send "Backup scheduled under #{jobdata.jobId}"
                        robot.emit "job", {
                            user: res.envelope.user
                            jobId: jobdata.jobId
                            clusterId: clusterid
                        }
                      else
                        res.send "Backup could not be scheduled: #{jobdata.requestStatus} #{jobdata.status} ( #{jobdata.statusText} )"
                    catch error
                      console.log(error)
            catch error
              console.log(error)


  defineBackup = (clusterdata, backuptype, backupschema) ->
    for hostid, host of clusterdata.data
      if host.connected == true 
        if host.nodetype is 'galera' or host.nodetype is 'mysql'
          backuphost = host.hostname
          backupport = host.port
          backuphostype = host.nodetype  
          #Now we have all the information we need to construct the backup job
          if backuptype == 'mysqldump'
            job = {
                command: "backup"
                job_data: {
                  hostname: backuphost
                  backup_method: backuptype
                  cc_storage: 0
                  wsrep_desync: false
                  include_databases: backupschema
                  port: backupport}
              }
            return job
          else
            #desync = if backuphosttype is 'galera' then true else false
            desync = true
            job = {
                command: "backup"
                job_data: {
                  hostname: backuphost
                  backup_method: backuptype
                  cc_storage: 0
                  wsrep_desync: desync
                  port: backupport}
              }
            return job

  robot.on "job", (job) ->
    robot.send job.user, "Has scheduled a job #{job.jobId}!"

    jobUrl = "http://" + config.cmonrpcHost + ":" + config.cmonrpcPort + "/" + job.clusterId + "/job"
    POSTDATA = JSON.stringify ({
      token: config.cmonrpcToken
      operation: "getStatus"
      jobId: job.jobId
    })
    status = "DEFINED"
    prevStatus = status
    intervalId = setInterval () ->
      robot.http(jobUrl)
        .header('Content-Type', 'application/json')
        .post(POSTDATA) (err, list, body) ->
          if body
            try
              jobStatus = JSON.parse body
              status = jobStatus.status
              if status isnt prevStatus
                robot.send job.user, "Job #{job.jobId} changed state. New status: #{jobStatus.status} ( #{jobStatus.statusText})"
                prevStatus = status
              if status is "FINISHED" or status is "FAILED"
                clearInterval(intervalId)
    , 1000
    #deploy code goes here

  # Parses the given arguments and removes whitespace where possible
  robot.getArguments = (user, string, nr_args) ->
    # Trim whitespace
    argstring = string.replace /^\s+|\s+$/g, ""
    # Remove double spaces
    argstring = argstring.replace /\s+/g, " "
    args = argstring.split(" ")
    # Check if the number of arguments is correct
    if args.length > nr_args
      robot.send(user, "Wrong number of parameters given: expected #{nr_args} and got #{args.length}")
      return false
    else
      return args

  #Start polling the global state every 10 seconds
  prevClusterState = {}
  clusterIntervalId = setInterval () ->

    clusterUrl = "http://" + config.cmonrpcHost + ":" + config.cmonrpcPort + "/0/clusters"

    POSTDATA = JSON.stringify ({
      token: config.cmonrpcToken 
    })
    robot.http(clusterUrl)
      .header('Content-Type', 'application/json')
      .post(POSTDATA) (err, list, body) ->
        if body
          data = JSON.parse body
          if prevClusterState.length > 0
            for clusterid, cluster of data.data
              # Cluster state has changed since the previous polling
              if prevClusterState[clusterid].status isnt cluster.status
                if cluster.status <= 2
                    robot.messageRoom 'general', "Cluster #{cluster.name} in regained a healthy state: #{cluster.statusText}"
                # Degraded cluster detected. Let's get some information on the cluster and print that
                if cluster.status > 2
                  robot.messageRoom 'general', "Cluster #{cluster.name} in unhealthy state: #{cluster.statusText}"
                  POSTDATA = '{ "token": "ABCDEFGHIJKLMNOP", "operation": "getHosts" }' 
                  robot.http("http://localhost:9500/" + cluster.id + "/stat")
                    .header('Content-Type', 'application/json')
                    .post(POSTDATA) (err, list, body) ->
                      if list.statusCode is 200
                        try
                          clusterdata = JSON.parse body
                          for hostid, host of clusterdata.data
                            if host.connected == false
                              robot.messageRoom 'general', "#{host.hostname}: #{host.description} (#{host.nodetype})"
                        catch error
                          console.log(error)
              else
            prevClusterState = data.data
          else
            #Starting up the cluster polling, so give warning if a cluster is not okay
            prevClusterState = data.data
            for clusterid, cluster of data.data
              if cluster.status > 2
                robot.messageRoom 'general', "Cluster #{cluster.name} in unhealthy state: #{cluster.statusText}"
                POSTDATA = '{ "token": "ABCDEFGHIJKLMNOP", "operation": "getHosts" }' 
                robot.http("http://localhost:9500/" + cluster.id + "/stat")
                  .header('Content-Type', 'application/json')
                  .post(POSTDATA) (err, list, body) ->
                    if list.statusCode is 200
                      try
                        clusterdata = JSON.parse body
                        for hostid, host of clusterdata.data
                          if host.connected == false
                            robot.messageRoom 'general', "#{host.hostname}: #{host.description} (#{host.nodetype})"
                      catch error
                        console.log(error)
  , 1000


  #           catch error
  #             res.send "Ran into an error parsing JSON :("
  #           return

