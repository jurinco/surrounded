require 'triad'
require 'forwardable'
module Surrounded
  module Context
    class RoleMap
      extend Forwardable

      class << self
        def from_base(klass=::Triad)
          role_mapper = Class.new(self)
          Surrounded::Exceptions.define(role_mapper, exceptions: :ItemNotPresent, namespace: klass)
          role_mapper.container_class=(klass)
          role_mapper.def_delegators :container, :update, :each, :values, :keys
          role_mapper
        end

        def container_class=(klass)
          @container_class = klass
        end
      end

      def container
        @container ||= self.class.instance_variable_get(:@container_class).new
      end

      def role?(role)
        keys.include?(role)
      end

      def role_player?(object)
        !values(object).empty?
      rescue ::StandardError
        false
      end

      def assigned_player(role)
        values(role).first
      end
    end
  end
end