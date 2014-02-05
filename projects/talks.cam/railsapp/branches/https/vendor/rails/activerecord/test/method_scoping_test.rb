require 'abstract_unit'
require 'fixtures/developer'
require 'fixtures/project'
require 'fixtures/comment'
require 'fixtures/post'
require 'fixtures/category'

class MethodScopingTest < Test::Unit::TestCase
  fixtures :developers, :projects, :comments, :posts
  
  def test_set_conditions
    Developer.with_scope(:find => { :conditions => 'just a test...' }) do
      assert_equal 'just a test...', Developer.send(:current_scoped_methods)[:find][:conditions]
    end
  end

  def test_scoped_find
    Developer.with_scope(:find => { :conditions => "name = 'David'" }) do
      assert_nothing_raised { Developer.find(1) }
    end
  end
  
  def test_scoped_find_first
    Developer.with_scope(:find => { :conditions => "salary = 100000" }) do
      assert_equal Developer.find(10), Developer.find(:first, :order => 'name')
    end
  end
  
  def test_scoped_find_combines_conditions
    Developer.with_scope(:find => { :conditions => "salary = 9000" }) do
      assert_equal developers(:poor_jamis), Developer.find(:first, :conditions => "name = 'Jamis'")
    end
  end
  
  def test_scoped_find_sanitizes_conditions
    Developer.with_scope(:find => { :conditions => ['salary = ?', 9000] }) do
      assert_equal developers(:poor_jamis), Developer.find(:first)
    end  
  end
  
  def test_scoped_find_combines_and_sanitizes_conditions
    Developer.with_scope(:find => { :conditions => ['salary = ?', 9000] }) do
      assert_equal developers(:poor_jamis), Developer.find(:first, :conditions => ['name = ?', 'Jamis'])
    end  
  end
  
  def test_scoped_find_all
    Developer.with_scope(:find => { :conditions => "name = 'David'" }) do
      assert_equal [developers(:david)], Developer.find(:all)
    end      
  end
  
  def test_scoped_count
    Developer.with_scope(:find => { :conditions => "name = 'David'" }) do
      assert_equal 1, Developer.count
    end        

    Developer.with_scope(:find => { :conditions => 'salary = 100000' }) do
      assert_equal 8, Developer.count
      assert_equal 1, Developer.count(:conditions => "name LIKE 'fixture_1%'")
    end        
  end

  def test_scoped_find_include
    # with the include, will retrieve only developers for the given project
    scoped_developers = Developer.with_scope(:find => { :include => :projects }) do
      Developer.find(:all, :conditions => 'projects.id = 2')
    end
    assert scoped_developers.include?(developers(:david))
    assert !scoped_developers.include?(developers(:jamis))
    assert_equal 1, scoped_developers.size
  end
  
  def test_scoped_count_include
    # with the include, will retrieve only developers for the given project
    Developer.with_scope(:find => { :include => :projects }) do
      assert_equal 1, Developer.count(:conditions => 'projects.id = 2')
    end
  end

  def test_scoped_create
    new_comment = nil

    VerySpecialComment.with_scope(:create => { :post_id => 1 }) do
      assert_equal({ :post_id => 1 }, VerySpecialComment.send(:current_scoped_methods)[:create])
      new_comment = VerySpecialComment.create :body => "Wonderful world"
    end

    assert Post.find(1).comments.include?(new_comment)
  end

  def test_immutable_scope
    options = { :conditions => "name = 'David'" }
    Developer.with_scope(:find => options) do
      assert_equal %w(David), Developer.find(:all).map { |d| d.name }
      options[:conditions] = "name != 'David'"
      assert_equal %w(David), Developer.find(:all).map { |d| d.name }
    end

    scope = { :find => { :conditions => "name = 'David'" }}
    Developer.with_scope(scope) do
      assert_equal %w(David), Developer.find(:all).map { |d| d.name }
      scope[:find][:conditions] = "name != 'David'"
      assert_equal %w(David), Developer.find(:all).map { |d| d.name }
    end
  end

  def test_scoped_with_duck_typing
    scoping = Struct.new(:method_scoping).new(:find => { :conditions => ["name = ?", 'David'] })
    Developer.with_scope(scoping) do
       assert_equal %w(David), Developer.find(:all).map { |d| d.name }
    end
  end

  def test_ensure_that_method_scoping_is_correctly_restored
    scoped_methods = Developer.instance_eval('current_scoped_methods')

    begin
      Developer.with_scope(:find => { :conditions => "name = 'Jamis'" }) do
        raise "an exception"
      end
    rescue
    end
    assert_equal scoped_methods, Developer.instance_eval('current_scoped_methods')
  end
end

