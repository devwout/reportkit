$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '..', 'lib')
$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '..', '..', 'filterkit', 'lib')
require 'reportkit'

require File.join(File.dirname(__FILE__), 'model')

include Reportkit
