require 'rubygems'
ENV['GEM_PATH'] = "#{File.dirname(__FILE__)}/../.gems:#{ENV['GEM_PATH']}" if File.exist?('/dh') # for the deploy win
Gem.clear_paths
require 'rack'
require 'wiki'

use Rack::ShowExceptions

Wiki.create if Wiki.respond_to? :create
run Wiki
