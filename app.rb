require 'sinatra'

set :port, 80
set :bind, "0.0.0.0"

get "/rand" do
    rand(10).to_s
end

# Should be available only to paid users
get "/rand/:number" do
    rand(params[:number].to_i).to_s
end
