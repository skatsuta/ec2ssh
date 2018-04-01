#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
require 'aws-sdk-ec2'
require 'pp'
require 'inifile'
require 'optparse'
require 'yaml'

CONFIG = File.join(Dir.home, '.aws', 'config').freeze
CACHE = File.join(Dir.home, '.ec2ssh').freeze
CACHE_TTL = 3600
INSTANCE = Struct.new(:instance_id, :public_ip_address, :private_ip_address, :tags)

profile = 'default'
options = {}
OptionParser.new do |opt|
  opt.banner = "Usage: #{opt.program_name} [options]"
  opt.on('-h', '--help', 'Show usage') do
    puts opt.help
    exit
  end
  opt.on('-f', '--flush', 'Flush cache') { options[:ignore] = true }
  opt.on('-p', '--profile PROFILE', 'Specify profile') do |v|
    profile = "profile #{v}"
    Aws.config[:credentials] = Aws::SharedCredentials.new(profile_name: profile)
  end
  opt.parse!(ARGV)
end

ini = IniFile.load(CONFIG)
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
  ).reservations.flat_map(&:instances).map! do |instance|
    INSTANCE.new(instance.instance_id,
                 instance.public_ip_address,
                 instance.private_ip_address,
                 instance.tags)
  end
  File.open(CACHE, 'w') do |f|
    cache = { profile => { region => instances } }
    YAML.dump(cache, f)
  end
end

instances.each do |instance|
  user = 'ec2-user'
  name = instance.instance_id
  ip_address = instance.public_ip_address || instance.private_ip_address
  instance.tags.each do |tag|
    name = tag.value if tag.key =~ /^name/i
    user = tag.value if tag.key =~ /^user/i
  end
  puts "\"#{name}\"\t#{user}@#{ip_address}\t#{instance.instance_id}"
end
