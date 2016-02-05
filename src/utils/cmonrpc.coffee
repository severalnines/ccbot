# Description:
#   CMONRPC library for Hubot.
#
# Authors:
#   Art van Scheppingen (art@severalnines.com)
#

config = require '../config/config'
http = require 'http'

class Cmonrpc

  constructor: () ->
    @cmonmsgs = []
    @cmonrpcTokens = []
    if typeof config.cmonrpcToken isnt 'undefined'
      @cmonrpcTokens = config.cmonrpcToken.split(',')

  getToken: (channel, callback) ->
    if @cmonrpcTokens and @cmonrpcTokens.length > 0
      if typeof @cmonrpcTokens[channel] isnt 'undefined'
        return @cmonrpcTokens[channel]
      else
        return false

  fetchUrl: (msg, url, callback) ->
    msg.http("http://#{config.cmonrpcHost}:#{config.cmonrpcPort}#{url}")
      .headers("Accept": "application/json")
      .get() ( err, res, body ) ->
        callback(err, res, body)

  postUrl: (msg, url, data, callback) ->
    msg.http("http://#{config.cmonrpcHost}:#{config.cmonrpcPort}#{url}")
      .header('Content-Type', 'application/json')
      .post(data) (err, res, body) ->
        callback(err, res, body)

  cmonClusterStatus: (msg, err, list, body) ->
    try
      if list.statusCode is 200 and body
        data = JSON.parse body
        for clusterid, cluster of data.clusters
          msg.send "#{cluster.name}: #{cluster.statusText}"
          if cluster.status > 2
            POSTDATA = JSON.stringify ({
              token: @getToken(cluster.id)
              operation: "getHosts"
            })
            url = "/" + cluster.id + "/stat"
            @postUrl msg, url, POSTDATA, (err, res, body) ->
              cmon = new Cmonrpc()
              cmon.cmonHostStatus(msg, err, res, body)
      else
        console.log(err)
    catch error
      console.log (error)

  cmonHostStatus: (msg, err, list, body) ->
    messages = []
    try
      if list.statusCode is 200 and body
        clusterdata = JSON.parse body
        for hostid, host of clusterdata.data
          if host.connected == false
            description = if host.description then host.description else host.role
            msg.send  "#{host.hostname}: #{description} (#{host.nodetype})"
      else
        console.log(err)
    catch error
      console.log (error)

  cmonGetClusterHosts: (msg, err, list, body, callback) ->
    try
      if list.statusCode is 200 and body
        clusterdata = JSON.parse body
        callback(clusterdata.data)
      else
        console.log(err)
    catch error
      console.log (error)

  cmonGetCluster: (msg, err, list, body, callback) ->
    try
      if list.statusCode is 200 and body
        data = JSON.parse body
        if (data.clusters)
          callback(data.clusters)
        else
          if (data.data)
            callback(data.data)
      else
        console.log(err)
    catch error
      console.log (error)

  cmonGetClusterLogfiles: (msg, err, list, body, callback) ->
    try
      if list.statusCode is 200 and body
        data = JSON.parse body
        callback(data.data)
      else
        console.log(err)
    catch error
      console.log (error)

  cmonGetClusterLoglines: (msg, err, list, body, callback) ->
    try
      if list.statusCode is 200 and body
        data = JSON.parse body
        callback(data.data)
      else
        console.log(err)
    catch error
      console.log (error)


  defineBackup: (clusterdata, backuptype, backupschema) ->
    for hostid, host of clusterdata
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

  scheduleBackup: (robot, msg, clusterid, job) ->
    POSTDATA = JSON.stringify ({
      token: @getToken(clusterid)
      operation: "createJob"
      job: job
    })
    @postUrl msg, "/" + clusterid + "/job", POSTDATA, (err, list, body) ->
      cmon = new Cmonrpc()
      cmon.parseMessage err, list, body, (jobdata) ->
        if jobdata.requestStatus is "ok"
          msg.send "Backup scheduled under #{jobdata.jobId}"
          # robot.emit "job", {
          #     user: msg.envelope.user
          #     jobId: jobdata.jobId
          #     clusterId: clusterid
          # }
        else
          msg.send "Backup could not be scheduled: #{jobdata.requestStatus} #{jobdata.status} ( #{jobdata.statusText} )"

  getJobs: (robot, clusterid, callback) ->
    POSTDATA = JSON.stringify ({
      token: @getToken(clusterid)
      operation: "getJobs"
      limit: 1
    })
    @postUrl robot, "/" + clusterid + "/job", POSTDATA, (err, list, body) ->
      if list.statusCode is 200 and body
        try
          jobStatus = JSON.parse body
          callback(jobStatus)
        catch error
          console.log(error)

  getJobStatus: (robot, job, callback) ->
    POSTDATA = JSON.stringify ({
      token: @getToken(clusterid)
      operation: "getStatus"
      jobId: job.jobId
    })
    @postUrl robot, "/" + job.clusterId + "/job", POSTDATA, (err, list, body) ->
      if list.statusCode is 200 and body
        try
          jobStatus = JSON.parse body
          callback(jobStatus)
        catch error
          console.log(error)

  getJobMessages: (robot, job, callback) ->
    POSTDATA = JSON.stringify ({
      token: @getToken(clusterid)
      operation: "getJobMessages"
      jobId: job.jobId
    })
    @postUrl robot, "/" + job.clusterId + "/job", POSTDATA, (err, list, body) ->
      if list.statusCode is 200 and body
        try
          jobMessages = JSON.parse body
          callback(jobMessages.messages)
        catch error
          console.log(error)

  parseMessage: (err, list, body, callback) ->
    if list.statusCode is 200
      try
        data = JSON.parse body
        callback(data)
      catch error
        console.log(error)
    else
      console.log(err)

  # Parses the given arguments and removes whitespace where possible
  getArguments: (user, string) ->
    args = {}
    # Trim whitespace
    argstring = string.replace /^\s+|\s+$/g, ""
    # Remove double spaces
    argstring = argstring.replace /\s+/g, " "
    key = ''
    i = 0
    for argument in argstring.split(" ")
      do (argument) ->
        if i % 2 is 0
          key = argument
        else
          args[key] = argument
        i++
    # Check if the number of arguments is correct
    if args.length is 0
      robot.send(user, "Wrong number of parameters given")
      return false
    else
      return args



module.exports = Cmonrpc
