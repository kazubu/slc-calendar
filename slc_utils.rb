#!/usr/bin/env ruby

module SLCCalendar
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

    def get_youtube_video_detail(video_id)
      video_id = Utils.vurl_to_vid(video_id)
      url = "https://www.googleapis.com/youtube/v3/videos?key=#{YOUTUBE_DATA_API_KEY}&part=snippet,liveStreamingDetails&id=#{video_id}"

      res = nil
      Utils.retry_on_error {
        res = JSON.parse(Net::HTTP.get_response(URI.parse(url)).body)
      }

      if res['error']
        if res ['error']['errors'][0] && res['error']['errors'][0]['reason']
          raise res['error']['errors'][0]['reason']
        else
          raise 'unknown error from YouTube'
        end
      end

      return res
    end

    def is_upcoming_stream(video_id, force: false)
      video_id = Utils.vurl_to_vid(video_id)
      v = Utils.get_youtube_video_detail video_id

      if !v.nil? && !v['items'].nil? && !v['items'][0].nil? && v['items'][0]['id'] == video_id
        if !v['items'][0]['snippet'].nil? && !v['items'][0]['snippet']['liveBroadcastContent'].nil? && (v['items'][0]['snippet']['liveBroadcastContent'] == 'upcoming' || force) && !v['items'][0]['liveStreamingDetails'].nil? && !v['items'][0]['liveStreamingDetails']['scheduledStartTime'].nil?
          video_url = "https://www.youtube.com/watch?v=#{video_id}"
          return video_url, Time.parse(v['items'][0]['liveStreamingDetails']['scheduledStartTime']).getlocal("+09:00"), v['items'][0]['snippet']['channelTitle'], v['items'][0]['snippet']['title']
        end
      end

      return false
    end

    module_function :retry_on_error
    module_function :expand_url
    module_function :vurl_to_vid
    module_function :get_youtube_video_detail
    module_function :is_upcoming_stream
  end
end
