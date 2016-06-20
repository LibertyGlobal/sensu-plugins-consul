#! /usr/bin/env ruby
#
#   check-consul-service-health
#
# DESCRIPTION:
#   This plugin checks which percent of service is healthy in consul cluster
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
#   Check if infludb has less then 50% of healthy nodes for critical, or less then 75%
#     for warning:
#
#     ./check-consul-service-health.rb -s influxdb -w 75 -c 50
#

require 'sensu-plugin/check/cli'
require 'diplomat'
require 'json'

#
# Service Status
#
class CheckConsulServiceHealthPercent < Sensu::Plugin::Check::CLI
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

  option :critical,
         description: 'Critical threshold for service',
         short: '-c CRITICAL',
         long: '--critical CRITICAL',
         default: 50

  option :warning,
         description: 'Warning threshold for service',
         short: '-w WARNING',
         long: '--warning WARNING',
         default: 75

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
    p data
    return critical "Could not find service #{config[:service]}. Are checks defined?" if data.empty?

    passing = []

    # Parse services states (see https://www.consul.io/docs/agent/http/health.html)
    data.each do |d|
      passing << {
        'node' => d['Node'],
        'service' => d['ServiceName'],
        'service_id' => d['ServiceID'],
        'notes' => d['Notes']
      } if d['Status'] == 'passing'
    end
    percent = (passing.size.to_f / (data.size.to_f / 100)).round(2)
    critical "Service #{config[:service]} health is #{percent}% below #{config[:critical]}%" if percent < config[:critical].to_f
    warning "Service #{config[:service]} health is #{percent}% below #{config[:warning]}%" if percent < config[:warning].to_f
    ok "Service #{config[:service]} health is #{percent}%"
  end
end
