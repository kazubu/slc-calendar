require 'twitter'
require 'pp'
require 'net/http'
require 'uri'

require_relative './config'

def expand_url(url)
  begin
    response = Net::HTTP.get_response(URI.parse(url))
  rescue
    return url
  end
  case response
  when Net::HTTPRedirection
    expand_url(response['location'])
  else
    url
  end
end

client = Twitter::REST::Client.new do|config|
    config.consumer_key = TWITTER_CONSUMER_KEY
    config.consumer_secret = TWITTER_CONSUMER_SECRET
    config.bearer_token = TWITTER_BEARER_TOKEN
end

# get 20k tweets
option = {count: 200, tweet_mode: 'extended'}

def is_include_youtube_live(t)
  youtube_url_lists = [ 'youtu.be', 'youtube.com' ]
  url = nil

  return false unless t.urls.count > 0
  t.urls.each{|u|
    youtube_url_lists.each{|y|
      if u.expanded_url.to_s.index(y)
        url = u[:expanded_url]
        break
      end
    }
  }

  return false if url.nil?

  e_url = expand_url(url)

  if e_url.index('watch')
    pp e_url
    return true
  end

end

announce_lists = []

begin
  (0..4).each{|i|
    last_id = nil
    l = client.list_timeline("Starlight_chann", 1006957219303211008, option).each{|x|
      last_id = x.id
      if ( (
          x.text.index('配信') &&
          (x.text.index('配信します') || x.text.index('告知'))
         ) && x.in_reply_to_status_id.nil? && !x.retweeted_status )

        # pass
      else
        next unless is_include_youtube_live(x)
      end

      d = { user: x.user.screen_name,
            uri: x.uri,
            text: x.full_text,
            mention: x.user_mentions?,
            live_url: is_include_youtube_live(x)
          }

        announce_lists << d
    }

    p "LC: " + l.count.to_s
    option[:max_id] = last_id
  }
rescue Exception => e
  pp e
end

pp announce_lists
