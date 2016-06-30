require 'sinatra'
require 'json'
require 'net/http'
require 'uri'
require 'time'

uri = URI.parse('https://hooks.slack.com')
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
http.verify_mode = OpenSSL::SSL::VERIFY_NONE
slackRequest = Net::HTTP::Post.new("/services/T024PSVLF/B1MDP55HU/UujJlw0BbmDtEI5QflFBvq41")
slackRequest.add_field('Content-Type', 'application/json')

get '/' do
    'Hello world!'
end

post '/event_handler' do
    @payload = JSON.parse(params[:payload])
    case request.env['HTTP_X_GITHUB_EVENT']
    when "pull_request"
        if @payload["action"] == "closed" && @payload["pull_request"]["merged"]

            user = @payload["pull_request"]["merged_by"]["login"]
            userUrl = @payload["pull_request"]["merged_by"]["html_url"]

            prAuthor = @payload["pull_request"]["user"]["login"]
            prAuthorUrl = @payload["pull_request"]["user"]["html_url"]

            mergeTime = @payload["pull_request"]["merged_by"]["login"]

            prNumber = @payload["number"]
            prTitle = @payload["pull_request"]["title"]
            prUrl = @payload["pull_request"]["html_url"]

            mergeTime = @payload["pull_request"]["merged_at"]

            repoName = @payload["repository"]["name"]
            repoFullName = @payload["repository"]["full_name"]
            displayPrName = repoName + '#' + prNumber.to_s

            epochSecs = Time.parse(mergeTime).to_i
            ENV['TZ']='Asia/Kolkata'
            timeSinceEpoch = Time::at(epochSecs).to_i

            data = {
                attachments: [
                    {
                        fallback: user + " merged a PR to " + repoFullName,
                        title: user + " merged a PR to " + repoFullName,
                        title_link: prUrl,
                        # author_name: user,
                        # author_link: userUrl,
                        # mrkdwn_in: ["fields"],
                        color: '#e8e8e8',
                        fields:[
                            {
                                title: "PR # ",
                                value: "<" + prUrl + "|" + displayPrName + ">",
                                short: true
                            },
                            {
                                title: "PR Author",
                                value: "<" + prAuthorUrl + "|" + prAuthor + ">",
                                short: true
                            },
                            {
                                title: "PR Title",
                                value: prTitle,
                                short: false
                            }
                        ],
                        ts: timeSinceEpoch
                    }
                ]
            }
            slackRequest.body = data.to_json
            slackResponse = http.request(slackRequest)
        end
    end
end

post '/travis_notifications' do
    puts params
    @payload = JSON.parse(params[:payload])
    puts @payload
end
