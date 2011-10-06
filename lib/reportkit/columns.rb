module Reportkit
  module Columns
    
    class Date < Column
      def value(date)
        date = date.in_time_zone.to_date if date.is_a?(Time) or date.is_a?(DateTime)
        date
      end
      def format(date)
        return unless date
        @format_string ||= option(:format_options, :date_format) || '%Y-%m-%d'
        date.strftime(@format_string)
      end
    end
    
    class Time < Column
      def value(time)
        time.try(:in_time_zone)
      end
      def format(time)
        return unless time
        @format_string ||= [
          option(:format_options, :date_format) || '%Y-%m-%d',
          option(:format_options, :time_format) || '%H:%M'
        ].join(' ')
        time.strftime(@format_string)
      end
    end
    
    class Duration < Column
      def value(start, stop)
        stop - start
      end
      def format(duration)
        sprintf("%02d:%02d", duration / 3600, duration % 3600 / 60)
      end
    end
    
    # TODO: consolidate Duration and DurationMinutes when we can trash the TimeRegistration report...
    class DurationMinutes < Column
      def value(seconds)
        seconds.to_i / 60
      end
      def format(duration)
        case @format ||= option(:format_options, :duration_format)
        when 'minutes' then duration.to_s
        when 'hours' then (duration.to_f / 60).to_s.sub('.', ',')
        else
          sprintf("%02d:%02d", duration / 60, duration % 60)
        end
      end
    end
    
    class Boolean < Column
      # Typecast code ripped from arel. The result may not be casted already,
      # since it may come from an sql expression which is typeless.
      def value(value)
        case value
        when true, false then value
        when nil         then false
        when 1           then true
        when 0           then false
        else
          case value.to_s.downcase.strip
          when 'true', '1' then true
          when 'false', '0' then false
          else true # TODO: or typecasting error? or nil?
          end
        end
      end
      def format(bool)
        bool ? 1 : 0
      end
    end
    
    class Integer < Column
      def value(v)
        v && v.to_i
      end
    end
    
    class Decimal < Column
      def value(v)
        v && v.to_f
      end
      def format(number)
        return unless number
        @comma ||= option(:format_options, :decimal_format) == ','
        @precision ||= option(:format_options, :decimal_precision) # TODO: set on initialize
        @delimiter ||= option(:format_options, :decimal_delimiter)
        if @precision
          number = sprintf("%01.#{@precision}f", (Float(number) * (10 ** @precision)).round.to_f / 10 ** @precision)
        end
        parts = number.to_s.split('.')
        parts[0].gsub!(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1#{@delimiter}") if @delimiter
        parts.join(@comma ? ',' : '.')
      end
    end
    
    class Money < Decimal ; end
    
  end
end