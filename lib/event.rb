require File.join(File.dirname(__FILE__), 'state_transition')

module AASM
  module SupportingClasses
    class Event
      attr_reader :name, :success
      
      def initialize(name, options = {}, &block)
        @name = name
        @success = options[:success]
        @transitions = []
        instance_eval(&block) if block
        validate_transitions
      end

      def fire(obj, to_state=nil, *args)
        transitions = @transitions.select { |t| t.from == obj.aasm_current_state }
        raise AASM::InvalidTransition if transitions.size == 0

        next_state = nil
        transitions.each do |transition|
          next if to_state and !Array(transition.to).include?(to_state)
          if transition.perform(obj, *args)
            next_state = to_state || Array(transition.to).first
            transition.execute(obj, *args)
            break
          end
        end
        next_state
      end

      def transitions_from_state?(state)
        @transitions.any? { |t| t.from == state }
      end

      def transitions_to_state?(state)
        @transitions.any? { |t| Array(t.to).include?(state) }
      end

      # get me all the possible states that the passed state
      # can go to when calling firing this event
      def get_to_states_when_transitioning_from(state)
        @transitions.inject([]) do |memo, t| 
          memo.concat(Array(t.to)) if t.from == state
          memo
        end
      end
      
      private
      
      def validate_transitions
        # since we can have multiple froms and tos,
        # we want to make sure that there is no confusion such as multiple transitions
        # that contain same from and to states.
        transitions = {}
        @transitions.each do |transition| 
          next if !transition
          if transitions.has_key?(transition.from)
            existing_tos    = transitions[transition.from]
            this_tos_array  = Array(transition.to)
            this_tos_set    = this_tos_array.to_set
            if existing_tos & this_tos_set
              raise AASM::InvalidTransition.new("You can't have transitions that have the same from state and to state.")
              return
            end
            transitions[transition.from] = existing_tos.merge(this_tos_array)
          else
            transitions[transition.from] = Array(transition.to).to_set
          end
        end
      end
      
      def transitions(trans_opts)
        Array(trans_opts[:from]).each do |s|
          transition = SupportingClasses::StateTransition.new(trans_opts.merge({:from => s.to_sym}))
          @transitions << transition
        end
      end
    end
  end
end
