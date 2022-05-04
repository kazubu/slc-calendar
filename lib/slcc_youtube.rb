#!/usr/bin/env ruby
# frozen_string_literal: true

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
        rescue StandardError
          retry if try < times
          raise
        end
      end

      def url_to_video_id(url)
        if url.index('http') == 0
          url.split('v=')[1].split('&')[0]
        else
          url
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
        return nil if thumbnails.nil? || thumbnails.empty?

        # medium/maxres is 16:9
        # default/high/standard is 4:3
        return thumbnails['medium']['url'] if thumbnails['medium']
        return thumbnails['high']['url'] if thumbnails['high']
        return thumbnails['standard']['url'] if thumbnails['standard']
        return thumbnails['maxres']['url'] if thumbnails['maxres']

        # return 1st thumbnail if above thumbnails are not found
        thumbnails.first[1]['url']
      end

      def upcoming_or_on_live?
        upcoming_stream? || on_live?
      end

      def upcoming_stream?
        @live_state == 'upcoming'
      end

      def on_live?
        @live_state == 'live'
      end

      def live?
        !@live_state.nil?
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

      video_id_array = []
      case video_ids
      when Array
        video_id_array = video_ids
      when String
        video_id_array = video_ids.split(',')
      else
        raise 'Video IDs should be Array or String'
      end

      videos += get_videos_impl(video_id_array_to_video_ids(video_id_array.pop(50))) until video_id_array.empty?

      videos
    end

    def get_playlist_videos(playlist_id)
      video_ids = []

      playlist_items = api_get(
        resource: 'playlistItems',
        options: { part: 'snippet', playlistId: playlist_id }
      )

      return nil if playlist_items.nil? || playlist_items['items'].nil? || playlist_items['items'].length == 0

      playlist_items['items'].each{|v|
        next if v['snippet'].nil?

        video_ids << v['snippet']['resourceId']['videoId']
      }

      get_videos(video_ids)
    end

    private

    def video_id_array_to_video_ids(video_id_array)
      video_id_array.map{|x| Utils.url_to_video_id x }.join(',')
    end

    def timestring_to_time(time)
      return nil unless time.is_a?(String)

      Time.at(Time.parse(time).to_i / 60 * 60).getlocal('+09:00')
    end

    def get_videos_impl(video_ids)
      videos = []

      video_details = api_get(
        resource: 'videos',
        options: { part: 'snippet,liveStreamingDetails', id: video_ids }
      )

      return nil if video_details.nil? || video_details['items'].nil?

      video_details['items'].each do |v|
        next if v['id'].nil?
        next if v['snippet'].nil?

        videos << Video.new(
          youtube: self,
          channel_id: v['snippet']['channelId'],
          channel_title: v['snippet']['channelTitle'],
          video_id: v['id'],
          video_title: v['snippet']['title'],
          live_state: ((v['snippet']['liveBroadcastContent'].nil? || v['liveStreamingDetails'].nil?) ? nil : v['snippet']['liveBroadcastContent']),
          scheduled_start_time: (v.dig('liveStreamingDetails', 'scheduledStartTime').nil? ? nil : timestring_to_time(v['liveStreamingDetails']['scheduledStartTime'])),
          actual_start_time: (v.dig('liveStreamingDetails', 'actualStartTime').nil? ? nil : timestring_to_time(v['liveStreamingDetails']['actualStartTime'])),
          actual_end_time: (v.dig('liveStreamingDetails', 'actualEndTime').nil? ? nil : timestring_to_time(v['liveStreamingDetails']['actualEndTime'])),
          thumbnails: v['snippet']['thumbnails']
        )
      end

      videos
    end

    def api_get(resource:, options:)
      options = options.map{|k, v| "#{k}=#{v}" }.join('&') if options.is_a?(Hash)

      url = "https://www.googleapis.com/youtube/v3/#{resource}?key=#{@api_key}&#{options}"

      res = nil
      Utils.retry_on_error do
        res = JSON.parse(Net::HTTP.get_response(URI.parse(url)).body)
      end

      if res['error']
        raise "Received error from YouTube. Reason: #{res['error']['errors'][0]['reason']}" if res ['error']['errors'][0] && res['error']['errors'][0]['reason']

        raise 'Received unknown error from YouTube'
      end

      res
    end
  end
end
