require 'sinatra/base'
require './app'

map('/admin') { run DashboardAdmin }
map('/api') { run PrivateAPI }
