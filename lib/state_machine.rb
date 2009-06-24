module AASM
  class StateMachine
    def self.[](*args)
      (@machines ||= {})[args]
    end

    def self.[]=(*args)
      val = args.pop
      (@machines ||= {})[args] = val
    end
    
    attr_accessor :states, :events, :initial_state, :before_all_transition, :after_all_transition
    attr_reader :name
    
    def initialize(name)
      @name   = name
      @initial_state = nil
      @before_all_transition = nil
      @after_all_transition  = nil
      @states = []
      @events = {}
    end

    def create_state(name, options)
      @states << AASM::SupportingClasses::State.new(name, options) unless @states.include?(name)
    end
  end
end
