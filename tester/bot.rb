require 'uri'

module Tester
  class Bot < Struct.new(:game_uri)
    def logger
      Tester::Base.logger
    end

    def start
      http = EventMachine::HttpRequest.new(game_uri).get

      http.callback do
        @waiting_location = http.response_header['LOCATION']
        update_cookie(http.response_header['SET_COOKIE'])
        if room_id
          logger.info "redirected to room #{room_id} (#{@waiting_location})"
          logger.info "cookie: #{cookie}"
          waiting_for_game
        else
          logger.error "wrong password"
          logger.info "redirected to #{@waiting_location}"
        end
      end
    end

    def room_id
      res = %r{\/rooms\/(\d+)\/}.match(@waiting_location)
      res && res[1]
    end

    def bid_url
      uri = URI.parse(@waiting_location)
      "http://#{uri.host}#{uri.port == 80 ? '' : uri.port}/rooms/#{room_id}/bids"
    end

    def waiting_for_game
      http = EventMachine::HttpRequest.new(@waiting_location).get(:head => {:cookie => cookie})

      http.callback do |response|
        res = %r{new Socky\('([^'']+)', '([^'']+)', '([^'']+)'\)}.match http.response
        listen_websocket(res[1], res[2], res[3])
      end
    end

    def listen_websocket(addr, port, params)
      conn = EventMachine::WebSocketClient.connect("#{addr}:#{port}/?#{params}")

      conn.stream do |cmd|
        process_command(cmd)
      end
    end

    def process_command(cmd_string)
      cmd = JSON.parse(cmd_string)
      case cmd['body']
      when /Room\.startGame/
        @game_id = %r{Room\.startGame\(.+, (\d+)\)}.match(cmd['body'])[1]
        logger.info "Game #{@game_id} started"
        @timer = EM.add_periodic_timer(1) do
          make_bid
        end
      when /Room\.stopGame/
        logger.info "Game stopped"
        if @timer
          @timer.cancel
          @timer = nil
        end
      else
        logger.warn "Unknown command: #{cmd_string}"
      end
    end

    def make_bid
      value = rand(300)
      http = EventMachine::HttpRequest.new(bid_url).post(:body => {'bid[value]' => value, :auction_id => @game_id}, :head => {:cookie => cookie})

      http.callback do |response|
        logger.info "bid of $#{value} have made, status #{http.response_header.status}"
      end
    end

    def update_cookie(cookie_string)
      @cookie ||= {}
      cookie_string.split(';').map do |pair|
        k, v = pair.strip.split('=')
        @cookie[k] = v
      end
    end

    def cookie
      @cookie.map { |k, v| "#{k}=#{v}" }.join('; ')
    end

    def get_location(response)
      response[:headers].find {|h| h =~ /^Location: / }.gsub(/^Location: /, '')
    end
  end
end
