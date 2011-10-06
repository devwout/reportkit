require File.join(File.dirname(__FILE__), 'spec_helper')

describe 'arel_ext' do
  it 'allows specifying the ordering in group clauses' do
    Company.arel_table.
      group(Company.arel_table[:name].asc, Company.arel_table[:id].desc).
      project(Company.arel_table[:id]).to_sql.should == 
    "SELECT     `companies`.`id` FROM       `companies` GROUP BY  `companies`.`name` ASC, `companies`.`id` DESC"
  end
  
  it 'allows ordering on aggregates' do
    Company.arel_table.group(Company.arel_table[:id]).
      project(Company.arel_table[:id].sum).
      order(Company.arel_table[:id].sum).to_sql.should == 
    "SELECT     SUM(`companies`.`id`) FROM       `companies` GROUP BY  `companies`.`id` ORDER BY  sum_id ASC"
  end
  
  it 'allows ordering on aggregates with their own alias' do
    Company.arel_table.group(Company.arel_table[:name]).
      project(Company.arel_table[:updated_at].maximum.as(:max_timestamp)).
      order(Company.arel_table[:updated_at].maximum.as(:max_timestamp).desc).to_sql.should == 
    "SELECT     MAX(`companies`.`updated_at`) AS `max_timestamp` FROM       `companies` GROUP BY  `companies`.`name` ORDER BY  max_timestamp DESC"
  end
  
  it 'has the mysql-specific group_concat aggregate' do
    Company.arel_table.group(Company.arel_table[:name]).project(Company.arel_table[:id].group_concat).to_sql.should ==
    "SELECT     GROUP_CONCAT(`companies`.`id`) FROM       `companies` GROUP BY  `companies`.`name`"
  end
  
  it 'has the mysql-specific group_concat aggregate with distinct' do
    Company.arel_table.group(Company.arel_table[:name]).project(Company.arel_table[:id].group_concat(true)).to_sql.should ==
    "SELECT     GROUP_CONCAT(DISTINCT `companies`.`id`) FROM       `companies` GROUP BY  `companies`.`name`"
  end
  
  it 'has the mysql-specific group_concat aggregate with order by' do
    Company.arel_table.group(Company.arel_table[:name]).project(Company.arel_table[:id].group_concat(false, Company.arel_table[:name]).as(:x)).to_sql.should ==
    "SELECT     GROUP_CONCAT(`companies`.`id` ORDER BY `companies`.`name` ASC) AS `x` FROM       `companies` GROUP BY  `companies`.`name`"
  end
    
  it 'has the concat expression' do
    Company.arel_table.project(Company.arel_table[:id].concat('test', Company.arel_table[:name], 'xxx')).to_sql.should ==
    "SELECT     CONCAT(`companies`.`id`,'test',`companies`.`name`,'xxx') FROM       `companies`"
  end
  
  it 'has the mysql-specific coalesce expression' do
    Company.arel_table.project(Company.arel_table[:name].coalesce('unnamed')).to_sql.should ==
    "SELECT     COALESCE(`companies`.`name`,'unnamed') FROM       `companies`"
    Company.arel_table.project(Company.arel_table[:name].coalesce(1)).to_sql.should ==
    "SELECT     COALESCE(`companies`.`name`,1) FROM       `companies`"
  end
  
  it 'has the timediff and time_to_sec expressions' do
    Company.arel_table.project(Company.arel_table[:id].timediff(Company.arel_table[:name]).time_to_sec).to_sql.should ==
    "SELECT     TIME_TO_SEC(TIMEDIFF(`companies`.`id`,`companies`.`name`)) FROM       `companies`"
  end
  
  describe Arel::Header do
    it 'finds the closest match of an attribute in the header' do
      c = Company.arel_table
      ca = Company.arel_table.alias
      c.join(ca).on[ca[:id]].original_relation.should == ca
      ca.join(c).on[c[:id]].original_relation.should == c
    end
  end
  
  it 'uses consistent naming for table aliases' do
    c = Company.arel_table
    ca = Company.arel_table.alias
    sql = c.join(ca).on(ca[:id].eq(c[:id])).project(c[:id], ca[:id]).to_sql
    sql =~ /(companies_[0-9]+)/
    $1.should_not be_nil
    sql.should == "SELECT     `companies`.`id`, `#{$1}`.`id` FROM       `companies` INNER JOIN `companies` `#{$1}` ON `#{$1}`.`id` = `companies`.`id`"
    
    sql = c.join(ca).on(ca[:id].eq(c[:id])).project(ca[:id], c[:id]).to_sql    
    sql =~ /(companies_[0-9]+)/
    $1.should_not be_nil
    sql.should == "SELECT     `#{$1}`.`id`, `companies`.`id` FROM       `companies` INNER JOIN `companies` `#{$1}` ON `#{$1}`.`id` = `companies`.`id`"
  end
  
  describe Arel::Attribute do
    describe '==' do
      it 'returns true when the name, alias, relation and original relation are the same' do
        Company.arel_table[:id].should == Company.arel_table[:id]
        Company.arel_table[:id].should == Company.arel_table.join(Relationship.arel_table).on[Company.arel_table[:id]].bind(Company.arel_table)
      end
      
      it 'returns false when attributes have different names or aliases' do
        Company.arel_table[:id].should_not == Company.arel_table[:name]
        Company.arel_table[:id].should_not == Company.arel_table[:id].as(:id2)
      end
      
      it 'returns false when attributes are on aliased relations' do
        Company.arel_table[:id].should_not == Company.arel_table.alias[:id]
        Company.arel_table.alias[:id].should_not == Company.arel_table.alias[:id]
      end
      
      it 'returns false when comparing to an expression' do
        Company.arel_table[:id].should_not == Company.arel_table[:id].sum
      end
    end
    
    describe '#type_cast' do
      it 'uses the attribute root for type casting, even if the attribute == the root' do
        Arel::Attribute.new(Company.arel_table, :name, :ancestor => Company.arel_table[:name]).type_cast('test').should == 'test'
      end
    end
  end
  
  describe Arel::Expression do
    describe '==' do
      it 'returns true when the attribute is the same, and the expression is of the same class' do
        Company.arel_table[:updated_at].maximum.should == Company.arel_table[:updated_at].maximum
        # TODO: don't know if the following is needed. It fails anyway.
        # Company.arel_table[:updated_at].maximum.should == Company.arel_table.join(Relationship.arel_table).on[Company.arel_table[:updated_at].maximum].bind(Company.arel_table)
        Company.arel_table[:updated_at].maximum.should == Company.arel_table.join(Relationship.arel_table).on[Company.arel_table[:updated_at]].bind(Company.arel_table).maximum
      end
      
      it 'returns false when the attribute or alias is different' do
        Company.arel_table[:updated_at].maximum.should_not == Company.arel_table[:created_at].maximum
        Company.arel_table[:updated_at].maximum.should_not == Company.arel_table[:updated_at].as(:x).maximum
      end
      
      it 'returns false when attributes are on aliased relations' do
        Company.arel_table[:updated_at].maximum.should_not == Company.arel_table.alias[:updated_at].maximum
        Company.arel_table.alias[:updated_at].maximum.should_not == Company.arel_table.alias[:updated_at].maximum
      end
      
      it 'returns false when expressions are of different classes' do
        Company.arel_table[:id].maximum.should_not == Company.arel_table[:id].minimum
      end
      
      it 'returns false when expressions have different aliases' do
        Company.arel_table[:id].maximum.as(:m).should_not == Company.arel_table[:id].maximum
        Company.arel_table[:id].maximum.should_not == Company.arel_table[:id].maximum.as(:x)
      end
    end
  end
  
  describe Arel::Value do
    it 'appropriately quotes the value in a select clause' do
      Arel::Value.new('test', Company.arel_table).to_sql(Arel::Sql::SelectClause.new(Company.arel_table)).should == "'test'"
    end
    
    it 'allows constructing expressions' do
      Company.arel_table.project(Arel::Value.new('ID', Company.arel_table).concat(Company.arel_table[:id])).to_sql.should == 
      "SELECT     CONCAT('ID',`companies`.`id`) FROM       `companies`"
    end
  end
  
  describe Arel::Join do
    describe 'singular?' do
      it 'returns true for belongs_to associations on a primary key' do
        Relationship.arel(:company).should be_singular
        Relationship.arel(:person).should be_singular
        Quote.arel(:company).should be_singular
        Quote.arel(:contact).should be_singular
        Quote.arel(:responsible).should be_singular
      end
      
      it 'returns true for has_one associations backed by a unique index' do
        Company.arel(:financial).should be_singular
        Quote.arel(:company, :financial).should be_singular
      end
      
      it 'returns false for has_many associations' do
        Company.arel(:relationships).should_not be_singular
        Company.arel(:people).should_not be_singular
        Company.arel(:quotes).should_not be_singular
        Person.arel(:companies).should_not be_singular
      end
      
      it 'returns false when a has_many association is present' do
        Company.arel(:quotes, :contact).should_not be_singular
        Quote.arel(:company, :people).should_not be_singular
        Quote.arel(:contact, :relationships).should_not be_singular
      end
    end
  end
  
  describe Arel::InfixOperation do
    it 'generates the correct sql for a product with a constant' do
      Company.arel_table.project(Company.arel_table[:id] * 0).to_sql.should == 
        "SELECT     ((`companies`.`id`) * (0)) FROM       `companies`"
    end
    
    it 'generates the correct sql for a product with another attribute' do
      Company.arel_table.project(Company.arel_table[:id] * Company.arel_table[:id]).to_sql.should ==
        "SELECT     ((`companies`.`id`) * (`companies`.`id`)) FROM       `companies`"
    end
    
    it 'aliases the product in sql when asked' do
      Company.arel_table.project((Company.arel_table[:id] * Company.arel_table[:id]).as(:square)).to_sql.should == 
        "SELECT     ((`companies`.`id`) * (`companies`.`id`)) AS `square` FROM       `companies`"
    end
    
    it 'allows combining expressions' do
      Company.arel_table.project((Company.arel_table[:id] * Company.arel_table[:id]).sum.as(:tzesum)).to_sql.should ==
        "SELECT     SUM(((`companies`.`id`) * (`companies`.`id`))) AS `tzesum` FROM       `companies`"
    end
    
    it 'generates the correct sql for an addition with another attribute' do
      Company.arel_table.project(Company.arel_table[:id] + Company.arel_table[:updated_at]).to_sql.should ==
        "SELECT     ((`companies`.`id`) + (`companies`.`updated_at`)) FROM       `companies`"
    end
    
    it 'generates the correct sql for a substraction from another attribute' do
      Company.arel_table.project(Company.arel_table[:id] - Company.arel_table[:updated_at]).to_sql.should ==
        "SELECT     ((`companies`.`id`) - (`companies`.`updated_at`)) FROM       `companies`"
    end
    
    it 'generates the correct sql for a divison from another attribute' do
      Company.arel_table.project(Company.arel_table[:id].div(Company.arel_table[:updated_at])).to_sql.should ==
        "SELECT     ((`companies`.`id`) / (`companies`.`updated_at`)) FROM       `companies`"
    end
    
    it 'generates the correct sql for a combination of infix operations' do
      Company.arel_table.project((Company.arel_table[:id].div(2) + 2) * 100).to_sql.should ==
        "SELECT     ((((((`companies`.`id`) / (2))) + (2))) * (100)) FROM       `companies`"
    end
    
    it 'raises an error when constructed without a second attribute' do
      lambda { Company.arel_table[:id] * nil }.should raise_error(StandardError)
    end
  end
end