require 'test_helper'
require 'tire'
require 'sidekiq'
require 'resque'
require 'tire_async_index'

class AmUser
  extend ActiveModel::Callbacks
  define_model_callbacks :save, :destroy

  include Tire::Model::AsyncCallbacks
  attr_accessor :id

  def save
    run_callbacks :save do
    end
  end

  def destroy
    run_callbacks :destroy do
    end
  end
end

describe TireAsyncIndex do

  before(:all) do
    TireAsyncIndex.configuration = TireAsyncIndex::Configuration.new
  end

  context "configurable" do
    it "valid default config settings" do
      TireAsyncIndex.queue.should eql :normal
      TireAsyncIndex.engine.should eql :none
    end

    it "set queue name" do
      TireAsyncIndex.configure do |config|
        config.use_queue :high
      end

      TireAsyncIndex.queue.should eql :high
    end

    it "should be able to set sidekiq as engine" do
      TireAsyncIndex.configure do |config|
        config.background_engine :sidekiq
      end

      TireAsyncIndex.engine.should eql :sidekiq
    end

    it "should be able to set resque as engine" do
      TireAsyncIndex.configure do |config|
        config.background_engine :resque
      end

      TireAsyncIndex.engine.should eql :resque
    end

    it "should not be able to set not supported engine" do
      expect {
        TireAsyncIndex.configure do |config|
          config.background_engine :some_engine
        end
      }.to raise_error(TireAsyncIndex::EngineNotFound)
    end
  end

  context "integration" do

    describe '#after_save' do
      it "should not start backroub on no engine" do
        TireAsyncIndex.configure do |config|
          config.background_engine :none
        end
        a    = AmUser.new.tap { |a| a.id = 23 }
        tire = double(:Tire)
        a.stub(:tire) { tire }
        tire.should_receive(:update_index)
        a.save
      end

      it "should start sidekiq" do
        TireAsyncIndex.configure do |config|
          config.background_engine :sidekiq
        end

        TireAsyncIndex::Workers::Sidekiq.should_receive(:perform_async).with(:update, "AmUser", instance_of(Fixnum))

        AmUser.new.tap { |a| a.id = 23 }.save
      end

      it "should start resque" do
        TireAsyncIndex.configure do |config|
          config.background_engine :resque
        end

        Resque.should_receive(:enqueue).with(TireAsyncIndex::Workers::Resque, :update, "AmUser", instance_of(Fixnum))

        AmUser.new.tap { |a| a.id = 23 }.save
      end
    end

    describe '#after_destroy' do

      it 'should directly invoke remove index' do
        TireAsyncIndex.configure do |config|
          config.background_engine :none
        end

        a    = AmUser.new.tap { |a| a.id = 23 }
        tire = double(:Tire, index: double(:index))
        a.stub(:tire) { tire }

        tire.index.should_receive(:remove)
        a.destroy
      end

      it 'should enqueue sidekiq job' do
        TireAsyncIndex.configure do |config|
          config.background_engine :sidekiq
        end

        TireAsyncIndex::Workers::Sidekiq.should_receive(:perform_async).with(:delete, "AmUser", instance_of(Fixnum))

        AmUser.new.tap { |a| a.id = 23 }.destroy
      end

      it "should enqueue resque job" do
        TireAsyncIndex.configure do |config|
          config.background_engine :resque
        end

        Resque.should_receive(:enqueue).with(TireAsyncIndex::Workers::Resque, :delete, "AmUser", instance_of(Fixnum))

        AmUser.new.tap { |a| a.id = 23 }.destroy
      end
    end

  end
end
