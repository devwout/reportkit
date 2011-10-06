require File.join(File.dirname(__FILE__), 'spec_helper')

describe ActiveRecord::Base do
  
  describe '#column_named' do
    it 'accepts symbols as column names' do
      Company.column_named(:id).arel_attributes.should == [Company.arel_table[:id]]
    end
    it 'raises UnknownProperty when no column exists by that name' do
      lambda { Company.column_named(:blabla) }.should raise_error(Filterkit::UnknownProperty)
    end
    it 'favors declared property types over database definitions' do
      p = Company.column_named(:turnover)
      p.should_not be_nil
      p.should be_kind_of(Columns::Money)
      p.arel_attributes.should == [Company.arel_table[:turnover]]
    end
  end
  
end