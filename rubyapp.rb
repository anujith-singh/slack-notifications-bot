# require "date"
require 'time'

timestamp = "2016-06-29T18:29:35Z"


epochSecs = Time.parse(timestamp).to_i
ENV['TZ'] = 'Asia/Kolkata'
righttime = Time::at(epochSecs).to_i
puts righttime

# istTime = Time.now.in_time_zone("Chennai")

# puts istTime


