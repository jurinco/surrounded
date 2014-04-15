require 'set'
require 'surrounded/context/role_map'
require 'surrounded/context/role_builders'
require 'surrounded/context/initializing'
require 'surrounded/context/trigger_controls'
require 'surrounded/access_control'
require 'surrounded/shortcuts'
require 'surrounded/east_oriented'

# Extend your classes with Surrounded::Context to handle their
# initialization and application of behaviors to the role players
# passed into the constructor.
#
# The purpose of this module is to help you create context objects
# which encapsulate the interaction and behavior of objects inside.
module Surrounded
  module Context
    def self.extended(base)
      base.class_eval {
        extend RoleBuilders, Initializing

        @triggers = Set.new
        include InstanceMethods

        trigger_mod = Module.new
        const_set('TriggerMethods', trigger_mod)
        include trigger_mod

        extend TriggerControls
      }
    end

    private

    # Set the default type of implementation for role methods for all contexts.
    def self.default_role_type
      @default_role_type ||= :module
    end

    class << self
      attr_writer :default_role_type
    end
    
    # Provide the ability to create access control methods for your triggers.
    def protect_triggers;  self.extend(::Surrounded::AccessControl); end
    
    # Automatically create class methods for each trigger method.
    def shortcut_triggers; self.extend(::Surrounded::Shortcuts); end
    
    # Automatically return the context object from trigger methods.
    def east_oriented_triggers; self.extend(::Surrounded::EastOriented); end

    def default_role_type
      @default_role_type ||= Surrounded::Context.default_role_type
    end

    # Set the default type of implementation for role method for an individual context.
    def default_role_type=(type)
      @default_role_type = type
    end
    
    # === Utility shortcuts
    
    # Set a named constant and make it private
    def private_const_set(name, const)
      unless self.const_defined?(name, false)
        const = const_set(name, const)
        private_constant name.to_sym
      end
      const
    end

    # Create attr_reader for the named methods and make them private
    def private_attr_reader(*method_names)
      attr_reader(*method_names)
      private(*method_names)
    end

    # Conditional const_get for a named role behavior
    def role_const(name)
      if role_const_defined?(name)
        const_get(name)
      end
    end

    def role_const_defined?(name)
      const_defined?(name, false)
    end

    module InstanceMethods
      # Check whether a given name is a role inside the context.
      # The provided block is used to evaluate whether or not the caller
      # is allowed to inquire about the roles.
      def role?(name, &block)
        return false unless role_map.role?(name)
        accessor = block.binding.eval('self')
        role_map.role_player?(accessor) && role_map.assigned_player(name)
      end

      # Check if a given object is a role player in the context.
      def role_player?(obj)
        role_map.role_player?(obj)
      end

      # Return a Set of all defined triggers
      def triggers
        self.class.triggers
      end

      private

      def role_map
        @role_map ||= RoleMap.new
      end

      def map_roles(role_object_array)
        role_object_array.each do |role, object|
          if self.respond_to?("map_role_#{role}")
            self.send("map_role_#{role}", object)
          else
            map_role(role, role_behavior_name(role), object)
            map_role_collection(role, role_behavior_name(role), object)
          end
        end
      end

      def map_role_collection(role, mod_name, collection)
        singular_role_name = singularize_name(role)
        singular_behavior_name = singularize_name(role_behavior_name(role))
        if collection.respond_to?(:each_with_index) && role_const_defined?(singular_behavior_name)
          collection.each_with_index do |item, index|
            map_role(:"#{singular_role_name}_#{index + 1}", singular_behavior_name, item)
          end
        end
      end

      def map_role(role, mod_name, object)
        instance_variable_set("@#{role}", object)
        role_map.update(role, role_module_basename(mod_name), object)
      end

      def add_interface(role, behavior, object)
        if behavior && role_const_defined?(behavior)
          applicator = role_const(behavior).is_a?(Class) ? method(:add_class_interface) : method(:add_module_interface)

          role_player = applicator.call(object, role_const(behavior))
          map_role(role, behavior, role_player)
        end
        role_player || object
      end

      def add_module_interface(obj, mod)
        adder_name = module_extension_methods.find{|meth| obj.respond_to?(meth) }
        return obj if !adder_name

        obj.method(adder_name).call(mod)
        obj
      end

      def add_class_interface(obj, klass)
        wrapper_name = wrap_methods.find{|meth| klass.respond_to?(meth) }
        return obj if !wrapper_name
        klass.method(wrapper_name).call(obj)
      end

      def remove_interface(role, behavior, object)
        if behavior && role_const_defined?(behavior)
          remover_name = (module_removal_methods + unwrap_methods).find{|meth| object.respond_to?(meth) }
        end

        if remover_name
          role_player = object.send(remover_name)
        end

        role_player || object
      end

      def apply_roles
        role_map.each do |role, mod_name, object|
          player = add_interface(role, mod_name, object)
          player.send(:store_context, self) do; end
        end
      end

      def remove_roles
        role_map.each do |role, mod_name, player|
          if player.respond_to?(:remove_context, true)
            player.send(:remove_context) do; end
          end
          remove_interface(role, mod_name, player)
        end
      end

      # List of possible methods to use to add behavior to an object from a module.
      def module_extension_methods
        [:cast_as, :extend]
      end

      # List of possible methods to use to add behavior to an object from a wrapper.
      def wrap_methods
        [:new]
      end

      # List of possible methods to use to remove behavior from an object with a module.
      def module_removal_methods
        [:uncast]
      end

      # List of possible methods to use to remove behavior from an object with a wrapper.
      def unwrap_methods
        [:__getobj__]
      end

      def role_behavior_name(role)
        role.to_s.gsub(/(?:^|_)([a-z])/) { $1.upcase }.sub(/_\d+/,'')
      end

      def role_module_basename(mod)
        mod.to_s.split('::').last
      end

      def role_const(name)
        self.class.send(:role_const, name)
      end

      def role_const_defined?(name)
        self.class.send(:role_const_defined?, name)
      end

      def singularize_name(name)
        if name.respond_to?(:singularize)
          name.singularize
        else
          # good enough for now but should be updated with better rules
          name.to_s.tap do |string|
            if string =~ /ies\z/
              string.sub!(/ies\z/,'y')
            elsif string =~ /s\z/
              string.sub!(/s\z/,'')
            end
          end
        end
      end
    end
  end
end