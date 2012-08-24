# Specify a custom time format for icalendar
ActiveSupport::CoreExtensions::Time::Conversions::DATE_FORMATS.update(:ics => '%Y%m%dT%H%M%S')

# Specify a custom string format for icalendar
class String
  
  def to_ics
    # Escape the characters we need
    ical = self.dup
    [ ["\\","\\\\\\"],[/\r\n/,'\n' ],[/\n/,'\n' ],[',','\,'],[';','\;'] ].each do |substition|
      ical.gsub! *substition
    end
    # Shorten the text to less than 50 characters
    ical.scan(/.{1,50}/).join("\r\n ")
  end
  
end

# Add a to_ical to the Array class

class Array
  
  def to_ics
    london_vtimezone = ("BEGIN:VTIMEZONE\r\n" +
      "TZID:Europe/London\r\n" +
      "BEGIN:DAYLIGHT\r\n" +
      "TZOFFSETFROM:+0000\r\n" +
      "TZOFFSETTO:+0100\r\n" +
      "TZNAME:BST\r\n" +
      "DTSTART:19700329T010000\r\n" +
      "RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU\r\n" +
      "END:DAYLIGHT\r\n" +
      "BEGIN:STANDARD\r\n" +
      "TZOFFSETFROM:+0100\r\n" +
      "TZOFFSETTO:+0000\r\n" +
      "TZNAME:GMT\r\n" +
      "DTSTART:19701025T020000\r\n" +
      "RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU\r\n" +
      "END:STANDARD\r\n" +
      "END:VTIMEZONE\r\n")
    ("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//talks.cam.ac.uk//v3//EN\r\n" +
    london_vtimezone +
    map {|element| element.to_ics }.join("\r\n") +
    "\r\nEND:VCALENDAR\r\n")
  end
end
