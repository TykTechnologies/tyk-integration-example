require 'sinatra'
require 'excon'

dashboard = ENV['TYK_DASHBOARD_URL'] || 'http://tyk_dashboard:3000'
Tyk = Excon.new(dashboard, :persistent => true, :headers => { "authorization": ENV['TYK_API_KEY']})

def analytics_totals(data)
    data.reduce({}) do |total, row|
        api_id = row['id']['api_name']
        if !total[api_id]
            total[api_id] = {"hits" => 0, "success" => 0, "error" => 0}
        end
        total[api_id]['hits'] += row['hits'].to_i
        total[api_id]['success'] += row['success'].to_i
        total[api_id]['error'] += row['error'].to_i

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
    For the last 30 days:<br/>
    <%@totals.each do |api, total| %>
        <%=api%>: <span class="is-size-4"><%=total%></span><br/>
    <%end%>
    HTML
    end

    get "/" do
        from = (Date.today - 30).strftime("%d/%m/%Y")
        to = (Date.today+1).strftime("%d/%m/%Y")
        resp = Tyk.get(path: "/api/usage/apis/#{from}/#{to}?by=Hits&sort=1&p=0")

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
