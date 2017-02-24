require 'sinatra'
require 'json'
require 'net/http'
require 'uri'
require 'time'
require 'yaml'

CONFIG = {
    'slack_service_url': 'slack_service_url',
    'slack_domain': 'https://hooks.slack.com'
}

messages_user_id = YAML.load_file('messages_user_id.yml')
messages_user_name = YAML.load_file('messages_user_name.yml')

generic_messages = [
    'Cheers! Grab a :beer:, but if you are on ROTA, we\'ve built Practo Order :pill:  for you',
    'Cheers! Go and play :table_tennis_paddle_and_ball: for a while (as if you have a choice) :troll:',
    'Cheers! :v:  Take money from your TL and grab something from the Vending Machine :tada:',
    'Cheers! How about asking your SEM/EM about that PS4 he promised? :troll:',
    'Cheers! Great work, ask the person beside you to get you a :coffee:!',
    'Cheers! But, :thinking_face: you deserve a party, tag your PM and SEM/EM! :tada:'
]

message_huge_no_prs = [
    'Cheers :bow::skin-tone-3: But, enough! How many PRs do I have to stuff in?'
]

# set :port, 9494
uri = URI.parse(CONFIG[:'slack_domain'])
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
http.verify_mode = OpenSSL::SSL::VERIFY_NONE
slackRequest = Net::HTTP::Post.new(CONFIG[:'slack_service_url'])
slackRequest.add_field('Content-Type', 'application/json')

def get_org_repo_prnumber(nonProtoLink)
    prLink = nonProtoLink.split("/")
    return prLink[1], prLink[2], prLink[4]
end

def clean_up_pr_links(prs, triggerWord)
    # removing triggerWord < > \n and spaces from input text
    prs.gsub!(triggerWord, '')
    prs.gsub!(/[<>\n ]/, '')
    return prs
end

def add_to_org_repo_prnumber(prArray, orgRepoPrs)
    countOfPrsAdded = 0
    countOfDuplicatePrsAdded = 0
    prArray.each { |x|
        if x.empty?
            next
        end
        org, repo, prNumber = get_org_repo_prnumber(x)
        if orgRepoPrs[org]
            if orgRepoPrs[org][repo]
                if orgRepoPrs[org][repo].include? prNumber
                    countOfDuplicatePrsAdded += 1
                else
                    orgRepoPrs[org][repo].push(prNumber)
                    countOfPrsAdded += 1
                end
            else
                orgRepoPrs[org][repo] = [prNumber]
                countOfPrsAdded += 1
            end
        else
            orgRepoPrs[org] = {}
            orgRepoPrs[org][repo] = [prNumber]
            countOfPrsAdded += 1
        end
    }
    return orgRepoPrs, countOfPrsAdded, countOfDuplicatePrsAdded
end

def get_prs_to_deploy()
    orgRepoPrs = {}
    if File.exist?('prs_to_deploy.yml')
        orgRepoPrs = YAML.load_file('prs_to_deploy.yml')
    end
    return orgRepoPrs
end

set :environment, :production

get '/test' do
    'Hello world!'
end

