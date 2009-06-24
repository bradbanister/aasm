require File.join(File.dirname(__FILE__), '../../lib/aasm')
require File.dirname(__FILE__) + '/../../../../../test/test_helper'

ActiveRecord::Base.connection.create_table :test_orders, :force => true do |t|
  t.string :status
end


class Order < ActiveRecord::Base
  set_table_name "test_orders"
  include AASM
  aasm_column :status
  aasm_log_method :my_log_method
  aasm_initial_state :received
  aasm_state :processed
  aasm_state :shipped
  aasm_state :received
  aasm_state :forbidden, :enter => Proc.new {|o, *args| o.update_attribute(:status, 'whatever')}
  aasm_state :error

  aasm_event :process do
    transitions :from => [:received, :processed], :to => :processed
  end

  aasm_event :forbid do
    transitions :from => [:received, :processed], :to => :forbidden
  end

  aasm_event :donot do
    transitions :from => [:received, :processed], :to => :error
  end

  attr_accessor :log_var
  
  validate :fail_on_error


  aasm_event :ship do
    transitions :from => :processed, :to => :shipped
  end

  def fail_on_error
    if self.aasm_current_state == :error
      errors.add(:status, "error")
      return false 
    end
    true
  end

  def my_log_method(*args)
    self.state_change_detected = status_changed?
    self.log_var = args.first
  end
  
  def aasm_forbid_log(*arg)
    raise Exception
  end
  
  def aasm_ship_log(*args)
    self.state_change_detected = status_changed?
    self.log_var = args.first
  end
  
  def state_change_detected
    @state_change_detected || false
  end
  def state_change_detected=(value)
    @state_change_detected = value
  end
end

class OrderTest < Test::Unit::TestCase
  
  def test_logging_with_specific_log_method_name
    o = Order.create(:status => :processed)
    assert_equal :processed, o.aasm_current_state
    
    o.ship!(:shipped, true)
    assert o.state_change_detected
    assert o.log_var
    assert_equal :shipped, o.aasm_current_state
  end

  def test_logging_with_common_log_method_name
    o = Order.create
    assert_equal :received, o.aasm_current_state
    o.log_var = false
    o.process!(:processed, true)
    assert o.state_change_detected
    assert o.log_var
    assert_equal :processed, o.aasm_current_state
  end

  def test_logging_donot_log
    o = Order.create
    o.aasm_log_transition = false
    assert_equal :received, o.aasm_current_state
    
    o.process!(:processed, true)
    assert !o.state_change_detected
    assert_equal :processed, o.aasm_current_state
  end

  def test_transaction
    o = Order.create

    # make sure we return false when something bad happen during the execution
    begin
      o.forbid(:forbidden, true)
    rescue Exception
    end
    # we update the status when entering the forbidden state and save to database.
    # need to make sure that it doesn't persist
    fresh_o = Order.find(o.id)
    assert_equal 'received', fresh_o.status
  end
  
  def test_bang_with_error
    o = Order.create

    # make sure we return false when something bad happen during the execution
    assert_raise(ActiveRecord::RecordInvalid) {o.donot!(:error, true) }
  end
end