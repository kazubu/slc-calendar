# SLC Calendar

The purpose of this program is to retrieve upcoming live broadcasts on YouTube from tweets on Twitter lists and register them as schedules in Google Calendar to easily check the schedule of the live broadcasts.

This program is intended to provide [星チルカレンダー](https://kazubu.jp/slcc/) but it is not limited to. Anyone can use this program to have your original livestreaming schedule calendar from any Twitter lists.

## Install

The required gems needed to be installed. Gemfile is included in this repository.

You need to rename `config.rb.example` to `config.rb` and fill the required parameters.
Required parameters are:
 - Twitter API Consumer Key/Consumer Secret/Bearer token
 - List of Twitter Lists
 - API Key for YouTube Data API v3
 - Google Calendar ID
 - Path of client secret for a Service Account with full access to the Google Calendar.

## Usage

You can execute `update`, `update_by_tweets` or `update_registered` command that works as below. It's recommended to register them to cron or any periodical execution mechanism.
 - `update_by_tweets` command checks the tweets from Twitter list and register tweeted livestreams.
 - `update_registered` command checks registered events in Google Calendar and update the change of existing livestreams.
 - `update` command runs both above actions in sequence.
 - `update_known_channel_videos` commands checks channel information of livestreams registered in the past and register upcoming livestreams in channels.

## Web Frontend

Simple web front-end is located on webapp dir that is used in [星チルカレンダー](https://kazubu.jp/slcc/).
You can provide web-based calendar view.

Apache + Passenger example:

```
    RackBaseURI /slc-calendar/events

    Alias /slc-calendar/events /opt/slc-calendar/webapp
    <Location /slc-calendar/events>
        PassengerBaseURI /slc-calendar/events
        PassengerAppRoot /opt/slc-calendar/webapp
    </Location>
    <Directory /opt/slc-calendar/webapp>
        Allow from all
        Options -MultiViews
        Require all granted
    </Directory>
```

