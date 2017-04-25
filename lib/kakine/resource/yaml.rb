module Kakine
  class Resource
    class Yaml
      class << self
        def load_security_group
          config = load_file(Kakine::Option.yaml_name)
          config.map {|sg| Kakine::SecurityGroup.new(Kakine::Option.tenant_name, sg) }
        end

        def load_file(filename)
          data = yaml(filename).reject {|k, _| k.start_with?('_') && k.end_with?('_') }
          validate_file_input(data)
          data.each do |name, params|
            params['rules'] = perform_desugar(perform_expansion(params['rules'])) if params['rules']
          end
        end

        def yaml(filename)
          YAML.load_file(filename).to_hash
        end

        def validate_file_input(load_sg)
          load_sg.each do |sg|
            validate_attributes(sg)
            validate_rules(sg)
          end
          true
        end

        def validate_attributes(sg)
          sg_name = sg[0]
          case
          when sg[1].nil?
            raise(Kakine::ConfigureError, "#{sg_name}:rules and description is required")
          when !sg[1].key?("rules")
            raise(Kakine::ConfigureError, "#{sg_name}:rules is required")
          when sg_name != 'default' && !sg[1].key?("description")
            raise(Kakine::ConfigureError, "#{sg_name}:description is required")
          end
        end

        def validate_rules(sg)
          sg_name = sg[0]
          sg[1]["rules"].each do |rule|
            case
            when !has_port?(rule)
              raise(Kakine::ConfigureError,  "#{sg_name}:rules port(icmp code) is required")
            when !has_remote?(rule)
              raise(Kakine::ConfigureError, "#{sg_name}:rules remote_ip or remote_group required")
            when !has_direction?(rule)
              raise(Kakine::ConfigureError, "#{sg_name}:rules direction is required")
            when !has_protocol?(rule)
              raise(Kakine::ConfigureError, "#{sg_name}:rules protocol is required")
            when !has_ethertype?(rule)
              raise(Kakine::ConfigureError, "#{sg_name}:rules ethertype is required")
            end
          end unless sg[1]["rules"].nil?
        end

        def has_port?(rule)
          rule.key?("port") ||
          ( rule.key?("port_range_max") && rule.key?("port_range_min") ) ||
          ( rule.key?("type") && rule.key?("code") )
        end

        def has_remote?(rule)
          rule.key?("remote_ip") || rule.key?("remote_group")
        end

        def has_direction?(rule)
          rule.key?("direction")
        end

        def has_protocol?(rule)
          rule.key?("protocol")
        end

        def has_ethertype?(rule)
          rule.key?("ethertype")
        end

        # [{key => [val0, val1], ...}] to [{key => val0, ...}, {key => val1, ...}]
        def expand_rules(rules, key)
          rules.flat_map do |rule|
            if rule[key].respond_to?(:to_ary)
              rule[key].to_ary.flatten.map do |val|
                rule.dup.tap {|rule| rule[key] = val }
              end
            else
              rule
            end
          end
        end

        def perform_expansion(rules)
          %w(remote_ip port protocol).each do |key|
            rules = expand_rules(rules, key)
          end

          rules
        end

        def perform_desugar(rules)
          rules.map do |rule|
            if rule['port'].is_a?(String) && rule['port'] =~ /\A(?<min>\d+)-(?<max>\d+)\z/
              rule.dup.tap do |rule|
                rule.delete('port')
                rule['port_range_min'] = $~[:min].to_i
                rule['port_range_max'] = $~[:max].to_i
              end
            else
              rule
            end
          end
        end
      end
    end
  end
end
