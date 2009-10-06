require 'digest/md5'
require 'socket'
require 'zlib'
require 'timeout'

class CacheBar
  class NotFound < StandardError; end
  class NotStored < StandardError; end
  class ConnectionError < StandardError; end

  def self.pool(name=nil)
    name = name ? name.to_sym : :default
    (@pools ||= {})[name] ||= begin
      @config ||= begin
        yaml = YAML.load(File.read(File.join(RAILS_ROOT, 'config', 'memcached.yml')))
        (yaml['defaults'] || {}).merge(yaml[RAILS_ENV] || {})
      end

      if name == :default
        new(@config.symbolize_keys)
      else
        raise "CacheBar Pool not found (#{name})" unless @config.has_key?(name.to_s) && @config[name.to_s].is_a?(Hash)
        (@pools ||= {})[name.to_sym] ||= new(@config[name.to_s].symbolize_keys)
      end
    end
  end

  def initialize(options={})
    @options = {
      :namespace => 'default',
      :gzip => false,
      :ttl => 0,
      :servers => '0.0.0.0'
    }.merge(options)
    @options[:servers] = [@options[:servers]].flatten
  end

  def set(key, value, options={})
    generic_set(:set, key, value, options)
  end

  def add(key, value, options={})
    generic_set(:add, key, value, options)
  end

  def replace(key, value, options={})
    generic_set(:replace, key, value, options)
  end

  def append(key, value, options={})
    generic_set(:append, key, value, options)
  end

  def prepend(key, value, options={})
    generic_set(:prepend, key, value, options)
  end

  def cas(key, value, cas, options={})
    generic_set(:cas, key, value, options.merge(:cas => cas))
  end

  def incr(key, value=1, options={})
    generic_incr_or_decr(:incr, key, value, options)
  end

  def decr(key, value=1, options={})
    generic_incr_or_decr(:decr, key, value, options)
  end
    
  def get(key, options={})
    generic_get(:get, [key], options).first[:value]
  end

  def gets(key, options={})
    results = generic_get(:gets, [key], options)
    [results.first[:value], results.first[:cas]]
  end

  def get_multi(*keys)
    options = keys.last.is_a?(Hash) ? keys.pop : {}
    generic_get(:get, keys, options).inject({}) { |hash,results| hash[results[:key]] = results[:value]; hash }
  end

  def gets_multi(*keys)
    options = keys.last.is_a?(Hash) ? keys.pop : {}
    generic_get(:gets, keys, options).inject({}) { |hash,results| hash[results[:key]] = [results[:value], results[:cas]]; hash }
  end
  
  def delete(key, options={})
    generic_key_command(:delete, key, nil, options)
    true
  end

  def flush_all
    all_servers.inject({}) do |hash,(server,server_id)|
      socket_for_server_id(server_id) do |socket|
        socket.write("flush_all\r\n")
        hash[server] = (socket.gets.strip == 'OK')
      end
      hash
    end
  end

  def stats
    all_servers.inject({}) do |hash,(server,server_id)|
      socket_for_server_id(server_id) do |socket|
        socket.write("stats\r\n")
        while true do
          result, key, value = socket.gets.split(' ')
          break if result == 'END'
          (hash[server] ||= {})[key.to_sym] = value
        end
      end
      hash
    end
  end

  def [](key)
    get(key)
  rescue NotFound
    nil
  end

  def []=(key, value)
    set(key, value)
  end

  # get or set... a = cache.gos('a') { expensive_function_here() }
  def gos(key, options={}, &block)
    get(key, options)
  rescue NotFound
    set(key, block.call, options)
  end

  def with_options(options={})
    (proxy = Object.new).instance_eval %(
      def [](key)
        @cache.get(key, @options)
      rescue NotFound
        nil
      end

      def []=(key, value)
        @cache.set(key, value, @options)
      end
    
      def method_missing(method, *params, &block)
        params.push({}) unless params.last.is_a?(Hash)
        params.last.merge!(@options)
        @cache.send(method, *params, &block)
      end
    )
    proxy.instance_variable_set('@cache', self)
    proxy.instance_variable_set('@options', options)
    proxy
  end
  
