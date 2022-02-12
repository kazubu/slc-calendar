#!/usr/bin/env ruby
require 'json'
require 'net/http'
require 'time'
require 'uri'

module SLCCalendar
  class YouTube
    module Utils
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

      def url_to_video_id(url)
        if url.index('http') == 0
          return url.split('v=')[1].split('&')[0]
        else
          return url
        end
      end

      module_function :retry_on_error
      module_function :url_to_video_id
    end

    class Video
      attr_reader :channel_id, :channel_title, :video_id, :video_title, :live_state, :scheduled_start_time, :actual_start_time, :actual_end_time, :thumbnails

      def initialize(youtube:, channel_id:, channel_title:, video_id:, video_title:, live_state:, scheduled_start_time:, actual_start_time:, actual_end_time:, thumbnails:)
        @youtube = youtube
        @channel_id = channel_id
        @channel_title = channel_title
        @video_id = video_id
        @video_title = video_title
        @live_state = live_state
        @scheduled_start_time = scheduled_start_time
        @actual_start_time = actual_start_time
        @actual_end_time = actual_end_time
        @thumbnails = thumbnails
      end

      def video_url
        "https://www.youtube.com/watch?v=#{@video_id}"
      end

      def thumbnail_url
        return nil if thumbnails.nil? || thumbnails.count == 0

        return thumbnails["standard"]["url"] if thumbnails["standard"]
        return thumbnails["high"]["url"] if thumbnails["high"]
        return thumbnails["maxres"]["url"] if thumbnails["maxres"]

        # return 1st thumbnail if above thumbnails are not found
        return thumbnails.first[1]["url"]
      end

      def is_upcoming_stream
        return true if @live_state == 'upcoming' || @live_state == 'live'
        false
      end

      def update
        x = @youtube.get_videos(video_id)[0]
        x.instance_variables.each{|k| instance_variable_set(k, x.instance_variable_get(k)) }
        self
      end
    end

    def initialize(api_key:)
      @api_key = api_key
    end

    def get_videos(video_ids)
      videos = []

      if video_ids.kind_of?(Array)
        video_ids = video_ids.map{|x| Utils.url_to_video_id x}.join(',')
      elsif video_ids.kind_of?(String) && video_ids.index(',')
        video_ids = video_ids.split(',').map{|x| Utils.url_to_video_id x}.join(',')
      else
        video_ids = Utils.url_to_video_id(video_ids)
      end

      return get_videos_impl(video_ids)
    end

    private

    def get_videos_impl(video_ids)
      videos = []

      video_details = api_get(
        resource: 'videos',
        options: { part: 'snippet,liveStreamingDetails', id: video_ids }
      )

      return nil if video_details.nil? || video_details['items'].nil?

      video_details['items'].each{|v|
        next if v['id'].nil?
        next if v['snippet'].nil?

        videos << Video.new(
          youtube: self,
          channel_id: v['snippet']['channelId'],
          channel_title: v['snippet']['channelTitle'],
          video_id: v['id'],
          video_title: v['snippet']['title'],
          live_state: (v['snippet']['liveBroadcastContent'].nil? ? nil : v['snippet']['liveBroadcastContent']),
          scheduled_start_time: ((v['liveStreamingDetails'].nil? || v['liveStreamingDetails']['scheduledStartTime'].nil?) ? nil : Time.at(Time.parse(v['liveStreamingDetails']['scheduledStartTime']).to_i / 60 * 60).getlocal("+09:00")),
          actual_start_time: ((v['liveStreamingDetails'].nil? || v['liveStreamingDetails']['actualStartTime'].nil?) ? nil : Time.at(Time.parse(v['liveStreamingDetails']['actualStartTime']).to_i / 60 * 60).getlocal("+09:00")),
          actual_end_time: ((v['liveStreamingDetails'].nil? || v['liveStreamingDetails']['actualEndTime'].nil?) ? nil : Time.at(Time.parse(v['liveStreamingDetails']['actualEndTime']).to_i / 60 * 60).getlocal("+09:00")),
          thumbnails: v['snippet']['thumbnails']
        )
      }

      return videos
    end

    def api_get(resource:, options:)
      if options.kind_of?(Hash)
        options = options.map{|k,v| "#{k}=#{v}"}.join('&')
      end

      url = "https://www.googleapis.com/youtube/v3/#{resource}?key=#{@api_key}&#{options}"

      res = nil
      Utils.retry_on_error {
        res = JSON.parse(Net::HTTP.get_response(URI.parse(url)).body)
      }

      if res['error']
        if res ['error']['errors'][0] && res['error']['errors'][0]['reason']
          raise 'Received error from YouTube. Reason: ' + res['error']['errors'][0]['reason']
        else
          raise 'Received unknown error from YouTube'
        end
      end

      res
    end
  end
end
