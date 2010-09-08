require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')
require "om"

describe "OM::XML::Document" do
  
  before(:all) do
    #ModsHelpers.name_("Beethoven, Ludwig van", :date=>"1770-1827", :role=>"creator")
    class DocumentTest 

      include OM::XML::Document    
      
      # Could add support for multiple root declarations.  
      #  For now, assume that any modsCollections have already been broken up and fed in as individual mods documents
      # root :mods_collection, :path=>"modsCollection", 
      #           :attributes=>[],
      #           :subelements => :mods
      
      set_terminology do |t|
        t.root(:path=>"mods", :xmlns=>"http://www.loc.gov/mods/v3", :schema=>"http://www.loc.gov/standards/mods/v3/mods-3-2.xsd")

        t.title_info(:path=>"titleInfo") {
          t.main_title(:path=>"title", :label=>"title")
          t.language(:path=>{:attribute=>"lang"})
        }                 
        # This is a mods:name.  The underscore is purely to avoid namespace conflicts.
        t.name_ {
          # this is a namepart
          t.namePart(:index_as=>[:searchable, :displayable, :facetable, :sortable], :required=>:true, :type=>:string, :label=>"generic name")
          # affiliations are great
          t.affiliation
          t.displayForm
          t.role(:ref=>[:role])
          t.description
          t.date(:path=>"namePart", :attributes=>{:type=>"date"})
          t.family_name(:path=>"namePart", :attributes=>{:type=>"family"})
          t.given_name(:path=>"namePart", :attributes=>{:type=>"given"}, :label=>"first name")
          t.terms_of_address(:path=>"namePart", :attributes=>{:type=>"termsOfAddress"})
        }
        # lookup :person, :first_name        
        t.person(:ref=>:name, :attributes=>{:type=>"personal"})

        t.role {
          t.text(:path=>"roleTerm",:attributes=>{:type=>"text"})
          t.code(:path=>"roleTerm",:attributes=>{:type=>"code"})
        }
        t.journal(:path=>'relatedItem', :attributes=>{:type=>"host"}) {
          t.title_info
          t.origin_info(:path=>"originInfo")
          t.issn(:path=>"identifier", :attributes=>{:type=>"issn"})
          t.issue!
        }
        t.issue(:path=>"part") {
          t.volume(:path=>"detail", :attributes=>{:type=>"volume"}, :default_content_path=>"number")
          t.level(:path=>"detail", :attributes=>{:type=>"number"}, :default_content_path=>"number")
          t.start_page(:path=>"pages", :attributes=>{:type=>"start"})
          t.end_page(:path=>"pages", :attributes=>{:type=>"end"})
          # t.start_page(:path=>"extent", :attributes=>{:unit=>"pages"}, :default_content_path => "start")
          # t.end_page(:path=>"extent", :attributes=>{:unit=>"pages"}, :default_content_path => "end")
          t.publication_date(:path=>"date")
        }
      end
           
    end
        
  end
  
  before(:each) do
    @fixturemods = DocumentTest.from_xml( fixture( File.join("CBF_MODS", "ARS0025_016.xml") ) )
    article_xml = fixture( File.join("mods_articles", "hydrangea_article1.xml") )
    @mods_article = DocumentTest.from_xml(article_xml)
  end
  
  after(:all) do
    Object.send(:remove_const, :DocumentTest)
  end
  
  
  describe ".find_with_value"  do
    
    it "uses the generated xpath queries" do
      @fixturemods.ng_xml.expects(:xpath).with('//oxns:name[@type="personal"]', @fixturemods.ox_namespaces)
      @fixturemods.find_with_value(:person)
      
      @fixturemods.ng_xml.expects(:xpath).with('//oxns:name[@type="personal" and contains(oxns:namePart, "Beethoven, Ludwig van")]', @fixturemods.ox_namespaces)
      @fixturemods.find_with_value(:person, "Beethoven, Ludwig van")
      
      @fixturemods.ng_xml.expects(:xpath).with('//oxns:name[@type="personal" and contains(oxns:namePart[@type="date"], "2010")]', @fixturemods.ox_namespaces)
      @fixturemods.find_with_value(:person, :date=>"2010")
      
      @fixturemods.ng_xml.expects(:xpath).with('//oxns:name[@type="personal" and contains(oxns:role/oxns:roleTerm, "donor")]', @fixturemods.ox_namespaces)
      @fixturemods.find_with_value(:person, :role=>"donor")
      
      # 
      # This is the way we want to move towards... (currently implementing part of this in accessor_constrained_xpath)
      # @fixturemods.ng_xml.expects(:xpath).with('//oxns:relatedItem/oxns:identifier[@type=\'issn\'] and contains("123-ABC-44567")]', @fixturemods.ox_namespaces)
      # @fixturemods.lookup([:journal, :issn], "123-ABC-44567")
      
    end
  end
    
  describe ".find_by_term" do
    it "should use Nokogiri to retrieve a NodeSet corresponding to the combination of accessor keys and array/nodeset indexes" do
      @mods_article.find_by_term( :person ).length.should == 2
      
      @mods_article.find_by_term( {:person=>1} ).first.should == @mods_article.ng_xml.xpath('//oxns:name[@type="personal"][2]', "oxns"=>"http://www.loc.gov/mods/v3").first
      @mods_article.find_by_term( {:person=>1}, :first_name ).class.should == Nokogiri::XML::NodeSet
      @mods_article.find_by_term( {:person=>1}, :first_name ).first.text.should == "Siddartha"
    end
    
    it "should support accessors whose relative_xpath is a lookup array instead of an xpath string" do
      # pending "this only impacts scenarios where we want to display & edit"
      DocumentTest.terminology.retrieve_term(:title_info, :language).path.should == {:attribute=>"lang"}
      # @sample.retrieve( :title, 1 ).first.text.should == "Artikkelin otsikko Hydrangea artiklan 1"
      @mods_article.find_by_term( {:title_info=>1}, :language ).first.text.should == "finnish"
    end
    
    it "should support xpath queries as the pointer" do
      @mods_article.find_by_term('//oxns:name[@type="personal"][1]/oxns:namePart[1]').first.text.should == "FAMILY NAME"
    end
    
    it "should return nil if the xpath fails to generate" do
      @mods_article.find_by_term( {:foo=>20}, :bar ).should == nil
    end
  
  end
   
end