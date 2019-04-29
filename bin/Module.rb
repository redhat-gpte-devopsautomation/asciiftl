#!/usr/bin/env ruby
#
# ::CModule for parsing GPTE instruction modules
# Course::CModule::Topic::Slide
# Course::CModule::Topic::Lab
# Course::CModule::Topic::Assessment

# Courses:
#   CModules:
#     Topics:
#       Slides
#     Labs:
#       Topics

require 'git'
require 'octokit'
require 'asciidoctor'

class GitHubOrg
  def initialize(org='redhat-gpe',repo_base='/tmp/course_repos')
    @org       = org
    @client    = Octokit::Client.new(:login => ENV["git_username"], :password => ENV["git_password"])
    @repo_base = repo_base
    @repos     = Hash.new
    @courses   = Array.new(0)
    puts "org: #{org}: #{repo_base}"
    ocp_courses
    load_courses
  end

  # returns list of courses
  def courses
    courses = @client.org_repos('redhat-gpe', {:type => 'all', :sort => 'pushed'})
    courses.each { |c| puts c.name }
  end

  def ocp_courses
    c_repos = @client.org_repos('redhat-gpe', {:type => 'all', :sort => 'pushed'})
    c_repos.each do |c|
      if c.name.start_with?('ocp')
        @repos[c.name] = c.html_url
        puts c.name
        puts @repos[c.name]
      end
    end
    puts @repos
  end

  def clone_repo(repo_name)
    puts "clone repo: #{repo_name})"
    g = Git.clone(repo_name, :path => @repo_base + repo_name)
    return @repo_base + '/' + name
  end

  def refresh_repo(repo_name)
    repo_base_name = "#{@repo_base}/#{repo_name}"
    #puts "refresh #{@repos[repo_name]} basename: #{repo_base_name}"
    g = Git.clone(@repos[repo_name], repo_base_name)
    # if g failed, then clone
    return repo_base_name
  end

  def load_courses
    @repos.each_key do |r_name|
      puts "rname #{r_name}"
      # refresh the repo
      r_path = refresh_repo(r_name)
      puts "repo path: #{r_path}"
      # load the course
      @courses << Course.new(r_name,r_path)
    end
  end
end

class Course
  def initialize(name, path)
    @name    = name
    @path    = path
    @modules = Array.new
    load
  end

  def load
    # read URL or path to get all CModule names
    # load by URL

    # load by path
    modules_path = @path + "/modules/"
    # it should have a modules directory
    if FileTest.directory?(modules_path)
      # /*/ == find depth 1
      # load all modules
      Dir[modules_path+"/*/"].each { |p| @modules << CModule.new("",p) }
      @course_title = @modules[0].course_title
    else
      raise "no dir #{modules_path}"
    end
  end

  def title
    @course_title
  end

  def modules
    @modules
  end
end

