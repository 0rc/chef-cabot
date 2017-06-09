actions :create, :modify
default_action :create

state_attrs :name,
            :active,
            :importance,
            :frequency,
            :debounce,
            :metric,
            :check_type,
            :value,
            :expected_num_hosts

attribute :name, :kind_of => [String, NilClass], :default => nil, :required => true
attribute :active, :kind_of => String, :default => "true"
attribute :importance, :kind_of => String, :default => 'WARNING'
attribute :frequency, :kind_of => Integer, :default => 5
attribute :debounce, :kind_of => Integer, :default => 1
attribute :metric, :kind_of => String, :required => true
attribute :check_type, :kind_of => String, :default => '<'
attribute :value, :kind_of => String, :required => true
attribute :expected_num_hosts, :kind_of => Integer, :default => 0
attribute :expected_num_metrics, :kind_of => Integer, :default => 0
attribute :api_url, :kind_of => String, :required => true
attribute :api_username, :kind_of => String, :required => true
attribute :api_password, :kind_of => String, :required => true

attr_accessor :exists
