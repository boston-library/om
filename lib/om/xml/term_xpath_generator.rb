module OM::XML::TermXpathGenerator
  
  # Generate relative xpath for a term
  # @param [OM::XML::Term] term that you want to generate relative xpath for
  #
  # In most cases, the resulting xpath will be the Term's path with the appropriate namespace appended to it.
  # If the Term specifies any attributes, 
  # Special Case: attribute Terms
  # If the Term's path is set to {:attribute=>attr_name}, the resulting xpath will points to a node attribute named attr_name 
  # ie. a path fo {:attribute=>"lang"} will result in a relative xpath of "@lang"
  # Special Case: xpath functions
  # If the Term's path variable is text(), it will be treated as an xpath function (no namespace) and turned into "text()[normalize-space(.)]"
  def self.generate_relative_xpath(term)
    template = ""
    predicates = []
    
    if term.namespace_prefix.nil?
      complete_prefix = ""
    else
      complete_prefix = term.namespace_prefix + ":"
    end
    
    if term.path.kind_of?(Hash)
      if term.path.has_key?(:attribute)
        base_path = "@"+term.path[:attribute]
      else
        raise "#{term.path} is an invalid path for an OM::XML::Term.  You should provide either a string or {:attributes=>XXX}"
      end
    else
      if term.path == "text()"
        base_path = "#{term.path}[normalize-space(.)]"
      else
        unless term.namespace_prefix.nil?
          template << complete_prefix
        end
        base_path = term.path
      end
    end
    template << base_path
    
    unless term.attributes.nil?
      term.attributes.each_pair do |attr_name, attr_value|
        if attr_value == :none
          predicates << "not(@#{attr_name})"
        else
          predicates << "@#{attr_name}=\"#{attr_value}\""
        end
      end
    end
    
    unless predicates.empty? 
      template << "["+ delimited_list(predicates, " and ")+"]"
    end
    
    return template
  end
  
  # Generate absolute xpath for a Term
  # @param [OM::XML::Term] term that you want to generate absolute xpath for
  #
  # Absolute xpaths always begin with "//".  They are generated by relying on the Term's relative xpath and the absolute xpath of its parent node.
  def self.generate_absolute_xpath(term)
    relative = generate_relative_xpath(term)
    if term.parent.nil?
      return "//#{relative}"
    else
      return term.parent.xpath_absolute + "/" + relative
    end
  end
  
  def self.generate_constrained_xpath(term)
    if term.namespace_prefix.nil?
      complete_prefix = ""
    else
      complete_prefix = term.namespace_prefix + ":"
    end
    
    absolute = generate_absolute_xpath(term)
    constraint_predicates = []
    
    arguments_for_contains_function = []

    if !term.default_content_path.nil?
      arguments_for_contains_function << "#{complete_prefix}#{term.default_content_path}"
    end
      
    # If no subelements have been specified to search within, set contains function to search within the current node
    if arguments_for_contains_function.empty?
      arguments_for_contains_function << "."
    end
    
    arguments_for_contains_function << "\":::constraint_value:::\""
  
    contains_function = "contains(#{delimited_list(arguments_for_contains_function)})"

    template = add_predicate(absolute, contains_function)
    return template.gsub( /:::(.*?):::/ ) { '#{'+$1+'}' }.gsub('"', '\"')
  end
  
  # Generate an xpath of the chosen +type+ for the given Term.
  # @param [OM::XML::Term] term that you want to generate relative xpath for
  # @param [Symbol] the type of xpath to generate, :relative, :abolute, or :constrained
  def self.generate_xpath(term, type)
    case type
    when :relative
      self.generate_relative_xpath(term)
    when :absolute
      self.generate_absolute_xpath(term)
    when :constrained
      self.generate_constrained_xpath(term)
    end
  end
  
  # Use the given +terminology+ to generate an xpath with (optional) node indexes for each of the term pointers.
  # Ex.  OM::XML::TermXpathGenerator.xpath_with_indexes(my_terminology, {:conference=>0}, {:role=>1}, :text ) 
  #      will yield an xpath similar to this: '//oxns:name[@type="conference"][1]/oxns:role[2]/oxns:roleTerm[@type="text"]'
  # @param [OM::XML::Terminology] terminology to generate xpath based on
  # @param [String -- OM term pointer] pointers identifying the node to generate xpath for
  def self.generate_xpath_with_indexes(terminology, *pointers)
    if pointers.first.nil?
      root_term = terminology.root_terms.first
      if root_term.nil?
        return "/"
      else
        return root_term.xpath
      end
    end
    
    query_constraints = nil
    
    if pointers.length > 1 && pointers.last.kind_of?(Hash)
      constraints = pointers.pop
      unless constraints.empty?
        query_constraints = constraints
      end 
    end

    if pointers.length == 1 && pointers.first.instance_of?(String)
      return xpath_query = pointers.first
    end
      
    # if pointers.first.kind_of?(String)
    #   return pointers.first
    # end
    
    keys = []
    xpath = "//"

    pointers = OM.destringify(pointers)
    pointers.each_with_index do |pointer, pointer_index|
      
      if pointer.kind_of?(Hash)
        k = pointer.keys.first
        index = pointer[k]
      else
        k = pointer
        index = nil
      end
      
      keys << k
      
      term = terminology.retrieve_term(*keys)  
      # Return nil if there is no term to work with
      if term.nil? then return nil end
      
      # If we've encountered a NamedTermProxy, insert path sections corresponding to 
      # terms corresponding to each entry in its proxy_pointer rather than just the final term that it points to.
      if term.kind_of? OM::XML::NamedTermProxy
        current_location = term.parent.nil? ? term.terminology : term.parent
        relative_path = ""
        term.proxy_pointer.each_with_index do |proxy_pointer, proxy_pointer_index|
          proxy_term = current_location.retrieve_term(proxy_pointer)
          proxy_relative_path = proxy_term.xpath_relative
          if proxy_pointer_index > 0
            proxy_relative_path = "/"+proxy_relative_path
          end
          relative_path << proxy_relative_path
          current_location = proxy_term
        end
      else  
        relative_path = term.xpath_relative
      
        unless index.nil?
          relative_path = add_node_index_predicate(relative_path, index)
        end
      end
      
      if pointer_index > 0
        relative_path = "/"+relative_path
      end
      xpath << relative_path 
    end
      
    final_term = terminology.retrieve_term(*keys) 
    
    if query_constraints.kind_of?(Hash)
      contains_functions = []
      query_constraints.each_pair do |k,v|
        if k.instance_of?(Symbol)
          constraint_path = final_term.children[k].xpath_relative
        else
          constraint_path = k
        end
        contains_functions << "contains(#{constraint_path}, \"#{v}\")"
      end
      
      xpath = add_predicate(xpath, delimited_list(contains_functions, " and ") )
    end
    
    return xpath
  end
  
  # Turns an Array into a String containing values separated by a delimiter.  Defaults to comma as a delimiter.
  # @param [Array] values_array to convert
  # @param [String] delimiter.  Default: ", "
  def self.delimited_list( values_array, delimiter=", ")
    result = values_array.collect{|a| a + delimiter}.to_s.chomp(delimiter)
  end
  
  # Adds xpath xpath node index predicate to the end of your xpath query
  # Example: 
  # add_node_index_predicate("//oxns:titleInfo",0)
  #   => "//oxns:titleInfo[1]"
  #
  # add_node_index_predicate("//oxns:titleInfo[@lang=\"finnish\"]",0)
  #   => "//oxns:titleInfo[@lang=\"finnish\"][1]"
  def self.add_node_index_predicate(xpath_query, array_index_value)
    modified_query = xpath_query.dup
    modified_query << "[#{array_index_value + 1}]"
  end
  
  # Adds xpath:position() method call to the end of your xpath query
  # Examples: 
  #
  # add_position_predicate("//oxns:titleInfo",0)
  # => "//oxns:titleInfo[position()=1]"
  #
  # add_position_predicate("//oxns:titleInfo[@lang=\"finnish\"]",0)
  # => "//oxns:titleInfo[@lang=\"finnish\" and position()=1]"
  def self.add_position_predicate(xpath_query, array_index_value)
    position_function = "position()=#{array_index_value + 1}"
    self.add_predicate(xpath_query, position_function)
  end
  
  def self.add_predicate(xpath_query, predicate)
    modified_query = xpath_query.dup
    # if xpath_query.include?("]")
    if xpath_query[xpath_query.length-1..xpath_query.length] == "]"
      modified_query.insert(xpath_query.rindex("]"), " and #{predicate}")
    else
      modified_query << "[#{predicate}]"
    end
    return modified_query
  end

end
