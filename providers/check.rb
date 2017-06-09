#
# Cookbook Name:: infra-cabot
# Provider:: check
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

      cabot_check_modify($current_check, $new_check)

      new_resource.updated_by_last_action(true)
    end
  when :none
    converge_by("#{ @new_resource } (Instance: #{@new_resource.name}) does not exist. Creating.") do
      Chef::Log.info("#{ @new_resource } (Instance: #{@new_resource.name}) does not exist. Creating.")

      cabot_check_create(new_resource)

      new_resource.updated_by_last_action(true)
    end
  end
end

#action :delete do
#  case @current_resource.exists
#  when :same, :modified
#    cabot_check_delete(current_resource)
#  end
#end

def load_current_resource
  @current_resource = Chef::Resource::CabotInstance.new(@new_resource.name)

  # Checking if check is already created
  if cabot_check_exists(@new_resource.name)
    $current_check = JSON.parse(cabot_check_get(@new_resource.name).to_json)
    $new_check = JSON.parse(check_to_json(@new_resource))
    Chef::Log.info "Comparing current and new checks"
    Chef::Log.info "Current check: #{$current_check}"
    Chef::Log.info "New check    : #{$new_check}"
    @current_resource.exists = :same
    @current_resource.exists = :modified unless $current_check["name"] == $new_check["name"]
    @current_resource.exists = :modified unless $current_check["active"].to_s.tr('"', '') == $new_check["active"]
    @current_resource.exists = :modified unless $current_check["importance"] == $new_check["importance"]
    @current_resource.exists = :modified unless $current_check["frequency"] == $new_check["frequency"]
    @current_resource.exists = :modified unless $current_check["debounce"] == $new_check["debounce"]
    @current_resource.exists = :modified unless $current_check["metric"] == $new_check["metric"]
    @current_resource.exists = :modified unless $current_check["check_type"] == $new_check["check_type"]
    @current_resource.exists = :modified unless $current_check["value"] == $new_check["value"]
    @current_resource.exists = :modified unless $current_check["expected_num_hosts"] == $new_check["expected_num_hosts"]
    @current_resource.exists = :modified unless $current_check["expected_num_metrics"] == $new_check["expected_num_metrics"]
    Chef::Log.info "Current check state is #{@current_resource.exists}"
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

# Convert check object to json
def check_to_json(check)
  return { :name => check.name, :active => check.active, :importance => check.importance , :frequency=> check.frequency, :debounce => check.debounce, :metric => check.metric, :check_type => check.check_type, :value => check.value, :expected_num_hosts => check.expected_num_hosts, :expected_num_metrics => check.expected_num_metrics }.to_json
end

# Check if check with given name exists
def cabot_check_exists(name)
  checks = JSON.parse(get_request("graphite_checks/").body)
  check = checks.find {|h1| h1['name']=="#{name}"} || JSON.parse("{}")
  Chef::Log.info "Checking if check with #{name} exists"  
  Chef::Log.info "Check is: #{check}"  
  if (check.key?("name") && check["name"] == "#{name}")
    Chef::Log.info "Check #{name} exists"  
    return true
  else
    Chef::Log.info "Check #{name} does not exists"  
    return false
  end
end

# Get an check by its unique name
def cabot_check_get(name)
  checks = JSON.parse(get_request("graphite_checks/").body)
  check = checks.find {|h1| h1['name']=="#{name}"}

  return check
end

# Create a check
def cabot_check_create(check)
  response = post_request(check_to_json(check), "POST", "graphite_checks/")
  new_check = JSON.parse(response.body)
  if response.code != "201"
      Chef::Log.error "Creating check failed. JSON: #{check_to_json(check)}.  HTTP response code is #{response.code}, response body is #{response.body}"
      raise "Creating check failed"
  else
      Chef::Log.info "Created check #{check.name}. HTTP response code is #{response.code}, response body is #{response.body}"
  end
end

def cabot_check_modify(current_check, new_check)
  Chef::Log.info "Current check: #{current_check}"
  Chef::Log.info "New check    : #{new_check}"
  new_check['id'] = current_check['id']
  response = post_request(new_check.to_json, "PUT", "graphite_checks/#{current_check['id']}/")
  if response.code != "200"
      Chef::Log.error "Modifying check failed. JSON: #{new_check.to_json}.  HTTP response code is #{response.code}, response body is #{response.body}"
      raise "Modifying check failed"
  else
      Chef::Log.info "Modified check #{new_check['name']}. HTTP response code is #{response.code}, response body is #{response.body}"
  end
end
