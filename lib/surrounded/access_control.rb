module Surrounded
  module AccessControl
    def self.extended(base)
      base.send(:include, AccessMethods)
      base.const_set(:'AccessError', Class.new(StandardError))
    end
    
    private
    
    def disallow(*names, &block)
      names.map do |name|
        define_access_method(name, &block)
      end
    end
    
    def redo_method(name)
      class_eval %{
        def #{name}
          begin
            apply_roles if __apply_role_policy == :trigger
            
            method_restrictor = "disallow_#{name}?"
            if self.respond_to?(method_restrictor, true) && self.send(method_restrictor)
              raise ::Surrounded::Context::AccessError.new("access to #{self.name}##{name} is not allowed")
            end
            
            self.send("__trigger_#{name}")

          ensure
            remove_roles if __apply_role_policy == :trigger
          end
        end
      }
    end
    
    def define_access_method(name, &block)
      class_eval {
        meth = AccessMethods.instance_method(:with_roles)
        define_method "disallow_#{name}?" do
          begin
            apply_roles if __apply_role_policy == :trigger
            instance_exec(&block)
          ensure
            remove_roles if __apply_role_policy == :trigger
          end
        end
      }
    end
    
    module AccessMethods
      def all_triggers
        self.class.triggers
      end
    
      def triggers
        all_triggers.select {|name|
          method_restrictor = "disallow_#{name}?"
          !self.respond_to?(method_restrictor, true) || !self.send(method_restrictor)
        }.to_set
      end
      
      def with_roles(policy = :trigger)
        begin
          apply_roles if __apply_role_policy == policy
          yield
        ensure
          remove_roles if __apply_role_policy == policy
        end
      end
    end
  end
end