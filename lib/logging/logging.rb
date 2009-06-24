module AASM
  module Logging
    module ActiveRecordLogging
      
      def self.included(base)
        base.extend AASM::Logging::ActiveRecordLogging::ClassMethods
        base.send(:include, AASM::Logging::ActiveRecordLogging::InstanceMethods)
        base.class_eval do
          attr_accessor :aasm_old_state, :aasm_new_state, :aasm_event_name
        end
      end
    
      module ClassMethods 
        def aasm_log_method(value)
          @log_method = value.to_sym unless value.blank?
        end
        
        def aasm_log_method_name
          @log_method || :aasm_log_transition
        end        
      end
    
      module InstanceMethods
        def aasm_log_transition?
          return true if @aasm_log_transition.nil?
          @aasm_log_transition
        end
        
        def aasm_log_transition=(value)
          @aasm_log_transition = value
        end
        
        def do_log_transition(event_name, old_state, new_state, to_state=nil, *args)
          return if !self.aasm_log_transition?
          self.aasm_event_name  = event_name
          self.aasm_old_state   = old_state
          self.aasm_new_state   = new_state
          
          # by calling this method, we set the state column to
          # new state. This way, we can detect what kind of change
          # has been made to model (especially to the state column)
          # when logging
          write_attribute(self.class.aasm_column, new_state.to_s) if self.class.respond_to?(:aasm_column)

          specific_log_method_name = "aasm_#{event_name}_log".to_sym
          generic_log_method_name  = self.class.aasm_log_method_name.to_sym
          if self.respond_to?(specific_log_method_name)
            # if we specify a special log (aasm_{event_name}_log), use that
            self.send(specific_log_method_name.to_sym, *args)
          elsif generic_log_method_name and self.respond_to?(generic_log_method_name)
            # if we have log_transition_method, call that instead
            self.send(generic_log_method_name.to_sym, *args)
          end
        rescue Exception => e
          #puts "error: #{e.backtrace}"
          logger.error(e)
        end
        
      end
    end
  end
end
