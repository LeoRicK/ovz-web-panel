require "xmlrpc/client"

class HwDaemonException < Exception
end

class HwDaemonExecException < HwDaemonException
  def initialize(message, code, output = '')
    super(message)
    @message = message
    @code = code
    @output = output
  end
  
  def code
    @code
  end
  
  def output
    @output
  end
end

class HwDaemonClient
  
  def initialize(host, auth_key, port, timeout)
    @host = host
    @auth_key = auth_key
    @port = port
    @rpc_client = XMLRPC::Client.new3({
      :host => @host,
      :path => "/xmlrpc",
      :port => @port,
      :user => 'admin', 
      :password => @auth_key,
      :timeout => timeout
    })
  end
  
  def exec(command, args = '')
    RAILS_DEFAULT_LOGGER.info "Executing command: #{command} #{args}"
    result = rpc_call('hwDaemon.exec', command, args)
    raise HwDaemonExecException.new("Command '#{command} #{args}' execution failed with code #{result['exit_code']}\nOutput: #{result['output']}", result['exit_code'], result['output']) if 0 != result['exit_code']
    result
  end
  
  def job(command, args = '')
    RAILS_DEFAULT_LOGGER.info "Scheduling job: #{command} #{args}"
    rpc_call('hwDaemon.job', command, args)
  end
  
  def job_status(job_id)
    rpc_call('hwDaemon.job_status', job_id)
  end
  
  def daemon_version
    rpc_call('hwDaemon.version')
  end
  
  def ping
    rpc_call('hwDaemon.version')
  end
  
  def write_file(filename, content)
    rpc_call('hwDaemon.write_file', filename, content)
  end
  
  private
  
  def rpc_call(*args)
    begin
      ok, result = @rpc_client.call2(*args)
    rescue RuntimeError => error
      RAILS_DEFAULT_LOGGER.error "XML-RPC runtime error: #{error}"
      return false
    end
    
    if ok then
      return result
    else
      error = "XML-RPC call error: #{result.faultCode}; #{result.faultString}"
      RAILS_DEFAULT_LOGGER.error(error)
      raise HwDaemonException, error
    end
  end
  
end