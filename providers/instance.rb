#
# Cookbook Name:: infra-cabot
# Provider:: instances
#


require 'net/http'
require "uri"
require 'json'
include Chef::Mixin::ShellOut

def whyrun_supported?
  true
end

# Default action
action :create do
  case @current_resource.exists
  when :same
    Chef::Log.debug("#{ @new_resource } wasn't modified.")
  when :modified
    converge_by("#{ @new_resource } was modified. Modifying.") do
      Chef::Log.info("#{ @new_resource } was modified. Modifying.")

      cabot_instance_modify($current_instance, $new_instance)

      @new_resource.updated_by_last_action(true)
    end
  when :none
    converge_by("#{ @new_resource } (Instance: #{@new_resource.name}) does not exist. Creating.") do
      Chef::Log.info("#{ @new_resource } (Instance: #{@new_resource.name}) does not exist. Creating.")

      cabot_instance_create(new_resource)

      @new_resource.updated_by_last_action(true)
    end
  end
end

#action :delete do
#  case @current_resource.exists
#  when :same, :modified
#    cabot_instance_delete(current_resource)
#  end
#end

def load_current_resource
  @current_resource = Chef::Resource::CabotInstance.new(@new_resource.name)

  # Checking if instance is already created
  if cabot_instance_exists(@new_resource.name)
    $current_instance = JSON.parse(cabot_instance_get(@new_resource.name).to_json)
    @new_resource = cabot_instance_associate_checks(@new_resource)
    $new_instance = JSON.parse(instance_to_json(@new_resource))
    Chef::Log.info "Comparing current and new instances"
    Chef::Log.info "Current instance: #{$current_instance}"
    Chef::Log.info "New instance    : #{$new_instance}"
    @current_resource.exists = :same
    @current_resource.exists = :modified unless $current_instance["name"] == $new_instance["name"]
    @current_resource.exists = :modified unless $current_instance["address"] == $new_instance["address"]
    @current_resource.exists = :modified unless $current_instance["email_alert"].to_s.tr('"', '') == $new_instance["email_alert"]
    @current_resource.exists = :modified unless $current_instance["hipchat_alert"].to_s.tr('"', '') == $new_instance["hipchat_alert"]
    @current_resource.exists = :modified unless $current_instance["sms_alert"].to_s.tr('"', '') == $new_instance["sms_alert"]
    @current_resource.exists = :modified unless $current_instance["telephone_alert"].to_s.tr('"', '') == $new_instance["telephone_alert"]
    @current_resource.exists = :modified unless $current_instance["alerts_enabled"].to_s.tr('"', '') == $new_instance["alerts_enabled"]
    @current_resource.exists = :modified unless $current_instance["status_checks"] == $new_instance["status_checks"]
    Chef::Log.info "Current instance state is #{@current_resource.exists}"
  else
    @current_resource.exists = :none
  end
  
  @current_resource
end

# Get request obj
def post_request(body, request_type, request_path)
  Chef::Log.info "Performing a POST with body #{body} to #{@new_resource.api_url + request_path}"  
  uri = URI.parse(@new_resource.api_url)
  http = Net::HTTP.new(uri.host, uri.port)
  if request_type == "POST"
    request = Net::HTTP::Post.new(@new_resource.api_url + request_path, initheader = {'Content-Type' =>'application/json'})
  elsif request_type == "PUT"
    request = Net::HTTP::Put.new(@new_resource.api_url + request_path, initheader = {'Content-Type' =>'application/json'})
  else
    raise "unknown request type: #{request_type}"
  end
  request.basic_auth(@new_resource.api_username, @new_resource.api_password)
  request.body = body
  return http.request(request)
end

# Perform get request
def get_request(request_path)
  uri = URI.parse(@new_resource.api_url)
  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Get.new(@new_resource.api_url + request_path)
  request.basic_auth(@new_resource.api_username, @new_resource.api_password)
  response = http.request(request)
  return response
