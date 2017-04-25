module Kakine
  class Builder
    class << self
      def create_security_group(sg)
        attributes = { name: sg.name, description: sg.description, tenant_id: sg.tenant_id }
        security_group_id = Kakine::Adapter.instance.create_security_group(attributes)
        delete_default_security_rule(sg.tenant_name, sg.name)
        security_group_id
      end

      def delete_security_group(sg)
        Kakine::Adapter.instance.delete_security_group(sg.id)
      end

      def first_create_security_group(new_sg)
        create_security_group(new_sg)
        new_sg.rules.map do |rule|
          create_security_rule(new_sg.tenant_name, new_sg.name, rule)
        end if new_sg.has_rules?
      end

      def clean_up_security_group(new_sgs, current_sgs)
        current_sgs.map do |current_sg|
          delete_security_group(current_sg) if new_sgs.none? { |new_sg| current_sg.name == new_sg.name }
        end
      end

      def convergence_security_group(new_sg, current_sg)
        if new_sg.name != 'default' && new_sg.description != current_sg.description
          delete_security_group(current_sg)
          first_create_security_group(new_sg)
        else
          clean_up_security_rule(new_sg, current_sg)
          first_create_rule(new_sg, current_sg)
        end
      end

      def already_setup_security_group(new_sg, current_sgs)
        current_sgs.find { |current_sg| current_sg.name == new_sg.name }
      end

      def create_security_rule(tenant_name, sg_name, rule)
        sg = Kakine::Resource.get(:openstack).security_group(tenant_name, sg_name)
        security_group_id =  Kakine::Option.dryrun? && sg.nil? ? Kakine::Adapter.instance.id(sg_name) : sg.id
        Kakine::Adapter.instance.create_rule(security_group_id, rule.direction, rule)
      end

      def delete_security_rule(tenant_name, sg_name, rule)
        Kakine::Adapter.instance.delete_rule(rule.id)
      end

      def delete_default_security_rule(tenant_name, sg_name)
        target_sg = Kakine::Resource.get(:openstack).load_security_group.find do |sg|
          sg.name == sg_name
        end

        target_sg.rules.map do |rule|
          delete_security_rule(tenant_name, sg_name, rule)
        end if target_sg
      end

      def first_create_rule(new_sg, current_sg)
        new_sg.rules.map do |rule|
          unless current_sg.find_by_rule(rule)
            create_security_rule(new_sg.tenant_name, new_sg.name, rule)
          end
        end
      end

      def clean_up_security_rule(new_sg, current_sg)
        current_sg.rules.map do |rule|
          delete_security_rule(new_sg.tenant_name, new_sg.name, rule) unless new_sg.find_by_rule(rule)
        end
      end

      def security_groups
        sgs = Kakine::Resource.get(:openstack).security_groups_hash
        delete_id_column(sgs).to_yaml
      end

      def delete_id_column(sgs)
        case sgs
        when Array
          sgs.map { |sg| delete_id_column(sg) }
        when Hash
          sgs.inject({}) do |hash, (k, v)|
            hash[k] = delete_id_column(v) if k != "id"
            hash
          end
        else
          sgs
        end
      end
    end
  end
end
