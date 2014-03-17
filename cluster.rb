require 'getoptlong'
require 'ostruct'

class Main
  attr_reader :nodes, :config

  def initialize(config)
    @config = config
    @nodes = {}
  end

  def shutdown
    @nodes.each_pair do |port, pid|
      Process.kill("TERM", pid)
    end

    @nodes.clear
  end

  def node_path(port)
    File.join(@config.working_dir, port.to_s)
  end

  def create_working_dir(port)
    dir = node_path(port)
    unless Dir.exist?(dir)
      Dir.mkdir dir
      File.open(File.join(dir, "redis.conf"), "w") do |f|
        f.puts <<-CONFIG
port #{port}
cluster-enabled yes
cluster-config-file nodes.conf
cluster-node-timeout 5000
appendonly yes
        CONFIG
      end
    end
  end

  def init
    args = @nodes.keys.map { |port| "127.0.0.1:#{port}"}
    cmd = "ruby #{config.trib_path} create --replicas 1 #{args.join ' '}"
    puts cmd
    puts system cmd
  end

  def boot
    (7000..7005).each do |port|
      create_working_dir(port.to_s)

      pid = fork do
        Dir.chdir node_path(port)
        $stdout.reopen("#{port}.out", "w")
        exec "#{@config.binary_path} ./redis.conf"
      end

      puts "started instance #{pid}"

      @nodes[port] = pid
    end

    Signal.trap("TERM") do
      puts "shutting down..."
      shutdown
    end
  end
end

opts = GetoptLong.new(
  [ '--binary', '-n', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--working-dir', '-d', GetoptLong::REQUIRED_ARGUMENT ],
  [ '--trib-path', '-t', GetoptLong::REQUIRED_ARGUMENT ],
)

config = OpenStruct.new
config.binary_path = File.expand_path("redis-server")
config.working_dir = "work"
config.trib_path = "../redis/src/redis-trib.rb"

opts.each do |opt, arg|
  case opt
  when '--binary'      then config.binary_path = File.expand_path(arg)
  when '--working-dir' then config.working_dir = File.expand_path(arg)
  when '--trib-path'   then config.trib_path = arg
  end
end

abort "binary #{config.binary_path} does not exist!" unless File.exist?(config.binary_path)

@main = Main.new(config)

def boot
  @main.boot
end

def nodes
  @main.nodes
end

def shutdown
  @main.shutdown
end

require 'irb'
require 'irb/completion'
IRB.start