end

# Convert instance object to json
def instance_to_json(instance)
  return { :name => instance.name, :users_to_notify => instance.users_to_notify, :alerts_enabled => instance.alerts_enabled, :status_checks => instance.status_checks,  :email_alert => instance.email_alert, :hipchat_alert => instance.hipchat_alert, :sms_alert => instance.sms_alert, :telephone_alert => instance.telephone_alert, :hackpad_id => nil, :address => instance.address }.to_json
end

# Convert instance object to hash
def instance_to_hash(instance)
  return { :name => instance.name, :users_to_notify => instance.users_to_notify, :alerts_enabled => instance.alerts_enabled, :status_checks => instance.status_checks,  :email_alert => instance.email_alert, :hipchat_alert => instance.hipchat_alert, :sms_alert => instance.sms_alert, :telephone_alert => instance.telephone_alert, :hackpad_id => nil, :address => instance.address }
end

# Check if instance with given name exists
def cabot_instance_exists(name)
  instances = JSON.parse(get_request("instances/").body)
  instance = instances.find {|h1| h1['name']=="#{name}"} || JSON.parse("{}")
  Chef::Log.info "Checking if instance with #{name} exists"  
  Chef::Log.info "Instance is: #{instance}"  
  if (instance.key?("name") && instance["name"] == "#{name}")
    Chef::Log.info "Instance #{name} exists"  
    return true
  else
    Chef::Log.info "Instance #{name} does not exists"  
    return false
  end
end

# Get an instance by its unique name
def cabot_instance_get(name)
  instances = JSON.parse(get_request("instances/").body)
  instance = instances.find {|h1| h1['name']=="#{name}"}

  return instance
end

# Get an instance by its unique name
def cabot_checks_get_id(name)
  checks = JSON.parse(get_request("graphite_checks/").body)
  check = checks.find {|h1| h1['name']=="#{name}"}
  Chef::Log.info "Checks are #{checks}"
  Chef::Log.info "Looking for check with name #{name}"
  Chef::Log.info "Check is #{check}"
  return check['id']
end

# Create an instance
def cabot_instance_create(instance)
  response = post_request(instance_to_json(instance), "POST", "instances/")
  new_instance = JSON.parse(response.body)
  if response.code != "201"
      Chef::Log.error "Creating instance failed. JSON: #{instance_json}.  HTTP response code is #{response.code}, response body is #{response.body}"
      raise "Creating instance failed"
  else
      Chef::Log.info "Created instance #{instance.name}. HTTP response code is #{response.code}, response body is #{response.body}"
  end
end

#Modify an instance
def cabot_instance_modify(current_instance, new_instance)
  Chef::Log.info "Current instance: #{current_instance}"
  Chef::Log.info "New instance    : #{new_instance}"
  new_instance['id'] = current_instance['id'].to_s
  response = post_request(new_instance.to_json, "PUT", "instances/#{current_instance['id']}/")
  if response.code != "200"
      Chef::Log.error "Modifying instance failed. JSON: #{new_instance.to_json}.  HTTP response code is #{response.code}, response body is #{response.body}"
      raise "Modifying instance failed"
  else
      Chef::Log.info "Modified instance #{new_instance['name']}. HTTP response code is #{response.code}, response body is #{response.body}"
  end
end

#Set associations between instance and checks
def cabot_instance_associate_checks(resource)
#  instance['status_checks'] = []
Chef::Log.info "Checks: #{@new_resource.upper_node.to_json}"
  resource.check_groups.each do |check_group|
    @new_resource.upper_node['checks']["#{check_group}"].each do |check|
      Chef::Log.info "Processing check #{check}"
      check_id = cabot_checks_get_id(check['name'])
      resource.status_checks.push(check_id) unless resource.status_checks.include?(check_id)
    end
  end
  Chef::Log.info "Currently instance is associated with following checks: #{resource.status_checks}"
  return resource
end
