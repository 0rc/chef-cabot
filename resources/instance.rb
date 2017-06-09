actions :create, :modify
default_action :create

state_attrs :name,
            :address,
            :alerts_enabled,
            :email_alert,
            :hipchat_alert,
            :sms_alert,
            :telephone_alert,
            :status_checks,
            :users_to_notify,
            :hackpad_id,
            :check_groups

attribute :name, :kind_of => String, :default => nil, :required => true
attribute :address, :kind_of => String, :default => :name, :required => true
attribute :alerts_enabled, :kind_of => String, :default => 'true'
attribute :email_alert, :kind_of => String, :default => 'true'
attribute :hipchat_alert, :kind_of => String, :default => 'true'
attribute :sms_alert, :kind_of => String, :default => 'false'
attribute :telephone_alert, :kind_of => String, :default => 'false'
attribute :status_checks, :kind_of => Array, :default => []
attribute :users_to_notify, :kind_of => Array, :default => [1]
attribute :upper_node, :kind_of => Hash, :required => true
attribute :check_groups, :kind_of => Array, :default => []
attribute :api_url, :kind_of => String, :required => true
attribute :api_username, :kind_of => String, :required => true
attribute :api_password, :kind_of => String, :required => true

attr_accessor :exists
