require 'spec_helper'
require_db 'position/positioner'

module RCS
module DB

describe Positioner do

  def point_from_string(string)
    values = string.split(' ')
    Point.new({time: Time.parse("#{values.shift} #{values.shift} +0100"),
               lat: values.shift.to_f,
               lon: values.shift.to_f,
               r: values.shift.to_i})
  end

  def load_points(strings)
    points = []
    strings.each_line do |e|
      points << point_from_string(e)
    end
    points
  end

  def emit_staying(positioner, points)
    emitted = []

    points.each do |point|
      positioner.feed(point) do |e|
        emitted << e
      end
    end

    emitted
  end

  context 'given an array of Points with a small stay point' do
    before do
      # the STAY point is:
      # 45.514992 9.5873462 10 (2013-01-15 07:37:43 - 2013-01-15 07:40:43)
      data =
      "2013-01-15 07:36:43 45.5149089 9.5880504 25
      2013-01-15 07:36:43 45.515057 9.586814 3500
      2013-01-15 07:37:43 45.5149920 9.5873462 10
      2013-01-15 07:37:43 45.515057 9.586814 3500
      2013-01-15 07:38:43 45.5149920 9.5873462 15
      2013-01-15 07:38:43 45.515057 9.586814 3500
      2013-01-15 07:39:43 45.5148914 9.5873097 10
      2013-01-15 07:39:43 45.515057 9.586814 3500
      2013-01-15 07:40:43 45.5148914 9.5873097 10
      2013-01-15 07:40:43 45.515057 9.586814 3500
      2013-01-15 07:41:43 45.5147590 9.5821532 25"

      @points = load_points(data)
    end

    it 'should not emit stay point with 10 minute timefram' do
      # default min time is 10 minutes
      positioner = Positioner.new
      emitted = emit_staying(positioner, @points)
      emitted.should be_empty
    end

    it 'should detect the stay point with 3 minutes timeframe' do
      # set it to 3 minutes to emit a point
      positioner = Positioner.new(time: 3*60)
      emitted = emit_staying(positioner, @points)
      emitted.should_not be_empty
      emitted.size.should be 1

      found = emitted.first
      found.lat.should eq 45.514992
      found.lon.should eq 9.5873462
      found.r.should be 10
      found.start.should eq Time.local(2013, 1, 15, 7, 37, 43)
      found.end.should eq Time.local(2013, 1, 15, 7, 40, 43)
    end
  end

  context 'given an array of Point with a big stay point' do
    before do
      # the STAY point is:
      # 45.4768394 9.1919074 15 (2013-01-15 08:41:43 - 2013-01-15 09:22:18 )
      data =
      "2013-01-15 08:34:47 45.4808555 9.1972061 50
      2013-01-15 08:35:43 45.4804529 9.1963426 5
      2013-01-15 08:35:43 45.481476 9.195733 3500
      2013-01-15 08:36:43 45.4798806 9.1953605 5
      2013-01-15 08:36:43 45.47943 9.193656 3500
      2013-01-15 08:37:43 45.4792564 9.1942233 5
      2013-01-15 08:37:43 45.479427 9.193684 3500
      2013-01-15 08:38:43 45.4795906 9.1932162 5
      2013-01-15 08:38:43 45.479721 9.191801 3500
      2013-01-15 08:39:43 45.4786170 9.1922358 30
      2013-01-15 08:39:43 45.476985 9.192453 3500
      2013-01-15 08:40:43 45.4777251 9.1917863 5
      2013-01-15 08:40:43 45.476773 9.190884 3500
      2013-01-15 08:41:43 45.4768394 9.1919074 15
      2013-01-15 08:41:43 45.476773 9.190884 3500
      2013-01-15 08:42:43 45.4763669 9.1913297 77
      2013-01-15 08:42:43 45.476773 9.190884 3500
      2013-01-15 08:43:43 45.4761434 9.1913594 125
      2013-01-15 08:43:43 45.476773 9.190884 3500
      2013-01-15 08:45:18 45.476773 9.190884 3500
      2013-01-15 08:46:18 45.475958 9.190387 3500
      2013-01-15 08:47:18 45.475958 9.190387 3500
      2013-01-15 08:48:18 45.475958 9.190387 3500
      2013-01-15 08:49:18 45.475958 9.190387 3500
      2013-01-15 08:50:18 45.475958 9.190387 3500
      2013-01-15 08:51:18 45.475958 9.190387 3500
      2013-01-15 08:52:18 45.475958 9.190387 3500
      2013-01-15 08:53:18 45.475958 9.190387 3500
      2013-01-15 08:54:18 45.475958 9.190387 3500
      2013-01-15 08:55:18 45.475958 9.190387 3500
      2013-01-15 08:56:18 45.475958 9.190387 3500
      2013-01-15 08:57:18 45.475958 9.190387 3500
      2013-01-15 08:58:18 45.475958 9.190387 3500
      2013-01-15 08:59:18 45.476773 9.190884 3500
      2013-01-15 09:00:18 45.476773 9.190884 3500
      2013-01-15 09:01:18 45.475958 9.190387 3500
      2013-01-15 09:02:18 45.475958 9.190387 3500
      2013-01-15 09:03:18 45.475958 9.190387 3500
      2013-01-15 09:04:18 45.475958 9.190387 3500
      2013-01-15 09:05:18 45.475958 9.190387 3500
      2013-01-15 09:06:18 45.475958 9.190387 3500
      2013-01-15 09:07:18 45.475958 9.190387 3500
      2013-01-15 09:08:18 45.475958 9.190387 3500
      2013-01-15 09:09:18 45.475958 9.190387 3500
      2013-01-15 09:10:18 45.475958 9.190387 3500
      2013-01-15 09:11:18 45.475958 9.190387 3500
      2013-01-15 09:12:18 45.475958 9.190387 3500
      2013-01-15 09:13:18 45.475958 9.190387 3500
      2013-01-15 09:14:18 45.475958 9.190387 3500
      2013-01-15 09:15:18 45.475958 9.190387 3500
      2013-01-15 09:16:18 45.475958 9.190387 3500
      2013-01-15 09:17:18 45.475958 9.190387 3500
      2013-01-15 09:18:18 45.475958 9.190387 3500
      2013-01-15 09:19:18 45.475958 9.190387 3500
      2013-01-15 09:20:18 45.475958 9.190387 3500
      2013-01-15 09:21:18 45.475958 9.190387 3500
      2013-01-15 09:22:18 45.475958 9.190387 3500"

      @points = load_points(data)
    end

    it 'should detect the stay point' do
      positioner = Positioner.new
      emitted = emit_staying(positioner, @points + [Point.new])
      emitted.should_not be_empty
      emitted.size.should be 1

      found = emitted.first
      found.lat.should eq 45.4768394
      found.lon.should eq 9.1919074
      found.r.should eq 15
      found.start.should eq Time.local(2013, 1, 15, 8, 41, 43)
      found.end.should eq Time.local(2013, 1, 15, 9, 22, 18)
    end
  end

  context 'given an array of moving points' do
    before do
      # no STAY points
      data =
      "2013-01-15 08:18:43 45.4771410 9.2790018 45
      2013-01-15 08:18:43 45.479385 9.267321 3500
      2013-01-15 08:19:43 45.4745361 9.2639604 45
      2013-01-15 08:20:43 45.4725768 9.2532104 50
      2013-01-15 08:20:43 45.472919 9.252803 3500
      2013-01-15 08:21:43 45.467058 9.240121 3500
      2013-01-15 08:22:43 45.463381 9.236164 3500
      2013-01-15 08:23:43 45.461875 9.232106 3500
      2013-01-15 08:34:47 45.4808555 9.1972061 50
      2013-01-15 08:35:43 45.4804529 9.1963426 5
      2013-01-15 08:35:43 45.481476 9.195733 3500
      2013-01-15 08:36:43 45.4798806 9.1953605 5
      2013-01-15 08:36:43 45.47943 9.193656 3500
      2013-01-15 08:37:43 45.4792564 9.1942233 5
      2013-01-15 08:37:43 45.479427 9.193684 3500"

      @points = load_points(data)
    end

    it 'should not detect any stay point' do
      positioner = Positioner.new
      emitted = emit_staying(positioner, @points + [Point.new])
      emitted.should be_empty
    end
  end

  context 'given an array of point with a data hole' do
    before do
      # the STAY points are:
      # 45.4792009 9.1891592 30  (2013-01-15 12:58:18 - 2013-01-15 13:12:18)
      # 45.4765921521739 9.19198076086957 35 (2013-01-15 14:49:29 - 2013-01-15 15:00:29 )
      data =
      "2013-01-15 12:58:18 45.4792009 9.1891592 30
      2013-01-15 12:58:18 45.479504 9.191055 3500
      2013-01-15 12:59:18 45.4796248 9.1896666 52
      2013-01-15 12:59:18 45.479504 9.191055 3500
      2013-01-15 13:00:18 45.4792650 9.1892971 165
      2013-01-15 13:00:18 45.479504 9.191055 3500
      2013-01-15 13:01:18 45.4792650 9.1892971 183
      2013-01-15 13:01:18 45.479504 9.191055 3500
      2013-01-15 13:02:18 45.4792650 9.1892971 201
      2013-01-15 13:03:18 45.4792650 9.1892971 217
      2013-01-15 13:03:18 45.474878 9.190448 1000
      2013-01-15 13:04:18 45.474878 9.190448 1000
      2013-01-15 13:05:18 45.474878 9.190448 1000
      2013-01-15 13:06:00 45.4792650 9.1892971 217
      2013-01-15 13:06:18 45.4792650 9.1892971 223
      2013-01-15 13:06:18 45.474878 9.190448 1000
      2013-01-15 13:07:18 45.4792650 9.1892971 241
      2013-01-15 13:08:18 45.4792650 9.1892971 259
      2013-01-15 13:09:18 45.4792650 9.1892971 277
      2013-01-15 13:10:18 45.4792650 9.1892971 295
      2013-01-15 13:11:18 45.4792650 9.1892971 312
      2013-01-15 13:12:18 45.4792650 9.1892971 0
      2013-01-15 13:46:18 45.479504 9.191055 3500
      2013-01-15 13:47:18 45.4796048 9.1899594 40
      2013-01-15 13:47:18 45.479504 9.191055 3500
      2013-01-15 14:48:23 45.475958 9.190387 3500
      2013-01-15 14:49:22 45.475958 9.190387 3500
      2013-01-15 14:49:29 45.4765798363636 9.19202071818182 40
      2013-01-15 14:50:22 45.475958 9.190387 3500
      2013-01-15 14:50:29 45.47657328125 9.1920464375 50
      2013-01-15 14:51:22 45.475958 9.190387 3500
      2013-01-15 14:51:29 45.4765737684211 9.19204335789474 50
      2013-01-15 14:52:22 45.475958 9.190387 3500
      2013-01-15 14:52:29 45.4765822844828 9.19201257758621 40
      2013-01-15 14:53:22 45.475958 9.190387 3500
      2013-01-15 14:53:29 45.4765790285714 9.1920378 50
      2013-01-15 14:54:22 45.475958 9.190387 3500
      2013-01-15 14:54:29 45.4765921521739 9.19198076086957 35
      2013-01-15 14:55:22 45.475958 9.190387 3500
      2013-01-15 14:55:29 45.476559527027 9.19205722972973 66
      2013-01-15 14:56:22 45.475958 9.190387 3500
      2013-01-15 14:56:29 45.4765887118644 9.191975 40
      2013-01-15 14:57:22 45.475958 9.190387 3500
      2013-01-15 14:57:29 45.4765715106383 9.19204797872341 50
      2013-01-15 14:58:22 45.475958 9.190387 3500
      2013-01-15 14:58:29 45.4765842255639 9.19198761654135 35
      2013-01-15 14:59:22 45.475958 9.190387 3500
      2013-01-15 14:59:29 45.4765732234043 9.19204562765957 50
      2013-01-15 15:00:22 45.475958 9.190387 3500
      2013-01-15 15:00:29 45.4765828376068 9.1920078034188 40"

      @points = load_points(data)
    end

    it 'should detect two stay points' do
      positioner = Positioner.new
      emitted = emit_staying(positioner, @points + [Point.new])
      emitted.size.should be 2

      first = emitted.first
      first.lat.should eq 45.4792009
      first.lon.should eq 9.1891592
      first.r.should eq 30
      first.start.should eq Time.local(2013, 1, 15, 12, 58, 18)
      first.end.should eq Time.local(2013, 1, 15, 13, 12, 18)

      second = emitted.last
      second.lat.should eq 45.4765921521739
      second.lon.should eq 9.19198076086957
      second.r.should eq 35
      second.start.should eq Time.local(2013, 1, 15, 14, 49, 29)
      second.end.should eq Time.local(2013, 1, 15, 15, 00, 29)
    end
  end

  context 'given an array of points with increasing precision' do
    before do
      # the STAY point is:
      # 45.4768005 9.1917216 5 (2013-01-15 17:30:19 - 2013-01-15 17:41:23)
      # getting better from:
      # 45.4765950147059 9.19197409558823 35
      data =
      "2013-01-15 17:30:19 45.475958 9.190387 3500
      2013-01-15 17:30:25 45.4765989264706 9.19196678676471 35
      2013-01-15 17:31:19 45.475958 9.190387 3500
      2013-01-15 17:31:25 45.4765859272727 9.19199954545455 40
      2013-01-15 17:32:19 45.475958 9.190387 3500
      2013-01-15 17:32:25 45.4765787586207 9.19204289655172 50
      2013-01-15 17:33:19 45.475958 9.190387 3500
      2013-01-15 17:33:25 45.4765719285714 9.19194480357143 40
      2013-01-15 17:34:19 45.475958 9.190387 3500
      2013-01-15 17:34:25 45.4765812 9.19193278461539 35
      2013-01-15 17:35:19 45.475958 9.190387 3500
      2013-01-15 17:35:25 45.4765932090909 9.19188369090909 40
      2013-01-15 17:36:19 45.475958 9.190387 3500
      2013-01-15 17:36:25 45.4765524666667 9.19208173333333 66
      2013-01-15 17:37:19 45.475958 9.190387 3500
      2013-01-15 17:37:25 45.4765585454545 9.19206063636364 66
      2013-01-15 17:38:19 45.475958 9.190387 3500
      2013-01-15 17:38:25 45.4765269894737 9.1922372 40
      2013-01-15 17:39:19 45.475958 9.190387 3500
      2013-01-15 17:39:25 45.4765927647059 9.19194729411765 66
      2013-01-15 17:40:19 45.475958 9.190387 3500
      2013-01-15 17:40:33 45.4767174 9.1915881 50
      2013-01-15 17:41:19 45.4768005 9.1917216 5
      2013-01-15 17:41:19 45.476773 9.190884 3500
      2013-01-15 17:41:23 45.4770617853107 9.19218252542373 35
      2013-01-15 17:42:19 45.4773772 9.1921140 5
      2013-01-15 17:42:19 45.476773 9.190884 3500
      2013-01-15 17:42:22 45.4783532222222 9.19225337777778 50"

      @points = load_points(data)
    end

    it 'should detect the more precise point' do
      positioner = Positioner.new
      emitted = emit_staying(positioner, @points + [Point.new])
      emitted.should_not be_empty
      emitted.size.should be 1

      found = emitted.first
      found.lat.should eq 45.4768005
      found.lon.should eq 9.1917216
      found.r.should eq 5
      found.start.should eq Time.local(2013, 1, 15, 17, 30, 19)
      found.end.should eq Time.local(2013, 1, 15, 17, 41, 23)
    end
  end

  context 'given an array of points (exactly the size of the window)' do
    before do
      # we need to feed 6 points since the default window is 5
      data =
      "2013-01-15 20:56:30 45.519874 9.590737 3500
      2013-01-15 20:57:30 45.5217845 9.5950983 50
      2013-01-15 20:57:30 45.519874 9.590737 3500
      2013-01-15 20:58:30 45.5217065 9.5951096 45
      2013-01-15 20:58:30 45.519874 9.590737 3500
      2013-01-15 20:59:30 45.5215891 9.5951431 45"

      @points = load_points(data)
    end

    it 'should detect one stay point' do
      positioner = Positioner.new(time: 0)
      emitted = emit_staying(positioner, @points + [Point.new])
      emitted.should_not be_empty
      emitted.size.should be 1

      found = emitted.first
      found.lat.should eq 45.5217065
      found.lon.should eq 9.5951096
      found.r.should eq 45
      found.start.should eq Time.local(2013, 1, 15, 20, 56, 30)
      found.end.should eq Time.local(2013, 1, 15, 20, 59, 30)
    end
  end

  context 'give an array of points with a big radius' do
    before do
      data =
      "2013-01-15 20:56:30 45.519874 9.590737 3500
      2013-01-15 20:57:30 45.5217845 9.5950983 3500
      2013-01-15 20:57:30 45.519874 9.590737 3500
      2013-01-15 20:58:30 45.5217065 9.5951096 3500
      2013-01-15 20:58:30 45.519874 9.590737 3500
      2013-01-15 20:59:30 45.5215891 9.5951431 3500"

      @points = load_points(data)
    end

    it 'should not detect any stay point (radius too big)' do
      # default radius is 500
      positioner = Positioner.new(time: 0)
      emitted = emit_staying(positioner, @points + [Point.new])
      emitted.should be_empty
    end

    it 'should detect the stay point (setting the raius filter to bigger value)' do
      # change the filter on the radius to 3500
      positioner = Positioner.new(time: 0, radius: 3500)
      emitted = emit_staying(positioner, @points + [Point.new])
      emitted.should_not be_empty
      emitted.size.should be 1

      found = emitted.first
      found.lat.should eq 45.519874
      found.lon.should eq 9.590737
      found.r.should eq 3500
      found.start.should eq Time.local(2013, 1, 15, 20, 56, 30)
      found.end.should eq Time.local(2013, 1, 15, 20, 59, 30)
    end
  end

  context 'given two array of points' do
    before do
      # the STAY point is:
      # 45.514992 9.5873462 10 (2013-01-15 07:37:43 - 2013-01-15 07:40:43)
      data =
      "2013-01-15 07:36:43 45.5149089 9.5880504 25
      2013-01-15 07:36:43 45.515057 9.586814 3500
      2013-01-15 07:37:43 45.5149920 9.5873462 10
      2013-01-15 07:37:43 45.515057 9.586814 3500
      2013-01-15 07:38:43 45.5149920 9.5873462 15"

      @points1 = load_points(data)

      data =
      "2013-01-15 07:38:43 45.515057 9.586814 3500
      2013-01-15 07:39:43 45.5148914 9.5873097 10
      2013-01-15 07:39:43 45.515057 9.586814 3500
      2013-01-15 07:40:43 45.5148914 9.5873097 10
      2013-01-15 07:40:43 45.515057 9.586814 3500
      2013-01-15 07:41:43 45.5147590 9.5821532 25"

      @points2 = load_points(data)
    end

    it 'should dump the current status' do
      positioner = Positioner.new
      @points1.each do |point|
        positioner.feed(point)
      end

      dump = positioner.dump
      dup = Positioner.new_from_dump(dump)

      # check that the value are identical
      dup.instance_variables.each do |var|
        dup.instance_variable_get(var).should eq positioner.instance_variable_get(var)
      end
    end

    it 'should restart from previous status' do
      # set it to 3 minutes to emit a point
      positioner = Positioner.new(time: 3*60)
      emitted = emit_staying(positioner, @points1)

      dump = positioner.dump

      positioner = Positioner.new_from_dump(dump)
      emitted += emit_staying(positioner, @points2)

      emitted.should_not be_empty
      emitted.size.should be 1

      found = emitted.first
      found.lat.should eq 45.514992
      found.lon.should eq 9.5873462
      found.r.should be 10
      found.start.should eq Time.local(2013, 1, 15, 7, 37, 43)
      found.end.should eq Time.local(2013, 1, 15, 7, 40, 43)
    end
  end

end

end
end