class NestedScopingTest < Test::Unit::TestCase
  fixtures :developers, :projects, :comments, :posts

  def test_merge_options
    Developer.with_scope(:find => { :conditions => 'salary = 80000' }) do
      Developer.with_scope(:find => { :limit => 10 }) do
        merged_option = Developer.instance_eval('current_scoped_methods')[:find]
        assert_equal({ :conditions => 'salary = 80000', :limit => 10 }, merged_option)
      end
    end
  end

  def test_replace_options
    Developer.with_scope(:find => { :conditions => "name = 'David'" }) do
      Developer.with_exclusive_scope(:find => { :conditions => "name = 'Jamis'" }) do
        assert_equal({:find => { :conditions => "name = 'Jamis'" }}, Developer.instance_eval('current_scoped_methods'))
        assert_equal({:find => { :conditions => "name = 'Jamis'" }}, Developer.send(:scoped_methods)[-1])
      end
    end
  end

  def test_append_conditions
    Developer.with_scope(:find => { :conditions => "name = 'David'" }) do
      Developer.with_scope(:find => { :conditions => 'salary = 80000' }) do
        appended_condition = Developer.instance_eval('current_scoped_methods')[:find][:conditions]
        assert_equal("( name = 'David' ) AND ( salary = 80000 )", appended_condition)
        assert_equal(1, Developer.count)
      end
      Developer.with_scope(:find => { :conditions => "name = 'Maiha'" }) do
        assert_equal(0, Developer.count)
      end
    end
  end

  def test_merge_and_append_options
    Developer.with_scope(:find => { :conditions => 'salary = 80000', :limit => 10 }) do
      Developer.with_scope(:find => { :conditions => "name = 'David'" }) do
        merged_option = Developer.instance_eval('current_scoped_methods')[:find]
        assert_equal({ :conditions => "( salary = 80000 ) AND ( name = 'David' )", :limit => 10 }, merged_option)
      end
    end
  end

  def test_nested_scoped_find
    Developer.with_scope(:find => { :conditions => "name = 'Jamis'" }) do
      Developer.with_exclusive_scope(:find => { :conditions => "name = 'David'" }) do
        assert_nothing_raised { Developer.find(1) }
        assert_equal('David', Developer.find(:first).name)
      end
      assert_equal('Jamis', Developer.find(:first).name)
    end
  end

  def test_nested_scoped_find_include
    Developer.with_scope(:find => { :include => :projects }) do
      Developer.with_scope(:find => { :conditions => "projects.id = 2" }) do
        assert_nothing_raised { Developer.find(1) }
        assert_equal('David', Developer.find(:first).name)
      end
    end  
  end

  def test_nested_scoped_find_merged_include
    # :include's remain unique and don't "double up" when merging
    Developer.with_scope(:find => { :include => :projects, :conditions => "projects.id = 2" }) do
      Developer.with_scope(:find => { :include => :projects }) do
        assert_equal 1, Developer.instance_eval('current_scoped_methods')[:find][:include].length
        assert_equal('David', Developer.find(:first).name)
      end
    end  
    
    # the nested scope doesn't remove the first :include
    Developer.with_scope(:find => { :include => :projects, :conditions => "projects.id = 2" }) do
      Developer.with_scope(:find => { :include => [] }) do
        assert_equal 1, Developer.instance_eval('current_scoped_methods')[:find][:include].length
        assert_equal('David', Developer.find(:first).name)
      end
    end  
    
    # mixing array and symbol include's will merge correctly
    Developer.with_scope(:find => { :include => [:projects], :conditions => "projects.id = 2" }) do
      Developer.with_scope(:find => { :include => :projects }) do
        assert_equal 1, Developer.instance_eval('current_scoped_methods')[:find][:include].length
        assert_equal('David', Developer.find(:first).name)
      end
    end  
  end
  
  def test_nested_scoped_find_replace_include
    Developer.with_scope(:find => { :include => :projects }) do
      Developer.with_exclusive_scope(:find => { :include => [] }) do
        assert_equal 0, Developer.instance_eval('current_scoped_methods')[:find][:include].length
      end
    end  
  end

  def test_three_level_nested_exclusive_scoped_find
    Developer.with_scope(:find => { :conditions => "name = 'Jamis'" }) do
      assert_equal('Jamis', Developer.find(:first).name)

      Developer.with_exclusive_scope(:find => { :conditions => "name = 'David'" }) do
        assert_equal('David', Developer.find(:first).name)

        Developer.with_exclusive_scope(:find => { :conditions => "name = 'Maiha'" }) do
          assert_equal(nil, Developer.find(:first))
        end

        # ensure that scoping is restored
        assert_equal('David', Developer.find(:first).name)
      end

      # ensure that scoping is restored
      assert_equal('Jamis', Developer.find(:first).name)
    end
  end

  def test_merged_scoped_find
    poor_jamis = developers(:poor_jamis)
    Developer.with_scope(:find => { :conditions => "salary < 100000" }) do
      Developer.with_scope(:find => { :offset => 1 }) do
        assert_equal(poor_jamis, Developer.find(:first, :order => 'id asc'))
      end
    end
  end

  def test_merged_scoped_find_sanitizes_conditions
    Developer.with_scope(:find => { :conditions => ["name = ?", 'David'] }) do
      Developer.with_scope(:find => { :conditions => ['salary = ?', 9000] }) do
        assert_raise(ActiveRecord::RecordNotFound) { developers(:poor_jamis) }
      end
    end
  end

  def test_nested_scoped_find_combines_and_sanitizes_conditions
    Developer.with_scope(:find => { :conditions => ["name = ?", 'David'] }) do
      Developer.with_exclusive_scope(:find => { :conditions => ['salary = ?', 9000] }) do
        assert_equal developers(:poor_jamis), Developer.find(:first)
        assert_equal developers(:poor_jamis), Developer.find(:first, :conditions => ['name = ?', 'Jamis'])
      end
    end
  end

  def test_merged_scoped_find_combines_and_sanitizes_conditions
    Developer.with_scope(:find => { :conditions => ["name = ?", 'David'] }) do
      Developer.with_scope(:find => { :conditions => ['salary > ?', 9000] }) do
        assert_equal %w(David), Developer.find(:all).map { |d| d.name }
      end
    end
  end

  def test_immutable_nested_scope
    options1 = { :conditions => "name = 'Jamis'" }
    options2 = { :conditions => "name = 'David'" }
    Developer.with_scope(:find => options1) do
      Developer.with_exclusive_scope(:find => options2) do
        assert_equal %w(David), Developer.find(:all).map { |d| d.name }
        options1[:conditions] = options2[:conditions] = nil
        assert_equal %w(David), Developer.find(:all).map { |d| d.name }
      end
    end
  end

  def test_immutable_merged_scope
    options1 = { :conditions => "name = 'Jamis'" }
    options2 = { :conditions => "salary > 10000" }
    Developer.with_scope(:find => options1) do
      Developer.with_scope(:find => options2) do
        assert_equal %w(Jamis), Developer.find(:all).map { |d| d.name }
        options1[:conditions] = options2[:conditions] = nil
        assert_equal %w(Jamis), Developer.find(:all).map { |d| d.name }
      end
    end
  end

  def test_ensure_that_method_scoping_is_correctly_restored
    Developer.with_scope(:find => { :conditions => "name = 'David'" }) do
      scoped_methods = Developer.instance_eval('current_scoped_methods')
      begin
        Developer.with_scope(:find => { :conditions => "name = 'Maiha'" }) do
          raise "an exception"
        end
      rescue
      end
      assert_equal scoped_methods, Developer.instance_eval('current_scoped_methods')
    end
  end
