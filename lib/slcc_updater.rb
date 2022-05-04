#!/usr/bin/env ruby
# frozen_string_literal: true

require 'logger'
require 'damerau-levenshtein'

require_relative '../config'
require_relative './slcc_schedule_collector'
require_relative './slcc_calendar'

$logger = Logger.new($stdout)
class String
  def trunc(trunc_at, om = "")
    om_size = (om.bytesize - om.size) / 2 + om.size
    if size == bytesize
      return size <= trunc_at ? self : "#{self[0, trunc_at - om_size]}#{om}"
    end
    return self if (self.bytesize - self.size) / 2 + self.size <= trunc_at
    size.times do |i|
      str_size = (self[0..i].bytesize - self[0..i].size) / 2 + self[0..i].size
      case
      when str_size <  trunc_at - om_size; next
      when str_size == trunc_at - om_size; return "#{self[0..i]}#{om}"
      else;                                return "#{self[0..(i - 1)]}#{om}"
      end
    end
    return self
  end
end


module SLCCalendar
  class Updater
    def initialize
      @youtube = YouTube.new(api_key: YOUTUBE_DATA_API_KEY)
    end

    def update_by_tweets
      create_count = 0
      update_count = 0
      skip_count = 0

      collector = SLCCalendar::ScheduleCollector.new(
        twitter_consumer_key: TWITTER_CONSUMER_KEY,
        twitter_consumer_secret: TWITTER_CONSUMER_SECRET,
        twitter_bearer_token: TWITTER_BEARER_TOKEN,
        youtube_data_api_key: YOUTUBE_DATA_API_KEY
      )
      calendar = SLCCalendar::Calendar.new

      latest_id_list = {}
      begin
        latest_id_list = JSON.parse(File.read(TWITTER_LATEST_ID_STORE)) if File.exist?(TWITTER_LATEST_ID_STORE)
      rescue StandardError
        latest_id_list = {}
      end

      schedules = []
      TWITTER_LISTS.each do |x|
        user_id = x[0]
        list_id = x[1]
        schedules += if latest_id_list[list_id.to_s]
                       collector.get_schedules(user_id, list_id, since_id: latest_id_list[list_id.to_s].to_i)
                     else
                       collector.get_schedules(user_id, list_id)
                     end
        latest_id_list[list_id.to_s] = collector.latest_tweet_id if collector.latest_tweet_id
      end

      current_events = calendar.events
      $logger.info "#{current_events.count} events are found on Calendar."

      schedules.each do |sc|
        event_id = nil
        current_events.each do |ev|
          event_id = ev.id if ev.description.index(sc.video.video_url)
        end

        if event_id
          # event is already exists
          ev = current_events.select{|x| x.id == event_id }[0]
          nev = calendar.gen_event(sc)
          if calendar.compare_events(ev, nev)
            skip_count += 1
            $logger.info "SKIP: #{calendar.event_summary(ev)}"
          else
            update_count += 1
            $logger.info "UPDATE: #{calendar.event_summary(calendar.update(event_id, sc))}"
          end
        else
          # no existing events
          create_count += 1
          $logger.info "CREATE: #{calendar.event_summary(calendar.create(sc))}"
        end
      end

      begin
        File.write(TWITTER_LATEST_ID_STORE, latest_id_list.to_json)
      rescue StandardError => e
        $logger.warn 'Failed to write latest id list'
        $logger.error e.message
        $logger.error e.backtrace.join("\n")
      end

      $logger.info "#{create_count} created; #{update_count} updated; #{skip_count} skipped;"
    end

    # 配信URLをチェックして時間だけアップデートする
    def update_registered_events(force: false, past: 2, future: 120)
      update_count = 0
      skip_count = 0
      ended_count = 0

      calendar = SLCCalendar::Calendar.new

      current_events = calendar.events(past, future)
      $logger.info "#{current_events.count} events are found on Calendar."

      events = []
      current_events.each do |e|
        if calendar.is_live_ended(e)
          ended_count += 1
          next unless force
        end

        next unless e.description.index('/watch?v=')

        video_id = e.description.split('/watch?v=')[1].split('"')[0]

        tweet_url = nil
        if e&.extended_properties&.shared && e.extended_properties.shared['tweet_url']
          tweet_url = e.extended_properties.shared['tweet_url']
        elsif e.description.index('twitter.com/')
          tweet_url = "https://twitter.com/#{e.description.split('twitter.com/')[1].split('"')[0]}"
        end

        events << { event: e, video_id: video_id, tweet_url: tweet_url }
      end

      videos = @youtube.get_videos(events.map{|x| x[:video_id] })

      events.each do |e|
        video = videos.find{|x| x.video_id == e[:video_id] }
        tweet_url = e[:tweet_url]

        sc = Schedule.new(video: video, tweet: tweet_url)

        # live is finished after last execution
        if video.nil?
          # need to update existing event if live is deleted due to can't generate new event without video detail.
          if e[:event].extended_properties.shared
            e[:event].extended_properties.shared['live_deleted'] = true
            e[:event].extended_properties.shared['live_ended'] = true
            e[:event].extended_properties.shared['on_live'] = false
          else
            e[:event].description = "#{e[:event].description}##"
          end
          $logger.info "ENDED: #{calendar.event_summary(calendar.update_event(e[:event]))}"
          ended_count += 1
          next
        elsif !video.upcoming_or_on_live?
          # live is finished. generate new event
          $logger.info "ENDED: #{calendar.event_summary(calendar.update(e[:event].id, sc))}"
          ended_count += 1
          next
        end

        # generate new event for compare
        nev = calendar.gen_event(sc)
        if calendar.compare_events(e[:event], nev)
          skip_count += 1
          $logger.info "SKIP: #{calendar.event_summary(e[:event])}"
        else
          update_count += 1
          $logger.info "UPDATE: #{calendar.event_summary(calendar.update(e[:event].id, sc))}"
        end
      end

      $logger.info "#{update_count} updated; #{skip_count} skipped; #{ended_count} ended;"
    end

    def update_known_channel_videos()
      update_count = 0
      skip_count = 0
      ended_count = 0

      collector = SLCCalendar::ScheduleCollector.new(
        twitter_consumer_key: TWITTER_CONSUMER_KEY,
        twitter_consumer_secret: TWITTER_CONSUMER_SECRET,
        twitter_bearer_token: TWITTER_BEARER_TOKEN,
        youtube_data_api_key: YOUTUBE_DATA_API_KEY
      )

      calendar = SLCCalendar::Calendar.new
      current_events = calendar.events(10, 120)
      puts current_events.count

      channels = {}

      current_events.each do |e|
        if e&.extended_properties&.shared && e.extended_properties.shared['channel_id']
          channel_id = e.extended_properties.shared['channel_id']
          if channels.find{|k,v| k == channel_id}
            channels[channel_id][:count] += 1
          else
            channels[channel_id] = {count: 1, name: e.extended_properties.shared['channel_name'] }
          end
        end
      end

      twitter_list_members = []

      TWITTER_LISTS.each do |x|
        user_id = x[0]
        list_id = x[1]
        twitter_list_members += collector.get_list_members(user_id, list_id)
      end

      channels.each{|k, v|
        name = v[:name].split(/Ch\.|ちゃんねる|Channel|channel/)[0].split(/[\/\-@＠‐]/)[0].gsub(' ', '').trunc(12)

        # if count is greater than 3, it will be checked.
        if v[:count] > 3
          channels[k][:need_check] = true
          next
        end

        # if count is less than 3, check twitter lists.
        distances = []
        max_distance = 4
        twitter_list_members.each{|member|
          full_match = nil
          twn = member[:name].split(/[\/\-@＠‐]/)[0].gsub(/\(.+\)/,'').gsub(' ', '').trunc(16)
          if twn.length <= name.length
            full_match = twn if twn == name[0...twn.length]
          else
            full_match = twn if twn[0...name.length] == name
          end

          if full_match
            distances << [full_match, -1]
            break
          else
            distance = DamerauLevenshtein.distance(name, twn)
            allowed_distance = max_distance
            if name.length - 2 <= max_distance
              allowed_distance = name.length - 2
            end

            if distance <= allowed_distance
              distances << [twn, distance] if distance <= allowed_distance
            end
          end
        }

        if distances.length > 0
          channels[k][:need_check] = true
        else
          channels[k][:need_check] = false
        end
      }

      channels.each{|id, v|
        pp v
      }

    end

    def force_register(video_id)
      c = SLCCalendar::Calendar.new

      current_events = c.events(10, 30)

      if current_events.find{|x| x.description.index(video_id) }
        $logger.info 'This video is exists.'
        return false
      end

      video = @youtube.get_videos(video_id)[0]
      unless video
        $logger.error 'Invalid video id?'
        return false
      end

      sc = Schedule.new(video: video, tweet: nil)

      $logger.info "CREATE: #{c.event_summary(c.create(sc))}"
    end
  end
end
