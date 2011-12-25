require 'rubygems'
require 'bundler/setup'
require 'logger'
require 'eventmachine'
require 'em-http-request'
require 'em-websocket-client'
require 'json'
require 'ruby-debug'
$LOAD_PATH << '.' unless $LOAD_PATH.include?('.')
require 'tester/base'

tester = Tester::Base.new
tester.start