end

class HasManyScopingTest< Test::Unit::TestCase
  fixtures :comments, :posts
  
  def setup
    @welcome = Post.find(1)
  end
  
  def test_forwarding_of_static_methods
    assert_equal 'a comment...', Comment.what_are_you
    assert_equal 'a comment...', @welcome.comments.what_are_you
  end

  def test_forwarding_to_scoped
    assert_equal 4, Comment.search_by_type('Comment').size
    assert_equal 2, @welcome.comments.search_by_type('Comment').size
  end
  
  def test_forwarding_to_dynamic_finders
    assert_equal 4, Comment.find_all_by_type('Comment').size
    assert_equal 2, @welcome.comments.find_all_by_type('Comment').size
  end

  def test_nested_scope
    Comment.with_scope(:find => { :conditions => '1=1' }) do
      assert_equal 'a comment...', @welcome.comments.what_are_you
    end
  end
end


class HasAndBelongsToManyScopingTest< Test::Unit::TestCase
  fixtures :posts, :categories, :categories_posts

  def setup
    @welcome = Post.find(1)
  end

  def test_forwarding_of_static_methods
    assert_equal 'a category...', Category.what_are_you
    assert_equal 'a category...', @welcome.categories.what_are_you
  end

  def test_forwarding_to_dynamic_finders
    assert_equal 4, Category.find_all_by_type('SpecialCategory').size
    assert_equal 0, @welcome.categories.find_all_by_type('SpecialCategory').size
    assert_equal 2, @welcome.categories.find_all_by_type('Category').size
  end

  def test_nested_scope
    Category.with_scope(:find => { :conditions => '1=1' }) do
      assert_equal 'a comment...', @welcome.comments.what_are_you
    end
  end
end


=begin
# We disabled the scoping for has_one and belongs_to as we can't think of a proper use case


class BelongsToScopingTest< Test::Unit::TestCase
  fixtures :comments, :posts

  def setup
    @greetings = Comment.find(1)
  end

  def test_forwarding_of_static_method
    assert_equal 'a post...', Post.what_are_you
    assert_equal 'a post...', @greetings.post.what_are_you
  end

  def test_forwarding_to_dynamic_finders
    assert_equal 4, Post.find_all_by_type('Post').size
    assert_equal 1, @greetings.post.find_all_by_type('Post').size
  end

end


class HasOneScopingTest< Test::Unit::TestCase
  fixtures :comments, :posts

  def setup
    @sti_comments = Post.find(4)
  end

  def test_forwarding_of_static_methods
    assert_equal 'a comment...', Comment.what_are_you
    assert_equal 'a very special comment...', @sti_comments.very_special_comment.what_are_you
  end

  def test_forwarding_to_dynamic_finders
    assert_equal 1, Comment.find_all_by_type('VerySpecialComment').size
    assert_equal 1, @sti_comments.very_special_comment.find_all_by_type('VerySpecialComment').size
    assert_equal 0, @sti_comments.very_special_comment.find_all_by_type('Comment').size
  end

end

=end
