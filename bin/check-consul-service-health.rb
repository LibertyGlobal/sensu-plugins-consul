#! /usr/bin/env ruby
#
#   check-consul-service-health
#
# DESCRIPTION:
#   This plugin assists in checking the check status of a Consul Service
#   In addition, it provides additional Yieldbot logic for Output containing
#   JSON.
#
# OUTPUT:
#   plain text
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: sensu-plugin
#   gem: diplomat
#
# USAGE:
#   Check infludb service in all datacenters on my-consul-server.io cluster:
#     ./check-consul-service-health.rb --consul http://my-consul-server.io:8500 -s influxdb
#
#   Check nginx service in dc1 datacenter on http://localhost:8500
#     ./check-consul-service-health.rb -d dc1 -s nginx
#
# NOTES:
#
# LICENSE:
#   Copyright 2015 Yieldbot, Inc. <devops@yieldbot.com>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'sensu-plugin/check/cli'
require 'diplomat'
require 'json'

#
# Service Status
#
class CheckConsulServiceHealth < Sensu::Plugin::Check::CLI
  option :consul,
         description: 'consul server',
         long: '--consul SERVER',
         default: 'http://localhost:8500'

  option :datacenter,
         description: 'consul datacenter to query (query all datacenters by default)',
         short: '-d DATACENTER',
         long: '--datacenter SERVER',
         default: 'all'

  option :service,
         description: 'a service managed by consul',
         short: '-s SERVICE',
         long: '--service SERVICE',
         default: 'consul'

  # Get the service checks for the given service
  def acquire_service_data
    datacenters.map do |datacenter|
      Diplomat::Health.checks(config[:service], dc: datacenter)
    end
  rescue Faraday::ConnectionFailed => e
    warning "Connection error occurred: #{e}"
  rescue StandardError => e
    unknown "Exception occurred when checking consul service: #{e}"
  end

  # Get the datacenters from consul if all specified, return option otherwise
  def datacenters
    config[:datacenter] == 'all' ? Diplomat::Datacenter.get : [config[:datacenter]]
  rescue Faraday::ConnectionFailed => e
    warning "Connection error occurred: #{e}"
  rescue StandardError => e
    unknown "Exception occurred when getting consul datacenters: #{e}"
  end

  # Do work
  def run
    Diplomat.configure do |dip|
      dip.url = config[:consul]
    end
    data = acquire_service_data.reduce(:+)
    return unknown "Could not find service #{config[:service]}. Are checks defined?" if data.empty?

    passing = []
    failing = []
    warn = []

    # Parse services states (see https://www.consul.io/docs/agent/http/health.html)
    data.each do |d|
      passing << {
        'node' => d['Node'],
        'service' => d['ServiceName'],
        'service_id' => d['ServiceID'],
        'notes' => d['Notes']
      } if d['Status'] == 'passing'
      warn << {
        'node' => d['Node'],
        'service' => d['ServiceName'],
        'service_id' => d['ServiceID'],
        'notes' => d['Notes']
      } if d['Status'] == 'warning'
      failing << {
        'node' => d['Node'],
        'service' => d['ServiceName'],
        'service_id' => d['ServiceID'],
        'notes' => d['Notes']
      } if d['Status'] == 'critical'
    end
    critical failing unless failing.empty?
    warning warn unless warn.empty?
    ok passing unless passing.empty?
    unknown "Service #{config[:service]} state is uknown"
  end
end
