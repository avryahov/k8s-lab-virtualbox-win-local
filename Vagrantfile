require "fileutils"

def load_env_file(path)
  env = {}
  return env unless File.exist?(path)

  File.readlines(path, chomp: true).each do |line|
    next if line.strip.empty? || line.strip.start_with?("#")

    key, value = line.split("=", 2)
    next if key.nil? || value.nil?

    env[key.strip] = value.strip.gsub(/\A['"]|['"]\z/, "")
  end

  env
end

def ps_quote(value)
  "'#{value.gsub("'", "''")}'"
end

def ensure_node_key(generate_key_script, node_name, ssh_key_dir)
  ok = system(
    "powershell.exe",
    "-ExecutionPolicy", "Bypass",
    "-File", generate_key_script,
    "-NodeName", node_name,
    "-KeyDirectory", ssh_key_dir
  )
  raise "Failed to generate SSH key for #{node_name}" unless ok
end

env_file = load_env_file(File.join(__dir__, ".env"))
env = ENV.to_h.merge(env_file)
active_command = ARGV.first
commands_requiring_node_keys = %w[up reload provision validate]
requires_node_keys = commands_requiring_node_keys.include?(active_command)
workspace_dir = __dir__
ssh_key_dir = File.join(workspace_dir, ".vagrant", "node-keys")
generate_key_script = File.join(workspace_dir, "scripts", "generate-node-key.ps1")
cleanup_key_script = File.join(workspace_dir, "scripts", "cleanup-node-key.ps1")

cluster_prefix = env.fetch("CLUSTER_PREFIX", "lab-k8s")
box_name = env.fetch("VM_BOX", "bento/ubuntu-22.04")
worker_count = env.fetch("WORKER_COUNT", "2").to_i
worker_count = 1 if worker_count < 1

common_cpus = env.fetch("VM_CPUS", "4").to_i
common_memory = env.fetch("VM_MEMORY_MB", "8192").to_i
boot_timeout = env.fetch("VM_BOOT_TIMEOUT", "600").to_i
private_network_prefix = env.fetch("PRIVATE_NETWORK_PREFIX", "192.168.56")
private_network_gateway = env.fetch("PRIVATE_NETWORK_GATEWAY", "#{private_network_prefix}.1")
master_private_ip = env.fetch("MASTER_PRIVATE_IP", "#{private_network_prefix}.10")
master_ssh_port = env.fetch("MASTER_SSH_PORT", "2232").to_i
master_api_port = env.fetch("MASTER_API_PORT", "6443").to_i
master_dashboard_port = env.fetch("MASTER_DASHBOARD_PORT", "30443").to_i
kubernetes_version = env.fetch("KUBERNETES_VERSION", "1.34")
pod_cidr = env.fetch("POD_CIDR", "10.244.0.0/16")
bridge_adapter = env["BRIDGE_ADAPTER"]

nodes = [
  {
    name: env.fetch("MASTER_VM_NAME", "#{cluster_prefix}-master"),
    hostname: env.fetch("MASTER_HOSTNAME", "#{cluster_prefix}-master"),
    ip: master_private_ip,
    ssh_port: master_ssh_port,
    role: "master"
  }
]

(1..worker_count).each do |idx|
  nodes << {
    name: env.fetch("WORKER#{idx}_VM_NAME", "#{cluster_prefix}-worker#{idx}"),
    hostname: env.fetch("WORKER#{idx}_HOSTNAME", "#{cluster_prefix}-worker#{idx}"),
    ip: env.fetch("WORKER#{idx}_PRIVATE_IP", "#{private_network_prefix}.#{10 + idx}"),
    ssh_port: env.fetch("WORKER#{idx}_SSH_PORT", (2232 + idx * 10).to_s).to_i,
    role: "worker"
  }
end

host_entries = nodes.map { |node| "#{node[:ip]} #{node[:hostname]}" }.join(",")
nodes.each { |node| ensure_node_key(generate_key_script, node[:name], ssh_key_dir) } if requires_node_keys

Vagrant.configure("2") do |config|
  config.vm.box = box_name
  config.vm.box_check_update = false
  config.ssh.username = "vagrant"
  config.ssh.password = "vagrant"
  config.ssh.insert_key = false

  nodes.each do |node|
    config.vm.define node[:name] do |machine|
      node_key_path = File.join(ssh_key_dir, "#{node[:name]}.ed25519")

      machine.vm.hostname = node[:hostname]
      machine.vm.boot_timeout = boot_timeout
      machine.ssh.username = "vagrant"
      machine.ssh.password = "vagrant"

      machine.trigger.after :destroy do |trigger|
        trigger.name = "Remove SSH key for #{node[:name]}"
        trigger.run = {
          inline: "powershell.exe -ExecutionPolicy Bypass -File #{ps_quote(cleanup_key_script)} -NodeName #{ps_quote(node[:name])} -KeyDirectory #{ps_quote(ssh_key_dir)}"
        }
      end

      machine.vm.network "private_network", ip: node[:ip]
      if bridge_adapter && !bridge_adapter.empty?
        machine.vm.network "public_network", bridge: bridge_adapter, auto_config: true
      end

      machine.vm.network "forwarded_port",
        guest: 22,
        host: node[:ssh_port],
        auto_correct: true,
        id: "ssh"

      if node[:role] == "master"
        machine.vm.network "forwarded_port",
          guest: 6443,
          host: master_api_port,
          auto_correct: true,
          id: "k8s-api"
        machine.vm.network "forwarded_port",
          guest: 30443,
          host: master_dashboard_port,
          auto_correct: true,
          id: "k8s-dashboard"
      end

      machine.vm.provider "virtualbox" do |vb|
        vb.name = node[:name]
        vb.cpus = common_cpus
        vb.memory = common_memory
        vb.gui = false
      end

      machine.vm.provision "shell",
        path: "scripts/common.sh",
        args: [
          node[:hostname],
          node[:ip],
          host_entries,
          kubernetes_version,
          private_network_gateway,
          node[:name]
        ]

      if node[:role] == "master"
        machine.vm.provision "shell",
          path: "scripts/master.sh",
          args: [master_private_ip, pod_cidr]
      else
        machine.vm.provision "shell",
          path: "scripts/worker.sh"
      end
    end
  end
end
