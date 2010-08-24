require 'rubygems'
require 'camping'
require 'fileutils'
require 'open-uri'
require 'syntax/convertors/html'
require 'RedCloth'
require 'rdiscount'

Camping.goes :Wiki
Wiki::WikiAccess = 'git://github.com/camping/camping.wiki.git'
Wiki::CreateArticleLink = 'http://github.com/camping/camping/wiki/_new?wiki[name]={article}'
Wiki::EditURL = 'http://github.com/camping/camping/wiki/{article}/_edit'
Wiki::BlogURL = 'http://campingrb.tumblr.com/'
Wiki::BlogAPI = "#{Wiki::BlogURL}api/read/json"
Wiki::BlogTitleRegexp = /"regular-title"\:\"([^"]*)\"/

def Wiki.create
  unless File.exists? 'camping.wiki'
    system 'git', 'clone', Wiki::WikiAccess
    FileUtils.touch 'camping.wiki/touchable'
  end
end

module Wiki::Controllers
  class Article < R '/([a-zA-Z0-9:#-]+)'
    def get article
      file = Dir["camping.wiki/#{article}.*"].first
      return render(:article_not_found, article.gsub(/-/, ' ')) unless file
      @article = file
      @title = article.gsub('-', ' ')
      @edit = EditURL.gsub('{article}', article)
      render :article
    end
  end
  
  class TumblrTheme < R '/_tumblr_theme'
    def get
      render :tumblr_theme
    end
  end
  
  class Index
    def get
      @title = "Camping, a Microframework"
      render :index
    end
  end
  
  class StaticFile < R '/([a-zA-Z0-9-]+\.[a-zA-Z0-9]+)'
    FileTypes = {
      'css'  => 'text/css; charset=utf-8',
      'png'  => 'image/png',
      'gif'  => 'image/gif',
      'jpeg' => 'image/jpeg',
      'jpg'  => 'image/jpeg',
      'eot'  => 'application/vnd.ms-fontobject',
      'woff' => 'application/x-woff',
      'ttf'  => 'font/ttf',
      'svg'  => 'image/svg+xml',
      'js'   => 'application/javascript; charset=utf-8'
    }
    
    def get filename
      if File.exists? "public/#{filename}"
        @headers['X-Sendfile'] = "public/#{filename}"
        @headers['Content-Type'] = FileTypes[File.extname(filename)[1..4]] || 'text/plain'
        @status = '200'
        return 'You need to enable X-Sendfile in your server.'
      else
        @status = 404
        "File not available"
      end
    end
  end
end

module Wiki::Helpers
  RefreshInterval = 60*60 # 1 Hour
  
  def update_wiki
    Dir.chdir 'camping.wiki' do
      system 'git', 'pull'
      FileUtils.touch 'touchable'
    end
  end
  
  def maybe_update_wiki
    update_wiki if File.mtime('camping.wiki/touchable') < Time.now - RefreshInterval ||
                   @env['HTTP_CACHE_CONTROL'] =~ /max-age *= *0/
  end
  
  def transcode file
    text = presyntaxify(File.read(file)) rescue ''
    fancify case File.extname(file)
    when '.textile'
      RedCloth.new(text).to_html
    when '.md'
      RDiscount.new(text).to_html
    else
      if File.exists?(file)
        "<p>Error: Do not know how to parse #{format} files. Here it is raw:</p><blockquote><pre>#{text}</pre></blockquote>"
      else
        Wiki::Views.send(:article_not_found, File.basename(file))
      end
    end
  end
  
  # syntax highlighty dance!
  def presyntaxify text, ext = '.md'
    text.gsub(/^ruby do\n(.+?)\n^end/m) {
      (ext == '.textile' && "<notextile>\n" || '').to_s + "<blockquote>\n" + 
        Syntax::Convertors::HTML.for_syntax('ruby').convert($1.gsub(/(^|\n)  /, '\1')) + 
      "\n</blockquote>\n" + (ext == '.textile' && "</notextile>\n" || '').to_s
    }
  end
  
  # put in those fancy headings and stuff
  def fancify html
    html.gsub(/<h([0-9])([^>]*?>.*?<\/h\1>)/i) { |match|
      num = $1; remainder = $2
      also = " id=\"#{remainder[1...remainder.index('<')].gsub(/[^a-z0-9.]+/i, '-')}\"" if remainder[0..0] == '>'
      "<h#{num} class=fill#{remainder}\n<h#{num} class=outline#{also}#{remainder}"
    }.gsub(/\[\[([^\]]+?)\]\]/) { |match|
      content = $1.split(/\|/, 2); label = content.first.strip; link = content.last.strip
      '<a href="' + self / '/' + link.gsub(/ /, '-') + '">' + label + '</a>'
    }
  end
  
  [:h1, :h2, :h3].each do |num|
    define_method(num) do |*args, &blk|
      opts = {:id => args.first.to_s.gsub(/[^a-z0-9.]+/i, '-')}.merge((args.last.is_a?(Hash) && args.pop) || {})
      prior_classes = ((opts[:class] || '').split(' ') + ['']).join(' ')
      tag!(num, args.first, opts.merge(:class => "#{prior_classes}fill", :id => ''), &blk)
      tag!(num, args.first, opts.merge(:class => "#{prior_classes}outline"), &blk)
    end
  end
