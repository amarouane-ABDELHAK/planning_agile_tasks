require 'sinatra'
require 'sinatra/reloader'
require "base64"
require 'json'
require 'rest-client'
require "sinatra/config_file"
require 'mongo'

config_file './config.yml'
#set :environment, settings.install_ENV['env]
set :port , ENV['port'] #settings.install_ENV['port]
set :bind, '0.0.0.0'

$jira_project ='CDDIS'

def get_jira_data(project='VISAGE', offset=0, max_results=1000,id=nil, updated_date=nil)
  base_query = "#{ENV['rest_url']}#{project}"
  base_query = "#{base_query} and updatedDate >= #{updated_date}" unless updated_date.nil?
  token = Base64.encode64("#{ENV['username']}:#{ENV['password']}")
  headers={:"Content-Type"=>"application/json", :Authorization=>"Basic #{token}"}
  url="#{base_query}&startAt=#{offset}&maxResults=#{max_results}"
  url="https://bugs.earthdata.nasa.gov/rest/api/latest/search?jql=key%3D#{id}" if id

  re = RestClient.get(url, headers)


  begin
    result = JSON.parse(re)
    retrieve_next = offset + result['maxResults'] <  result['total']
    {'result': result['issues'], 'offset':offset + result['maxResults'], 'request_next':retrieve_next}
  rescue
    {'result': [], 'offset':0, 'request_next': false}
  end



end

def cach_jira_data(id=nil)
  #mongo Session
  client = Mongo::Client.new([ "mongodb:#{ENV['database_port']}" ],
                             :database => "#{ENV['database_name']}",
                            :password => "#{ENV['database_password']}", :user => "#{ENV['database_user']}"
  )
  collection = client[:tasks]
  offset = 0
  begin
    last_cached_updated_task=collection.find.sort({'updated_date':-1}).limit(1).first['updated_date'] # last updated in DB
    last_cached_updated_task = last_cached_updated_task.strftime("%Y-%m-%d")
  rescue
    last_cached_updated_task =nil
  end




  loop do

    data = get_jira_data(project="#$jira_project", offset=offset, max_results=1000,id=id, updated_date=last_cached_updated_task)


  for ele in data[:result]
    field = ele['fields']
    #next unless field['customfield_10701'] # jump the loop for a condition
    #.strftime("%m/%d/%Y") <= Javascript
    #YYYY-mm-dd <= Jira




      start_date= field['created']

      start_date = field['customfield_12600'] if field['customfield_12600']
      stop_date = field['duedate']
      start_date = Date.parse(start_date)
      # Some Jira actions does not have stop date
      if stop_date
        stop_date = Date.parse(stop_date)
      else
        stop_date = start_date >> 2
      end
      updated_date = Date.parse(field['updated'])
      assignee_name = "No One"
      assignee_url= "404"
      if field['assignee']
        assignee_name = field['assignee']['displayName']
        assignee_url = field['assignee']['self']
      end

      reporter_name = field['reporter']['displayName']
      reporter_url = field['reporter']['self']
      type = field['issuetype']['name']
      priority = field['priority']['name']
      summary = field['summary']
      epic = '-'
      epic = field['customfield_10702'] if field['customfield_10702']
      progress = 20
      progress = field['customfield_10401'] if field['customfield_10401']
          status = ele['fields']['status']['name']
      if status == "Closed" || status == "Resolved"
        progress =100
      end
      parent = epic
      parent = field['parent']['key'] if field['parent']
      subtasks = []
      if field['subtasks']
        field['subtasks'].each do |subtask|
          subtasks.push subtask['key']
        end

      end

      components = []
      belongs_to_epic = nil
      belongs_to_epic = field['customfield_10701'] if field['customfield_10701']
      for component in field['components']
        components.push(component['name'])
      end
    # If it is not an epic it means it is a story and a story have subtasks
      due_days = stop_date.mjd - Date.today.mjd
      task_duration = stop_date.mjd - start_date.mjd + 1
    custom_id= ele['key'].split("#{project}-")[1].to_i
      fetched_data= { 'name':ele['key'],'start': start_date, 'end': stop_date,
                      'parent': parent, 'progress': progress, 'assignee':{'assignee_name':assignee_name, 'assignee_url':assignee_url},
                      'reporter':{'reporter_name':reporter_name, 'reporter_url':reporter_url}, 'status':status,'custom_id':custom_id,
                      'due_days':due_days, 'task_duration': task_duration, 'updated_date':updated_date, 'subtasks':subtasks,
                      'type': type, 'priority': priority, 'components':components, 'summary': summary, 'epic': epic, 'belongs_to_epic':belongs_to_epic}



      begin

        fetched_data_insert=fetched_data
        fetched_data_insert['_id']=ele['key']
        collection.insert_one(fetched_data_insert)

      rescue
        collection.update_one( { '_id': ele['key'] }, { '$set': fetched_data} )


      end


    end



    offset = data[:offset]
    break unless data [:request_next]

  end



