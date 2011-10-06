ActiveRecord::Base.establish_connection(
  :adapter => 'mysql',
  :username => 'root',
  :encoding => 'utf8',
  :database => 'reportkit_integration'
)

ActiveRecord::Schema.define do
  create_table :companies, :force => true do |t|
    t.string :name
    t.string :alpha
    t.decimal :turnover
    t.timestamps
  end
  add_index :companies, [:name, :alpha]
  create_table :financials, :force => true do |t|
    t.belongs_to :financiable, :polymorphic => true #, :null => false # TODO: this should be required by singular? spec
    t.string :vat_no
  end
  add_index :financials, [:financiable_type, :financiable_id], :unique => true
  create_table :relationships, :force => true do |t|
    t.belongs_to :company, :person
    t.string :function
    t.timestamps
  end
  add_index :relationships, :company_id
  create_table :people, :force => true do |t|
    t.string :first_name, :last_name
    t.timestamps
  end
  create_table :quotes, :force => true do |t|
    t.belongs_to :company
    t.belongs_to :contact
    t.belongs_to :responsible
    t.string :description
    t.timestamp :deleted_at
  end
end

class Person < ActiveRecord::Base
  has_many :relationships
  has_many :companies, :through => :relationships
end

class Relationship < ActiveRecord::Base
  belongs_to :company
  belongs_to :person
end

class Financial < ActiveRecord::Base
  belongs_to :financiable, :polymorphic => true
end

class Quote < ActiveRecord::Base
  belongs_to :company
  belongs_to :contact, :class_name => "Person"
  belongs_to :responsible, :class_name => "Person"
end

class Company < ActiveRecord::Base
  has_many :relationships
  has_many :people, :through => :relationships
  has_many :quotes
  has_one :financial, :as => :financiable
  
  define_columns do
    column :turnover, :money
    column :people_count, :decimal, arel(:people)[Person.arel_table[:id]].count.as(:people_count)
    column :people_sum, :decimal, arel(:people)[Person.arel_table[:id]].sum # stupid, but needed for testing
    column :quote_count, :decimal, arel(:quotes)[Quote.arel_table[:id]].count.as(:quote_count)
  end
  
  define_columns do
    r2 = Relationship.arel.alias
    column :related_count, :decimal, arel(:relationships).outer_join(r2).on(
      Relationship.arel[:person_id].eq(r2[:person_id])
    )[r2[:company_id]].count(true).as(:related_count)
  end
end
