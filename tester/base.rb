require 'tester/bot'

module Tester
  class Base
    def self.logger
      @logger ||= Logger.new(STDOUT)
    end

    def logger
      self.class.logger
    end

    def initialize
      process_argv
    end

    def ready?
      @bots_count && @game_uri
    end

    def start
      return unless ready?

      EM.run do
        @bots = (1..@bots_count).map do
          bot = Tester::Bot.new(@game_uri)
          bot.start
          bot
        end
      end
    end

    private

    def process_argv
      if ARGV.length == 2
        @game_uri = ARGV[0]
        @bots_count = ARGV[1].to_i
        logger.info "game uri: #{@game_uri}"
        logger.info "bots count: #{@bots_count}"
      else
        logger.info "Usage: tester.rb game_uri bots_count"
      end
    end
  end
end