protected

  FLAG_INTEGER = 0x001
  FLAG_MARSHAL = 0x010
  FLAG_GZIP =    0x100

  def namespace(key, options)
    Digest::MD5.hexdigest("#{@options[:namespace]}:#{"#{options[:namespace]}:" if options[:namespace]}#{key}")
  end
  
  def generic_incr_or_decr(command, key, value, options)
    generic_key_command(command, key, value, options).to_i
  rescue NotFound
    begin
      add(key, 0, options)
    rescue NotStored
      # this is fine... race condition, somebody else added the key already
    end
    generic_key_command(command, key, value, options).to_i
  end
  
  def generic_key_command(command, key, data, options)
    key = namespace(key, options)
    results = socket_for_server_id(server_id_for_key(key)) do |socket|
      socket.write("#{command} #{key} #{data}\r\n")
      socket.gets.strip
    end
    
    case results
      when "NOT_STORED", "EXISTS" then raise NotStored
      when "NOT_FOUND" then raise NotFound
      else results
    end
  end
  
  def generic_set(command, key, value, options)
    flags = 0
    if value.is_a?(Integer)
      data = value.to_s
      flags |= FLAG_INTEGER
    else
      if value.is_a?(String)
        data = value
      else
        data = Marshal.dump(value)
        flags |= FLAG_MARSHAL
      end

      if (options.has_key?(:gzip) && options[:gzip]) || @options[:gzip]
        data = Zlib::Deflate.deflate(data)
        flags |= FLAG_GZIP
      end
    end
    
    generic_key_command(command, key, "#{flags} #{options[:ttl] || @options[:ttl]} #{data.length} #{options[:cas]}\r\n#{data}", options)
    value
  end

  def generic_get(command, keys, options)
    md5_keys = keys.inject({}) { |hash, key| hash[namespace(key, options)] = key; hash }
    server_keys = md5_keys.keys.inject({}) { |hash,key| (hash[server_id_for_key(key)] ||= []) << key; hash }
    results = server_keys.inject([]) do |array, (server_id, keys)|
      socket_for_server_id(server_id) do |socket|
        socket.write("#{command} #{keys.join(' ')}\r\n")

        while true
          raise ConnectionError unless line = socket.gets
          result, key, flag, length, cas = line.split(' ')
          break if result == 'END'

          raise ConnectionError unless value = socket.read(length.to_i)
          raise ConnectionError unless socket.read(2)

          value = value.to_i if flag.to_i & FLAG_INTEGER > 0
          value = Zlib::Inflate.inflate(value) if flag.to_i & FLAG_GZIP > 0
          begin
            value = Marshal.load(value) if flag.to_i & FLAG_MARSHAL > 0
          rescue ArgumentError => e
            if e.message.match("undefined class/module (.*)")
              $1.split('::').reject { |n| n.empty? }.inject(Object) do |constant,name|
                constant.const_defined?(name) ? constant.const_get(name) : constant.const_missing(name)
              end
              retry
            else
              raise
            end
          end

          array << { :value => value, :key => md5_keys[key], :cas => cas.to_i }
        end
      end
      array
    end
    
    if keys.length == 1 && results.length == 0
      raise NotFound
    else
      results
    end
  end

  def server_id_for_key(key)
    key.hex % all_servers.length
  end

  def socket_for_server_id(server_id, &block)
    timeout(1) do
      (@sockets ||= {})[server_id] ||= begin
        host, port = @options[:servers][server_id].split(':')
        TCPSocket.new(host, port ? port.to_i : 11211)
      end
      block.call(@sockets[server_id])
    end
  rescue ConnectionError, Errno::EACCES, Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNREFUSED, Errno::ETIMEDOUT, Timeout::Error
    @sockets.delete(server_id)
    raise ConnectionError
  end
  
  def all_servers
    @options[:servers].inject([{},0]) { |(hash,index),server| hash[server] = index; [hash, index+1] }.first
  end
  
end

