require 'twitter'
require 'pp'
require 'net/http'
require 'uri'
require 'json'
require 'nkf'

require_relative './config'

class SLCScheduleCollector
  def initialize
  end

  def get_schedules(twitter_id, list_id)
    announce_parser(collect_announces(twitter_id, list_id))
  end

  private

  def retry_on_error(times: 3)
    try = 0
    begin
      try += 1
      yield
    rescue
      retry if try < times
      raise
    end
  end

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

  def vurl_to_vid(url)
    if url.index('http') == 0
      return url.split('v=')[1].split('&')[0]
    else
      return url
    end
  end

  def get_video_detail(video_id)
    video_id = vurl_to_vid(video_id)
    url = "https://www.googleapis.com/youtube/v3/videos?key=#{YOUTUBE_DATA_API_KEY}&part=snippet,liveStreamingDetails&id=#{video_id}"

    retry_on_error {
      res = Net::HTTP.get_response(URI.parse(url))

      return JSON.parse(res.body)
    }
    return nil
  end

  def is_upcoming_stream(video_id)
    video_id = vurl_to_vid(video_id)
    v = get_video_detail video_id

    if !v.nil? && !v['items'].nil? && !v['items'][0].nil? && v['items'][0]['id'] == video_id
      if !v['items'][0]['snippet'].nil? && !v['items'][0]['snippet']['liveBroadcastContent'].nil? && v['items'][0]['snippet']['liveBroadcastContent'] == 'upcoming' && !v['items'][0]['liveStreamingDetails'].nil? && !v['items'][0]['liveStreamingDetails']['scheduledStartTime'].nil?
        return true, v['items'][0]['liveStreamingDetails']['scheduledStartTime'], v['items'][0]['snippet']['channelTitle'], v['items'][0]['snippet']['title']
      end
    end

    return false, nil
  end

  def is_include_youtube_live(tweet)
    youtube_url_lists = [ 'youtu.be', 'youtube.com' ]
    url = nil

    return false if tweet.urls.count <= 0
    tweet.urls.each{|u|
      youtube_url_lists.each{|y|
        if u.expanded_url.to_s.index(y)
          url = u.expanded_url.to_s
          break
        end
      }
    }

    return false if url.nil?

    e_url = expand_url(url).to_s

    if e_url.index('watch')
      res, date, ch_name, title = is_upcoming_stream(e_url)
      if res
        video_url = "https://www.youtube.com/watch?v=#{vurl_to_vid(e_url)}"
        return video_url, Time.parse(date).getlocal("+09:00"), ch_name, title
      end
    end

    return false
  end

  def collect_announces(twitter_user, list_id)
    client = Twitter::REST::Client.new do|config|
      config.consumer_key = TWITTER_CONSUMER_KEY
      config.consumer_secret = TWITTER_CONSUMER_SECRET
      config.bearer_token = TWITTER_BEARER_TOKEN
    end

    # get 20k tweets
    option = {count: 200, tweet_mode: 'extended'}

    announce_lists = []

    tweets_count = 0

    #begin
    (0..4).each{|i|
      last_id = nil
      client.list_timeline(twitter_user, list_id, option).each{|x|
        tweets_count += 1
        last_id = x.id
        skip_unless_upcoming_live = false
        text = NKF.nkf('-w -Z4', x.full_text)
        next if !x.in_reply_to_status_id.nil? # Skip a reply to any tweet
        next if !x.retweeted_status.nil? # Skip RT

        if (
            text.index('配信') &&
            (text.index('配信します') || text.index('告知'))
        )
          # pass
        else
          skip_unless_upcoming_live = true
        end

        live = is_include_youtube_live(x)
        next if (skip_unless_upcoming_live && !live)

        d = { user: x.user.screen_name,
              uri: x.uri.to_s,
              text: x.full_text,
              live_info: live
        }

        next if announce_lists.select{|a| a[:live_info] && a[:live_info][0] == d[:live_info][0]}.length > 0 if live
        announce_lists << d
      }
      puts "## Iterate #{i}"
      puts "Collected tweets: #{tweets_count}"
      puts "Collected announces: #{announce_lists.length}"

      option[:max_id] = last_id
    }
    #end

    puts "## Overall"
    puts "Collected tweets: #{tweets_count}"
    puts "Collected announces: #{announce_lists.length}"

    return announce_lists
  end

  def announce_parser(announces)
    schedules = []

    announces.each{|a|
      if a[:live_info]
        schedules << {
          user: a[:user],
          date: a[:live_info][1].strftime('%Y/%m/%d'),
          time: a[:live_info][1].strftime('%H:%M'),
          channel_title: a[:live_info][2],
          title: a[:live_info][3],
          tweet_url: a[:uri],
          video_url: a[:live_info][0]
        }
      else
        # 告知っぽいけどYouTube URLがない
      end
    }

    schedules
  end


end
