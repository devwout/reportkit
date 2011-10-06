require File.join(File.dirname(__FILE__), 'spec_helper')

describe Columns::Date do
  before do
    @c = Columns::Date.new(:dat, nil)
  end
  
  it 'formats dates as %Y-%m-%d by default' do
    @c.format(Date.civil(2010,1,31)).should == '2010-01-31'
  end
  
  it 'formats dates with a custom formatter provided in the options' do
    @c.options = {:format_options => {:date_format => '%d/%m!x%y'}}
    @c.format(Date.civil(2009,12,31)).should == '31/12!x09'
  end
end

describe Columns::Time do
  before do
    @c = Columns::Time.new(:tim, nil)
  end
  
  it 'formats times as %Y-%m-%d %H:%M by default' do
    @c.format(Time.parse('2011-03-16 02:13:30')).should == "2011-03-16 02:13"
  end
  
  it 'formats times with custom date and time formatters provided in the options' do
    @c.options = {:format_options => {:date_format => '%m %d', :time_format => '%H::%M::%S'}}
    @c.format(Time.parse('2011-03-16 02:13:30')).should == "03 16 02::13::30"
  end
end

describe Columns::Duration do
  before(:all) do
    @c = Columns::Duration.new(:dur, nil)
  end
  
  it 'formats durations in seconds as 00:00 (hour-minute)' do
    @c.format(10).should == "00:00"
    @c.format(119).should == "00:01"
    @c.format(3599).should == "00:59"
    @c.format(126840).should == "35:14"
    @c.format(756000).should == "210:00"
  end
end

describe Columns::DurationMinutes do
  before do
    @c = Columns::DurationMinutes.new(:mins, nil)
  end
  
  it 'formats duration in minutes as 00:00 (hour-minute) by default' do
    @c.format(0).should == "00:00"
    @c.format(59).should == "00:59"
    @c.format(60).should == "01:00"
    @c.format(1000).should == "16:40"
    @c.format(126544).should == "2109:04"
  end
  
  it 'formats duration in minutes when the format option is given' do
    @c.options = {:format_options => {:duration_format => 'minutes'}}
    @c.format(66).should == "66"
    @c.format(12456).should == "12456"
  end
  
  it 'formats duration in hours when the format option is given' do
    @c.options = {:format_options => {:duration_format => 'hours'}}
    @c.format(90).should == "1,5"
    @c.format(10547).should == "175,783333333333"
  end
end

describe Columns::Boolean do
  before(:all) do
    @c = Columns::Boolean.new(:bool, nil)
  end
  
  it 'performs casting for well-known boolean notations' do
    [false, nil, 0, 0.0, '0', 'false'].each do |raw|
      @c.value(raw).should == false
    end
    [true, 1, '1', 'true'].each do |raw|
      @c.value(raw).should == true
    end
    ['pipi', Object.new, 2, -10, 0.1].each do |raw|
      @c.value(raw).should == true
    end
  end
  
  it 'formats booleans as 0 or 1' do
    @c.format(true).should == 1
    @c.format(false).should == 0
    @c.format(nil).should == 0
  end
end

describe Columns::Decimal do
  before do
    @c = Columns::Decimal.new(:dec, nil)
  end
  
  it 'formats decimals with period delimiter by default' do
    @c.format(21.33333).should == "21.33333"
  end
  
  it 'formats decimals with comma delimiter when provided in the options' do
    @c.options = {:format_options => {:decimal_format => ','}}
    @c.format(21.33333).should == '21,33333'
  end
  
  it 'formats decimals with fixed precision when provided in the options' do
    @c.options = {:format_options => {:decimal_precision => 2}}
    @c.format(21.33333).should == "21.33"
    @c.format(21.335).should == "21.34"
  end
  
  it 'formats decimals with a thousands separator when provided in the options' do
    @c.format(4955642).should == "4955642"
    @c.options = {:format_options => {:decimal_delimiter => ','}}
    @c.format(4955642).should == "4,955,642"
  end
end

describe Columns::Integer do
  before do
    @c = Columns::Integer.new(:int, nil)
  end
  
  it 'converts strings to integers' do
    @c.value("100.55").should == 100
  end
  
  it 'converts decimals to integers' do
    @c.value(100.55).should == 100
  end
  
  it 'retains nil values' do
    @c.value(nil).should be_nil
  end
end