post '/github_event_handler' do
    payload = JSON.parse(request.body.read)
    case request.env['HTTP_X_GITHUB_EVENT']
    when "pull_request"
        if payload["action"] == "closed" && payload["pull_request"]["merged"] && payload["pull_request"]["base"]["ref"] === "master"
            user = payload["pull_request"]["merged_by"]["login"]
            userUrl = payload["pull_request"]["merged_by"]["html_url"]

            prAuthor = payload["pull_request"]["user"]["login"]
            prAuthorUrl = payload["pull_request"]["user"]["html_url"]

            prNumber = payload["number"]
            prTitle = payload["pull_request"]["title"]
            prUrl = payload["pull_request"]["html_url"]

            mergeTime = payload["pull_request"]["merged_at"]

            repoName = payload["repository"]["name"]
            repoFullName = payload["repository"]["full_name"]
            displayPrName = repoName + '#' + prNumber.to_s

            epochSecs = Time.parse(mergeTime).to_i
            ENV['TZ']='Asia/Kolkata'
            timeSinceEpoch = Time::at(epochSecs).to_i

            # Deleting the PR from queue
            merged_pr = payload['pull_request']['html_url']
            merged_pr.gsub!('https://', '')
            orgRepoPrs = get_prs_to_deploy()
            org, repo, prNumber = get_org_repo_prnumber(merged_pr)
            orgRepoPrs = get_prs_to_deploy()
            if orgRepoPrs[org][repo].include? prNumber
                orgRepoPrs[org][repo].delete(prNumber)
                if orgRepoPrs[org][repo].length == 0
                    orgRepoPrs[org].delete(repo)
                    if orgRepoPrs[org].length == 0
                        orgRepoPrs.delete(org)
                    end
                end
            end
            File.write('prs_to_deploy.yml', orgRepoPrs.to_yaml)
            data = {
                attachments: [
                    {
                        fallback: user + " merged a PR to " + repoFullName,
                        title: user + " merged a PR to " + repoFullName,
                        # title_link: prUrl,
                        # author_name: user,
                        # author_link: userUrl,
                        mrkdwn_in: ["fields"],
                        color: '#e8e8e8',
                        fields:[
                            {
                                value: "*PR #* <" + prUrl + "|" + displayPrName + ">",
                                short: true
                            },
                            {
                                value: "*PR Author* <" + prAuthorUrl + "|" + prAuthor + ">",
                                short: true
                            },
                            {
                                value: "*PR Title* " + prTitle,
                                short: false
                            }
                        ],
                        footer: "GitHub",
                        footer_icon: "https://a.slack-edge.com/2fac/plugins/github/assets/service_48.png",
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
    @payload = JSON.parse(params[:payload])
    print "\n\n\n"
    print @payload
    print "\n\n\n"
    buildStatus = @payload["status_message"]
    buildFailStatuses = ['Broken','Failed','Still Failing']
    if @payload["branch"] === "master" && buildFailStatuses.include?(buildStatus)
        payload2 =[]
        if File.exist?('travis_log_data')
            payload2 = Marshal.load File.read('travis_log_data')
        end
        log_data = [@payload] + payload2
        serializedArray = Marshal.dump(log_data)
        File.open('travis_log_data', 'w') {|f| f.write(serializedArray) }

        author = @payload["author_name"]
        buildUrl = @payload["build_url"]
        message = @payload["message"]
        repo = @payload["repository"]["name"]

        buildFinishedAt = @payload["finished_at"]
        epochSecs = Time.parse(buildFinishedAt).to_i
        ENV['TZ']='Asia/Kolkata'
        timeSinceEpoch = Time::at(epochSecs).to_i

        colors = {
            'Pending' => 'warning',
            'Passed' => 'good',
            'Fixed' => 'good',
            'Broken' => 'danger',
            'Failed' => 'danger',
            'Still Failing' => 'danger'
        }
        data = {
            attachments: [
                {
                    fallback: "Build " + buildStatus + " on master in " + repo,
                    title: "Build " + buildStatus + " on master in " + repo,
                    title_link: buildUrl,
                    # author_name: user,
                    # author_link: userUrl,
                    # mrkdwn_in: ["fields"],
                    color: colors[buildStatus],
                    fields:[
                        {
                            title: "Build Status",
                            value: buildStatus,
                            short: true
                        },
                        {
                            title: "Merged by",
                            value: author,
                            short: true
                        },
                        {
                            title: "Commit Title",
                            value: message,
                            short: false
                        }
                    ],
                    footer: "Travis CI",
                    footer_icon: "https://a.slack-edge.com/0180/img/services/travis_48.png",
                    ts: timeSinceEpoch
                }
            ]
        }
        slackRequest.body = data.to_json
        slackResponse = http.request(slackRequest)
    end
end

post '/from_slack' do
    content_type :json
    triggerWord = params["trigger_word"]
    user_name = params['user_name']
    user_id = params['user_id']
    responseText = ""

    case triggerWord
    when "queue+", "queue++"
        prs = params["text"]
        prs = clean_up_pr_links(prs, triggerWord)

        prArray = prs.split("https://")
        orgRepoPrs = get_prs_to_deploy()

        orgRepoPrs, countOfPrsAdded, countOfDuplicates = add_to_org_repo_prnumber(prArray, orgRepoPrs)

        prsInQueue = countOfPrsAdded
        orgRepoPrs.each { |org,repos|
            repos.each { |repo,prNumbers|
                prNumbers.each{ |prNumber|
                    prsInQueue += 1
                }
            }
        }

        File.write('prs_to_deploy.yml', orgRepoPrs.to_yaml)

        if countOfDuplicates > 0
            responseText = countOfDuplicates.to_s + " PRs already exist in queue\n"
        end

        responseText = "Added " + countOfPrsAdded.to_s + " PRs to queue\n"
        if prsInQueue == 9 || prsInQueue == 13 || prsInQueue == 15
            responseText = responseText + message_huge_no_prs.sample
        elsif messages_user_id[user_id]
            responseText = responseText + messages_user_id[user_id].sample
        elsif messages_user_name[user_name]
            responseText = responseText + messages_user_name[user_name].sample
        else
            responseText = responseText + generic_messages.sample
        end

        if countOfPrsAdded == 0
            responseText = ''
            if countOfDuplicates > 0
                responseText = countOfDuplicates.to_s + " PRs already exist in queue\n"
            end
            responseText = responseText + "¯\\_(ツ)_/¯ what are you even trying to do!!"
        end

    when "queue-", "queue--"
        responseText = "¯\\_(ツ)_/¯ nothing's there to remove"
        if File.exist?('prs_to_deploy.yml')
            prs = params["text"]
            prs = clean_up_pr_links(prs, triggerWord)

            prArray = prs.split("https://")
            orgRepoPrs = get_prs_to_deploy()

            countOfPrsRemoved = 0
            prArray.each { |x|
                if x.empty?
                    next
                end
                org, repo, prNumber = get_org_repo_prnumber(x)
                if orgRepoPrs[org][repo].include? prNumber
                    orgRepoPrs[org][repo].delete(prNumber)
                    if orgRepoPrs[org][repo].length == 0
                        orgRepoPrs[org].delete(repo)
                        if orgRepoPrs[org].length == 0
                            orgRepoPrs.delete(org)
                        end
                    end
                    countOfPrsRemoved += 1
                end
            }
            File.write('prs_to_deploy.yml', orgRepoPrs.to_yaml)

            responseText = "Done :thumbsup::skin-tone-4:\nRemoved " + countOfPrsRemoved.to_s + " PRs"
        end
    when "clear queue"
        responseText = "¯\\_(ツ)_/¯ nothing's there to clear"
        if File.exist?('prs_to_deploy.yml')
            File.delete('prs_to_deploy.yml')
            responseText = "All gone :thumbsup::skin-tone-4:"
        end

    when "list queue"
        orgRepoPrs = get_prs_to_deploy()
        prsInQueue = []
        currentRepo = ''
        previousRepo = ''
        orgRepoPrs.each { |org,repos|
            repos.each { |repo,prNumbers|
                previousRepo = currentRepo
                currentRepo = repo
                if previousRepo != currentRepo
                    prsInQueue.push('')
                end
                prNumbers.each{ |prNumber|
                    prUrl = "https://github.com/" + org + "/" + repo + "/pull/" + prNumber
                    displayPrName = repo + '#' + prNumber
                    prsInQueue.push("<" + prUrl + "|" + displayPrName + ">")
                }
            }
        }
        if prsInQueue.length > 0
            responseText = "The following PRs are in queue\n"
            responseText = responseText + prsInQueue.join("\n")
        else
            responseText = "No PRs in queue :sunglasses:"
        end
    else
        responseText = "Unrecognised triggerWord"
    end

    { :text => responseText }.to_json
end
