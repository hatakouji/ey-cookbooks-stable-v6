# Expect this to run before haproxy::install
#

# We need to do an execute here because a service
# definition requires the init.d file to be in
# place at by this point. And since we configure first
# it won't be on clean instances
execute "reload-haproxy" do
  command 'if /etc/init.d/haproxy status ; then /etc/init.d/haproxy reload; else /etc/init.d/haproxy restart; fi'
  action :nothing
end



directory "/etc/haproxy/errorfiles" do
  action :create
  owner 'root'
  group 'root'
  mode 0755
  recursive true
end

["400.http","403.http","408.http","500.http","502.http","503.http","504.http"].each do |p|
  cookbook_file "/etc/haproxy/errorfiles/#{p}" do
    owner 'root'
    group 'root'
    mode 0644
    backup 0
    source "errorfiles/#{p}"
    not_if { File.exists?("/etc/haproxy/errorfiles/keep.#{p}") }
  end
end


# CC-52
# Add http check for accounts with adequate settings in their dna metadata
haproxy_httpchk_path = (app = node.engineyard.apps.detect {|a| a.metadata?(:haproxy_httpchk_path) } and app.metadata?(:haproxy_httpchk_path))
haproxy_httpchk_host = (app = node.engineyard.apps.detect {|a| a.metadata?(:haproxy_httpchk_host) } and app.metadata?(:haproxy_httpchk_host))

# CC-954: Allow for an app to use specific http check endpoint instead of tcp connectivity check
unless haproxy_httpchk_path
  app = node.engineyard.apps.detect {|a| a.metadata?(:node_health_check_url)}
  if app
    haproxy_httpchk_path = app.metadata(:node_health_check_url)
    haproxy_httpchk_host = app.vhosts.first.domain_name.empty? ? nil : app.vhosts.first.domain_name
  end
end

=begin

# SSL configuration
directory "/etc/haproxy/ssl" do
  owner 'root'
  group 'root'
  mode 0775
  action:create
end

execute "clearing old SSL certificates" do
  command "rm -rf /etc/haproxy/ssl/*"
end


node.engineyard.environment['apps'].each do |app|

  if (!app[:vhosts][0][:ssl_cert].nil?)

    Chef::Log.info "Installing SSL certificates for application #{app.name}"
    dhparam_available = app.components[1].dh_key

    if dhparam_available
      managed_template "/etc/haproxy/ssl/dhparam.#{app.name}.pem" do
        owner node['owner_name']
        group node['owner_name']
        mode 0600
        source "dhparam.erb"
        variables ({
          :dhparam => app.components[1].dh_key
        })
      end
    end

    template "/etc/haproxy/ssl/#{app.name}.key" do
      owner node['owner_name']
      group node['owner_name']
      mode 0644
      source "sslkey.erb"
      backup 0
      variables(
        :key => app[:vhosts][0][:ssl_cert][:private_key]
      )
    end

    template "/etc/haproxy/ssl/#{app.name}.crt" do
      owner node['owner_name']
      group node['owner_name']
      mode 0644
      source "sslcrt.erb"
      backup 0
      variables(
        :crt => app[:vhosts][0][:ssl_cert][:certificate],
        :chain => app[:vhosts][0][:ssl_cert][:certificate_chain]
      )
    end

    template "/etc/haproxy/ssl/#{app.name}.pem" do
      owner node['owner_name']
      group node['owner_name']
      mode 0644
      source "sslpem.erb"
      backup 0
      variables(
        :crt => app[:vhosts][0][:ssl_cert][:certificate],
        :chain => app[:vhosts][0][:ssl_cert][:certificate_chain],
        :key => app[:vhosts][0][:ssl_cert][:private_key]
      )
      notifies :run, resources(:execute => 'reload-haproxy'), :delayed
    end
  end
end
# SSL configuration - END
=end


use_http2 = node['haproxy'] && node['haproxy']['http2']
managed_template "/etc/haproxy.cfg" do
  owner 'root'
  group 'root'
  mode 0644
  source "haproxy.cfg.erb"
  members = node['dna']['members'] || []
  variables({
    :backends => node.engineyard.environment.app_servers,
    :app_master_weight => members.size < 51 ? (50 - (members.size - 1)) : 0,
    :haproxy_user => node['dna']['haproxy']['username'],
    :haproxy_pass => node['dna']['haproxy']['password'],
    :httpchk_host => haproxy_httpchk_host,
    :httpchk_path => haproxy_httpchk_path,
    :http2 => use_http2
  })

  # We need to reload to activate any changes to the config
  # but delay it as haproxy may not be installed yet
  notifies :run, resources(:execute => 'reload-haproxy'), :delayed
end

link "/etc/haproxy/haproxy.cfg" do
  to "/etc/haproxy.cfg"
end