end

def create_people_gain( collection)
  workers ={}



  data = collection.find({}, {
      "status": 1,
      "assignee.assignee_name": 1
  })

  status_list= []



  data.each do |gain|
    status_list.push(gain[:status]) unless status_list.include? gain[:status]
    begin
      workers[gain[:assignee][:assignee_name]][gain[:status]] +=1
    rescue
      if workers[gain[:assignee][:assignee_name]]
        workers[gain[:assignee][:assignee_name]][gain[:status]] =0

      else
        workers[gain[:assignee][:assignee_name]] ={}


      end

    end



  end

  status_list.each do |s|
    workers.keys.each do |k|
      workers[k][s]= 0 unless workers[k][s]
    end

  end

  {'workers': workers,'status_list': status_list}



end


    post '/synchronize' do
      cach_jira_data
      redirect '/'

    end

    post '/' do
      params.delete('captures')
      query = params.map{|key, value| "#{key}=#{value}"}.join("&")
      redirect ("/?#{query}")

    end

    get '/' do
      epics_selected = params['epics']

      priority_selected = params['priorities']
      people_selected = params['people']
      @params={'Epic': params['epics'], 'Priority': priority_selected, 'People': people_selected}


      client = Mongo::Client.new([ "mongodb:#{ENV['database_port']}" ],
                             :database => "#{ENV['database_name']}",
                            :password => "#{ENV['database_password']}", :user => "#{ENV['database_user']}"
  )
      collection = client[:tasks]
      #names = [ "key", [startDate,Stopdate]]
      @actions =[]
      @tree= []
      components = collection.distinct("components")
      @priority_type = collection.distinct("priority")
      components.each do |component|
        epics = collection.distinct('epic',{'epic': {'$ne':'-'},'status': {'$ne': 'Closed'} , "components":component})
        @tree.push({'component':
                        {
                            'name':component,
                            'epics':epics
                        }

                   })

      end

      query = {'status': {'$ne': 'Closed'},'type': {'$ne': 'Epic'}}

      unless epics_selected == nil || epics_selected.strip.empty?
        epics_id= collection.distinct('_id',{'type':'Epic', 'epic': {'$in': epics_selected.split(',')}} )

        query[:belongs_to_epic] = {'$in': epics_id}
        related_to_epic_id = collection.distinct('_id',query )
        subtasks_id = collection.distinct('_id',{'parent':{'$in': related_to_epic_id}})

        (subtasks_id << related_to_epic_id).flatten!

        query= {'_id':{'$in':subtasks_id},'status': {'$ne': 'Closed'}}


      end
      query[:priority] = {'$in': priority_selected.split(',')} unless priority_selected == nil || priority_selected.strip.empty?

      query['assignee.assignee_name'] = {'$in': people_selected.split(',')} unless people_selected == nil || people_selected.strip.empty?

      @action_table =[]
      collection.find(query).sort({'custom_id':-1}).each do |act_tab|
        @action_table.push(act_tab)

      end


      collection.find(query).sort({'custom_id':-1}).limit(100).each do |document|


        @actions.push(document)
      end

      @people = []
      collection.distinct('assignee').each do |person|
        @people.push({'name': person[:assignee_name], 'url':person[:assignee_url]})
      end



      @people_gain = create_people_gain(collection)
      @workers = @people_gain[:workers]
      @status_task = @people_gain[:status_list]


    erb :index, :locals => {:actions => @actions,:action_table => @action_table, :tree => @tree, :priority_type => @priority_type, :params => epics_selected,
    :people => @people, :people_gain => @workers, :status_task => @status_task, :filter => @params
    }
    end


