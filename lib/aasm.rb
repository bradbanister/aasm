require File.join(File.dirname(__FILE__), 'event')
require File.join(File.dirname(__FILE__), 'state')
require File.join(File.dirname(__FILE__), 'state_machine')
require File.join(File.dirname(__FILE__), 'persistence')
require File.join(File.dirname(__FILE__), 'logging', 'logging')

module AASM
  class InvalidTransition < Exception
  end
  
  def self.included(base) #:nodoc:
    base.extend AASM::ClassMethods
    AASM::Persistence.set_persistence(base)
    AASM::StateMachine[base] = AASM::StateMachine.new('')
    base.send(:include, AASM::Logging::ActiveRecordLogging)

    base.class_eval do
      def base.inherited(klass)
        AASM::StateMachine[klass] = AASM::StateMachine[self].dup
      end
    end
  end

  module ClassMethods
    def aasm_before_all_transition(before_transition=nil)
      if before_transition
        AASM::StateMachine[self].before_all_transition = before_transition
      else
        AASM::StateMachine[self].before_all_transition
      end
    end

    def aasm_after_all_transition(after_transition=nil)
      if after_transition
        AASM::StateMachine[self].after_all_transition = after_transition
      else
        AASM::StateMachine[self].after_all_transition
      end
    end
    
    def aasm_initial_state(set_state=nil)
      if set_state
        AASM::StateMachine[self].initial_state = set_state
      else
        AASM::StateMachine[self].initial_state
      end
    end
    
    def aasm_initial_state=(state)
      AASM::StateMachine[self].initial_state = state
    end
    
    def aasm_state(name, options={})
      sm = AASM::StateMachine[self]
      sm.create_state(name, options)
      sm.initial_state = name unless sm.initial_state

      define_method("#{name.to_s}?") do
        aasm_current_state == name
      end
    end
    
    def aasm_event(name, options = {}, &block)
      sm = AASM::StateMachine[self]
      
      unless sm.events.has_key?(name)
        sm.events[name] = AASM::SupportingClasses::Event.new(name, options, &block)
      end

      define_method("#{name.to_s}!") do |*args|
        aasm_fire_event(name, true, true, *args)
      end

      define_method("#{name.to_s}") do |*args|
        aasm_fire_event(name, true, false, *args)
      end

      define_method("#{name.to_s}_not_persist") do |*args|
        aasm_fire_event(name, false, false, *args)
      end
    end

    def aasm_states
      AASM::StateMachine[self].states
    end

    def aasm_events
      AASM::StateMachine[self].events
    end
    
    def aasm_states_for_select
      AASM::StateMachine[self].states.map { |state| state.for_select }
    end
  end

  # Instance methods
  def aasm_current_state
    return @aasm_current_state if @aasm_current_state

    if self.respond_to?(:aasm_read_state) || self.private_methods.include?('aasm_read_state')
      @aasm_current_state = aasm_read_state
    end
    return @aasm_current_state if @aasm_current_state
    self.class.aasm_initial_state
  end

  def aasm_events_for_current_state
    aasm_events_for_state(aasm_current_state)
  end

  def aasm_events_for_state(state)
    events = self.class.aasm_events.values.select {|event| event.transitions_from_state?(state) }
    events.map {|event| event.name}
  end

  private
  def aasm_current_state_with_persistence=(state, use_bang=false)
    result = true
    if (self.respond_to?(:aasm_write_state) || self.private_methods.include?('aasm_write_state')) and !use_bang
      result = aasm_write_state(state)
      result = true if result.nil?
    end
    
    if (self.respond_to?(:aasm_write_state!) || self.private_methods.include?('aasm_write_state!')) and use_bang
      aasm_write_state!(state)
    end
    self.aasm_current_state = state if result
    result
  end

  def aasm_current_state=(state)
    if self.respond_to?(:aasm_write_state_without_persistence) || self.private_methods.include?('aasm_write_state_without_persistence')
      aasm_write_state_without_persistence(state)
    end
    @aasm_current_state = state
  end

  def aasm_state_object_for_state(name)
    self.class.aasm_states.find {|s| s == name}
  end

  def aasm_fire_transition_callback(callback,to_state=nil, *args)
    return if callback.blank?
    case callback
    when Symbol, String
      self.send(callback, *args)
    when Proc
      callback.call(self, *args) 
    end
  end
  
  # before firing an event, we make sure that we prepopulate
  # the args if we pass paramaters. We need to prepopulate the
  # args ONLY if we don't pass the transition to state as the
  # first parameter and there is only one possible state to go to
  def prepare_args_before_firing_event(name, *args)
    return args if args.length < 1
    event     = self.class.aasm_events[name]
    to_state  = args.first.blank? ? nil : args.first.to_s.to_sym
    to_states = event.get_to_states_when_transitioning_from(self.aasm_current_state) || []
    return args if to_state.nil? or to_states.include?(to_state)
    case to_states.length
    when 0:
      raise AASM::InvalidTransition.new("This event doesn't have any state to go to.")
    else
      args.insert(0, to_states.first)
    # else
    #   raise AASM::InvalidTransition.new("Please specify your destination state because this event can go to many states.")
    end
    args
  end

  # this method handles the exception caching and active record transaction
  # while firing the event. If we persist and use bang, we will
  # raise exception thrown, otherwise, just return false
  def aasm_fire_event(name, persist, use_bang = false, *args)
    begin
      args = prepare_args_before_firing_event(name, *args)
      puts "**args: #{args.inspect}" if self.aasm_current_state == :processed and name.to_s == 'ship'
      if self.is_a?(ActiveRecord::Base) and persist
        self.class.transaction do
          aasm_fire_event_helper(name, persist, use_bang, *args)
        end
      else
        aasm_fire_event_helper(name, persist, use_bang, *args)
      end
    rescue AASM::InvalidTransition => e
      raise e if use_bang
      return false
    rescue ActiveRecord::ActiveRecordError => e
      raise e if use_bang
      return false
    end
  end
  
  # this method is the one that actually execute the whole
  # transition. Order of execution:
  # - fire before_all_transition callback
  # - fire exit action for from state
  # - fire the event, which will:
  #   - call guard on transition
  #   - execute the on_transition callback
  # - fire enter action on the new state
  # - fire the aasm_event_fire
  # - log the transition
  # - set the new state (persist/non persist)  
  # - fire after_all_transition
  def aasm_fire_event_helper(name, persist, use_bang = false, *args)
    aasm_fire_transition_callback(self.class.aasm_before_all_transition)
    aasm_state_object_for_state(aasm_current_state).call_action(:exit, self, *args)

    new_state = self.class.aasm_events[name].fire(self, *args)
    current_state = self.aasm_current_state
    
    unless new_state.nil?
      aasm_state_object_for_state(new_state).call_action(:enter, self, *args)
      
      if self.respond_to?(:aasm_event_fired)
        self.aasm_event_fired(self.aasm_current_state, new_state)
      end

      result = true
      if persist
        # adding logging here
        self.do_log_transition(name, current_state, new_state, *args)
        
        result = self.send("aasm_current_state_with_persistence=", new_state, use_bang)
        self.send(self.class.aasm_events[name].success) if self.class.aasm_events[name].success
      else
        self.aasm_current_state = new_state
      end
      aasm_fire_transition_callback(self.class.aasm_after_all_transition)

      result
    else
      if self.respond_to?(:aasm_event_failed)
        self.aasm_event_failed(name)
      end
      
      false
    end
  end
end
