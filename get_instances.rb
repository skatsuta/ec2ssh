#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
require 'aws-sdk'
require 'pp'
require 'inifile'
require 'optparse'
require 'yaml'

CACHE = "#{Dir.home}/.ec2ssh".freeze
CACHE_TTL = 3600

profile = 'default'
options = {}
OptionParser.new do |opt|
  opt.banner = "Usage: #{opt.program_name} [options]"
  opt.on('-h', '--help', 'Show usage') do
    puts opt.help
    exit
  end
  opt.on('-f', '--flush', 'Flush cache') { options[:ignore] = true }
  opt.on('-p PROFILE', '--profile PROFILE', 'Specify profile') do |v|
    profile = "profile #{v}"
    Aws.config[:credentials] = Aws::SharedCredentials.new(profile_name: profile)
  end
  opt.parse!(ARGV)
end

ini = IniFile.load(File.expand_path('~/.aws/config'))
region = ENV['REGION'] || ini[profile]['region']
Aws.config[:region] = region

instances = []
# load cache if fresh
if File.exist?(CACHE) && options[:ignore].nil?
  mtime = File::Stat.new(CACHE).mtime
  if Time.now - mtime < CACHE_TTL
    cache = YAML.load_file(CACHE)
    instances = cache[profile][region]
  end
end

if instances.empty?
  ec2 = Aws::EC2::Client.new
  instances = ec2.describe_instances(
    filters: [{ name: 'instance-state-name', values: ['running'] }]
  ).reservations
  File.open(CACHE, 'w') do |f|
    cache = { profile => { region => instances } }
    YAML.dump(cache, f)
  end
end

instances.each do |reservation|
  reservation.instances.each do |instance|
    user = 'ec2-user'
    name = instance.instance_id
    dnsname = instance.public_dns_name || instance.private_dns_name
    instance.tags.each do |tag|
      name = tag.value if tag.key =~ /^name/i
      user = tag.value if tag.key =~ /^user/i
    end
    puts "\"#{name}\"\t#{user}@#{dnsname}\t#{instance.instance_id}"
  end
end
