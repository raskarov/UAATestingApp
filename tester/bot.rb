require 'uri'

module Tester
  class Bot < Struct.new(:game_uri, :min_price, :max_price)
    def logger
      Tester::Base.logger
    end

    def start
      http = EventMachine::HttpRequest.new(game_uri).get

      http.callback do
        @waiting_location = http.response_header['LOCATION']
        update_cookie(http.response_header['SET_COOKIE'].to_s)
        if room_id
          logger.info "redirected to room #{room_id} (#{@waiting_location})"
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

      http.callback do
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
        play(cmd)
      when /Room\.stopGame/
        logger.info "Game stopped"
        if @timer
          @timer.cancel
          @timer = nil
        end
      else
        # logger.warn "Unknown command: #{cmd_string}"
      end
    end

    def play(cmd)
      res = %r{Room\.startGame\(\"(.+)\", (\d+)\)}.match(cmd['body'])
      @game_url = res[1]
      @game_id = res[2]
      http = EventMachine::HttpRequest.new(@game_url).get(:head => {:cookie => cookie})

      http.callback do
        html = Nokogiri::HTML.parse(http.response)
        @member_name = html.css('table.game-table tr:first-child td:first-child').first.inner_text.strip
        logger.info "Play game #{@game_id} as #{@member_name}"
        @timer = EM.add_periodic_timer(1) do
          make_bid
        end
      end
    end

    def make_bid
      value = min_price + rand(max_price - min_price)
      http = EventMachine::HttpRequest.new(bid_url).post(:body => {'bid[value]' => value, 'bid[auction_id]' => @game_id}, :head => {:cookie => cookie})

      http.callback do
        logger.info "#{@member_name}: bid of $#{value} have made, status #{http.response_header.status}"
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
  end
end
