require 'sinatra'
require 'excon'

dashboard = ENV['TYK_DASHBOARD_URL'] || 'http://tyk_dashboard:3000'
Tyk = Excon.new(dashboard, :persistent => true, :headers => { "authorization": ENV['TYK_API_KEY']})

def analytics_totals(data)
    data.reduce({"hits" => 0, "success" => 0, "error" => 0}) do |total, row|
        total['hits'] += row['hits'].to_i
        total['success'] += row['success'].to_i
        total['error'] += row['error'].to_i

        total
    end
end

class DashboardAdmin < Sinatra::Base
    use Rack::Auth::Basic do |username, password|
        username == 'admin' && password == 'admin'
    end

    template :dashboard do
        <<-HTML
    <h3>Analytics</h3>
    For the last 30 days users made: <span class="is-size-4"><%=@totals%></span> requests
        HTML
    end

    get "/" do
        from = (Date.today - 30).strftime("%d/%m/%Y")
        to = (Date.today+1).strftime("%d/%m/%Y")
        resp = Tyk.get(path: "/api/usage/#{from}/#{to}?res=hour&p=-1")

        @analytics = JSON.parse(resp.body)
        @totals = analytics_totals(@analytics['data'])

        erb :dashboard
    end
end

class PrivateAPI < Sinatra::Base
    use Rack::Auth::Basic do |username, password|
        username == 'secret' && password == 'secret'
    end

    get "/rand" do
        rand(10).to_s
    end

    # Should be available only to paid users
    get "/rand/:number" do
        rand(params[:number].to_i).to_s
    end
end