class CModule
  def initialize(name, path)
    @name = name
    @path  = path
    @labs = Array.new
    @slides = Array.new
    @topics = Hash.new(0)
    @topics_slides = Hash.new {|h,k| h[k] = Array.new }
    @course_title  = String.new
    @module_title  = String.new
    load
    parse_titles
    parse_slides
    parse_labs
    parse_topics
    return @course_title
  end

  def topics
    @topics
  end

  def slides_by_topic
    @topics_slides.each
  end

  def title
    @module_title
  end

  def course_title
    @course_title
  end

  def slides
    @slides.each
  end

  def labs
    @labs
  end

  def load
    #puts "reads in all slides and labs by path or URL of the module/NN"
    # just files for now
    # slides
    # use find to get the _Slides and *_Lab.adoc paths of module
    slides_path = @path + "/_Slides.adoc"
    if FileTest.readable?(slides_path)
      @slides_asciidoc = Asciidoctor.load_file slides_path, safe: :safe, parse: :false, :attributes => 'revealjs_slideshow'
    else
      raise "cant read #{slides_path}"
    end

    #labs
    # for each lab name, use the solutions, else use the lab
    lab_paths = Hash.new("0")
    path = @path + "/[0-9][0-9]*_Lab.adoc"
    Dir.glob(path).each do |l|
      # get names
      lab_name = File.basename(l)
      lab_name.delete_suffix! "_Solution_Lab.adoc" 
      lab_name.delete_suffix! "_Lab.adoc"
      # Hash[lab_name: :lab_path]
      lab_paths[lab_name] = l unless lab_paths[lab_name].match?('_Solution_Lab.adoc')
    end

    puts lab_paths

    # process labs asciidoc
    # lab sections are topics
    @labs_asciidoc = Array.new
    lab_paths.each do |lab_name,lab_path|
      @labs_asciidoc << Asciidoctor.load_file(lab_path, safe: :safe, parse: :false)
    end

  end

  def parse_titles
    title_block = @slides_asciidoc.find_by(context: :section, id: 'cover')[0].blocks
    @course_title = title_block[0].content
    @module_title = title_block[1].content

    #@slides_asciidoc.find_by(context: :section, id: 'cover') do |c|
    #  @course_title c.blocks[0].content
    #end
  end

  def parse_slides
    # create many slides objects from one long _Slides.adoc file
    # _Slides.adoc sections are topics
    @slides_asciidoc.find_by(context: :section).each do |sect|
      @slides << Slide.new(sect.id,sect)
    end
    #@slides.each{|t| puts t.topic}
  end

  def parse_labs
    # all labs asciidocs -> parse into labs objects
    @labs_asciidoc.each do |l|
      @labs << Lab.new(l.title, l)
    end
  end

  def parse_topics
    # a hash of topics and slide count
    @slides.each do |slide|
      @topics[slide.topic] += 1
      @topics_slides[slide.topic] << slide
      #puts @topics_slides[slide.topic].each { |p| puts "all slides for topic #{p.topic}" }
    end

  end

  def parse_topics_omitted
    @slides_asciidoc.find_by(context: :section).each do |sect|
      if sect.id == "_module_topics"
        module_topics = sect.content
        sect.find_by(context: :ulist).each do |list|
          list.items.each do |item|
            topics << %("#{item.text}", "#{module_name.slice(3..-1)}", "#{course_name}")
          end
        end
      end
    end
  end
end

class Slide
  def initialize(name,sect)
    @name = name
    @sect = sect
  end

  def topic
    return @sect.title
  end

  def content
    @sect.content
  end
end

class Lab
  def initialize(name,doc)
    @name = name
    @doc  = doc
    @topics = Array.new
    @doc.find_by(context: :section) do |s|
      puts s.title
      @topics << s.title
    end
  end

  def topics
    #puts @doc.find_by(context: :section)
    @topics
  end

  def prep_blocks
    puts "prep_block"
  end

  def grade_blocks
    puts "grade_block"
  end

  def solve_blocks
    puts "solve_block"
  end
end

#course1 = Course.new('ocp4_foundaitons','/Users/jmaltin/newgoliath/ocp4_foundations')
#puts "Course title: "+course1.title
#course1.modules.each do |p|
#  puts "Module title: "+ p.title
#  puts "Module Slides Count: #{p.slides.count}"
#  puts "Module Topics: #{p.slides_by_topic.count}"
#  puts "Module Slides Topics: #{p.topics}"
#  puts
#end

##module1 = Module.new('intro', '/Users/jmaltin/newgoliath/ocp4_foundations/modules/03_OpenShift_User_Experience/')
#puts module1.topics
#puts "Module Labs: #{module1.labs.count}"
#puts "Module Labs Topics: "
#module1.labs.each { |l| puts l.topics }
#puts module1.course_title
#puts module1.title
#
#lab1 = Lab.new('test', '/Users/jmaltin/newgoliath/ocp4_foundations/modules/03_OpenShift_User_Experience/03_01_Demonstrate_OpenShift_Resources_Lab.adoc')
#puts lab1.topics

github = GitHubOrg.new()