end

require 'markaby'
Markaby::Builder.set(:auto_validation, false)
#Markaby::Builder.set(:indent, 2)

module Wiki::Views
  def layout
    text "<!DOCTYPE html>\n"
    tag!(:html) do
      tag!(:head) do
        meta :charset => 'utf-8'
        link :rel => 'stylesheet', :href => URL('/style.css')
        title do
          text 'Camping, ' unless @title =~ /camping/i
          text @title
        end
        link :rel => 'icon', :href => URL('/badge.gif')
        meta :name => 'viewport', :content => 'width=660'
      end
    
      body do
        tag!(:header, :id => 'top') { h1(@title) }
        div.wrapper! do
          ul.aside.nav! do
            li { a 'Home', :href => URL(Index) }
            li { a('Camping Book', :href => URL(Article, 'The-Camping-Book')) }
            #li { a('Community', :href => URL(Article, 'Community') }
            li { a('Reference', :href => 'http://camping.rubyforge.org/api.html') }
            li { a('Tumblog', :href => 'http://log.whywentcamping.com/') }
          end
          
          div.subwrap! do
            a.edit(:href => @edit) { button "Edit" } if @edit
            self << yield
          end
        end
      end
    end
  end
  
  
  def index
    maybe_update_wiki
    p.notice do
      strong "Latest news: "
      begin
        open(Wiki::BlogAPI).read =~ Wiki::BlogTitleRegexp
        a $1, :href => Wiki::BlogURL
      rescue
        em "Couldn't load the feed. Oh well."
      end
    end
    
    @edit = Wiki::EditURL.gsub('{article}', 'WhyWentCamping-Homepage')
    self << transcode(Dir['camping.wiki/WhyWentCamping-Homepage.*'].first)
  end
  
  # Display a solitary article
  def article
    maybe_update_wiki
    transcode(@article)
  end
  
  # Generates the tumblr theme
  def tumblr_theme
    @title = "{Title}{block:PostTitle} - {PostTitle}{/block:PostTitle}"
    self << File.read("public/tumblrtheme.html")
  end
  
  # Displayed on articles not available
  def article_not_found name
    @status = 404
    @title = name.capitalize
    maybe_update_wiki
    h2 "So Sorry…"
    p do
      text "This article doesn't exist, like, at all. "
      text "Maybe once upon a time, it existed, but right now, not so much. "
      text "Perhaps you should " + a("create it", :href => Wiki::CreateArticleLink.sub('{article}', name)) + "."
    end
  end
end

module Wiki
  def r404 path
    render :article_not_found, path.gsub(/-/, ' ')
  end
end


