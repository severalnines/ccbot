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
Cmonrpc = require '../utils/cmonrpc'
cmon = new Cmonrpc()

module.exports = (robot) ->
  # Fetches the status of the clusters
  robot.respond /status/i, (msg) ->
    POSTDATA = JSON.stringify ({
      token: config.cmonrpcToken 
    })
    cmon.postUrl msg, '/0/clusters', POSTDATA, (err, list, body) ->
      cmon.cmonClusterStatus msg, err, list, body, (messages) ->

  robot.respond /showlogs (.*)/i, (res) ->
    if args = cmon.getArguments(res.envelope.user, res.match[1])
      # Check if the cluster has been set
      if typeof args.cluster is 'undefined'
        res.send("Wrong parameters given. Usage: showlogs cluster <clusterid>")
      else
        POSTDATA = JSON.stringify ({
          token: config.cmonrpcToken
          operation: "list" 
        })
        cmon.postUrl res, '/' + args.cluster+ '/log', POSTDATA, (err, list, body) ->
          cmon.cmonGetClusterLogfiles res, err, list, body, (data) ->
            for logfile in data
              do (logfile) ->
                res.send("hostname: #{logfile.hostname}, filename: #{logfile.filename}")

  robot.respond /lastlog (.*)/i, (res) ->
    if args = cmon.getArguments(res.envelope.user, res.match[1])
      # Check if the cluster has been set
      if typeof args.host is 'undefined' and typeof args.cluster is 'undefined'
        res.send("Wrong parameters given. Usage: lastlog cluster <cluster> host <host> filename <filename> limit <limit>")
      else
        POSTDATA = JSON.stringify ({
          token: config.cmonrpcToken
          operation: "contents" 
          hostname: args.host
          filename: args.filename
          limit: if args.limit then args.limit else 5
        })
        cmon.postUrl res, '/' + args.cluster+ '/log', POSTDATA, (err, list, body) ->
          cmon.cmonGetClusterLoglines res, err, list, body, (data) ->
            for logline in data.reverse()
              do (logline) ->
                res.send("#{logline.created}: #{logline.message}")


  # Schedules a backup of a host or a schema
  # Either backups a full host or only a single schema (1 or 3 arguments)
  robot.respond /backup (.*)/i, (res) ->
    if args = cmon.getArguments(res.envelope.user, res.match[1])
      # Check if the cluster has been set
      if typeof args.cluster is 'undefined'
        res.send("Wrong number of parameters given: expected #{nr_args} and got #{args.length}")
      else
        clusterid = args.cluster
        # Otherwise the backup method has been specified
        if typeof args.schema isnt 'undefined'
          backuptype = 'mysqldump'
          backupschema = args.schema
        else
          backuptype = 'xtrabackupfull'
          backupschema = ''

        POSTDATA = JSON.stringify ({
          token: config.cmonrpcToken 
          operation: "getHosts"
        })
        cmon.postUrl res, "/" + clusterid + "/stat", POSTDATA, (err, list, body) ->
          cmon.cmonGetClusterHosts res, err, list, body, (hosts) ->
            # Filter the hosts
            if typeof args.host isnt 'undefined'
              newhosts = []
              for hostid, host of hosts
                if host.hostname is args.host
                  newhosts[hostid] = host
              hosts = newhosts
            if hosts.length > 0
              # Define job and then schedule the backup
              job = cmon.defineBackup(hosts, backuptype, backupschema)
              cmon.scheduleBackup(robot, res, clusterid, job)
            else
              console.log(hosts)
              res.send("Can't schedule backup as there are no suitable hosts in this cluster.")


  # Generic hook on "job" to display the status of jobs within Clustercontrol
  # The interval is set at 1 second
  robot.on "job", (job) ->
    robot.send job.user, "Has scheduled a job #{job.jobId}!"

    status = "DEFINED"
    prevStatus = status
    intervalId = setInterval () ->
      cmon.getJobStatus robot, job, (jobStatus) ->
        # Status of the job changed
        if jobStatus.status isnt prevStatus
          robot.send job.user, "Job #{job.jobId} changed state. New status: #{jobStatus.status} ( #{jobStatus.statusText})"
          prevStatus = jobStatus.status
        if jobStatus.status is "FINISHED"
          clearInterval(intervalId)
          cmon.getJobMessages robot, job, (jobMessages) ->
            for messageid, message of jobMessages[-1..]
              robot.send job.user, "Finished: #{message.message}"
        # If the job failed we need to figure out what went wrong from the last three entries
        else if jobStatus.status is "FAILED"
          clearInterval(intervalId)
          cmon.getJobMessages robot, job, (jobMessages) ->
            for messageid, message of jobMessages.reverse()[-3..]
              robot.send job.user, "Error: #{message.message}"
    , 1000



  #Start polling the global state every 10 seconds
  prevClusterState = {}
  clusterIntervalId = setInterval () ->
    POSTDATA = JSON.stringify ({
      token: config.cmonrpcToken
    })
    cmon.postUrl robot, '/0/clusters', POSTDATA, (err, list, body) ->
      cmon.cmonGetCluster robot, err, list, body, (data) ->
        if prevClusterState.length > 0
          for clusterid, cluster of data
            # Cluster state has changed since the previous polling
            if prevClusterState[clusterid].status isnt cluster.status
              if cluster.status <= 2
                  robot.messageRoom 'general', "Cluster #{cluster.name} in regained a healthy state: #{cluster.statusText}"
              # Degraded cluster detected. Let's get some information on the cluster and print that
              if cluster.status > 2
                robot.messageRoom 'general', "Cluster #{cluster.name} in unhealthy state: #{cluster.statusText}"
                POSTDATA = '{ "token": "'+ config.cmonrpcToken +'", "operation": "getHosts" }' 
                url = "/" + cluster.id + "/stat"
                @postUrl robot, url, POSTDATA, (err, res, body) ->
                  cmon.cmonGetClusterHosts robot, err, list, body, (hosts) ->
                    for hostid, host of hosts
                      if host.connected == false
                        robot.messageRoom 'general', "#{host.hostname}: #{host.description} (#{host.nodetype})"
            else
          prevClusterState = data
        else
          #Starting up the cluster polling, so give warning if a cluster is not okay
          prevClusterState = data
          for cluster_i, cluster of data
            if cluster.status > 2
              robot.messageRoom 'general', "Cluster #{cluster.name} in unhealthy state: #{cluster.statusText}"
              POSTDATA = '{ "token": "'+ config.cmonrpcToken +'", "operation": "getHosts" }' 
              url = "/" + cluster.id + "/stat"
              @postUrl robot, url, POSTDATA, (err, res, body) ->
                cmon.cmonGetClusterHosts robot, err, list, body, (hosts) ->
                  for hostid, host of hosts
                    if host.connected == false
                      robot.messageRoom 'general', "#{host.hostname}: #{host.description} (#{host.nodetype})"
  , 10000

  #Start polling the global jobs every 10 seconds
  lastJobs = {}
  clusterIntervalId = setInterval () ->
    # Get global jobs
    cmon.getJobs robot, 0, (jobStatus) ->
      for jobid, job of jobStatus.jobs
        do (job) ->
          # Status of the job changed
          if typeof lastJobs[0] isnt 'undefined' and job.jobId isnt lastJobs[0].jobId
            jobDetails =  JSON.parse job.jobStr
            robot.messageRoom 'general', "Job #{job.jobId} changed state. New status: #{job.status} ( #{jobDetails.command} )"
            lastJobs[0] = job
          else
            lastJobs[0] = job
    # Get jobs per cluster
    POSTDATA = JSON.stringify ({
      token: config.cmonrpcToken
    })
    cmon.postUrl robot, '/0/clusters', POSTDATA, (err, list, body) ->
      cmon.cmonGetCluster robot, err, list, body, (data) ->
        for cluster_i, cluster of data
          do (cluster) ->
            cmon.getJobs robot, cluster.id, (jobStatus) ->
              for jobid, job of jobStatus.jobs
                do (job) ->
                  # Status of the job changed
                  if typeof lastJobs[cluster.id] is 'undefined' 
                    lastJobs[cluster.id] = job
                  else 
                    try
                      jobDetails =  JSON.parse job.jobStr
                      if typeof jobDetails.job_data.action isnt 'undefined'
                        statusMessage = jobDetails.job_data.action
                      else
                        statusMessage = jobDetails.command
                    catch
                        statusMessage = job.jobStr
                    if job.jobId isnt lastJobs[cluster.id].jobId
                      robot.messageRoom 'general', "New job (#{job.jobId}) has been scheduled on cluster #{cluster.id}: #{statusMessage} (#{job.status})"
                    else
                      if job.status isnt lastJobs[cluster.id].status
                        if job.status is "FINISHED"
                          cmon.getJobMessages robot, {jobId: job.jobId, clusterId: cluster.id}, (jobMessages) ->
                            for messageid, message of jobMessages[-1..]
                              robot.messageRoom 'general', "Finished job #{job.jobId}: #{message.message}"
                        # If the job failed we need to figure out what went wrong from the last three entries
                        else if job.status is "FAILED"
                          cmon.getJobMessages robot, {jobId: job.jobId, clusterId: cluster.id}, (jobMessages) ->
                            for messageid, message of jobMessages
                              do (message) ->
                                if message.exitCode isnt 0
                                  robot.messageRoom 'general', "Error in job #{job.jobId}: #{message.message}"
                            robot.messageRoom 'general', "Job #{job.jobId} ended in status: #{job.status} "
                    lastJobs[cluster.id] = job
                  

  , 1000