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
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/bulma/0.5.1/css/bulma.min.css">
    <div class="container content">
        <h3>Analytics</h3>
        For the last 30 days:<br/>
        <%@totals.each do |api, total| %>
            <%=api%>: <span class="is-size-4"><%=total%></span><br/>
        <%end%>
        <h3>Developers</h3>
        <%@developers.each do |dev|%>
        <%=dev['email']%><br/>
        <%end%>
    </div>
        HTML
    end

    get "/" do
        from = (Date.today - 30).strftime("%d/%m/%Y")
        to = (Date.today+1).strftime("%d/%m/%Y")
        resp = Tyk.get(path: "/api/usage/apis/#{from}/#{to}?by=Hits&sort=1&p=0")

        @analytics = JSON.parse(resp.body)
        @totals = analytics_totals(@analytics['data'])

        resp = Tyk.get(path: "/api/portal/developers")
        @developers = JSON.parse(resp.body)["Data"]

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

class DeveloperPortal < Sinatra::Base
    enable :sessions

    before do
        if session[:developer]
            resp = Tyk.get(path: "/api/portal/developers/email/#{session[:developer]}")

            if resp.status == 200
                @developer = JSON.parse(resp.body)
                @raw_keys = session[:raw_keys]
                @raw_keys = {} if @raw_keys.nil?
            else
                session.delete(:developer)
            end
        end

        @apis_catalogue = JSON.parse(Tyk.get(path: "/api/portal/catalogue").body)
        @portal_config = JSON.parse(Tyk.get(path: "/api/portal/configuration").body)
    end

    set(:auth) do |*roles|   # <- notice the splat here
        condition do
            if roles.include?(:logged) && @developer.nil?
                redirect "/", 303
            end
        end
    end

    template :layout do
        <<-HTML
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/bulma/0.5.1/css/bulma.min.css">
    <div class="container content">
        <br/>
        <% if @developer.nil? %>
            <span class="title is-2">Welcome to the developer portal</span>
            <a href="/login" class="is-pulled-right is-size-4">Login</a>
            <a href="/register" class="is-pulled-right is-size-4" style="margin-right: 2em">Signup</a>
        <% else %>
            <span class="title is-2">Hello <%=@developer['fields']['Name']%>!</span>
            <a href="/logout" class="is-pulled-right is-size-4">Logout</a>
        <% end %>
        <hr/>
        <% if @error %>
        <h3 style="color: red"><%=@error%></h3>
        <% end %>
        <%=yield%>
    </div>
        HTML
    end

    ### ==== Basic templates used for rendering portal ====
    template :dashboard do
        <<-HTML
    <h3>Analytics</h3>
    For the last 30 days you made:<br/>
    <%@totals.each do |api, total| %>
        <%=api%>: <span class="is-size-4"><%=total%></span><br/>
    <%end%>
    <h3>APIs:</h3>
    <% @apis_catalogue['apis'].each do |api| %>
    <h2 class="header"><%=api['name']%></h2>
    <h3 class="subheader"><%=api['short_description'] %></h3>
    <p><%=api['long_description'] %></p>
    <% if @developer['subscriptions'][api['policy_id']] %>
    <h4>Already subscribed<h4>
    <%= @raw_keys[api['policy_id']] %>
    <% else %>
    <a href="/request/<%=api['policy_id']%>">Request access</a>
    <% end %>
    <hr>
    <% end %>
        HTML
    end

    template :home do
        <<-HTML
    <h3>You can subscribe to the following APIs:</h3>
    <% @apis_catalogue['apis'].each do |api| %>
    <h2 class="header"><%=api['name']%></h2>
    <h3 class="subheader"><%=api['short_description'] %></h3>
    <p><%=api['long_description'] %></p>
    <hr>
    <% end %>
        HTML
    end

    get '/' do
        if @developer
            redirect "/dashboard"
            return
        end

        erb :home
    end

    get '/dashboard', auth: :logged do
        if @developer['subscriptions'].empty?
            @totals = {}
            return erb :dashboard
        end
        keys = @developer['subscriptions'].values.join(',')
        from = (Date.today - 30).strftime("%d/%m/%Y")
        to = Date.today.strftime("%d/%m/%Y")

        resp = Tyk.get(path: "/api/activity/keys/aggregate/#{keys}/#{from}/#{to}?p=-1&res=day")
        @analytics = JSON.parse(resp.body)
        @totals = analytics_totals(@analytics['data'])

        erb :dashboard
    end

    ### ==== Key request ===
    template :request_access do
        <<-HTML
    <h1>Requesting access to '<%=@api['name']%>' API</h1>
    <form target="/request/<%=params[:policy_id]%>" method="POST" class="column is-half">
        <input class="input" placeholder="Use case" name="usecase" /><br/><br/>
        <input class="input"  placeholder="Planned amount of monthly requests" name="traffic" /><br/><br/>
        <input class="button is-primary" type="submit" />
    </form>
        HTML
    end

    before '/request/:policy_id' do
        @api = @apis_catalogue['apis'].detect{|api| api['policy_id'] == params[:policy_id] }
    end

    get '/request/:policy_id', auth: :logged do
        erb :request_access
    end

    post '/request/:policy_id', :auth => :logged do
        key_request = {
            "by_user" => @developer['id'],
            "fields" => {
                "usecase" => params[:usecase],
                "traffic" => params[:traffic],
            },
            'date_created' => Time.now.iso8601,
            "version" => "v2",
            "for_plan" => params[:policy_id]
        }

        resp = Tyk.post(path: "/api/portal/requests", body: key_request.to_json)
        if resp.status != 200
            @error = resp.
            return erb :request_access
        end

        unless @portal_config['require_key_approval']
            reqID = JSON.parse(resp.body)["Message"]
            resp = Tyk.put(path: "/api/portal/requests/approve/#{reqID}")
            rawKey = JSON.parse(resp.body)["RawKey"]
            if session[:raw_keys].nil?
                session[:raw_keys] = {}
            end

            session[:raw_keys][params[:policy_id]] = rawKey
        end

        redirect "/"
    end

    ### ==== User registration ====
    template :register do
        <<-HTML
    <form target="/register" method="POST" class="column is-half">
        <h1>Sign Up</h1>
        <input class="input" placeholder="Email" name="email"/><br/><br/>
        <input class="input" placeholder="Password" name="password" type="password"/><br/><br/>
        <input class="input" placeholder="Name" name="name"/><br/><br/>
        <input class="input" placeholder="Location" name="location"/><br/><br/>
        <input class="button is-primary" type=submit />
    </form>
        HTML
    end

    get '/register' do
        erb :register
    end

    post '/register' do
        developer = {
            "email": params[:email],
            "password": params[:password],
            "inactive": false, # Use this field to add additional developer check
            "fields": {
                "Name": params[:name],
                "Location": params[:location]
            }
        }
        resp = Tyk.post(path: "/api/portal/developers", body: developer.to_json)

        if resp.status != 200
            @error = resp.body
            erb :register
        else
            session[:developer] = params[:email]
            redirect "/"
        end
    end

    #### === User authentification logic ====
    template :login do
        <<-HTML
    <form target="/login" method="POST" class="column is-half">
        <h1>Login</h1>
        <input class="input" placeholder="Email" name="email"/><br/><br/>
        <input class="input" placeholder="Password" name="password" type="password"/><br/><br/>
        <input class="button is-primary" type=submit />
    </form>
        HTML
    end

    get '/login' do
        erb :login
    end

    post '/login' do
        resp = Tyk.post(path: "/api/portal/developers/verify_credentials", body: { username: params[:email], password: params[:password] }.to_json)
        if false
            @error = "Password not match"
            return erb :login
        end

        session[:developer] = params[:email]
        redirect "/"
    end

    get '/logout' do
        session.delete(:developer)
        redirect "/"
    end
end
