#
# Cookbook Name:: infra-cabot
# Provider:: service
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

      cabot_service_modify($current_service, $new_service)

      new_resource.updated_by_last_action(true)
    end
  when :none
    converge_by("#{ @new_resource } (Service: #{@new_resource.name}) does not exist. Creating.") do
      Chef::Log.info("#{ @new_resource } (Service: #{@new_resource.name}) does not exist. Creating.")
      @new_resource = cabot_service_associate_checks(@new_resource)

      cabot_service_create(@new_resource)

      new_resource.updated_by_last_action(true)
    end
  end
end

#action :delete do
#  case @current_resource.exists
#  when :same, :modified
#    cabot_service_delete(current_resource)
#  end
#end

def load_current_resource
  @current_resource = Chef::Resource::CabotService.new(@new_resource.name)

  # Checking if service is already created
  if cabot_service_exists(@new_resource.name)
    $current_service = JSON.parse(cabot_service_get(@new_resource.name).to_json)
    @new_resource = cabot_service_associate_checks(@new_resource)
    $new_service = JSON.parse(service_to_json(@new_resource))
    Chef::Log.info "Comparing current and new services"
    Chef::Log.info "Current service: #{$current_service}"
    Chef::Log.info "New service    : #{$new_service}"
    @current_resource.exists = :same
    @current_resource.exists = :modified unless $current_service["name"] == $new_service["name"]
    @current_resource.exists = :modified unless $current_service["url"] == $new_service["url"]
    @current_resource.exists = :modified unless $current_service["email_alert"].to_s.tr('"', '') == $new_service["email_alert"]
    @current_resource.exists = :modified unless $current_service["hipchat_alert"].to_s.tr('"', '') == $new_service["hipchat_alert"]
    @current_resource.exists = :modified unless $current_service["sms_alert"].to_s.tr('"', '') == $new_service["sms_alert"]
    @current_resource.exists = :modified unless $current_service["telephone_alert"].to_s.tr('"', '') == $new_service["telephone_alert"]
    @current_resource.exists = :modified unless $current_service["alerts_enabled"].to_s.tr('"', '') == $new_service["alerts_enabled"]
    @current_resource.exists = :modified unless $current_service["status_checks"] == $new_service["status_checks"]
    Chef::Log.info "Current service state is #{@current_resource.exists}"
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

# Convert service object to json
def service_to_json(service)
  return { :name => service.name, :users_to_notify => service.users_to_notify, :alerts_enabled => service.alerts_enabled, :status_checks => service.status_checks,  :email_alert => service.email_alert, :hipchat_alert => service.hipchat_alert, :sms_alert => service.sms_alert, :telephone_alert => service.telephone_alert, :hackpad_id => nil, :url => service.url }.to_json
end

# Convert service object to hash
def service_to_hash(service)
  return { :name => service.name, :users_to_notify => service.users_to_notify, :alerts_enabled => service.alerts_enabled, :status_checks => service.status_checks,  :email_alert => service.email_alert, :hipchat_alert => service.hipchat_alert, :sms_alert => service.sms_alert, :telephone_alert => service.telephone_alert, :hackpad_id => nil, :url => service.url }
end

# Check if service with given name exists
def cabot_service_exists(name)
  services = JSON.parse(get_request("services/").body)
  service = services.find {|h1| h1['name']=="#{name}"} || JSON.parse("{}")
  Chef::Log.info "Checking if service with #{name} exists"  
  Chef::Log.info "Service is: #{service}"  
  if (service.key?("name") && service["name"] == "#{name}")
    Chef::Log.info "Service #{name} exists"  
    return true
  else
    Chef::Log.info "Service #{name} does not exists"  
    return false
  end
end

# Get a service by its unique name
def cabot_service_get(name)
  services = JSON.parse(get_request("services/").body)
  service = services.find {|h1| h1['name']=="#{name}"}

  return service
end

# Get a service by its unique name
def cabot_checks_get_id(name)
  checks = JSON.parse(get_request("graphite_checks/").body)
  check = checks.find {|h1| h1['name']=="#{name}"}
  Chef::Log.info "Checks are #{checks}"
  Chef::Log.info "Looking for check with name #{name}"
  Chef::Log.info "Check is #{check}"
  return check['id']
end

# Create a service
def cabot_service_create(service)
  response = post_request(service_to_json(service), "POST", "services/")
  new_service = JSON.parse(response.body)
  if response.code != "201"
      Chef::Log.error "Creating service failed. JSON: #{service_to_json(service)}.  HTTP response code is #{response.code}, response body is #{response.body}"
      raise "Creating service failed"
  else
      Chef::Log.info "Created service #{service.name}. HTTP response code is #{response.code}, response body is #{response.body}"
  end
end

#Modify a service
def cabot_service_modify(current_service, new_service)
  Chef::Log.info "Current service: #{current_service}"
  Chef::Log.info "New service    : #{new_service}"
  new_service['id'] = current_service['id'].to_s
  response = post_request(new_service.to_json, "PUT", "services/#{current_service['id']}/")
  if response.code != "200"
      Chef::Log.error "Modifying service failed. JSON: #{new_service.to_json}.  HTTP response code is #{response.code}, response body is #{response.body}"
      raise "Modifying service failed"
  else
      Chef::Log.info "Modified service #{new_service['name']}. HTTP response code is #{response.code}, response body is #{response.body}"
  end
end

#Set associations between service and checks
def cabot_service_associate_checks(resource)
  resource.status_checks.clear
  resource.check_groups.each do |check_group|
    @new_resource.upper_node['checks']["#{check_group}"].each do |check|
      Chef::Log.info "Processing check #{check}"
      check_id = cabot_checks_get_id(check['name'])
      resource.status_checks.push(check_id) unless resource.status_checks.include?(check_id)
    end
  end
  Chef::Log.info "Currently service is associated with following checks: #{resource.status_checks}"
  return resource
end
